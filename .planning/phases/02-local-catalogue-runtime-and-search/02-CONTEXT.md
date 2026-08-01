# Phase 2: Local catalogue runtime and search - Context

**Gathered:** 2026-07-30
**Status:** Ready for planning

<domain>
## Phase Boundary

Make the bundled food catalogue usable at runtime: one-time idempotent import into Drift, indexed exact barcode lookup, and local name/brand search. Keep existing custom foods, recipes and diary records intact.
</domain>

<decisions>
## Implementation Decisions

- **D-01:** Seed the existing `Foods` table so existing `FoodEntries` and `NutritionRepository` remain compatible; add source/basis/provenance fields additively.
- **D-02:** Use a `FoodCatalogueMeta` marker with schema version and expected count. Import is idempotent and never re-imports a complete catalogue on every app launch.
- **D-03:** Import in batches inside one transaction. Missing nutrient fields remain null in the source JSON; legacy serving values are labelled and not silently converted.
- **D-04:** Local lookup is authoritative. The Open Food Facts client remains injectable for old tests/compatibility but is not called by normal search or barcode lookup.
- **D-05:** Search uses exact barcode first, then case-insensitive name/brand `LIKE` with a deterministic limit; Phase 3 adds FTS and filters.

### Claude's Discretion

- Keep the full source nutrient/provenance payload in JSON columns for Phase 4 expansion, while mirroring current macro columns for existing totals.
</decisions>

<canonical_refs>
- `assets/data/food_database_eu.v1.json` — bundled source catalogue.
- `scripts/build_food_database_json.py` — export schema and validation.
- `lib/data/local/tables.dart` — existing Foods and FoodMicros tables.
- `lib/data/local/database.dart` — additive Drift migration conventions.
- `lib/features/nutrition/data/nutrition_repository.dart` — repository facade and current API fallback.
- `docs/v2/02-SCHEMA-AND-MIGRATION.md` — additive migration policy.
</canonical_refs>

<code_context>
- `Foods` already backs `FoodEntries`, recipes and all current macro calculations.
- `OpenFoodFactsClient` is currently injected into `NutritionRepository`; normal runtime calls will stop using it in this phase.
- `assets/data/exercises.json` demonstrates bundled asset conventions.
</code_context>

<deferred>
- FTS/token ranking, filters and detailed source panel: Phase 3.
- Full micro totals, selectable nutrient UI and basis-aware portion calculator: Phase 4.
</deferred>
