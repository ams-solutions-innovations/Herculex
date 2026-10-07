---
phase: 27-herculex-ai-program-generation
plan: 08
subsystem: domain
tags: [flutter, dart, guardrails, refactor, program-builder]

# Dependency graph
requires:
  - phase: 27-herculex-ai-program-generation (plan 01)
    provides: block_builder_view.dart split into part/part-of mixins, with
      _create() confirmed stable in actions.part.dart
  - phase: 27-herculex-ai-program-generation (plan 02)
    provides: characterization tests pinning _create()'s current inline
      guardrail throw behavior across manual/smart/guided modes
provides:
  - ProgramGuardrails.validateConfiguration({buildMode, model, split,
    mainMethodByDayLabel}) - the single, unit-tested guardrail home for the
    Max-Effort-per-week and 6-day-PPL+Max-Effort rules, returning
    List<ProgramGuardrailIssue> rather than throwing
  - _create() (all four eventual build modes - manual/smart/guided today,
    Herculex AI in plan 27-11) retrofitted to call this shared method
    instead of duplicating inline StateError throws
affects: [27-11]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Configuration-stage guardrail (pre-materialization) as a sibling
      static method on ProgramGuardrails next to the existing
      post-materialization validateMaxEffortWeek - one guardrail home
      regardless of validation lifecycle stage"

key-files:
  created: []
  modified:
    - lib/features/programs/domain/program_guardrails.dart
    - test/program_guardrails_test.dart
    - lib/features/programs/presentation/views/block_builder_view.dart
    - lib/features/programs/presentation/views/block_builder_view/actions.part.dart

key-decisions:
  - "validateConfiguration() takes the exact same 4 raw builder-state values
    _create() already had locally (buildMode, model, split,
    mainMethodByDayLabel) rather than an intermediate value object - matches
    the plan's <interfaces> section and PATTERNS.md's pre-sketched signature
    verbatim, no design discretion needed."
  - "_create()'s retrofit preserves the exact single-StateError-per-call
    contract its surrounding try/catch expects: on any blocking issue,
    throws StateError with the FIRST blocking issue's message (not a
    concatenation of all issues) - byte-identical to the pre-refactor
    behavior where the two checks were sequential ifs and only the first
    one to match would throw."

patterns-established: []

requirements-completed: []

# Metrics
duration: 25min
completed: 2026-09-30
---

# Phase 27 Plan 08: ProgramGuardrails.validateConfiguration() extraction Summary

**Extracted the two inline Max-Effort-per-week and 6-day-PPL+Max-Effort StateError throws out of block_builder_view's `_create()` into a new, unit-tested `ProgramGuardrails.validateConfiguration()` method; retrofitted `_create()` for all build modes to call it, with zero behavior drift proven by plan 27-02's 6 pre-refactor characterization tests still passing unchanged.**

## Performance

- **Duration:** ~25 min
- **Completed:** 2026-09-30
- **Tasks:** 2 (both `type="auto"`, Task 1 `tdd="true"`)
- **Files modified:** 4

## Accomplishments

- `ProgramGuardrails.validateConfiguration({buildMode, model, split, mainMethodByDayLabel})`
  added as a sibling static method to the existing `validateMaxEffortWeek` on the same
  `abstract final class ProgramGuardrails` (D-06 — one guardrail home, not a new class).
  Returns `List<ProgramGuardrailIssue>`, mirroring `validateMaxEffortWeek`'s exact
  list-building shape.
- Message text and trigger conditions preserved byte-for-byte from the original inline
  throws, including the em dash in `PeriodizationModel.maxEffort.label` (unaffected by
  this extraction — it lives in the enum, not the guardrail message) and the en dash
  (`U+2013`) in `'...Conjugate 3–4 day structure.'`.
- `_create()` (in `actions.part.dart`) now calls the shared method and throws
  `StateError` with the first blocking issue's message, for all build modes
  (manual/smart/guided) — the manual-mode exemption (`buildMode != ProgramBuildMode.manual`
  gating both checks) moved into the guardrail method itself, so `_create()` no longer
  needs its own exemption logic.
- Zero behavior drift: all 10 tests in `test/block_builder_view_test.dart` pass unchanged,
  including all 6 of plan 27-02's characterization tests (2 conditions x 3 build modes).
- `program_guardrails.dart` remains at 206 lines (well under the 600-line cap);
  `block_builder_view.dart` at 403 lines; `actions.part.dart` at 205 lines.
- This is the exact method plan 27-11's Herculex AI brief validator will call — see
  **Final Signature** below.

## Task Commits

