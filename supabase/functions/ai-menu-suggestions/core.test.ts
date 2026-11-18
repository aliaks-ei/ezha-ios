import {
  buildModelBody,
  buildPrompt,
  COUNT,
  DEFAULT_MODEL,
  FALLBACK_MODEL,
  MAX_IMAGES,
  type MenuItem,
  type MenuReading,
  type MenuRequest,
  NO_DISHES_MESSAGE,
  normalizeMenu,
  NOT_MENU_MESSAGE,
  parseRequest,
  shouldEscalate,
  UNREADABLE_MESSAGE,
} from "./core.ts";
import { createHandler, parseModelResponse } from "./service.ts";

function assert(value: unknown, message = "Assertion failed"): asserts value {
  if (!value) throw new Error(message);
}
function equal(a: unknown, b: unknown) {
  assert(
    JSON.stringify(a) === JSON.stringify(b),
    `${JSON.stringify(a)} != ${JSON.stringify(b)}`,
  );
}
function throws(fn: () => unknown, message: string) {
  try {
    fn();
  } catch (error) {
    assert(
      (error as Error).message.includes(message),
      `${(error as Error).message} does not include ${message}`,
    );
    return;
  }
  throw new Error("Expected an error");
}

const jpeg = "/9j/4AAQSkZJRgABAQ==";
const remaining = { calories: 650, protein: 40, carbs: 70, fat: 20 };
const body = (overrides: Record<string, unknown> = {}) => ({
  remaining,
  meal_type: "Meal",
  preferences: "no dairy",
  images: [jpeg],
  ...overrides,
});
const item = (overrides: Partial<MenuItem> = {}): MenuItem => ({
  title: "Grilled chicken salad",
  menu_section: "Salads",
  description: "Chicken breast over greens, about 350 g.",
  calories: 480,
  protein: 42,
  carbs: 18,
  fat: 24,
  order_tip: "Ask for the dressing on the side.",
  ...overrides,
});
const reading = (
  suggestions: MenuItem[] = [item()],
  status: MenuReading["status"] = "ok",
): MenuReading => ({ status, suggestions });
const request = (overrides: Partial<MenuRequest> = {}): MenuRequest => ({
  remaining,
  mealType: "Meal",
  preferences: "",
  variationNote: "",
  images: [jpeg],
  ...overrides,
});

Deno.test("parseRequest accepts a valid body and trims text", () => {
  const parsed = parseRequest(
    body({ preferences: "  no dairy  ", variation_note: " Different " }),
  );
  assert("request" in parsed);
  equal(parsed.request.remaining, remaining);
  equal(parsed.request.mealType, "Meal");
  equal(parsed.request.preferences, "no dairy");
  equal(parsed.request.variationNote, "Different");
  equal(parsed.request.images, [jpeg]);
});

Deno.test("parseRequest defaults the meal type and keeps negative remaining", () => {
  const parsed = parseRequest(
    body({
      meal_type: undefined,
      remaining: { ...remaining, calories: -120 },
    }),
  );
  assert("request" in parsed);
  equal(parsed.request.mealType, "Meal");
  equal(parsed.request.remaining.calories, -120);
});

Deno.test("parseRequest rejects missing or invalid fields", () => {
  const error = (payload: Record<string, unknown>) => {
    const parsed = parseRequest(payload);
    assert("error" in parsed, "Expected an error");
    return parsed.error;
  };
  equal(
    error(body({ remaining: undefined })),
    "Missing required field: remaining",
  );
  equal(
    error(body({ remaining: { ...remaining, fat: "x" } })),
    "Invalid remaining macros.",
  );
  equal(error(body({ meal_type: "Brunch" })), "Invalid meal type.");
  equal(error(body({ images: [] })), "Add at least one photo of the menu.");
  equal(
    error(body({ images: undefined })),
    "Add at least one photo of the menu.",
  );
  equal(
    error(body({ images: Array(MAX_IMAGES + 1).fill(jpeg) })),
    `Add up to ${MAX_IMAGES} menu photos.`,
  );
  const unreadable = "A menu photo could not be read. Add it again.";
  equal(error(body({ images: ["iVBORw0KGgo="] })), unreadable); // PNG
  equal(error(body({ images: ["/9j/not base64!"] })), unreadable);
  equal(error(body({ images: [42] })), unreadable);
  equal(
    error(body({ images: ["/9j/" + "A".repeat(4_000_000)] })),
    unreadable,
  );
});

