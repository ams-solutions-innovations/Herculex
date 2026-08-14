---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: in_progress
last_updated: "2026-08-14T15:30:00.000Z"
progress:
  total_phases: 10
  completed_phases: 9
  total_plans: 19
  completed_plans: 15
  percent: 79
---

# Project State

## Project Reference

See: `.planning/PROJECT.md` (updated 2026-07-30)

**Core value:** Fast, trustworthy local food logging.
**Current focus:** Phase 10 — assisted-rep-tracking

## Progress

- Source workbook analyzed: 44,913 records, 87 populated columns, 29,729 valid non-empty barcodes.
- Phases 1–6 are implemented and documented; v1 capture and nutrition foundations are complete.

## Session update — 2026-07-30

- Phase 1 catalogue export completed and validated.
- Phase 2 local catalogue runtime completed: additive Drift v15 metadata, one-time batch importer, local-authoritative barcode/name lookup, and passing importer + nutrition tests.
- Next implementation focus: Phase 3 FTS/filter UX and user-configurable meal slots.
- Phase 3 meal-slot implementation is complete.
- Phase 4 nutrient ledger is complete: basis-aware portions, source micronutrient aggregation, persisted nutrient visibility and regression coverage are green.
- Phase 5 barcode hardening is complete: supported retail formats validate locally, manual correction is available, and custom foods retain canonical codes.
- Phase 6 label capture is complete: on-device OCR routes low-confidence/incomplete labels to Gemini, keeps evidence, and requires editable review before logging.

## Session update — 2026-08-04

- Audited the Samsung Now Bar work. The full adapter layer exists and is tested — snapshot contract, MethodChannel bridge, native receiver with session/set staleness rejection, native queue, diagnostics sheet — but the renderer never produces a Live Update: it posts a `NotificationCompat` BigText notification and writes `android.requestPromotedOngoing` into `extras` reflectively after `build()`. No `ProgressStyle`, no `setShortCriticalText`, so `hasPromotableCharacteristics()` is false and no Now Bar chip can appear.
- Also found: Flutter and the native renderer both publish notification id 1 on channel `workout_live` once per second, so the native post always overwrites the Flutter fallback; the rest timer is silently downgraded by sharing that low-importance channel; and the bridge's `clear()` is never called on dispose.
- Phase 8 (Samsung Now Bar Live Update) added to ROADMAP.md with NOWBAR-01–03 in REQUIREMENTS.md, plus CONTEXT and two plans: 08-01 rewrites the renderer against the real API 36 setters, 08-02 collapses the publish path and fixes the collateral issues.
- Next implementation focus: `/gsd:execute-phase 8`.

## Session update — 2026-08-14

- Phase 8 (Samsung Now Bar) confirmed complete — all NOWBAR-01–03 requirements checked.
- Audited `lib/features/analytics/` to scope a previously-undefined "Phase 9" (only referenced in passing by `10-CONTEXT.md`, absent from ROADMAP.md/REQUIREMENTS.md). Found: a duplicate legacy recovery card stacked with the v3 recovery card in `insights_view.dart`, a dead `cnsFatigueProvider`, five providers still doing independent unfiltered `setEntries` scans instead of the shared `trainingSnapshotProvider`, and — most importantly — zero soft-delete (`deletedAt`) filtering anywhere in analytics, a latent correctness bug for cross-device sync deletes.
- Added Phase 9 (Analytics consolidation and soft-delete correctness) to ROADMAP.md and REQUIREMENTS.md (ANLY-01–04), ran phase discussion, and wrote `09-CONTEXT.md`.
- Decisions locked: delete the legacy recovery card and `muscle_recovery.dart`/`cnsFatigueProvider` outright (no fallback); ship the effective-load number changes silently, no user-facing banner; verify soft-delete correctness with an automated regression test (acceptance gate for ANLY-03).
- Note: `agents_installed` is false in this environment (no `gsd-planner`/`gsd-executor`/etc. under `.claude/agents/`) — `/gsd:plan-phase 9` may need those agents available before it can run.
- Next implementation focus: `/gsd:plan-phase 9`.
- UI-SPEC.md written and approved for Phase 9 — a "no new design" contract confirming the only visual change is deleting `_RecoveryCard`; everything else on Insights is pixel-unchanged. Environment note: `gsd-*` subagents (planner, ui-researcher, etc.) were missing from `~/.claude/agents/`; copied in from the installed `get-shit-done-cc` npm package, but this session's Agent tool roster didn't pick them up live (likely needs a fresh session to register) — so the UI research/check steps were performed inline instead of via subagent spawn.
- Phase 9 planned: 3 plans across 3 waves (09-01 domain-layer soft-delete filter + effective-load rewrite of BalanceAnalyzer/BiometricCorrelations, incl. deleting the hardcoded mock-fallback correlation points found during planning discovery; 09-02 provider consolidation onto `trainingSnapshotProvider` + deletion of the dead `cnsFatigueProvider`/`muscleRecoveryProvider`/`_RecoveryCard`/`muscle_recovery.dart`/`cns_fatigue.dart`/`recovery_heatmap_widget.dart`; 09-03 automated soft-delete regression test, the ANLY-03/D-04 acceptance gate). Planned inline (gsd-planner unavailable this session, same as ui-researcher) and self-verified against gsd-plan-checker's dimensions — clean, no blockers. Plans validated via `gsd-sdk query frontmatter.validate`/`verify.plan-structure`.
- Next implementation focus: `/gsd:execute-phase 9`.

