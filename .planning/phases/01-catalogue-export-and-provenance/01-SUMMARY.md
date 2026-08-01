# Phase 1: Catalogue export and provenance — Summary

**Completed:** 2026-07-30

## Delivered

- Added `scripts/build_food_database_json.py`, a reproducible, read-only workbook exporter.
- Generated `assets/data/food_database_eu.v1.json` (49,423,750 bytes).
- Declared the new file in `pubspec.yaml` as a Flutter asset.
- Preserved all 87 source columns in documented semantic groups and 42 nutrient definitions.

## Validation evidence

- 44,913 exported food records with unique IDs.
- 29,729 barcode identifiers remain JSON strings.
- Reference bases: 43,996 `100 g`, 182 `100 ml`, 735 `Legacy serving (unverified)`.
- `LEGACY-000001` retains its serving basis and supplied 508 kcal; no fabricated conversion was applied.
- Transformer performs the same assertions after every generation.

## Next phase

Phase 2 imports this portable asset into indexed SQLite/FTS and replaces the runtime food-lookup API path.
