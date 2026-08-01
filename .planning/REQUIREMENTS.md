# Requirements: Herculex Nutrition completion

**Defined:** 2026-07-30
**Core Value:** Find or capture the correct food, choose a realistic portion, and log it with trustworthy nutrient totals in seconds.

## v1 Requirements

### Catalogue and search

- [ ] **CAT-01**: App contains an export of all source workbook food rows with source, basis, nutrient, allergen and quality metadata preserved.
- [ ] **CAT-02**: Exact barcode lookup treats barcode identifiers as strings and works offline.
- [ ] **CAT-03**: Search ranks exact barcode/name/brand matches ahead of partial matches and supports brand/category/country filters.
- [ ] **CAT-04**: User can inspect source basis, completeness and nutrients before logging.

### Diary and portions

- [ ] **DIA-01**: User can log a food by grams, millilitres where applicable, or an available labelled serving.
- [ ] **DIA-02**: User can add, rename, reorder, duplicate and delete meal slots under Edit nutrients; default slots remain Breakfast, Lunch, Dinner and Snacks.
- [ ] **DIA-03**: Diary supports recent, frequent, favourite, quick-add, copy-meal/day, timestamps, notes, saved meals, recipes and edits/deletes.

### Nutrients and goals

- [x] **NUT-01**: Each food preserves all supplied macro/micronutrients with canonical units and an explicit reference basis.
- [x] **NUT-02**: User can select nutrients shown in the diary and choose per-day/week views and targets where data exists.
- [x] **NUT-03**: Totals never imply zero when a selected nutrient is unavailable; UI displays availability/completeness.

### Capture

- [x] **CAP-01**: Barcode scan validates/normalizes EAN-8, UPC-A, EAN-13 and GTIN-14 and offers manual entry on a miss.
- [x] **CAP-02**: A label-photo OCR flow maps nutrition-label values into an editable draft before saving/logging.
- [x] **CAP-03**: Food-photo analysis is opt-in, shows confidence and proposed foods/portions, and requires review; internet lookup is an explicit secondary mode.

## v2 Requirements

- **PLAN-01**: Recipe URL import with user review/matching.
- **PLAN-02**: Meal planner, grocery list and dietary-preference/allergen planning.
- **SOC-01**: Sharing/copying diaries across users after an account and sync model exist.
- **VOICE-01**: Voice food entry when a supported, privacy-reviewed recogniser is selected.

## Out of Scope

| Feature | Reason |
|---|---|
| MyFitnessPal subscription/paywall model | Product decision unrelated to nutrition correctness. |
| Automatic camera diagnosis/logging | Insufficiently reliable without confirmation. |
| Public food-catalogue server | User asked for a JSON export first; server contract follows. |

## Traceability

| Requirement | Phase | Status |
|---|---:|---|
| CAT-01 | 1 | Complete |
| CAT-02–04 | 2 | Complete |
| DIA-01–03 | 3 | Complete |
| NUT-01–03 | 4 | Complete |
| CAP-01 | 5 | Complete |
| CAP-02–03 | 6 | Complete |
