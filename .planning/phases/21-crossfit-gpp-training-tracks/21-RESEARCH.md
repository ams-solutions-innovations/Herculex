# Phase 21: CrossFit & GPP Training Tracks - Research

**Researched:** 2026-09-16
**Domain:** Structured session blueprints, circuit-based conditioning formats, level-gated exercise scaling — inside a Flutter/drift offline-first program generator
**Confidence:** MEDIUM-HIGH (codebase-grounded; blueprint/spec claims verified against actual code, several diverge from the doc)

## Summary

Phase 21 is almost entirely additive glue on top of infrastructure that Phases 16–18 already built: `SlotRole`, `SetType.amrap/.emom/.forTime`, `WarmupResolver`, `WorkoutDurationEstimator`, `ExerciseScalingResolver`, `SlotPrescriptionCodec`, and `CircuitsRepository` all already exist and are tested. What is missing is (1) a session-level segment tag threaded through three tables and the materialization path, (2) a link from `WorkoutCircuitData`/`CircuitExerciseData` to a scheduled `ProgramDayExercises` row so a metcon can be *planned*, not just logged ad hoc, and (3) new domain services (`crossfit_program_planner.dart`, `crossfit_scaling_policy.dart`, `gpp_program_planner.dart`) that assemble segments, apply level policy, and drive the existing circuit/format plumbing — as the blueprint's own "Glavne datoteke" list anticipates.

One important discovery changes the shape of the work: the GPP/Dynamic-Effort guard (D-05 discretion item) is **already structurally enforced today**. `smart_program_planner.dart`'s `_needsFor` gives a GPP day exactly one `SlotRole.conditioning` slot, and `_methodFor` only ever assigns `SlotTrainingMethod.dynamicEffort` to `SlotRole.main`/`supplemental` (`role.isHeavy`) under a max-effort periodization model — `SlotRole.conditioning` short-circuits to `technique` before the DE branch is even reachable. This means the "hard structural exclude vs. discipline-tag filtering" discretion item is not a new build — it is confirming and regression-testing an existing invariant, then making sure GPP's expanded content (skill/strength/metcon segments) doesn't accidentally introduce a `SlotRole.main`/`supplemental` slot into the GPP day.

The `gpp` discipline tag pool is genuinely thin: exactly 4 exercises (burpee, rowing-erg, air-bike, stationary-bike), all novice, all pure cardio — no loaded carries, sled work, or sandbag work exists in the catalog under any discipline. The `crossfit` tag has 17 exercises including barbell/gymnastics/Olympic movements not appropriate for a "no 8×3, no DE" GPP day. Research recommends treating this as a curation gap that must be explicitly decided in planning (see Open Questions), not silently resolved by widening eligibility to the crossfit pool.

The Hercul coaching engine (Phase 13) has **no scheduling or generation-time hook** — it is a read-only, rule-driven dashboard messaging layer (`HerculEngine.evaluate` → ranked `HerculMessage` list for a card), not a gate that a program generator can consult mid-generation. "Recovery reserve" (D-06) therefore needs a new Phase-21-only mechanism; there is no existing integration point to reuse.

**Primary recommendation:** Add one nullable `sessionSegment` (or similarly named) text column to `ProgramExerciseSlots`, `ProgramDayExercises`, and `WorkoutExercises` (full five-chores schema bump), thread it through `PlannedExerciseSnapshot`/`materialize()`, and build three new pure-Dart domain services under `lib/features/programs/domain/` that consume existing `SlotRole`/`SetType`/`CircuitsRepository`/`ExerciseScalingResolver` machinery rather than duplicating it.

## User Constraints

<user_constraints>
### Locked Decisions

- **D-01:** Segments (warmup/skill/strength/metcon/cooldown) are represented by tagging existing rows — adding a segment identifier to `ProgramDayExercises`/slot rows alongside `SlotRole` — not a new segment table.
- **D-02:** A CrossFit day can carry both a skill segment and a separate strength segment before the metcon.
- **D-03:** The CrossFit warmup segment is genuinely different from `WarmupResolver` (general movement prep vs. %1RM ramp). Where a skill/strength segment includes a loaded barbell lift, `WarmupResolver` still runs inside that segment additively.
- **D-04:** Cooldown is a lightweight structural placeholder this phase — present/ordered/rendered, no curated content or exercise pool required yet.
- **Naming note:** The existing `WorkSegment` class (`slot_prescription.dart`) is unrelated (a per-slot set-group). The new session-segment concept must use a different name.
- **D-05:** Metcons support multi-movement circuits (e.g. "21-15-9 thrusters/pull-ups"), likely extending `WorkoutCircuitData`/`CircuitsRepository` rather than new schema — verify how far existing plumbing goes first.
- **D-05 discretion:** Whether time cap/format lives on the circuit as a whole vs. per movement; how a metcon's time cap flows into the time-budget/session-length estimator; whether GPP conditioning reuses the same metcon/circuit mechanism or stays separate. Must be decided, not defaulted.
- **GPP day shape discretion:** Standalone 3rd training day vs. shorter block appended to Full Body A/B.
- **GPP/DE guard discretion:** Structural hard exclude vs. discipline-tag filtering — CLAUDE.md's "no silently relaxed filters" weighs toward structural exclude.
- **GPP pool discretion:** Expand the 4-exercise `gpp` pool as content curation vs. widen eligibility to the 17 `crossfit`-tagged exercises. Research should assess pool diversity before deciding.
- **D-06:** Time caps per level, combo/complexity limits, and recovery reserve all need an explicit mechanism — not left unaddressed.
- **D-06 discretion (skill gating):** Whether Phase 16's `prerequisiteSlugs` + `ExerciseScalingResolver` already sufficiently covers skill-movement gating, or needs CrossFit-specific extension.
- **D-06 discretion (Olympic complexes):** Whether chained Olympic complexes need a new complexity ladder, or existing `olympic`-tagged scaling groups already cover it.

### Claude's Discretion

