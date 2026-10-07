# Phase 17: Deterministic Program Planner & Hard Guardrails - Context

**Gathered:** 2026-09-13
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 17 unifies program generation under a single authoritative `ProgramGenerationRequest` contract, enforces hard filters (injury/pain, equipment, style, experience, prerequisites) before scoring with zero silent relaxation, guarantees anchor lifts persist across a block's weeks, and returns human-readable selection rationales for chosen and excluded movements. It builds directly on Phase 16's metadata/eligibility/scaling-ladder work; it does not touch prescription/time-budget concerns (Phase 18) or the editor UI (Phase 19) beyond leaving clean data for them to consume.

</domain>

<decisions>
## Implementation Decisions

### No-Safe-Candidate Behavior
- **D-01:** When a slot's hard filters (injury/pain, equipment, style, experience, prerequisites) leave zero candidates, the slot is left empty (no `ProgramDayExercises` row, or a placeholder marker) rather than filled via any relaxation of those filters. A `SelectionExplanation` records why nothing qualified.
- **D-02:** The "never relax" guarantee applies strictly to the 5 named hard filters. Pattern/muscle targeting (`need.pattern`, `need.muscle`) is a soft placement preference and may still relax to fill a slot, exactly as `smart_program_planner.dart:335-358` does today — that fallback logic stays, scoped so it never crosses into equipment/injury/style/experience/prerequisite territory.
- **D-03:** Before declaring a slot truly empty, the planner consults Phase 16's `ExerciseScalingResolver` for a safer/easier regression on the same movement pattern. Only if the scaling resolver also returns null does the slot count as "no safe candidate."
- **D-04:** Empty slots are surfaced visibly in the program view with a short explanation (e.g. "No safe [pattern] movement available for your equipment/injuries") rather than being an invisible gap — this requires new UI in the program day view, in scope for Phase 17's user-facing surface even though the full editor lands in Phase 19.

### Injury/Pain as a Hard Filter
- **D-05:** Injury/pain filtering reuses Recovery's existing `JointModel.influencingMuscles` (joint → weighted muscle map) rather than inventing a new movement-pattern-based mapping. This is the same mechanism that already drives muscle exclusions in `TrainingSuggestion` (`lib/features/recovery/domain/training_suggestion.dart`) — one source of truth shared between Recovery and program generation.
- **D-06:** Any flagged joint-pain severity (severity >= 1, per `JointPainStatus.isFlagged`) triggers a hard exclusion of exercises whose `primaryMuscle` is in that joint's influencing-muscle set (same `>= 0.5` weight threshold `TrainingSuggestion` already uses). This is not a soft scoring penalty — it's a full candidate-pool exclusion, matching the "no silently relaxed filters" principle.
- **D-07:** Injury/pain data flows into generation as an explicit field on `ProgramGenerationRequest` (e.g. `excludedMuscles` or `flaggedJoints`), computed once by the caller from `JointPainRepository.watchCurrentStatuses()` before generation starts. The planner itself does not query `JointPainRepository` live — this keeps `SmartProgramPlanner`/the deterministic scorer pure, deterministic, and unit-testable with fixed inputs.
- **D-08:** If joint-pain exclusion empties a slot, it gets the exact same visible-gap-with-explanation treatment as any other hard-filter exhaustion (D-01/D-04) — no special-cased fallback to an unsafe or off-pattern movement.