Deno.test("prompt carries remaining macros, meal type and user text as data", () => {
  const prompt = buildPrompt(
    request({
      remaining: { calories: 412.6, protein: 30.2, carbs: 50, fat: 9.5 },
      mealType: "Snack",
      preferences: 'vegan "please"',
      images: [jpeg, jpeg],
    }),
  );
  assert(prompt.includes("2 page(s)"));
  assert(prompt.includes(`exactly ${COUNT} different dishes`));
  assert(prompt.includes("for a snack"));
  assert(prompt.includes("starters, sides"));
  assert(prompt.includes("413 kcal, protein 30 g, carbs 50 g, fat 10 g"));
  assert(prompt.includes('User preferences: "vegan \\"please\\""'));
  assert(prompt.includes('User wants changes: "[none]"'));
  assert(prompt.includes("Never invent a dish."));
});

Deno.test("model body sends each page as a high-detail data URL", () => {
  const model = buildModelBody({
    model: DEFAULT_MODEL,
    request: request({ images: [jpeg, jpeg] }),
  });
  equal(model.model, DEFAULT_MODEL);
  equal(model.reasoning, { effort: "low" });
  equal(model.store, false);
  equal(model.text.format.name, "menu_suggestions_v1");
  equal(model.text.format.strict, true);
  const content = model.input[0].content;
  equal(content.length, 5);
  equal(content[1], { type: "input_text", text: "Menu page 1:" });
  equal(content[2], {
    type: "input_image",
    image_url: `data:image/jpeg;base64,${jpeg}`,
    detail: "high",
  });
  throws(
    () => buildModelBody({ model: "gpt-4.1", request: request() }),
    "support gpt-6-luna",
  );
});

Deno.test("normalizeMenu keeps valid items, drops duplicates and caps the count", () => {
  const items = [
    item({ title: "  Soup  ", menu_section: " ", order_tip: "" }),
    item({ title: "soup" }),
    item({ title: "Bad", calories: -1 }),
    item({ title: "", calories: 100 }),
    item({ title: "Huge", calories: 9000 }),
    ...Array.from({ length: 6 }, (_, i) => item({ title: `Dish ${i}` })),
  ];
  const { suggestions } = normalizeMenu(reading(items));
  equal(suggestions.length, COUNT);
  equal(suggestions[0].title, "Soup");
  equal(suggestions[0].menu_section, null);
  equal(suggestions[0].order_tip, null);
  equal(suggestions.map((s) => s.title), [
    "Soup",
    "Dish 0",
    "Dish 1",
    "Dish 2",
    "Dish 3",
  ]);
});

Deno.test("normalizeMenu turns statuses into clear errors", () => {
  throws(() => normalizeMenu(reading([], "not_menu")), NOT_MENU_MESSAGE);
  throws(() => normalizeMenu(reading([], "unreadable")), UNREADABLE_MESSAGE);
  throws(
    () => normalizeMenu(reading([item({ calories: Number.NaN })])),
    NO_DISHES_MESSAGE,
  );
});

Deno.test("only unreadable or empty readings escalate", () => {
  equal(shouldEscalate(reading()), false);
  equal(shouldEscalate(reading([], "not_menu")), false);
  equal(shouldEscalate(reading([], "unreadable")), true);
  equal(shouldEscalate(reading([])), true);
});

Deno.test("parseModelResponse reads output text and rejects refusals", () => {
  const text = JSON.stringify(reading());
  equal(
    parseModelResponse({
      status: "completed",
      output: [{ content: [{ type: "output_text", text }] }],
    }),
    reading(),
  );
  throws(
    () =>
      parseModelResponse({
        status: "completed",
        output: [{ content: [{ type: "refusal", refusal: "no" }] }],
      }),
    "couldn't be analyzed",
  );
  throws(
    () => parseModelResponse({ status: "incomplete" }),
    "Try fewer pages",
  );
  throws(
    () => parseModelResponse({ status: "completed", output_text: "{" }),
    "invalid response",
  );
});

