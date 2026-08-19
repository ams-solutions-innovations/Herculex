// Sole write path for the shared/public `product_catalogue` table (see
// supabase/migrations/0012_product_catalogue.sql). The table's RLS grants no
// insert/update policy to anon/authenticated roles, so this function is the
// only thing that can ever add or correct a community product entry — it
// authenticates the caller via the platform-verified JWT (verify_jwt = true
// in config.toml) and writes with the service-role key, which bypasses RLS.

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type PublishRequest = {
  barcode?: string;
  name?: string;
  brand?: string | null;
  servingGrams?: number | null;
  servingLabel?: string | null;
  referenceBasis?: string | null;
  kcalPer100g?: number;
  proteinPer100g?: number;
  carbsPer100g?: number;
  fatPer100g?: number;
  fiberPer100g?: number | null;
  sodiumMgPer100g?: number | null;
  potassiumMgPer100g?: number | null;
  cholesterolMgPer100g?: number | null;
  source?: string;
};

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json({ error: "Method not allowed." }, 405);
  }

  if (!supabaseUrl || !serviceRoleKey) {
    return json({ error: "Product catalogue is not configured on the server." }, 503);
  }

  const contributedBy = callerUserId(req.headers.get("authorization"));
  if (!contributedBy) {
    return json({ error: "Unauthorized." }, 401);
  }

  let payload: PublishRequest;
  try {
    payload = await req.json();
  } catch {
    return json({ error: "Invalid JSON request." }, 400);
  }

  const barcode = payload.barcode?.trim();
  const name = payload.name?.trim();
  if (!barcode || !name || typeof payload.kcalPer100g !== "number") {
    return json({ error: "barcode, name and kcalPer100g are required." }, 400);
  }

  const row = {
    barcode,
    name,
    brand: payload.brand ?? null,
    kcal_per_100g: payload.kcalPer100g,
    protein_per_100g: payload.proteinPer100g ?? 0,
    carbs_per_100g: payload.carbsPer100g ?? 0,
    fat_per_100g: payload.fatPer100g ?? 0,
    fiber_per_100g: payload.fiberPer100g ?? null,
    sodium_mg_per_100g: payload.sodiumMgPer100g ?? null,
    potassium_mg_per_100g: payload.potassiumMgPer100g ?? null,
    cholesterol_mg_per_100g: payload.cholesterolMgPer100g ?? null,
    serving_grams: payload.servingGrams ?? null,
    serving_label: payload.servingLabel ?? null,
    reference_basis: payload.referenceBasis ?? "100 g",
    source: payload.source ?? "gemini",
    contributed_by: contributedBy,
    updated_at: new Date().toISOString(),
  };

  const response = await fetch(
    `${supabaseUrl}/rest/v1/product_catalogue?on_conflict=barcode`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "apikey": serviceRoleKey,
        "Authorization": `Bearer ${serviceRoleKey}`,
        "Prefer": "resolution=merge-duplicates,return=minimal",
      },
      body: JSON.stringify(row),
    },
  );

  if (!response.ok) {
    const body = await response.text();
    console.error("product_catalogue upsert failed", response.status, body);
    return json({ error: "Failed to publish product." }, 502);
  }

  return json({ ok: true });
});

/// Extracts the `sub` claim from the already-platform-verified JWT on the
/// request (verify_jwt = true means Supabase rejected the request before it
/// reached here if the signature were invalid) — no need to re-verify, only
/// to read the payload.
function callerUserId(authHeader: string | null): string | null {
  if (!authHeader?.startsWith("Bearer ")) return null;
  const token = authHeader.slice("Bearer ".length);
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  try {
    let base64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    while (base64.length % 4 !== 0) base64 += "=";
    const payload = JSON.parse(atob(base64));
    return typeof payload.sub === "string" ? payload.sub : null;
  } catch {
    return null;
  }
}

function json(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}
