# Phase 21: CrossFit & GPP Training Tracks - Context

**Gathered:** 2026-09-16
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 21 turns CrossFit from a plain exercise filter into a structured session type: every CrossFit workout gets an ordered blueprint of segments (warmup, skill, strength, metcon, cooldown), beginner/intermediate/advanced level policy governs which skills/scaling/complexity/time caps/recovery spacing apply, and the `fullBodyAbGpp` split (already stubbed in `split_template.dart`) gets real GPP conditioning content that cannot silently become a third Dynamic Effort strength day. It does not touch general program generation architecture (Phase 17), the prescription codec itself (Phase 18, reused as-is), the program/wave editor (Phase 19), or the active workout shell (Phase 20) beyond whatever materialization/rendering those already do for ordered slots.

</domain>

<decisions>
## Implementation Decisions

### Session blueprint & segments
- **D-01:** Segments (warmup / skill / strength / metcon / cooldown) are represented by **tagging existing rows** — adding a segment identifier to the existing `ProgramDayExercises`/slot rows alongside `SlotRole` — rather than introducing a new dedicated segment table. This is the lighter-weight schema path; ordering/grouping by segment is inferred from the tag rather than being a first-class table relationship.
- **D-02:** A CrossFit day can carry **both a skill segment and a separate strength segment** before the metcon — not one segment with two flavors. This is closer to real CrossFit programming but adds a second segment slot to schedule and time-budget for.
- **D-03:** The CrossFit **warmup segment is genuinely different** from Phase 18's `WarmupResolver` — that resolver only computes a %1RM ramp for a single barbell/dumbbell/kettlebell working set. CrossFit's warmup is general movement prep (mobility, light cardio, movement rehearsal) and needs its own logic. Where a CrossFit day's skill/strength segment includes a loaded barbell lift, `WarmupResolver` still runs for that lift's ramp *inside* that segment — the standalone warmup segment is additive on top, not a replacement.
- **D-04:** **Cooldown is a lightweight placeholder** for this phase — it must exist structurally in the blueprint (present, ordered, shows in UI) but does not need curated exercise/stretch-level content or its own exercise pool yet.
- **Naming note (structural, not a "decision" but load-bearing):** the existing `WorkSegment` class (`lib/features/programs/domain/slot_prescription.dart`) is an unrelated concept — a per-slot set-group (sets/reps/intent within one exercise's prescription), not a session-level segment. The new session-segment concept from D-01–D-04 **must use a different name** to avoid collision/confusion in code and downstream docs.

### Metcon structure
- **D-05:** Metcons support **multi-movement circuits** (e.g. "21-15-9 thrusters/pull-ups"), not just single-exercise AMRAP/EMOM/For Time. This likely extends the existing `WorkoutCircuitData`/`CircuitsRepository` (already models ordered `CircuitExerciseData` rows per circuit) rather than introducing new schema from scratch — planning should verify how far that existing plumbing goes before adding anything new.
- **Claude's discretion:** Whether the time cap/format (AMRAP/EMOM/For Time) lives on the circuit as a whole vs. per movement; how a metcon's time cap flows into Phase 18's time-budget/session-length estimator (fixed-duration treatment vs. estimating below a For Time cap); and whether GPP conditioning content reuses the same metcon/circuit mechanism or stays a simpler, separate concept. All three were explicitly left to research/planning — but must be decided, not silently defaulted; canonical_refs below give the entry points to figure this out.

### GPP day shape (Full Body 2× + GPP)
- **Claude's discretion:** Whether GPP is a standalone 3rd training day (matching `SplitType.fullBodyAbGpp`'s existing 3-slot definition in `split_template.dart`) or a shorter block appended to Full Body A/B — the blueprint itself says "GPP/conditioning day OR shorter GPP addition, by agreement," and the user left the resolution to planning.
- **Claude's discretion:** The enforcement mechanism preventing GPP from becoming a 3rd Dynamic Effort day — a hard structural exclude of the Dynamic Effort/max-effort archetype on GPP slots, vs. relying on discipline-tag filtering (drawing only from the `gpp` tag pool) to naturally avoid heavy barbell DE work. CLAUDE.md's "no silently relaxed filters" principle should weigh toward the structural exclude if there's any doubt.
- **Claude's discretion:** Whether to expand the currently tiny `gpp`-tagged exercise pool (4 exercises in Phase 16 metadata) as content-curation work in this phase, or widen the eligible pool to also draw from `crossfit`-tagged conditioning movements (17 exercises already tagged). Research should assess whether 4 exercises is workably diverse before deciding.

