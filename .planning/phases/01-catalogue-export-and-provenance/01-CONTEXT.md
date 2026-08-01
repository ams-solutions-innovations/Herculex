# Phase 1: Catalogue export and provenance - Context

**Gathered:** 2026-07-30
**Status:** Ready for planning

<domain>
## Phase Boundary

Export the user-supplied workbook into a versioned, lossless JSON asset inside the Flutter project. This phase establishes catalogue semantics and validation; it does not yet import the full catalogue into Drift or change diary UI.
</domain>

<decisions>
## Implementation Decisions

### Export format and integrity
- **D-01:** Export one JSON document with global `nutrientDefinitions` and compact per-food numeric nutrient maps. Values omit unknown fields; unknown is never represented as zero.
- **D-02:** Preserve `referenceBasis` exactly (`100 g`, `100 ml`, or legacy serving) and keep an optional labelled serving separately. Do not normalise a legacy serving with no reliable weight.
- **D-03:** Preserve barcodes as strings. No numeric parsing or country-origin inference is performed.
- **D-04:** Preserve every supplied field in semantic groups: identity, catalogue, serving, nutrients, dietary claims, allergens, provenance and quality.

### Delivery and auditability
- **D-05:** Put the generated data in `assets/data/food_database_eu.v1.json` and retain a reproducible transformer in `scripts/build_food_database_json.py`.
- **D-06:** The transformer requires an explicit input path, reads workbook data only, emits a deterministic JSON shape, and validates record count, unique IDs and representative source values.

### Claude's Discretion
- Use compact keys only where their meaning is documented in the JSON schema; keep food names and labels legible for the future server importer.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### User data and existing system
- `C:/Users/marti/OneDrive/Desktop/Food_Database_Professional_EU_Expansion_2026-07-30.xlsx` — authoritative input workbook; never mutate it.
- `lib/data/local/tables.dart` — current `Foods`, `FoodMicros`, recipes and diary schema.
- `lib/features/nutrition/data/nutrition_repository.dart` — current local-first repository still falls back to Open Food Facts; Phase 2 replaces that fallback.
- `lib/features/nutrition/domain/meal.dart` — enum meal type that Phase 3 must replace with persisted slots.
- `docs/v2/02-SCHEMA-AND-MIGRATION.md` — additive migration convention.

### Research
- `.planning/phases/01-catalogue-export-and-provenance/01-RESEARCH.md` — MyFitnessPal parity, GTIN and capture research.
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `assets/data/exercises.json`: established bundled-data convention.
- `ExerciseImporter.runFromAsset`: idempotent asset import pattern, to adapt in Phase 2.
- `NutritionRepository`: single database gateway to keep when replacing remote food lookup.

### Established Patterns
- Flutter presentation must not import Drift directly.
- Drift migrations are additive and data-preserving.

### Integration Points
- `pubspec.yaml` requires the JSON asset declaration.
- Phase 2 will import this JSON into `Foods`/`FoodMicros` or a dedicated optimised catalogue schema.
</code_context>

<specifics>
## Specific Ideas

- User wants MyFitnessPal-level macro/micro detail, multiple custom meal types and a camera-first product entry flow.
- Source workbook has 44,913 rows, 87 columns, 29,729 barcode values; 15,184 rows lack a barcode and need search/manual capture in later phases.
</specifics>

<deferred>
## Deferred Ideas

- Local FTS search, server contract, barcode runtime and full UI: Phase 2.
- User-customisable breakfast/lunch/pre-workout/post-workout slots: Phase 3.
- Nutrient dropdown/targets/availability: Phase 4.
- OCR and visual/internet analysis: Phase 6. The hard-coded external AI key is a security issue to remove then; no key may ship in source.
</deferred>

---
*Phase: 1-catalogue-export-and-provenance*
*Context gathered: 2026-07-30*
