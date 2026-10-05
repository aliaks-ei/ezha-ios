import { serve } from "https://deno.land/std@0.203.0/http/server.ts";
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type"
};
serve(async (req)=>{
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: corsHeaders
    });
  }
  let payload;
  try {
    payload = await req.json();
  } catch  {
    return jsonError("Invalid JSON payload.", 400);
  }
  const { remaining, error: remainingError } = parseRemaining(payload.remaining);
  if (remainingError) {
    return jsonError(remainingError, 400);
  }
  const mealType = typeof payload.meal_type === "string" ? payload.meal_type.trim() : "";
  if (!mealType) {
    return jsonError("Missing required field: meal_type", 400);
  }
  const maxPrepMinutes = parsePositiveInt(payload.max_prep_minutes);
  if (!maxPrepMinutes) {
    return jsonError("Missing required field: max_prep_minutes", 400);
  }
  const count = clampCount(payload.count ?? 3);
  const ingredientNotes = typeof payload.ingredient_notes === "string" ? payload.ingredient_notes.trim() : "";
  const variationNote = typeof payload.variation_note === "string" ? payload.variation_note.trim() : "";
  const units = typeof payload.units === "string" && payload.units.trim() ? payload.units.trim() : "grams";
  const openAiKey = Deno.env.get("OPENAI_API_KEY");
  if (!openAiKey) {
    return jsonError("Missing required field: OPENAI_API_KEY", 500);
  }
  const authHeader = req.headers.get("authorization") ?? "";
  const tokenMatch = authHeader.match(/^Bearer\s+(.+)$/i);
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
      Authorization: `Bearer ${tokenMatch[1]}`,
      apikey: supabaseAnonKey
    }
  });
  if (!authResponse.ok) {
    return jsonError("Invalid JWT", 401);
  }
  const model = payload.model ?? Deno.env.get("OPENAI_MODEL") ?? "gpt-5-mini";
  const baseUrl = Deno.env.get("OPENAI_BASE_URL") ?? "https://api.openai.com/v1";
  const prompt = buildPrompt({
    remaining,
    mealType,
    maxPrepMinutes,
    count,
    ingredientNotes,
    variationNote,
    units
  });
  const response = await fetch(`${baseUrl}/responses`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${openAiKey}`
    },
    body: JSON.stringify({
      model,
      temperature: 0.4,
      text: {
        format: {
          type: "json_object"
        }
      },
      instructions: "You are a meal suggestion assistant. Return only valid JSON. " + "All numeric fields are numbers without units. Calories are kcal. " + "Protein, carbs, fat are grams.",
      input: [
        {
          role: "user",
          content: [
            {
              type: "input_text",
              text: prompt
            }
          ]
        }
      ]
    })
  });
  if (!response.ok) {
    const errorText = await response.text();
    return jsonError(`OpenAI request failed with status ${response.status}: ${errorText || "unknown error"}.`, 502);
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
  } catch  {
    return jsonError("Invalid OpenAI response.", 502);
  }
  let result;
  try {
    result = JSON.parse(content);
  } catch  {
    return jsonError("OpenAI returned invalid JSON.", 502);
  }
  if (result.error) {
    return jsonError(result.error, 502);
  }
  const normalized = normalizeSuggestions(result, remaining, count);
  if ("error" in normalized) {
    return jsonError(normalized.error, 502);
  }
  return new Response(JSON.stringify({
    suggestions: normalized.suggestions
  }), {
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json"
    }
  });
});
function jsonError(message, status) {
  return new Response(JSON.stringify({
    error: message
  }), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json"
    }
  });
}
function parseRemaining(value) {
  if (!value || typeof value !== "object") {
    return {
      remaining: null,
      error: "Missing required field: remaining"
    };
  }
  const raw = value;
  const calories = Number(raw.calories);
  const protein = Number(raw.protein);
  const carbs = Number(raw.carbs);
  const fat = Number(raw.fat);
  if ([
    calories,
    protein,
    carbs,
    fat
  ].some((item)=>Number.isNaN(item))) {
    return {
      remaining: null,
      error: "Invalid remaining macros."
    };
  }
  return {
    remaining: {
      calories,
      protein,
      carbs,
      fat
    }
  };
}
function parsePositiveInt(value) {
  if (typeof value === "number" && Number.isFinite(value)) {
    const rounded = Math.round(value);
    return rounded > 0 ? rounded : null;
  }
  if (typeof value === "string") {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) {
      const rounded = Math.round(parsed);
      return rounded > 0 ? rounded : null;
    }
  }
  return null;
}
function clampCount(value) {
  const numeric = parsePositiveInt(value);
  if (!numeric) return 3;
  return Math.min(Math.max(numeric, 1), 5);
}
function buildPrompt({ remaining, mealType, maxPrepMinutes, count, ingredientNotes, variationNote, units }) {
  const notesLine = ingredientNotes ? `Ingredient notes: ${ingredientNotes}` : "Ingredient notes: [none]";
  const variationLine = variationNote ? `User wants changes: ${variationNote}` : "User wants changes: [none]";
  return [
    "Task: Suggest meal ideas based on remaining macros today.",
    `Return exactly ${count} suggestions for a ${mealType.toLowerCase()}.`,
    "Each suggestion should be a short meal idea or a small food set (no full recipes).",
    `Max prep time: ${maxPrepMinutes} minutes.`,
    `Units: calories in kcal, macros in ${units}.`,
    "If a suggestion exceeds any remaining macro, explicitly mention it in notes.",
    "Return JSON with fields in this exact order: suggestions.",
    "Each suggestion object must include fields in this exact order:",
    "title, description, calories, protein, carbs, fat, notes.",
    "notes can be an empty string.",
    `Remaining macros: calories ${remaining.calories}, protein ${remaining.protein}, carbs ${remaining.carbs}, fat ${remaining.fat}.`,
    notesLine,
    variationLine
  ].join("\n");
}
function normalizeSuggestions(result, remaining, count) {
  if (!Array.isArray(result.suggestions) || result.suggestions.length === 0) {
    return {
      error: "Missing required field: suggestions"
    };
  }
  const suggestions = [];
  for (const entry of result.suggestions.slice(0, count)){
    if (!entry || typeof entry !== "object") {
      return {
        error: "Invalid suggestion payload."
      };
    }
    const title = typeof entry.title === "string" ? entry.title.trim() : "";
    const description = typeof entry.description === "string" ? entry.description.trim() : "";
    const calories = Number(entry.calories);
    const protein = Number(entry.protein);
    const carbs = Number(entry.carbs);
    const fat = Number(entry.fat);
    if (!title || !description) {
      return {
        error: "Invalid suggestion payload."
      };
    }
    if ([
      calories,
      protein,
      carbs,
      fat
    ].some((value)=>Number.isNaN(value))) {
      return {
        error: "Invalid suggestion payload."
      };
    }
    const notes = typeof entry.notes === "string" ? entry.notes.trim() : "";
    const normalizedNotes = appendExceedNotes(notes, {
      calories,
      protein,
      carbs,
      fat
    }, remaining);
    suggestions.push({
      title,
      description,
      calories,
      protein,
      carbs,
      fat,
      notes: normalizedNotes
    });
  }
  return {
    suggestions
  };
}
function appendExceedNotes(notes, macros, remaining) {
  const parts = [];
  if (macros.calories > remaining.calories) {
    parts.push(`calories by ${Math.round(macros.calories - remaining.calories)} kcal`);
  }
  if (macros.protein > remaining.protein) {
    parts.push(`protein by ${Math.round(macros.protein - remaining.protein)} g`);
  }
  if (macros.carbs > remaining.carbs) {
    parts.push(`carbs by ${Math.round(macros.carbs - remaining.carbs)} g`);
  }
  if (macros.fat > remaining.fat) {
    parts.push(`fat by ${Math.round(macros.fat - remaining.fat)} g`);
  }
  if (parts.length === 0) {
    return notes;
  }
  const warning = `Exceeds ${parts.join(", ")}.`;
  if (!notes) {
    return warning;
  }
  if (notes.toLowerCase().includes("exceeds")) {
    return notes;
  }
  return `${notes} ${warning}`.trim();
}
function extractOutputText(data) {
  if (typeof data === "object" && data !== null && "output_text" in data) {
    const outputText = data.output_text;
    if (typeof outputText === "string") {
      return outputText;
    }
  }
  const output = data?.output;
  if (!Array.isArray(output)) {
    return "";
  }
  const texts = [];
  for (const item of output){
    if (!item || typeof item !== "object") {
      continue;
    }
    const content = item.content;
    if (!Array.isArray(content)) {
      continue;
    }
    for (const part of content){
      if (!part || typeof part !== "object") {
        continue;
      }
      if (part.type === "output_text") {
        const text = part.text;
        if (typeof text === "string") {
          texts.push(text);
        }
      }
    }
  }
  return texts.join("");
}
function extractRefusal(data) {
  const output = data?.output;
  if (!Array.isArray(output)) {
    return null;
  }
  for (const item of output){
    if (!item || typeof item !== "object") {
      continue;
    }
    const content = item.content;
    if (!Array.isArray(content)) {
      continue;
    }
    for (const part of content){
      if (!part || typeof part !== "object") {
        continue;
      }
      if (part.type === "refusal") {
        const refusal = part.refusal;
        if (typeof refusal === "string" && refusal.trim()) {
          return refusal;
        }
        return "OpenAI refused to answer.";
      }
    }
  }
  return null;
}
