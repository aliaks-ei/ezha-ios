import { serve } from "https://deno.land/std@0.203.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// --- Fix 1/2 tuning knobs ---
// How far the model's stated calories may drift from its own macros (Atwater)
// before we reconcile. 0.2 = 20%.
const CAL_MISMATCH_TOLERANCE = 0.2;
// Physical ceiling for energy density. Pure fat is 9 kcal/g; nothing edible
// exceeds this. Values above it mean the portion or macros are wrong.
const MAX_KCAL_PER_GRAM = 9.2;

const INSTRUCTIONS =
  "You are a nutrition estimation assistant. Return only valid JSON. " +
  "All numeric fields are numbers without units. Calories must be in kcal; " +
  "if the label shows kJ, first look for kcal; if kcal is absent, convert kJ to kcal (kJ / 4.184). " +
  "Protein, carbs, and fat must be grams. " +
  "Keep each item internally consistent: calories should be close to 4*protein + 4*carbs + 9*fat. " +
  "If the input is unclear, estimate a typical portion and explain assumptions in notes.";

serve(async (req) => {
  console.log("ai-estimate hit", new Date().toISOString());
  console.log("method", req.method);
  console.log("auth header present", !!req.headers.get("authorization"));
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  let payload: RequestPayload;
  try {
    payload = await req.json();
  } catch {
    return jsonError("Invalid JSON payload.", 400);
  }

  const text = typeof payload.text === "string" ? payload.text.trim() : "";
  const imagePath = typeof payload.imagePath === "string" ? payload.imagePath.trim() : "";
  const { items, error: itemsError } = parseItems(payload.items);
  if (itemsError) {
    return jsonError(itemsError, 400);
  }
  if (!text && !imagePath && items.length === 0) {
    return jsonError("Missing required field: text, items, or imagePath", 400);
  }

  const openAiKey = Deno.env.get("OPENAI_API_KEY");
  if (!openAiKey) {
    return jsonError("Missing required field: OPENAI_API_KEY", 500);
  }

  const verifyJwt = (Deno.env.get("VERIFY_JWT") ?? "false").toLowerCase() === "true";
  let accessToken = "";
  const authHeader = req.headers.get("authorization") ?? "";
  const tokenMatch = authHeader.match(/^Bearer\s+(.+)$/i);
  if (tokenMatch) {
    accessToken = tokenMatch[1];
  }
  if (verifyJwt) {
    if (!tokenMatch) {
      return jsonError("Missing required field: Authorization", 401);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
    if (!supabaseUrl || !supabaseAnonKey) {
      return jsonError("Missing required field: SUPABASE_URL or SUPABASE_ANON_KEY", 500);
    }
    const authResponse = await fetch(`${supabaseUrl}/auth/v1/user`, {
      method: "GET",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        apikey: supabaseAnonKey,
      },
    });

    if (!authResponse.ok) {
      return jsonError("Invalid JWT", 401);
    }
  }

  const model = payload.model ??
    Deno.env.get("OPENAI_MODEL") ??
    "gpt-5-mini";
  const baseUrl = Deno.env.get("OPENAI_BASE_URL") ?? "https://api.openai.com/v1";
  const isLabelInput = (payload.inputType ?? "text") === "label_photo";

  const parsedWeight = items.length > 0 ? null : (text ? extractWeight(text) : null);
  const prompt = buildPrompt(text, items, parsedWeight, payload.inputType ?? "text", imagePath);
  let imageUrl: string | null = null;
  if (imagePath) {
    if (!accessToken) {
      return jsonError("Missing required field: Authorization", 401);
    }
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
    if (!supabaseUrl || !supabaseAnonKey) {
      return jsonError("Missing required field: SUPABASE_URL or SUPABASE_ANON_KEY", 500);
    }
    try {
      imageUrl = await createSignedImageUrl({
        supabaseUrl,
        supabaseAnonKey,
        accessToken,
        imagePath,
        bucket: Deno.env.get("FOOD_IMAGES_BUCKET") ?? "food-images",
      });
    } catch {
      console.log("signed url error for imagePath:", imagePath);
      return jsonError("Unable to create signed URL for image.", 400);
    }
  }

  if (payload.stream) {
    return await streamEstimate({
      baseUrl,
      model,
      isLabelInput,
      prompt,
      imageUrl,
      hasItems: items.length > 0,
      openAiKey,
    });
  }

  console.log("calling OpenAI", { model, baseUrl, hasImage: Boolean(imageUrl) });
  const response = await fetch(`${baseUrl}/responses`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${openAiKey}`,
    },
    body: JSON.stringify(buildResponsesBody({ model, prompt, imageUrl, stream: false })),
  });

  console.log("OpenAI response status", response.status);
  if (!response.ok) {
    const errorText = await response.text();
    return jsonError(
      `OpenAI request failed with status ${response.status}: ${errorText || "unknown error"}.`,
      502,
    );
  }

  let content = "";
  try {
    const data = await response.json();
    if (data?.status && data.status !== "completed") {
      return jsonError(`OpenAI response status: ${data.status}`, 502);
    }
    const refusal = extractRefusal(data);
    if (refusal) {
      return jsonError(refusal, 502);
    }
    content = extractOutputText(data);
  } catch {
    return jsonError("Invalid OpenAI response.", 502);
  }

  let result: AIResult;
  try {
    result = JSON.parse(content);
  } catch {
    return jsonError("OpenAI returned invalid JSON.", 502);
  }

  const normalizedResult = normalizeResult(result, {
    requireItems: items.length > 0,
    isLabel: isLabelInput,
  });
  if ("error" in normalizedResult) {
    return jsonError(normalizedResult.error, 502);
  }

  return new Response(JSON.stringify(normalizedResult.normalized), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
});

type RequestPayload = {
  text?: string;
  items?: ItemInput[];
  imagePath?: string;
  inputType?: string;
  model?: string;
  stream?: boolean;
};

type ItemInput = {
  name: string;
  grams: number;
};

type AIResult = {
  items?: AIItemResult[];
  totals?: MacroTotals;
  calories?: number;
  protein?: number;
  carbs?: number;
  fat?: number;
  confidence?: number;
  source?: string;
  food_name?: string;
  notes?: string;
  error?: string;
};

type NormalizedResult = {
  totals: MacroTotals;
  items?: AIItemResult[];
  confidence?: number;
  source: string;
  food_name?: string;
  notes: string;
};

type ParsedWeight = {
  value: number;
  unit: string;
  grams?: number;
};

type MacroTotals = {
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
};

type AIItemResult = {
  name: string;
  grams: number;
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
  confidence?: number;
  notes?: string;
};

const allowedSources = ["food_photo", "label_photo", "text", "unknown"];

// Fix 3/4: Build one Responses API body for both streaming and non-streaming
// calls so they stay in sync. Reasoning models (gpt-5*, o*) reject `temperature`
// and instead take a `reasoning.effort` hint; classic models get temperature 0
// for deterministic, repeatable estimates.
function buildResponsesBody({
  model,
  prompt,
  imageUrl,
  stream,
}: {
  model: string;
  prompt: string;
  imageUrl: string | null;
  stream: boolean;
}): Record<string, unknown> {
  const isReasoningModel = /^(gpt-5|o\d)/i.test(model);
  const maxOutputTokensRaw = Number(Deno.env.get("MAX_OUTPUT_TOKENS") ?? "2000");
  const maxOutputTokens = Number.isFinite(maxOutputTokensRaw) && maxOutputTokensRaw > 0
    ? maxOutputTokensRaw
    : 2000;

  const body: Record<string, unknown> = {
    model,
    max_output_tokens: maxOutputTokens,
    text: { format: { type: "json_object" } },
    instructions: INSTRUCTIONS,
    input: [
      {
        role: "user",
        content: imageUrl
          ? [
            { type: "input_text", text: prompt },
            { type: "input_image", image_url: imageUrl },
          ]
          : [{ type: "input_text", text: prompt }],
      },
    ],
  };

  if (stream) {
    body.stream = true;
  }

  if (isReasoningModel) {
    body.reasoning = { effort: Deno.env.get("OPENAI_REASONING_EFFORT") ?? "low" };
  } else {
    body.temperature = 0;
  }

  return body;
}

function jsonError(message: string, status: number) {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function parseItems(value: unknown): { items: ItemInput[]; error?: string } {
  if (!Array.isArray(value)) {
    return { items: [] };
  }

  const items: ItemInput[] = [];
  for (const entry of value) {
    if (!entry || typeof entry !== "object") {
      return { items: [], error: "Invalid items payload." };
    }
    const name = typeof (entry as { name?: unknown }).name === "string"
      ? (entry as { name: string }).name.trim()
      : "";
    const gramsRaw = (entry as { grams?: unknown }).grams;
    const grams = typeof gramsRaw === "number" ? gramsRaw : Number(gramsRaw);
    if (!name || !Number.isFinite(grams) || grams <= 0) {
      return { items: [], error: "Invalid items payload." };
    }
    items.push({ name, grams });
  }

  return { items };
}

function extractWeight(text: string): ParsedWeight | null {
  const match = text.match(
    /(\d+(?:\.\d+)?)\s*(g|gram|grams|kg|oz|lb|lbs|pound|pounds)\b/i,
  );
  if (!match) {
    return null;
  }

  const value = Number(match[1]);
  const unit = match[2].toLowerCase();
  if (Number.isNaN(value)) {
    return null;
  }

  return {
    value,
    unit,
    grams: normalizeToGrams(value, unit),
  };
}

function normalizeToGrams(value: number, unit: string): number | undefined {
  switch (unit) {
    case "g":
    case "gram":
    case "grams":
      return value;
    case "kg":
      return value * 1000;
    case "oz":
      return value * 28.3495;
    case "lb":
    case "lbs":
    case "pound":
    case "pounds":
      return value * 453.592;
    default:
      return undefined;
  }
}

function buildPrompt(
  text: string,
  items: ItemInput[],
  parsedWeight: ParsedWeight | null,
  inputType: string,
  imagePath: string,
): string {
  const weightLine = parsedWeight
    ? `Parsed weight: ${parsedWeight.value} ${parsedWeight.unit}` +
      (parsedWeight.grams ? ` (~${Math.round(parsedWeight.grams)} g)` : "")
    : "Parsed weight: none";

  const itemLines = items.length > 0
    ? [
      "Food items (use grams exactly, preserve order):",
      ...items.map((item, index) => `${index + 1}. ${item.name} - ${item.grams} g`),
    ]
    : ["Food items: [none - identify from text/image]"];

  // Fix 5: Portion reference table. Count->grams is a major error source, so we
  // give the model realistic per-unit weights to anchor its estimates. Only
  // needed when we ask it to estimate portions (no explicit grams provided).
  const portionReference = items.length > 0
    ? []
    : [
      "Typical reference weights when a count/quantity is given (guide only; adjust for size and context):",
      "1 egg ≈ 50 g; 1 slice bread ≈ 30 g; 1 medium apple ≈ 180 g; 1 medium banana ≈ 120 g;",
      "1 cup cooked rice ≈ 160 g; 1 cup cooked pasta ≈ 140 g; 1 chicken breast ≈ 170 g;",
      "1 tbsp oil/butter ≈ 14 g; 1 slice cheese ≈ 20 g; 1 medium potato ≈ 170 g; 1 handful nuts ≈ 30 g.",
    ];

  // Always request itemized breakdown for accurate totals
  const outputSpec = items.length > 0
    ? [
      "Return JSON with fields in this exact order:",
      "items, totals, source, food_name, notes.",
      "items must be an array matching the input order. Each item must include:",
      "name, grams, calories, protein, carbs, fat, confidence, notes (confidence/notes optional).",
      "totals must be the sum of all items (calories, protein, carbs, fat).",
      "food_name is optional; use a short name if identifiable.",
    ]
    : [
      "IMPORTANT: Always identify and itemize each distinct food in the input.",
      "Return JSON with fields in this exact order:",
      "items, totals, source, food_name, notes.",
      "items must be an array where each item represents one food component. Each item must include:",
      "name (food name), grams (estimated weight in grams), calories, protein, carbs, fat.",
      "confidence and notes are optional per item.",
      "If the input contains multiple foods (e.g., 'chicken with rice and salad'), create separate items for each.",
      "If the input is a single food (e.g., 'apple'), create one item.",
      "If a number appears without a weight unit (e.g., '2 eggs' or 'egg 2'), treat it as quantity/count, not grams.",
      "Estimate realistic grams for that count using typical per-unit weight; do not default to 100g per unit.",
      "When quantity refers to the same food, prefer a single aggregated item with total grams.",
      "For photos: identify each visible food component separately with estimated gram weights.",
      "totals must be the exact sum of all items (calories, protein, carbs, fat).",
      "food_name is optional; use a combined short name if multiple items.",
    ];

  return [
    "Task: estimate calories (kcal) and macros (grams) from the input.",
    "Units: calories must be kcal. If a label shows kJ, first look for kcal on the label; if no kcal value is present, convert kJ to kcal using kcal = kJ / 4.184.",
    "Macros must be grams; output numbers only (no units).",
    "Consistency: for every item, calories must be close to 4*protein + 4*carbs + 9*fat. Do not report calories that contradict the macros.",
    "If a nutrition label is present, prioritize it over visual estimation.",
    "Handle labels in any language; translate as needed to identify calories, protein, carbs, fat.",
    "Prefer per-100g values first. If per-100g exists, never use per-portion values.",
    "If weight is parsed, scale per-100g values to that weight.",
    "If only a food photo is available, estimate a typical portion and explain assumptions in notes.",
    ...outputSpec,
    "Notes must be a short string (can be empty).",
    "Set source to one of: food_photo, label_photo, text, unknown.",
    `Input type: ${inputType}`,
    `User text: ${text || "[none]"}`,
    `Image path: ${imagePath || "[none]"}`,
    ...itemLines,
    ...portionReference,
    weightLine,
  ].join("\n");
}

// Fix 1/2: Reconcile a single set of macros/calories.
// - Clamps negatives.
// - Cross-checks calories against 4P + 4C + 9F (Atwater). On mismatch, for
//   non-label inputs we trust the macros and recompute calories; for labels we
//   keep the printed calories but flag the discrepancy.
// - Enforces the physical energy-density ceiling (<= ~9.2 kcal/g).
// Returns corrected values plus human-readable flags describing any change.
function reconcileMacros(
  entry: { calories: number; protein: number; carbs: number; fat: number; grams?: number },
  options: { isLabel: boolean },
): { calories: number; protein: number; carbs: number; fat: number; flags: string[] } {
  const flags: string[] = [];

  const protein = Math.max(0, Number.isFinite(entry.protein) ? entry.protein : 0);
  const carbs = Math.max(0, Number.isFinite(entry.carbs) ? entry.carbs : 0);
  const fat = Math.max(0, Number.isFinite(entry.fat) ? entry.fat : 0);
  let calories = Math.max(0, Number.isFinite(entry.calories) ? entry.calories : 0);

  const grams = entry.grams;
  const hasGrams = typeof grams === "number" && Number.isFinite(grams) && grams > 0;

  // Macro mass can never exceed the portion weight.
  if (hasGrams && protein + carbs + fat > (grams as number) * 1.05) {
    flags.push("macro grams exceed portion weight");
  }

  // Calorie/macro consistency (Atwater).
  const derived = 4 * protein + 4 * carbs + 9 * fat;
  if (derived > 0) {
    const denom = Math.max(calories, derived, 1);
    const mismatch = Math.abs(derived - calories) / denom;
    if (calories <= 0 || mismatch > CAL_MISMATCH_TOLERANCE) {
      if (options.isLabel && calories > 0) {
        flags.push("label calories differ from macros");
      } else {
        calories = Math.round(derived);
        flags.push("calories recomputed from macros");
      }
    }
  }

  // Physical energy-density ceiling.
  if (hasGrams) {
    const cap = Math.round((grams as number) * MAX_KCAL_PER_GRAM);
    if (calories > cap) {
      calories = derived > 0 ? Math.min(calories, Math.round(derived), cap) : cap;
      flags.push("calorie density capped");
    }
  }

  return { calories, protein, carbs, fat, flags };
}

function appendNotes(existing: string | undefined, flags: string[]): string | undefined {
  if (flags.length === 0) {
    return existing;
  }
  const adjustment = `Auto-adjusted: ${flags.join("; ")}.`;
  const base = (existing ?? "").trim();
  return base ? `${base} ${adjustment}` : adjustment;
}

function capConfidence(
  confidence: number | undefined,
  hadFlags: boolean,
): number | undefined {
  if (confidence === undefined) {
    return undefined;
  }
  const numeric = Number(confidence);
  if (Number.isNaN(numeric)) {
    return undefined;
  }
  // If we had to correct the model, don't let it claim high confidence.
  return hadFlags ? Math.min(numeric, 0.5) : numeric;
}

function normalizeResult(
  result: AIResult,
  options: { requireItems: boolean; isLabel?: boolean },
): { normalized: NormalizedResult } | { error: string } {
  if (result.error) {
    return { error: result.error };
  }

  if (!result.source || !allowedSources.includes(result.source)) {
    return { error: "Missing required field: source" };
  }

  if (typeof result.notes !== "string") {
    return { error: "Missing required field: notes" };
  }

  const isLabel = Boolean(options.isLabel) || result.source === "label_photo";
  let anyAdjusted = false;

  // Parse items if provided
  let normalizedItems: AIItemResult[] | undefined;
  if (result.items && Array.isArray(result.items) && result.items.length > 0) {
    normalizedItems = [];
    for (const item of result.items) {
      const name = typeof item.name === "string" ? item.name.trim() : "";
      const grams = Number(item.grams);
      const calories = Number(item.calories);
      const protein = Number(item.protein);
      const carbs = Number(item.carbs);
      const fat = Number(item.fat);
      if (!name || !Number.isFinite(grams) || grams <= 0) {
        return { error: "OpenAI returned invalid item data." };
      }
      if ([calories, protein, carbs, fat].some((value) => Number.isNaN(value))) {
        return { error: "OpenAI returned invalid numeric values." };
      }

      // Fix 1/2: reconcile each item before it counts toward totals.
      const reconciled = reconcileMacros(
        { calories, protein, carbs, fat, grams },
        { isLabel },
      );
      if (reconciled.flags.length > 0) {
        anyAdjusted = true;
      }

      normalizedItems.push({
        name,
        grams,
        calories: reconciled.calories,
        protein: reconciled.protein,
        carbs: reconciled.carbs,
        fat: reconciled.fat,
        confidence: capConfidence(
          item.confidence === undefined ? undefined : Number(item.confidence),
          reconciled.flags.length > 0,
        ),
        notes: appendNotes(item.notes, reconciled.flags),
      });
    }
  }

  if (options.requireItems && (!normalizedItems || normalizedItems.length === 0)) {
    return { error: "Missing required field: items" };
  }

  // Get AI's totals (may be inaccurate)
  const aiTotals = normalizeTotals(result);

  // Compute totals from items if available (more accurate, and now consistent
  // because each item was reconciled above).
  let totals: MacroTotals;
  if (normalizedItems && normalizedItems.length > 0) {
    const computedTotals = computeTotalsFromItems(normalizedItems);
    totals = computedTotals;

    // Log if there's a significant mismatch (for debugging)
    if (aiTotals) {
      const calDiff = Math.abs(aiTotals.calories - computedTotals.calories);
      const protDiff = Math.abs(aiTotals.protein - computedTotals.protein);
      const carbsDiff = Math.abs(aiTotals.carbs - computedTotals.carbs);
      const fatDiff = Math.abs(aiTotals.fat - computedTotals.fat);
      if (calDiff > 1 || protDiff > 0.5 || carbsDiff > 0.5 || fatDiff > 0.5) {
        console.log(
          `Totals mismatch - AI: ${JSON.stringify(aiTotals)}, Computed: ${JSON.stringify(computedTotals)}`,
        );
      }
    }
  } else if (aiTotals) {
    // No items: reconcile the AI totals directly (no grams available, so only
    // negatives and the Atwater cross-check apply).
    const reconciled = reconcileMacros(aiTotals, { isLabel });
    if (reconciled.flags.length > 0) {
      anyAdjusted = true;
    }
    totals = {
      calories: reconciled.calories,
      protein: reconciled.protein,
      carbs: reconciled.carbs,
      fat: reconciled.fat,
    };
  } else {
    return { error: "Missing required field: totals" };
  }

  return {
    normalized: {
      totals,
      items: normalizedItems,
      confidence: capConfidence(
        result.confidence === undefined ? undefined : Number(result.confidence),
        anyAdjusted,
      ),
      source: result.source,
      food_name: result.food_name?.trim() || undefined,
      notes: appendNotes(
        result.notes,
        anyAdjusted ? ["some values were adjusted for consistency"] : [],
      ) ?? result.notes,
    },
  };
}

function computeTotalsFromItems(items: AIItemResult[]): MacroTotals {
  let calories = 0;
  let protein = 0;
  let carbs = 0;
  let fat = 0;

  for (const item of items) {
    calories += item.calories;
    protein += item.protein;
    carbs += item.carbs;
    fat += item.fat;
  }

  // Round to 2 decimal places to avoid floating point issues
  return {
    calories: Math.round(calories * 100) / 100,
    protein: Math.round(protein * 100) / 100,
    carbs: Math.round(carbs * 100) / 100,
    fat: Math.round(fat * 100) / 100,
  };
}

function normalizeTotals(result: AIResult): MacroTotals | null {
  if (result.totals) {
    const calories = Number(result.totals.calories);
    const protein = Number(result.totals.protein);
    const carbs = Number(result.totals.carbs);
    const fat = Number(result.totals.fat);
    if ([calories, protein, carbs, fat].some((value) => Number.isNaN(value))) {
      return null;
    }
    return { calories, protein, carbs, fat };
  }

  if (
    result.calories === undefined ||
    result.protein === undefined ||
    result.carbs === undefined ||
    result.fat === undefined
  ) {
    return null;
  }

  const calories = Number(result.calories);
  const protein = Number(result.protein);
  const carbs = Number(result.carbs);
  const fat = Number(result.fat);
  if ([calories, protein, carbs, fat].some((value) => Number.isNaN(value))) {
    return null;
  }
  return { calories, protein, carbs, fat };
}

function extractOutputText(data: unknown): string {
  if (typeof data === "object" && data !== null && "output_text" in data) {
    const outputText = (data as { output_text?: unknown }).output_text;
    if (typeof outputText === "string") {
      return outputText;
    }
  }

  const output = (data as { output?: unknown })?.output;
  if (!Array.isArray(output)) {
    return "";
  }

  const texts: string[] = [];
  for (const item of output) {
    if (!item || typeof item !== "object") {
      continue;
    }
    const content = (item as { content?: unknown }).content;
    if (!Array.isArray(content)) {
      continue;
    }
    for (const part of content) {
      if (!part || typeof part !== "object") {
        continue;
      }
      if ((part as { type?: unknown }).type === "output_text") {
        const text = (part as { text?: unknown }).text;
        if (typeof text === "string") {
          texts.push(text);
        }
      }
    }
  }

  return texts.join("");
}

function extractRefusal(data: unknown): string | null {
  const output = (data as { output?: unknown })?.output;
  if (!Array.isArray(output)) {
    return null;
  }

  for (const item of output) {
    if (!item || typeof item !== "object") {
      continue;
    }
    const content = (item as { content?: unknown }).content;
    if (!Array.isArray(content)) {
      continue;
    }
    for (const part of content) {
      if (!part || typeof part !== "object") {
        continue;
      }
      if ((part as { type?: unknown }).type === "refusal") {
        const refusal = (part as { refusal?: unknown }).refusal;
        if (typeof refusal === "string" && refusal.trim()) {
          return refusal;
        }
        return "OpenAI refused to answer.";
      }
    }
  }

  return null;
}

async function streamEstimate({
  baseUrl,
  model,
  isLabelInput,
  prompt,
  imageUrl,
  hasItems,
  openAiKey,
}: {
  baseUrl: string;
  model: string;
  isLabelInput: boolean;
  prompt: string;
  imageUrl: string | null;
  hasItems: boolean;
  openAiKey: string;
}): Promise<Response> {
  const encoder = new TextEncoder();
  const decoder = new TextDecoder();
  const timeoutMs = Number(Deno.env.get("STREAM_TIMEOUT_MS") ?? "20000");

  const sendEvent = (controller: ReadableStreamDefaultController, event: string, data: unknown) => {
    const payload = JSON.stringify(data);
    controller.enqueue(encoder.encode(`event: ${event}\ndata: ${payload}\n\n`));
  };

  const stream = new ReadableStream({
    start: async (controller) => {
      const startedAt = Date.now();
      try {
        console.log("streaming OpenAI request", { model, baseUrl, hasImage: Boolean(imageUrl) });
        sendEvent(controller, "status", { stage: "requesting_model" });

        const response = await fetch(`${baseUrl}/responses`, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${openAiKey}`,
          },
          body: JSON.stringify(buildResponsesBody({ model, prompt, imageUrl, stream: true })),
        });

        console.log("streaming OpenAI response status", response.status);
        if (!response.ok || !response.body) {
          const errorText = await response.text();
          sendEvent(controller, "error", {
            error: `OpenAI request failed with status ${response.status}: ${errorText || "unknown error"}.`,
          });
          controller.close();
          return;
        }

        const reader = response.body.getReader();
        let buffer = "";
        let outputText = "";
        let timedOut = false;

        while (true) {
          if (Date.now() - startedAt > timeoutMs) {
            timedOut = true;
            break;
          }
          const { value, done } = await reader.read();
          if (done) break;
          buffer += decoder.decode(value, { stream: true });

          let separator = nextSseSeparator(buffer);
          while (separator) {
            const rawEvent = buffer.slice(0, separator.index);
            buffer = buffer.slice(separator.index + separator.length);

            const parsed = parseSseEvent(rawEvent);
            if (!parsed?.data) {
              separator = nextSseSeparator(buffer);
              continue;
            }

            if (parsed.data === "[DONE]") {
              separator = nextSseSeparator(buffer);
              continue;
            }

            let payload: { type?: string; delta?: string } | null = null;
            try {
              payload = JSON.parse(parsed.data);
            } catch {
              payload = null;
            }

            if (payload?.type === "response.output_text.delta" && payload.delta) {
              outputText += payload.delta;
              sendEvent(controller, "delta", { delta: payload.delta });
            }

            separator = nextSseSeparator(buffer);
          }
        }

        if (timedOut) {
          console.log("stream timeout");
          sendEvent(controller, "error", { error: "Model response timed out." });
          controller.close();
          return;
        }

        sendEvent(controller, "status", { stage: "finalizing" });

        let result: AIResult;
        try {
          result = JSON.parse(outputText);
        } catch {
          sendEvent(controller, "error", { error: "OpenAI returned invalid JSON." });
          controller.close();
          return;
        }

        const normalizedResult = normalizeResult(result, {
          requireItems: hasItems,
          isLabel: isLabelInput,
        });
        if ("error" in normalizedResult) {
          sendEvent(controller, "error", { error: normalizedResult.error });
          controller.close();
          return;
        }

        sendEvent(controller, "result", normalizedResult.normalized);
        controller.close();
      } catch (error) {
        const message = error instanceof Error ? error.message : "Unknown error.";
        sendEvent(controller, "error", { error: message });
        controller.close();
      }
    },
  });

  return new Response(stream, {
    headers: {
      ...corsHeaders,
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      Connection: "keep-alive",
    },
  });
}

