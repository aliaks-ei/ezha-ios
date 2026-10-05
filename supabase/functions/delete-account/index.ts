import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const BUCKET = Deno.env.get("FOOD_IMAGES_BUCKET") ?? "food-images";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonError("Method not allowed.", 405);
  }

  const token = (req.headers.get("authorization") ?? "").match(/^Bearer\s+(.+)$/i)?.[1];
  if (!token) {
    return jsonError("Missing required field: Authorization", 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) {
    return jsonError("Missing required field: SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY", 500);
  }
  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: userData, error: userError } = await admin.auth.getUser(token);
  const uid = userData?.user?.id;
  if (userError || !uid) {
    return jsonError("Invalid JWT", 401);
  }

  // Remove the user's photos first. Storage rows do not cascade from auth.users.
  while (true) {
    const { data: files, error } = await admin.storage.from(BUCKET).list(uid, { limit: 1000 });
    if (error) {
      return jsonError(`Could not list stored images: ${error.message}`, 500);
    }
    if (!files || files.length === 0) break;
    const { error: removeError } = await admin.storage
      .from(BUCKET)
      .remove(files.map((file) => `${uid}/${file.name}`));
    if (removeError) {
      return jsonError(`Could not delete stored images: ${removeError.message}`, 500);
    }
  }

  // Every public table references auth.users with on delete cascade.
  const { error: deleteError } = await admin.auth.admin.deleteUser(uid);
  if (deleteError) {
    return jsonError(`Could not delete account: ${deleteError.message}`, 500);
  }

  return new Response(JSON.stringify({ ok: true }), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
});

function jsonError(message: string, status: number) {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
