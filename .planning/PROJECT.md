# Herculex — Nutrition completion

## What This Is

Herculex is a Flutter fitness application. This nutrition milestone turns it into an EU-first, local-first food diary with a curated 44,913-product food database, macro and micronutrient tracking, flexible meal slots, and a fast capture flow comparable to MyFitnessPal.

## Core Value

A user can find or capture the correct food, choose a realistic portion, and log it with trustworthy nutrient totals in a few seconds.

## Requirements

### Validated

- ✓ Existing diary, food/recipe tables, macro targets, barcode camera screen and local food records — existing application.

### Active

- [ ] Ship an auditable local EU food-catalogue asset without relying on a nutrition lookup API.
- [ ] Support standard portions and custom meal-slot names/order/count.
- [ ] Display and track selectable macro and micronutrients with explicit units and data-quality state.
- [ ] Provide reliable offline barcode lookup, label OCR with edit-before-save, and an optional photo-analysis fallback.

### Out of Scope

- Medical diagnosis or personalised medical advice — nutrition data must remain informational.
- Silent AI or OCR logging — every extracted value requires user confirmation.
- Runtime dependence on Open Food Facts or another nutrition API — the owned catalogue is the primary source.

## Constraints

- **Stack**: Flutter + Drift/SQLite; preserve all existing diary records.
- **Data integrity**: The supplied workbook is source-of-truth input; do not fabricate a 100 g conversion when the row is a legacy serving.
- **Privacy**: Barcode recognition and label OCR should run on-device where feasible; photo/internet analysis must be opt-in and disclose upload.
- **Licensing**: Before public server distribution, verify the redistribution rights of the embedded USDA/Open Food Facts and user-provided source data.

## Key Decisions

| Decision | Rationale | Outcome |
|---|---|---|
| Local catalogue first | User supplied a curated EU data set; search/scan must work without the nutrition API. | Pending |
| Preserve source basis | 735 rows are unverified serving-basis values, so coercing them to 100 g would be misleading. | Pending |
| Custom meal slots are data, not an enum | Users need repeated breakfasts/lunches and pre/post-workout entries. | Pending |
| Human confirmation after capture | Barcode, OCR and visual recognition can be wrong. | Pending |

---
*Last updated: 2026-07-30 after nutrition planning initialization*
