---
phase: 2
plan: 1
type: execute
wave: 1
depends_on: ["01-01"]
files_modified:
  - lib/data/local/tables.dart
  - lib/data/local/database.dart
  - lib/data/local/database.g.dart
  - lib/features/nutrition/data/food_catalogue_importer.dart
  - lib/features/nutrition/data/nutrition_repository.dart
  - lib/features/nutrition/presentation/nutrition_providers.dart
  - test/food_catalogue_importer_test.dart
autonomous: true
---

# Phase 2 plan: local catalogue runtime and search

1. Add additive Foods metadata (`catalogueId`, reference basis, serving amount/unit, category/country and source JSON) plus a one-row import marker table.
2. Add an idempotent asset importer that validates the catalogue schema, inserts the 44,913 foods in batches, mirrors current macro columns, and preserves complete nutrients/provenance JSON.
3. Run the importer on create and upgrade; never touch existing user foods or diary rows.
4. Make repository barcode/name search local-authoritative and retain constructor compatibility for existing tests.
5. Add importer/migration tests with a small fixture and assertions for no duplicate re-import, basis preservation and barcode string lookup.

Acceptance: a fresh test DB can import a fixture, a second import is a no-op, local barcode lookup works without HTTP, legacy serving basis survives, and existing nutrition tests remain green.
