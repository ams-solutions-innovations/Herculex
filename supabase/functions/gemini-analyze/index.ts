const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

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

const geminiApiKey = Deno.env.get("GEMINI_API_KEY");
const geminiModel = Deno.env.get("GEMINI_MODEL") ?? "gemini-2.0-flash";
const supabaseUrl = Deno.env.get("SUPABASE_URL");
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

/// Dnevna kvota Gemini klicev na uporabnika, skupno cez vse `kind`-e.
/// Nastavljiva prek projektne skrivnosti, da je ni treba redeployati.
///
/// Zakaj sploh obstaja: do migracije 0018 ni bilo NOBENEGA stevca. Vsak
/// prijavljen uporabnik je lahko poslal sliko v zanki in edini signal bi bil
/// racun od Googla ob koncu meseca. 50/dan je vec, kot jih realen uporabnik
/// porabi (nekaj obrokov + kaksna naprava), in dovolj malo, da je skripta
/// neuporabna.
const dailyLimit = Number(Deno.env.get("GEMINI_DAILY_LIMIT") ?? "50");

/// Najvecja base64 dolzina ene slike. Base64 je +33 %, torej je to ~1,9 MB
/// izvirnika. Prej je bila meja 12 MB (~9 MB izvirnika) — cisto po
/// nepotrebnem: Gemini slike interno skalira, tako da je edini ucinek vecje
/// slike vec prenesenih bajtov in vec zaracunanih tokenov. Klient naj
/// stisne na <= 1600 px, preden posilja.
const maxImageBase64 = 2_600_000;

