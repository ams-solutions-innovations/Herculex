---
gsd_state_version: 1.0
milestone: v2.0
milestone_name: Training Programs Revamp, Dream Physique & Gamification
status: ready_to_plan
last_updated: "2026-09-30T08:06:42.434Z"
progress:
  total_phases: 15
  completed_phases: 9
  total_plans: 66
  completed_plans: 57
  percent: 60
---

# Project State: Milestone v2.0

## Session update — 2026-09-30 (Phase 27 Plan 04 Completed)

- Completed Plan 27-04 (AIP-04, partial — persistence target only): the
  `HerculexAiProgramBriefs` drift table at local schema **v46** (D-08),
  modeled directly on `PhysiqueProgrammingProfiles`: non-nullable `programId`
  FK to `Programs` (cascade delete — diverges from `ExercisePreferences`'
  nullable FK per the plan's explicit instruction), a single `briefJson`
  blob carrying the full brief (split, periodization, dayRoles-with-
  rationale per D-09, musclePriorities, phaseIntent), plus
  `source`/`knowledgeVersion`/`modelVersion`/`confirmedAt`/`active`
  provenance columns. Registered in `syncedTableNames` and
  `sync_table_specs.dart` (`SimpleFk` to `programs`), ready for sync once
  plan 27-10's Supabase migration lands — chore 5 is deliberately deferred
  there, same sequencing Phase 28's `tdee_estimates` used between its own
  plans 05 and 11.

- Chores 1-4 of the schema bump done: `schemaVersion` 45 -> 46 with a guarded
  `onUpgrade` branch (byte-for-byte v45 `TdeeEstimates` template — sqlite_master
  existence check, unique `idx_sync_uuid_herculex_ai_program_briefs` index,
  `installSyncTriggers`); `drift_schema_v46.json` and `schema_v46.dart`
  (`DatabaseAtV46`) generated; `test/migration_test.dart` retargeted (all
  `migrateAndValidate` calls, new v45->v46 replay test asserting the new
  table's columns/index/triggers) and `test/schema_v25/27/28/29_test.dart`
  retargeted from v45 to v46 (import alias, `newVersion:`, `createNew:`
  factory reference). `schema_v21/24_test.dart` correctly left untouched —
  they assert against `db.schemaVersion` dynamically.

- Exact snake_case column list recorded in 27-04-SUMMARY.md for plan 27-10's
  Supabase migration and column-parity test to match without re-deriving it.

- **AIP-04 left unchecked in REQUIREMENTS.md** (annotated, not marked
  complete), following the KB-02/KB-04/TDEE-05/AIP-02/AIP-03 partial-
  completion convention: this plan only builds the local persistence target
  the review-gate rendering will read from — no brief is generated yet
  (27-06/27-09) and `ProgramReviewView` does not yet render per-day
  rationale from this table. The SDK's `requirements.mark-complete`/
  `state.*` verbs are non-functional against this STATE.md's format (same
  "no-op" behavior every prior session in this file has logged since Phase
  28) — `roadmap.update-plan-progress 27` did work and was used; everything
  else in this section is hand-written.

- Gotcha reconfirmed: `dart run drift_dev schema dump` wrote
  `drift_schema_v46.json` to disk but the process itself hung afterward;
  killed it once the file was confirmed on disk (via `ls -la`, non-zero
  size) and ran `schema generate` as a separate step, exactly as CLAUDE.md
  documents. `pwsh` is unavailable in this session's Bash environment, so
  `tool/codegen.ps1` was read and its underlying `dart run build_runner
  build --delete-conflicting-outputs` command run directly instead —
  identical effect.

- Validation: `flutter test test/migration_test.dart test/schema_v21_test.dart
  test/schema_v24_test.dart test/schema_v25_test.dart test/schema_v27_test.dart
  test/schema_v28_test.dart test/schema_v29_test.dart` — 43/43 passing.
  `flutter analyze` on every touched file: 0 errors (one pre-existing,
  out-of-scope warning on `database.dart:1114`'s unrelated `TableMigration`
  experimental-API use in the v40 migration branch, untouched by this plan).

- Next implementation focus: Plan 27-05 (`GeminiBackend.generateProgramBrief()`
  + provenance-returning helper — Wave 1's next plan per ROADMAP.md).

---

## Session update — 2026-09-30 (Phase 27 Plan 03 Completed)

- Completed Plan 27-03 (AIP-02, AIP-03, partial on both): the pure-Dart
  `ProgramBrief`/`DayRoleBrief` domain model — `lib/features/programs/domain/
  program_brief.dart` — the authoritative client-side gate on Herculex AI's
  program design brief. TDD RED (`3441324`) then GREEN (`cadf5da`).

- `ProgramBrief.fromJson` strictly validates `splitType`/`periodizationModel`/
  `dayRoles[].role` via new private `_strict*` Set-membership lookups that
  throw `FormatException` on any unknown id — never the codebase's existing
  lenient `fromId(..., orElse: () => default)` statics, which are reserved
  for user input, not AI output (D-02). `musclePriorities` reuses
  `ProgrammingMusclePriority`/`canonicalProgrammingMuscleIds`/
  `ProgrammingPriorityLevel` from `dream_physique_service.dart` verbatim
  (D-01) — zero new apply logic needed downstream in
  `_applyDreamPhysiqueTuning()`. A recursive disallow-list scan rejects
  `exerciseId`/`sets`/`reps`/`load`/`rpe`/`tempo`/`timeCap` at any nesting
  depth, before any field parsing begins (AIP-02, threat T-27-04).
  `toJson()` round-trips losslessly and is the exact shape plan 27-09 will
  persist to the new `HerculexAiProgramBriefs` table.

- **REQUIREMENTS.md left both AIP-02 and AIP-03 unchecked** (annotated, not
  marked complete), following the KB-02/KB-04/TDEE-05/27-02 partial-
  completion convention: this plan delivers only the Dart-side strict-schema
  half. AIP-02 still needs the Edge Function + builder wiring (27-06/27-09)
  before Herculex AI can actually *return* a brief; AIP-03 still needs the
  guardrail extraction into `ProgramGuardrails.validateConfiguration()`
  (27-08) and the fallback-to-deterministic behavior. The SDK's
  `requirements.mark-complete` verb ticked both boxes automatically; reverted
  to `[ ]` with explanatory annotations.

- Validation: `flutter test test/program_brief_test.dart` 39/39 passing;
  `flutter analyze` 0 issues on both touched files; `check_structure` no new
  violations (236 and 283 lines respectively, both well under the 600-line
  cap). Per this plan's own note, the full-repo suite was not re-run
  standalone this session — the new files are self-contained (no shared
  files with 27-01/27-02), so no regression risk to the existing suite is
  expected; the orchestrator's wave-level full-suite check still applies.

- Next implementation focus: Plan 27-04 (or next plan in Phase 27's wave
  order — see 27-*-PLAN.md files).

---

## Session update — 2026-09-29 (Phase 27 Plan 02 Completed)

- Completed Plan 27-02 (AIP-03, partial), the D-07-mandated pre-refactor gap closure:
  added 6 new widget tests to `test/block_builder_view_test.dart` pinning `_create()`'s
  two current inline guardrail `StateError` throws (Max-Effort-per-week > 2, and 6-day-PPL

  + Max Effort) across manual/smart/guided build modes, against the UNREFACTORED code.
  Closes RESEARCH.md's Pitfall 4 / Wave-0 gap — no prior test exercised either throw.

- Manual mode's current exemption from both checks (creates successfully instead of
  throwing, since both conditions are gated on `buildMode != manual`) is now proven by
  test, not just read from the source — this is the exact baseline plan 27-08 must
  preserve when it retrofits every build mode onto the new shared
  `ProgramGuardrails.validateConfiguration()` method.

- Recorded reusable tap sequences in 27-02-SUMMARY.md for plan 27-08: `SplitType.abc`
  isolates the per-week Max-Effort-count condition (3 distinct non-PPL slots), while
  `SplitType.ppl` + `PeriodizationModel.maxEffort` isolates the 6-day-PPL condition
  without also tripping the count condition. Exact current message text recorded
  verbatim, including the em dash in the periodization label and the en dash in the
  PPL rejection message.

- **AIP-03 left unchecked in REQUIREMENTS.md** (annotated, not marked complete): this
  plan only adds the pre-refactor safety net. No guardrail extraction, AI-brief strict
  schema validation, or fallback-to-deterministic behavior exists yet — those are plan
  27-08 and later plans' work. The SDK's `requirements.mark-complete` verb ticked the
  box automatically; reverted to `[ ]` with an explanatory annotation, following the
  existing KB-02/KB-04/TDEE-05 partial-completion convention.

- **Environment note (not a code defect):** full-repo `flutter analyze`/`flutter test`
  could not be completed this session — three attempts hung indefinitely with near-zero
  CPU progress, alongside three long-lived VS Code `flutter daemon` processes and general
  machine-wide slowness (even a plain `Get-Process` call took >120s at one point). The
  scoped verification the plan's own `<verification>` block asks for
  (`flutter analyze test/block_builder_view_test.dart` and
  `flutter test test/block_builder_view_test.dart`) both passed cleanly before the
  contention began (0 issues, 10/10 tests). **Re-run the full suite once the machine is
  free of this contention**, before the phase gate.

- Next implementation focus: Plan 27-03 (or next plan in Phase 27's wave order — see
  27-*-PLAN.md files; 27-08 is the guardrail-extraction plan this test net unblocks).

---

## Session update — 2026-09-29 (Phase 27 Plan 01 Completed)

- Completed Plan 27-01 (AIP-01), the phase's mandatory first task per CONTEXT.md's
  explicit sequencing mandate: split the 3398-line `block_builder_view.dart` into a
  402-line thin shell (widget class, abstract `_BuilderStateBase` field holder,
  concrete `_BlockBuilderViewState` glue) plus 10 part files under
  `lib/features/programs/presentation/views/block_builder_view/`, using an
  abstract-base-plus-`on`-constrained-mixins technique (Dart cannot split one class
  body across files). Every part file is under 600 lines (max 493).

- Deviations (all mechanical, required to compile the plan's own prescribed
  technique — see 27-01-SUMMARY.md): split `step_parameters` into two files
  (`step_parameters.part.dart` + a new `step_parameters_specialization.part.dart`
  for the primary-lift-specialization modal + helpers) to stay under 600 lines;
  added `_defaultDayRole` to `step_methods.part.dart` (the plan's group list
  omitted it); qualified 3 static base-class members
  (`_stepCount`/`_manualMuscleLabels`/`_today()`) as `_BuilderStateBase.<member>`
  at their mixin call sites, since Dart does not inherit static members into
  `on`-bound mixins.

- `_create()` (now in `actions.part.dart`) and `_stepBuildModeAndPriorities()`
  (now in `step_mode_and_split.part.dart`, containing the exhaustive
  `switch (mode)`) are confirmed as the exact, stable edit targets plans 27-08,
  27-11, and 27-13 need — recorded in 27-01-SUMMARY.md's file-to-method map.

- Validation: `flutter analyze` 0 issues (0 errors, 0 warnings, 0 info) across all
  11 touched files; `flutter test test/block_builder_view_test.dart` 4/4 passing
  unchanged; full `flutter test` 1627 passed / 9 skipped / 0 failed — matches the
  Phase 28 baseline exactly, zero regressions. `dart run tool/check_structure.dart`
  no longer lists `block_builder_view.dart` among its violations.

- Next implementation focus: Plan 27-02 (or next plan in Phase 27's wave order —
  see 27-PLAN files).

---

## Session update — 2026-09-28 (Phase 28 loose ends closed; Phase 26 status reconciled)

- Closed the three Phase 28 loose ends: (1) independently verified and actually applied the
  `tdee_estimates` Supabase migration — the earlier "Pushed" report was checked and found false
  (migration was still pending remotely); ran `supabase db push` with user go-ahead and confirmed
  all 12 columns, 4 RLS policies, both triggers and the index via read-only queries. (2) Ran
  `/gsd-verify-work 28`: 3/6 UAT items passed (badge, detail sheet, HxStatTile), 3 blocked
  (reset flow, 14-day real-device run) on not being able to run the app right now — recorded as
  `blocked`, not guessed at. (3) Annotated TDEE-05 in REQUIREMENTS.md as partially delivered
  (weekly-report half deferred to Phase 29 by design), following the existing KB-02/KB-04
  convention instead of unticking.

- **Discovered Phase 26 was already fully executed and verified** (7/7 plans, 26-VERIFICATION.md
  scored 8/8 must-haves, 1 via human override, verified 2026-09-28) but this file's "Current
  Roadmap" summary still listed it as "Pending" — stale, same class of drift as the CLAUDE.md
  staleness already flagged. Reconciled the summary list below, `progress.completed_phases`
  (8 → 9), and `stopped_at`/`Current focus`. Per the non-numeric execution order
  (26 → 28 → 27 → 22 → 23 → 29 → 24 → 25), with 26 and 28 both actually done, **Phase 27** is
  next — it has no phase directory yet, so `/gsd:discuss-phase 27` starts fresh.

- Note for whoever picks up Phase 27, 29, or Hercul: KB-04's "labelled AI advice channel" half
  was deferred out of Phase 26 by explicit human decision and is **not yet claimed by any
  future phase**. 26-VERIFICATION.md flags Phase 29's weekly-report narrative as the leading
  candidate to close it.

---

## Session update — 2026-09-28 (Phase 28 Plan 11 Completed, Phase 28 code-complete)

- Completed Plan 28-11: phase-level verification. Full `flutter test` 1627 passed / 9 skipped /
  0 failed; `flutter analyze` 0 errors (44 pre-existing warnings/info); `check_structure` 58
  pre-existing violations, none new. The 9 skips are the opt-in live-Supabase tests in
  `test/sync/live_*_test.dart`, unchanged since 2026-09-02 (CLAUDE.md's "4 skipped" is stale).

- Supabase: the user reported "Pushed" for `20260928000000_tdee_estimates_v45.sql` (after 0015
  and 0016), but supplied no project ref, migration list or verification-query results, and the
  Supabase MCP was not authorized. This is USER-REPORTED, NOT independently verified. Run the
  four read-only queries (columns, four RLS policies, two triggers, index) against
  `ldzgyzigvbwofbswitrv` to close the gap.

- Known limitations (not fixed): the classifier needs step data, so users without Health data
  stay on the ActivityLevel seed until observed mode qualifies; the `goals_view.dart` activity
  sheet is not relabelled and has no reset confirm. D-10 (accept/dismiss) is deferred to
  Phase 29.

- SDK state-advance verbs still no-op on this STATE.md, so this note is hand-written.

---

## Session update — 2026-09-28 (Phase 28 Plan 09 Completed)

- Completed Plan 28-09 (TDEE-04): `TdeeEstimateBadge` (public, `presentation/widgets`) under
  the "Maintenance calories" field and a read-only `TdeeEstimateSheet` (public,
  `presentation/sheets`) with method, confidence, window and per-method inputs, plus
  `savedTargetForTodayProvider` for the no-delta comparison against the saved manual
  target. Both are public files so Phase 29's weekly report can reuse them.

- Decisions: the window shown is `span_days + 1`, never the winning candidate;
  classifier active calories, sleep and resting HR appear only under "Also recorded (not
  used in the estimate)"; no accept/dismiss controls (D-10 stays in Phase 29).
  `HxStatTile` label and value became `Flexible` (Rule 3) because the unmodified tile
  overflowed at 360dp with 2x text. `nutrition_targets_view.dart` is 2618 lines (+3).

- Validation: full `flutter test` 1627 passed / 9 skipped / 0 failed, 0 analyzer errors.
  Progress 10/11 plans in Phase 28. SDK `state.advance-plan` still cannot parse this
  STATE.md, so this note is hand-written.

- Next implementation focus: Plan 28-11 (human-gated migration apply).

---

## Session update — 2026-09-28 (Phase 28 Plan 10 Completed)

- Completed Plan 28-10 (TDEE-02, TDEE-04): `ActivityResetPolicy` (nutrition/domain,
  pure, unit-tested) and a new `ActivityLevelSection` widget that owns the Profile
  tiles, caption, confirm dialog and snackbar. Onboarding step reads "How active are
  you right now?" with a starting-point subtitle. The reset is still just the existing
  `_onFieldChanged` profile save; plan 07's controller forces the recalibration.

- Decisions: calibrated users get a confirm dialog; a Measured user's snackbar says the
  estimate stays measured (D-15), others get the next-recalibration text (D-14); the
  loading state counts as calibrating. `goals_view.dart`'s activity sheet is left
  unrelabelled (out of UI-SPEC scope) and is a possible follow-up.

- Validation: full `flutter test` 1586 passed / 9 skipped / 0 failed, 0 analyzer
  errors. Progress 9/11 plans in Phase 28 (28-09 not yet executed). SDK state-advance
  verbs still no-op, so this note is hand-written.

- Next implementation focus: Plan 28-09 (badge, detail sheet, material-shift prompt),
  then Plan 28-11 (human-gated migration apply).

---

## Session update — 2026-09-28 (Phase 28 Plan 08 Completed)

- Completed Plan 28-08 (TDEE-01, TDEE-04): the editor's "Maintenance calories" field
  and the Quick Calories & Phase Planner now read `maintenanceKcalProvider` (pure
  maintenance); the dream-physique setup view reads `baselineTargetsProvider`. No UI
  code calls `MacroTargets.fromProfile` any more (only `nutrition_providers.dart`
  does, as the cold-start fallback).

- Decision: the estimate is pure maintenance wherever a value is labelled maintenance,
  so the goal delta is applied once per path. Side effect: for weight-loss and
  muscle-gain users the planner/editor maintenance figures move by the old goal delta
  (-500/+300), correcting a pre-existing double application. PHYS-04 marker comments
  sit at both `DietPhaseCalculator.apply` call sites; no gate implemented.

- `nutrition_targets_view.dart` is 2615 lines (was 2617), so plan 28-09 keeps its
  full edit budget.

- Validation: full `flutter test` 1558 passed / 9 skipped / 0 failed, 0 analyzer
  errors. Progress 8/11 plans in Phase 28. SDK state-advance verbs still no-op, so
  this note is hand-written.

- Next implementation focus: Plan 28-09 (badge, detail sheet, material-shift prompt).

---

## Session update — 2026-09-28 (Phase 28 Plan 07 Completed)

- Completed Plan 28-07 (TDEE-01..05): `tdee_providers.dart` (latest estimate stream,
  `tdeeEstimateProvider`, pure `maintenanceKcalProvider`) and the
  `baselineTargetsProvider` rewire (goal delta re-added once via `fromMaintenance`;
  cold start, loading and error return exactly `MacroTargets.fromProfile`).
  `TdeeRecalibrator` plus `tdeeRecalibrationControllerProvider` (app open, resume,
  forced on ActivityLevel change) registered once in `app.dart`.

- Decisions: a stored coldStart row's kcal is ignored so a manual reset reseeds at
  once; the recalibrator reads the latest emitted profile, not `profileProvider.future`
  (that returned a stale profile on reset, fixed as a Rule 1 bug). No background
  scheduler exists, so a user who never opens or resumes the app is not recalibrated.

- Validation: full `flutter test` 1554 passed / 9 skipped / 0 failed, 0 analyzer
  errors. Progress 7/11 plans in Phase 28. SDK `state.advance-plan` still cannot
  parse this STATE.md, so this note is hand-written.

- Next implementation focus: Plan 28-08 (UI: badge, detail sheet, route
  "Maintenance calories" to `maintenanceKcalProvider`).

---

## Session update — 2026-09-28 (Phase 28 Plan 06 Completed)

- Completed Plan 28-06 (TDEE-01, TDEE-02, TDEE-05): `TdeeEstimatesRepository`
  (record with kcal/windowDays validation, latest/watchLatest/recent newest-first
  by estimatedAt then id, fromName validation and safe inputsJson decode) and
  `TdeeInputsRepository.load()` (presence-based food days, snapshot-aware per-day
  kcal reused from `NutritionRepository`, bodyweight, steps-only map, 14-day
  health means, workouts/week). Both take an injected `Clock`.

- Decision: history and observation reads are separate repositories so
  `baselineTargetsProvider` can depend on history alone (no import cycle).

- 23 tests passing, 0 analyzer errors. Progress 6/11 plans in Phase 28. SDK
  state-advance verbs still no-op, so this note is hand-written.

- Next implementation focus: Plan 28-07 (providers and controller).

---

## Session update — 2026-09-28 (Phase 28 Plan 05 Completed)

- Completed Plan 28-05 (TDEE-05): `supabase/migrations/20260928000000_tdee_estimates_v45.sql`
  written (NOT applied), completing schema chore 5 for v45. Owner-only RLS,
  updated_at and tombstone triggers, realtime publication and the
  `(user_id, updated_at, id)` pull index. `test/tdee_supabase_migration_test.dart`
  asserts column parity with drift `TdeeEstimates` (sync_uuid/synced_at excluded
  as local-only, matching 0014).

- Decision: no check constraints on `method`/`confidence`; validation stays at
  the Dart repository boundary.

- Ordering: 0015 and 0016 remain outstanding and must be applied before this
  file; applying all three is the plan 28-11 human-gated step.

- Progress 5/11 plans in Phase 28. SDK state-advance verbs still no-op, so this
  note is hand-written.

- Next implementation focus: Plan 28-06.

---

## Session update — 2026-09-28 (Phase 28 Plan 04 Completed)

- Completed Plan 28-04 (TDEE-01, TDEE-03, TDEE-05): pure-Dart `TdeeEstimator`
  in `tdee_estimator.dart` (498 lines) plus `WeightLog`/`TrendSeries` daily-grid
  EWMA in `tdee_trend.dart`, re-exported so downstream plans import both from
  the estimator. Every tunable is on `TdeeTuning`.

- Decisions: `windowDays` is the winning candidate (35/28/21/14), the measured
  span is `span_days` and the UI prints `span_days + 1`. `observedRecencyDays`
  is 6 so a week-old window fails the gate and the D-04 hold starts at the first
  cadence run after logging stops. Hysteresis counts elapsed days (rows must be
  >= 7 calendar days apart), so every persisted qualified non-observed row
  restarts the promotion clock; plan 07 should keep that in mind. Mean intake
  averages logged days only. `isMaterialShift` is strict and unrounded.

- Validation: 91 tests passing across the estimator, classifier and estimate
  suites, 0 analyzer errors. Progress 4/11 plans in Phase 28. SDK state-advance
  verbs still no-op on this STATE.md format, so this note is hand-written.

- Next implementation focus: Plan 28-05 (Supabase migration for tdee_estimates).

---

## Session update — 2026-09-28 (Phase 28 Plan 03 Completed)

- Completed Plan 28-03 (TDEE-05): drift schema v44 to v45. New synced
  `TdeeEstimates` table (`@DataClassName('TdeeEstimateData')`) with a domain
  `estimatedAt` distinct from sync-owned `updated_at`. The v45 onUpgrade branch
  guards `createTable` via `sqlite_master`, adds `idx_sync_uuid_tdee_estimates`
  and runs `installSyncTriggers`; registered in `syncedTableNames` and
  `syncTableSpecs` (`estimated_at` as dateTimeColumn).

- Chores 1-4 of the schema bump done (schemaVersion, dump, generate, test
  retarget); `drift_schema_v45.json` and `schema_v45.dart` generated,
  `test/migration_test.dart` retargeted with a v44 to v45 replay. Chore 5
  (Supabase SQL) is plan 28-05; applying it is plan 28-11. Until then local v45
  would quarantine `tdee_estimates` rows on push (PGRST204).

- `schema_v25/27/28/29_test.dart` retargeted from stale v39 to v45 and now pass
  (the 7 long-standing failures logged since Phase 21 are gone).

- Gotcha: `dart run drift_dev schema dump` writes the JSON but the process may
  never exit; kill it once the file exists and run `schema generate` separately.

- Validation: full `flutter test` 1443 passed / 9 skipped / 0 failed, 0 analyzer
  errors. Progress 3/11 plans in Phase 28. SDK state-advance verbs still no-op
  on this STATE.md format, so this note is hand-written.

- Next implementation focus: Plan 28-04.

---

## Session update — 2026-09-28 (Phase 28 Plan 02 Completed)

- Completed Plan 28-02 (TDEE-02, TDEE-04): `MacroTargets.fromProfile` split into
  `bmr`, `multiplierFor`, `goalDeltaKcal`, `seedMaintenanceKcal`, `fromMaintenance`
  in `macro_targets.dart`; `fromProfile` output is byte-identical (32-combination
  characterization test). New `test/target_resolver_test.dart` proves a saved manual
  rule always beats the fallback (TDEE-04).

- Decision: the estimate is always PURE maintenance; `fromMaintenance` adds the
  -500/+300/0 goal delta exactly once, so it is never double-applied. Plan 07 uses
  `fromMaintenance` for fallback targets; plan 08 reads pure maintenance for
  maintenance-labelled UI.

- Validation: 35 tests passing across the three touched suites, 0 analyzer errors.
  Progress 2/11 plans in Phase 28.

- Next implementation focus: Plan 28-03.

---

## Session update — 2026-09-28 (Phase 28 Plan 01 Completed)

- Completed Plan 28-01 (TDEE-02, TDEE-04): plain-Dart `TdeeEstimateResult` /
  `TdeeMethod` / `TdeeConfidence` / `TdeeBadgeState` (locked UI-SPEC badge copy) in
  `lib/features/nutrition/domain/tdee_estimate.dart`, and `ActivityClassifier` in
  `activity_classifier.dart` (continuous 1.15-1.90 multiplier from steps + training,
  seed blended by sparsity, unavailable below 3 step days, never high confidence).

- Decision: `active_kcal`, `sleep_hours`, `resting_hr` are recorded-only inputs, never
  used in the multiplier or confidence (would double-count with `countBurnedCalories`).

- Validation: 33 tests passing, 0 analyzer errors. Progress 1/11 plans in Phase 28.
- Next implementation focus: Plan 28-02.

---

## Session update — 2026-09-28 (Phase 28 context gathered)

- Ran `/gsd:discuss-phase 28`. No SPEC.md, no blocking anti-patterns, no prior CONTEXT.md/plans
  for this phase. Discussed 4 areas: Adherence threshold, Estimate visibility, Material-shift
  handling, Onboarding activity picker (15 decisions, D-01–D-15).

- Key fixes: adherence bar is ~70% of window days with food logged (D-02) plus any bodyweight
  logs in the window (D-01), with sustained-crossing hysteresis (D-03) and a grace period before
  falling back to the classifier (D-04). Estimate surfaces as a badge + tap-through detail next
  to "Maintenance calories" in `nutrition_targets_view.dart` (D-05), classifier inputs shown
  individually (D-06), compared side-by-side with any saved manual target (D-07), with a
  "Calibrating" cold-start state (D-08). Material shift = bigger of ±100 kcal or ±5% (D-09),
  surfaced as an explicit accept/dismiss prompt (D-10) — Phase 28 persists estimate history only,
  Phase 29 diffs it itself (D-11), keeping the Phase 28/29 boundary clean since Phase 29 doesn't
  exist yet. Onboarding `ActivityLevel` picker stays, reframed as a starting estimate (D-12),
  and stays editable in Profile post-calibration as a reseed-only manual reset (D-13–D-15).

- Confirmed via code read: the existing `TargetResolver`/`TargetRule` resolution order in
  `target_resolver.dart` already makes TDEE-04 ("never overrides a manually-set value") true by
  construction — a saved `NutritionTargetData` row always wins over `baselineTargetsProvider`,
  so the adaptive estimator only needs to change what the *fallback* returns.

- Deferred: PHYS-04 (underage/low-confidence deficit guardrails) applying to adaptive TDEE is
  noted as a cross-phase constraint on Phase 23 (not yet built) — Phase 28 must not create a
  bypass but doesn't implement the gate itself.

- Files changed: `.planning/phases/28-adaptive-tdee-activity-calibration/28-CONTEXT.md` (new),
  `28-DISCUSSION-LOG.md` (new).

- Next implementation focus: `/gsd:plan-phase 28`.

---

## Project Reference

See: `.planning/PROJECT.md` (initiated 2026-09-13)  
Blueprint: `docs/training-programs-physique-gamification-plan-2026-09-10.md`

**Core value:** Safe, deterministic, and explainable training program generation; flexible program and wave editing; persistent Dream Physique goals with phased nutrition plans; and an authentic 15-tier XP gamification system. Herculex AI is an additive, bounded layer over that core — it proposes and explains, the deterministic engines decide.  
**Current focus:** Phase 27 — herculex-ai-program-generation

---

## Current Roadmap (Phases 15–29)

Execution order is **not** numeric — see ROADMAP.md. Recommended:
`26 → 28 → 27 → 22 → 23 → 29 → 24 → 25`.

- **Phase 15: Program Generator Regression Fixes & Interaction Hardening** — Completed (2026-09-13).
- **Phase 16: Exercise Programming Metadata & Discipline Taxonomy** — Completed (2026-09-13).
- **Phase 17: Deterministic Program Planner & Hard Guardrails** — Complete, 5/5 plans.
- **Phase 18: Workout Time Budget, Warmups & Set Method Prescriptions** — Complete, 6/6 plans.
- **Phase 19: Program & Wave Editor with Explainable Periodization** — Complete, 4/4 plans.
- **Phase 20: Active Workout Shell & Calendar Execution Flow** — Complete, 5/5 plans.
- **Phase 21: CrossFit & GPP Training Tracks** — Complete, 9/9 plans. Ready for `/gsd:verify-phase 21`.
- **Phase 22: Primary Lift Strength Specialization** — Pending.
- **Phase 23: Persistent Dream Physique & Multi-Phase Nutrition** — Pending. Scope widened 2026-09-27 (PHYS-05–08: progress screen, weekly check-in cadence, AI verdict, trend charts). PHYS-07 depends on Phase 26.
- **Phase 24: Gamification System & 15-Rank XP Ledger** — Pending.
- **Phase 25: Cloud Sync, Privacy & Export Hardening** — Pending. Must stay last; covers every table added by 23/28/29.
- **Phase 26: Herculex AI Knowledge Base & Brand Unification** — Complete, 7/7 plans, verified 2026-09-28 (8/8 must-haves, 1 via human override — KB-04's "labelled AI advice channel" half deferred, unclaimed by any future phase; see 26-VERIFICATION.md). Foundational for 27, 29, PHYS-07.
- **Phase 27: Herculex AI Program Generation** — In progress, 3/13 plans (27-01 complete: block_builder_view.dart split into part/part-of mixins; 27-02 complete: pre-refactor characterization tests for _create()'s inline guardrail throws; 27-03 complete: ProgramBrief strict-parsing domain model, ahead of the AI wiring plans).
- **Phase 28: Adaptive TDEE & Activity Calibration** — Complete, 11/11 plans, verified 2026-09-28. No AI dependency; feeds 23 and 29.
- **Phase 29: Weekly Report & Herculex AI Narrative** — Pending. Blocked on 23 (26, 28 now complete).

---

## Session update — 2026-09-27 (Scope amendment — Herculex AI, Phases 26–29)

- User-directed scope change: custom program preparation gains a Herculex AI path
  alongside the manual one, grounded in a coaching "textbook" (a mentality corpus the
  user will supply). Four new phases appended and Phase 23 widened. No Dart written —
  this session amended planning documents only.

- **Four decisions taken with the user:**

  1. **Hercul stays deterministic.** `hercul_rules.json`, `HerculSignals.all` and the
     closed-vocabulary test are untouched and keep working offline. Herculex AI is an
     additive, clearly-labelled second advice channel, not a replacement (KB-04).

  2. **Adaptive TDEE is hybrid.** Observed energy balance (mean intake + bodyweight
     trend × 7700 kcal/kg over a rolling window) is primary, because it measures real
     expenditure from data the app already holds; activity classification over
     `HealthSamples` is the fallback when logging adherence is too thin (TDEE-01/02).

  3. **The textbook lives server-side**, versioned beside
     `supabase/functions/gemini-analyze/prompts.ts` — not extractable from the APK,
     updatable by deploy without an app release, and stamped onto every output as
     `knowledgeVersion` (KB-01/02). Consistent with RB-01.

  4. **Existing numbering preserved.** Phase 23 extended rather than split; new work
     appended as 26–29 with an explicit non-numeric execution order.

- **Architectural constraint carried into every new phase.** The project's house rule
  from `06-AI-SPEC.md` — deterministic primary, AI bounded, AI never writes directly to
  the database, user confirms — governs all of this. Herculex AI returns a *program
  design brief* (split, periodization, day roles, muscle priorities, phase intent,
  rationale); `SmartProgramPlanner` remains the sole exercise selector, so every
  Phase 16–21 guardrail stays in force and cannot be argued away by a model (AIP-02/03).
  `smart_program_planner.dart:109` already documents exactly this seam.

- **Risks logged for the phase contexts** (detail in the amendment blueprint):
  Supabase migrations `0015`/`0016` are still unapplied and three new phases add tables;
  local drift is at v44 and each new table is a five-chore bump; `block_builder_view.dart`
  (3398 lines) and `nutrition_targets_view.dart` (1450+) both breach the 600-line rule
  before any new mode is added; the AI daily cap is a single shared 50/day that
  **fails open** on RPC error; no AI response is cached today, so weekly reports and
  program briefs must be persisted rather than recomputed; `flutter_local_notifications`
  cannot run Dart on fire, so the Sunday report must be generated on open and deep-linked.

- Files changed: `.planning/ROADMAP.md`, `.planning/REQUIREMENTS.md`, `.planning/STATE.md`,
  `docs/herculex-ai-plan-2026-09-27.md` (new), `CLAUDE.md` (stale active-track line).

- Next implementation focus: `/gsd:discuss-phase 26`. Phase 26 is the only new phase with
  no upstream dependency, and it can ship the corpus contract, versioning and injection
  path against a placeholder corpus — so waiting on the user's textbook blocks nothing.

---

## Session update — 2026-09-27 (Phase 21 Plan 09 Completed — gap closure, Phase 21 complete)

- Completed Plan 21-09 (CF-01), the second and final gap-closure plan found by
  Phase 21 verification: `program_review_view.dart`'s `_ExerciseRow` rendered
  the raw placeholder `targetSets`/`targetRepsMin`/`targetRepsMax` columns
  directly for every row, including CrossFit metcon rows, so the program
  review screen showed "1 sets · 1 reps" for metcons even though the real
  AMRAP/EMOM/For-Time prescription was already correctly encoded in
  `prescriptionCodecJson` and correctly decoded on the active-workout path
  (21-07).

  - `_ExerciseRow` now decodes `prescriptionCodecJson` via
    `SlotPrescriptionCodec.decode` whenever `item.row.sessionSegment ==
    SessionSegment.metcon.id`, rendering a real one-line summary ("AMRAP
    7:30", "EMOM 12 min", "For Time, cap 9:00") via new `_metconSummary`/
    `_formatCap` helpers. Non-metcon rows and metcon rows whose decode
    fails are unchanged — the pre-existing placeholder text is the fallback,
    never a crash or blank subtitle.

  - New widget test seeds a metcon `programDayExercises` row with a real
    encoded AMRAP prescription (`capSeconds: 450`) and proves "AMRAP" renders
    while "1 sets" is absent.

- Validation: 0 analyzer errors; `flutter test test/program_review_view_test.dart`
  7/7 passing (1 new).

- **Phase 21 (CrossFit & GPP Training Tracks) gap closure is complete — 9/9
  plans.** CF-01/02/03 all closed end-to-end, including both gaps
  VERIFICATION.md found. Ready for `/gsd:verify-phase 21`.

- Next implementation focus: `/gsd:verify-phase 21`, then Phase 17 or 22
  planning.

---

## Session update — 2026-09-27 (Phase 21 Plan 08 Completed — gap closure)

- Completed Plan 21-08 (CF-02), the first of two gap-closure plans found by
  Phase 21 verification: `CrossfitScalingPolicy.complexityCheck` had zero
  production call sites before this plan, despite being fully implemented
  and unit-tested since Plan 21-02.

  - Wired `complexityCheck` into `SmartProgramPlanner._createStableSlots`:
    per-`metconGroupKey` movement/advanced-movement tracking maps, a new
    `_isCrossfitAdvancedOrJustUnlocked` helper, and a candidate-pool
    substitution filter applied *before* scoring so the scorer is never
    even offered a second advanced/just-unlocked pick when a safe
    alternative exists in that slot's own pool.

  - When no safe substitute exists, `complexityCheck`'s `exceedsCeiling`
    rationale is appended to the slot's `why`, flowing into
    `ProgramDayExercises.prescriptionWhy` as an explicit, non-silent
    exception record (D-06 hard rule: never stack 2+ advanced/just-unlocked
    movements in one metcon, regardless of level).

  - Two new regression tests prove both branches. Deviation (Rule 1): the
    plan's literal `programmingDifficulty: 'advanced'` fixture instruction
    doesn't reach the guard at `ExperienceLevel.novice` — that difficulty
    is hard-excluded from a novice's candidate pool entirely by
    `ExerciseProgrammingEligibility.allows`, before the guard ever runs.
    Switched to `prerequisiteSlugs`-based "just-unlocked" fixtures instead,
    and discovered CrossFit/GPP segment needs share an identical
    role/pattern/muscle-less eligibility mask (any fixture can land in any
    segment slot), so the forced-exception test seeds the entire eligible
    pool as just-unlocked to make the assertion hold regardless of scorer
    assignment.

- Validation: 0 analyzer errors; `smart_program_planner_test.dart` 11/11
  passing (2 new).

- Next implementation focus: Plan 21-09 (the second gap-closure plan —
  decode `prescriptionCodecJson` for metcon rows in
  `program_review_view.dart`'s `_ExerciseRow`, CF-01).

---

## Session update — 2026-09-27 (Phase 21 Plan 07 Completed — Phase 21 Complete)

- Completed Plan 21-07 (CF-01), the final plan in Phase 21:
  - `PlannedExerciseSnapshot` gained a `sessionSegment` field; `resolveProgramDay`
    now reads both `pde.sessionSegment` and `pde.supersetGroup` (the Program
    path never populated `supersetGroup` before — only `resolveTemplate` did).

  - `materialize()`'s `WorkoutExercisesCompanion.insert` now writes
    `plannedSessionSegment: Value(exercise.sessionSegment)` alongside the
    already-correct `supersetGroup` write.

  - Two new end-to-end tests in `test/planned_session_resolver_test.dart`:
    segment/superset-group threading through resolution + materialization,
    and AMRAP `capSeconds` meta survival into `SetEntries.setTypeMetaJson`
    (proving existing `_setsFromPrescription` behavior, no new production
    code needed for that half).

- Validation: 0 analyzer errors (whole repo); `test/planned_session_resolver_test.dart`
  9/9 passing. Full `flutter test`: only the pre-existing `schema_v25/27/28/29_test.dart`
  failures remain (stale v39 fixture targets from before Plan 21-01, already
  logged in `deferred-items.md`, out of scope for this plan).

- **Phase 21 (CrossFit & GPP Training Tracks) is now complete — 7/7 plans.**
  CF-01/02/03 all closed end-to-end. Ready for `/gsd:verify-phase 21`.

- Next implementation focus: Phase 22 (Primary Lift Strength Specialization) planning.

---

## Session update — 2026-09-27 (Phase 21 Plan 06 Completed)

- Completed Plan 21-06 (CF-01, CF-02, CF-03): wired `CrossfitProgramPlanner`
  (21-04) and `GppProgramPlanner` (21-05) into
  `smart_program_planner.dart`'s `_needsFor` dispatch, replacing the bare
  2-slot CrossFit stub and the inline GPP `_SlotNeed` literal:

  - `_SlotNeed`/`_ResolvedSmartSlot`/`_TimePlan` extended with
    segment/metcon fields (source-compatible, every existing call site
    untouched).

  - Every segment-tagged slot is categorically forced to
    `SlotTrainingMethod.technique`, unconditionally — closes RESEARCH.md's
    Pitfall 2 (T-21-01), proven end-to-end for both `maxEffort` and
    `linear` periodization models.

  - `slotCache`/`ProgramExerciseSlots.slotKey` are week-scoped for
    CrossFit/GPP days so metcon format genuinely rotates
    AMRAP → EMOM → For Time via `variationSeed: week.weekIndex`.

  - `sessionSegment`/`supersetGroup` persisted through `populate()`;
    metcon duration uses `WorkoutDurationEstimator.estimateCappedSegment`
    and is excluded from the time-budget trim loop.

  - `CrossfitScalingPolicy.recoveryReserveWarning` surfaced through the
    existing `ProgramSlotExplanations` rationale channel.

  - Deviation (Rule 1): updated the pre-existing
    `test/crossfit_gpp_program_test.dart` CrossFit assertion, which
    guarded the old bare-stub shape this plan intentionally replaces.

- Validation: 0 analyzer errors; `smart_program_planner_test.dart` (9/9,
  4 new) and `crossfit_gpp_program_test.dart` (3/3) pass. Full
  `flutter test`: only the 7 pre-existing `schema_v25/27/28/29_test.dart`
  failures remain (stale v39 targets, logged in this phase's
  `deferred-items.md` during 21-01, unrelated to this plan).

- Next implementation focus: Plan 21-07 (if any remain), else Phase 21
  closeout.

---

## Session update — 2026-09-26 (Phase 21 Plan 05 Completed)

- Completed Plan 21-05 (CF-03): `GppProgramPlanner` segment-assembly domain service for the GPP conditioning day:
  - Added `GppProgramPlanner.segmentNeedsFor()` in `lib/features/programs/domain/gpp_program_planner.dart`, returning exactly one `CrossfitSlotNeed(role: SlotRole.conditioning, segment: SessionSegment.metcon)`.
  - Resolved both CONTEXT.md discretion items in code comments: GPP day shape is a standalone 3rd day matching the already-shipped `SplitType.fullBodyAbGpp` skeleton; the GPP/Dynamic-Effort guard relies on the existing `role.isHeavy`-gated structural exclude in `smart_program_planner.dart` as primary, with `SlotRoleEligibility`'s isTimed/cardio-only gate as secondary — no new disciplines-based filter added.
  - 4-exercise gpp pool (burpee, rowing-erg, air-bike, stationary-bike) ships as-is this phase, documented as a known content-curation limitation rather than silently widened or ignored.
  - TDD RED/GREEN: `test/features/programs/gpp_program_planner_test.dart` (4 tests) confirmed failing (compile error against non-existent class) before implementation existed, then passing after.
  - Full end-to-end "`populate()` never emits `dynamicEffort` for a GPP day" regression explicitly deferred to Plan 21-06, where the `smart_program_planner.dart` wiring exists to exercise it.
- Validation: 0 analyzer errors; all 4 new tests passing.
- Next implementation focus: Plan 21-06 (wires `CrossfitProgramPlanner`/`GppProgramPlanner` into `smart_program_planner.dart`'s `_needsFor` dispatch).

---

## Session update — 2026-09-26 (Phase 21 Plan 04 Completed)

- Completed Plan 21-04 (CF-01, CF-02): `CrossfitProgramPlanner` segment-assembly domain service:
  - Added `CrossfitProgramPlanner.segmentNeedsFor(experience, variationSeed)` in `lib/features/programs/domain/crossfit_program_planner.dart`, producing the ordered D-01/D-02 segment blueprint (warmup, skill, strength, metcon x N, cooldown) as `CrossfitSlotNeed` descriptors — pure domain logic, no catalog/DB dependency.
  - Metcon format rotates deterministically via `variationSeed % 3` across `SetType.amrap/.emom/.forTime`, proving all three ROADMAP-named formats are reachable through normal week-over-week variation.
  - Movement count and time cap sourced from `CrossfitScalingPolicy.movementCeilingFor`/`.timeCapFor` (Plan 21-02), never hardcoded.
  - Strength segment is the sole `SlotRole.supplemental` need; every other segment uses `SlotRole.accessory`; `SlotRole.main` is never emitted, keeping the existing Dynamic-Effort guard closed to CrossFit content (threat T-21-03).
  - TDD RED/GREEN: `test/features/programs/crossfit_program_planner_test.dart` (7 tests) confirmed failing before implementation existed, then passing after.
- Validation: 0 analyzer errors; all 7 new tests passing.
- Next implementation focus: Plan 21-05 (GPP program planner, Wave 2 sibling of this plan).

---

## Session update — 2026-09-26 (Phase 21 Plan 03 Completed)

- Completed Plan 21-03 (CF-01, CF-02): Duration cap estimator + prerequisite metadata gap:
  - Added `WorkoutDurationEstimator.estimateCappedSegment(capSeconds)`, returning the cap verbatim as a conservative upper bound for AMRAP/EMOM/For-Time metcon segments (TDD RED/GREEN), composing with `estimateSession`'s existing `Iterable<Duration>` parameter with no signature change.
  - Closed the `prerequisiteSlugs` metadata gap RESEARCH.md identified: `kipping-muscle-up`/`strict-muscle-up` now gated on `pull-up`/`chest-dips` (mirroring `bar-muscle-up`); all 6 Olympic-tagged lifts (`power-clean`, `hang-power-clean`, `clean-and-jerk`, `power-snatch`, `hang-snatch`, `squat-snatch`) now gated on `front-squat`/`overhead-press`.
  - Extended `test/exercise_scaling_resolver_test.dart` with a `CrossFit prerequisite gating (CF-02)` group proving `ExerciseProgrammingEligibility.verifyPrerequisites` correctly gates a novice with no history and admits one with completed prerequisites.
- Validation: 0 analyzer errors; `test/features/workouts/workout_duration_estimator_test.dart` and `test/exercise_scaling_resolver_test.dart` both fully passing (17/17 combined).
- Next implementation focus: Plan 21-04 (Wave 2, blocked on Wave 1 completion — 21-04/21-05 remain).

---

## Session update — 2026-09-26 (Phase 21 Plan 01 Completed)

- Completed Plan 21-01 (CF-01): `SessionSegment` schema primitive:
  - Added `SessionSegment` enum (warmup/skill/strength/metcon/cooldown) and the shared public `CrossfitSlotNeed` descriptor in `lib/features/programs/domain/session_segment.dart`, kept separate from either Wave 2 planner file so `crossfit_program_planner.dart` (21-04) and `gpp_program_planner.dart` (21-05) stay file-independent.
  - Bumped drift `schemaVersion` to 44: `sessionSegment` on `ProgramExerciseSlots`/`ProgramDayExercises`, `supersetGroup` on `ProgramDayExercises`, `plannedSessionSegment` on `WorkoutExercises`, with a guarded `addIfMissing` onUpgrade branch.
  - All five schema-bump chores done: codegen regenerated (`drift_schema_v44.json`, `schema_v44.dart`, `database.g.dart`), `test/migration_test.dart` retargeted to v44 with a new v43->v44 replay test, and matching `supabase/migrations/20260916000000_session_segment_v44.sql`.
- Validation: 0 analyzer errors; `test/migration_test.dart` 17/17 passing. Full `flutter test` run: 1334 passed, 7 pre-existing failures in `test/schema_v25_test.dart`/`schema_v27_test.dart`/`schema_v28_test.dart`/`schema_v29_test.dart` (stale hardcoded v39 targets, predates this plan — logged to `.planning/phases/21-crossfit-gpp-training-tracks/deferred-items.md`, not fixed — out of scope).
- Next implementation focus: Plan 21-02.

---

## Session update — 2026-09-13 (Phase 16 Completed)

- Completed Phase 16: `Exercise Programming Metadata & Discipline Taxonomy`:
  - **Plan 16-01 (META-01):** Shipped Drift & Supabase schema v41 with 6 new metadata columns and scaling index, verified TableMigration table rewrite, generated migration fixtures and dumped schema snapshot, and packaged `exercise_programming_metadata.json` in `pubspec.yaml`.
  - **Plan 16-02 (META-01, META-03):** Upgraded `exercise_programming_metadata.json` to version 2 covering 108 exercises across 5 canonical disciplines (`weights`, `calisthenics`, `crossfit`, `olympic`, `gpp`), 4 commonness tiers, 7 scaling ladders, and specialization anchors; extended `ExerciseImporter` companion mapping; hardened `ExerciseProgrammingEligibility.allows` with strict novice difficulty ceiling and two-layer `basicWeights` hard gate blocking specialty bars, chains, boards, and pins.
  - **Plan 16-03 (META-02, META-04):** Implemented dual-check prerequisite gate in `ExerciseProgrammingEligibility.verifyPrerequisites` with canonical `movementSlug` family alias resolution; built `ExerciseScalingResolver` domain service with progressive ladder regression, strict group boundaries, and explainable rationales.
- Validation: 0 Dart static analysis errors; 46/46 automated tests passing across 6 test suites in 15s.
- Next implementation focus: `/gsd-plan-phase 17` (Deterministic Program Planner & Hard Guardrails).