const env = (values: Record<string, string> = {}) => (name: string) =>
  ({
    OPENAI_API_KEY: "key",
    SUPABASE_URL: "https://project.supabase.co",
    SUPABASE_ANON_KEY: "anon",
    ...values,
  })[name];
const post = (payload: unknown, token = "token") =>
  new Request("https://fn/ai-menu-suggestions", {
    method: "POST",
    headers: token ? { Authorization: `Bearer ${token}` } : {},
    body: JSON.stringify(payload),
  });
const modelReply = (value: MenuReading) =>
  Response.json({
    id: "resp_1",
    status: "completed",
    output: [{
      content: [{ type: "output_text", text: JSON.stringify(value) }],
    }],
  });

Deno.test("handler verifies the user, calls the model once and returns suggestions", async () => {
  const calls: { url: string; body?: Record<string, unknown> }[] = [];
  const fetcher = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input);
    calls.push({
      url,
      body: init?.body ? JSON.parse(String(init.body)) : undefined,
    });
    if (url.endsWith("/auth/v1/user")) return Response.json({ id: "u" });
    return modelReply(reading());
  }) as typeof fetch;
  const logs: Record<string, unknown>[] = [];
  const response = await createHandler({
    env: env(),
    fetcher,
    log: (event) => logs.push(event),
  })(post(body()));
  equal(response.status, 200);
  const result = await response.json();
  equal(result.suggestions[0].title, "Grilled chicken salad");
  equal(result.suggestions[0].order_tip, "Ask for the dressing on the side.");
  equal(calls.length, 2);
  equal(calls[1].body?.model, DEFAULT_MODEL);
  equal(logs[0].outcome, "success");
  // Photos are never logged.
  assert(!JSON.stringify(logs).includes(jpeg));
});

Deno.test("handler retries an unreadable menu once with the fallback model", async () => {
  const models: unknown[] = [];
  const fetcher = (async (input: RequestInfo | URL, init?: RequestInit) => {
    if (String(input).endsWith("/auth/v1/user")) return Response.json({});
    const model = JSON.parse(String(init?.body)).model;
    models.push(model);
    return modelReply(
      model === DEFAULT_MODEL ? reading([], "unreadable") : reading(),
    );
  }) as typeof fetch;
  const response = await createHandler({ env: env(), fetcher, log: () => {} })(
    post(body()),
  );
  equal(response.status, 200);
  equal(models, [DEFAULT_MODEL, FALLBACK_MODEL]);
});

Deno.test("handler does not retry when the photos are not a menu", async () => {
  let modelCalls = 0;
  const fetcher = (async (input: RequestInfo | URL) => {
    if (String(input).endsWith("/auth/v1/user")) return Response.json({});
    modelCalls++;
    return modelReply(reading([], "not_menu"));
  }) as typeof fetch;
  const response = await createHandler({ env: env(), fetcher, log: () => {} })(
    post(body()),
  );
  equal(response.status, 502);
  equal((await response.json()).error, NOT_MENU_MESSAGE);
  equal(modelCalls, 1);
});

Deno.test("handler rejects bad input and missing sessions before calling the model", async () => {
  let called = false;
  const fetcher = (async (input: RequestInfo | URL) => {
    called = true;
    if (String(input).endsWith("/auth/v1/user")) {
      return new Response("", { status: 401 });
    }
    throw new Error("The model must not be called");
  }) as typeof fetch;
  const handler = createHandler({ env: env(), fetcher, log: () => {} });

  const invalid = await handler(post(body({ images: [] })));
  equal(invalid.status, 400);
  equal(called, false);

  const noToken = await handler(post(body(), ""));
  equal(noToken.status, 401);
  equal(called, false);

  const expired = await handler(post(body()));
  equal(expired.status, 401);
  equal((await expired.json()).error, "Your session expired. Sign in again.");

  const unconfigured = await createHandler({
    env: env({ OPENAI_API_KEY: "" }),
    fetcher,
    log: () => {},
  })(post(body()));
  equal(unconfigured.status, 500);
});
