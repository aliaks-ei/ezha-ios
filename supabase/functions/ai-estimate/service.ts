import foods from "./food-catalog.json" with { type: "json" };
import {
  buildModelBody,
  type CatalogFood,
  DEFAULT_MODEL,
  FALLBACK_MODEL,
  type ItemInput,
  type LabelReading,
  libraryFood,
  type MealReading,
  normalizeLabel,
  normalizeMeal,
  type Result,
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
      return json({ error: "Use POST for meal analysis." }, 405);
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
    const text = typeof payload.text === "string" ? payload.text.trim() : "";
    const imagePath = typeof payload.imagePath === "string"
      ? payload.imagePath.trim()
      : "";
    const inputType = payload.inputType ?? (imagePath ? "food_photo" : "text");
    if (
      !["text", "food_photo", "label_photo"].includes(inputType as string) ||
      text.length > 12000
    ) {
      return json(
        { error: "Invalid input type or description is too long." },
        400,
      );
    }
    let items: ItemInput[] = [];
    if (payload.items != null) {
      if (
        !Array.isArray(payload.items) || payload.items.length > 20 ||
        payload.items.some((item) =>
          !item || typeof item.name !== "string" || !item.name.trim() ||
          typeof item.grams !== "number" || !Number.isFinite(item.grams) ||
          item.grams <= 0 || item.grams > 5000
        )
      ) {
        return json({ error: "Invalid items payload." }, 400);
      }
      items = payload.items.map((item) => ({
        name: item.name.trim(),
        grams: item.grams,
      }));
    }
    if (!text && !imagePath && !items.length) {
      return json({ error: "Provide text, items, or a photo." }, 400);
    }
    const isLabel = inputType === "label_photo";
    if (isLabel && !imagePath) {
      return json({ error: "Attach a nutrition label photo." }, 400);
    }
    const apiKey = env("OPENAI_API_KEY");
    if (!apiKey) {
      return json({ error: "Meal analysis is not configured." }, 500);
    }
    // Estimate settings are independent of ai-suggestions and legacy OPENAI_MODEL overrides.
    const model = typeof payload.model === "string"
      ? payload.model
      : env("OPENAI_ESTIMATE_MODEL") ?? DEFAULT_MODEL;
    const fallbackModel = env("OPENAI_ESTIMATE_FALLBACK_MODEL") ??
      FALLBACK_MODEL;
    const maxOutputTokens = positiveInteger(
      env("MAX_OUTPUT_TOKENS"),
      2400,
      10000,
    );
    try {
      buildModelBody({
        model,
        isLabel,
        text,
        imageUrl: null,
        items,
        catalog: [],
        maxOutputTokens,
      });
      if (![DEFAULT_MODEL, FALLBACK_MODEL].includes(fallbackModel)) {
        throw new Error("Invalid fallback model.");
      }
    } catch (error) {
      return json({ error: (error as Error).message }, 400);
    }

    const abort = new AbortController();
    const deadline = positiveInteger(
      env("ESTIMATE_TIMEOUT_MS") ?? env("STREAM_TIMEOUT_MS"),
      35000,
      120000,
    );
    const timer = setTimeout(() => abort.abort(), deadline);
    const cancel = () => abort.abort();
    req.signal.addEventListener("abort", cancel, { once: true });
    if (req.signal.aborted) abort.abort();
    const cleanup = () => {
      clearTimeout(timer);
      req.signal.removeEventListener("abort", cancel);
    };
    const started = performance.now();
    const telemetry: Record<string, unknown> = {
      request_id: crypto.randomUUID(),
      input_type: inputType,
      model,
    };
    let imageUrl: string | null;
    let catalog: CatalogFood[];
    try {
      const token =
        req.headers.get("authorization")?.match(/^Bearer\s+(.+)$/i)?.[1] ?? "";
      const supabaseUrl = env("SUPABASE_URL");
      const anonKey = env("SUPABASE_ANON_KEY");
      if ((env("VERIFY_JWT") ?? "false").toLowerCase() === "true") {
        if (!token) throw new HTTPError("Sign in to analyze a meal.", 401);
        if (!supabaseUrl || !anonKey) {
          throw new HTTPError("Meal analysis is not configured.", 500);
        }
        const auth = await fetcher(`${supabaseUrl}/auth/v1/user`, {
          headers: { Authorization: `Bearer ${token}`, apikey: anonKey },
          signal: abort.signal,
        });
        if (!auth.ok) {
          throw new HTTPError("Your session expired. Sign in again.", 401);
        }
      }
      const prepStarted = performance.now();
      // Independent reads overlap. Library lookup uses the user's RLS-scoped token.
      [imageUrl, catalog] = await Promise.all([
        imagePath
          ? signedImage({
            imagePath,
            token,
            supabaseUrl,
            anonKey,
            bucket: env("FOOD_IMAGES_BUCKET") ?? "food-images",
            fetcher,
            signal: abort.signal,
          })
          : Promise.resolve(null),
        isLabel ? Promise.resolve([]) : loadCatalog({
          token,
          supabaseUrl,
          anonKey,
          fetcher,
          signal: abort.signal,
        }),
      ]);
      abort.signal.throwIfAborted();
      telemetry.preparation_ms = Math.round(performance.now() - prepStarted);
    } catch (error) {
      cleanup();
      return json(
        { error: errorMessage(error, abort.signal) },
        error instanceof HTTPError ? error.status : 502,
      );
    }

    const run = async (
      send: (event: string, data: unknown) => void,
    ): Promise<Result> => {
      let selectedModel = model;
      send("status", { stage: "requesting_model" });
      const getReading = async (allowPreviews: boolean) => {
        const modelStarted = performance.now();
        let firstDelta = false, previewCount = 0;
        const body = buildModelBody({
          model: selectedModel,
          isLabel,
          text,
          imageUrl,
          items,
          catalog,
          maxOutputTokens,
        });
        const response = await fetcher(
          `${env("OPENAI_BASE_URL") ?? "https://api.openai.com/v1"}/responses`,
          {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              Authorization: `Bearer ${apiKey}`,
            },
            body: JSON.stringify({ ...body, stream: true }),
            signal: abort.signal,
          },
        );
        if (!response.ok || !response.body) {
          throw new Error(
            `Meal model request failed (${response.status}). Try again.`,
          );
        }
        const reading = await readModelStream(response.body, (output) => {
          if (!firstDelta) {
            telemetry.first_output_ms ??= Math.round(
              performance.now() - started,
            );
            firstDelta = true;
          }
          if (!allowPreviews || isLabel) return;
          const completed = completedMealItems(output);
          for (; previewCount < completed.length; previewCount++) {
            try {
              const explicit = items[previewCount] ? [items[previewCount]] : [];
              const item = normalizeMeal(
                {
                  status: "ok",
                  food_name: null,
                  items: [completed[previewCount]],
                  review: null,
                },
                catalog,
                imageUrl ? "food_photo" : "text",
                explicit,
              ).items[0];
              telemetry.first_item_ms ??= Math.round(
                performance.now() - started,
              );
              send("item", { index: previewCount, item });
            } catch {
              /* Invalid provisional data is never shown. Final validation remains mandatory. */
            }
          }
        });
        telemetry.model_ms = Number(telemetry.model_ms ?? 0) +
          Math.round(performance.now() - modelStarted);
        telemetry.openai_response_id = reading.responseId;
        telemetry.usage = reading.usage;
        const attempts = (telemetry.attempts ?? []) as Record<
          string,
          unknown
        >[];
        attempts.push({
          model: selectedModel,
          response_id: reading.responseId,
          usage: reading.usage,
        });
        telemetry.attempts = attempts;
        return reading.value;
      };
      let reading = await getReading(true);
      if (
        imageUrl && selectedModel !== fallbackModel && shouldEscalate(reading)
      ) {
        // Greater compute helps recognition/OCR, not missing scale or invisible ingredients.
        selectedModel = fallbackModel;
        telemetry.fallback_model = fallbackModel;
        send("status", { stage: "checking_details" });
        send("reset", {});
        reading = await getReading(false);
      }
      send("status", { stage: "finalizing" });
      const result = isLabel
        ? normalizeLabel(reading as LabelReading)
        : normalizeMeal(
          reading as MealReading,
          catalog,
          imageUrl ? "food_photo" : "text",
          items,
        );
      telemetry.total_ms = Math.round(performance.now() - started);
      telemetry.grounded_items =
        result.items.filter((i) => i.nutrition_source !== "estimated").length;
      telemetry.estimated_items =
        result.items.filter((i) => i.nutrition_source === "estimated").length;
      telemetry.outcome = "success";
      return result;
    };
    if (!payload.stream) {
      try {
        return json(await run(() => {}));
      } catch (error) {
        telemetry.outcome = "error";
        return json({ error: errorMessage(error, abort.signal) }, 502);
      } finally {
        cleanup();
        log(telemetry);
      }
    }
    let closed = false;
    const encoder = new TextEncoder();
    const stream = new ReadableStream({
      start(controller) {
        const send = (event: string, data: unknown) => {
          if (!closed) {
            controller.enqueue(
              encoder.encode(
                `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`,
              ),
            );
          }
        };
        run(send).then((result) => send("result", result)).catch((error) => {
          telemetry.outcome = "error";
          send("error", { error: errorMessage(error, abort.signal) });
        }).finally(() => {
          cleanup();
          telemetry.total_ms = Math.round(performance.now() - started);
          log(telemetry);
          if (!closed) {
            closed = true;
            controller.close();
          }
        });
      },
      cancel() {
        closed = true;
        abort.abort();
        cleanup();
      },
    });
    return new Response(stream, {
      headers: {
        ...cors,
        "Content-Type": "text/event-stream",
        "Cache-Control": "no-cache",
      },
    });
  };
}

