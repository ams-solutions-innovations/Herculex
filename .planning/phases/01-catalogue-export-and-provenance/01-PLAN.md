---
phase: 1
plan: 1
type: execute
wave: 1
depends_on: []
files_modified:
  - scripts/build_food_database_json.py
  - assets/data/food_database_eu.v1.json
  - pubspec.yaml
autonomous: true
---

# Phase 1 plan: catalogue export and provenance

## Objective

Generate a portable JSON catalogue from the supplied `.xlsx` while retaining all source semantics and make it a declared Flutter asset.

## Tasks

1. Add a read-only streaming Python transformer with explicit input/output arguments and a documented schema.
2. Map each of the 87 headers into semantic JSON groups. Compact shared nutrient definitions carry canonical units; records omit missing values.
3. Preserve arbitrary barcode strings and the supplied `Reference Basis`; calculate source SHA-256 and export statistics.
4. Generate `assets/data/food_database_eu.v1.json`; register it in `pubspec.yaml`.
5. Re-read the output and verify row count, unique IDs, required identifiers, first-row nutrient mapping and barcode-as-string behaviour.

## Acceptance criteria

- Output record count is exactly the input row count (44,913).
- Metadata records all 87 mapped columns and every mapped food has an ID/name.
- `LEGACY-000001` remains serving-basis with its given macros; it is not made into 100 g data.
- A 12/13-digit barcode remains a quoted JSON string.
- No workbook is altered.

## Risks

- Source reference basis varies: preserving it is mandatory.
- A bundled JSON asset is intentionally large; Phase 2 moves the runtime query path to indexed SQLite.
