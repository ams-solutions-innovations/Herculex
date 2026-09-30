---
phase: 27-herculex-ai-program-generation
plan: 12
subsystem: programs
tags: [flutter, drift, riverpod, ai, herculex-ai, program-review, widget-test]

# Dependency graph
requires:
  - phase: 27-herculex-ai-program-generation (plan 07)
    provides: "AiDayRationaleCard(rationale) - the primary-tinted per-day rationale widget this plan renders"
  - phase: 27-herculex-ai-program-generation (plan 09)
    provides: "HerculexAiBriefService.watchBriefForProgram() and the HerculexAiProgramBriefs table this plan reads"
provides:
  - "ProgramReviewView._DayCard renders AiDayRationaleCard per day, additive to the existing EmptySlotNotice rendering, conditional on an active HerculexAiProgramBriefs row with source == 'herculex_ai' for the reviewed program (AIP-04, D-09)"
  - "HerculexAiBriefService.readActiveBriefForProgram(programId) - a one-shot Future<HerculexAiProgramBriefData?> sibling to watchBriefForProgram(), for callers that build state once rather than subscribing to a live stream"
affects: [27-13 (block_builder_view.dart pre-fill/persistence wiring - unrelated files, no overlap)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Prefer a one-shot Future query (getSingleOrNull()) over Stream.first for a drift watch() query consumed from a widget's imperative one-shot _load() - taking .first from a live drift watch stream hangs indefinitely under flutter_test's fake-async tester.pump() clock, even though it resolves correctly in plain async/await tests"
    - "Optional AI-derived enrichment reads (per-day rationale) are wrapped in their own inner try/catch, isolated from the screen's outer _load() try/catch, so a malformed/legacy stored value degrades to 'no rationale' rather than surfacing the screen's generic error state"

key-files:
  created: []
  modified:
    - lib/features/programs/presentation/views/program_review_view.dart
    - lib/features/programs/data/herculex_ai_brief_service.dart
    - test/program_review_view_test.dart

key-decisions:
  - "Added HerculexAiBriefService.readActiveBriefForProgram() (one-shot Future) rather than using watchBriefForProgram(...).first as the plan's <interfaces> section suggested as one option - the .first approach hung for the full 10-minute flutter_test timeout under tester.pump()'s fake-async clock (confirmed by reproducing the hang, then fixing it), while a plain getSingleOrNull() query resolves normally within the existing 2-pump budget every other test in this file already uses"
  - "The one-shot query and the existing watch() stream now share a private _activeBriefQuery(programId) helper on HerculexAiBriefService, so the active/source/newest-first query shape can never drift between the two read paths"
  - "Explicitly checked briefRow.source == 'herculex_ai' in _load() even though the table's default and persistBrief() both always write that value - matches the plan's literal behavior spec and makes the conditional-rendering rule readable at the call site without relying on the table's write-side invariant holding forever"

requirements-completed: [AIP-04]

# Metrics
duration: ~40min
completed: 2026-09-30
---

# Phase 27 Plan 12: Herculex AI Per-Day Rationale in ProgramReviewView Summary

**`_DayCard` now renders `AiDayRationaleCard` per day - the brief's verbatim `dayRoles[].rationale` - additive to the existing per-slot `EmptySlotNotice`, conditional on an active `HerculexAiProgramBriefs` row with `source == 'herculex_ai'`; `_confirm()` is byte-for-byte unchanged.**

## Performance

- **Duration:** ~40 min
- **Completed:** 2026-09-30
- **Tasks:** 1/1 completed
- **Files modified:** 3

## Accomplishments
- `_ReviewDay` gained a nullable `aiRationale` field, populated in `_load()` from a new `_herculexAiRationaleByDayIndex()` helper: reads the active Herculex AI brief for the program (via `HerculexAiBriefService.readActiveBriefForProgram`), decodes `briefJson` through `ProgramBrief.fromJson`, and maps each `dayRoles[].dayIndex` to that day's array position in the `days` list built earlier in `_load()`.
- `_DayCard` renders `if (day.aiRationale != null) Padding(... AiDayRationaleCard(rationale: day.aiRationale!))` immediately after the existing `emptyReasons` loop - additive, never replacing, and both can render on the same day.
- Any failure reading/decoding the brief (no row, wrong source, malformed/legacy JSON, a `ProgramBrief.fromJson` `FormatException`) is caught inside `_herculexAiRationaleByDayIndex()`'s own try/catch and treated as "no rationale available" - it can never surface the screen's generic `_error` state (T-27-19).
- `_confirm()` (lines unchanged) - verified via `git diff --unified=0` showing zero changed lines in that method - remains the sole point a program becomes real.
- 5 new widget tests covering all 4 plan-specified behavior cases plus one extra (non-`herculex_ai` source): positive render with exact verbatim text, zero cards for no matching brief row, zero cards for a wrong-source row, malformed-JSON swallowed without crashing, and both `EmptySlotNotice`+`AiDayRationaleCard` rendering together on the same day. Plus a new `_confirm()`-unchanged navigation test (tap "Confirm plan" -> `BlockDetailView`).

## Task Commits

Each task was committed atomically:

1. **Task 1: Per-day AI rationale rendering in _DayCard, conditional on an active Herculex AI brief** - `f101be5` (feat)

**Plan metadata:** this commit (docs: complete plan).

## Files Created/Modified
- `lib/features/programs/presentation/views/program_review_view.dart` - `_ReviewDay.aiRationale` field, `_herculexAiRationaleByDayIndex()` helper, `_DayCard` additive rendering block, new imports (`dart:convert`, `herculex_ai_brief_service.dart`, `program_brief.dart`, `ai_day_rationale_card.dart`)
- `lib/features/programs/data/herculex_ai_brief_service.dart` - new `readActiveBriefForProgram()` one-shot method + shared private `_activeBriefQuery()` helper (refactored `watchBriefForProgram()` to reuse it, same query shape, no behavior change)
- `test/program_review_view_test.dart` - 5 new tests in a `Herculex AI per-day rationale (27-12, AIP-04)` group + 1 new test in a `_confirm() (unchanged by plan 27-12)` group

## Decisions Made
See `key-decisions` in frontmatter. The most consequential one: switching from `watchBriefForProgram(...).first` to a new one-shot `readActiveBriefForProgram()` method - this was necessary, not stylistic (see Deviations below).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `.watchBriefForProgram(...).first` hangs indefinitely under `flutter_test`'s fake-async pump clock**
- **Found during:** Task 1, first test run against the plan's literal `<interfaces>` suggestion (`.first` on the existing watch stream)
- **Issue:** Calling `.first` on the drift `Stream<HerculexAiProgramBriefData?>` from `watchBriefForProgram()` inside `_load()` (triggered from `initState()` via `Future<void>.microtask(_load)`) caused every pre-existing widget test in `test/program_review_view_test.dart` to hang for the full 10-minute `flutter_test` default timeout, then fail with `TimeoutException`. The same `.first` call on the same stream passes instantly in `test/herculex_ai_brief_service_test.dart`'s plain `async`/`await` tests - the hang is specific to consuming a live drift watch stream's first emission from within `tester.pump()`'s `FakeAsync` zone, not a slow query.
- **Fix:** Added `HerculexAiBriefService.readActiveBriefForProgram(programId)` - a one-shot `Future<HerculexAiProgramBriefData?>` using `getSingleOrNull()` against the same active/source/newest-first query shape (now shared with `watchBriefForProgram()` via a private `_activeBriefQuery()` helper). `_load()` calls this instead of `.watch(...).first`. This is exactly the plan's own documented fallback option ("...or read the underlying one-shot query if the service also exposes one").
- **Files modified:** `lib/features/programs/data/herculex_ai_brief_service.dart`, `lib/features/programs/presentation/views/program_review_view.dart`
- **Verification:** All 3 pre-existing tests in the `ProgramReviewView empty-slot notices` group (previously hanging/timing out) now pass in ~1-2s each; all 5 new per-day-rationale tests and the new `_confirm()` navigation test pass; `test/herculex_ai_brief_service_test.dart`'s 7 pre-existing tests still pass unchanged (the refactored `watchBriefForProgram()` has identical behavior, confirmed by its own watch-stream tests still passing).
- **Committed in:** `f101be5` (Task 1 commit)

**2. [Test-only fix, not a Rule 1-4 deviation] Added post-navigation cleanup to the new `_confirm()` test**
- **Found during:** Task 1, writing the `_confirm()`-unchanged navigation test
- **Issue:** After tapping "Confirm plan" and navigating to `BlockDetailView`, the test ended without unmounting the widget tree first. `BlockDetailView` owns its own live stream providers, and flutter_test's post-test invariant check (`!timersPending`) failed because a pending drift-stream-cancellation `Timer` was still scheduled when the test completed.
- **Fix:** Added `await tester.pumpWidget(const SizedBox()); await tester.pump(const Duration(milliseconds: 50));` after the assertion - the exact teardown pattern `test/block_detail_view_test.dart`'s own tests already use for the same reason.
- **Files modified:** `test/program_review_view_test.dart`
- **Verification:** Test passes cleanly, no pending-timer assertion.

---

**Total deviations:** 2 (1 Rule 1 bug fix affecting production + test code, 1 test-only cleanup fix)
**Impact on plan:** The `.first`-vs-one-shot fix was required for the plan's own acceptance criteria (`flutter test test/program_review_view_test.dart` passing) to be achievable at all - without it, 3 pre-existing tests plus every new test in this plan would time out. No scope creep: both fixes are scoped entirely to this plan's own files and behavior.

## Issues Encountered
None beyond the deviation documented above (found and fixed within Task 1, no unresolved blockers).

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- AIP-04 is now fully closed end-to-end: `HerculexAiProgramBriefs` persistence (27-04/27-10), `HerculexAiBriefService` read/write (27-09), and this plan's review-screen rendering all connect.
- `HerculexAiBriefService.readActiveBriefForProgram()` is a new public method available to any future caller needing a one-shot brief read (e.g. plan 27-13, if it needs anything beyond the stream-based pre-fill it already consumes from `watchBriefForProgram()`).
- No blockers for plan 27-13 (`block_builder_view.dart` pre-fill/persistence wiring) - zero shared files with this plan's changes.
- `flutter analyze` (full repo): 0 errors, 52 pre-existing warnings/info, none in this plan's 3 touched files. `dart run tool/check_structure.dart`: 57 pre-existing violations (unchanged count) - `program_review_view.dart` was already over the 600-line cap before this plan (742 lines) and is now 786 lines after this plan's additive changes; not newly introduced by this plan and out of this plan's scope to split (unlike `block_builder_view.dart`, no plan/context document calls for splitting `program_review_view.dart`). Flagged here for a future cleanup pass, not fixed.
- `dart format` applied to all 3 touched files; re-verified 0 analyzer issues and all tests still passing after formatting.

## Threat Flags

None beyond what the plan's own `<threat_model>` already covers (T-27-19, mitigated as designed - a malformed/legacy stored brief never crashes the review screen).

## Known Stubs

None. The rendering is fully wired to the real `HerculexAiProgramBriefs` table via `HerculexAiBriefService`; no placeholder/mock data.

---
*Phase: 27-herculex-ai-program-generation*
*Completed: 2026-09-30*

## Self-Check: PASSED

- FOUND: lib/features/programs/presentation/views/program_review_view.dart
- FOUND: lib/features/programs/data/herculex_ai_brief_service.dart
- FOUND: test/program_review_view_test.dart
- FOUND: .planning/phases/27-herculex-ai-program-generation/27-12-SUMMARY.md
- FOUND: f101be5 (Task 1 commit)