### CrossFit level policy scope
- **D-06:** All three of the following level-policy axes need an **explicit decision during research/planning** (not left un-addressed): **time caps per level**, **combo/complexity limits**, and **recovery reserve**. The user did not lock the specific mechanism for any of the three (each was answered "you decide") but was explicit that all three must be resolved with a real answer, not silently dropped.
  - Time caps per level: candidate shapes are a level→multiplier applied to a base cap per metcon format, vs. a fixed per-level×format cap table.
  - Combo/complexity limits: candidate shapes are a simple movement-count ceiling per level, vs. a count ceiling plus a rule blocking a just-unlocked skill from being stacked with another demanding movement in the same metcon.
  - Recovery reserve: candidate shapes are a new, Phase-21-only session-spacing rule, vs. tying into the existing Hercul coaching engine's (Phase 13) recovery guidance if it has a usable hook.
- **Claude's discretion:** Whether skill-movement gating (muscle-up, handstand walk, snatch complex) is already sufficiently covered by Phase 16's `prerequisiteSlugs` + `ExerciseScalingResolver`, or needs CrossFit-specific extension (e.g. never placing a barely-unlocked skill inside a fatigued metcon). Research should check actual Phase 16 coverage against real CrossFit level expectations before deciding.
- **Claude's discretion:** Whether Olympic lift *complexes* (chained lifts like snatch + overhead squat + snatch balance) need a new complexity ladder, or whether Phase 16's existing scaling groups (6 exercises tagged `olympic`) already cover level-appropriate Olympic lift selection. Phase 16 models single-movement scaling, not chained complexes, so research should confirm the gap before building new logic.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Milestone & Blueprint Specs
- `docs/training-programs-physique-gamification-plan-2026-09-10.md` §"Faza 6 — CrossFit in Full Body 2× + GPP" (lines ~427-484) — Architecture blueprint, origin of CF-01–03: session blueprint segments, level policy axes, Full Body 2×+GPP preset, and the explicit "GPP/conditioning day OR shorter GPP addition, by agreement" open question (line 462).
- `docs/training-programs-physique-gamification-plan-2026-09-10.md` line 829 — Note that the CrossFit exercise/scaling matrix needed to be substantively determined before this phase starts; Phase 16 did most of this (disciplines, commonness tiers, scaling ladders, prerequisites) but coverage should be verified against Faza 6's specific examples (muscle-up, handstand walk, snatch complex).
- `.planning/REQUIREMENTS.md` CF-01–03 — Authoritative requirements for Phase 21.
- `.planning/ROADMAP.md` (Phase 21) — Milestone phase goal and success criteria.
- `CLAUDE.md` — "No silently relaxed filters" (relevant to the GPP/Dynamic-Effort guard), "Schema changes are five chores, not one" (relevant if any segment/circuit schema change is needed), "UI never touches drift directly."

### Prior Phase Context
- `.planning/phases/16-exercise-programming-metadata-discipline-taxonomy/16-CONTEXT.md` — D-09: the 5 canonical disciplines (`weights`, `calisthenics`, `crossfit`, `olympic`, `gpp`); this phase's exercise-tagging foundation.
- `.planning/phases/18-workout-time-budget-warmups-set-method-prescriptions/18-CONTEXT.md` — `SlotPrescriptionCodec`, `WorkSegment`/`Intent`/`SetType` model, and the time-budget/warmup logic this phase must not duplicate or collide with by name.

### Session Blueprint & Segment Domain
- `lib/features/programs/domain/slot_role.dart` — `SlotRole` enum (main/supplemental/accessory/isolation/conditioning) and `SlotRoleEligibility` mask — the existing per-slot role concept segments sit alongside (D-01).
- `lib/features/programs/domain/slot_prescription.dart` — `WorkSegment` class (per-slot set-group: sets/reps/intent) — **name collision risk**; the new session-segment concept must be named differently (see Naming note under D-01–D-04).
- `lib/features/workouts/domain/warmup_resolver.dart` — `WarmupResolver`, the existing %1RM barbell/dumbbell/kettlebell ramp calculator (Phase 18 D-08/D-09/D-10) that D-03 says is complementary to, not a replacement for, the new CrossFit warmup segment.
- `lib/features/workouts/data/planned_session_resolver.dart` — Where `PlannedSetSnapshot`s get materialized from `SlotPrescription`; likely integration point for however segments end up threading through to the active workout shell.

