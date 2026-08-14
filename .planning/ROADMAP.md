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

**Plans:** 3/3 plans complete

Plans:
- [x] 09-01-PLAN.md — Filter soft-deleted rows out of training_snapshot.dart/analytics_repository.dart; rewrite balance_analyzer.dart and biometric_correlations.dart for effective load, drop mock fallback
- [x] 09-02-PLAN.md — Retarget remaining providers onto trainingSnapshotProvider; delete dead cnsFatigueProvider/muscleRecoveryProvider and the duplicate recovery card
- [x] 09-03-PLAN.md — Automated regression test proving soft-deleted sets are excluded from analytics

## Phase 10: Assisted rep tracking

**Goal:** Add an opt-in, on-device rep counter for pull-ups and dips that *proposes* a rep count — and, once calibrated, an RPE — at the end of a set, which the user reviews and confirms or edits. The tracker can never write a set.

**Requirements:** REP-01–06

**Depends on:** Phase 9 (merge order only — Phase 9 adds no tables, this phase takes schema v26)

**Success:** Nothing under `lib/features/reps/` imports `workouts_repository.dart` or references `updateSet`, enforced by a static test; the authoritative detector is pure Dart on the phone and the Kotlin watch counter is provisional-only and never persisted; the three new tables are local-only with no `SyncColumns`/tombstones/outbox triggers and raw samples are discarded at set end; an RPE is offered only past the n ≥ 10 / ≥ 3 sessions / LOO MAE ≤ 1.0 gate; and recorded pull-up and dip traces verify counting accuracy, missed reps, false-positive resistance and the never-auto-complete guarantee.

**Plans:** 6/7 plans executed

Plans:
- [x] 10-01-PLAN.md — Schema v26, RepMovement, consent/eligibility state, rep tracking repository (wave 1)
- [x] 10-03a-PLAN.md — Wear Kotlin capture, both WearSyncPaths copies, phone-side routing (wave 1, Gradle-verified)
- [ ] 10-02-PLAN.md — Pure-Dart rep detection engine and recorded trace fixtures (wave 2, Tasks 1-4 done, blocking human fixture-recording checkpoint remains)
- [x] 10-03b-PLAN.md — Dart capture service, RepSuggestion/TrackerState contract, phone motion source (wave 3)
- [x] 10-04-PLAN.md — Consent flow, live counter, review-and-confirm sheet (wave 4)
- [x] 10-05-PLAN.md — Calibration learning and LOO-gated RPE suggestion (wave 5)
- [x] 10-06-PLAN.md — In-app fixture-recording debug tool: checklist, capture flow, export (wave 6, does not close REP-06 itself)

**Risk:** 10-02 is gated on a human task — recording real pull-up and dip traces on both a watch and a pocketed phone with ground-truth counts. Synthetic traces cannot meet the accuracy bar. 10-06 makes this easier to do opportunistically across real workouts but does not remove the requirement for a human to actually perform them.

## Later — Samsung Now Bar, recipe import, meal planning, social, voice

**Requirements:** NOWBAR-01–03, PLAN-01–02, SOC-01, VOICE-01

- **Samsung Now Bar Live Update (Deferred to January):** Upgrade the ongoing workout surface into a native Android 16 (API 36) `requestPromotedOngoing(true)` / `ProgressStyle` Live Update and collapse notification publishers.
- **Recipe import & meal planning**
- **Social & voice**

**Scope fence:** Do not add these before the local catalogue, trustworthy diary foundation, and release blockers are verified.
