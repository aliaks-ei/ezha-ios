/// Meal suggestions: ideas to cook that fit the remaining macros.
/// Pure logic only. `index.ts` handles auth, the model call and HTTP.

export type Macros = {
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
};
export type SuggestionsRequest = {
  remaining: Macros;
  mealType: string;
  maxPrepMinutes: number;
  count: number;
  ingredientNotes: string;
  variationNote: string;
  units: string;
  /// Recent titles the model must not repeat.
  avoidTitles: string[];
  /// The user's local hour, 0–23. Null when unknown or not today.
  localHour: number | null;
};
export type Suggestion = Macros & {
  title: string;
  description: string;
  notes: string;
};
/// One starting point per idea, picked at random so each request explores something new.
export type Inspiration = { cuisine: string; protein: string; format: string };

export const DEFAULT_MODEL = "gpt-5-mini";
export const TEMPERATURE = 0.9;
export const MAX_AVOID_TITLES = 30;
export const MAX_TITLE_LENGTH = 80;

export const CUISINES = [
  "Mediterranean",
  "Mexican",
  "Japanese",
  "Korean",
  "Thai",
  "Vietnamese",
  "Indian",
  "Middle Eastern",
  "Greek",
  "Italian",
  "Chinese",
  "Ukrainian",
  "Georgian",
  "Turkish",
  "Moroccan",
  "Peruvian",
  "Spanish",
  "French",
  "Caribbean",
  "Nordic",
];
export const PROTEINS = [
  "eggs",
  "tofu",
  "tempeh",
  "salmon",
  "tuna",
  "white fish",
  "shrimp",
  "turkey",
  "lean beef",
  "pork tenderloin",
  "chicken thighs",
  "lentils",
  "chickpeas",
  "black beans",
  "cottage cheese",
  "edamame",
  "halloumi",
  "sardines",
];
export const MEAL_FORMATS = [
  "bowl",
  "wrap",
  "soup",
  "warm salad",
  "open sandwich",
  "stir-fry",
  "omelette or frittata",
  "noodles or pasta",
  "tray bake",
  "skewers",
  "stuffed vegetables",
  "curry or stew",
  "tacos",
  "plate with sides",
];
export const SNACK_FORMATS = [
  "dip with vegetables",
  "smoothie",
  "toast or crackers with a topping",
  "energy bites",
  "savory muffin",
  "roasted snack mix",
  "mini skewers",
  "lettuce cups",
  "yogurt or skyr bowl",
  "rice cakes with a topping",
];

const text = (value: unknown, max = 500) =>
  typeof value === "string" ? value.trim().slice(0, max) : "";

export function parsePositiveInt(value: unknown): number | null {
  const numeric = typeof value === "string" ? Number(value) : value;
  if (typeof numeric !== "number" || !Number.isFinite(numeric)) return null;
  const rounded = Math.round(numeric);
  return rounded > 0 ? rounded : null;
}

export function clampCount(value: unknown): number {
  const numeric = parsePositiveInt(value);
  if (!numeric) return 3;
  return Math.min(Math.max(numeric, 1), 5);
}

/// Unique, trimmed titles, newest first as sent. Ignores anything that is not a string.
export function parseAvoidTitles(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  const seen = new Set<string>();
  const titles: string[] = [];
  for (const entry of value) {
    const title = text(entry, MAX_TITLE_LENGTH);
    const key = title.toLowerCase();
    if (!title || seen.has(key)) continue;
    seen.add(key);
    titles.push(title);
    if (titles.length === MAX_AVOID_TITLES) break;
  }
  return titles;
}

export function parseLocalHour(value: unknown): number | null {
  return typeof value === "number" && Number.isInteger(value) && value >= 0 &&
      value <= 23
    ? value
    : null;
}

