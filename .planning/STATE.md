---
gsd_state_version: 1.0
milestone: v2.0
milestone_name: Training Programs Revamp, Dream Physique & Gamification
status: ready_to_plan
last_updated: "2026-10-03T14:48:53.578Z"
progress:
  total_phases: 15
  completed_phases: 12
  total_plans: 107
  completed_plans: 106
  percent: 80
---

# Project State: Milestone v2.0

## Session update — 2026-10-03 (Phase 29 Plan 19 Completed)

- Completed Plan 29-19 (verification only, no product code): full `flutter test` 2706 passed / 9 skipped
  / 0 failed (skipped equals baseline); `flutter analyze` 0 errors (51 pre-existing warnings/infos);
  `check_structure` 57 violations (unchanged baseline); Deno `gemini-analyze` 40 passed; all source
  gates clean (the literal `DateTime.now` grep false-positives on `DateTime now` parameters, escaped
  form is 0). `pubspec.*` unchanged; only one new Supabase migration file, nothing applied or deployed.
  `29-VALIDATION.md` signed off (`nyquist_compliant` and `wave_0_complete` true; latency box left
  unchecked, quick run measured 86 s). Traceability table in `29-19-SUMMARY.md`.

- Decisions: RPT-01, RPT-02, RPT-03 un-ticked in `REQUIREMENTS.md` (plan 18 had ticked all five): they
  still need the unapplied v48 migration, the undeployed `weekly_report` Edge kind and the on-device
  Sunday/cold-start checks, all owned by plan 20. RPT-04 and RPT-05 stay complete. Repo-wide
  `dart format` drift (62 files) is pre-existing and was not touched. SDK `state.*` verbs no-op on this
  STATE.md layout; this note is hand-written.

---

## Session update — 2026-10-03 (Phase 29 Plan 18 Completed)

- Completed Plan 29-18 (RPT-01..RPT-05): `WeeklyReportView` (frozen render, `open(week)` once after the
  first frame, TDEE card only when material, single distinct Herculex AI card after a 32 gap, corrupt
  payload / opt-in off / no-data states), both routes registered in `router.dart` via
  `buildWeeklyReportRoute` (`_intParam` + `IsoWeek.tryCreate`, impossible weeks hit `_badParam`), and
  `weeklyReportResumeProvider` (invalidates `weeklyReportDueWeekProvider` on app resume, one watch line
  in `app.dart`). 35 new tests, folder total 406.

- Decisions: route builder is a `@visibleForTesting` top-level function so tests use the production
  logic; domainTraining equals primary in every palette, so the "only the AI card is primary-tinted"
  test is scoped to nutrition / recovery / TDEE cards. SDK `state.*` verbs still partly no-op; this
  note is hand-written.

---

## Session update — 2026-10-03 (Phase 29 Plan 17 Completed)

- Completed Plan 29-17 (RPT-01, RPT-04, entry points only): `WeeklyReportsHistoryView` (newest first,
  unread dot, "Narrative pending" pill, opt-out banner to notification settings, empty state),
  `WeeklyReportsEntryCard` (+3 lines in `insights_view.dart`) and `WeeklyReportReadyCard`
  (+2 lines in `dashboard_view.dart`, not a `DashboardWidgetType`). 14 new tests.

- Decisions: the ready card owns its bottom gap so the dashboard hook is a single widget line; the
  history view sorts by `IsoWeek` itself; the opt-out banner only navigates, never flips the setting.
  `AppRoutes.weeklyReports` / `weeklyReport` still need router registration (plan 18), which should
  also add the resume hook for `weeklyReportDueWeekProvider`. SDK `state.*` verbs still partly no-op;
  this note is hand-written.

---

## Session update — 2026-10-03 (Phase 29 Plan 16 Completed)

- Completed Plan 29-16 (RPT-01, RPT-04, TDEE card only): `TdeeTargetProposalCalculator` (pure,
  delta-preserving, floor- and PHYS-04-clamped), `TdeeDecisionActions` (update / keep, write-once,
  the only `upsertTarget` path in weekly_report), `tdeeTargetProposalProvider`, `isActionableWeek`,
  and `TdeeShiftCard` (actionable / decided / read-only). 48 new tests, folder total 360.

- Decisions: OQ2 confirmed as delta-preserving (saved rule kcal + estimate delta, rounded to 10, carbs
  absorb remainder, same scope); `update()` validates the 800..6000 decision range and the undecided
  row before writing the target; card is stateful to disable both buttons while a call runs. Plan 18
  mounts `TdeeShiftCard(record:, section:)` only when `section.material`. SDK `state.*` verbs still
  partly no-op; this note is hand-written.

---
## Session update — 2026-10-03 (Phase 29 Plan 15 Completed)

- Completed Plan 29-15 (RPT-01, RPT-03, RPT-04, application half only): `weekly_report_providers.dart`
  (repository/inputs/service, week and history StreamProviders, opt-in, due week, dismissed-empty
  marker, dashboard `weeklyReportReadyProvider`) and the app-lifetime `WeeklyReportController`
  (`open` / `retryNarrative`, de-duplicated futures, persist-before-narrative, auto narrative on first
  open only, fail-soft) with `narrativeUiStateProvider` and `narrativeStatusFor`. 34 new tests,
  folder total 322.

- Decisions: quota-exhausted Retry is blocked only on the same Clock calendar day (next day reads as
  pending with Retry on); unreadable stored narrative shows pending with Retry off; NoData stores the
  dismissed marker (`weekly_report_dismissed_week` = `<isoYear>-<isoWeek>`). Bug caught: `whenComplete`
  with an arrow `map.remove()` deadlocks on its own future. Plans 16-18 add the TDEE action, views and
  dashboard entry point; call `open(week)` once on report entry. SDK `state.*` verbs still partly
  no-op; this note is hand-written.

---
## Session update — 2026-10-03 (Phase 29 Plan 14 Completed)

- Completed Plan 29-14 (RPT-01, RPT-02, RPT-04, RPT-05, data/service half only):
  `WeeklyReportInputsRepository.load(week, windowEnd)` (clock-free, presence-based, snapshot-first food
  names, both TDEE history rows) and `WeeklyReportService` (`generate` freezes a week once and persists
  before any AI work; `generateNarrative` is the single auto/manual narrative path, attempt counted
  before the backend call, write-once, narrative columns only). 31 new tests, folder total 288.

- Decisions: everything dated after `windowEnd` is excluded at load time (current week to date);
  `NarrativeOutcome` is a value class (saved / alreadySaved / notEligible / failed(kind)); the auto
  narrative gate lives in the plan-15 controller, not the service. Deferred: `watchDailyTotalsForRange`
  does not filter tombstoned `food_entries` (shared with TDEE inputs). RPT-01/02/04/05 left unchecked
  (partial). SDK `state.*` verbs still partly no-op; this note is hand-written.