function errorMessage(error: unknown, signal: AbortSignal): string {
  return signal.aborted
    ? "Meal analysis timed out. Try again."
    : error instanceof Error
    ? error.message
    : "Analysis failed. Try again.";
}
async function signedImage(options: {
  imagePath: string;
  token: string;
  supabaseUrl?: string;
  anonKey?: string;
  bucket: string;
  fetcher: typeof fetch;
  signal: AbortSignal;
}): Promise<string> {
  const { imagePath, token, supabaseUrl, anonKey, bucket, fetcher, signal } =
    options;
  if (!token) throw new HTTPError("Sign in to analyze a photo.", 401);
  if (!supabaseUrl || !anonKey) {
    throw new HTTPError("Photo analysis is not configured.", 500);
  }
  if (!/^[\w-]+\/[\w-]+\.jpg$/.test(imagePath)) {
    throw new HTTPError("Invalid image path.", 400);
  }
  const response = await fetcher(
    `${supabaseUrl}/storage/v1/object/sign/${bucket}/${imagePath}`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        apikey: anonKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ expiresIn: 120 }),
      signal,
    },
  );
  if (!response.ok) {
    throw new HTTPError(
      "Unable to read the photo. Attach it again.",
      response.status === 401 ? 401 : 400,
    );
  }
  const data = await response.json();
  const url = data.signedURL ?? data.signedUrl;
  if (typeof url !== "string" || !url) {
    throw new Error("Unable to read the photo. Attach it again.");
  }
  if (url.startsWith("http")) return url;
  if (url.startsWith("/storage/v1")) return `${supabaseUrl}${url}`;
  return `${supabaseUrl}/storage/v1${url.startsWith("/") ? "" : "/"}${url}`;
}
async function loadCatalog(
  options: {
    token: string;
    supabaseUrl?: string;
    anonKey?: string;
    fetcher: typeof fetch;
    signal: AbortSignal;
  },
): Promise<CatalogFood[]> {
  const { token, supabaseUrl, anonKey, fetcher, signal } = options;
  const catalog = foods as CatalogFood[];
  if (!token || !supabaseUrl || !anonKey) return catalog;
  // Optional personalization has a short deadline; no new provider request is needed for USDA.
  const localAbort = new AbortController();
  const cancel = () => localAbort.abort();
  signal.addEventListener("abort", cancel, { once: true });
  const timer = setTimeout(cancel, 1500);
  try {
    const select =
      "id,name,is_meal,serving_size,serving_unit,calories_per_100g,protein_per_100g,carbs_per_100g,fat_per_100g,calories_per_serving,protein_per_serving,carbs_per_serving,fat_per_serving";
    const response = await fetcher(
      `${supabaseUrl}/rest/v1/saved_foods?is_meal=eq.false&select=${select}&order=is_favorite.desc,last_used_at.desc.nullslast,id.asc&limit=60`,
      {
        headers: { Authorization: `Bearer ${token}`, apikey: anonKey },
        signal: localAbort.signal,
      },
    );
    if (!response.ok) return catalog;
    const rows: Record<string, unknown>[] = await response.json();
    return [
      ...rows.map(libraryFood).filter((food): food is CatalogFood =>
        food !== null
      ),
      ...catalog,
    ];
  } catch {
    return catalog;
  } finally {
    clearTimeout(timer);
    signal.removeEventListener("abort", cancel);
  }
}