/// Validates the request body. Returns a user-facing error for invalid input.
/// `avoid_titles` and `local_hour` are optional, so older app builds keep working.
export function parseRequest(
  payload: Record<string, unknown>,
): { request: SuggestionsRequest } | { error: string } {
  const raw = payload.remaining as Record<string, unknown> | null | undefined;
  if (!raw || typeof raw !== "object") {
    return { error: "Missing required field: remaining" };
  }
  const values = [raw.calories, raw.protein, raw.carbs, raw.fat].map(Number);
  if (values.some((item) => Number.isNaN(item))) {
    return { error: "Invalid remaining macros." };
  }
  const [calories, protein, carbs, fat] = values;
  const mealType = text(payload.meal_type);
  if (!mealType) return { error: "Missing required field: meal_type" };
  const maxPrepMinutes = parsePositiveInt(payload.max_prep_minutes);
  if (!maxPrepMinutes) {
    return { error: "Missing required field: max_prep_minutes" };
  }
  return {
    request: {
      remaining: { calories, protein, carbs, fat },
      mealType,
      maxPrepMinutes,
      count: clampCount(payload.count ?? 3),
      ingredientNotes: text(payload.ingredient_notes),
      variationNote: text(payload.variation_note),
      units: text(payload.units) || "grams",
      avoidTitles: parseAvoidTitles(payload.avoid_titles),
      localHour: parseLocalHour(payload.local_hour),
    },
  };
}

/// Picks `count` items without repeats.
function pick<T>(items: T[], count: number, random: () => number): T[] {
  const pool = [...items];
  const picked: T[] = [];
  while (picked.length < count && pool.length > 0) {
    const index = Math.min(Math.floor(random() * pool.length), pool.length - 1);
    picked.push(pool.splice(index, 1)[0]);
  }
  return picked;
}

/// A different cuisine, protein, and format for each idea.
export function pickInspirations(
  count: number,
  mealType: string,
  random: () => number = Math.random,
): Inspiration[] {
  const formats = mealType.toLowerCase() === "snack"
    ? SNACK_FORMATS
    : MEAL_FORMATS;
  const cuisines = pick(CUISINES, count, random);
  const proteins = pick(PROTEINS, count, random);
  const picked = pick(formats, count, random);
  return cuisines.map((cuisine, index) => ({
    cuisine,
    protein: proteins[index],
    format: picked[index],
  }));
}

/// "dinner (19:00)": what the local hour is usually eaten as.
export function timeOfDay(hour: number, mealType: string): string {
  const time = `${String(hour).padStart(2, "0")}:00`;
  const snack = mealType.toLowerCase() === "snack";
  if (hour >= 5 && hour <= 10) {
    return `${snack ? "a morning snack" : "breakfast"} (${time})`;
  }
  if (hour >= 11 && hour <= 15) {
    return `${snack ? "a midday snack" : "lunch"} (${time})`;
  }
  if (hour >= 16 && hour <= 21) {
    return `${snack ? "an afternoon or evening snack" : "dinner"} (${time})`;
  }
  return `a light late-night ${snack ? "snack" : "meal"} (${time})`;
}

export function buildPrompt(
  request: SuggestionsRequest,
  inspirations: Inspiration[],
): string {
  const { remaining, count } = request;
  const lines = [
    "Task: Suggest meal ideas based on remaining macros today.",
    `Return exactly ${count} suggestions for a ${request.mealType.toLowerCase()}.`,
    "Each suggestion should be a short meal idea or a small food set (no full recipes).",
    `Max prep time: ${request.maxPrepMinutes} minutes.`,
    `Units: calories in kcal, macros in ${request.units}.`,
    "If a suggestion exceeds any remaining macro, explicitly mention it in notes.",
    "Return JSON with fields in this exact order: suggestions.",
    "Each suggestion object must include fields in this exact order:",
    "title, description, calories, protein, carbs, fat, notes.",
    "notes can be an empty string.",
    `Remaining macros: calories ${remaining.calories}, protein ${remaining.protein}, carbs ${remaining.carbs}, fat ${remaining.fat}.`,
    `Ingredient notes: ${request.ingredientNotes || "[none]"}`,
    `User wants changes: ${request.variationNote || "[none]"}`,
    "Variety: make the ideas clearly different from each other, with a different main protein, cuisine, and format for each.",
    "Avoid the usual defaults, such as a plain chicken salad bowl or Greek yogurt with berries, unless the user asks for them.",
  ];
  if (inspirations.length > 0) {
    lines.push(
      "Starting points, one per idea. Adapt them freely, and swap any that clash with the ingredient notes, prep time, or macros:",
      ...inspirations.map((item, index) =>
        `${index + 1}. ${item.cuisine}, ${item.protein}, ${item.format}`
      ),
    );
  }
  if (request.localHour !== null) {
    lines.push(
      `Time of day: the user will eat this as ${
        timeOfDay(request.localHour, request.mealType)
      }. Suggest food that suits it.`,
    );
  }
  if (request.avoidTitles.length > 0) {
    lines.push(
      `Recently suggested. Do not repeat these or suggest close variations: ${
        request.avoidTitles.join("; ")
      }`,
    );
  }
  return lines.join("\n");
}