### Anchor Lift Guarantee Mechanism
- **D-09:** An "anchor" is a specific exercise, not a movement pattern. Once week 1 selects an exercise (e.g. Back Squat) for a `SlotRole.main` slot, every subsequent week in the block reuses that same exercise — preserving load/1RM progression continuity — rather than allowing rotation to swap it for pattern variety.
- **D-10:** Anchor-lift protection applies to every slot with `SlotRole.main`, not just a single "primary lift of the day." This matches how `RotationPolicy` already special-cases `main`-role scoring today (`smart_program_planner.dart:392-400`).
- **D-11:** Anchors remain manually overridable at any point mid-block via the exercise replacement flow (Phase 19's `thisWave`/`thisAndFutureWaves`/`entireBlock` scopes, per EDIT-02). The Phase 17 guarantee is only a defense against *automatic* rotation logic silently swapping the anchor — it must not fight deliberate user-driven replacement, even though the replacement UI itself ships in Phase 19.
- **D-12:** If a locked anchor exercise becomes injury-excluded mid-block (e.g. a new joint-pain flag appears after week 1), the safety hard filter wins and breaks the anchor lock — the slot re-resolves under the normal candidate/scaling-ladder/no-safe-candidate flow (D-01–D-03), it does not silently keep prescribing an now-unsafe anchor with just a warning.

### Claude's Discretion
- Exact `ProgramGenerationRequest` field names/shapes for `excludedMuscles`/`flaggedJoints` and the anchor-lock bookkeeping (e.g. a `lockedAnchors: Map<slotKey, exerciseId>` carried between week iterations in `populate()`).
- Whether the empty-slot placeholder is a null-exercise `ProgramDayExercises` row with a sentinel, or the day list simply renders fewer items keyed off `SelectionExplanation` records — left to planning/implementation, as long as D-04's visible-gap-with-explanation UX outcome is met.
- Migration path for the existing unused `ProgramGenerationRequest` class in `programming_models.dart` vs. the currently-used `SmartProgramConfiguration` — planner/researcher to determine whether this phase fully replaces `SmartProgramConfiguration` call sites or adapts one into the other.
- Exact `SelectionExplanation` schema/persistence (PLAN-04) — not deep-dived in this discussion; format and depth (chosen-only vs. chosen+excluded rationale) are left to planning, informed by D-01's requirement that at minimum the "why" for a no-safe-candidate slot must be captured.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Milestone & Blueprint Specs
- `docs/training-programs-physique-gamification-plan-2026-09-10.md` — Architecture blueprint (see program-generation sections for PLAN-01–04 origin).
- `.planning/REQUIREMENTS.md` §3 (PLAN-01–04) — Authoritative requirements for Phase 17.
- `.planning/ROADMAP.md` (Phase 17) — Milestone phase goal and success criteria.
- `.planning/PROJECT.md` — "No Silently Relaxed Filters" and "Single Source of Truth" guiding principles, directly load-bearing for D-01–D-03 and D-08.

### Prior Phase Context
- `.planning/phases/16-exercise-programming-metadata-discipline-taxonomy/16-CONTEXT.md` — Phase 16 decisions on difficulty/commonness/discipline/prerequisite/scaling metadata that Phase 17's hard filters and `ExerciseScalingResolver` consumption depend on.

### Program Generation Domain
- `lib/features/programs/data/smart_program_planner.dart` — Current planner implementation; the relax-then-fill fallback (lines 335-358) and `RotationPolicy`/anchor selection (lines 373-477) are the exact code this phase must change. **Note: this file is 1352 lines, already over the project's 600-line hand-written-file limit — any new logic added here should be split via `part`/`part of` into a subfolder, per `CLAUDE.md` conventions.**
- `lib/features/programs/domain/programming_models.dart` — `ProgramGenerationRequest` (currently defined but unused anywhere outside this file), `SlotRole`, `RotationPolicy`-adjacent enums.
- `lib/features/programs/domain/exercise_programming_eligibility.dart` — Existing hard filtering rules (experience, commonness, style) from Phase 15/16, extends here to cover injury/pain.
- `lib/features/programs/domain/exercise_scaling_resolver.dart` (Phase 16) — Scaling ladder traversal, consulted per D-03 before declaring a slot empty.

### Injury/Pain Data Source
- `lib/features/recovery/data/joint_pain_repository.dart` — `JointPainRepository`, `JointPainStatus` (severity model, `isFlagged`).
- `lib/features/recovery/domain/joint_model.dart` — `JointModel.influencingMuscles`, the joint → weighted muscle map reused per D-05.
- `lib/features/recovery/domain/training_suggestion.dart` — Existing precedent for joint-pain-driven muscle exclusion (`_jointExclusionWeight = 0.5`, lines 65-110) that Phase 17's injury hard filter should mirror.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `JointModel.influencingMuscles`: Joint → weighted muscle map, already validated by Recovery's `TrainingSuggestion` — reuse directly rather than re-deriving.
- `ExerciseScalingResolver` (Phase 16): Progressive regression lookup, to be threaded into the candidate-selection flow before a slot can be declared empty.
- `ExerciseProgrammingEligibility.allows`: Existing hard-filter entry point (experience/commonness/style) — injury/pain should extend this same call site rather than adding a parallel filter path.

### Established Patterns
- Conservative-default philosophy from Phase 16 (uncurated data defaults to the safest/most restrictive tier) extends naturally to "empty slot over unsafe fill."
- `RotationPolicy` already special-cases `SlotRole.main` + advanced + max-effort scoring (`smart_program_planner.dart:392-400`) — the anchor-lock mechanism should hook into this existing main-role branch point rather than introducing a parallel concept.
- In-memory test database (`test/support/test_database.dart`) pattern from Phase 16 applies directly to unit-testing the new hard-filter and anchor-lock logic.

### Integration Points
- `SmartProgramPlanner.populate()` (`smart_program_planner.dart:96`) is the actual generation entry point today, driven by `SmartProgramConfiguration` — NOT the unused `ProgramGenerationRequest`. Planning must decide how these two converge (see Claude's Discretion above).
- `_createStableSlots` (`smart_program_planner.dart:257`) is where the candidate-filtering fallback (D-01/D-02) and anchor selection (`pool.first` at line 476) currently live — this is the primary edit surface.
- Caller of `JointPainRepository.watchCurrentStatuses()` must be identified/added at whatever call site currently builds the generation request, to populate D-07's explicit `excludedMuscles`/`flaggedJoints` field.

</code_context>

<specifics>
## Specific Ideas

- Example empty-slot message: "No safe [pattern] movement available for your equipment/injuries."
- Anchor example: Back Squat selected week 1 stays Back Squat through the whole block unless the user replaces it via the Phase 19 editor, or it becomes injury-excluded.

</specifics>

<deferred>
## Deferred Ideas

- Selection rationale depth (whether to persist "why" for runner-up/excluded candidates, not just the chosen one, and whether this needs any Phase 17 UI vs. staying backend-only for Phase 19's editor to surface) — this gray area was identified but the user chose not to discuss it now. Planner should default to capturing at minimum the no-safe-candidate rationale (D-01) and can treat richer per-candidate rationale persistence as a stretch goal within PLAN-04's scope, not a separate phase.
- Full migration of `SmartProgramConfiguration` call sites to `ProgramGenerationRequest` across the UI layer (block builder view, etc.) is noted as a research question, not decided here — see Claude's Discretion.

None — discussion stayed within phase scope otherwise.

</deferred>

---

*Phase: 17-deterministic-program-planner-hard-guardrails*
*Context gathered: 2026-09-13*
