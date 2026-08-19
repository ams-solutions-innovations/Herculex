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
  | "barcode_product"
  | "body_fat_estimate"
  | "dream_physique";

type GeminiImage = {
  mimeType?: string;
  data?: string;
  label?: string;
};

type GeminiRequest = {
  kind?: GeminiKind;
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

  let payload: GeminiRequest;
  try {
    payload = await req.json();
  } catch {
    return json({ error: "Invalid JSON request." }, 400);
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
        const text = await generateText({
          images: [image],
          promptText: exerciseIdentificationPrompt(),
          temperature: 0.1,
        });
        return json({ text: text.trim() || "Unknown" });
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
  if (data.length > 12_000_000) {
    return { error: "Image is too large." };
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
  return text;
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
    const text = await generate({
      images: [image],
      promptText,
      temperature: 0.1,
      tools: [{ google_search: {} }],
    });
    const parsed = extractJsonObject(text);
    if (parsed) return parsed;
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
Analyze this image of gym equipment or an exercise setup.
Identify the exercise or machine.
Return only the exercise or machine name.
If it is a chest press machine, return either "Plate Loaded Chest Press" or
"Pin Loaded Chest Press" depending on what you see.
If you do not know, return "Unknown".
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