---
## Session update — 2026-10-03 (Phase 29 Plan 13 Completed)

- Completed Plan 29-13 (RPT-01, RPT-02, RPT-05, widgets half only): `NarrativeStatus`,
  `SectionCardScaffold` / `ReportText` / `ReportTileGrid`, the four measured section cards
  (domain-tinted, never `hx.primary`, correlation statements verbatim) and the provider-free
  `AiNarrativeCard` (five states, per-day quota copy, `retryEnabled` flag). All under
  `presentation/widgets/`. Plans 15-18 wire controller, views, TDEE card and dashboard.

- Decisions: AI footer note shown in every state; ready + null narrative falls back to the pending
  face; disabled Retry built around `PremiumButton` (no disabled state) without editing it.
  `HxStatTile` renders values at 22 / labels at 12, not the UI-SPEC 28 / 14: a follow-up could add a
  size option. RPT-01/02/05 left unchecked (partial). SDK `state.*` verbs still partly no-op; this
  note is hand-written.

---

## Session update — 2026-10-03 (Phase 29 Plan 12 Completed)

- Completed Plan 29-12 (RPT-01, RPT-02, RPT-05, calculators half only): `CorrelationStatement`
  (fixed "tended to" templates, direction from the covariance sign of `result.points`,
  `minSamples = 8` / `minR2 = 0.3` named constants), `RecoverySectionCalculator` (engines run with
  `asOf: windowEnd` over a snapshot filtered to sets completed by `windowEnd`; 8-week trailing
  correlations), `PhysiqueSectionCalculator`, `TdeeShiftCalculator` (delegates to
  `TdeeEstimator.isMaterialShift`) and `TdeeEstimatesRepository.latestAtOrBefore` / `latestBefore`.
  Plan 14 loads the inputs (8 weeks of health rows, both TDEE estimates) and maps check-in/bodyweight
  rows into `PhysiqueCheckInInput` / `BodyweightLog`.

- Decisions: no live Health Connect reads at generation time (`externalWorkouts: const []`);
  `cnsReadinessPct` is null when no set exists by `windowEnd`; both correlation lines are always
  emitted (neutral when thin); physique confidence limited to its closed vocabulary. RPT-01/02/05 left
  unchecked (partial). SDK `state.*` verbs still no-op; this note is hand-written.

---

## Session update — 2026-10-03 (Phase 29 Plan 11 Completed)

- Completed Plan 29-11 (RPT-01, RPT-02, calculators half only): `NutritionSectionCalculator`
  (presence-based, `adherenceBandFraction = 0.10`) and `TrainingSectionCalculator` (tonnage via
  `ResolvedSet.tonnageKg`, e1RM movers behind the `isRepBased && isLoaded` gate). Both pure, no clock,
  null for an empty window. Plan 14 builds `NutritionWeekInputs` (without targets) and fills targets via
  `copyWith`.

- Decisions: a target with kcal <= 0 counts as no target; movers use 1-decimal rounded e1RM with
  rounded delta > 0; sets after `windowEnd` are excluded even inside the week. RPT-01/RPT-02 left
  unchecked (partial). SDK `state.*` verbs still no-op; this note is hand-written.

---

## Session update — 2026-10-03 (Phase 29 Plan 06 Completed)

- Completed Plan 29-06 (RPT-01, RPT-04, chore 5 + repository half only): wrote (NOT applied)
  `supabase/migrations/20261003000000_weekly_reports_v48.sql` with a drift-derived column-parity
  test, and `WeeklyReportRepository`, the sole writer of `weekly_reports`: payload written once in
  `insertSnapshot`, `saveNarrative` / `recordTdeeDecision` write-once, `markViewed` only when null.

- Decision (per 29-05): no unique key local or remote. One report per week is enforced inside
  `insertSnapshot`'s transaction; reads and mutators use the earliest live row by (generated_at, id).
  A tombstoned-only week is hard-deleted and regenerated.

- Note: migration apply is human-gated in plan 20; do not ship a build with local v48 before it.
  Provider wiring is plan 15. RPT-01/RPT-04 left unchecked (partial). SDK `state.*` verbs still
  no-op; this note is hand-written.

---

## Session update — 2026-10-03 (Phase 29 Plan 10 Completed)

- Completed Plan 29-10 (RPT-03, tap-path half only): weekly-report payload is matched before the
  `actionId` guard in both `onDidReceiveNotificationResponse` and `workoutNotificationTapBackground`;
  background taps queue `pending_weekly_report_open` (boolean), drained by `app.dart` at start and on
  resume; cold start handled via `getNotificationAppLaunchDetails`. No generation in any callback.

- Decision: queue holds a flag, not a week; the week is resolved at open time by
  `IsoWeek.forNotificationTap(clock.now(), weeklyReportTimeHHMM)`.

- Note: cold-start behaviour needs a real device (manual UAT in plan 20). The fasting tap path has the
  same latent cold-start gap (not changed). `AppPaths.weeklyReport` is registered in the router by
  plan 18. RPT-03 left unchecked (partial).

---

## Session update — 2026-10-03 (Phase 29 Plan 09 Completed)

- Completed Plan 29-09 (RPT-02, RPT-05, client-call half only): `WeeklyReportBackend` interface +
  `weeklyReportBackendProvider` (separate from `GeminiBackend`, both backends implement it, no
  existing fake touched) and database-free `WeeklyReportNarrativeService` with
  `NarrativeFailureKind { offline, unconfigured, quotaExhausted, rejected, unavailable }`.

- Decision: `weekly_report` sends no `privacyConsent` (open question 5 stays a human decision; adding
  a gate later is a one-field change). Causal wording and structural failures both map to `rejected`.

- Note: pre-existing dead test in `test/gemini_backend_service_test.dart` (physique check-in test
  nested after a `throw`); should be moved into `main()`. RPT-02/RPT-05 left unchecked (partial).

---

## Session update — 2026-10-03 (Phase 29 Plan 08 Completed)

- Completed Plan 29-08 (RPT-01, RPT-03, opt-in wiring half only): notifier setters,
  `weeklyReportNotificationSchedulerProvider`, `_syncWeeklyReport` in the settings listener and
  `syncAll()`, "Weekly report" toggle + "Report Time" row in notification settings, and
  `weekly_reports` documented in PRIVACY_POLICY / GDPR_ARTICLE_9_COMPLIANCE / DATA_TRUTH_TABLE.

- Decision: the toggle sub-label names Google Gemini (KB-03 exception, consent requires naming the
  processor). Owner to confirm wording. Open item recorded in the GDPR memo: whether an explicit
  `privacyConsent` step is needed for weekly aggregates (Phase 29 open question 5).

