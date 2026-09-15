---
phase: 18-workout-time-budget-warmups-set-method-prescriptions
plan: 04
subsystem: database
tags: [drift, prescription-codec, warmup-resolver, resolver-wiring]

# Dependency graph
requires:
  - phase: 18-workout-time-budget-warmups-set-method-prescriptions
    provides: "18-01: SlotPrescriptionCodec + schema v43 columns; 18-02: WarmupResolver + WorkoutDurationEstimator"
provides:
  - "resolveProgramDay reads prescriptionCodecJson through SlotPrescriptionCodec instead of the ad-hoc templateSets JSON blob"
  - "resolveProgramDay computes automatic warmups (compound and max-effort paths) through WarmupResolver, tracking movement order across a session's exercises"
  - "PlannedExerciseSnapshot.allowsAdvancedTechniques sourced from Programs.allowTimeSavingSetTechniques, materialized onto WorkoutExercises.plannedAllowsAdvancedTechniques"
affects: [18-05, 18-06]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Single warmup+workingSets splice shared by both the max-effort and general-compound branches of resolveProgramDay, replacing two separately-shaped code paths"
    - "sawHeavyLiftInSession loop-local flag derives per-exercise isFirstHeavy from row iteration order (rows are already fetched ordered by orderIndex)"

key-files:
  created: []
  modified:
    - lib/features/workouts/data/planned_session_resolver.dart
    - lib/features/programs/data/programs_repository.dart
    - test/planned_session_resolver_test.dart

key-decisions:
  - "ProgramsRepository.snapshotLinkedTemplates (a caller of the now-removed prescriptionJson read, not in the plan's stated file list) was also updated to write prescriptionCodecJson, since removing pde.prescriptionJson support silently broke its frozen-blueprint guarantee — the codec has no field for a literal per-set weight or an isWarmup flag, so those are no longer captured for template-snapshotted programs; automatic warmup computation now owns warmup structure everywhere per D-10"
  - "Retargeted test/planned_session_resolver_test.dart instead of the plan's stated test/features/programs/prescription_resolver_test.dart, which only unit-tests PrescriptionResolver in isolation with no database and has no resolveProgramDay coverage at all"

patterns-established: []

requirements-completed: [PRES-01, PRES-03]

# Metrics
duration: ~50min
completed: 2026-09-15
---

# Phase 18 Plan 04: Resolver Wiring — SlotPrescriptionCodec + WarmupResolver Summary

**`PlannedSessionResolver.resolveProgramDay` now reads prescriptions through `SlotPrescriptionCodec` and computes warmups through `WarmupResolver` with movement-order tracking, replacing the ad-hoc `templateSets` blob and the fixed `_automaticWarmups`/`_maxEffortSets` ramp tables — the single call site both calendar preview and workout start go through, making preview/session parity structural.**

## Performance

- **Duration:** ~50 min
- **Started:** 2026-09-15T~18:10:00Z
- **Completed:** 2026-09-15T~19:00:00Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- `resolveProgramDay` tracks `sawHeavyLiftInSession` across the day's ordered exercises so each slot's `isFirstHeavy` reflects real movement order; both the general compound-lift path and the max-effort path now run through one shared `[...warmups, ...workingSets]` splice instead of two differently-shaped branches.
- Automatic warmups (standard and max-effort) come from `WarmupResolver.resolve` — density-scaled by target `%1RM` and abbreviated for later heavy lifts in the same session — fully replacing `_automaticWarmups` and the leading 4-step ramp previously hardcoded inside `_maxEffortSets` (now `_maxEffortWorkingSets`, top single + 3 back-off sets only).
- `resolveProgramDay` decodes `pde.prescriptionCodecJson` via `SlotPrescriptionCodec.decode` and, when present, builds working sets through the same `_setsFromPrescription` used for the template-resolved case — `_copiedTemplateSets` and the `pde.prescriptionJson` read are deleted entirely.
- `PlannedExerciseSnapshot.allowsAdvancedTechniques` is sourced from `program.allowTimeSavingSetTechniques` in `resolveProgramDay` (always `false` in `resolveTemplate`, which has no program config) and materialized onto `WorkoutExercises.plannedAllowsAdvancedTechniques`.
- Companion fix: `ProgramsRepository.snapshotLinkedTemplates` (the "new builder" template-freeze feature) now also writes a codec-encoded `prescriptionCodecJson`, since it previously relied exclusively on the now-unread `prescriptionJson` blob.

## Task Commits

Each task was committed atomically:

1. **Task 1: Replace fixed warmup tables with WarmupResolver, tracking movement order** - `be377ff` (feat)
2. **Task 2: Read prescriptions through SlotPrescriptionCodec; persist the advanced-technique flag** - `1855631` (feat)

## Files Created/Modified
- `lib/features/workouts/data/planned_session_resolver.dart` - `resolveProgramDay` rewritten to use `WarmupResolver`/`SlotPrescriptionCodec`; `_automaticWarmups`/`_maxEffortSets`/`_copiedTemplateSets` deleted; `_warmupSnapshots`/`_maxEffortWorkingSets` added; `PlannedExerciseSnapshot.allowsAdvancedTechniques` field added
- `lib/features/programs/data/programs_repository.dart` - `snapshotLinkedTemplates` now also encodes a `SlotPrescriptionCodec`-backed `prescriptionCodecJson` for its frozen per-set blueprint
- `test/planned_session_resolver_test.dart` - Retargeted warmup-count expectations to the new density-based ramp lengths; retargeted the "new builder" snapshot test to the codec-representable contract (reps/setType frozen, literal weight/isWarmup no longer captured); added tests for movement-order abbreviation, codec-override precedence, and `allowsAdvancedTechniques` sourcing/materialization