(See discretion items embedded above — all explicitly deferred to research/planning, not defaulted.)

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CF-01 | CrossFit sessions structure into ordered blueprint segments (warmup, skill/strength, metcon, cooldown) with time caps | See "Segment Tagging Mechanism" and "Metcon & Circuit Domain" below — concrete column/table plan and time-cap placement options |
| CF-02 | CrossFit experience levels scale movement complexity and metcon formats (AMRAP, EMOM, For Time) | See "Level Policy" section — confirms partial existing coverage (prerequisiteSlugs, ExerciseScalingResolver) and the specific gaps (Olympic complexes, kipping/strict muscle-up, missing handstand-walk exercise) |
| CF-03 | Full Body 2× + GPP split delivers dedicated conditioning sessions without unintended Dynamic Effort sets | See "GPP/Dynamic-Effort Guard — Already Enforced" below — the guard already exists structurally; work is regression-testing it plus deciding GPP day shape and exercise pool |
</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Segment ordering/blueprint assembly | API/Backend (domain, `lib/features/programs/domain/`) | Database/Storage (new column) | Pure Dart planning logic; persisted as a tag on existing rows per D-01 |
| Metcon circuit definition & time cap | API/Backend (`crossfit_program_planner.dart` + `CircuitsRepository`) | Database/Storage (link table/column) | Circuits already live in `data/`; new link from circuit → scheduled day is the gap |
| Level policy (time caps, complexity, recovery reserve) | API/Backend (new `crossfit_scaling_policy.dart`) | — | Pure policy logic, mirrors `ExerciseScalingResolver`'s existing pattern |
| GPP day content selection | API/Backend (`gpp_program_planner.dart`) | Database/Storage (`disciplines` JSON column, already exists) | Reuses Phase 16 discipline tags; no new catalog schema needed |
| Materialization into active workout | API/Backend (`planned_session_resolver.dart`) | Database/Storage (`WorkoutExercises` new column) | Existing single source of truth for Program → active workout; must not be duplicated |
| Segment rendering in active workout shell | Browser/Client (Phase 20 shell, read-only in this phase) | — | Phase 21 boundary explicitly stops at "whatever materialization/rendering those already do for ordered slots" |
| Time-budget integration for metcon caps | API/Backend (`WorkoutDurationEstimator`) | — | Existing estimator itemizes duration; needs a new component for fixed/cap-based segments (see Open Questions) |

## Standard Stack

No new external packages are required. This phase is pure Dart domain logic plus a drift schema migration inside the existing stack (Flutter 3.44, Dart 3.12, Riverpod, drift). No `## Package Legitimacy Audit` section is needed — no packages are being installed.

