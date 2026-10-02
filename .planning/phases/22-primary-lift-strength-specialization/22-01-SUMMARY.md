---
phase: 22-primary-lift-strength-specialization
plan: 01
subsystem: training-programs
tags: [dart, drift, domain-model, program-generation, guardrails]

# Dependency graph
requires:
  - phase: 21
    provides: smart_program_planner.dart assistance-slot shape for squat/deadlift sticking-point branching (the pattern this plan mirrors for bench/OHP/pull-up)
provides:
  - "_needsForPrimaryLift covers all 5 PrimaryLift values with distinct per-sticking-point assistance slots (D-12)"
  - "SquatSpecialization/SquatStickingPoint fully deleted, zero dangling references"
  - "ProgramGuardrails.validateVolumeFloor(Map<String,num>) - warning-only maintenance-volume-floor check (D-04-D-07)"
  - "ProgramGuardrails.validateKgIncrease({specialization, experience}) - warning-only unrealistic-kg-increase check (D-11)"
  - "ProgramGuardrails.kgIncreaseCeilings - tunable per-experience-tier kg ceilings"
affects: [22-02, 22-03, 22-04, primary-lift-specialization-ui-wiring]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Per-sticking-point assistance branching: one explicit case for the lift's lift-specific PrimaryLiftStickingPoint value, one `_` default for the rest (mirrors squat/deadlift's pre-existing shape)"
    - "Guardrail functions are pure, return List<ProgramGuardrailIssue>, never throw - callers choose their own UX"

key-files:
  created: []
  modified:
    - lib/features/programs/data/smart_program_planner.dart
    - lib/features/programs/domain/program_guardrails.dart
    - test/smart_program_planner_test.dart
    - test/program_guardrails_test.dart

key-decisions:
  - "pull-up's integration test asserts the assistance (SlotRole.supplemental) slot, not the main slot - pull-up's cnsScore (4) is below the pre-existing SlotRole.main eligibility threshold (>=5), a constraint unrelated to and unchanged by this plan"
  - "pull-up specialization test uses TrainingStyle.basic (not the default weightlifting) since pull-up/pull-up-wide-grip's allowedTrainingStyles never include weightlifting in the catalog metadata"

patterns-established:
  - "Per-lift sticking-point assistance switch in _needsForPrimaryLift, one branch per PrimaryLift value"

requirements-completed: [SPEC-01, SPEC-02, SPEC-03]

# Metrics
duration: 25min
completed: 2026-10-02
---

# Phase 22 Plan 01: Primary Lift Specialization Domain Foundation Summary

**D-12 per-sticking-point assistance branching for all 5 primary lifts, dead SquatSpecialization deletion, and two new warning-only ProgramGuardrails pure functions (validateVolumeFloor, validateKgIncrease) ready for wave-2/3 UI wiring.**

## Performance

- **Duration:** ~25 min (worktree-local; base-correction reset not counted)
- **Tasks:** 2 completed
- **Files modified:** 4 (2 lib, 2 test), 2 files deleted

## Accomplishments

- `_needsForPrimaryLift`'s assistance switch now branches `PrimaryLift.benchPress`, `.overheadPress`, and `.pullUp` individually by sticking point (matching squat/deadlift's pre-existing shape), replacing the single generic `horizontal_pull` fallback all three previously shared
- `SquatSpecialization`/`SquatStickingPoint` (superseded, zero live callers) fully deleted from `lib/` and `test/`, along with the dead `isSquatFocused` block and all `squatSpecialization` threading through `SmartProgramConfiguration`/`_needsFor`
- `ProgramGuardrails.validateVolumeFloor(Map<String, num>)` and `ProgramGuardrails.validateKgIncrease({specialization, experience})` added, both warning-severity-only pure functions, message text matching 22-UI-SPEC.md's copy templates verbatim
- `ProgramGuardrails.kgIncreaseCeilings` (novice 50kg / intermediate 30kg / advanced 15kg) added with a doc comment flagging it as a tunable RESEARCH.md proposal, not a locked decision

## Task Commits

1. **Task 1: Remove dead SquatSpecialization code and add D-12 sticking-point branching** - `06600af` (feat)
2. **Task 2: ProgramGuardrails.validateVolumeFloor and validateKgIncrease (D-04-D-07, D-11)** - `8c45d6d` (feat)

## Files Created/Modified

- `lib/features/programs/data/smart_program_planner.dart` - removed `SquatSpecialization` import/field/threading and dead `isSquatFocused` block; extended `_needsForPrimaryLift`'s assistance switch to branch bench/OHP/pullUp individually by sticking point
- `lib/features/programs/domain/squat_specialization.dart` - deleted (superseded by `PrimaryLiftSpecialization`)
- `lib/features/programs/domain/program_guardrails.dart` - added `kgIncreaseCeilings`, `validateKgIncrease`, `validateVolumeFloor`, `_formatSets` helper
- `test/smart_program_planner_test.dart` - rewrote the squat specialization test onto `PrimaryLiftSpecialization`; added OHP, pull-up, and PPL no-top-up regression tests
- `test/squat_specialization_test.dart` - deleted (exercised only the deleted class)
- `test/program_guardrails_test.dart` - added `validateKgIncrease` and `validateVolumeFloor` test groups (11 new tests)