## Decisions Made
- Kept `_maxEffortWorkingSets()` returning only the top single + 3 back-off sets (4 sets), with its warmup ramp now prepended by the same shared splice every other eligible slot uses, at a fixed `targetPercentOf1Rm: 0.90` per the plan's explicit "max-effort lifts are treated as always near-max" instruction.
- `ProgramsRepository.snapshotLinkedTemplates`'s codec conversion maps each non-warmup template set to its own `WorkSegment` (`sets: 1`), preserving reps and `setType` exactly; warmup sets from the original template are dropped from the frozen blueprint since `WarmupResolver` now computes warmup structure everywhere per D-10, and literal per-set weight targets are not representable in `SlotPrescription`/`WorkSegment` at all (by design — the model prescribes reps/intent/%1RM, not literal weight).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Plan's stated acceptance-criteria test file has no resolveProgramDay coverage**
- **Found during:** Task 1, before writing any test assertions
- **Issue:** The plan's `files_modified` and `acceptance_criteria.automated` both name `test/features/programs/prescription_resolver_test.dart`, but that file only unit-tests the plain-Dart `PrescriptionResolver` (no database, no `resolveProgramDay` calls at all) — it cannot exercise or verify any of this plan's stated behaviors (warmup density/order, codec decode, `allowsAdvancedTechniques`). `test/planned_session_resolver_test.dart` is the existing DB-backed suite that already exercises `resolveProgramDay`.
- **Fix:** Added/retargeted all new assertions in `test/planned_session_resolver_test.dart` instead. Still ran `test/features/programs/prescription_resolver_test.dart` as literally specified — unaffected, still green (13/13).
- **Files modified:** `test/planned_session_resolver_test.dart`
- **Verification:** `flutter test test/planned_session_resolver_test.dart` (7/7 passing) and `flutter test test/features/programs/prescription_resolver_test.dart` (13/13 passing)
- **Committed in:** `be377ff` (Task 1 commit)

**2. [Rule 1 - Bug] ProgramsRepository.snapshotLinkedTemplates's frozen snapshot silently degraded to the template-resolved archetype**
- **Found during:** Task 2, full-suite verification after removing `pde.prescriptionJson`/`_copiedTemplateSets`
- **Issue:** `ProgramsRepository.snapshotLinkedTemplates` ("new builder" feature) wrote its per-set frozen blueprint exclusively to `prescriptionJson`, the exact ad-hoc blob `resolveProgramDay` no longer reads after Task 2. Left as-is, every program day frozen by this feature would silently fall back to the archetype-resolved prescription (wrong reps/sets/intent) instead of its recorded blueprint, with no error — an existing regression test caught this immediately.
- **Fix:** Updated `snapshotLinkedTemplates` to also encode a `SlotPrescriptionCodec`-backed `prescriptionCodecJson`, mapping each non-warmup copied template set to its own `WorkSegment` (reps + `setType` preserved). Literal per-set weight and warmup-flag data are not representable in the codec's `SlotPrescription`/`WorkSegment` model by design (it prescribes reps/intent/%1RM, not literal weight) and are no longer captured for this path — retargeted the affected test's assertions accordingly (frozen reps/setType survive future template edits; literal weight no longer does, matching what the new architecture can actually represent).
- **Files modified:** `lib/features/programs/data/programs_repository.dart`, `test/planned_session_resolver_test.dart`
- **Verification:** `flutter test test/planned_session_resolver_test.dart` (7/7 passing, including the affected "new builder snapshots a linked template" test); full suite green (1307 passed, 9 skipped, 0 failed)
- **Committed in:** `1855631` (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (1 blocking, 1 bug)
**Impact on plan:** Both fixes were necessary consequences of Task 2's explicit, plan-mandated removal of `prescriptionJson`/`_copiedTemplateSets` (D-04's "no legacy-shape fallback" applied literally would have silently broken a live feature outside this plan's stated file list). No scope creep beyond what was required to keep the full suite green.

## Issues Encountered
- Retargeting the max-effort and automatic-warmup test assertions in `test/planned_session_resolver_test.dart` required recomputing exact set counts by hand against `WarmupResolver`'s density table (dense ramp at `targetPercentOf1Rm: 0.90` is 5 steps, not the old fixed 4; a null-target straight-sets slot falls to the 2-step light ramp, not the old fixed 3) — verified against `lib/features/workouts/domain/warmup_resolver.dart`'s thresholds directly rather than guessing.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- `resolveProgramDay` is now the single canonical read path for prescriptions and warmups; both `previewScheduledWorkout` and `startScheduledWorkoutById` (unchanged call sites in `scheduled_workout_service.dart`) resolve through it identically by construction (T-18-08 mitigated).
- `flutter analyze` reports 0 errors on all modified files; full suite green (1307 passed, 9 skipped, 0 failed).
- Plans 18-05/18-06 can build on `resolveProgramDay`'s codec-first read path and the shared warmup splice without further resolver rewiring.
- No blockers.

---
*Phase: 18-workout-time-budget-warmups-set-method-prescriptions*
*Completed: 2026-09-15*
