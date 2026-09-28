---
gsd_state_version: 1.0
milestone: v2.0
milestone_name: Training Programs Revamp, Dream Physique & Gamification
status: ready_to_plan
last_updated: "2026-09-28T07:46:40.674Z"
progress:
  total_phases: 15
  completed_phases: 8
  total_plans: 42
  completed_plans: 42
  percent: 53
---

# Project State: Milestone v2.0

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
**Current focus:** Phase 28 — adaptive tdee & activity calibration (context gathered, ready to plan)

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
- **Phase 26: Herculex AI Knowledge Base & Brand Unification** — Pending. Foundational for 27, 29, PHYS-07.
- **Phase 27: Herculex AI Program Generation** — Pending. Blocked on 26.
- **Phase 28: Adaptive TDEE & Activity Calibration** — Pending. No AI dependency; feeds 23 and 29.
- **Phase 29: Weekly Report & Herculex AI Narrative** — Pending. Blocked on 26, 28, 23.

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
