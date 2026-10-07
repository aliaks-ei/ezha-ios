import {
  buildModelBody,
  type CatalogFood,
  DEFAULT_MODEL,
  FALLBACK_MODEL,
  type LabelReading,
  libraryFood,
  type MealReading,
  normalizeLabel,
  normalizeMeal,
  shouldEscalate,
} from "./core.ts";
import {
  completedMealItems,
  createHandler,
  readModelStream,
} from "./service.ts";
import foods from "./food-catalog.json" with { type: "json" };

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
    assert((error as Error).message.includes(message));
    return;
  }
  throw new Error("Expected an error");
}
async function rejects(fn: () => Promise<unknown>, message: string) {
  try {
    await fn();
  } catch (error) {
    assert((error as Error).message.includes(message));
    return;
  }
  throw new Error("Expected an error");
}
const label = (
  overrides: Partial<NonNullable<LabelReading["label"]>> = {},
): LabelReading => ({
  status: "ok",
  food_name: "Cereal",
  label: {
    basis: "per_100g",
    calories_unit: "kcal",
    calories: 400,
    protein: 10,
    carbs: 70,
    fat: 10,
    reference_mass_grams: 100,
    notes: "",
    ...overrides,
  },
});
const meal = (
  overrides: Partial<MealReading["items"][number]> = {},
): MealReading => ({
  status: "ok",
  food_name: "Chicken",
  review: null,
  items: [{
    name: "Chicken breast",
    grams: 150,
    portion_basis: "user_weight",
    identification: "clear",
    catalog_id: "usda:171477",
    fallback_per100g: null,
    notes: "",
    ...overrides,
  }],
});
const encoder = new TextEncoder();
function modelResponse(
  value: unknown,
  terminal = "response.completed",
): Response {
  const text = JSON.stringify(value);
  const wire = [
    {
      type: "response.output_text.delta",
      delta: text.slice(0, Math.floor(text.length / 2)),
    },
    {
      type: "response.output_text.delta",
      delta: text.slice(Math.floor(text.length / 2)),
    },
    {
      type: terminal,
      response: {
        status: terminal === "response.completed" ? "completed" : "incomplete",
        id: "response-test",
        usage: { output_tokens: 100 },
      },
    },
  ].map((event) => `data: ${JSON.stringify(event)}\r\n\r\n`).join("");
  return new Response(
    new ReadableStream({
      start(controller) {
        const bytes = encoder.encode(wire);
        // Split within CRLF boundaries and multibyte strings to exercise the actual SSE reader.
        for (let i = 0; i < bytes.length; i += 13) {
          controller.enqueue(bytes.slice(i, i + 13));
        }
        controller.close();
      },
    }),
  );
}
function request(payload: unknown) {
  return new Request("https://test/ai-estimate", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: "Bearer test-token",
    },
    body: JSON.stringify(payload),
  });
}
const env = (extra: Record<string, string> = {}) => (name: string) =>
  ({
    OPENAI_API_KEY: "mock-only",
    SUPABASE_URL: "https://supabase.test",
    SUPABASE_ANON_KEY: "mock-anon",
    ...extra,
  } as Record<string, string>)[name];
const noop = () => {};

