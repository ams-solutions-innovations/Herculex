---
phase: 29-weekly-report-herculex-ai-narrative
plan: 24
subsystem: weekly_report
tags: [gap-closure, WR-07, RPT-04, verification]
requires: [29-21, 29-22, 29-23]
provides:
  - WeeklyReportInProgress open result
  - "Week still in progress" view state
affects: [weekly_report controller, weekly_report view]
key-files:
  modified:
    - lib/features/weekly_report/application/weekly_report_controller.dart
    - lib/features/weekly_report/presentation/views/weekly_report_view.dart
    - test/features/weekly_report/weekly_report_controller_test.dart
    - test/features/weekly_report/weekly_report_view_test.dart
    - test/features/weekly_report/weekly_report_providers_test.dart
decisions:
  - "Running week before canSnapshot with no row returns WeeklyReportInProgress: no row, no narrative, no dismissed marker"
  - "Existing rows for the running week are still shown (stored row wins over in-progress)"
requirements: [RPT-03, RPT-04]
completed: 2026-10-04
---

# Phase 29 Plan 24: WR-07 in-progress state and final gap-closure verification

The controller now refuses to freeze the running ISO week before it is due (Sunday at or after the configured time) and the view shows "Week still in progress" with the ready time; the due-week flows (notification tap, dashboard card) are untouched because they only target weeks that `canSnapshot` accepts.

## Tasks

| Task | Commit | Result |
| ---- | ------ | ------ |
| 1 Controller InProgress | f6a1ed9 | 7 new tests (no row, existing row, Sunday 17:59, future week NoData + marker, ended week, opt-in off, concurrent opens) |
| 2 View state | c6a05e4 | 3 view tests, 2 providers tests (due week equals notification-tap week and canSnapshot is true; Tuesday due week is the ended week) |
| 2b import sort | (style commit) | analyzer `directives_ordering` fix |
| 3 Verification | this docs commit | gates below |

Existing controller fixtures had already been rebased to a Sunday-due clock by 29-21, so no duplicate rebasing was needed.

## WR-01..WR-07 closure

| WR | Status | Evidence |
| -- | ------ | -------- |
| WR-01 | closed | `_db.delete` count in weekly_report_repository.dart is 0 (tombstones kept, 29-21) |
| WR-02 | closed | `_pickWinner` used by 7 sites in the repository; winner tests pass |
| WR-03 | closed | `applyTdeeDecision` (atomic, rollback tests) and `isActionableWeek` used in weekly_report_tdee_actions.dart (29-22) |
| WR-04 | PARTLY closed | In index.ts `prepareWeeklyReportRequest` (line ~305) runs before `bumpUsage` (line ~312), so the 400 validation path no longer spends quota. Failed or rejected generations and manual retries still spend a unit, by design; limit kept at 5/day |
| WR-05 | closed | `<facts>` delimiter in prompts.ts, `assertNumbersInFacts` in index.ts, `facts:` passed in the narrative service (29-23) |
| WR-06 | closed | `finally` in tdee_shift_card.dart (29-22) |
| WR-07 | closed | `canSnapshot` in service (guard in generate) and controller (before generate); this plan adds the UI state |

## Final gates

- flutter analyze: 0 errors (44 issues, all pre-existing warnings/infos in unrelated test files; the one weekly_report info was fixed).
- flutter test (full): 2789 passed, 9 skipped, all green.
- test/features/weekly_report/: 489 passed.
- dart run tool/check_structure.dart: exits 1 with 57 violations, all "file over 600 lines" in unrelated files (workouts etc.); none in weekly_report, no new violation from this plan. CLAUDE.md's "51" is stale.
- Deno (gemini-analyze): 49 passed, 0 failed. Needs `--allow-net` in addition to `--allow-read --allow-env` (index_test.ts starts Deno.serve); the plan's command without it reports uncaught errors.
- No change under supabase/migrations, lib/data/local, drift_schemas since before 29-21; no 29-01..29-20 plan docs edited. .claude/settings.json and outputs/ not staged.

## Deviations from Plan

- The "Sunday shows the real report and creates one row" widget test was not written as a view test: the view harness uses a fake controller. That behaviour is covered at controller level (existing Sunday-due tests plus the new Sunday 17:59 and ended-week cases) and the providers test.
- Flaky pre-existing test noted in 29-23 ("reads equal generatedAt falls back to the lowest id") passed in the full run this time; still worth a look.

## Residual items

- IN-01 (stale SharedPreferences cache in pending-open queue) untouched.
- IN-02 (cold-start tap navigation before router settles) untouched.
- WR-04 only partly closed (see above).
- Server string cap is 120 chars while Dart allows 160 for correlation statements; a 121-160 char statement would pass Dart but be rejected server-side.
- 29-23 dropped the knowledge-range number allowance: only integers 0..60 are always allowed, so a figure such as "1.6 g/kg" or "150 g" quoted from knowledge text is rejected unless it is in the facts.
- Sleep is supplied as decimal hours (e.g. 7.2); "7h 20m" style conversions above 60 would be rejected by the number check.
- The orchestrator must deploy `supabase/functions/gemini-analyze` before the number check and delimiter change take effect on the live function.

## Self-Check: PASSED