function parseSseEvent(raw: string): { event: string; data: string } | null {
  const normalized = raw.replace(/\r\n/g, "\n");
  const lines = normalized.split("\n");
  let event = "";
  const dataLines: string[] = [];

  for (const line of lines) {
    if (line.startsWith("event:")) {
      event = line.replace("event:", "").trim();
    } else if (line.startsWith("data:")) {
      dataLines.push(line.replace("data:", "").trim());
    }
  }

  const data = dataLines.join("\n");
  if (!data) return null;
  return { event, data };
}

function nextSseSeparator(buffer: string): { index: number; length: number } | null {
  const lfIndex = buffer.indexOf("\n\n");
  const crlfIndex = buffer.indexOf("\r\n\r\n");

  if (lfIndex === -1 && crlfIndex === -1) {
    return null;
  }

  if (lfIndex === -1) {
    return { index: crlfIndex, length: 4 };
  }

  if (crlfIndex === -1) {
    return { index: lfIndex, length: 2 };
  }

  return lfIndex < crlfIndex
    ? { index: lfIndex, length: 2 }
    : { index: crlfIndex, length: 4 };
}

async function createSignedImageUrl({
  supabaseUrl,
  supabaseAnonKey,
  accessToken,
  imagePath,
  bucket,
}: {
  supabaseUrl: string;
  supabaseAnonKey: string;
  accessToken: string;
  imagePath: string;
  bucket: string;
}): Promise<string> {
  const response = await fetch(
    `${supabaseUrl}/storage/v1/object/sign/${bucket}/${imagePath}`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${accessToken}`,
        apikey: supabaseAnonKey,
      },
      body: JSON.stringify({ expiresIn: 60 }),
    },
  );

  if (!response.ok) {
    throw new Error("Unable to create signed URL for image.");
  }

  const data = await response.json();
  const signedUrl = data.signedURL ?? data.signedUrl;
  if (!signedUrl) {
    throw new Error("Signed URL response missing.");
  }

  if (signedUrl.startsWith("http")) {
    return signedUrl;
  }

  if (signedUrl.startsWith("/object/")) {
    return `${supabaseUrl}/storage/v1${signedUrl}`;
  }

  if (signedUrl.startsWith("/storage/v1")) {
    return `${supabaseUrl}${signedUrl}`;
  }

  return `${supabaseUrl}/storage/v1${signedUrl.startsWith("/") ? "" : "/"}${signedUrl}`;
}
