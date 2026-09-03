// Strezniski proxy za Gemini. Edini razlog, da ta funkcija obstaja, je
// `GEMINI_API_KEY` — klient ga ne sme nikoli imeti (RB-01,
// docs/rb01-gemini-secret-remediation.md).
//
// Kar tu NE sodi: pisanje v `product_catalogue`. Ta pot gre skozi
// `product_catalogue_submit()` RPC, ki bere `auth.uid()` sam — glej
// docs/edge-functions-prod-arhitektura.md. Mesanje AI proxyja s pisalno
// potjo v deljene podatke pomeni, da en deploy ogrozi oboje.
//
// Namerno brez `@supabase/supabase-js`. Edini klic v bazo je en RPC, ki ga
// `fetch` opravi v treh vrsticah; uvoz SDK-ja bi dodal hladen zagon in se
// eno odvisnost, ki se lahko razide (`jsr:...@2` se razresi na karkoli je
// takrat najnovejse v major 2).

import {
  barcodeProductPrompt,
  bodyFatPrompt,
  dreamPhysiquePrompt,
  exerciseIdentificationPrompt,
  foodPhotoPrompt,
  nutritionLabelPrompt,
  ramblerFoodPrompt,
  supplementPhotoPrompt,
} from "./prompts.ts";
import { callerUserId } from "../_shared/auth.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { json } from "../_shared/json.ts";

type GeminiKind =
  | "food_photo"
  | "nutrition_label"
  | "exercise_identification"
  | "supplement_photo"
  | "barcode_product"
  | "body_fat_estimate"
  | "dream_physique"
  | "rambler_food";

type GeminiImage = {
  mimeType?: string;
  data?: string;
  label?: string;
};

type GeminiRequest = {
  kind?: GeminiKind;
  text?: string;
  mealKey?: string;
  image?: GeminiImage;
  images?: GeminiImage[];
  currentImages?: GeminiImage[];
  targetImage?: GeminiImage;
  biometrics?: Record<string, unknown>;
  userNote?: string | null;
  ocrText?: string;
  barcode?: string;
};

type ValidImage = { mimeType: string; data: string };

const geminiApiKey = Deno.env.get("GEMINI_API_KEY");
const geminiModel = Deno.env.get("GEMINI_MODEL") ?? "gemini-2.0-flash";

/// Model, na katerega se zatecemo, ko primarni vrne 429 (kvota) ali 503
/// (preobremenjen). Razlika med "AI ne dela" in "AI je malo slabsi".
/// Prazna vrednost izklopi fallback.
const geminiFallbackModel = Deno.env.get("GEMINI_FALLBACK_MODEL") ??
  "gemini-2.0-flash-lite";

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

/// Dnevna kvota klicev na uporabnika, skupno cez vse `kind`-e.
/// Nastavljiva prek projektne skrivnosti, da je za spremembo ni treba
/// redeployati.
const dailyLimit = Number(Deno.env.get("GEMINI_DAILY_LIMIT") ?? "50");

/// Najvecja base64 dolzina ene slike (~1,9 MB izvirnika, ker je base64
/// +33 %). Prej 12 MB, kar je bilo brez koristi: Gemini slike interno
/// skalira, tako da je edini ucinek vecje slike vec prenesenih bajtov in
/// vec zaracunanih tokenov. Klient ze slika pri maxWidth 1024 / q85, torej
/// je ta meja daljno nad tem, kar posilja.
const maxImageBase64 = 2_600_000;

