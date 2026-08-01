# Phase 4: Full nutrient ledger and insights — Summary

**Completed:** 2026-07-30

- Added additive `portionAmount`/`portionUnit` fields to food diary entries and migrated the local database to schema v16.
- Made calculations basis-aware for 100 g, 100 ml and labelled legacy servings; gram input for a legacy serving uses the known serving weight when available.
- Preserved the complete source nutrient map in `DailyTotals.micros`, with missing values represented as unavailable rather than zero.
- Added a persisted nutrient selection screen at `/nutrition-nutrients`, linked from Edit nutrients/Goals, with units and availability-safe rendering in the diary.
- Recipes now aggregate source micronutrients as well as macros.
- Logging UI now displays the food’s actual reference basis instead of fabricating “100 g”.

Verification:

- `flutter analyze lib/features/nutrition lib/app/router.dart` — no issues.
- `flutter test test/food_catalogue_importer_test.dart test/phase5_nutrition_test.dart` — all 16 tests passed, including 100 ml and legacy-serving scaling cases.
