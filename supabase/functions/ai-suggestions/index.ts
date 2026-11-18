import {
  buildModelBody,
  buildPrompt,
  DEFAULT_MODEL,
  extractOutputText,
  extractRefusal,
  normalizeSuggestions,
  parseRequest,
  pickInspirations,
} from "./core.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function jsonError(message: string, status: number) {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  let payload: Record<string, unknown>;
  try {
    payload = await req.json();
  } catch {
    return jsonError("Invalid JSON payload.", 400);
  }
  if (!payload || typeof payload !== "object") {
    return jsonError("Invalid JSON payload.", 400);
  }
  const parsed = parseRequest(payload);
  if ("error" in parsed) return jsonError(parsed.error, 400);
  const { request } = parsed;

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
    return jsonError(
      "Missing required field: SUPABASE_URL or SUPABASE_ANON_KEY",
      500,
    );
  }
  const authResponse = await fetch(`${supabaseUrl}/auth/v1/user`, {
    method: "GET",
    headers: {
      Authorization: `Bearer ${tokenMatch[1]}`,
      apikey: supabaseAnonKey,
    },
  });
  if (!authResponse.ok) return jsonError("Invalid JWT", 401);

  const model = typeof payload.model === "string" && payload.model
    ? payload.model
    : Deno.env.get("OPENAI_MODEL") ?? DEFAULT_MODEL;
  const baseUrl = Deno.env.get("OPENAI_BASE_URL") ??
    "https://api.openai.com/v1";
  const prompt = buildPrompt(
    request,
    pickInspirations(request.count, request.mealType),
  );
  const response = await fetch(`${baseUrl}/responses`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${openAiKey}`,
    },
    body: JSON.stringify(buildModelBody({ model, prompt })),
  });
  if (!response.ok) {
    const errorText = await response.text();
    return jsonError(
      `OpenAI request failed with status ${response.status}: ${
        errorText || "unknown error"
      }.`,
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
    if (refusal) return jsonError(refusal, 502);
    content = extractOutputText(data);
  } catch {
    return jsonError("Invalid OpenAI response.", 502);
  }
  let result: Record<string, unknown>;
  try {
    result = JSON.parse(content);
  } catch {
    return jsonError("OpenAI returned invalid JSON.", 502);
  }
  if (typeof result?.error === "string") {
    return jsonError(result.error, 502);
  }
  const normalized = normalizeSuggestions(
    result,
    request.remaining,
    request.count,
  );
  if ("error" in normalized) return jsonError(normalized.error, 502);
  return new Response(
    JSON.stringify({ suggestions: normalized.suggestions }),
    { headers: { ...corsHeaders, "Content-Type": "application/json" } },
  );
});