/// Zgornja meja stevila slik na zahtevek. Brez nje lahko en zahtevek sam
/// preseze 150-sekundni wall-clock limit funkcije.
const maxImages = 4;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json({ error: "Method not allowed." }, 405);
  }

  if (!geminiApiKey) {
    return json({ error: "Gemini is not configured on the server." }, 503);
  }

  // `verify_jwt = true` (config.toml) pomeni, da je platforma podpis in
  // veljavnost ze preverila — zahtevek z neveljavnim zetonom do sem sploh
  // ne pride. Zato je branje `sub` dovolj; `auth.getUser()` bi dodal se en
  // omrezni obhod na avtentikacijski streznik pri VSAKEM klicu, plus nov
  // nacin odpovedi, za nic dodatnega zagotovila.
  const userId = callerUserId(req.headers.get("Authorization"));
  if (!userId) {
    return json({ error: "Unauthorized." }, 401);
  }

  let payload: GeminiRequest;
  try {
    payload = await req.json();
  } catch {
    return json({ error: "Invalid JSON request." }, 400);
  }

  const quota = await bumpUsage(userId, payload.kind ?? "unknown");
  if (!quota.allowed) {
    return json(
      {
        error:
          `Dnevna kvota za AI analize (${quota.limit}/dan) je presežena. Poskusi jutri.`,
        used: quota.used,
        limit: quota.limit,
      },
      429,
    );
  }

  try {
    switch (payload.kind) {
      case "food_photo": {
        const image = validateImage(payload.image);
        if ("error" in image) return json({ error: image.error }, 400);
        const { result } = await generateJson({
          images: [image],
          promptText: foodPhotoPrompt(payload.userNote),
          temperature: 0.2,
        });
        return json({ result });
      }

      case "nutrition_label": {
        const image = validateImage(payload.image);
        if ("error" in image) return json({ error: image.error }, 400);
        const { result } = await generateJson({
          images: [image],
          promptText: nutritionLabelPrompt(payload.ocrText ?? ""),
          temperature: 0.1,
        });
        return json({ result });
      }

      case "exercise_identification": {
        const image = validateImage(payload.image);
        if ("error" in image) return json({ error: image.error }, 400);
        const { result } = await generateJson({
          images: [image],
          promptText: exerciseIdentificationPrompt(),
          temperature: 0.1,
        });
        const name = typeof result.identifiedName === "string"
          ? result.identifiedName.trim()
          : "Unknown";
        return json({ text: name || "Unknown", result });
      }

      case "supplement_photo": {
        const image = validateImage(payload.image);
        if ("error" in image) return json({ error: image.error }, 400);
        const { result } = await generateJson({
          images: [image],
          promptText: supplementPhotoPrompt(payload.userNote),
          temperature: 0.1,
        });
        return json({ result });
      }

      case "barcode_product": {
        const image = validateImage(payload.image);
        if ("error" in image) return json({ error: image.error }, 400);
        const barcode = payload.barcode?.trim();
        if (!barcode) return json({ error: "Barcode is required." }, 400);

        const { result, groundingSources } = await generateGroundedJson({
          image,
          promptText: barcodeProductPrompt(barcode, payload.userNote),
        });
        // `groundingSources` je edini dokaz, ki ga ta pot proizvede. Klient
        // ga nese naprej v `product_catalogue_submissions`; brez njega je
        // sporna skupna stevilka nepreverljiva.
        return json({ result, groundingSources });
      }

      case "body_fat_estimate": {
        const rawImages = payload.images && payload.images.length > 0
          ? payload.images
          : (payload.image ? [payload.image] : []);
        if (rawImages.length === 0) {
          return json(
            { error: "At least one image is required for body fat estimation." },
            400,
          );
        }
        const validated = validateImages(rawImages);
        if ("error" in validated) return json({ error: validated.error }, 400);

        const { result } = await generateJson({
          images: validated.images,
          promptText: bodyFatPrompt(payload.biometrics, payload.userNote),
          temperature: 0.2,
        });
        return json({ result });
      }

      case "dream_physique": {
        const currentRaw = payload.currentImages &&
            payload.currentImages.length > 0
          ? payload.currentImages
          : (payload.image ? [payload.image] : []);
        if (currentRaw.length === 0) {
          return json({ error: "Current physique image is required." }, 400);
        }
        if (!payload.targetImage) {
          return json(
            { error: "Target/dream physique image is required." },
            400,
          );
        }
        // Ciljna slika steje v isto mejo — zato `maxImages - 1` za trenutne.
        const validatedCurrent = validateImages(currentRaw, maxImages - 1);
        if ("error" in validatedCurrent) {
          return json({ error: validatedCurrent.error }, 400);
        }
        const targetValid = validateImage(payload.targetImage);
        if ("error" in targetValid) return json({ error: targetValid.error }, 400);

        // Vrstni red je pomemben: prompt pravi, da je ZADNJA slika cilj.
        const allImages = [...validatedCurrent.images, targetValid];

        const { result } = await generateJson({
          images: allImages,
          promptText: dreamPhysiquePrompt(payload.biometrics, payload.userNote),
          temperature: 0.2,
        });
        return json({ result });
      }

      case "rambler_food": {
        const text = payload.text?.trim() || payload.userNote?.trim();
        if (!text) {
          return json({ error: "Text description of food is required." }, 400);
        }
        const { result } = await generateJson({
          images: [],
          promptText: ramblerFoodPrompt(text, payload.mealKey),
          temperature: 0.1,
        });
        return json({ result });
      }

      default:
        return json({ error: "Unsupported Gemini analysis kind." }, 400);
    }
  } catch (error) {
    console.error("gemini-analyze failed", {
      kind: payload.kind,
      error: String(error),
    });
    return json({ error: "Gemini analysis failed. Please try again." }, 502);
  }
});

// ── Kvota ──────────────────────────────────────────────────────────────