## Exact Final Signatures (for waves 2-3)

```dart
abstract final class ProgramGuardrails {
  static const kgIncreaseCeilings = <ExperienceLevel, double>{
    ExperienceLevel.novice: 50,
    ExperienceLevel.intermediate: 30,
    ExperienceLevel.advanced: 15,
  };

  static List<ProgramGuardrailIssue> validateKgIncrease({
    required PrimaryLiftSpecialization specialization,
    required ExperienceLevel experience,
  });

  static List<ProgramGuardrailIssue> validateVolumeFloor(
    Map<String, num> weeklySetsByGroup,
  );
}
```

Both return `GuardrailSeverity.warning`-only issues (`validateKgIncrease` code
`'specialization_kg_increase'`, `validateVolumeFloor` code
`'specialization_volume_floor'`), never `blocking`, never throw.

## Decisions Made

- **Pull-up integration test targets the assistance slot, not the main slot.** Pull-up's catalog `cnsScore` (4) is below the pre-existing `SlotRoleEligibility.derive` threshold for `SlotRole.main` (requires `cnsScore >= 5` and a max-effort-capable modality) — a constraint that predates and is unrelated to this plan. The day's main slot therefore always falls back to a different exercise for a pull-up specialization through the automatic Smart flow; this is correctly out of this plan's scope. The new test instead asserts the `SlotRole.supplemental` (assistance) slot's `movementPattern`, which is exactly what Task 1's D-12 branching controls for `PrimaryLift.pullUp`.
- **Pull-up test uses `TrainingStyle.basic`, not the configuration default `weightlifting`.** Both `pull-up` and `pull-up-wide-grip`'s catalog `allowedTrainingStyles` metadata never include `weightlifting` — under the default training style neither candidate is eligible for any slot at all. `TrainingStyle.basic` is the narrowest style pull-up's metadata actually allows.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug/test correctness] Rewrote the pull-up integration test to target the assistance slot and use TrainingStyle.basic**
- **Found during:** Task 1, writing the pull-up regression test
- **Issue:** The plan's behavior spec described asserting a pull-up specialization's main exercise has `movementPattern == 'vertical_pull'`, mirroring the bench/OHP integration test shape. Running that test revealed two pre-existing, unrelated catalog/eligibility constraints: (a) pull-up's `cnsScore` (4) is below the `SlotRole.main` eligibility threshold (>=5), so a bodyweight pull-up can never fill the day's main slot through the automatic Smart flow regardless of this plan's changes; (b) under the configuration default `TrainingStyle.weightlifting`, pull-up is excluded entirely since its catalog metadata never lists `weightlifting` as an allowed training style.
- **Fix:** Changed the test to assert the `SlotRole.supplemental` (assistance) slot's `movementPattern` instead of the main slot — this is precisely what the new D-12 branching for `PrimaryLift.pullUp` controls, and pull-up IS eligible for `SlotRole.supplemental` (its compound mechanics add the supplemental role unconditionally in `SlotRoleEligibility.derive`). Also set `trainingStyle: TrainingStyle.basic` so pull-up candidates aren't excluded by the unrelated training-style gate.
- **Files modified:** test/smart_program_planner_test.dart
- **Verification:** `flutter test test/smart_program_planner_test.dart` — 17/17 passing
- **Committed in:** `06600af` (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 bug/test-correctness)
**Impact on plan:** No production code behavior changed by this deviation — only the test's assertion target and configured training style were corrected to match pre-existing, unrelated catalog-eligibility constraints. `_needsForPrimaryLift`'s actual D-12 branching logic matches the plan's `<action>` section exactly.

## Issues Encountered

- Worktree was initially checked out at a stale base commit (`d0c152a`, a pre-Phase-27 commit) rather than the expected `47238a3`. Corrected via the mandatory `<worktree_branch_check>` base-correction reset (clean working tree, no uncommitted work lost) before any plan work began.

## Next Phase Readiness

- `_needsForPrimaryLift` is now fully exhaustive over all 5 `PrimaryLift` values with distinct per-sticking-point assistance branching — ready for wave-2/3 UI work to surface `PrimaryLiftSpecialization.assistanceFocus` copy for every lift (per 22-UI-SPEC.md's Copywriting Contract).
- `ProgramGuardrails.validateVolumeFloor`/`validateKgIncrease` are unit-tested and ready for direct consumption by wave-2/3's Create-time guardrail banner and live-preview UI wiring — their exact signatures and warning-severity-only contract are recorded above.
- No blockers.

---
*Phase: 22-primary-lift-strength-specialization*
*Completed: 2026-10-02*
