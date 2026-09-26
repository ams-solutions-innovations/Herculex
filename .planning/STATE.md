---
gsd_state_version: 1.0
milestone: v2.0
milestone_name: Training Programs Revamp, Dream Physique & Gamification
status: ready_to_plan
last_updated: "2026-09-26T10:53:27.775Z"
progress:
  total_phases: 11
  completed_phases: 6
  total_plans: 33
  completed_plans: 31
  percent: 55
---

# Project State: Milestone v2.0

## Project Reference

See: `.planning/PROJECT.md` (initiated 2026-09-13)  
Blueprint: `docs/training-programs-physique-gamification-plan-2026-09-10.md`

**Core value:** Safe, deterministic, and explainable training program generation; flexible program and wave editing; persistent Dream Physique goals with phased nutrition plans; and an authentic 15-tier XP gamification system.  
**Current focus:** Phase 21 — crossfit-gpp-training-tracks

---

## Current Roadmap (Phases 15–25)

- **Phase 15: Program Generator Regression Fixes & Interaction Hardening** — Completed (2026-09-13).
- **Phase 16: Exercise Programming Metadata & Discipline Taxonomy** — Completed (2026-09-13).
- **Phase 17: Deterministic Program Planner & Hard Guardrails** — Ready to execute (`/gsd:execute-phase 17`), 5 plans.
- **Phase 18: Workout Time Budget, Warmups & Set Method Prescriptions** — Pending.
- **Phase 19: Program & Wave Editor with Explainable Periodization** — Pending.
- **Phase 20: Active Workout Shell & Calendar Execution Flow** — Pending.
- **Phase 21: CrossFit & GPP Training Tracks** — In progress, 5/7 plans (`/gsd:execute-phase 21`).
- **Phase 22: Primary Lift Strength Specialization** — Pending.
- **Phase 23: Persistent Dream Physique & Multi-Phase Nutrition** — Pending.
- **Phase 24: Gamification System & 15-Rank XP Ledger** — Pending.
- **Phase 25: Cloud Sync, Privacy & Export Hardening** — Pending.

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