/// Steje klic v `public.ai_usage` prek `ai_usage_bump` (migracija 0018) in
/// pove, ali je dovoljen.
///
/// Steje se PRED klicem na Gemini. Ce bi steli po uspehu, bi bila kvota
/// obvod za vsakogar, ki zna sprozati zahtevke, ki padejo — zato neuspesen
/// klic uporabnika stane eno enoto. To je namerno.
///
/// Ce odpove stetje samo (baza nedosegljiva, RPC manjka), zahtevek
/// SPUSTIMO naprej. AI analiza je uporabnikova funkcionalnost; izpad
/// obracuna je nasa tezava. Ta izbira je pomembna: ce se kdaj obrne v
/// "fail closed", naj bo to zavestna odlocitev in ne stranski ucinek
/// refaktorja.
///
/// OPOMBA: podpis RPC-ja je `(p_user_id uuid, p_kind text,
/// p_daily_limit integer)` in `p_kind` NIMA privzete vrednosti. Klic brez
/// njega pade, konca tu v fail-open veji, in kvota se tiho nikoli ne
/// uveljavi — brez sledi v logih razen enega `console.warn`.
async function bumpUsage(
  userId: string,
  kind: string,
): Promise<{ allowed: boolean; used: number; limit: number }> {
  const failOpen = { allowed: true, used: 0, limit: dailyLimit };
  if (!supabaseUrl || !serviceRoleKey) return failOpen;

  try {
    const response = await fetch(`${supabaseUrl}/rest/v1/rpc/ai_usage_bump`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "apikey": serviceRoleKey,
        "Authorization": `Bearer ${serviceRoleKey}`,
      },
      body: JSON.stringify({
        p_user_id: userId,
        p_kind: kind,
        p_daily_limit: dailyLimit,
      }),
      signal: AbortSignal.timeout(5000),
    });

    if (!response.ok) {
      console.warn("ai_usage_bump failed (failing open)", {
        status: response.status,
        body: await response.text(),
      });
      return failOpen;
    }

    // RPC vrne jsonb `{allowed, used, limit}`. Preverjati je treba
    // `body.allowed`, ne `body !== false` — objekt ni nikoli `false`, zato
    // bi taksno preverjanje vedno reklo "dovoljeno".
    const body = await response.json();
    return {
      allowed: body?.allowed !== false,
      used: Number(body?.used ?? 0),
      limit: Number(body?.limit ?? dailyLimit),
    };
  } catch (error) {
    console.warn("ai_usage_bump threw (failing open)", String(error));
    return failOpen;
  }
}

// ── Validacija slik ────────────────────────────────────────────────────

function validateImage(
  raw: GeminiImage | undefined,
): ValidImage | { error: string } {
  const mimeType = raw?.mimeType;
  const data = raw?.data;
  if (!mimeType || !data) {
    return { error: "Image is required." };
  }
  if (!["image/jpeg", "image/png", "image/webp"].includes(mimeType)) {
    return { error: "Unsupported image type." };
  }
  if (data.length > maxImageBase64) {
    return { error: "Image is too large. Compress it before uploading." };
  }
  return { mimeType, data };
}

function validateImages(
  raw: GeminiImage[],
  limit = maxImages,
): { images: ValidImage[] } | { error: string } {
  if (raw.length > limit) {
    return { error: `At most ${limit} images are allowed.` };
  }
  const images: ValidImage[] = [];
  for (const img of raw) {
    const validated = validateImage(img);
    if ("error" in validated) return { error: validated.error };
    images.push(validated);
  }
  return { images };
}

// ── Gemini ─────────────────────────────────────────────────────────────

async function generateJson({
  images,
  promptText,
  temperature,
}: {
  images: ValidImage[];
  promptText: string;
  temperature: number;
}): Promise<{ result: Record<string, unknown> }> {
  const { text } = await generate({
    images,
    promptText,
    temperature,
    responseMimeType: "application/json",
  });
  const parsed = JSON.parse(text);
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("Gemini returned non-object JSON.");
  }
  return { result: parsed as Record<string, unknown> };
}