### Core (existing, reused)
| Component | Location | Purpose | Why Standard (for this phase) |
|-----------|----------|---------|-------------------------------|
| `SlotRole` / `SlotRoleEligibility` | `lib/features/programs/domain/slot_role.dart` | Per-slot job classification, eligibility mask | Segment tag sits *alongside* this, not inside it (D-01) |
| `SetType.amrap/.emom/.forTime` | `lib/features/workouts/domain/set_type.dart` | Format enum with `metaKeys` (`capSeconds`/`rounds`, `minutes`/`repsPerMinute`, `elapsedSeconds`) | Already the canonical per-slot format vocabulary; CF-01/02 reconciles this with circuit-level caps |
| `WarmupResolver` | `lib/features/workouts/domain/warmup_resolver.dart` | %1RM ramp calculator | Runs *inside* skill/strength segments per D-03; the new CrossFit warmup segment is additive, separate logic |
| `WorkoutDurationEstimator` | `lib/features/workouts/domain/workout_duration_estimator.dart` | Itemized session duration | Currently has no notion of a fixed/capped-duration block; extension point for metcon time caps |
| `ExerciseScalingResolver` | `lib/features/programs/domain/exercise_scaling_resolver.dart` | Progressive regression ladder traversal with rationale | Directly reusable for CrossFit skill-movement scaling; already enforces difficulty ceiling, equipment, prerequisites |
| `CircuitsRepository` / `WorkoutCircuitData` / `CircuitExerciseData` | `lib/features/workouts/data/circuits_repository.dart` | Ordered multi-exercise circuit CRUD + session/template insertion | D-05's foundation for multi-movement metcons; currently **not linked** to `ProgramDayExercises` |
| `SlotPrescriptionCodec` | `lib/features/programs/domain/slot_prescription_codec.dart` | Versioned JSON codec for `SlotPrescription` | Reuse as-is per phase boundary; do not fork a parallel codec for metcon prescriptions if avoidable |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| New `program_day_segments` table (blueprint's own suggestion, "potrebne program segment tabele/migracije") | Tagging existing rows (D-01, locked) | User explicitly locked the lighter-weight tagging path; a dedicated table was considered and rejected during discuss-phase |
| Extending `WorkSegment` with a session-segment field | New, separately-named enum/column | `WorkSegment` is a per-slot set-group (sets/reps/intent within one exercise), a different concept from a session-level segment; reusing it risks exactly the name confusion D-01's naming note warns about |

**Installation:** None — no new dependencies.

## Segment Tagging Mechanism (CF-01, D-01)

**Verified in code:** `ProgramDayExercises` (`lib/data/local/tables.dart:798-844`) currently has `slotRole` (text, default `'accessory'`), `trainingMethod`, `targetRir`, `restSeconds`, `prescriptionWhy`, `prescriptionJson`, `prescriptionCodecJson`, `variantConfigJson` — **no segment concept exists today**. `ProgramExerciseSlots` (the stable per-program slot definition, lines 850-871) has an analogous `role` column and no segment column either. `WorkoutExercises` (materialized active-workout row, lines 250-290+) has `plannedSlotRole` (mirrors `ProgramDayExercises.slotRole` at materialization time) but no segment mirror.

This means a segment tag needs to propagate through **three** tables to reach the active workout shell (Phase 20) without a schema-scope gap:
1. `ProgramExerciseSlots.sessionSegment` (or similar) — the stable, program-level definition.
2. `ProgramDayExercises.sessionSegment` — the per-day materialized-from-slot row (already has a `slotRole` sibling to mirror the pattern).
3. `WorkoutExercises.plannedSessionSegment` — the immutable active-workout snapshot (mirrors `plannedSlotRole`).

`PlannedExerciseSnapshot` (`planned_session_resolver.dart:57-89`) and `materialize()` (`planned_session_resolver.dart:332-409`) are the exact seam that already copies `slotRole` from `ProgramDayExercises` → `PlannedExerciseSnapshot` → `WorkoutExercises.plannedSlotRole`; a segment field threads through the identical path with no new architectural pattern needed.

Current schema version is **43** (`lib/data/local/database.dart:101`). This is a five-chores schema bump per CLAUDE.md: `schemaVersion` → 44, `onUpgrade` branch, drift schema dump/generate, migration test retargeting (`test/migration_test.dart`, `test/schema_v2*.dart`), and a matching `supabase/migrations/NNNN_*.sql` (all three tables are synced — verify via `SyncColumns`/`SyncTombstone` mixins present on all three, confirmed in the table defs read during this research).

**Recommendation:** A single small enum (5 values: `warmup`, `skill`, `strength`, `metcon`, `cooldown`) stored by `.id` string, `null` = "no segment" (ordinary strength-program rows outside CrossFit/GPP). Ordering within a segment still comes from `orderIndex`; the segment is a label overlay, not a new ordering axis — consistent with D-01's "ordering/grouping by segment is inferred from the tag rather than being a first-class table relationship."

## Metcon & Circuit Domain (CF-01, D-05)

**Verified:** `CircuitsRepository` (`lib/features/workouts/data/circuits_repository.dart`) is fully built and tested (`test/features/workouts/circuits_repository_test.dart`) with `createCircuit`/`updateCircuit`/`deleteCircuit`, `addCircuitToSession`, `addCircuitToTemplate`, and `startSessionFromCircuit`. `WorkoutCircuits` table has `name`, `notes`, `rounds` (int, default 3), `restSeconds` (default 90) — **no time-cap field, no format field (AMRAP/EMOM/For Time)**. `CircuitExercises` has `exerciseId`, `orderIndex`, `targetReps`, `targetWeightKg` — no per-exercise cap either.

Critically, **`WorkoutCircuitData` rows are never referenced by `ProgramDayExercises` or any program table** — circuits today are a purely ad-hoc, user-authored, logged-workout-time construct (`addCircuitToSession`/`addCircuitToTemplate` insert directly into `workout_exercises`/`template_exercises`, bypassing the program/slot layer entirely). This confirms the CONTEXT.md's own observation: **the link from a metcon circuit to a *planned/scheduled* program day does not exist and must be designed**, not merely reused.

Two viable designs, both consistent with the existing circuit plumbing:
1. **Circuit-as-slot-group:** A metcon becomes N `ProgramDayExercises` rows sharing a `supersetGroup` (the mechanism `WorkoutExercises`/`TemplateExercises` already use for circuits) tagged `sessionSegment = metcon`, with the circuit-level cap/format stored once — e.g. on the first row's `prescriptionCodecJson` meta, or a new nullable `circuitId` FK on `ProgramDayExercises` pointing at a `WorkoutCircuits` row created at generation time. This reuses `SetType.amrap/.emom/.forTime`'s existing `metaKeys` (`capSeconds`/`rounds`, `minutes`/`repsPerMinute`, `elapsedSeconds`) per-row, which already supports per-movement metadata — but a shared cap across movements (the "21-15-9 thrusters/pull-ups" example, one cap for the whole couplet) needs the cap value duplicated or hoisted to a shared owner.
2. **Explicit `programDayId` FK on `WorkoutCircuits`/new junction table:** Gives circuits a first-class link to a scheduled day without touching `ProgramDayExercises`' row shape, but is closer to the "new segment table" the blueprint suggested and D-01 explicitly avoided for segments — likely inconsistent with the tagging-not-tables principle unless scoped narrowly to circuits only (D-05 only locks that metcons "likely" extend circuit plumbing, not that no schema grows at all).

**Recommendation for planning:** Favor option 1 (shared `supersetGroup` + `sessionSegment=metcon` tag + cap-and-format stored once via a small addition to `prescriptionCodecJson`'s existing JSON meta, or a new lightweight `metconMetaJson` column) — it keeps the "tag existing rows" spirit of D-01 and avoids a second parallel linking mechanism. Whichever shape is chosen, `SetType.metaKeys` already gives the codec a precedent for storing `capSeconds`/`rounds`/`minutes`/`repsPerMinute`/`elapsedSeconds` — extend that vocabulary rather than inventing a new one.

**Time cap → time budget flow (D-05 discretion, open):** `WorkoutDurationEstimator.estimateExercise` (`workout_duration_estimator.dart:14-45`) computes duration from `workingSets × (reps × secondsPerRep + restSeconds)` — it has no concept of "this block is capped at N seconds regardless of reps performed." A metcon under a hard time cap (AMRAP, EMOM) has a **known, fixed duration** (the cap itself) — this should be treated as a fixed-duration input to `estimateSession`, not run through the per-rep formula. For Time is the harder case: duration is unknown until performed, bounded above by its cap; the estimator should treat it as "duration = cap" for budgeting purposes (conservative upper bound) rather than trying to predict actual completion time. This is a genuine estimator extension, not something already covered — flag as a concrete task, not a research gap.

## GPP/Dynamic-Effort Guard — Already Enforced (CF-03)

**Verified in `smart_program_planner.dart`:**
- `_needsFor` (line ~1204): a day labeled `'gpp'` returns exactly `const [_SlotNeed(null, null, SlotRole.conditioning)]` — a single conditioning-role slot, with an explicit code comment: *"A standalone GPP day is intentionally narrow: one conventional cardio/carry slot, not an opaque high-fatigue WOD."*
- `_methodFor` (line ~1158): `SlotTrainingMethod.dynamicEffort` is only ever returned when `role.isHeavy` (main/supplemental) **and** `model == PeriodizationModel.maxEffort` **and** `stressRole == DayStressRole.dynamicTechnique`. `SlotRole.conditioning` hits its own unconditional branch (`if (role == SlotRole.conditioning) return SlotTrainingMethod.technique;`) which is reached *before* the DE-eligible branches would apply to it, and `SlotRole.isHeavy` (`slot_role.dart:34`) is `main || supplemental` only — conditioning can never satisfy it.

This means: **the structural hard exclude the user's discretion item asks about already exists**, purely as a byproduct of `SlotRole` gating training-method eligibility. There is no code path today by which a GPP day's conditioning slot could receive Dynamic Effort. The work in this phase is:
1. Confirming this invariant does not regress when GPP gets richer segment content (skill/strength/metcon segments) — if planning decides to add a strength-flavored segment to GPP day, that segment must stay on `SlotRole.conditioning` (or another non-`isHeavy` role) to preserve the guard, not introduce `SlotRole.main`/`supplemental`.
2. Adding an explicit regression test asserting this (currently implicit/untested for the GPP case specifically — `smart_program_planner_test.dart` should be checked in planning for existing coverage).
3. Recommendation: **keep the structural exclude as primary** (already free) and treat discipline-tag filtering (drawing only from `gpp`-tagged exercises) as a secondary content-curation concern, per CLAUDE.md's "no silently relaxed filters" — this matches the user's own steer.

## GPP Exercise Pool — Verified Thin (D-05 discretion)

**Verified via `assets/data/exercise_programming_metadata.json` (108 exercises total):**
- `gpp` discipline: exactly **4 exercises** — `burpee`, `rowing-erg`, `air-bike`, `stationary-bike`. All `difficulty: novice`, `commonness: basic`, no `scalingGroup`. All are pure cardio/conditioning machines or bodyweight — **no loaded carries, sled work, sandbag work, or kettlebell complexes exist in the catalog under any discipline tag.**
- `crossfit` discipline: **17 exercises**, including `barbell-back-squat`, `front-squat`, `thruster`, `dumbbell-snatch`, `power-clean`/`hang-power-clean`/`clean-and-jerk`, `power-snatch`/`hang-snatch`/`squat-snatch`, `kipping-muscle-up`/`bar-muscle-up`, `chest-to-bar-pull-up`, plus the 4 `gpp` exercises (which are also tagged `crossfit`). Widening GPP eligibility to the full `crossfit` pool would admit barbell squats, Olympic lifts, and muscle-ups into a "no 8×3, no DE" conditioning day — directly against CF-03's intent.

**Recommendation:** 4 exercises is not workably diverse for a dedicated GPP day (a user would see the same 4 movements every session). Neither raw option in the CONTEXT.md discretion item is safe as-is:
- Widening to the full `crossfit` pool is unsafe (admits barbell/Olympic/gymnastics skill work).
- Leaving the pool at 4 is thin but *safe*.

A middle path — curating a handful of *additional* `gpp`-tagged entries from the existing `crossfit` set that are genuinely GPP-appropriate (e.g. `burpee` variants, carries, non-technical conditioning movements) rather than the technical/loaded ones — is content curation work, explicitly the kind of thing Phase 16 did for other disciplines. This phase's scope note says it "does not touch general program generation architecture" but curating `disciplines` JSON tags for a handful of existing catalog rows is data curation, not architecture, and is consistent with how Phase 16 shipped its metadata. **Flag as an explicit planning decision** (not resolved here) — the two safe options are: (a) curate 3-6 more `gpp` tags onto already-existing non-technical exercises (e.g. any dumbbell carry variants the catalog already has under other disciplines), or (b) ship with the 4-exercise pool for this phase and note the thinness as a known limitation/follow-up.

## GPP Day Shape (standalone 3rd day vs. shorter addition)

**Verified:** `SplitType.fullBodyAbGpp` (`split_template.dart:41-45`) is already defined with 3 named slots (`Full Body A`, `Full Body B`, `GPP`) and `defaultDaysPerWeek: 3` — i.e., the *split skeleton* already assumes GPP is a standalone 3rd day, not an appendix to A/B. `block_builder_view.dart` already wires `TrainingStyle.fullBody2xGpp` → `SplitType.fullBodyAbGpp` with `_daysPerWeek = 3` (line ~1106-1108) and `includeGppConditioning = true`.

Separately, `TrainingStyle.includesGppConditioning` (`programming_models.dart:122`) already triggers a conditioning slot appended to `'full'`-labeled days when a primary-lift specialization is active (`_needsFor`, line ~1215) — this is the "shorter GPP addition" mechanism, but it currently only fires in the specialization codepath, not generally.

**Recommendation:** The standalone 3rd-day shape is what the existing split skeleton, UI copy ("Two full-body strength sessions with optional general physical-preparedness work"), and slot-need logic already assume and partially implement. Building out the standalone-day path is strictly less new-architecture work than retrofitting a "shorter addition" mode onto Full Body A/B (which would require making GPP slot-count conditional on split choice). Unless the user's original blueprint intent was specifically the shorter-addition mode, the standalone day is the path of least resistance and matches what's already shipped. This is presented as a recommendation, not a lock — planning should make the explicit call.

## Level Policy (CF-02, D-06)

### Skill-movement gating — partially covered, not fully

**Verified in metadata:** Prerequisite coverage is **inconsistent** across near-identical skill movements:
- `bar-muscle-up`: `prerequisiteSlugs: ['pull-up', 'chest-dips']`, `scalingGroup: vertical_pull`, `scalingOrder: 6` — fully gated.
- `ring-muscle-up`: same prerequisites, `scalingOrder: 7` — fully gated.
- `kipping-muscle-up` and `strict-muscle-up`: `prerequisiteSlugs: []`, **no scalingGroup** — ungated. A beginner with zero pull-up history could be selected for `kipping-muscle-up` today if it ever entered a candidate pool (it currently can't, since nothing wires `crossfit`-tagged skill work into slot selection yet — but the metadata itself has the gap).
- `handstand-push-up`: `prerequisiteSlugs: ['pike-push-up']`, `scalingGroup: handstand_pushup`, `scalingOrder: 2` — gated.
- **`handstand-walk` does not exist anywhere in the 108-exercise catalog.** The blueprint's own example ("beginner without prerequisite proof doesn't get a muscle-up, handstand walk, or advanced snatch complex") references a movement that isn't in the exercise database at all yet.
- Olympic lifts (`power-clean`, `hang-power-clean`, `clean-and-jerk`, `power-snatch`, `hang-snatch`, `squat-snatch`): all `difficulty: advanced`, **all `prerequisiteSlugs: []`, none have a `scalingGroup`.** The *only* current protection is the difficulty ceiling (advanced-only) via `ExerciseProgrammingEligibility.allows`/`ExerciseScalingResolver._difficultySafe` — there is no prerequisite chain (e.g. requiring front-squat/overhead-press competency before power-clean) despite Phase 16's own D-07 example explicitly naming "clean & jerk requires front squat and overhead press" as a curated pairing. **This pairing was never actually curated into the JSON** — a gap between the Phase 16 CONTEXT.md's stated intent and the shipped data.

**Recommendation:** `ExerciseScalingResolver` + `prerequisiteSlugs` is architecturally sufficient (D-15/D-16 from Phase 16 already implement exactly the "return null / no safe candidate rather than silently crossing groups" behavior CF-02 needs) — **no new gating mechanism needs building**. What's needed is (a) fixing the metadata gaps found above (add `prerequisiteSlugs` to `kipping-muscle-up`/`strict-muscle-up`/Olympic lifts per Phase 16's own stated intent), and (b) deciding whether `handstand-walk` needs to be added as a new catalog row (content curation, likely out of this phase's architecture-only scope, but must be flagged rather than silently ignored since the blueprint names it explicitly).

### Olympic lift complexes — no scaling ladder exists

**Verified:** All 6 `olympic`-tagged exercises have `scalingGroup: null`. There is no chained-complex model anywhere in the codebase (`WorkSegment`/`SlotPrescription` model single-exercise prescriptions; nothing composes "snatch + overhead squat + snatch balance" as one unit). Building this would be genuinely new domain modeling, not a metadata fix. Given D-06 says only that this "needs a new complexity ladder or existing scaling groups already cover it" — **existing scaling groups do not cover it** (confirmed: zero Olympic exercises have any `scalingGroup`), so the discretion resolves to: either build minimal new complexity-ladder logic, or scope Phase 21 to single-movement Olympic lift selection only (gated by difficulty ceiling + newly-added prerequisites) and explicitly defer chained complexes. Given phase boundary language ("does not touch general program generation architecture"), scoping to single-movement selection with an explicit deferred note is the lower-risk recommendation — full complex-ladder modeling is a meaningfully sized sub-feature.

### Time caps, combo/complexity limits, recovery reserve — all need new mechanism

- **Time caps per level:** No existing per-level time-cap table or multiplier exists anywhere in the codebase (`WorkoutDurationEstimator` estimates duration, doesn't cap it; `SetType.amrap.metaKeys` includes `capSeconds` but nothing currently populates it by level). This is new logic regardless of which shape (multiplier vs. fixed table) planning picks.
- **Combo/complexity limits:** No existing "movement count ceiling per metcon" or "don't stack a fresh skill with another demanding movement" rule exists. New logic.
- **Recovery reserve:** Confirmed via Phase 13 CONTEXT.md — Hercul is a **read-only, dashboard-card messaging engine** (`HerculEngine.evaluate(rules, context, lastFiredAt) → ranked List<HerculMessage>`), driven by a static JSON rule corpus and computed signal snapshots (`CnsTrends`, `MuscleRecoveryV3`, etc.). It has no generation-time API, no scheduling authority, and nothing in its pipeline is called during program generation — it only *describes* facts already computed elsewhere, after the fact, for a UI card. **There is no usable hook.** D-06's recovery-reserve axis needs a new, Phase-21-only session-spacing rule (e.g. consulting existing `CnsTrends`/`MuscleRecoveryV3` signals directly — the same underlying engines Hercul itself reads — rather than going through Hercul's message layer).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| AMRAP/EMOM/For Time set semantics | A parallel CrossFit-specific format enum | `SetType.amrap/.emom/.forTime` (already exists with `metaKeys`) | Already built, tested, and understood by `set_entries.set_type` storage |
| Skill-movement regression/gating | New prerequisite-checking logic | `ExerciseScalingResolver` + `ExerciseProgrammingEligibility.verifyPrerequisites` | Already implements exactly the "return null, never silently cross groups" behavior CF-02 needs; only the *data* (prerequisiteSlugs) has gaps, not the mechanism |
| Multi-movement circuit ordering | New segment-internal ordering scheme | `CircuitExercises.orderIndex` / `supersetGroup` pattern already used by `WorkoutExercises`/`TemplateExercises` | Same pattern already proven for logged circuits; reuse rather than reinvent |
| Warmup ramp math inside a loaded skill/strength segment | A CrossFit-specific %1RM ramp calculator | `WarmupResolver` (Phase 18) | D-03 explicitly says this is additive, not replaced |
| Prescription JSON storage for metcon meta | A new bespoke JSON shape | Extend `SetType.metaKeys` vocabulary / `SlotPrescriptionCodec`'s existing `meta` map pattern (already used by `myoReps`, `restPause`, etc.) | Codec and meta-map pattern already exist and are tested; extending is far cheaper than forking |

**Key insight:** Nearly every mechanism CF-01–03 needs already exists in some adjacent form (`SetType`, `SlotRole`, `ExerciseScalingResolver`, `CircuitsRepository`, `WarmupResolver`). The actual net-new work is thin glue (a segment tag, a circuit↔day link, a level-policy service, a duration-estimator extension for capped/fixed-duration blocks) — the risk in this phase is *duplicating* existing infrastructure under CrossFit-specific names rather than composing it.

## Architecture Patterns

### System Architecture Diagram

```
Block Builder UI (TrainingStyle.crossfit / fullBody2xGpp selection)
        │
        ▼
SplitTemplates.generate(SplitType.crossfit | fullBodyAbGpp)
        │  (existing — produces day skeleton, 3 slots)
        ▼
SmartProgramPlanner._needsFor(label, trainingStyle, ...)
        │  (existing entry point — currently returns bare
        │   SlotRole.conditioning slots for gpp/crossfit days)
        ▼
   NEW: crossfit_program_planner.dart / gpp_program_planner.dart
        │  assembles ordered segment list per day:
        │  [warmup?, skill?, strength?, metcon, cooldown?]
        │  each segment → one or more ProgramExerciseSlots
        │  tagged with sessionSegment
        ▼
   NEW: crossfit_scaling_policy.dart
        │  applies D-06 level policy per segment:
        │  - ExerciseScalingResolver for skill movement selection
        │  - time-cap-by-level for metcon format
        │  - combo/complexity ceiling for circuit movement count
        │  - recovery-reserve spacing check (new signal read)
        ▼
ProgramExerciseSlots / ProgramDayExercises rows written
   (existing tables + new sessionSegment column)
        │
        ▼
PlannedSessionResolver.resolveProgramDay()
        │  (existing — extended to read sessionSegment,
        │   route metcon segments through CircuitsRepository-
        │   shaped data, run WarmupResolver additively per D-03)
        ▼
PlannedSessionSnapshot → materialize()
        │  (existing — extended to write
        │   WorkoutExercises.plannedSessionSegment)
        ▼
Active Workout Shell (Phase 20, read-only consumer this phase)
```

### Recommended Project Structure
```
lib/features/programs/domain/
├── session_segment.dart          # NEW — 5-value enum (warmup/skill/strength/metcon/cooldown)
├── crossfit_program_planner.dart # NEW — assembles CrossFit day segment list
├── crossfit_scaling_policy.dart  # NEW — D-06 level policy (time caps, complexity, recovery)
├── gpp_program_planner.dart      # NEW — assembles GPP day content (conditioning-only)
├── slot_role.dart                # existing, unchanged
├── slot_prescription.dart        # existing, unchanged (WorkSegment stays as-is)
├── exercise_scaling_resolver.dart # existing, reused as-is
lib/features/workouts/
├── data/circuits_repository.dart  # existing — extend with a program-day link method
├── data/planned_session_resolver.dart # existing — extend to read sessionSegment + circuit link
├── domain/workout_duration_estimator.dart # existing — extend with fixed/capped-duration segment support
```

### Pattern: Segment as a tag, not a table (D-01)
**What:** A `sessionSegment` enum value stored per-row on the same table that already carries `SlotRole`, rather than a `ProgramDaySegments` parent table.
**When to use:** Any time a concept needs ordering *within* an existing ordered collection rather than a new grouping relationship. Segments are inferred by grouping consecutive/matching-tag rows client-side (planner and materializer), not by a FK join.
**Example:**
```dart
// Source: pattern inferred from existing SlotRole usage in
// lib/data/local/tables.dart and planned_session_resolver.dart
enum SessionSegment {
  warmup('warmup'),
  skill('skill'),
  strength('strength'),
  metcon('metcon'),
  cooldown('cooldown');

  const SessionSegment(this.id);
  final String id;

  static SessionSegment? fromId(String? id) =>
      id == null ? null : values.firstWhereOrNull((s) => s.id == id);
}
```

### Anti-Patterns to Avoid
- **Reusing `WorkSegment` for session segments:** `WorkSegment` is per-slot set-group data (sets/reps/intent within one exercise's prescription). D-01's naming note makes this an explicit collision risk — a second, differently-scoped class must not share the name or the type.
- **Building a parallel `crossfit_circuits` table:** `WorkoutCircuitData`/`CircuitExerciseData` already model ordered circuits; extend or link to them, don't fork.
- **Re-deriving Olympic/skill-movement safety from scratch:** `ExerciseScalingResolver` already implements the "no safe candidate → return null, never silently cross groups" contract Phase 16 built specifically for this purpose.

## Common Pitfalls

### Pitfall 1: Segment tag not threaded all the way to `WorkoutExercises`
**What goes wrong:** Segment tag added only to `ProgramDayExercises`, forgotten on `WorkoutExercises` (the materialized/immutable row Phase 20's shell actually reads).
**Why it happens:** `ProgramDayExercises` is the natural first place to add a column since it's where `slotRole` already lives; the mirror onto `WorkoutExercises.plannedSlotRole` at materialization time is easy to miss because it happens inside `materialize()`'s `WorkoutExercisesCompanion.insert(...)` call, several files away from the schema change.
**How to avoid:** Grep for every existing `plannedSlotRole`/`slotRole` occurrence and add the segment column at each corresponding site (3 tables, `PlannedExerciseSnapshot`, `materialize()`).
**Warning signs:** Active workout shell renders CrossFit sessions with no segment headers even though the program preview shows them correctly.

### Pitfall 2: GPP guard regression via a new "strength" segment
**What goes wrong:** If GPP day content is expanded beyond pure conditioning (e.g. adding a light strength segment for variety), a naive implementation assigns that segment's slots `SlotRole.main`/`supplemental`, silently re-opening the DE eligibility the current architecture structurally closes.
**Why it happens:** `_methodFor`'s DE gate is keyed on `role.isHeavy`, not on split type or day label — nothing stops a new codepath from creating a heavy-role slot on a GPP day.
**How to avoid:** Keep every GPP-day slot on `SlotRole.conditioning` (or another non-`isHeavy` role) categorically; add a regression test asserting no GPP-labeled day ever produces a `SlotTrainingMethod.dynamicEffort` slot regardless of periodization model.
**Warning signs:** A GPP day preview shows an 8×3-shaped prescription or a "Dynamic Effort" method label.

### Pitfall 3: Treating a For Time cap as a hard duration in the estimator
**What goes wrong:** `WorkoutDurationEstimator` is fed the time cap as if it were the *actual* expected duration for every level, overestimating session length for advanced athletes who finish well under cap and underestimating variance for beginners near the cap.
**Why it happens:** The cap is the only concrete number available at generation time; actual completion time is unknowable until performed.
**How to avoid:** Document explicitly that for-time-capped segments use the cap as a conservative upper bound for time-budget purposes, not a point estimate — consistent with Phase 18's existing philosophy of itemized-not-flat estimation, applied to the one case where a true point estimate is impossible.
**Warning signs:** Users on a tight time budget get sessions that "estimate" as fitting but the metcon segment alone consumes the entire budget at cap.

### Pitfall 4: Inconsistent prerequisite curation silently admitting unsafe skill movements
**What goes wrong:** `kipping-muscle-up`/`strict-muscle-up`/Olympic lifts have empty `prerequisiteSlugs` today; if CrossFit slot selection starts drawing from the `crossfit` discipline pool without first fixing this metadata gap, a beginner could be selected for a technical/high-injury-risk movement with zero prerequisite gate, even though the adjacent `bar-muscle-up`/`ring-muscle-up` variants are correctly gated.
**Why it happens:** The metadata curation gap (documented above) predates this phase and is easy to miss since the difficulty ceiling (`advanced`-only) provides partial, easily-mistaken-for-complete protection.
**How to avoid:** Curate `prerequisiteSlugs` for the identified gaps (`kipping-muscle-up`, `strict-muscle-up`, all 6 Olympic lifts) as an explicit task before or alongside wiring CrossFit skill selection, following Phase 16's own D-07 stated intent (front-squat/overhead-press → clean & jerk, etc.).
**Warning signs:** A generated novice/intermediate CrossFit program includes a kipping muscle-up or an Olympic lift with no completed-prerequisite check in its selection rationale.

## Code Examples

### Existing GPP guard (already structurally correct — reference, not new code)
```dart
// Source: lib/features/programs/data/smart_program_planner.dart:1218-1231
// A standalone GPP day is intentionally narrow: one conventional cardio
// / carry slot, not an opaque high-fatigue WOD. It remains easy to edit or
// remove through the normal program editor.
if (value.trim() == 'gpp') {
  return const [_SlotNeed(null, null, SlotRole.conditioning)];
}
```
```dart
// Source: lib/features/programs/data/smart_program_planner.dart:1178-1198
// DE only reachable for role.isHeavy (main/supplemental) — SlotRole.conditioning
// short-circuits to `technique` before this branch is relevant.
if (model == PeriodizationModel.maxEffort &&
    experience != ExperienceLevel.novice &&
    stressRole == DayStressRole.dynamicTechnique &&
    role.isHeavy) {
  return SlotTrainingMethod.dynamicEffort;
}
...
if (role == SlotRole.conditioning) return SlotTrainingMethod.technique;
```

### Existing scaling ladder pattern to extend for level policy
```dart
// Source: lib/features/programs/domain/exercise_scaling_resolver.dart:30-111
// Already returns null / no-safe-candidate rather than silently crossing
// groups — the exact contract CF-02's skill gating needs, no new mechanism
// required, only metadata fixes (see Pitfall 4).
ScalingResolutionResult regress({
  required ExerciseCatalogData target,
  required List<ExerciseCatalogData> groupCandidates,
  required ExperienceLevel experience,
  ...
})
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|---------------|--------|
| Fixed hardcoded warmup ramp tables | `WarmupResolver` computed ramps | Phase 18 (shipped, this milestone) | CrossFit warmup segment must not reintroduce a fixed table — additive, separate logic per D-03 |
| Ad-hoc `templateSets` JSON blob for prescriptions | `SlotPrescriptionCodec` versioned wire format | Phase 18 (shipped, this milestone) | Any new metcon-meta storage should extend this codec's `meta` map pattern, not fork a new blob format |
| GPP/CrossFit as bare 2-conditioning-slot stub | (this phase) full segment blueprint | In progress | The entire "session blueprint" concept is genuinely new for this phase — no prior art to defer to beyond the generic `SlotRole`/`SetType` machinery |

**Deprecated/outdated:** None identified — this is a young milestone (v2.0, in progress since 2026-09-13), no legacy CrossFit implementation to migrate away from.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Curating additional `gpp` discipline tags onto existing catalog exercises counts as "data curation" rather than "program generation architecture" and is therefore in-scope for this phase per its own boundary note | GPP Exercise Pool | If the user considers any metadata/JSON change out of scope, this must be re-scoped to Phase 16 follow-up work or explicitly deferred |
| A2 | The standalone-3rd-day GPP shape is the intended interpretation of "GPP/conditioning day OR shorter GPP addition, by agreement" rather than the shorter-addition mode | GPP Day Shape | If the user actually wants the shorter-addition mode, the recommended low-risk path (leverage existing `fullBodyAbGpp` skeleton) is wrong and more retrofit work on Full Body A/B is needed |
| A3 | `handstand-walk`'s absence from the catalog is acceptable to defer/flag rather than requiring a new catalog row be added in this phase | Level Policy — skill-movement gating | If the user expects handstand-walk gating to work per the blueprint's literal example, a new exercise row (plus prerequisites/scaling) must be added, which is catalog-curation work not currently scoped |
| A4 | Extending `SetType.metaKeys`/`SlotPrescriptionCodec`'s meta map is preferable to a new `metconMetaJson` column for storing circuit-level time caps | Metcon & Circuit Domain | If a shared-cap-across-movements requirement can't be expressed cleanly in per-row meta, a small new column may actually be simpler; this is a real design decision for planning, not settled by this research |

**If this table is empty:** N/A — see above; all four items should be confirmed or explicitly decided during planning/discuss-phase follow-up if not already resolved by the locked CONTEXT.md decisions.

## Open Questions

1. **Where does a metcon's time cap live — per-circuit or per-movement — and how does it reach the time-budget estimator?**
   - What we know: `SetType.metaKeys` already supports per-row `capSeconds`/`elapsedSeconds`/`minutes`; `WorkoutCircuits` has no cap field at all today.
   - What's unclear: Whether the "21-15-9 thrusters/pull-ups" pattern (one shared cap for a whole couplet) is better modeled as one cap value duplicated per movement row, or hoisted to a single circuit-level owner.
   - Recommendation: Planning should pick one storage shape and document it in the plan; recommend hoisting to a circuit-level value (new column or `programDayExercises`-group-level meta) since duplicating a cap risks drift between rows if one is edited independently.

2. **Does GPP content curation (adding more `gpp` tags) happen inside this phase or get deferred?**
   - What we know: 4 exercises is measurably thin; widening to `crossfit` tags is unsafe per CF-03's intent.
   - What's unclear: Whether the user considers touching `exercise_programming_metadata.json` "architecture" (explicitly out of scope) or "content" (implicitly in scope, following Phase 16's own precedent).
   - Recommendation: Flag explicitly at plan-check; default to shipping with the 4-exercise pool and noting the limitation if not otherwise resolved, since it's the safer/smaller-scope default.

3. **Should Olympic lift chained complexes be built in this phase, or explicitly deferred?**
   - What we know: Zero existing scaffolding (`scalingGroup: null` on every Olympic exercise); genuinely new modeling work.
   - What's unclear: Whether CF-02's "scale movement complexity" success criterion is satisfied by single-movement Olympic lift selection (already achievable via difficulty ceiling + newly-curated prerequisites) or requires the chained-complex ladder specifically.
   - Recommendation: Scope to single-movement selection for this phase; explicitly note chained complexes as a deferred idea if the plan doesn't build them, so it isn't silently dropped.

## Environment Availability

No external tool/service dependencies for this phase — pure Dart domain logic plus a drift/SQLite schema migration inside the existing Flutter toolchain. Flutter 3.44/Dart 3.12/drift are already the verified project toolchain per CLAUDE.md; no new environment probing needed.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | `flutter_test` (existing, per CLAUDE.md commands) |
| Config file | none — standard `flutter test` discovery |
| Quick run command | `flutter test test/features/programs/... test/features/workouts/... 2>&1 \| tr '\r' '\n'` (redirect to file, per CLAUDE.md — piping to `tail` loses exit code) |
| Full suite command | `flutter test > /tmp/test-out.txt 2>&1; tr '\r' '\n' < /tmp/test-out.txt \| tail -50` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CF-01 | Segment tag threads through `ProgramExerciseSlots`→`ProgramDayExercises`→`WorkoutExercises`, ordered correctly | unit | `flutter test test/features/workouts/planned_session_resolver_test.dart` (or equivalent) | Verify in planning — resolver-level test likely exists for `slotRole`, needs a segment-parallel case |
| CF-01 | AMRAP/EMOM/For Time formats preserve time caps through materialization | unit | new test in `test/features/workouts/` | ❌ Wave 0 |
| CF-02 | Novice/intermediate/advanced generate different, prerequisite-gated skill/scaling selections | unit | `flutter test test/exercise_scaling_resolver_test.dart` (extend existing file) | ✅ exists, extend |
| CF-03 | GPP day never produces `SlotTrainingMethod.dynamicEffort` regardless of periodization model | unit/regression | new test targeting `SmartProgramPlanner` GPP day generation | ❌ Wave 0 |
| CF-03 | Full Body 2×+GPP delivers 2 strength days + GPP content without 8×3 | integration | `flutter test test/features/programs/smart_program_planner_test.dart` (verify existing file covers this; extend if not) | Verify in planning |

### Sampling Rate
- **Per task commit:** targeted `flutter test` on touched test files.
- **Per wave merge:** full `flutter test` suite (CLAUDE.md: ~2min, 1308 pass / 4 skipped baseline — expect growth).
- **Phase gate:** Full suite green plus `flutter analyze` (0 errors) before `/gsd:verify-work`, per CLAUDE.md.

### Wave 0 Gaps
- [ ] Regression test asserting no GPP-labeled day produces `SlotTrainingMethod.dynamicEffort` — covers CF-03's core guarantee explicitly (currently true by construction but untested for this specific case).
- [ ] Test for segment-tag threading through the three-table materialization path — covers CF-01.
- [ ] Test for AMRAP/EMOM/For Time time-cap preservation end-to-end (program day → planned snapshot → materialized `WorkoutExercises`/`SetEntries`) — covers CF-01's "time caps preserved" success criterion.
- [ ] Metadata curation: add `prerequisiteSlugs` to `kipping-muscle-up`, `strict-muscle-up`, and all 6 Olympic-tagged exercises (data task, not test, but blocks CF-02's gating from being meaningfully testable against Faza 6's own named examples).

## Security Domain

`security_enforcement` is absent from `.planning/config.json` — treated as enabled per protocol, but this phase has effectively no attack surface: no new auth, no new network calls, no new user input parsing beyond program-builder UI (already-validated Riverpod state), and no new PII. Local drift/SQLite storage only, following the project's existing offline-first sync model.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-------------------|
| V2 Authentication | no | No auth surface touched |
| V3 Session Management | no | No session surface touched |
| V4 Access Control | no | Single-user local app; no multi-tenant access control in scope |
| V5 Input Validation | marginal | New enum (`SessionSegment`) parsed via `fromId`-style safe lookup pattern already used project-wide (`SlotRole.fromId`, `SetType.fromId`) — reuse that pattern, never trust raw stored strings without a safe fallback |
| V6 Cryptography | no | No new secrets/crypto |

### Known Threat Patterns for {stack}

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|----------------------|
| Malformed/legacy `prescriptionCodecJson`/new `metconMetaJson` causing a decode exception to propagate into UI | Tampering / DoS (local) | Follow `SlotPrescriptionCodec.decode`'s existing try/catch-return-null pattern for any new JSON meta added for metcon caps |
| Supabase sync of a new `sessionSegment` column with a mismatched Postgres migration causing PGRST204 quarantine | Tampering (data integrity) | Follow CLAUDE.md's five-chores checklist exactly — matching `supabase/migrations/NNNN_*.sql` is mandatory, not optional, for every synced table touched |

## Sources

### Primary (HIGH confidence — direct codebase reads during this research session)
- `lib/features/programs/domain/slot_role.dart` — `SlotRole`, `SlotRoleEligibility`
- `lib/features/programs/domain/slot_prescription.dart` — `WorkSegment`, `SlotPrescription`, `Intent`
- `lib/features/workouts/domain/warmup_resolver.dart` — `WarmupResolver`
- `lib/features/workouts/data/planned_session_resolver.dart` — `PlannedSessionResolver`, `materialize`
- `lib/features/programs/domain/split_template.dart` — `SplitType`, `SplitTemplates`
- `lib/features/programs/domain/programming_models.dart` — `TrainingStyle`, `SlotTrainingMethod`
- `lib/features/workouts/data/circuits_repository.dart` — `CircuitsRepository`
- `lib/features/workouts/domain/set_type.dart` — `SetType`
- `lib/features/programs/domain/prescription_resolver.dart` — `PrescriptionResolver`
- `lib/features/programs/domain/exercise_scaling_resolver.dart` — `ExerciseScalingResolver`
- `lib/features/workouts/domain/workout_duration_estimator.dart` — `WorkoutDurationEstimator`
- `lib/features/programs/domain/slot_prescription_codec.dart` — `SlotPrescriptionCodec`
- `lib/data/local/tables.dart` — `ExerciseCatalog`, `ProgramDayExercises`, `ProgramExerciseSlots`, `WorkoutCircuits`, `CircuitExercises`, `WorkoutExercises` schema
- `lib/data/local/database.dart` — `schemaVersion` (43)
- `assets/data/exercise_programming_metadata.json` — 108-exercise discipline/prerequisite/scaling data, queried programmatically for gpp/crossfit/olympic tag membership and prerequisite coverage
- `lib/features/programs/data/smart_program_planner.dart` — `_needsFor`, `_methodFor` (GPP/DE guard verification)
- `lib/features/programs/presentation/views/block_builder_view.dart` — existing CrossFit/GPP builder UI wiring
- `docs/training-programs-physique-gamification-plan-2026-09-10.md` §"Faza 6" — origin blueprint text (Slovenian), cross-checked against actual code
- `.planning/phases/13-hercul-coaching-engine/13-CONTEXT.md` — Hercul architecture (recovery-reserve hook investigation)
- `.planning/phases/16-exercise-programming-metadata-discipline-taxonomy/16-CONTEXT.md`, `.planning/phases/18-workout-time-budget-warmups-set-method-prescriptions/18-CONTEXT.md` — prior-phase decisions this phase builds on

### Secondary (MEDIUM confidence)
None — all claims in this document were verified directly against the codebase or CONTEXT.md files during this research session; no WebSearch was needed since this is entirely an internal-codebase research task.

### Tertiary (LOW confidence)
None.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new external dependencies; all reused components read directly from source.
- Architecture: HIGH — segment-tagging and circuit-link designs are grounded in actual table/resolver code, not speculation.
- Pitfalls: HIGH — the GPP/DE guard finding and prerequisite-gap findings are directly reproducible from the JSON/code, not inferred.
- Level policy specifics (exact time-cap formula, complexity ceiling numbers): LOW — no existing mechanism to anchor against; genuinely new design left to planning per D-06's explicit "you decide."

**Research date:** 2026-09-16
**Valid until:** 30 days (internal codebase research; stale if Phase 17/19/20 land with structural changes to `ProgramDayExercises`/`PlannedSessionResolver` before Phase 21 planning executes)