/// Koliko slik sme en zahtevek nositi. `body_fat_estimate` in
/// `dream_physique` sta edina, ki jih sprejmeta vec; brez meje bi lahko en
/// zahtevek sam po sebi presegel 150-sekundni wall-clock limit funkcije.
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

  // verify_jwt = true (config.toml), torej je platforma podpis ze zavrnila,
  // ce ni bil veljaven — tu beremo `sub` samo zato, da vemo, komu steti
  // klic. Brez identitete ni kvote, zato je to trda zahteva.
  const userId = callerUserId(req.headers.get("authorization"));
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
        error: "Daily AI limit reached.",
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
        const result = await generateJson({
          images: [image],
          promptText: foodPhotoPrompt(payload.userNote),
          temperature: 0.2,
        });
        return json({ result });
      }
      case "nutrition_label": {
        const image = validateImage(payload.image);
        if ("error" in image) return json({ error: image.error }, 400);
        const result = await generateJson({
          images: [image],
          promptText: nutritionLabelPrompt(payload.ocrText ?? ""),
          temperature: 0.1,
        });
        return json({ result });
      }
      case "exercise_identification": {
        const image = validateImage(payload.image);
        if ("error" in image) return json({ error: image.error }, 400);
        const result = await generateJson({
          images: [image],
          promptText: exerciseIdentificationPrompt(),
          temperature: 0.1,
        });
        const name = typeof result.identifiedName === "string" ? result.identifiedName.trim() : "Unknown";
        return json({ text: name || "Unknown", result });
      }
      case "supplement_photo": {
        const image = validateImage(payload.image);
        if ("error" in image) return json({ error: image.error }, 400);
        const result = await generateJson({
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
        const result = await generateGroundedJson({
          image,
          promptText: barcodeProductPrompt(barcode, payload.userNote),
        });
        return json({ result });
      }
      case "body_fat_estimate": {
        const rawImages = payload.images && payload.images.length > 0
          ? payload.images
          : (payload.image ? [payload.image] : []);
        if (rawImages.length === 0) {
          return json({ error: "At least one image is required for body fat estimation." }, 400);
        }
        if (rawImages.length > maxImages) {
          return json({ error: `At most ${maxImages} images are allowed.` }, 400);
        }
        const validImages: { mimeType: string; data: string }[] = [];
        for (const img of rawImages) {
          const validated = validateImage(img);
          if ("error" in validated) return json({ error: validated.error }, 400);
          validImages.push(validated);
        }
        const result = await generateJson({
          images: validImages,
          promptText: bodyFatPrompt(payload.biometrics, payload.userNote),
          temperature: 0.2,
        });
        return json({ result });
      }
      case "dream_physique": {
        const currentRaw = payload.currentImages && payload.currentImages.length > 0
          ? payload.currentImages
          : (payload.image ? [payload.image] : []);
        if (currentRaw.length === 0) {
          return json({ error: "Current physique image is required." }, 400);
        }
        if (currentRaw.length + 1 > maxImages) {
          return json({ error: `At most ${maxImages} images are allowed.` }, 400);
        }
        if (!payload.targetImage) {
          return json({ error: "Target/dream physique image is required." }, 400);
        }
        const targetValid = validateImage(payload.targetImage);
        if ("error" in targetValid) return json({ error: targetValid.error }, 400);

        const allImages: { mimeType: string; data: string }[] = [];
        for (const img of currentRaw) {
          const validated = validateImage(img);
          if ("error" in validated) return json({ error: validated.error }, 400);
          allImages.push(validated);
        }
        allImages.push(targetValid);

        const result = await generateJson({
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
        const result = await generateJson({
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
    console.error("gemini-analyze failed", error);
    return json({ error: "Gemini analysis failed. Please try again." }, 502);
  }
});

function validateImage(raw: GeminiRequest["image"]):
  | { mimeType: string; data: string }
  | { error: string } {
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

async function generateJson({
  images,
  promptText,
  temperature,
}: {
  images: { mimeType: string; data: string }[];
  promptText: string;
  temperature: number;
}): Promise<Record<string, unknown>> {
  const text = await generate({
    images,
    promptText,
    temperature,
    responseMimeType: "application/json",
  });
  const parsed = JSON.parse(text);
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("Gemini returned non-object JSON.");
  }
  return parsed as Record<string, unknown>;
}

async function generateText({
  images,
  promptText,
  temperature,
}: {
  images: { mimeType: string; data: string }[];
  promptText: string;
  temperature: number;
}): Promise<string> {
  return generate({ images, promptText, temperature });
}

async function generate({
  images,
  promptText,
  temperature,
  responseMimeType,
  tools,
}: {
  images: { mimeType: string; data: string }[];
  promptText: string;
  temperature: number;
  responseMimeType?: string;
  tools?: Record<string, unknown>[];
}): Promise<string> {
  return (await generateRaw({
    images,
    promptText,
    temperature,
    responseMimeType,
    tools,
  })).text;
}

/// Same call as [generate], but hands back the whole response root as well.
///
/// Only the grounded barcode path needs it: the model's own answer is not
/// evidence of anything, but the `groundingMetadata` it returns names the
/// pages it actually read. Those URLs are what makes a disputed catalogue
/// entry adjudicable later — without them a wrong number is unfalsifiable.
async function generateRaw({
  images,
  promptText,
  temperature,
  responseMimeType,
  tools,
}: {
  images: { mimeType: string; data: string }[];
  promptText: string;
  temperature: number;
  responseMimeType?: string;
  tools?: Record<string, unknown>[];
}): Promise<{ text: string; root: Record<string, unknown> }> {
  const parts: Record<string, unknown>[] = [{ text: promptText }];
  for (const img of images) {
    parts.push({
      inline_data: {
        mime_type: img.mimeType,
        data: img.data,
      },
    });
  }

  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${geminiModel}:generateContent`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-goog-api-key": geminiApiKey!,
      },
      body: JSON.stringify({
        contents: [{ parts }],
        // response_mime_type (structured JSON mode) and search-grounding
        // `tools` are mutually exclusive on this API — callers pass one or
        // the other, never both (see generateGroundedJson).
        ...(tools ? { tools } : {}),
        generationConfig: {
          temperature,
          ...(responseMimeType ? { response_mime_type: responseMimeType } : {}),
        },
      }),
      signal: AbortSignal.timeout(35000),
    },
  );

  if (!response.ok) {
    throw new Error(`Gemini HTTP ${response.status}`);
  }

  const root = await response.json();
  const text = root?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (typeof text !== "string" || text.trim().length === 0) {
    throw new Error("Gemini returned an empty response.");
  }
  return { text, root };
}

/// Pulls the source URLs out of a grounded response, if there are any.
function groundingSources(root: Record<string, unknown>): string[] {
  try {
    // deno-lint-ignore no-explicit-any
    const chunks = (root as any)?.candidates?.[0]?.groundingMetadata
      ?.groundingChunks;
    if (!Array.isArray(chunks)) return [];
    const urls: string[] = [];
    for (const chunk of chunks) {
      const uri = chunk?.web?.uri;
      if (typeof uri === "string" && uri.length > 0) urls.push(uri);
    }
    return urls.slice(0, 10);
  } catch {
    return [];
  }
}

/// Grounded lookup for `barcode_product`: search-grounding `tools` and
/// structured JSON mode can't be requested together, so this asks for
/// grounded free text with an explicit fenced-JSON instruction and extracts
/// it. Falls back to an ungrounded structured-JSON call (degrading to
/// `{"found": false}` rather than a guess) if grounding fails or the model's
/// text doesn't contain parseable JSON.
async function generateGroundedJson({
  image,
  promptText,
}: {
  image: { mimeType: string; data: string };
  promptText: string;
}): Promise<Record<string, unknown>> {
  try {
    const { text, root } = await generateRaw({
      images: [image],
      promptText,
      temperature: 0.1,
      tools: [{ google_search: {} }],
    });
    const parsed = extractJsonObject(text);
    if (parsed) {
      const sources = groundingSources(root);
      if (sources.length > 0) parsed.groundingSources = sources;
      return parsed;
    }
    throw new Error("Grounded response did not contain valid JSON.");
  } catch (error) {
    console.error("Grounded barcode lookup failed, falling back", error);
    return await generateJson({
      images: [image],
      promptText:
        `${promptText}\n\nIf you cannot identify this product, return exactly {"found": false} instead of guessing.`,
      temperature: 0.1,
    });
  }
}

function bodyFatPrompt(biometrics?: Record<string, unknown>, userNote?: string | null): string {
  const bio = biometrics ? JSON.stringify(biometrics, null, 2) : "Ni podano";
  const note = userNote?.trim() ? `Opomba uporabnika: "${userNote.trim()}"` : "";
  return `
You are an expert sports scientist and body composition analyst for a Slovenian-language fitness app Herculex.
Analyze the provided body photo(s) and biometric data to accurately estimate Body Fat Percentage (BF%).

User biometrics:
${bio}
${note}

Visual criteria to assess:
1. Abdominal & core definition (serratus anterior, six-pack visibility, lower abdominal fat storage).
2. Vascularity (biceps, forearms, lower abs, quads).
3. Muscle striations & separation (deltoids, chest, quads).
4. Subcutaneous fat in typical storage zones (hips, love handles, lower back, inner thighs).
5. If biometrics (height, weight, sex, waist, neck, hips) are provided, compare visual assessment with anthropometric body fat models (e.g. US Navy method and BMI).

Return ONLY a JSON object:
{
  "estimatedBfPercent": 14.5,
  "bfRangeMin": 13.0,
  "bfRangeMax": 15.5,
  "confidence": 0.88,
  "explanation": "Kratek strokoven opis v slovenskem jeziku (vidna definicija zgornjih trebušnih mišic, zmerna količina maščobe na spodnjem delu trebuha)...",
  "fatDistribution": "Opis porazdelitve maščobe (npr. 'Pretežno androidna/ginoidna distribucija z zalogami na bokih')...",
  "leanMassKg": 68.4,
  "fatMassKg": 11.6,
  "recommendations": "Praktičen nasvet v slovenščini za prehrano in trening za dosego optimalne ravni maščobe."
}
`;
}

function dreamPhysiquePrompt(biometrics?: Record<string, unknown>, userNote?: string | null): string {
  const bio = biometrics ? JSON.stringify(biometrics, null, 2) : "Ni podano";
  const note = userNote?.trim() ? `Opomba uporabnika: "${userNote.trim()}"` : "";
  return `
You are an elite fitness coach and physique transformation specialist for Herculex.
The user has provided images:
- The first image(s) represent the CURRENT PHYSIQUE of the user.
- The LAST image represents the TARGET / DREAM PHYSIQUE the user aspires to achieve.

User profile and biometrics:
${bio}
${note}

Perform a rigorous, realistic comparative gap analysis between the Current Physique and Dream Physique.
Estimate:
1. Realistic timeframe in months (natural progression limits: 0.5-1kg lean mass/month for novice/intermediates, safe fat loss 0.5-1% bodyweight/week).
2. Target body fat percentage and current body fat percentage.
3. Lean muscle mass needed to gain (in kg).
4. Fat mass needed to lose or gain (in kg).
5. Total net weight delta (in kg).
6. Prioritized muscle groups to focus on (with priority level "high", "medium", or "maintenance", and specific key exercises to target lagging areas for this aesthetic).
7. Specific nutrition & caloric strategy (caloric surplus/deficit/recomposition, daily kcal target, protein intake in g/kg).
8. Training guidelines and strategic split advice.

Return ONLY a JSON object (all descriptions in Slovenian):
{
  "estimatedMonths": 8,
  "timeframeRange": "6 - 9 mesecev",
  "weightChangeKg": -2.5,
  "leanMuscleGainKg": 3.5,
  "fatLossKg": 6.0,
  "targetBfPercent": 11.0,
  "currentEstimatedBf": 17.5,
  "musclePriorities": [
    {
      "group": "Zgornji del prsi (Upper Chest)",
      "priority": "high",
      "focus": "Incline potiski z ročkami in kabli pod kotom za polnost zgornjega dela prsi"
    },
    {
      "group": "Stranske rame (Lateral Delts)",
      "priority": "high",
      "focus": "Lateralni dvigi z ročkami ali škripcem (15-20 ponovitev) za V-obliko ramen"
    },
    {
      "group": "Hrbet / Latissimus",
      "priority": "medium",
      "focus": "Široki potegi na prsi in enoročno veslanje za širino hrbta"
    },
    {
      "group": "Roke (Biceps / Triceps)",
      "priority": "medium",
      "focus": "Poudarek na dolgi glavi tricepsa (overhead extensions) in pregibih z ročkami"
    },
    {
      "group": "Noge (Kvadricepsi / Zadnje lože)",
      "priority": "medium",
      "focus": "Počepi in romunski mrtvi dvig za uravnotežen spodnji del telesa"
    }
  ],
  "nutritionStrategy": "Priporočen rahel kalorični deficit (cca 2.200 kcal/dan) z 2.0g beljakovin na kg telesne teže.",
  "trainingAdvice": "Frekvenca 4-5 treningov tedensko (npr. Upper/Lower ali Push/Pull/Legs) s poudarkom na progresivni preobremenitvi.",
  "overallAssessment": "Cilj je realno dosegljiv z doslednim treningom in discipliniranim prehranskim načrtom."
}
`;
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
    // fall through to null below
  }
  return null;
}

function barcodeProductPrompt(barcode: string, userNote?: string | null): string {
  const note = userNote?.trim()
    ? `User note: "${userNote.trim()}"`
    : "";
  return `
You are identifying a packaged retail product from a photo for a Slovenian-
language food diary. Its barcode is ${barcode}. Use Google Search to find the
real product (by barcode and/or the branding visible in the photo) and its
official nutrition facts. Never invent values — only report what you can
verify from search results or the image itself.
${note}

If you cannot confidently identify the product and its nutrition facts,
return exactly {"found": false} and nothing else.

Otherwise, return only a fenced JSON code block with this exact shape:
\`\`\`json
{
  "found": true,
  "name": "Product name",
  "brand": "Brand or null",
  "servingGrams": 100.0,
  "kcalPer100g": 0.0,
  "proteinPer100g": 0.0,
  "carbsPer100g": 0.0,
  "fatPer100g": 0.0,
  "fiberPer100g": 0.0,
  "sodiumMgPer100g": 0.0,
  "confidence": 0.0
}
\`\`\`
`;
}

function foodPhotoPrompt(userNote?: string | null): string {
  const note = userNote?.trim()
    ? `User note about quantity, ingredients or preparation: "${userNote.trim()}"`
    : "";
  return `
You are a nutrition expert analyzing a food photo for a Slovenian-language food diary.
${note}

Estimate:
1. Food or dish name in Slovenian.
2. Total serving mass in grams as estimatedServingGrams.
3. Nutrition per 100 g: kcal, protein, carbs, fat and fiber.
4. Food quality rating from 1.0 to 10.0.
5. A short Slovenian ratingReason.

Return only a JSON object:
{
  "name": "Ime obroka v slovenscini",
  "brand": "Gemini AI",
  "estimatedServingGrams": 250.0,
  "kcalPer100g": 140.0,
  "proteinPer100g": 12.0,
  "carbsPer100g": 15.0,
  "fatPer100g": 4.0,
  "fiberPer100g": 2.5,
  "rating": 8.5,
  "ratingReason": "Kratek pregled kakovosti hrane in sestave obroka."
}
`;
}

function nutritionLabelPrompt(ocrText: string): string {
  return `
You are extracting a packaged-food nutrition label. Return only valid JSON.
Use nutrition values as printed per serving, never invent missing values.
The OCR text below may contain errors; use the image to correct it.

OCR evidence:
${ocrText}

JSON schema:
{
  "name": "product name",
  "brand": "brand or null",
  "servingGrams": 100.0,
  "kcalPerServing": 0.0,
  "proteinPerServing": 0.0,
  "carbsPerServing": 0.0,
  "fatPerServing": 0.0,
  "fiberPerServing": 0.0,
  "sodiumMgPerServing": 0.0,
  "microsPerServing": {"vitamin_c": 0.0},
  "confidence": 0.0,
  "notes": "short uncertainty note"
}
`;
}

function exerciseIdentificationPrompt(): string {
  return `
You are a gym equipment and exercise biomechanics expert for Herculex fitness app.
Analyze this image of gym equipment, a fitness machine, weights, or workout station setup.

Identify:
1. The specific exercise or machine name in "identifiedName" (e.g. "Incline Dumbbell Bench Press", "Lat Pulldown", "Leg Extension Machine", "Cable Face Pull", "Plate Loaded Chest Press", "Pin Loaded Chest Press", "Smith Machine Squat", "Barbell Bicep Curl").
2. Primary muscle group in "primaryMuscle" (e.g. "Chest", "Back", "Lats", "Legs", "Quads", "Hamstrings", "Glutes", "Shoulders", "Biceps", "Triceps", "Abs", "Calves", "Traps").
3. Equipment category in "equipment" (e.g. "machine", "cable", "barbell", "dumbbell", "kettlebell", "smith", "plate-loaded", "bodyweight").
4. Movement category in "category" (e.g. "Push", "Pull", "Legs", "Core", "Cardio").
5. Confidence from 0.0 to 1.0 in "confidence".
6. Short Slovenian description in "description" (e.g. "Fitnes naprava za potisk s prsi za krepitev prsnih mišic in tricepsa.").

If the image is not gym equipment or an exercise, return:
{
  "identifiedName": "Unknown",
  "primaryMuscle": null,
  "equipment": null,
  "category": null,
  "confidence": 0.0,
  "description": "Slike ni bilo mogoče prepoznati kot fitnes napravo."
}

Return ONLY valid JSON:
{
  "identifiedName": "Lat Pulldown Machine",
  "primaryMuscle": "Lats",
  "equipment": "cable",
  "category": "Pull",
  "confidence": 0.95,
  "description": "Naprava za priteg na prsi (Lat Pulldown) za krepitev širokih hrbtnih mišic."
}
`;
}

function supplementPhotoPrompt(userNote?: string | null): string {
  const note = userNote?.trim()
    ? `Opomba uporabnika: "${userNote.trim()}"`
    : "";
  return `
You are an expert sports nutritionist and dietary supplement specialist for Herculex fitness app.
Analyze the provided photo of a dietary supplement (e.g. tub, bottle, packaging, or supplement facts / nutrition label).
${note}

Identify:
1. Product name in "name" (e.g. "Creatine Monohydrate", "Whey Protein Isolate", "Omega 3", "Vitamin D3", "Pre-Workout", "Magnezij Bisglicinat").
2. Brand or manufacturer in "brand" (e.g. "Optimum Nutrition", "MyProtein", "Battery Nutrition", "OstroVit", "Now Foods", etc. or null if unknown).
3. Recommended single dose amount in "doseAmount" (numeric value, e.g. 5.0, 30.0, 1.0, 2.0).
4. Dose unit in "doseUnit" (must be one of: 'g', 'mg', 'µg', 'ml', 'IU', 'capsule', 'scoop').
5. Nutrients provided per single dose in "nutrients" object matching supported Herculex nutrient keys in standard units:
   - "protein" (in g)
   - "fiber" (in g)
   - "sugars" (in g)
   - "saturated_fat" (in g)
   - "trans_fat" (in g)
   - "sodium" (in mg)
   - "potassium" (in mg)
   - "cholesterol" (in mg)
   - "calcium" (in mg)
   - "iron" (in mg)
   - "magnesium" (in mg)
   - "zinc" (in mg)
   - "vitamin_a" (in µg)
   - "vitamin_b12" (in µg)
   - "vitamin_c" (in mg)
   - "vitamin_d" (in µg - note: 1000 IU = 25 µg)
   - "vitamin_e" (in mg)
   - "vitamin_k" (in µg)
   - "folate" (in µg)
   - "omega_3" (in g)
   - "caffeine" (in mg)
6. Recommended schedule in "schedule": "none", "time" (e.g. for morning vitamins/omega 3), or "post_workout" (e.g. for creatine, whey protein).
7. If schedule is "time", recommended default time in "timeHHMM" (e.g. "08:00"), otherwise null.
8. A short Slovenian description/explanation in "description".
9. Confidence score from 0.0 to 1.0 in "confidence".

Return ONLY a valid JSON object:
{
  "name": "Creatine Monohydrate",
  "brand": "Optimum Nutrition",
  "doseAmount": 5.0,
  "doseUnit": "g",
  "nutrients": {
    "protein": 0.0
  },
  "schedule": "post_workout",
  "timeHHMM": null,
  "confidence": 0.95,
  "description": "Čisti mikroniziran kreatin monohidrat za povečanje moči in eksplozivnosti."
}
`;
}

function ramblerFoodPrompt(text: string, preferredMealKey?: string): string {
  const mealContext = preferredMealKey ? `Preferred or current meal slot: "${preferredMealKey}"` : "";
  return `
You are an expert nutritionist and meal analyzer for the Herculex fitness & nutrition app.
The user described what they ate or drank, either spoken (speech-to-text) or typed, in Slovenian, English, or another language.

User input:
"${text}"
${mealContext}

Analyze the food items described and extract each individual food component with realistic nutritional values (per 100g and estimated serving portion).

Rules:
1. Parse every mentioned food/beverage into an item.
2. If quantities are specified (e.g. "200g", "2 pieces", "skleda", "1 žlica", "2 jajci"), estimate the portion in grams and specify portionAmount + portionUnit.
3. If no quantity is specified, provide a typical realistic single serving (e.g., 1 banana = 120g, 1 slice bread = 40g, 1 egg = 55g, coffee with milk = 200ml, 1 steak = 200g).
4. Provide accurate macronutrient values per 100g (kcalPer100g, proteinPer100g, carbsPer100g, fatPer100g, fiberPer100g).
5. Infer the most likely meal slot ('breakfast', 'lunch', 'dinner', 'snack') if not already clear.
6. Provide names in the language used by the user (prefer Slovenian if user spoke Slovenian, English if English).

Return ONLY a JSON object:
{
  "suggestedMealKey": "breakfast",
  "summary": "Kratek povzetek obroka v slovenščini ali angleščini",
  "items": [
    {
      "name": "Pečene piščančje prsi",
      "servingGrams": 200.0,
      "portionAmount": 200.0,
      "portionUnit": "g",
      "kcalPer100g": 165.0,
      "proteinPer100g": 31.0,
      "carbsPer100g": 0.0,
      "fatPer100g": 3.6,
      "fiberPer100g": 0.0,
      "confidence": 0.95
    }
  ]
}
`;
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

/// Bere `sub` iz ze preverjenega JWT — glej isto funkcijo v
/// product-catalogue-publish.
function callerUserId(authHeader: string | null): string | null {
  if (!authHeader?.startsWith("Bearer ")) return null;
  const token = authHeader.slice("Bearer ".length);
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  try {
    let base64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    while (base64.length % 4 !== 0) base64 += "=";
    const claims = JSON.parse(atob(base64));
    return typeof claims.sub === "string" ? claims.sub : null;
  } catch {
    return null;
  }
}

/// Steje klic v `public.ai_usage` in pove, ali je dovoljen
/// (`public.ai_usage_bump`, migracija 0018).
///
/// Steje se PRED klicem na Gemini, ne po njem: ce bi steli po uspehu, bi
/// bila kvota obvod za vsakogar, ki zna sprozati zahtevke, ki padejo.
/// Neuspesen Gemini klic tako uporabnika stane eno enoto kvote — namerno.
///
/// Ce stetje samo po sebi odpove (baza nedosegljiva), zahtevek SPUSTIMO
/// naprej. AI analiza je uporabnikova funkcionalnost; izpad obracuna je
/// nasa tezava, ne njegova. Ta izbira je pomembna in namerna — ce se kdaj
/// obrne v "fail closed", naj bo to zavestna odlocitev, ne posledica
/// refaktorja.
async function bumpUsage(
  userId: string,
  kind: string,
): Promise<{ allowed: boolean; used: number; limit: number }> {
  const fallback = { allowed: true, used: 0, limit: dailyLimit };
  if (!supabaseUrl || !serviceRoleKey) return fallback;
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
      console.error("ai_usage_bump failed", response.status, await response.text());
      return fallback;
    }
    const body = await response.json();
    return {
      allowed: body?.allowed !== false,
      used: Number(body?.used ?? 0),
      limit: Number(body?.limit ?? dailyLimit),
    };
  } catch (error) {
    console.error("ai_usage_bump threw", error);
    return fallback;
  }
}