- Note: `notification_settings_view.dart` is 596 lines (cap 600); next edit should extract a part.

- Validation: `flutter test test/features/notifications/` 40 pass; analyze clean; check_structure
  baseline unchanged (57). RPT-01/RPT-03 left unchecked (partial-completion convention). Most SDK
  `state.*` verbs still no-op; this note is hand-written.

---

## Session update — 2026-10-03 (Phase 29 Plan 07 Completed)

- Completed Plan 29-07 (RPT-01, RPT-02, RPT-05, contract half only): pure-Dart
  `WeeklyReportPayload` (v1, strict `FormatException` parsing, impossible ISO weeks rejected),
  five section value classes with shared `ReportJson` readers, and `WeeklyReportFacts.fromPayload`
  (sanitised names, aggregates only, 8000-char cap with a deterministic reduction ladder).

- Decision: `hasSignal` excludes `tdee` (history-derived, D-06); `hasNarrativeSignal` is
  nutrition/training/recovery only. Null sections are omitted from the facts map.
  `fromPayload` has an optional `maxLength` used only by tests.

- Validation: `flutter test test/features/weekly_report` 124 pass; analyze clean on touched
  paths. RPT-01/RPT-02/RPT-05 left unchecked (partial-completion convention). SDK `state.*` verbs
  still no-op; this note is hand-written.

---

## Session update — 2026-10-03 (Phase 29 Plan 05 Completed)

- Completed Plan 29-05 (RPT-01, RPT-04, guard half only): OQ3 settled by
  `test/sync/weekly_reports_duplicate_pull_test.dart`. With a local unique key on
  (iso_year, iso_week), a pulled duplicate under another sync_uuid threw UNIQUE out of
  `SyncService._pullTable` (no per-row catch), aborting the whole pull cycle and never advancing
  the cursor. Fallback taken: the key was dropped from `WeeklyReports`; drift code, v48 schema
  dump and `schema_v48.dart` regenerated (diff vs old v48 = unique_keys only).

- Decision: plan 06's repository must enforce one-per-week inside its insert transaction and read
  the earliest row by (generated_at, id). No remote unique constraint either; table has no
  `created_at`.

- Added registration guard test (registries, spec, order, idx_sync_uuid, outbox upsert) and wipe
  test (`weekly_reports` cleared by `wipeAllLocalUserData`).

- Validation: full `flutter test` 2351 pass / 9 skipped; analyze 0 errors. RPT-01/RPT-04 left
  unchecked (partial-completion convention). SDK `state.*` verbs still no-op; this note is
  hand-written.

---

## Session update — 2026-10-03 (Phase 29 Plan 04 Completed)

- Completed Plan 29-04 (RPT-01, RPT-03, scheduler half only): `NotificationSettings` gained
  `weeklyReportEnabled` (default false, opt-in) and `weeklyReportTimeHHMM` (default 18:00) in
  constructor, copyWith, toJson and fromJson, tolerant of old blobs and wrong-typed values.
  `WeeklyReportNotificationScheduler` (id 5001, channel `weekly_report`, Sunday
  `dayOfWeekAndTime`, Clock-injected, generic lock-screen copy, static `weekly_report` payload in
  `weekly_report/domain`). Not yet wired: provider and `NotificationSyncService` are plan 08,
  tap path is plan 10.

- Decision: HH:MM is range-checked (0-23 / 0-59), so `25:00` schedules nothing rather than
  rolling into the next day. RPT-01/RPT-03 left unchecked (partial-completion convention).

- Validation: `flutter test test/features/notifications/` 30/30, analyze clean on touched paths,
  `check_structure` 57 violations (unchanged baseline).

- SDK `state.*` verbs still no-op on this STATE.md; `roadmap.update-plan-progress 29` worked.
  This note is hand-written.

---

## Session update — 2026-10-03 (Phase 29 Plan 03 Completed)

- Completed Plan 29-03 (RPT-02, RPT-05, server half only): `gemini-analyze` gained the
  `weekly_report` kind. `weeklyReportPrompt` (verbatim-number rule, "tended to go with"
  correlation-only wording with the cause-and-effect word list forbidden, at most 3 sentences
  plus 2 to 3 suggestions, no targets/training/medical, injection guard),
  `normalizeWeeklyReportResult` (summary <= 700, 2-3 suggestions <= 300, throws otherwise),
  `isValidWeeklyReportFacts` (object, <= 8000 serialized chars, 400 before any model call),
  `weeklyReportSystemInstruction` (core + nutrition + recovery, no programming) and a per-kind
  quota (default 5/day, `GEMINI_LIMIT_WEEKLY_REPORT`). No SQL change needed.

- Decision: RPT-02/RPT-05 left unchecked in REQUIREMENTS.md (partial-completion convention);
  the SDK `requirements.mark-complete` ticked them and I reverted. No client, report UI or
  deploy exists yet.

- Validation: `deno test --allow-env --allow-net .` 40 passed / 0 failed; `deno check
  index.ts` clean. **Function NOT deployed** (human-gated, plan 20).

- `roadmap.update-plan-progress 29` worked; other `state.*` verbs not used, note hand-written.
- Next: 29-04 (notification scheduler) and remaining Phase 29 plans.

---

## Session update — 2026-10-03 (Phase 29 Plan 02 Completed)

- Completed Plan 29-02 (RPT-01, RPT-04, persistence foundation only): `WeeklyReports` drift
  table at local schema **v48** (unique `(iso_year, iso_week)`, immutable `payloadJson`,
  write-once `narrativeJson`/`tdeeDecision`), guarded `from < 48` upgrade branch, registered
  in all four registries (`@DriftDatabase`, `syncedTableNames`, `syncTableSpecs`,
  `_fullyClearedTables`). Chores 1-4 of the schema bump are done (dump, generated
  `DatabaseAtV48`, retargeted `migration_test` + `schema_v25/27/28/29`, new v47 -> v48
  replay and existing-table guard test). Chore 5 (Supabase SQL) is plan 06's job.

- **Do not ship a build with local v48 until plan 06's migration is applied**: sync of
  `weekly_reports` would quarantine (PGRST204) after 8 attempts.

- Decision: RPT-01/RPT-04 left unchecked in REQUIREMENTS.md (partial-completion convention);
  no repository, generation or UI exists yet.

- Validation: full `flutter test` 2334 passed / 9 skipped / 0 failed; `flutter analyze` 0
  errors; `check_structure` 57 violations (unchanged baseline). `build_runner` took ~10 min
  on this machine. `drift_dev schema dump` warned it fell back to static analysis (space in
  the project path); v47 -> v48 JSON diff is exactly the new table.