async function generate({
  images,
  promptText,
  temperature,
  responseMimeType,
  tools,
}: {
  images: ValidImage[];
  promptText: string;
  temperature: number;
  responseMimeType?: string;
  tools?: Record<string, unknown>[];
}): Promise<{ text: string; groundingSources: string[] }> {
  const parts: Record<string, unknown>[] = [{ text: promptText }];
  for (const img of images) {
    parts.push({
      inline_data: { mime_type: img.mimeType, data: img.data },
    });
  }

  const body = JSON.stringify({
    contents: [{ parts }],
    // `response_mime_type` (strukturirani JSON nacin) in search-grounding
    // `tools` se na tem API-ju izkljucujeta — klicatelji podajo eno ali
    // drugo, nikoli obojega (glej generateGroundedJson).
    ...(tools ? { tools } : {}),
    generationConfig: {
      temperature,
      ...(responseMimeType ? { response_mime_type: responseMimeType } : {}),
    },
  });

  let response = await callGemini(geminiModel, body);

  // 429 = kvota, 503 = preobremenjen. Oboje je stanje primarnega modela,
  // ne napaka zahtevka, zato en poskus na cenejsi varianti. Vsak drug
  // status je prava napaka in gre naprej kot taka.
  if (
    !response.ok &&
    (response.status === 429 || response.status === 503) &&
    geminiFallbackModel &&
    geminiFallbackModel !== geminiModel
  ) {
    console.warn(
      `Gemini ${response.status} on ${geminiModel}, retrying on ${geminiFallbackModel}`,
    );
    response = await callGemini(geminiFallbackModel, body);
  }

  if (!response.ok) {
    throw new Error(`Gemini HTTP ${response.status}`);
  }

  const root = await response.json();
  const candidate = root?.candidates?.[0];
  const text = candidate?.content?.parts?.[0]?.text;
  if (typeof text !== "string" || text.trim().length === 0) {
    // Prazen odgovor je skoraj vedno varnostni filter, ne okvara. Razlog
    // je v `finishReason`, in brez njega v logu se ugiba.
    throw new Error(
      `Gemini returned an empty response (finishReason: ${
        candidate?.finishReason ?? "unknown"
      }).`,
    );
  }

  // Poraba tokenov v log. `ai_usage` steje klice, ne tokenov, in dokler ne
  // ves, kateri `kind` porabi koliko, ne ves, kaj te AI dejansko stane.
  const usage = root?.usageMetadata;
  if (usage) {
    console.log("gemini usage", {
      model: geminiModel,
      prompt: usage.promptTokenCount,
      output: usage.candidatesTokenCount,
      total: usage.totalTokenCount,
    });
  }

  return { text, groundingSources: extractGroundingSources(candidate) };
}

function callGemini(model: string, body: string): Promise<Response> {
  return fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-goog-api-key": geminiApiKey!,
      },
      body,
      signal: AbortSignal.timeout(35000),
    },
  );
}

/// Izlusci URL-je, ki jih je grounded iskanje dejansko prebralo.
function extractGroundingSources(candidate: unknown): string[] {
  try {
    // deno-lint-ignore no-explicit-any
    const chunks = (candidate as any)?.groundingMetadata?.groundingChunks;
    if (!Array.isArray(chunks)) return [];
    const urls: string[] = [];
    for (const chunk of chunks) {
      const uri = chunk?.web?.uri;
      if (typeof uri === "string" && uri.startsWith("http")) urls.push(uri);
    }
    // Zgornja meja: to gre v `submissions.payload` in ni razloga, da bi
    // ena oddaja nosila deset kilobajtov URL-jev.
    return urls.slice(0, 10);
  } catch {
    return [];
  }
}

/// Grounded iskanje za `barcode_product`: `tools` in strukturirani JSON
/// nacin se izkljucujeta, zato tu prosimo za grounded prosto besedilo z
/// izrecnim navodilom za ograjen JSON in ga izluscimo. Ce grounding odpove
/// ali besedilo ne vsebuje parsljivega JSON-a, pade nazaj na ungrounded
/// strukturiran klic, ki raje vrne `{"found": false}` kot ugiba.
async function generateGroundedJson({
  image,
  promptText,
}: {
  image: ValidImage;
  promptText: string;
}): Promise<{ result: Record<string, unknown>; groundingSources: string[] }> {
  try {
    const { text, groundingSources } = await generate({
      images: [image],
      promptText,
      temperature: 0.1,
      tools: [{ google_search: {} }],
    });
    const parsed = extractJsonObject(text);
    if (parsed) return { result: parsed, groundingSources };
    throw new Error("Grounded response did not contain valid JSON.");
  } catch (error) {
    console.error("Grounded barcode lookup failed, falling back", String(error));
    const { result } = await generateJson({
      images: [image],
      promptText:
        `${promptText}\n\nIf you cannot identify this product, return exactly {"found": false} instead of guessing.`,
      temperature: 0.1,
    });
    // Namerno prazno: ungrounded odgovor NIMA virov, in prazen seznam je
    // bolj posten kot seznam, ki izgleda, kot da je bil preverjen.
    return { result, groundingSources: [] };
  }
}

function extractJsonObject(text: string): Record<string, unknown> | null {
  const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/i);
  const candidate = fenced ? fenced[1] : text;
  const start = candidate.indexOf("{");
  const end = candidate.lastIndexOf("}");
  if (start === -1 || end === -1 || end <= start) return null;
  try {
    const parsed = JSON.parse(candidate.slice(start, end + 1));
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
      return parsed as Record<string, unknown>;
    }
  } catch {
    // neveljaven JSON — null spodaj
  }
  return null;
}