export async function readModelStream(
  body: ReadableStream<Uint8Array>,
  onDelta: (text: string) => void,
) {
  const reader = body.getReader();
  const decoder = new TextDecoder();
  let buffer = "", output = "", completed = false;
  let responseId: string | undefined;
  let usage: unknown;
  const parse = (raw: string) => {
    const data = raw.split(/\r?\n/).filter((line) => line.startsWith("data:"))
      .map((line) => line.slice(5).trimStart()).join("\n");
    if (!data || data === "[DONE]") return;
    const event = JSON.parse(data);
    if (event.type === "response.output_text.delta") {
      output += event.delta;
      onDelta(output);
    } else if (event.type === "response.completed") {
      if (event.response?.status !== "completed") {
        throw new Error("Meal analysis did not complete. Try again.");
      }
      completed = true;
      responseId = event.response.id;
      usage = event.response.usage;
    } else if (
      ["response.failed", "response.incomplete", "error"].includes(event.type)
    ) {
      throw new Error(
        event.type === "response.incomplete"
          ? "Meal analysis was incomplete. Try again with fewer foods or clearer details."
          : "Meal model failed. Try again.",
      );
    } else if (event.type === "response.refusal.delta") {
      throw new Error(
        "This input couldn't be analyzed. Try a food photo or description.",
      );
    }
  };
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) {
        buffer += decoder.decode();
        break;
      }
      buffer += decoder.decode(value, { stream: true });
      let match;
      while ((match = /\r?\n\r?\n/.exec(buffer))) {
        parse(buffer.slice(0, match.index));
        buffer = buffer.slice(match.index + match[0].length);
      }
    }
    if (buffer.trim()) parse(buffer);
    if (!completed) {
      throw new Error(
        "The connection ended before analysis completed. Try again.",
      );
    }
    return {
      value: JSON.parse(output) as MealReading | LabelReading,
      responseId,
      usage,
    };
  } finally {
    await reader.cancel().catch(() => {});
    reader.releaseLock();
  }
}

// Only closed item objects become previews; escaped quotes and nested macros are preserved.
export function completedMealItems(text: string): MealReading["items"] {
  const match = /"items"\s*:\s*\[/.exec(text);
  if (!match) return [];
  const result: MealReading["items"] = [];
  let depth = 0, start = -1, quoted = false, escaped = false;
  for (let i = match.index + match[0].length; i < text.length; i++) {
    const char = text[i];
    if (quoted) {
      if (escaped) escaped = false;
      else if (char === "\\") escaped = true;
      else if (char === '"') quoted = false;
      continue;
    }
    if (char === '"') quoted = true;
    else if (char === "{") { if (depth++ === 0) start = i; }
    else if (char === "}" && --depth === 0 && start >= 0) {
      try {
        result.push(JSON.parse(text.slice(start, i + 1)));
      } catch {
        return result;
      }
    } else if (char === "]" && depth === 0) break;
  }
  return result;
}
