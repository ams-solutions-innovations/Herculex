// Prompti za `gemini-analyze`.
//
// Loceni od `index.ts` iz enega razloga: to niso besedila, ampak POGODBE s
// klientom. Kljuci, ki jih tu nastejemo, se na Dart strani berejo dobesedno
// in brez preslikave — `supplementPhotoPrompt`-ov seznam hranil se mora
// ujemati s `lib/features/nutrition/domain/nutrient_definitions.dart`, ker
// `supplement_edit_sheet.dart` dela `{..._nutrients, ...result.nutrients}`.
// Ce iz prompta odstranis nasteti seznam kljucev, si bo model izmislil
// svoja imena, hranila bodo tiho izpadla, in nikjer ne bo napake.
//
// Zato: skrajsevanje teh promptov ni ciscenje. Preden karkoli odstranis,
// preveri, kdo tisto polje bere.

export function foodPhotoPrompt(userNote?: string | null): string {
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

export function nutritionLabelPrompt(ocrText: string): string {
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

export function barcodeProductPrompt(
  barcode: string,
  userNote?: string | null,
): string {
  const note = userNote?.trim() ? `User note: "${userNote.trim()}"` : "";
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

export function exerciseIdentificationPrompt(): string {
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

export function supplementPhotoPrompt(userNote?: string | null): string {
  const note = userNote?.trim() ? `Opomba uporabnika: "${userNote.trim()}"` : "";
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

export function bodyFatPrompt(
  biometrics?: Record<string, unknown>,
  userNote?: string | null,
): string {
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

export function dreamPhysiquePrompt(
  biometrics?: Record<string, unknown>,
  userNote?: string | null,
): string {
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

export function ramblerFoodPrompt(
  text: string,
  preferredMealKey?: string,
): string {
  const mealContext = preferredMealKey
    ? `Preferred or current meal slot: "${preferredMealKey}"`
    : "";
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
