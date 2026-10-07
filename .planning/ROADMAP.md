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

## Phase 11: Gym Buddy — live shared workout

**Goal:** Let two people train the same workout together in real time. One shares an active workout, the other joins by scanning a QR code from the `+` button, and from then on the exercise list stays in step between them — while each person's sets, reps, weights and measurements stay entirely their own.

**Requirements:** BUD-01–06

**Depends on:** Nothing functionally. Takes local schema v29 and a new Supabase migration; v26–v28 were already spoken for by the time this landed.

**Success:** Two phones running a shared session see the same exercise list within a second of any change; a change made with scope "only me" provably does not appear on the partner's device while "both" does; each participant's `WorkoutSessions` row is owned and synced by them alone, and a test proves no partner-owned set row is ever written into the other's tables or counted in their analytics; killing and reopening the app on one phone restores the shared exercise list from the durable event log rather than an empty session; and a static test proves `0003_sync_rls.sql`'s owner-only policies are unmodified, with cross-user reads confined to the new buddy tables.

**Plans:** 11/11 plans executed — corrected 2026-09-02, see the note below

> **The plan ledger below was badly stale.** It showed waves 4–9 unchecked and
> `REQUIREMENTS.md` showed all six BUD requirements as `[ ]`, but a session
> that afternoon (2026-08-18/19) had already built essentially the entire
> feature: `lib/features/buddy/` (18 files) with 74 passing tests covering
> the gateway, channel service, choreography sender/applier, session
> controller (host/join/leave/endForEveryone), and full UI (share sheet,
> QR scanner, presence bar, scope toggle) — all wired into
> `active_workout_view.dart` and the `+` quick-add menu. Nobody had gone back
> and ticked the boxes. Re-verified 2026-09-02 by reading the actual code and
> running the actual test suite rather than trusting this ledger; see
> `REQUIREMENTS.md`'s BUD-01–06 entries for the evidence behind each mark.
>
> Two real gaps were found and closed in that same pass:
> - **App-restart resume was missing** (BUD-04's "killing and reopening the
>   app restores the shared exercise list" half). `BuddySessionController`
>   only ever populated its state from a fresh host/join UI action, so a
>   killed-and-reopened app silently dropped out of a live session even
>   though the durable event log and `buddy_sessions_local`'s persisted
>   `lastSeenSeq` were sitting right there. Added `resumeIfActive()`, called
>   once at app startup (`app.dart`, same idiom as the fasting-schedule
>   rehydrate next to it); tested in
>   `test/buddy/buddy_session_controller_test.dart`.
> - **No analytics non-interference test** (BUD-02's second half, 11-11's
>   stated scope). Added `test/buddy/buddy_analytics_isolation_test.dart`,
>   which pins that `TrainingSnapshot.load` — the shared data path every
>   volume/analytics view has built on since the Phase 9 consolidation —
>   never filters, weights or groups on `buddySessionId`; the field is inert
>   to it by construction.
>
> **11-05 is written but not yet green.** `test/sync/live_buddy_test.dart`
> exists (5 tests, exactly per `11-05-PLAN.md` Task 2) and self-skips
> cleanly without credentials, but running it live surfaced a pre-existing,
> unrelated bug: `.secrets/live_sync.json`'s `SUPABASE_URL` points at
> `jioesomepkauponjrena` (SummitSki) rather than `ldzgyzigvbwofbswitrv`
> (Herculex, where migration 0011 actually lives — confirmed live via
> `npx supabase migration list` and a direct `pg_proc` query, so this is not
> a schema-cache issue). Blocked on the correct anon key for the Herculex
> project.

Plans:
- [x] 11-01-PLAN.md — Supabase CLI install, project link, migration workflow doc (wave 1)
- [x] 11-02-PLAN.md — Wire contract, scope enum on the far side of the boundary, publisher seam, the two structural gates (wave 1)
- [x] 11-03-PLAN.md — Drift v29: buddy mirror tables (local-only) and WorkoutSessions.buddySessionId (wave 2)
- [x] 11-04-PLAN.md — Supabase 0011: buddy tables, plpgsql participation helper, three RPCs, broadcast-from-DB trigger (wave 2)
- [~] 11-05-PLAN.md — db push done (0011 applied to `ldzgyzigvbwofbswitrv` 2026-08-18, recorded in `docs/supabase-migrations.md`); `test/sync/live_buddy_test.dart` written 2026-09-02 but blocked on `.secrets/live_sync.json` pointing at the wrong project (wave 3)
- [x] 11-06-PLAN.md — Gateway (`buddy_remote_gateway.dart`), private channel service (`buddy_channel_service.dart`), and the pure ordering machine (`buddy_event_stream.dart`) (wave 4)
- [x] 11-07-PLAN.md — The applier (`buddy_choreography_applier.dart`): slot mapping, placeholders, replay, and the BUD-06 remove gate (wave 5)
- [x] 11-08-PLAN.md — The sender (`buddy_choreography_sender.dart`): share policy, scope as control flow (wave 6)
- [x] 11-09-PLAN.md — Session lifecycle (`buddy_session_controller.dart`): host, join with auto-start, leave, teardown, Riverpod wiring, plus the 2026-09-02 resume-on-restart addition (wave 7)
- [x] 11-10-PLAN.md — UI: share sheet with QR (`buddy_share_sheet.dart`), scan-to-join in the + menu (`buddy_join_scanner_view.dart`), scope toggle, presence bar and notices (wave 8)
- [x] 11-11-PLAN.md — BUD-02 isolation proof across two devices (`buddy_two_device_test.dart`) and analytics non-interference (`buddy_analytics_isolation_test.dart`, added 2026-09-02) (wave 9)

**Scope fence:** MVP is the live shared session only. VS comparison in history (BUD-07), the persistent friends model (BUD-08) and challenges (BUD-09) are deliberately deferred — they are separate phases that build on this one. Do not add a friends list, a challenge model or history comparison screens in this phase; the QR join token is a session token, not a relationship.

## Phase 12: Exercise catalogue integrity and real logging metrics

**Goal:** Make the exercise list say one thing per movement, cover the training styles the app claims to support, and record each exercise in the unit it is actually measured in — a sled push in metres and kilos, not reps.

**Requirements:** EXR-01–05

**Depends on:** Local schema v31 (v29 went to Gym Buddy and v30 to the rep-tracking switch — the switch itself is gone, but the version number stays allocated to it historically — so 12-04 took v31 and Supabase 0013). Plan 12-04 touches `active_exercise_card.dart`, which UI-rework Phase 7 wants to split; that split is unblocked now that rep tracking is gone.

**Success:** Searching "bench" returns one Bench Press that expands to its six bars rather than six top-level rows; `cardio`, `crossfit` and `mobility` are all non-empty and a test keeps them that way; every `loggingMetric` in the asset resolves against the `LoggingMetric` registry; and a Sled Push logs weight × distance while a Plank logs a duration, both round-tripping through history without inflating tonnage.

**Plans:** 5/5 plans complete

Plans:
- [x] 12-01-PLAN.md — Movement layer completion: grip/attachment clustering, plainness tokens, canonical ranking (wave 1)
- [x] 12-02-PLAN.md — Coverage: 51 cardio, Olympic, CrossFit and mobility rows (wave 1)
- [x] 12-03-PLAN.md — `LoggingMetric` registry, metric corrections, catalogue invariant tests (wave 1)
- [x] 12-04-PLAN.md — Drift **v31** + Supabase **0013**: `durationSeconds`, `distanceM`, `calories` on `set_entries` (wave 2). Landed without a plan file; v30/0012 were taken by the rep-tracking switch and the product catalogue respectively.
- [x] 12-05-PLAN.md — Metric-driven set-entry UI; tonnage exclusion for distance/cardio sets (wave 3, sequenced after rep tracking's `active_exercise_card.dart` wiring to avoid a merge conflict — that wiring is since removed)

**Scope fence:** Non-destructive. No catalogue row is deleted and no `set_entries.exercise_id` is remapped — variants stay as rows and the picker collapses them through `movementSlug`. Rounds-based work (AMRAP, EMOM, For Time) stays in `SetType` + `set_type_meta_json`; it does not become a logging metric.

## Phase 13: Hercul — the coaching layer

**Goal:** Turn the analytics the app already computes into something that talks. A dashboard card where Hercul says what he sees — CNS load, neglected muscles, missed protein, a stalled cut — in one of two voices the user picks.

**Requirements:** HRC-01–05

**Depends on:** Phase 12 for the movement layer that ergonomics rules key on. Reads existing engines only; adds no new analytics.

**Success:** `HerculEngine.evaluate` is a pure function over a `HerculContext` and a rule list, unit-tested per rule; a rule whose signals are missing is skipped rather than firing wrongly on a fresh install; a fired rule does not fire again inside its cooldown; every rule in `hercul_rules.json` has both `normal` and `honest` copy, enforced by test; and the dashboard card renders the top messages with the tone the settings toggle selects.

**Plans:** 0/4 plans executed

Plans:
- [ ] 13-01-PLAN.md — `HerculContext`: signal aggregation over existing providers (wave 1)
- [ ] 13-02-PLAN.md — Rule model, JSON corpus format, evaluator, cooldown log (wave 1)
- [ ] 13-03-PLAN.md — Dashboard card, tone setting, 18+ gate (wave 2)
- [ ] 13-04-PLAN.md — Seed corpus across CNS, volume, nutrition, bodyweight and consistency (wave 2)

**Scope fence:** Not an LLM. Every message is an authored string selected by a deterministic rule over the user's own data, so it works offline and says nothing the app cannot show the numbers for. Guidance stays informational — `PROJECT.md` puts medical advice out of scope, and that fence covers Hercul.

**Tone:** Two voices. **Hercul** is plain and encouraging. **Honest Hercul** is sharp and disappointed about *training* — never about the user's body, weight or sex. The second voice is gated behind a settings toggle and an 18+ check, and carries no profanity, which keeps the store rating where it is.

## Phase 14: Anthropometric ergonomics

**Goal:** Use the height the profile already stores — and limb measurements if the user offers them — to tell people which variant of a big compound suits their proportions, instead of leaving them to wonder why their squat looks nothing like the video.

**Requirements:** ERG-01–03

**Depends on:** Phase 12 (guidance keys on `movementSlug`, so it attaches to the movement rather than to six duplicate rows) and Phase 13 (rules ride the same engine, priority and cooldown).

**Success:** A 190 cm user sees low-bar and heel-elevation guidance on the back squat and does not see it at 170 cm; guidance is absent entirely when height is unknown; every entry carries its sources; and the copy reads as a trade-off at those proportions, never as a diagnosis or a correction.

**Plans:** 0/3 plans executed

Plans:
- [ ] 14-01-PLAN.md — `inseam`, `arm_span`, `torso` measurement metrics; `anthropometry.dart` ratios (wave 1)
- [ ] 14-02-PLAN.md — `exercise_ergonomics.json` keyed on movementSlug, with sources (wave 1)
- [ ] 14-03-PLAN.md — Surface in exercise details and as Hercul rules (wave 2)

**Scope fence:** Height and optional tape measurements only. No video, no pose estimation, no form scoring — the app cannot see the lifter, and guidance that implies otherwise would be dishonest.

## Later — Samsung Now Bar, buddy VS, friends, challenges, recipe import, meal planning, voice

**Requirements:** NOWBAR-01–03, BUD-07–09, PLAN-01–02, SOC-01, VOICE-01

- **Samsung Now Bar Live Update (Deferred to January):** Upgrade the ongoing workout surface into a native Android 16 (API 36) `requestPromotedOngoing(true)` / `ProgressStyle` Live Update and collapse notification publishers.
- **Buddy VS comparison (BUD-07):** Three comparison views in workout history — who won each exercise, calisthenics rep counts, per-session volume — computed after the fact from both sessions via `buddySessionId`. Depends on Phase 11.
- **Friends model (BUD-08):** Persistent identity, search/invite, accept/block. Prerequisite for challenges.
- **Challenges (BUD-09):** Goal + deadline per participant (strength, BF%, kg lost/gained), progress read from existing measurement and training data. Depends on BUD-08.
- **Recipe import & meal planning**
- **Voice**

**Scope fence:** Do not add these before the local catalogue, trustworthy diary foundation, and release blockers are verified.
