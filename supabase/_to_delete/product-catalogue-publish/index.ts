// Vstopna tocka za edino pisalno pot v deljeno tabelo `product_catalogue`
// (glej supabase/migrations/0012_product_catalogue.sql). Tabela nima
// insert/update politike za anon/authenticated, zato je to edino, kar lahko
// kdaj doda ali popravi vnos.
//
// Od migracije 0018 ta funkcija NE pise vec neposredno v tabelo. Vsa logika
// (validacija, rate limit, konsenz, zgodovina oddaj) je v SECURITY DEFINER
// funkciji `public.product_catalogue_submit`, ki jo klicemo s service-role
// kljucem. Razlog je atomarnost: konsenz je read-modify-write, in dva
// hkratna skena istega izdelka bi tu, v TypeScriptu, oba prebrala isto
// stanje in oba pisala cez. V Postgresu je vse pod enim `for update`.
//
// Kar ostaja tu: preverjanje klicatelja (verify_jwt = true v config.toml,
// plus branje `sub`), oblika zahtevka in preslikava izidov na HTTP kode.

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
  confidence?: number | null;
  /// Viri, ki jih je grounded Gemini iskanje uporabilo. Shranijo se v
  /// `product_catalogue_submissions.payload` — brez njih ni nacina
  /// preveriti, od kod je stevilka prisla.
  evidence?: unknown;
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

  // Cenena, hitra zavrnitev ocitnih smeti, preden gremo v bazo. Prave meje
  // vsiljuje 0018 (CHECK constrainti + Atwater preverjanje v RPC-ju) — to
  // je samo zato, da ocitno napacen zahtevek ne porabi rate-limit kvote.
  if (!/^[0-9]{8,14}$/.test(barcode)) {
    return json({ error: "Barcode must be 8-14 digits." }, 400);
  }
  if (name.length < 2 || name.length > 200) {
    return json({ error: "Name must be 2-200 characters." }, 400);
  }

  const row = {
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
    evidence: payload.evidence ?? null,
  };

  const response = await fetch(
    `${supabaseUrl}/rest/v1/rpc/product_catalogue_submit`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "apikey": serviceRoleKey,
        "Authorization": `Bearer ${serviceRoleKey}`,
      },
      body: JSON.stringify({
        p_user_id: contributedBy,
        p_barcode: barcode,
        p_payload: row,
        p_source: payload.source ?? "gemini",
        p_confidence: payload.confidence ?? null,
      }),
    },
  );

  if (!response.ok) {
    const body = await response.text();
    // P0001 je rate limit, ki ga dvigne RPC. Locimo ga, ker klient nanj
    // reagira drugace kot na napako streznika (tiho odneha, ne retry-ja).
    if (body.includes("submission rate limit exceeded")) {
      return json({ error: "Too many submissions. Try again later." }, 429);
    }
    console.error("product_catalogue_submit failed", response.status, body);
    return json({ error: "Failed to publish product." }, 502);
  }

  const result = await response.json();
  // status: published | confirmed | conflict | rejected. Vsi so 200 — z
  // vidika klienta je prispevek oddan; kaj se je z njim zgodilo, je stvar
  // kataloga, ne uporabnikovega toka.
  return json({ ok: true, status: result?.status ?? "unknown" });
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
