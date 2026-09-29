---
phase: 27-herculex-ai-program-generation
plan: 02
subsystem: testing
tags: [flutter-test, widget-tests, program-guardrails, characterization-tests]

# Dependency graph
requires:
  - phase: 27-herculex-ai-program-generation (plan 01)
    provides: block_builder_view.dart split into part/part-of mixins, with
      _create() confirmed stable in actions.part.dart
provides:
  - Widget tests pinning block_builder_view.dart's _create() current inline
    Max-Effort-per-week (>2) and 6-day-PPL-with-Max-Effort StateError throws,
    across manual/smart/guided build modes, against the UNREFACTORED code
  - Documented, reusable tap sequences (Step 4 split chip, Step 3 periodization
    radio, Step 5 per-slot "Max Effort" method chip) for reaching each
    guardrail condition
  - Confirmation that manual mode is exempt from both checks today (creates
    successfully rather than throwing) - the pre-refactor baseline plan 27-08
    must preserve
affects: [27-08]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "appDatabaseProvider.overrideWithValue(await openTestDatabase()) to
      exercise a widget's real create-and-navigate path in a widget test,
      instead of relying on the swallowed-exception default AppDatabase()
      that every other test in this file implicitly depends on failing
      silently"

key-files:
  created: []
  modified:
    - test/block_builder_view_test.dart

key-decisions:
  - "Isolated the two guardrail conditions with different split choices: A/B/C
    (3 distinct slots, not PPL) for the Max-Effort-per-week>2 case, and 6-day
    Push/Pull/Legs + Max Effort periodization for the PPL case - so each test
    trips exactly one condition, never both at once."
  - "Manual-mode cases assert successful creation (navigates to
    ProgramReviewView, no 'Could not create the block' SnackBar) rather than
    absence of a specific message, per the plan's explicit instruction that
    this is an equally valuable characterization of the current buildMode !=
    manual exemption."
  - "Overrode appDatabaseProvider with an in-memory openTestDatabase() (the
    same helper training_blocks_view_test.dart uses) for the whole new group,
    even though the 4 throw-path tests never reach a DB write - needed so the
    2 manual-mode success-path tests can actually call
    createProgramFromSplit() against a real schema instead of the
    silently-failing default AppDatabase()."

patterns-established: []

requirements-completed: [AIP-03]

# Metrics
duration: 75min
completed: 2026-09-29
---

# Phase 27 Plan 02: Characterize _create()'s inline guardrail throws Summary

**Six new widget tests in test/block_builder_view_test.dart pin the exact current Max-Effort-per-week (>2) and 6-day-PPL+Max-Effort StateError messages for smart/guided modes, and the current manual-mode exemption, before plan 27-08 extracts the checks into ProgramGuardrails.validateConfiguration().**

## Performance

- **Duration:** ~75 min (includes an extended environment-contention delay documented under Issues Encountered)
- **Started:** 2026-09-29T19:53:40Z
- **Completed:** 2026-09-29T21:08:23Z
- **Tasks:** 1 (`type="auto"`)
- **Files modified:** 1

## Accomplishments
- Pinned both of `_create()`'s inline guardrail `StateError` throws (Max-Effort-per-week > 2 at `actions.part.dart:73-77`, and 6-day-PPL + Max Effort at `actions.part.dart:78-84`) with widget tests that drive the full 6-step builder flow for smart, guided, and manual build modes - closing the RESEARCH.md Pitfall 4 / Wave-0 gap (no prior test exercised these two throws at all).
- Proved the exact current message text verbatim (including the em dash in `PeriodizationModel.maxEffort.label` and the en dash in the PPL message) via `find.textContaining`, so plan 27-08's extraction has an immediate regression net for both trigger condition and copy.
- Proved manual mode's current exemption is real: with the identical inputs that trip each guardrail in smart/guided mode, manual mode instead completes `_create()` successfully and navigates to `ProgramReviewView` - this is the behavior plan 27-08 must preserve when it retrofits all four (including the future Herculex AI) build modes onto the shared `ProgramGuardrails.validateConfiguration()` method.
- Documented reusable tap sequences for future plans (see below) instead of leaving them buried in test code only.