Deno.test("labels normalize their printed column once, preserving energy", () => {
  equal(normalizeLabel(label()).totals.calories, 400);
  equal(
    normalizeLabel(
      label({
        basis: "per_serving",
        reference_mass_grams: 30,
        calories: 120,
        protein: 3,
        carbs: 21,
        fat: 3,
      }),
    ).totals,
    normalizeLabel(label()).totals,
  );
  equal(
    normalizeLabel(label({ calories_unit: "kJ", calories: 1673.6 })).totals
      .calories,
    400,
  );
  equal(normalizeLabel(label({ calories: 300 })).totals.calories, 300); // Do not force label energy to 4/4/9.
  equal(normalizeLabel(label()).nutrition_basis, "per_100g");
});
Deno.test("volume and serving labels require printed mass, never inferred density", () => {
  throws(
    () =>
      normalizeLabel(label({ basis: "per_100ml", reference_mass_grams: null })),
    "millilitres",
  );
  throws(
    () =>
      normalizeLabel(
        label({ basis: "per_serving", reference_mass_grams: null }),
      ),
    "serving weight",
  );
  equal(
    normalizeLabel(label({ basis: "per_100ml", reference_mass_grams: 110 }))
      .totals.calories,
    363.64,
  );
});
Deno.test("unreadable, non-food, and malformed numeric values cannot become valid labels", () => {
  throws(
    () =>
      normalizeLabel({ status: "unreadable", food_name: null, label: null }),
    "isn't readable",
  );
  throws(
    () => normalizeLabel({ status: "not_food", food_name: null, label: null }),
    "No nutrition label",
  );
  throws(() => normalizeLabel(label({ protein: NaN })), "invalid nutrition");
  throws(() => normalizeLabel(label({ fat: 110 })), "inconsistent");
});
Deno.test("matched USDA nutrition overrides model guesses and scales to the supplied weight", () => {
  const result = normalizeMeal(
    meal({
      fallback_per100g: { calories: 9999, protein: 0, carbs: 0, fat: 0 },
    }),
    foods as CatalogFood[],
    "text",
  );
  equal(result.totals.calories, 247.5);
  equal(result.totals.protein, 46.53);
  equal(result.items[0].nutrition_source_id, "171477");
  equal(result.review, null);
});
Deno.test("known weights preserve order, quantity guesses remain uncertain, and portions never trigger escalation", () => {
  const result = normalizeMeal(
    meal({ grams: 200, portion_basis: "visual_estimate" }),
    foods as CatalogFood[],
    "text",
    [{ name: "My chicken", grams: 100 }],
  );
  equal(result.items[0].name, "My chicken");
  equal(result.items[0].grams, 100);
  equal(result.review, null);
  const visual = meal({ portion_basis: "visual_estimate" });
  assert(
    normalizeMeal(visual, foods as CatalogFood[], "food_photo").review?.kind ===
      "portion",
  );
  assert(!shouldEscalate(visual));
  assert(shouldEscalate(meal({ identification: "uncertain" })));
});
Deno.test("fallback estimates are marked and impossible portions or reference IDs fail", () => {
  const fallback = meal({
    catalog_id: null,
    fallback_per100g: { calories: 100, protein: 20, carbs: 10, fat: 5 },
  });
  const result = normalizeMeal(fallback, [], "text");
  equal(result.items[0].nutrition_source, "estimated");
  assert(result.items[0].notes.includes("reconciled"));
  throws(
    () => normalizeMeal(meal({ catalog_id: "usda:fake" }), [], "text"),
    "unknown nutrition",
  );
  throws(
    () => normalizeMeal(meal({ grams: 0 }), [], "text"),
    "invalid portion",
  );
  throws(
    () => normalizeMeal({ ...meal(), items: [] }, [], "text"),
    "isn't clear",
  );
});
Deno.test("saved serving foods need a valid gram conversion and missing nutrients are not zero-filled", () => {
  const row = {
    id: "abc",
    name: "Yogurt",
    is_meal: false,
    serving_size: 150,
    serving_unit: "g",
    calories_per_serving: 90,
    protein_per_serving: 10,
    carbs_per_serving: 5,
    fat_per_serving: 3,
  };
  equal(libraryFood(row)?.per100g.calories, 60);
  equal(libraryFood({ ...row, serving_unit: "cup" })?.per100g.calories, 60);
  equal(libraryFood({ ...row, serving_size: null }), null);
  equal(libraryFood({ ...row, protein_per_serving: null }), null);
  equal(libraryFood({ ...row, is_meal: true }), null);
});
Deno.test("Luna and Sol use supported reasoning, strict schemas and explicit high image detail", () => {
  const body = buildModelBody({
    model: DEFAULT_MODEL,
    isLabel: true,
    text: "I ate 50 g",
    imageUrl: "https://image",
    items: [],
    catalog: [],
  });
  equal(body.reasoning.effort, "none");
  equal(body.text.format.type, "json_schema");
  equal(body.text.format.strict, true);
  assert(!("temperature" in body));
  assert(
    JSON.stringify(body).includes(
      "scaling happens in application code exactly once",
    ),
  );
  equal(
    buildModelBody({
      model: FALLBACK_MODEL,
      isLabel: true,
      text: "",
      imageUrl: null,
      items: [],
      catalog: [],
    }).reasoning.effort,
    "low",
  );
  throws(
    () =>
      buildModelBody({
        model: "gpt-4.1-mini",
        isLabel: false,
        text: "",
        imageUrl: null,
        items: [],
        catalog: [],
      }),
    "supports",
  );
});
Deno.test("partial objects, escaped quotes and nested macros produce only complete item previews", () => {
  const reading = meal({
    name: 'Chicken "roasted"',
    notes: "A } brace, [ array and é",
  });
  const json = JSON.stringify(reading);
  equal(completedMealItems(json).length, 1);
  equal(completedMealItems(json.slice(0, json.indexOf('"notes"'))).length, 0);
  equal(completedMealItems(json)[0].name, 'Chicken "roasted"');
});
Deno.test("stream parser requires a completed terminal event, not just valid JSON", async () => {
  const reading = meal();
  equal(
    (await readModelStream(modelResponse(reading).body!, noop)).value,
    reading,
  );
  await rejects(
    () =>
      readModelStream(
        modelResponse(reading, "response.incomplete").body!,
        noop,
      ),
    "incomplete",
  );
  await rejects(
    () =>
      readModelStream(
        new Response(
          `data: ${
            JSON.stringify({
              type: "response.output_text.delta",
              delta: JSON.stringify(reading),
            })
          }\n\n`,
        ).body!,
        noop,
      ),
    "connection ended",
  );
});
Deno.test("HTTP handler ignores legacy model setting and returns grounded itemized results", async () => {
  const bodies: Record<string, unknown>[] = [];
  const telemetry: Record<string, unknown>[] = [];
  const handler = createHandler({
    env: env({ OPENAI_MODEL: "gpt-5-mini" }),
    log: (value) => telemetry.push(value),
    fetcher: ((url, init) => {
      if (String(url).includes("saved_foods")) {
        return Promise.resolve(new Response("[]"));
      }
      bodies.push(JSON.parse(init?.body as string));
      return Promise.resolve(modelResponse(meal()));
    }) as typeof fetch,
  });
  const result = await handler(
    request({ text: "150 g chicken", inputType: "text" }),
  );
  equal(result.status, 200);
  equal((await result.json()).totals.calories, 247.5);
  equal(bodies[0].model, DEFAULT_MODEL);
  assert(telemetry[0].total_ms !== undefined);
});
Deno.test("HTTP label request with an eaten weight returns per100g, never already-scaled nutrition", async () => {
  const handler = createHandler({
    env: env(),
    log: noop,
    fetcher: ((url) =>
      Promise.resolve(
        String(url).includes("/storage/")
          ? new Response(
            '{"signedURL":"/object/sign/food-images/u/p.jpg?token=test"}',
          )
          : modelResponse(label()),
      )) as typeof fetch,
  });
  const response = await handler(
    request({
      text: "I ate 50 g",
      imagePath: "u/p.jpg",
      inputType: "label_photo",
    }),
  );
  const result = await response.json();
  equal(result.totals.calories, 400);
  equal(result.items[0].grams, 100);
  equal(result.nutrition_basis, "per_100g");
});
Deno.test("streaming handler emits provisional items before the validated result", async () => {
  const handler = createHandler({
    env: env(),
    log: noop,
    fetcher: (() => Promise.resolve(modelResponse(meal()))) as typeof fetch,
  });
  const response = await handler(
    request({ text: "150 g chicken", stream: true }),
  );
  const stream = await response.text();
  assert(stream.indexOf("event: item") >= 0);
  assert(stream.indexOf("event: item") < stream.indexOf("event: result"));
});
Deno.test("unclear images use Sol once and reset previews; non-food does not escalate", async () => {
  const seen: string[] = [];
  const handler = createHandler({
    env: env(),
    log: noop,
    fetcher: ((url, init) => {
      if (String(url).includes("saved_foods")) {
        return Promise.resolve(new Response("[]"));
      }
      if (String(url).includes("storage")) {
        return Promise.resolve(
          new Response('{"signedURL":"/object/sign/food-images/u/p.jpg"}'),
        );
      }
      const body = JSON.parse(init?.body as string);
      seen.push(body.model);
      return Promise.resolve(
        modelResponse(
          seen.length === 1 ? meal({ identification: "uncertain" }) : meal(),
        ),
      );
    }) as typeof fetch,
  });
  const response = await handler(
    request({ imagePath: "u/p.jpg", inputType: "food_photo", stream: true }),
  );
  assert((await response.text()).includes("event: reset"));
  equal(seen, [DEFAULT_MODEL, FALLBACK_MODEL]);
  assert(
    !shouldEscalate({
      status: "not_food",
      food_name: null,
      items: [],
      review: null,
    }),
  );
});
Deno.test("abort deadline interrupts a stalled provider request", async () => {
  let aborted = false;
  const handler = createHandler({
    env: (name) =>
      ({ OPENAI_API_KEY: "mock-only", ESTIMATE_TIMEOUT_MS: "20" } as Record<
        string,
        string
      >)[name],
    log: noop,
    fetcher: ((_url, init) =>
      new Promise((_resolve, reject) => {
        init?.signal?.addEventListener("abort", () => {
          aborted = true;
          reject(new DOMException("Aborted", "AbortError"));
        }, { once: true });
      })) as typeof fetch,
  });
  const response = await handler(request({ text: "chicken" }));
  equal(response.status, 502);
  assert(aborted);
  assert((await response.json()).error.includes("timed out"));
});
Deno.test("invalid input and excluded models make no provider call", async () => {
  const handler = createHandler({
    env: env(),
    log: noop,
    fetcher: (() => {
      throw new Error("Unexpected provider call");
    }) as typeof fetch,
  });
  equal((await handler(request({}))).status, 400);
  equal(
    (await handler(request({ text: "chicken", model: "gpt-4.1" }))).status,
    400,
  );
  equal(
    (await handler(request({ items: [{ name: "Chicken", grams: "100" }] })))
      .status,
    400,
  );
});