1. **Task 1: ProgramGuardrails.validateConfiguration() with unit tests** - `f1740e4` (feat)
2. **Task 2: Retrofit _create() to call the shared guardrail method for all build modes** - `84a6307` (refactor)

## Final Signature (for plan 27-11)

```dart
static List<ProgramGuardrailIssue> validateConfiguration({
  required ProgramBuildMode buildMode,
  required PeriodizationModel model,
  required SplitType split,
  required Map<String, SlotTrainingMethod> mainMethodByDayLabel,
})
```

- Location: `lib/features/programs/domain/program_guardrails.dart`
- Returns issues (never throws) with `severity: GuardrailSeverity.blocking` for both
  current rules; check `issue.isBlocking` before surfacing.
- Exempts `buildMode == ProgramBuildMode.manual` from both checks (matches `_create()`'s
  pre-existing behavior for manual mode).
- Codes: `'config_max_effort_per_week'`, `'config_six_day_ppl_max_effort'`.

## Files Created/Modified

- `lib/features/programs/domain/program_guardrails.dart` — added imports for
  `periodization.dart` and `split_template.dart` (needed for `PeriodizationModel`/
  `SplitType` parameter types), and the new `validateConfiguration()` static method.
- `test/program_guardrails_test.dart` — added imports for `periodization.dart` and
  `split_template.dart`, and a new `group('validateConfiguration', ...)` with 5 tests
  covering: >2 explicit Max Effort days (smart), 6-day PPL + Max Effort periodization
  (smart), manual-mode exemption with both triggers present, no-trigger empty result
  (guided), and both conditions firing simultaneously (2 distinct issues, not just one).
  The 3 pre-existing tests are untouched.
- `lib/features/programs/presentation/views/block_builder_view.dart` — added the
  `program_guardrails.dart` import to the main file's import block (parts inherit
  imports from the main file per the language rule and CLAUDE.md's parts-cannot-have-
  their-own-imports convention).
- `lib/features/programs/presentation/views/block_builder_view/actions.part.dart` —
  `_create()`'s two inline `explicitMaxEffort` computation + `if (...) throw
  StateError(...)` blocks replaced with a single call to
  `ProgramGuardrails.validateConfiguration(...)` followed by
  `if (configIssues.any((issue) => issue.isBlocking)) throw StateError(configIssues
  .firstWhere((issue) => issue.isBlocking).message);`.

## Decisions Made

- Signature matches PATTERNS.md's/the plan's `<interfaces>` pre-sketched shape exactly
  (raw builder-state parameters, not an intermediate value object) — no discretion needed,
  this was already decided at planning time.
- `_create()`'s retrofit throws only the FIRST blocking issue found (via
  `firstWhere`), preserving the pre-refactor behavior where the two `if` checks were
  sequential and only the first match would throw — the surrounding try/catch still
  expects exactly one `StateError` per call, shown in a single SnackBar.

## Deviations from Plan

None — the plan's `<action>` steps for both tasks were followed exactly as written,
including the exact method body, exact test cases, and exact retrofit shape specified
in the plan and PATTERNS.md.

## Issues Encountered

None.

## User Setup Required

None — no external service configuration required.

## Validation

- `flutter test test/program_guardrails_test.dart` — **8/8 passing** (3 pre-existing +
  5 new).
- `flutter analyze lib/features/programs/domain/program_guardrails.dart
  test/program_guardrails_test.dart` — **No issues found!**
- `flutter test test/block_builder_view_test.dart` — **10/10 passing** (4 pre-existing +
  6 characterization tests from plan 27-02, all unchanged).
- `flutter analyze lib/features/programs/presentation/views/block_builder_view.dart
  lib/features/programs/presentation/views/block_builder_view/actions.part.dart` — **No
  issues found!**
- Full-repo `flutter analyze` — **0 errors** (42 pre-existing warnings/info across
  unrelated files, none in any file touched by this plan — a slight improvement over the
  44 logged at the end of Phase 28, not a regression).
- `wc -l` confirms all touched files stay well under CLAUDE.md's 600-line cap:
  `program_guardrails.dart` 206, `block_builder_view.dart` 403,
  `actions.part.dart` 205.

## Next Phase Readiness

- `ProgramGuardrails.validateConfiguration()` is ready for plan 27-11's Herculex AI
  brief validator to call directly — same signature, same "return issues, caller decides
  UX" contract already proven by `_create()`'s StateError+SnackBar usage.
- No blockers for Phase 27's remaining plans.

---
*Phase: 27-herculex-ai-program-generation*
*Completed: 2026-09-30*

## Self-Check: PASSED

All 4 modified files and this SUMMARY.md verified present on disk; both task commit
hashes (`f1740e4`, `84a6307`) verified present in `git log --oneline --all`.