### Split & Discipline Domain
- `lib/features/programs/domain/split_template.dart` — `SplitType.crossfit` ("conservative conditioning-first skeleton," 3 slots) and `SplitType.fullBodyAbGpp` (Full Body A/B/GPP, already defined with `defaultDaysPerWeek: 3`) — the existing split-level stubs this phase gives real planner logic.
- `lib/features/programs/domain/programming_models.dart` — `TrainingStyle.crossfit` and `isConditioningFirst` — existing conditioning-first flag for CrossFit's exercise-selection style.
- `assets/data/exercise_programming_metadata.json` — Phase 16 metadata: 108 exercises, 17 tagged `crossfit`, 4 tagged `gpp`, 6 tagged `olympic`; scaling groups include `handstand_pushup` and `pistol_squat` (relevant to skill-gating discussion).
- `lib/data/local/exercise_importer.dart` — Where `disciplines`/scaling metadata gets mapped from the JSON into drift rows.

### Metcon & Circuit Domain
- `lib/features/workouts/data/circuits_repository.dart` — `CircuitsRepository`, `WorkoutCircuitData`, `CircuitExerciseData` — existing ordered-circuit plumbing D-05 says metcons should likely extend.
- `lib/features/workouts/domain/set_type.dart` — `SetType.amrap`/`.emom`/`.forTime` with their `metaKeys` (`capSeconds`/`rounds`, `minutes`/`repsPerMinute`, `elapsedSeconds`) — the existing per-slot format definitions that need to be reconciled with circuit-level time caps per D-05's discretion items.
- `lib/features/programs/domain/prescription_resolver.dart` / `lib/features/programs/domain/slot_prescription.dart` — Where `Intent.amrap`/`SetType.amrap` are currently assigned to a single slot; the seam that needs to widen for circuit-level metcons.

### Level Policy & Recovery Domain
- Phase 16's prerequisite/scaling system (`ExerciseScalingResolver`, `prerequisiteSlugs`, `verifyPrerequisites`) — referenced in `.planning/phases/16-exercise-programming-metadata-discipline-taxonomy/16-CONTEXT.md` — the existing gate that D-06's "skill-movement gating" discretion item builds on or extends.
- Hercul coaching engine (Phase 13, `.planning/phases/13-hercul-coaching-engine/13-CONTEXT.md`) — candidate integration point for the "recovery reserve" axis; research must confirm whether it has a usable hook before deciding.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `SplitType.crossfit` and `SplitType.fullBodyAbGpp` (`split_template.dart`): Already-defined split skeletons this phase fills in with real segment/planner content — no new split-selection UI needed.
- `WorkoutCircuitData`/`CircuitsRepository`: Already-built ordered-circuit data model, the most likely foundation for multi-movement metcons (D-05).
- `SetType.amrap`/`.emom`/`.forTime`: Already-built format types at the individual-slot level; need reconciling with circuit-level time caps rather than being rebuilt.
- Phase 16's discipline tags, commonness tiers, prerequisite gate, and `ExerciseScalingResolver`: Substantial existing content-curation and safety-gating infrastructure this phase should lean on rather than duplicate.

### Established Patterns
- CLAUDE.md's "no silently relaxed filters" principle — directly informs the GPP/Dynamic-Effort guard discretion item: prefer an explainable hard exclude over a filter that could quietly admit heavy DE work.
- Phase 16's "own domain model and tested policy per feature" principle (blueprint line 26: CrossFit/specialization/gamification "must not be added as extra `if` statements in the existing builder") — CrossFit's segment/level policy should be its own domain service (`crossfit_program_planner.dart`, `crossfit_scaling_policy.dart`, `gpp_program_planner.dart` per the blueprint's "Glavne datoteke" list), not inline conditionals in the generic planner.

### Integration Points
- Segment tagging (D-01) integrates with `SlotRole` at the row level — planning needs to decide the exact field/enum shape so materialization (`planned_session_resolver.dart`) and the active workout shell (Phase 20) can render segments in order without new schema if possible.
- Metcon circuits (D-05) integrate with the existing `CircuitsRepository`, but current `WorkoutCircuitData` rows aren't linked to `ProgramDayExercises`/scheduled workouts — that link (or a parallel one) needs designing.

</code_context>

<specifics>
## Specific Ideas

- Blueprint's worked metcon example: "21-15-9 thrusters/pull-ups" — a real multi-movement, rep-scheme circuit under one shared cap, used as the north star for D-05's multi-movement circuit decision.
- Blueprint's explicit open question on GPP shape: "GPP/conditioning day OR shorter GPP addition, by agreement" — the user confirmed this stays genuinely open, to be resolved during planning rather than pre-decided here.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 21-crossfit-gpp-training-tracks*
*Context gathered: 2026-09-16*