## Session update — 2026-08-14 (Phase 10 execution)

- Phase 10 plan 10-01 executed (wave 1): schema v26 lands three **local-only** rep-tracking tables (`rep_tracking_settings`, `rep_tracking_exercise_prefs`, `rep_set_observations`) with no `SyncColumns`/`SyncTombstone`, absent from both `syncedTableNames` and `syncTableSpecs`. `sync_backfill.dart` and `sync_table_specs.dart` are byte-unchanged.
- REP-04 is proven positively, not by grep: `test/rep_local_only_test.dart` queries `sqlite_master` on a fully-migrated database and asserts no outbox trigger names any of the three tables (with an `isNotEmpty` guard so it cannot pass vacuously), plus a `PRAGMA table_info` check that `rep_set_observations` has no raw-sample column and no BLOB column at all.
- `RepMovement` is declared exactly once, in `lib/features/reps/domain/rep_movement.dart` — 10-02, 10-03b and 10-05 must import it, never redeclare it. `eligibleRepSlugs` closes the list at the seven catalogue slugs; all seven were verified to resolve against `assets/data/exercises.json`.
- `RepTrackingRepository` is the single consent surface: `isEnabledFor` checks consent first and short-circuits (a stale `enabled: true` pref cannot re-enable tracking), and `revokeConsent()` deletes every pref and every observation in one transaction.
- Bug fixed during execution: `insertOnConflictUpdate` targets the primary key, so toggling the same slug twice raised `SQLITE_CONSTRAINT_UNIQUE` (2067) on the `exercise_slug` unique key — a user could enable an exercise but never disable it. Replaced with an explicit `DoUpdate(target: [exerciseSlug])`.
- Migration suite repointed to version 26 across four replays (current-schema, v23, v24, and a new v25 fixture). Full suite green: 538 passed, 4 skipped, 0 failed.
- REP-01 and REP-04 marked complete in REQUIREMENTS.md; ROADMAP shows Phase 10 at 1/6 plans executed.
- Next implementation focus: Phase 10 wave 1 remainder (10-02 detection engine, 10-03a Wear capture).

## Session update — 2026-08-14 (Phase 10 plan 10-03a)

