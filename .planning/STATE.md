---
gsd_state_version: 1.0
milestone: v2.0
milestone_name: Training Programs Revamp, Dream Physique & Gamification
status: in_progress
last_updated: "2026-09-14T16:58:57.684Z"
progress:
  total_phases: 11
  completed_phases: 2
  total_plans: 11
  completed_plans: 6
  percent: 18
---

# Project State: Milestone v2.0

## Project Reference

See: `.planning/PROJECT.md` (initiated 2026-09-13)  
Blueprint: `docs/training-programs-physique-gamification-plan-2026-09-10.md`

**Core value:** Safe, deterministic, and explainable training program generation; flexible program and wave editing; persistent Dream Physique goals with phased nutrition plans; and an authentic 15-tier XP gamification system.  
**Current focus:** Phase 17 — deterministic-program-planner-hard-guardrails

---

## Current Roadmap (Phases 15–25)

- **Phase 15: Program Generator Regression Fixes & Interaction Hardening** — Completed (2026-09-13).
- **Phase 16: Exercise Programming Metadata & Discipline Taxonomy** — Completed (2026-09-13).
- **Phase 17: Deterministic Program Planner & Hard Guardrails** — Ready to execute (`/gsd:execute-phase 17`), 5 plans.
- **Phase 18: Workout Time Budget, Warmups & Set Method Prescriptions** — Pending.
- **Phase 19: Program & Wave Editor with Explainable Periodization** — Pending.
- **Phase 20: Active Workout Shell & Calendar Execution Flow** — Pending.
- **Phase 21: CrossFit & GPP Training Tracks** — Pending.
- **Phase 22: Primary Lift Strength Specialization** — Pending.
- **Phase 23: Persistent Dream Physique & Multi-Phase Nutrition** — Pending.
- **Phase 24: Gamification System & 15-Rank XP Ledger** — Pending.
- **Phase 25: Cloud Sync, Privacy & Export Hardening** — Pending.

---

## Session update — 2026-09-13 (Phase 16 Completed)

- Completed Phase 16: `Exercise Programming Metadata & Discipline Taxonomy`:
  - **Plan 16-01 (META-01):** Shipped Drift & Supabase schema v41 with 6 new metadata columns and scaling index, verified TableMigration table rewrite, generated migration fixtures and dumped schema snapshot, and packaged `exercise_programming_metadata.json` in `pubspec.yaml`.
  - **Plan 16-02 (META-01, META-03):** Upgraded `exercise_programming_metadata.json` to version 2 covering 108 exercises across 5 canonical disciplines (`weights`, `calisthenics`, `crossfit`, `olympic`, `gpp`), 4 commonness tiers, 7 scaling ladders, and specialization anchors; extended `ExerciseImporter` companion mapping; hardened `ExerciseProgrammingEligibility.allows` with strict novice difficulty ceiling and two-layer `basicWeights` hard gate blocking specialty bars, chains, boards, and pins.
  - **Plan 16-03 (META-02, META-04):** Implemented dual-check prerequisite gate in `ExerciseProgrammingEligibility.verifyPrerequisites` with canonical `movementSlug` family alias resolution; built `ExerciseScalingResolver` domain service with progressive ladder regression, strict group boundaries, and explainable rationales.
- Validation: 0 Dart static analysis errors; 46/46 automated tests passing across 6 test suites in 15s.
- Next implementation focus: `/gsd-plan-phase 17` (Deterministic Program Planner & Hard Guardrails).
