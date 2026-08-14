const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type GeminiKind =
  | "food_photo"
  | "nutrition_label"
  | "exercise_identification";

type GeminiRequest = {
  kind?: GeminiKind;
  image?: {
    mimeType?: string;
    data?: string;
  };
  userNote?: string | null;
  ocrText?: string;
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

  const image = validateImage(payload.image);
  if ("error" in image) return json({ error: image.error }, 400);

  try {
    switch (payload.kind) {
      case "food_photo": {
        const result = await generateJson({
          image,
          promptText: foodPhotoPrompt(payload.userNote),
          temperature: 0.2,
        });
        return json({ result });
      }
      case "nutrition_label": {
        const result = await generateJson({
          image,
          promptText: nutritionLabelPrompt(payload.ocrText ?? ""),
          temperature: 0.1,
        });
        return json({ result });
      }
      case "exercise_identification": {
        const text = await generateText({
          image,
          promptText: exerciseIdentificationPrompt(),
          temperature: 0.1,
        });
        return json({ text: text.trim() || "Unknown" });
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
  image,
  promptText,
  temperature,
}: {
  image: { mimeType: string; data: string };
  promptText: string;
  temperature: number;
}): Promise<Record<string, unknown>> {
  const text = await generate({
    image,
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
  image,
  promptText,
  temperature,
}: {
  image: { mimeType: string; data: string };
  promptText: string;
  temperature: number;
}): Promise<string> {
  return generate({ image, promptText, temperature });
}

async function generate({
  image,
  promptText,
  temperature,
  responseMimeType,
}: {
  image: { mimeType: string; data: string };
  promptText: string;
  temperature: number;
  responseMimeType?: string;
}): Promise<string> {
  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${geminiModel}:generateContent`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-goog-api-key": geminiApiKey!,
      },
      body: JSON.stringify({
        contents: [
          {
            parts: [
              { text: promptText },
              {
                inline_data: {
                  mime_type: image.mimeType,
                  data: image.data,
                },
              },
            ],
          },
        ],
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
