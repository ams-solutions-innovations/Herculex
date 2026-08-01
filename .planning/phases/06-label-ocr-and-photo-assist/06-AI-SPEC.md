# AI-SPEC: Nutrition-label Gemini fallback

## System boundary

The deterministic local parser is the primary extractor. Gemini is a bounded
fallback for low-confidence OCR and is never allowed to write directly to the
database or diary.

## Input contract

- Packaging image supplied by the user.
- Local OCR text supplied as evidence.
- Prompt requires JSON only, per-serving values, explicit nulls for unknown
  values, and a confidence score in `[0, 1]`.

## Output contract

The client accepts product name, brand, serving grams, kcal, protein,
carbohydrate, fat, fiber, sodium, optional micronutrient map, confidence,
notes and raw evidence. Values are converted to per-100 g before persistence.

## Safety and review gates

- Gemini is called only below the local confidence threshold or when core fields
  are missing.
- The UI shows source and confidence and requires the user to edit/confirm.
- Missing values remain missing; fallback errors are surfaced as warnings.
- No image or response is sent to another service from this flow.

## Evaluation plan

- Unit fixtures cover clear English and Slovenian labels, serving conversion and
  incomplete OCR routing conditions.
- Manual UAT should include glare, rotated labels, decimal commas, multi-column
  labels and labels with missing micronutrients.