- SDK `state.*` verbs still no-op on this STATE.md format; `roadmap.update-plan-progress`
  worked. This note is hand-written.

- Next: remaining Phase 29 Wave 1 plans (29-03 Edge Function kind, 29-04 notification scheduler).

---

## Session update — 2026-10-03 (Phase 29 Plan 01 Completed)

- Completed Plan 29-01 (RPT-01, RPT-03, RPT-05, foundation only): `IsoWeek` (Thursday-rule
  ISO key, DST-safe `DateTime(y, m, d + n)` windows, `tryCreate` for untrusted deep-link
  params, `forNotificationTap` resolving the week of the most recent Sunday-at-HH:MM trigger
  per user-confirmed OQ1), `CausalLanguageGuard` (single-source word list) and strict
  `WeeklyNarrative` (`tryDecodeStored` skips the guard so saved narratives never orphan), and
  the `weeklyReports` / `weeklyReport` route constants. `router.dart` registration is plan 18.

- Decision: RPT-01/03/05 left unchecked in REQUIREMENTS.md (partial-completion convention);
  only the foundation exists, no persistence, notification or UI yet.

- Validation: `flutter test test/features/weekly_report` 79/79, `flutter analyze` on touched
  paths clean, `check_structure` no new violations. Full suite not re-run (new files are
  self-contained; only `routes.dart` gained three additive members).

- SDK `state.*` verbs still no-op on this STATE.md format, so this note is hand-written.
- Next: remaining Phase 29 Wave 1 plans (29-02 drift table + schema v48, 29-03 Edge Function
  kind, 29-04 notification scheduler).

---

## Session update — 2026-09-30 (Phase 22 context gathered)

- Ran `/gsd:discuss-phase 22`. Codebase scouting found Primary Lift Strength
  Specialization is **not a blank slate** — a working version is already live
  in the builder (`PrimaryLiftSpecialization` → `smart_program_planner.dart`
  slot-need assembly, toggle in Step Parameters). Discussion focused on 3 real
  gaps against SPEC-01–03 plus split-flexibility scope, all now locked in
  `22-CONTEXT.md`: sticking-point branching is missing for bench/OHP/pull-up
  (D-12), no timeline-realism warning exists anywhere (D-08–D-11, resolved to
  reuse the existing Weeks picker rather than adding a new field), and the
  built-but-unwired `VolumeBands` system should be wired in as a warning-only
  check at both Create time and a live preview (D-04–D-07). Split support
  extends to Upper/Lower and PPL, not just Full Body (D-01–D-03). Dead code
  (`SquatSpecialization`, superseded and unreachable) is flagged for removal
  in the same phase.

