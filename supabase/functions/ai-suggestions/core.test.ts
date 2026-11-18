import {
  buildModelBody,
  buildPrompt,
  CUISINES,
  MAX_AVOID_TITLES,
  normalizeSuggestions,
  parseRequest,
  pickInspirations,
  SNACK_FORMATS,
  type SuggestionsRequest,
  TEMPERATURE,
  timeOfDay,
} from "./core.ts";

function assert(value: unknown, message = "Assertion failed"): asserts value {
  if (!value) throw new Error(message);
}
function equal(a: unknown, b: unknown) {
  assert(
    JSON.stringify(a) === JSON.stringify(b),
    `${JSON.stringify(a)} != ${JSON.stringify(b)}`,
  );
}

const base = {
  remaining: { calories: 600, protein: 40, carbs: 60, fat: 20 },
  meal_type: "Meal",
  max_prep_minutes: 20,
};

function request(payload: Record<string, unknown> = {}): SuggestionsRequest {
  const parsed = parseRequest({ ...base, ...payload });
  if ("error" in parsed) throw new Error(parsed.error);
  return parsed.request;
}

/// Steps through a fixed sequence, so picks are repeatable.
function sequence(...values: number[]) {
  let index = 0;
  return () => values[index++ % values.length];
}

Deno.test("older requests without the new fields still parse", () => {
  const parsed = request();
  equal(parsed.avoidTitles, []);
  equal(parsed.localHour, null);
  equal(parsed.count, 3);
  equal(parsed.units, "grams");
});

Deno.test("rejects missing required fields", () => {
  equal(parseRequest({ ...base, remaining: null }), {
    error: "Missing required field: remaining",
  });
  equal(parseRequest({ ...base, meal_type: " " }), {
    error: "Missing required field: meal_type",
  });
  equal(parseRequest({ ...base, max_prep_minutes: 0 }), {
    error: "Missing required field: max_prep_minutes",
  });
});

Deno.test("cleans avoid titles", () => {
  const titles = Array.from({ length: 40 }, (_, index) => `Meal ${index}`);
  equal(
    request({ avoid_titles: [" Chicken bowl ", "chicken bowl", 7, "", "Soup"] })
      .avoidTitles,
    ["Chicken bowl", "Soup"],
  );
  equal(
    request({ avoid_titles: titles }).avoidTitles.length,
    MAX_AVOID_TITLES,
  );
  equal(request({ avoid_titles: "Chicken bowl" }).avoidTitles, []);
});

Deno.test("accepts only whole hours from 0 to 23", () => {
  equal(request({ local_hour: 0 }).localHour, 0);
  equal(request({ local_hour: 23 }).localHour, 23);
  equal(request({ local_hour: 24 }).localHour, null);
  equal(request({ local_hour: 7.5 }).localHour, null);
  equal(request({ local_hour: "8" }).localHour, null);
});

Deno.test("picks a different cuisine, protein, and format per idea", () => {
  for (let run = 0; run < 50; run++) {
    const picks = pickInspirations(5, "Meal");
    equal(picks.length, 5);
    for (const key of ["cuisine", "protein", "format"] as const) {
      equal(new Set(picks.map((item) => item[key])).size, 5);
    }
  }
  const snack = pickInspirations(3, "Snack", sequence(0));
  assert(snack.every((item) => SNACK_FORMATS.includes(item.format)));
  equal(
    pickInspirations(2, "Meal", sequence(0.999)).map((item) => item.cuisine),
    [CUISINES[CUISINES.length - 1], CUISINES[CUISINES.length - 2]],
  );
});

Deno.test("maps the hour to a meal", () => {
  equal(timeOfDay(8, "Meal"), "breakfast (08:00)");
  equal(timeOfDay(13, "Meal"), "lunch (13:00)");
  equal(timeOfDay(19, "Meal"), "dinner (19:00)");
  equal(timeOfDay(23, "Meal"), "a light late-night meal (23:00)");
  equal(timeOfDay(16, "Snack"), "an afternoon or evening snack (16:00)");
});

Deno.test("prompt includes variety, starting points, time, and avoid list", () => {
  const prompt = buildPrompt(
    request({
      local_hour: 19,
      avoid_titles: ["Chicken salad bowl", "Greek yogurt and berries"],
      variation_note: "Different options",
    }),
    [
      { cuisine: "Korean", protein: "tofu", format: "bowl" },
      { cuisine: "Peruvian", protein: "white fish", format: "tacos" },
    ],
  );
  assert(prompt.includes("Return exactly 3 suggestions for a meal."));
  assert(prompt.includes("different main protein, cuisine, and format"));
  assert(
    prompt.includes("1. Korean, tofu, bowl\n2. Peruvian, white fish, tacos"),
  );
  assert(prompt.includes("eat this as dinner (19:00)"));
  assert(
    prompt.includes(
      "Do not repeat these or suggest close variations: Chicken salad bowl; Greek yogurt and berries",
    ),
  );
  assert(prompt.includes("User wants changes: Different options"));
});

Deno.test("prompt leaves out time and avoid list when not sent", () => {
  const prompt = buildPrompt(request(), []);
  assert(!prompt.includes("Time of day"));
  assert(!prompt.includes("Recently suggested"));
  assert(!prompt.includes("Starting points"));
});

Deno.test("model body uses the higher temperature", () => {
  const body = buildModelBody({ model: "gpt-5-mini", prompt: "Hi" });
  equal(body.temperature, TEMPERATURE);
  equal(body.model, "gpt-5-mini");
});

Deno.test("normalizes suggestions and adds exceed notes", () => {
  const result = normalizeSuggestions(
    {
      suggestions: [
        {
          title: " Tofu bowl ",
          description: "Rice, tofu, kimchi",
          calories: 700,
          protein: "30",
          carbs: 60,
          fat: 20,
          notes: "",
        },
      ],
    },
    base.remaining,
    3,
  );
  equal(result, {
    suggestions: [
      {
        title: "Tofu bowl",
        description: "Rice, tofu, kimchi",
        calories: 700,
        protein: 30,
        carbs: 60,
        fat: 20,
        notes: "Exceeds calories by 100 kcal.",
      },
    ],
  });
  equal(normalizeSuggestions({ suggestions: [] }, base.remaining, 3), {
    error: "Missing required field: suggestions",
  });
});