## Task Commits

1. **Task 1: Characterize the Max-Effort-per-week and 6-day-PPL+Max-Effort throws across manual/smart/guided** - `a964422` (test)

**Plan metadata:** (this commit)

## Files Created/Modified
- `test/block_builder_view_test.dart` - Added a new `group('D-07 characterization: _create() inline guardrail throws', ...)` with 6 `testWidgets` cases (2 conditions × 3 build modes), plus 3 shared top-level helpers (`_pumpBuilder`, `_continue`, `_createBlock`) and 3 new imports (`app/providers.dart`, `data/local/database.dart`, `program_review_view.dart`, and relative `support/test_database.dart`).

## Reusable Tap Sequences (for plan 27-08)

Recorded here per this plan's `<output>` instruction, so 27-08 can reuse them when it extends this same test file with post-refactor coverage of `ProgramGuardrails.validateConfiguration()`:

- **Max-Effort-per-week > 2:** Step 4 (`_stepSplit`) — tap the split chip labelled **`'A / B / C'`** (`SplitType.abc`, 3 distinct day slots, not PPL, so the condition is isolated). Step 5 (`_stepContentAndMethods` / `_programRhythmCard`) — tap **`find.text('Max Effort').at(i)`** for `i` in `0, 1, 2` (one "Max Effort" choice chip renders per slot's "main exercise" card, in slot order).
- **6-day PPL + Max Effort:** Step 3 (`_stepParameters`) — tap the periodization radio card labelled **`'Max Effort — Westside (Conjugate)'`** (note: em dash, `PeriodizationModel.maxEffort.label`). Step 4 (`_stepSplit`) — tap the split chip labelled **`'Push / Pull / Legs'`** (`SplitType.ppl`, defaults to 6 days/week). Leave every Step 5 day method at its Auto default (0 explicit Max Effort selections) so only the split+model condition trips.
- **Exact current message text** (verbatim, confirm against `actions.part.dart` before reuse - do not paraphrase):
  - `'A Smart program can use at most two Max Effort patterns per week.'`
  - `'A six-day PPL would create three Max Effort days. Use per-slot Max Effort or choose a Conjugate 3–4 day structure.'` (en dash, `U+2013`, between `3` and `4`)
- **DB wiring for any test that must reach `createProgramFromSplit`:** override `appDatabaseProvider` with `await openTestDatabase()` (from `test/support/test_database.dart`) - the default `AppDatabase()` used by every other test in this file fails to open under `flutter_test` and is only safe because `_loadDreamPhysiquePriorities()` swallows the failure; `_create()`'s actual DB writes are not similarly guarded.

## Decisions Made

- Used `SplitType.abc` (not PPL) for the Max-Effort-per-week condition, so exactly 3 "Max Effort" chips exist and selecting all 3 cannot also accidentally trip the PPL condition (different split entirely).
- Left every Step 5 day method at Auto (0 explicit Max Effort selections) for the PPL condition, so the per-week-count condition cannot fire alongside it.
- Asserted manual-mode success via `find.byType(ProgramReviewView)` plus absence of the `'Could not create the block'` SnackBar, rather than only the latter - a stronger characterization of "creation genuinely succeeded" versus "failed for some unrelated reason that happens not to match either guardrail string."
- Added `await tester.pumpWidget(const SizedBox.shrink()); await tester.pump(const Duration(milliseconds: 10));` at the end of every new test, matching the existing file's convention (needed because disposing the `ProviderScope` cancels drift's watch-stream, which schedules a zero-duration cleanup timer that trips flutter_test's "timer still pending" assertion if the frame doesn't get one more pump - discovered via the first test run, see Issues Encountered).