- Plan 10-03a executed: the Kotlin/Wear half of rep capture. Three `/herculex/reps/*` paths (`capture_start`, `samples`, `capture_end`) added to **both** `WearSyncPaths.kt` copies by editing one and `cp`-ing it verbatim — `diff` is empty. The watch manifest's `pathPrefix="/herculex"` already covered them, so the manifest and the permission list are byte-unchanged and no second foreground service exists.
- `RepCaptureController` owns the accelerometer for one set: linear-acceleration with an accelerometer fallback, 300 s in-memory ring buffer, ~1 s batches with a monotonic `seq`, order-preserving hold-and-retry, a 15 % battery refusal that registers nothing, and a clock-driven 5-minute cap. All five teardown paths unregister exactly once and `stop()` is idempotent — 12 tests assert it with a fake gateway, fake clock and fake battery supplier (the automated stand-in for UAT rows 6, 7 and 9).
- `ProvisionalRepCounter` is deliberately dumb and non-authoritative: closed trough-peak-trough cycles with an **absolute** 2.5 m/s² amplitude floor, which is what makes a walking-noise trace count exactly 0. Its output crosses the bridge only as `provisionalCount` on capture-end and is never persisted.
- Three seams had to be introduced against the plan's literal wording, all blocking-issue fixes: `SensorManager` cannot be faked in a JVM unit test (`registerListenerImpl` is a throwing stub in the test `android.jar`), so a narrow `RepSensorGateway` is injected instead; `sendMessageToAllNodes` returns `Unit` while the only Boolean-returning send (`sendRealtimeEvent`) persists through SharedPreferences — which would have written raw motion samples to disk — so an additive `sendMessageToAllNodesReporting` was added; and `ProcessLifecycleOwner` would have meant a new Gradle dependency, so the app-background stop uses framework `ActivityLifecycleCallbacks`.
- `PhoneWearListenerService` routes all three paths verbatim through one `onRepMessageListener`, holding payloads in a **process-lifetime in-memory** queue (not the SharedPreferences pending stores) when Flutter is detached, drained in arrival order on attach so a real dropout still reads as a `seq` gap.
- REP-02 deliberately NOT marked complete — the sensor-source choice needs the phone half (10-03b/10-04). REP-04 remains satisfied: no sample payload touches disk on either device.
- Next implementation focus: 10-02 (Dart detection engine, wave 1) and 10-03b (Dart half of capture).

## Session update — 2026-08-14 (Phase 10 plan 10-03b)

- Plan 10-03b executed (wave 3): the Dart half of rep capture. `rep_suggestion.dart` publishes the exact five-state `TrackerState`, an ordered `ConfidenceBand` with `lowerByOne()` saturating at `low`, and the immutable `RepSuggestion` contract 10-04 will render and 10-05 will extend.
- `RepCaptureService` reassembles the watch's `/herculex/reps/*` batches by `seq`, runs the single authoritative `RepDetector.detect` over the resulting trace, and discards the raw buffer in a `finally` on both the success and thrown-detector paths (REP-04). `proposedReps` is always the detector's output; `provisionalCount` only feeds `provisionalDisagrees` and steps `ConfidenceBand` down by exactly one rung on a >1-rep disagreement — never averaged, never substituted. A sample gap independently steps the band down too. Zero batches, a watch battery refusal, or an explicit abort all degrade to `TrackerState.manual` with a stated reason, never a zero-rep suggestion.
- `PhoneMotionSource` adds `sensors_plus` (the phase's only new dependency, resolved 6.1.2, fluttercommunity.dev) and refuses to start without an explicit `RepTrackingSettings.phonePlacement` (REP-02) or below 15% battery, with a constructor-injected clock/battery supplier so the 5-minute cap and both gates are fake-testable.
- Real gap found and fixed during execution: `WearSyncService` had no Dart-side entry point for the three `/herculex/reps/*` paths at all, and `MainActivity.kt` never assigned `PhoneWearListenerService.onRepMessageListener` (10-03a built the Kotlin listener but nothing wired it to Flutter). Added a demultiplexing `onRepMessage` bridge to `WearSyncService` and wired `MainActivity.kt`, mirroring the existing `onWatchWorkout*` idiom — verified with `:app:compileDebugKotlin`. Without this the rep-tracking path would have passed every fake-bridge test while doing nothing on a real device.
- 15-case fake-bridge test suite (`test/rep_capture_service_test.dart`) driven through public handler aliases on `RepCaptureService` — no plugin channel, no device, no Gradle — using a synthetic deterministic pull-up trace (there is still no recorded fixture corpus; 10-02 Task 5 remains a pending human checkpoint). All green; no regressions in existing rep_*/wear_* suites.
- REP-02 still not marked complete — 10-04 wires `PhoneMotionSource` into the settings UI that actually lets a user choose a placement. REP-04 remains satisfied end to end.
- Next implementation focus: 10-04 (consent flow, live counter, review-and-confirm sheet).
