# Phase 4: Full nutrient ledger and insights - Context

**Gathered:** 2026-07-30
**Status:** In progress

<domain>
## Phase Boundary

Make portions and nutrient totals basis-aware, preserve all source micronutrients, and let the user choose which nutrients appear in the diary summary. Missing source values remain unavailable rather than being rendered as zero.
</domain>

<decisions>
- Food records carry a portion amount/unit in addition to the legacy grams override.
- `referenceBasis` controls conversion: grams/ml use a 100-unit basis; serving-based records use the labelled serving value and are not fabricated into grams.
- Full source nutrients remain in the JSON metadata payload and are aggregated into a stable nutrient map.
- Selected nutrient IDs are persisted locally; default visible nutrients are fiber, sodium, potassium and cholesterol.
- Daily totals expose nutrient availability by presence in the map, so a missing value is distinguishable from a measured zero.
</decisions>

<canonical_refs>
- `lib/data/local/tables.dart` — FoodEntries and Foods source metadata.
- `lib/features/nutrition/data/nutrition_repository.dart` — portion and aggregate calculations.
- `lib/features/nutrition/domain/daily_totals.dart` — total model.
- `assets/data/food_database_eu.v1.json` — source nutrient definitions and basis values.
</canonical_refs>

<deferred>
- Weekly chart polish and nutrient target thresholds beyond display selection.
- OCR label extraction and photo confidence UI: Phase 6.
</deferred>