- SDK `state.record-session` no-ops on this STATE.md format ("No session
  fields found in STATE.md"), consistent with every prior session's note in
  this file — this section is hand-written. `commit` SDK verb worked
  (`bc916a1`, `docs(22): capture phase context`).

- Next implementation focus: `/gsd:plan-phase 22` — CONTEXT.md's canonical_refs
  and decisions are ready for research/planning to consume.

---

## Session update — 2026-09-30 (Phase 27 Plan 13 Completed — Phase 27 COMPLETE, 13/13 plans)

- Completed Plan 27-13 (AIP-01, AIP-02, AIP-04), the final plan of the phase: wired the
  accepted Herculex AI brief's `musclePriorities` through the existing Dream Physique tuning
  seam (D-01), `splitType`/`periodizationModel` directly into `_split`/`_model` (D-03), and
  added `HerculexAiBriefService.persistBrief()` to `_create()` so an AI-built program's brief
  is persisted with provenance exactly once, never for other modes, non-fatally on failure
  (D-08). `phaseIntent` is surfaced via 27-11's existing mode-picker subtitle, no new field
  needed.

- **Session note:** this plan's first execution attempt was cut off mid-task by a Claude Code
  session rate limit. On resume, the partial working-tree changes were inspected (not
  discarded) — most of Task 1/2 were already correct; only cleanup, tests, and documentation
  remained.

- **Real bug found and fixed while finishing this plan's test coverage (Rule 1, in scope):**
  `_create()`'s non-manual follow-up path calls
  `JointPainRepository.watchCurrentStatuses().first`, which hangs indefinitely under widget-test
  `FakeAsync` — the exact same class of bug 27-12 already found and fixed for
  `HerculexAiBriefService.watchBriefForProgram()`. No test before this plan ever exercised the
  full non-manual create-block success path all the way to `ProgramReviewView` (the D-07
  characterization tests all expect a guardrail throw; the manual-mode tests skip this code
  path entirely since manual mode is exempt from it), so this was never caught until now. Fixed
  by adding `JointPainRepository.currentStatuses()`, a one-shot equivalent, mirroring 27-12's
  exact fix shape.

- Validation: `flutter test test/block_builder_view_test.dart` 24/24 passing (up from 17),
  `flutter test test/joint_pain_repository_test.dart` 7/7 passing, `flutter analyze` 0 errors
  on all touched files.

- **Phase 27 (Herculex AI Program Generation) is complete — 13/13 plans, AIP-01 through
  AIP-05 all satisfied.** Every wave's post-merge test gate was run and stayed clean
  throughout (Wave 1: 1687 tests / found+fixed one real cross-plan FK-inventory regression;
  Wave 2: 1708 tests, 0 failures; Wave 3: 1721 tests, 0 failures). The end-to-end Herculex AI
  flow works: select mode -> Generate -> guardrail-validated brief pre-fills Step 1-5
  (hand-editable) -> Create block -> persisted brief with provenance -> per-day rationale on
  the review screen (27-12) -> explicit confirmation via the unchanged `_confirm()`.

- A live production change was made this session with explicit user approval: plan 27-10's
  Supabase migration for `herculex_ai_program_briefs` was pushed to `ldzgyzigvbwofbswitrv` and
  independently verified via 4 read-only queries (11 columns, 4 RLS policies, 2 triggers,
  1 index) — see 27-10-SUMMARY.md.

- Next implementation focus: per the roadmap's non-numeric execution order
  (26 → 28 → 27 → 22 → 23 → 29 → 24 → 25), Phase 22 (Primary Lift Strength Specialization) is
  next. `/gsd:discuss-phase 22` to start.

## Session update — 2026-09-30 (Phase 27 Plan 12 Completed)

- Completed Plan 27-12 (AIP-04, closing it): `_DayCard` in `program_review_view.dart`
  now renders `AiDayRationaleCard` per day — the active Herculex AI brief's exact
  `dayRoles[].rationale` — additive to the existing per-slot `EmptySlotNotice`
  loop, conditional on an active `HerculexAiProgramBriefs` row with
  `source == 'herculex_ai'` for the reviewed program (D-09). Absent entirely for
  manual/smart/guided programs. `_confirm()` is byte-for-byte unchanged (verified
  via `git diff --unified=0`, zero changed lines in that method).

- **Deviation (Rule 1 - bug):** the plan's suggested `watchBriefForProgram(...)
  .first` read hung indefinitely (10-minute `flutter_test` timeout) under
  `tester.pump()`'s fake-async clock, even though the identical `.first` call
  resolves instantly in `herculex_ai_brief_service_test.dart`'s plain async
  tests. Fixed by adding `HerculexAiBriefService.readActiveBriefForProgram()` —
  a one-shot `getSingleOrNull()` query sharing the same active/source/
  newest-first shape via a new private `_activeBriefQuery()` helper (the watch
  stream and the one-shot read now share the same query definition). This was
  the plan's own documented fallback option, not a new mechanism.

- **REQUIREMENTS.md: AIP-04 marked complete** — the full chain (persistence
  27-04/27-10, service 27-09, review-screen rendering this plan) now holds
  end-to-end. This was the last of AIP-01–05 to close.

- Validation: `flutter test test/program_review_view_test.dart
  test/herculex_ai_brief_service_test.dart` — 20/20 passing (3 pre-existing
  empty-slot tests + 2 pre-existing sheet tests + 5 new per-day-rationale
  tests + 1 new `_confirm()`-unchanged navigation test + 7 pre-existing
  `HerculexAiBriefService` tests, plus 2 pre-existing replacement-sheet
  tests, all in one combined run). `flutter analyze` (full repo) — 0 errors,
  52 pre-existing warnings/info, none in this plan's 3 touched files.
  `dart run tool/check_structure.dart` — 57 pre-existing violations,
  unchanged count; `program_review_view.dart` was already over the 600-line
  cap before this plan (742 lines) and is now 786 lines — not a new
  violation, out of this plan's scope to split, flagged for a future cleanup
  pass. SDK `roadmap.update-plan-progress 27` and `requirements.mark-complete
  AIP-04` both worked and were used; `state.*` verbs still error/no-op on
  this STATE.md format ("Cannot parse Current Plan or Total Plans in Phase
  from STATE.md"), so this section is hand-written.

- **Phase 27 is now code-complete on AIP-01–05** (12/13 plans done — only
  27-13, the pre-fill/persistence wiring into `block_builder_view.dart`
  consuming plan 27-11's `_acceptedHerculexBrief`/`_herculexBriefProvenance`,
  remains). Per the non-numeric execution order
  (26 → 28 → 27 → 22 → 23 → 29 → 24 → 25), Phase 27 finishing clears the way
  for Phase 22 once 27-13 lands.

- Next implementation focus: Plan 27-13 (final plan in Phase 27's Wave 4 —
  pre-fill/persistence wiring in `block_builder_view.dart`).

---

## Session update — 2026-09-30 (Phase 27 Plan 11 Completed)

- Completed Plan 27-11 (AIP-01 reconfirmed, AIP-03, AIP-05): wired the Herculex AI
  mode into `block_builder_view.dart`'s Step 1 mode picker — the 4th
  `ProgramBuildMode.herculexAi` value, its mode-picker tile (UI-SPEC copy verbatim),
  and an explicit "Generate with Herculex AI" action (D-04: never auto-fired on mode
  selection, exactly one `generateBrief()` call per Generate/Regenerate tap).

- `_generateHerculexBrief()` (`actions.part.dart`) is the full state machine: calls
  `HerculexAiBriefService.generateBrief()`, then `ProgramGuardrails
  .validateConfiguration()` against the parsed brief's own `splitType`/
  `periodizationModel` (empty `mainMethodByDayLabel` — documented inline per the
  plan's interfaces section, since the brief never assigns per-day methods). Three
  distinct outcomes, each leaving the existing Smart/Guided recommendation as the
  active state (never a dead end): guardrail-passing success (`Applied` status chip

  + `Regenerate`, brief stored in `_acceptedHerculexBrief`/`_herculexBriefProvenance`
  for plan 27-13 to consume), guardrail rejection (`AiBriefRejectionBanner` with the
  validator's verbatim message, D-05), and the two distinct AIP-05 degradation
  messages (offline/unconfigured vs. over-quota, via
  `HerculexAiBriefException.isQuotaExhausted`).

- `AiBriefRejectionBanner` (plan 27-07) is reused for both D-05's 3-part
  heading/body/footer message and AIP-05's single-sentence degradation copy (full
  sentence in `heading`, empty `body`/`footer`) — one widget, two field-population
  shapes, per its caller-supplies-everything contract.

- **REQUIREMENTS.md: AIP-03 and AIP-05 marked complete.** Both were waiting
  specifically on this plan's UI wiring (the guardrail call + fallback for AIP-03,
  the degrade-to-Smart/Guided UI for AIP-05) per 27-08/27-09's explicit unchecked
  annotations. AIP-01 was already checked from 27-01's context but is now backed by
  a real 4th enum value. AIP-04 remains unchecked (plan 27-12's job — per-day
  rationale + review-gate wiring in `program_review_view.dart`, untouched by this
  plan).

- Validation: `flutter test test/block_builder_view_test.dart` — 17/17 passing (10
  pre-existing unchanged + 7 new covering every behavior case: no auto-fire on tile
  select, one call per tap, success+Applied, guardrail rejection, offline/
  unconfigured degradation, over-quota degradation, Regenerate re-fires exactly one
  new call). `flutter analyze` on all touched files — 0 issues. Full-repo `flutter
  analyze` — 0 errors (42 pre-existing warnings/info, matching the 27-08/27-09
  baseline, none new). `wc -l` confirms all touched files stay well under the
  600-line cap (`block_builder_view.dart` 419, `step_mode_and_split.part.dart` 547,
  `actions.part.dart` 272). SDK `roadmap.update-plan-progress 27` and
  `requirements.mark-complete` both worked and were used; `state.advance-plan`/
  `state.update-progress`/`state.record-metric`/`state.add-decision` still error/
  no-op on this STATE.md format ("Cannot parse Current Plan or Total Plans in
  STATE.md" / "Progress field not found" / "phase, plan, and duration required" /
  "summary required"), so this section is hand-written.

- Next implementation focus: Plan 27-12 (per-day AI rationale rendering +
  `program_review_view.dart` wiring) — the last plan before Wave 3 closes; Plan
  27-13 (pre-fill/persistence wiring, consuming this plan's
  `_acceptedHerculexBrief`/`_herculexBriefProvenance`) is Wave 4.

---

## Session update — 2026-09-30 (Phase 27 Plan 10 Completed — Wave 2 done)

- Completed Plan 27-10 (AIP-04, chore 5): wrote and **applied**
  `supabase/migrations/20260929000000_herculex_ai_program_briefs_v46.sql` to the live
  `ldzgyzigvbwofbswitrv` project. This is a `[BLOCKING]` human-gated schema push — the
  orchestrator asked the user for explicit go-ahead before running `supabase db push`
  (confirmed `ldzgyzigvbwofbswitrv`, not `jioesomepkauponjrena`, via `supabase projects
  list` first). User chose "push now."

- Independently verified via 4 read-only queries against the live project (not taken on
  the CLI's success message alone, per this plan's own anti-repeat-the-tdee-mistake
  design): 11/11 columns present with correct types, 4/4 owner-only RLS policies, 2/2
  triggers, 1/1 pull index (`herculex_ai_program_briefs_user_updated_idx`). Full query
  results recorded in `27-10-SUMMARY.md`.

- Side discovery: `supabase migration list` showed 0015/0016 already applied remotely —
  CLAUDE.md's "0015 and 0016 are both outstanding" gotcha note is now stale (only
  `20260929000000` was pending before this push). Worth a CLAUDE.md correction in a
  future session; not fixed here (scope discipline).

- AIP-04 requirement annotation updated but left **unchecked** — this plan only closes
  the schema/sync half; the review-gate UI (rationale rendering, plan 27-12) is still
  outstanding.

- **Phase 27 Wave 2 is now complete (27-08, 27-09, 27-10 — 10/13 plans in the phase).**
  Wave 1's post-merge test gate caught one real cross-plan regression (`fk_constraints_test.dart`'s
  hard-coded FK inventory needed plan 27-04's new edge added — fixed, commit `d6334f7`).
  Two other test failures seen mid-Wave-2 (`tdee_recalibration_test.dart`,
  `wear_workout_sync_service_test.dart`) were confirmed flaky/timing artifacts of running
  the full suite under machine load, not real regressions — both pass cleanly in isolation.

- Next implementation focus: Wave 3 (plans 27-11, 27-12).

---

## Session update — 2026-09-30 (Phase 27 Plan 09 Completed)

- Completed Plan 27-09 (AIP-02, partial on AIP-03/AIP-05): `HerculexAiBriefService`
  (`lib/features/programs/data/herculex_ai_brief_service.dart`) — the single
  generate -> parse -> persist -> read seam for Herculex AI program briefs,
  modeled directly on `DreamPhysiqueService`'s "call Gemini, parse strictly,
  translate failures into a UI-facing exception" shape. `generateBrief()` calls
  `GeminiBackend.generateProgramBrief()`, parses via `ProgramBrief.fromJson`, and
  translates every failure (unconfigured, network, quota, malformed JSON) into a
  `HerculexAiBriefException` — never a raw technical string reaches the caller.

- `HerculexAiBriefException` copies `DreamPhysiqueAnalysisException`'s exact shape
  (`message`, `recoverable` default `true`, `toString() => message`) plus one
  addition: `isQuotaExhausted` (bool, default `false`) — the AIP-05
  failure-category signal, detected by substring match (`'used up'` /
  `'try again tomorrow'`) against the Edge Function's real 429 message shape
  (`supabase/functions/gemini-analyze/index.ts:283`). This is a classification
  signal, not final UI copy — plan 27-11 picks the exact AIP-05 degradation
  string from `isQuotaExhausted`, keeping this data-layer service UI-copy-agnostic.

- `persistBrief()` is confirmed (by grep) the ONLY code path in
  `lib/features/programs/` that touches `HerculexAiProgramBriefs` — closes the
  "UI touches drift directly" anti-pattern RESEARCH.md explicitly warned this
  phase not to repeat. Clock-injected `confirmedAt`, never `DateTime.now()`
  directly. `watchBriefForProgram(programId)` returns a live
  `Stream<HerculexAiProgramBriefData?>` (`watchSingleOrNull`, active-only, newest
  `confirmedAt` first), mirroring `_loadDreamPhysiquePriorities()`'s existing
  query shape as a stream per the house StreamProvider-over-FutureProvider rule.

- One mechanical correction from the plan's illustrative `<action>` pseudocode:
  `HerculexAiProgramBriefsCompanion.insert()`'s actual generated constructor
  (verified by reading `database.g.dart`) takes `programId`/`briefJson` as plain
  required `int`/`String`, not `Value(programId)`/`Value(briefJson)` as the
  plan's pseudocode showed — drift only wraps optional/defaulted columns in
  `Value<T>` for `.insert()`. Not a design deviation, just matching the real
  generated API.

- **REQUIREMENTS.md: AIP-02 marked complete** (the brief-generation contract is
  now provably true end-to-end — request, transport, strict parse — independent
  of UI wiring). **AIP-03 and AIP-05 reverted to unchecked** despite being in
  this plan's `requirements` frontmatter list: AIP-03 needs the guardrail-
  rejection-triggers-fallback behavior (`ProgramGuardrails.validateConfiguration()`
  call + fallback), and AIP-05 needs the actual degrade-to-Smart/Guided UI
  behavior when `isQuotaExhausted`/offline/unconfigured — both are plan 27-11's
  job, not delivered here. Annotations updated accordingly, following the
  established partial-completion convention (see 27-03/27-05/27-06/27-08 notes
  above). AIP-04 annotation updated to reference this plan's new read/write
  service, still unchecked pending 27-12's review-gate wiring.

- Validation: `flutter test test/herculex_ai_brief_service_test.dart` — 7/7
  passing. `flutter analyze` on both touched files — 0 issues. `dart run
  tool/check_structure.dart` — no new violations (140 and 330 lines
  respectively, both well under the 600-line cap). SDK `roadmap.update-plan-
  progress 27` and `requirements.mark-complete` both worked and were used;
  `state.advance-plan`/`state.update-progress` still error/no-op on this
  STATE.md format ("Cannot parse Current Plan or Total Plans in Phase" /
  "Progress field not found"), so this section is hand-written.

- Next implementation focus: Plan 27-10 (Supabase migration for
  `herculex_ai_program_briefs`, chore 5 of the schema bump — deferred from
  27-04) — or, per Wave 2's dependency order, Plan 27-11 (wires
  `HerculexAiBriefService` and `ProgramGuardrails.validateConfiguration()` into
  `block_builder_view.dart`'s Herculex AI build mode, closing AIP-03/AIP-05).
  See 27-*-PLAN.md files for the exact wave order.

---

## Session update — 2026-09-30 (Phase 27 Plan 08 Completed)

- Completed Plan 27-08 (AIP-03, partial): extracted the two inline Max-Effort-per-week
  and 6-day-PPL-with-Max-Effort `StateError` throws out of `block_builder_view.dart`'s
  `_create()` (now `actions.part.dart`, per plan 27-01's split) into a new
  `ProgramGuardrails.validateConfiguration({buildMode, model, split,
  mainMethodByDayLabel})` static method (D-06) — a sibling of the existing
  `validateMaxEffortWeek`, returning `List<ProgramGuardrailIssue>` rather than
  throwing, so both `_create()` and the future Herculex AI brief validator (plan
  27-11) can share it and pick their own UX.

- `_create()` retrofitted for all build modes (manual/smart/guided today; Herculex
  AI in 27-11) to call the shared method and throw `StateError` with the first
  blocking issue's message — preserving the exact single-StateError-per-call
  contract its surrounding try/catch expects. Manual mode's exemption (`buildMode
  != ProgramBuildMode.manual` gating both checks) now lives inside the guardrail
  method itself.

- Zero behavior drift, proven by plan 27-02's regression net: all 10 tests in
  `test/block_builder_view_test.dart` pass unchanged, including all 6
  characterization tests (2 conditions x 3 build modes) written specifically to
  catch message-text or trigger-condition drift during this extraction.

- 5 new unit tests added to `test/program_guardrails_test.dart` (8/8 passing
  total, 3 pre-existing + 5 new) covering both trigger conditions individually,
  manual-mode exemption with both triggers present, no-trigger empty result, and
  both conditions firing simultaneously (2 distinct issues returned, not just the
  first).

- **AIP-03 remains unchecked in REQUIREMENTS.md** (annotation updated, not marked
  complete), following the established partial-completion convention: this plan
  only delivers the guardrail-consolidation half. The Herculex AI brief
  validator's actual call to `validateConfiguration()` and the fallback-to-
  deterministic behavior (plan 27-11) still don't exist.

- Validation: `flutter test test/program_guardrails_test.dart
  test/block_builder_view_test.dart` — 18/18 passing. `flutter analyze` on all 4
  touched files — 0 issues. Full-repo `flutter analyze` — 0 errors (42
  pre-existing warnings/info, none new, none in touched files — a slight
  improvement over Phase 28's logged 44). `wc -l` confirms all touched files
  stay well under the 600-line cap (`program_guardrails.dart` 206,
  `block_builder_view.dart` 403, `actions.part.dart` 205). SDK
  `roadmap.update-plan-progress 27` worked and was used; `state.advance-plan`
  still errors ("Cannot parse Current Plan or Total Plans in Phase from
  STATE.md") on this STATE.md format, so this section is hand-written.

- Next implementation focus: Plan 27-09 (or next plan in Phase 27's Wave 2 order
  — see 27-*-PLAN.md files; 27-11/27-12 are the two plans that will actually call
  `ProgramGuardrails.validateConfiguration()` from the Herculex AI brief
  validator).

---

## Session update — 2026-09-30 (Phase 27 Plan 07 Completed, Wave 1 complete)

- Completed Plan 27-07 (AIP-03, AIP-04, partial on both — UI half only): the two
  small new presentational widgets Herculex AI's UI-SPEC Component Inventory
  calls for — `AiBriefRejectionBanner(heading, body, footer)` (warning-tinted,
  D-05's rejection/degradation message shape) and `AiDayRationaleCard(rationale)`
  (primary-tinted, fixed "Why this day" heading, renders `dayRoles[].rationale`
  verbatim, D-09). Both are visual siblings of `EmptySlotNotice` (same
  `Container`/`Row`/icon/`Expanded(Text)` shape) but not reuses of it, and both
  read colors exclusively via `context.hx.*` — zero `AppColors`/literal-color
  usage, confirmed by grep — per UI-SPEC's scope-local token rule for new code
  in this otherwise-legacy-`AppColors` phase.

- `AiBriefRejectionBanner`'s heading/body/footer are all required constructor
  parameters (never hardcoded) so plan 27-11 can reuse the one widget for both
  the D-05 guardrail-rejection message and the distinct AIP-05
  offline/unconfigured/over-quota degradation copy. `AiDayRationaleCard`'s
  heading is a widget-internal constant per UI-SPEC's explicit note it never
  varies.

- Both widgets are self-contained, independently testable UI primitives with
  no overlap with the other 6 Wave 1 plans' files — this was the last plan in
  Wave 1. **Phase 27 Wave 1 is now complete (7/13 plans: 27-01 through 27-07)**;
  Wave 2 (27-08 onward, including the guardrail extraction and the two
  consuming plans 27-11/27-12) is next.

- **AIP-03/AIP-04 remain unchecked in REQUIREMENTS.md** (annotations updated,
  not marked complete), following the KB-02/KB-04/TDEE-05/27-02..27-06
  partial-completion convention: this plan only delivers the two widgets in
  isolation — neither is imported/wired into `block_builder_view.dart` or
  `program_review_view.dart` yet (plans 27-11/27-12), and no brief is
  generated end-to-end yet (plan 27-09).

- Validation: `flutter test test/ai_brief_rejection_banner_test.dart
  test/ai_day_rationale_card_test.dart` — 12/12 passing (light+dark theme x 6
  cases each). `flutter analyze` on all 4 touched files — 0 issues.
  `dart run tool/check_structure.dart` — 57 pre-existing violations, none new
  (both new files well under the 600-line cap: 77 and 63 lines). SDK
  `roadmap.update-plan-progress 27` worked and was used; `state.*` verbs still
  no-op on this STATE.md format, so this section is hand-written.

- Next implementation focus: Phase 27 Wave 2 (plan 27-08 — guardrail
  extraction into `ProgramGuardrails.validateConfiguration()` — is the next
  plan per ROADMAP.md's wave order; see 27-*-PLAN.md files).

---

## Session update — 2026-09-30 (Phase 27 Plan 06 Completed)

- Completed Plan 27-06 (AIP-02, AIP-03, partial on both): the `gemini-analyze` Edge
  Function's `program_brief` kind — a 9th `GeminiKind`, fully wired end-to-end on the
  server side. `programBriefPrompt()` (new in `prompts.ts`) is the first real consumer
  of Phase 26's `buildSystemInstruction()`/`knowledge_base.ts` `programming` segment,
  unused by all 8 prior kinds. `program_brief` gets its own 10/day quota bucket
  (`dream_physique` tier, per RESEARCH.md's Open Question 1 recommendation),
  fail-closed on RPC error per Phase 26's D-13, isolated from the other 8 kinds.

- `normalizeProgramBriefResult()` (exported from `index.ts`) is the server-side first
  line of the D-02 two-tier defense: rejects (throws, never defaults) any unknown
  `splitType`/`periodizationModel`/`dayRoles[].role`/`muscleId`, mirroring
  `normalizeProgrammingProfile`'s existing `canonicalProgrammingMuscleIds.has()`
  pattern via three new canonical id `Set`s (`canonicalSplitTypeIds`,
  `canonicalPeriodizationModelIds`, `canonicalDayStressRoleIds`), populated
  byte-for-byte from the Dart enums in `split_template.dart`/`periodization.dart`/
  `programming_models.dart`. Plan 27-03's `ProgramBrief.fromJson` remains the
  authoritative client-side gate — this is the first line, not a replacement.

- The prompt explicitly forbids exercise lists/sets/reps/load/RPE/tempo/metcon time
  caps and never asks for or accepts an `experienceLevel` field, copying
  `dreamPhysiquePrompt`'s exact sidestep of the 5-tier/3-tier `ExperienceLevel`
  mapping question (Pitfall 5) rather than building new collapse logic.

- Canonical id lists recorded in 27-06-SUMMARY.md for cross-check against plan
  27-03's Dart-side strict parser: `canonicalSplitTypeIds` (12 values),
  `canonicalPeriodizationModelIds` (5 values), `canonicalDayStressRoleIds` (4
  values) — both sides enumerate the same Dart enum's `.id` field, so no drift
  is possible unless one side is edited without the other.

- **AIP-02/AIP-03 remain unchecked in REQUIREMENTS.md** (annotations updated, not
  marked complete), following the KB-02/KB-04/TDEE-05/27-03/27-04/27-05
  partial-completion convention: this plan delivers only the server-side half. The
  calling `HerculexAiBriefService` (27-09) still doesn't exist, so no brief has ever
  been generated end-to-end yet.

- Validation: `deno test supabase/functions/gemini-analyze/` (full directory, 5 test
  files including the new `program_brief_test.ts`) — 17/17 passing, 0 regressions in
  the 8 pre-existing kinds. `deno check index.ts prompts.ts` — 0 type errors. `git
  diff --stat` confirmed only additive changes to both files (the sole `-` line is the
  `GeminiKind` union's trailing `;` relocating to make room for the new value). This
  plan is server-side only (TypeScript/Deno) and touches no Dart/Flutter file, so
  `flutter analyze`/`flutter test` were not run — independent of the other Wave 1
  plans per the plan's own note. SDK `roadmap.update-plan-progress 27` worked and was
  used; `state.*` verbs still no-op on this STATE.md format, so this section is
  hand-written.

- Next implementation focus: remaining Phase 27 Wave 1/2 plans (27-07 through 27-13
  — see 27-*-PLAN.md files for wave order; 27-06/27-05/27-04/27-03 have now delivered
  the domain model, transport (both directions), persistence target, and Edge
  Function kind — 27-09's `HerculexAiBriefService` is the next piece that actually
  connects them end-to-end).

---

## Session update — 2026-09-30 (Phase 27 Plan 05 Completed)

- Completed Plan 27-05 (AIP-02, AIP-03, partial on both): `GeminiBackend.
  generateProgramBrief()` added across all three tiers — the abstract
  interface, `UnconfiguredGeminiBackend` (throws the shared
  `_notConfigured()` Exception, verified identical to every sibling
  method's throw), and `SupabaseGeminiBackend` (`'kind': 'program_brief'`,
  text-only `_invoke` body, no images/privacyConsent block). Returns a
  `(Map<String, dynamic> result, Map<String, dynamic> provenance)` Dart
  record — the only `GeminiBackend` method that surfaces provenance.

- Per RESEARCH.md's Pitfall 2, `_resultMap()` (which the 8 existing
  callers all use) silently discards the wire response's `provenance` key.
  Rather than widen that shared contract, added a new sibling
  `_resultWithProvenance()` that calls `_resultMap()` internally (reusing
  its validation, zero duplicated cast logic) and additionally reads
  `data['provenance']`, defensively casting or falling back to an empty
  map — never throwing on missing provenance. `_resultMap()` and all 8
  existing callers are untouched.

- Updated all 5 test-only classes across 4 files that `implements
  GeminiBackend` directly (a breaking change once the interface gained an
  abstract method): `_FakeGeminiBackend` (gemini_food_analyzer_service_
  test.dart, canned-return convention), `_MockGeminiBackend` AND
  `_FailingGeminiBackend` (dream_physique_service_test.dart — this file
  has *two* direct implementers, not one as the plan's `<interfaces>`
  section stated; both were found via grep and updated),
  `_MockSupplementBackend` (supplement_ai_service_test.dart),
  `_MockGeminiBackend` (body_fat_ai_service_test.dart) — the latter three
  all use the `UnimplementedError()` convention.

- New `test/gemini_backend_service_test.dart` (5 tests): unconfigured-throw
  message parity against a sibling method, plus 4 cases for the
  provenance-extraction logic via a standalone helper mirroring the
  private `_resultWithProvenance` method (success, missing provenance,
  loose-Map provenance, invalid result still throws) — direct testing of
  `SupabaseGeminiBackend` itself was not attempted since no existing test
  in this codebase mocks `SupabaseClient.functions.invoke`; the actual
  `'kind': 'program_brief'` body construction is verified by code read,
  to be exercised end-to-end once 27-06/27-09 exist.

- **AIP-02/AIP-03 remain unchecked in REQUIREMENTS.md** (annotations
  updated, not marked complete), following the KB-02/KB-04/TDEE-05/27-03/
  27-04 partial-completion convention: this plan delivers only the
  client-side transport method. The Edge Function `program_brief` kind
  (27-06) and the calling `HerculexAiBriefService` (27-09) still don't
  exist.

- Validation: `flutter test test/gemini_backend_service_test.dart
  test/gemini_food_analyzer_service_test.dart
  test/dream_physique_service_test.dart test/supplement_ai_service_test.dart
  test/body_fat_ai_service_test.dart` — 19/19 passing. `flutter analyze`
  on all 6 touched files: 0 issues. Full-repo `flutter analyze`: 42
  pre-existing info/warning issues, 0 errors, none in this plan's files.
  SDK `roadmap.update-plan-progress 27` worked and was used; `state.*`
  verbs still no-op on this STATE.md format, so this section is
  hand-written.

- Next implementation focus: Plan 27-06 (Edge Function `program_brief`
  kind — prompt, quota tier, strict server-side normalizer; Wave 1's next
  plan per ROADMAP.md).

---

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
**Current focus:** Phase 29 — weekly-report-herculex-ai-narrative

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
- **Phase 27: Herculex AI Program Generation** — Complete, 13/13 plans, 2026-09-30. AIP-01–05 all satisfied. Full end-to-end flow: mode selection, generation, guardrail validation, pre-fill into existing editable screens, persisted brief with provenance, per-day rationale on the review screen, explicit confirmation. Supabase migration for `herculex_ai_program_briefs` applied and independently verified live on `ldzgyzigvbwofbswitrv`.
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