## Deviations from Plan

None - the plan's action steps (read `_create()`, drive the 6-step flow, isolate each condition, assert manual-mode exemption) were followed as written. The specific split choices (`SplitType.abc` for condition 1, keeping the plan's own suggested PPL split for condition 2) and the `appDatabaseProvider` override were within the plan's own "read the actual widget tree during execution to find the correct tap targets" and "adapt the tap path per mode" latitude, not departures from it.

## Issues Encountered

- **Pending-timer test failure (fixed within Task 1, no deviation entry needed - same fix category as the plan's own referenced async-pattern conventions):** the first run of the new tests failed with `A Timer is still pending even after the widget tree was disposed` on the very first new test. Root cause: unlike this plan's new tests, none of the 4 *existing* tests in the file exercise `_create()`, so they never dispose a `ProviderScope` holding live drift stream subscriptions opened by `_create()`'s DB writes; disposing without one extra pump left a zero-duration drift cleanup timer pending. Fixed by adding the existing file's own `pumpWidget(SizedBox.shrink()) + pump(10ms)` unmount pattern (already used by all 4 pre-existing tests, just not yet copied into the ones this plan added) to every new test.
- **Severe environment resource contention during full-repo verification (unrelated to the code change, not fixed - documented for the record):** after the target file's tests and analyze both passed cleanly, three separate attempts at a full-repo `flutter analyze` hung indefinitely with near-zero CPU time (0.03-0.06s after several minutes each), confirmed via `Get-Process`/`Get-CimInstance` that the process was alive but making no progress. Three long-lived `dart.exe ... flutter_tools.snapshot daemon` processes (one per open VS Code window) were running throughout this session; a stray orphaned `flutter test` process from this task's own first (pending-timer) failure was also found and killed. A PowerShell `Get-Process` diagnostic call itself took over 120s to return at one point, indicating the whole machine was under heavy resource contention at the time, not something specific to `flutter analyze`. This is an environment/IDE-tooling condition, not a defect introduced by this plan's change - **a full-repo `flutter analyze` and `flutter test` should be re-run once the local machine is not under this contention**, since this session could only validate the touched file in isolation (see Validation below).

## User Setup Required

None - no external service configuration required.

## Validation

- `flutter analyze test/block_builder_view_test.dart` — **No issues found!** (ran cleanly in 83.2s, before the later environment contention began).
- `flutter test test/block_builder_view_test.dart` — **All 10 tests passed** (4 pre-existing + 6 new), including all 6 new characterization cases. This is the exact command specified in the plan's own `<verification>` block.
- Full-repo `flutter analyze` / `flutter test` could **not** be completed this session due to environment resource contention documented above (three attempts hung with near-zero CPU progress; not related to this plan's change, which touches only a single test file). **Recommend re-running both once the machine is free of contention**, per CLAUDE.md's phase-gate expectations.

## Next Phase Readiness

- `test/block_builder_view_test.dart` now has a regression net for both of `_create()`'s inline guardrail throw conditions across all three pre-existing build modes (manual/smart/guided), ready for plan 27-08 to extract them into `ProgramGuardrails.validateConfiguration()` without silent drift in trigger condition or message text.
- The reusable tap sequences and exact message strings documented above give plan 27-08 everything it needs to extend this same test file with post-refactor coverage (asserting the new shared method is actually called) without re-deriving the widget tree paths from scratch.
- Outstanding: full-repo `flutter analyze`/`flutter test` should be re-run before the phase gate, once the local environment's resource contention (see Issues Encountered) has cleared - this plan's own scoped verification passed cleanly.

---
*Phase: 27-herculex-ai-program-generation*
*Completed: 2026-09-29*

## Self-Check: PASSED

Modified file `test/block_builder_view_test.dart` and this SUMMARY.md both verified
present on disk; task commit hash `a964422` verified present in `git log --oneline --all`.
