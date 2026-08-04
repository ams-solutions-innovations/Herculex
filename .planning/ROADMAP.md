# Herculex Nutrition completion roadmap

## Phase 1: Catalogue export and provenance — Complete

**Goal:** Put the supplied workbook into the app as a lossless, versioned JSON catalogue, without changing its meaning.

**Requirements:** CAT-01, NUT-01

**Success:** 44,913 foods are exported; barcode remains a string; all 90 source columns have a schema mapping; missing values are omitted rather than converted to zero; an automated validation verifies counts and samples.

## Phase 2: Local catalogue runtime and search — Complete

**Goal:** Import/cache the asset into SQLite/FTS and replace runtime Open Food Facts dependency for search and barcode lookup.

**Requirements:** CAT-02–04

**Success:** Offline search/barcode lookup works under a reasonable device-memory budget, has filters and source/data-quality detail, and migration is additive.

## Phase 3: Flexible diary, portions and reusable entries — Complete

**Goal:** Make diary meal slots and portions user-defined, while preserving existing logs.

**Requirements:** DIA-01–03

**Success:** Edit nutrients owns meal-slot CRUD; repeated/renamed meals are supported, all existing enum logs migrate safely, and quick/recent/favourite/saved/copy flows work.

## Phase 4: Full nutrient ledger and insights — Complete

**Goal:** Calculate all available micro- and macronutrient totals accurately and expose a selectable nutrient dashboard.

**Requirements:** NUT-01–03

**Success:** Units/basis are clear, selected nutrient totals have completeness state, and day/week targets and trends work.

## Phase 5: Barcode capture hardening — Complete

**Goal:** Deliver robust offline GTIN/EAN/UPC scanning with recovery flows.

**Requirements:** CAP-01

**Success:** Camera scan, check-digit validation, manual type-in, no-result search and user correction all work; code country prefixes are never used as proof of product origin.

## Phase 6: Label OCR and photo-assist — Complete

**Goal:** Let users create reviewed foods from packaging and meal photos, without automatic or opaque logging.

**Requirements:** CAP-02–03

**Success:** OCR parsing is editable and stores evidence/confidence; visual/internet analysis is opt-in, privacy-labelled and never bypasses the review screen.

## Phase 8: Samsung Now Bar Live Update — Pending

**Goal:** Turn the prepared ongoing-workout surface into a real Android 16 Live Update so One UI can promote the active workout into the Now Bar, and collapse the two competing notification publishers into one.

**Requirements:** NOWBAR-01–03

**Success:** The renderer calls the real `requestPromotedOngoing(true)` / `ProgressStyle` / `setShortCriticalText` platform API on API 36+ instead of writing a reflective extras flag after `build()`; logcat reports `promotable=true`; a single publisher owns notification id 1 and the surface is no longer rebuilt at 1 Hz; the rest timer regains its own high-importance channel; the surface clears on workout end and on dispose. The snapshot contract, MethodChannel bridge, native action receiver, queue and Dart command helpers are unchanged — only the renderer boundary and the publish path move.

**Depends on:** the existing Now Bar adapter layer under `android/app/src/main/kotlin/com/ams/herculex/nowbar/` and `docs/now-bar-native-adapter-contract.md`.

## Later — Recipe import, meal planning, social, voice

**Requirements:** PLAN-01–02, SOC-01, VOICE-01

**Scope fence:** Do not add these before the local catalogue and trustworthy diary foundation are verified.
