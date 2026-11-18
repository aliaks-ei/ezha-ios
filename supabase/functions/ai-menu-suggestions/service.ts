import {
  buildModelBody,
  DEFAULT_MODEL,
  FALLBACK_MODEL,
  type MenuReading,
  normalizeMenu,
  parseRequest,
  shouldEscalate,
} from "./core.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};
class HTTPError extends Error {
  constructor(message: string, readonly status: number) {
    super(message);
  }
}
type Dependencies = {
  env: (name: string) => string | undefined;
  fetcher?: typeof fetch;
  log?: (event: Record<string, unknown>) => void;
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
const positiveInteger = (
  raw: string | undefined,
  fallback: number,
  max: number,
) => {
  const n = Number(raw);
  return Number.isInteger(n) && n > 0 && n <= max ? n : fallback;
};

export function createHandler(
  { env, fetcher = fetch, log = console.log }: Dependencies,
) {
  return async (req: Request): Promise<Response> => {
    if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
    if (req.method !== "POST") {
      return json({ error: "Use POST for menu suggestions." }, 405);
    }
    let payload: Record<string, unknown>;
    try {
      const value = await req.json();
      if (!value || typeof value !== "object" || Array.isArray(value)) {
        throw new Error();
      }
      payload = value;
    } catch {
      return json({ error: "Invalid JSON payload." }, 400);
    }
    const parsed = parseRequest(payload);
    if ("error" in parsed) return json({ error: parsed.error }, 400);
    const { request } = parsed;

    const apiKey = env("OPENAI_API_KEY");
    const supabaseUrl = env("SUPABASE_URL");
    const anonKey = env("SUPABASE_ANON_KEY");
    if (!apiKey || !supabaseUrl || !anonKey) {
      return json({ error: "Menu suggestions are not configured." }, 500);
    }
    const model = env("OPENAI_MENU_MODEL") ?? DEFAULT_MODEL;
    const fallbackModel = env("OPENAI_MENU_FALLBACK_MODEL") ?? FALLBACK_MODEL;
    const maxOutputTokens = positiveInteger(
      env("MENU_MAX_OUTPUT_TOKENS"),
      3000,
      10000,
    );
    try {
      buildModelBody({ model, request, maxOutputTokens });
      buildModelBody({ model: fallbackModel, request, maxOutputTokens });
    } catch (error) {
      return json({ error: (error as Error).message }, 500);
    }

    const abort = new AbortController();
    const timer = setTimeout(
      () => abort.abort(),
      positiveInteger(env("MENU_TIMEOUT_MS"), 50000, 120000),
    );
    const cancel = () => abort.abort();
    req.signal.addEventListener("abort", cancel, { once: true });
    const started = performance.now();
    const telemetry: Record<string, unknown> = {
      request_id: crypto.randomUUID(),
      function: "ai-menu-suggestions",
      images: request.images.length,
      meal_type: request.mealType,
      model,
    };
    try {
      // Vision requests are costly, so the user is always verified.
      const token =
        req.headers.get("authorization")?.match(/^Bearer\s+(.+)$/i)?.[1] ?? "";
      if (!token) throw new HTTPError("Sign in to get suggestions.", 401);
      const auth = await fetcher(`${supabaseUrl}/auth/v1/user`, {
        headers: { Authorization: `Bearer ${token}`, apikey: anonKey },
        signal: abort.signal,
      });
      if (!auth.ok) {
        throw new HTTPError("Your session expired. Sign in again.", 401);
      }

      const attempts: Record<string, unknown>[] = [];
      const read = async (selected: string): Promise<MenuReading> => {
        const response = await fetcher(
          `${env("OPENAI_BASE_URL") ?? "https://api.openai.com/v1"}/responses`,
          {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              Authorization: `Bearer ${apiKey}`,
            },
            body: JSON.stringify(
              buildModelBody({ model: selected, request, maxOutputTokens }),
            ),
            signal: abort.signal,
          },
        );
        if (!response.ok) {
          throw new Error(
            `Menu model request failed (${response.status}). Try again.`,
          );
        }
        const data = await response.json();
        attempts.push({
          model: selected,
          response_id: data?.id,
          usage: data?.usage,
        });
        return parseModelResponse(data);
      };
      let reading = await read(model);
      if (model !== fallbackModel && shouldEscalate(reading)) {
        telemetry.fallback_model = fallbackModel;
        reading = await read(fallbackModel);
      }
      telemetry.attempts = attempts;
      telemetry.status = reading.status;
      const result = normalizeMenu(reading);
      telemetry.suggestions = result.suggestions.length;
      telemetry.outcome = "success";
      return json(result);
    } catch (error) {
      telemetry.outcome = "error";
      const message = abort.signal.aborted
        ? "Menu suggestions timed out. Try again."
        : error instanceof Error
        ? error.message
        : "Menu suggestions failed. Try again.";
      return json(
        { error: message },
        error instanceof HTTPError ? error.status : 502,
      );
    } finally {
      clearTimeout(timer);
      req.signal.removeEventListener("abort", cancel);
      telemetry.total_ms = Math.round(performance.now() - started);
      log(telemetry);
    }
  };
}

/// Reads a non-streaming Responses API body into the menu reading.
export function parseModelResponse(data: unknown): MenuReading {
  const response = data as {
    status?: string;
    output_text?: unknown;
    output?: { content?: { type?: string; text?: unknown }[] }[];
  };
  if (response?.status && response.status !== "completed") {
    throw new Error(
      response.status === "incomplete"
        ? "The menu was too long to read at once. Try fewer pages."
        : "Menu model failed. Try again.",
    );
  }
  const parts = (response?.output ?? []).flatMap((item) => item?.content ?? []);
  if (parts.some((part) => part?.type === "refusal")) {
    throw new Error("These photos couldn't be analyzed. Try a menu photo.");
  }
  const output = typeof response?.output_text === "string"
    ? response.output_text
    : parts.filter((part) => part?.type === "output_text")
      .map((part) => (typeof part.text === "string" ? part.text : "")).join("");
  try {
    return JSON.parse(output) as MenuReading;
  } catch {
    throw new Error("Menu model returned an invalid response. Try again.");
  }
}
