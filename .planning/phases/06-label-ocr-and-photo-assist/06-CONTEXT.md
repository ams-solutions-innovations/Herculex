# Phase 6 context: label OCR and Gemini fallback

## Locked decisions

- Nutrition-label capture starts with on-device Latin-script OCR so the common
  path works without uploading packaging photos.
- OCR is considered insufficient when confidence is below 75% or one of kcal,
  protein, carbohydrate or fat is missing. In that case the same image and OCR
  evidence are sent to Gemini for correction.
- Gemini output is a draft only. The user sees source (`On-device OCR` or
  `Gemini fallback`), confidence, evidence/warnings and editable fields before
  any food or diary entry is created.
- If Gemini is unavailable or fails, the OCR draft remains available with an
  explicit warning; the app never silently invents missing values.
- Accepted label values are normalized to per-100 g and the source evidence is
  retained in `sourceMetadataJson` for later auditing.
- The existing meal-photo Gemini flow remains separate; label OCR is a distinct
  capture action in the food picker.

## Scope fence

No automatic diagnosis, no invisible logging, no internet product search and no
server-side image retention are introduced in this phase.