export function buildModelBody(options: {
  model: string;
  prompt: string;
}): Record<string, unknown> {
  return {
    model: options.model,
    temperature: TEMPERATURE,
    text: { format: { type: "json_object" } },
    instructions:
      "You are a meal suggestion assistant. Return only valid JSON. " +
      "All numeric fields are numbers without units. Calories are kcal. " +
      "Protein, carbs, fat are grams.",
    input: [
      {
        role: "user",
        content: [{ type: "input_text", text: options.prompt }],
      },
    ],
  };
}

export function normalizeSuggestions(
  result: Record<string, unknown>,
  remaining: Macros,
  count: number,
): { suggestions: Suggestion[] } | { error: string } {
  if (!Array.isArray(result.suggestions) || result.suggestions.length === 0) {
    return { error: "Missing required field: suggestions" };
  }
  const suggestions: Suggestion[] = [];
  for (const raw of result.suggestions.slice(0, count)) {
    if (!raw || typeof raw !== "object") {
      return { error: "Invalid suggestion payload." };
    }
    const entry = raw as Record<string, unknown>;
    const title = text(entry.title, 10_000);
    const description = text(entry.description, 10_000);
    const calories = Number(entry.calories);
    const protein = Number(entry.protein);
    const carbs = Number(entry.carbs);
    const fat = Number(entry.fat);
    if (!title || !description) {
      return { error: "Invalid suggestion payload." };
    }
    if ([calories, protein, carbs, fat].some((value) => Number.isNaN(value))) {
      return { error: "Invalid suggestion payload." };
    }
    const macros = { calories, protein, carbs, fat };
    suggestions.push({
      title,
      description,
      ...macros,
      notes: appendExceedNotes(text(entry.notes, 10_000), macros, remaining),
    });
  }
  return { suggestions };
}

export function appendExceedNotes(
  notes: string,
  macros: Macros,
  remaining: Macros,
): string {
  const parts: string[] = [];
  if (macros.calories > remaining.calories) {
    parts.push(
      `calories by ${Math.round(macros.calories - remaining.calories)} kcal`,
    );
  }
  if (macros.protein > remaining.protein) {
    parts.push(
      `protein by ${Math.round(macros.protein - remaining.protein)} g`,
    );
  }
  if (macros.carbs > remaining.carbs) {
    parts.push(`carbs by ${Math.round(macros.carbs - remaining.carbs)} g`);
  }
  if (macros.fat > remaining.fat) {
    parts.push(`fat by ${Math.round(macros.fat - remaining.fat)} g`);
  }
  if (parts.length === 0) return notes;
  const warning = `Exceeds ${parts.join(", ")}.`;
  if (!notes) return warning;
  if (notes.toLowerCase().includes("exceeds")) return notes;
  return `${notes} ${warning}`.trim();
}

type OutputPart = { type?: unknown; text?: unknown; refusal?: unknown };
function outputParts(data: unknown): OutputPart[] {
  const output = (data as { output?: unknown } | null)?.output;
  if (!Array.isArray(output)) return [];
  return output.flatMap((item) => {
    const content = (item as { content?: unknown } | null)?.content;
    return Array.isArray(content)
      ? content.filter((part) => part && typeof part === "object")
      : [];
  });
}

export function extractOutputText(data: unknown): string {
  const outputText = (data as { output_text?: unknown } | null)?.output_text;
  if (typeof outputText === "string") return outputText;
  return outputParts(data)
    .filter((part) =>
      part.type === "output_text" && typeof part.text === "string"
    )
    .map((part) => part.text as string)
    .join("");
}

export function extractRefusal(data: unknown): string | null {
  const part = outputParts(data).find((part) => part.type === "refusal");
  if (!part) return null;
  return typeof part.refusal === "string" && part.refusal.trim()
    ? part.refusal
    : "OpenAI refused to answer.";
}
