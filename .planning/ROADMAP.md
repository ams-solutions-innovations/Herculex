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

## Phase 9: Analytics consolidation and soft-delete correctness

**Goal:** Make Insights report one correct number per metric, sourced from the shared effective-load snapshot, and make sure sync tombstones (`deletedAt`) can never inflate analytics after a cross-device delete.

**Requirements:** ANLY-01–04

**Success:** `analytics_providers.dart` has one recovery/CNS/balance/correlation data path (`trainingSnapshotProvider`), the legacy `muscle_recovery.dart` + `cns_fatigue.dart` engines and the duplicate recovery card in `insights_view.dart` are removed, every analytics query excludes soft-deleted rows, and push/pull + biometric-correlation cards use effective load (bands/chains/bodyweight included) instead of raw weight.

**Plans:** 3 plans

Plans:
- [ ] 09-01-PLAN.md — Filter soft-deleted rows out of training_snapshot.dart/analytics_repository.dart; rewrite balance_analyzer.dart and biometric_correlations.dart for effective load, drop mock fallback
- [ ] 09-02-PLAN.md — Retarget remaining providers onto trainingSnapshotProvider; delete dead cnsFatigueProvider/muscleRecoveryProvider and the duplicate recovery card
- [ ] 09-03-PLAN.md — Automated regression test proving soft-deleted sets are excluded from analytics

## Later — Samsung Now Bar, recipe import, meal planning, social, voice

**Requirements:** NOWBAR-01–03, PLAN-01–02, SOC-01, VOICE-01

- **Samsung Now Bar Live Update (Deferred to January):** Upgrade the ongoing workout surface into a native Android 16 (API 36) `requestPromotedOngoing(true)` / `ProgressStyle` Live Update and collapse notification publishers.
- **Recipe import & meal planning**
- **Social & voice**

**Scope fence:** Do not add these before the local catalogue, trustworthy diary foundation, and release blockers are verified.
