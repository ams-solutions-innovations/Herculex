# Phase 18: Workout Time Budget, Warmups & Set Method Prescriptions - Context

**Gathered:** 2026-09-15
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 18 introduces a single shared prescription model (`SlotPrescriptionCodec`) so the program preview, the block/program editor's stored data, and the live workout session all resolve from one byte-equivalent representation — today only the workout session reads through `SlotPrescription`/`PrescriptionResolver` at all; preview and editor read raw stored columns or an ad-hoc private JSON blob. It also adds two new pieces of domain logic that don't exist today: a `WorkoutDurationEstimator` that projects realistic session length (and feeds back into generation to hit the user's time budget within ±10%), and a `WarmupResolver` that computes ramp sets from target intensity and movement order (replacing today's fixed, un-scaled ramp tables). Finally it gates the intensity techniques (drop/rest-pause/myo-reps/AMRAP) that already exist unrestricted in the live workout UI, barring them from `SlotRole.main` lifts and requiring an explicit program-level opt-in. It does not touch the program/wave editor's UI itself (Phase 19) or program generation's hard-filter/anchor logic (Phase 17, already shipped).

</domain>

<decisions>
## Implementation Decisions

### Codec Migration Scope (PRES-01)
- **D-01:** `SlotPrescriptionCodec` is a new versioned JSON codec that becomes the canonical DB storage format (a new/replaced column) — not just an in-memory serialization layer. This matches CLAUDE.md's schema-bump checklist: `schemaVersion` bump, drift schema dump/generate, migration test retargeting, and a matching `supabase/migrations/NNNN_*.sql` if the table is synced.
- **D-02:** The program preview is upgraded to render actual set-by-set prescription detail (sets/reps/%1RM/rest) through the new codec, not just session name/time as today. This is the phase's only real end-to-end proof that preview and workout session see byte-identical data.
- **D-03:** The block/program editor (`block_builder_view.dart`) is left untouched in this phase — it keeps generating via `SmartProgramPlanner` exactly as today. Phase 19 wires the real editor UI to the codec when it's built; Phase 18 does not migrate editor storage ahead of that.
- **D-04:** No backward-compatibility reader for the existing ad-hoc `templateSets` JSON blob (`smart_program_planner.dart:1370-1383`) is required. Milestone v2.0 is pre-ship/in-progress, so existing generated programs are not a real-user liability — the stored shape can change outright without a legacy-shape fallback in the codec.

### Duration Estimator Behavior (PRES-02)
- **D-05:** `WorkoutDurationEstimator` is not read-only — its output feeds back into program generation to actively trim volume until the projected duration fits `SmartProgramConfiguration.workoutDurationMinutes` within ±10%. A pure reporter would not guarantee the ±10% success criterion is ever met, only measured.
- **D-06:** The estimate itemizes all of: working sets (sets×reps×rest), warmup sets (from `WarmupResolver`), unilateral work counted at 2x per side, inter-exercise transition time, and rest-pause/myo-reps mini-set bursts — not a flat overhead buffer.
- **D-07:** When trimming is needed to fit the time budget, accessory/isolation slots are cut first (reduced set counts, or dropped entirely if still over budget). `SlotRole.main`/`supplemental` slots — the anchor lifts protected by Phase 17's anchor-lock guarantee — are preserved untouched by time-budget trimming.

### Warmup Scaling Formula (PRES-03)
- **D-08:** Higher target `%1RM` produces more warmup ramp steps (denser progression) — e.g. a near-max target (90%+) gets 4-5 ramp steps, a moderate target (~70%) gets 2-3 — rather than keeping a fixed 3-step count with rescaled percentages.
- **D-09:** Movement order affects warmup: the first main/supplemental lift of a session gets its full computed ramp; subsequent main/supplemental lifts later in the same session get an abbreviated ramp (fewer steps), since general warmth already carries over from earlier heavy work. This also helps the duration estimator (D-06) hit its time budget.
- **D-10:** `WarmupResolver` fully replaces the existing hardcoded ramp tables in `planned_session_resolver.dart` (`_automaticWarmups`, `_maxEffortSets`) — it is the single source of warmup logic going forward, computing steps from intent/`%1RM`/movement order rather than wrapping or parameterizing the old fixed tables.

### Intensity Technique Gating (PRES-04)
- **D-11:** The opt-in for advanced intensity techniques (drop/rest-pause/myo-reps) is a global, program-level toggle — extending the existing `allowTimeSavingSetTechniques` switch on `SmartProgramConfiguration` (already has UI at `block_builder_view.dart:781-790`) rather than adding a separate per-set confirmation flow.
- **D-12:** "Technical compound lift" (the bar target) means `SlotRole.main` specifically — not the broader `SlotRole.isHeavy` (main + supplemental). This reuses the exact role distinction Phase 17 already relies on for anchor-lift guarantees; supplemental/accessory/isolation/conditioning slots remain eligible for drop/rest-pause/myo/AMRAP.
- **D-13:** Enforcement in `set_type_menu.dart` is a hard hide, not a visible-but-blocked state: drop/rest-pause/myo-reps/AMRAP options simply don't appear in the set-type menu for a `SlotRole.main` lift. No error/explanation UI is needed since this is a hard rule, not a warning.

### Claude's Discretion
- Exact `SlotPrescriptionCodec` JSON schema/version field naming, and how `SlotPrescription`/`WorkSegment`'s existing fields (`Intent`, `SetType`, `percentOf1Rm`, `meta` map) map onto the versioned wire format.
- Exact algorithm/thresholds for D-08's ramp-step-count-by-intensity mapping (e.g. specific %1RM breakpoints) and D-09's "abbreviated ramp" definition for later exercises — left to planning/implementation as long as the density-scales-with-intensity and order-reduces-ramp outcomes are met.
- Exact trim algorithm/ordering within accessory/isolation slots when multiple exist (D-07) — e.g. trim set counts uniformly vs. drop lowest-priority slot entirely first.
- Migration path detail for the new DB column (D-01) — column name, whether `SlotPrescription`'s current in-memory type needs restructuring to match the wire format, and how `PrescriptionResolver` changes to read the new canonical column instead of resolving ad-hoc.

</decisions>

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Milestone & Blueprint Specs
- `docs/training-programs-physique-gamification-plan-2026-09-10.md` — Architecture blueprint (Objective 4: Prescription Fidelity & Time Budgeting, origin of PRES-01–04).
- `.planning/REQUIREMENTS.md` (PRES-01–04) — Authoritative requirements for Phase 18.
- `.planning/ROADMAP.md` (Phase 18) — Milestone phase goal and success criteria.
- `.planning/PROJECT.md` — "Single Source of Truth" guiding principle ("The prescription shown in the preview must match the exact prescription executed in the workout session") — directly load-bearing for D-01–D-04.
- `CLAUDE.md` "Schema changes are five chores, not one" — mandatory checklist for D-01's new DB column (schemaVersion bump, drift schema dump/generate, migration test retargeting, matching Supabase migration).

### Prior Phase Context
- `.planning/phases/17-deterministic-program-planner-hard-guardrails/17-CONTEXT.md` — Phase 17's anchor-lift guarantee (D-09–D-12 there) is why D-07 here protects `SlotRole.main`/`supplemental` from time-budget trimming, and D-12 here reuses Phase 17's exact `SlotRole.main` distinction for technique gating.

### Prescription Domain
- `lib/features/programs/domain/slot_prescription.dart` — `SlotPrescription`/`WorkSegment`/`Intent` — the existing plain Dart model PRES-01's codec wraps (no `toJson`/`fromJson` exists yet).
- `lib/features/programs/domain/slot_role.dart` — `SlotRole` enum and `isHeavy` flag; `SlotRole.main` is the exact predicate for D-12's technique bar.
- `lib/features/programs/data/smart_program_planner.dart` — `SmartProgramConfiguration` (`workoutDurationMinutes`, `allowTimeSavingSetTechniques`), the ad-hoc `templateSets` JSON write (lines ~1370-1383) being replaced by the codec, and `_timePlanFor` (lines ~1354-1385) being replaced by the real estimator/warmup logic.
- `lib/features/workouts/data/planned_session_resolver.dart` — `PrescriptionResolver`/`_resolvePrescription`, `_automaticWarmups`/`_maxEffortSets` (the fixed ramp tables `WarmupResolver` replaces per D-10), and `_copiedTemplateSets` (the hand-decoded legacy JSON reader).
- `lib/features/workouts/domain/set_type.dart` — `SetType` enum (`drop`, `restPause`, `myoReps`, `forced`, `cheat`, `negatives`) and `Intent.amrap`/`toFailure` — the techniques D-11–D-13 gate.
- `lib/features/workouts/presentation/.../set_type_menu.dart` — Live workout UI where advanced techniques are currently exposed unrestricted; D-13's hard-hide enforcement point.

### Preview/Editor Surfaces
- `lib/features/programs/presentation/.../program_preview_view.dart`, `week_board.dart`, `day_column_card.dart`, `day_detail_sheet.dart` — Preview surfaces currently showing only session-level info; D-02 upgrades these to render codec-backed set detail.
- `lib/features/programs/presentation/.../block_builder_view.dart` — Editor/generation config UI (duration slider, time-saving-techniques switch at lines ~276-790); left untouched per D-03 beyond wherever the new opt-in toggle (D-11) needs wiring.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `SlotRole.isHeavy`/`SlotRole.main`: Already the exact mask/flag pattern Phase 17 uses for anchor-lift protection and eligibility — D-07 and D-12 both reuse this rather than inventing a new classification.
- `SmartProgramConfiguration.workoutDurationMinutes` / `allowTimeSavingSetTechniques`: Existing config fields and UI (slider + switch in `block_builder_view.dart`) that D-05's feedback loop and D-11's opt-in extend rather than replace.

### Established Patterns
- Phase 17's "no silent relaxation" / explainable-selection philosophy extends naturally to D-07's trim behavior — trimming should have a clear, deterministic priority order (accessory/isolation first), not silent proportional shrinkage.
- Phase 16/17's in-memory test database pattern (`test/support/test_database.dart`) applies directly to unit-testing `WorkoutDurationEstimator` and `WarmupResolver` with fixed inputs.

### Integration Points
- `PrescriptionResolver._resolvePrescription` (`planned_session_resolver.dart`) is the only current consumer of `SlotPrescription` — it becomes the reference implementation the codec's decode path must match exactly for D-02's preview parity.
- `_timePlanFor` (`smart_program_planner.dart`) is the current (single-rule) time/technique logic being fully superseded by `WorkoutDurationEstimator` + `WarmupResolver` + the D-11–D-13 gating.

</code_context>

<specifics>
## Specific Ideas

- Ramp density example: near-max target (90%+ 1RM) → 4-5 warmup steps; moderate target (~70%) → 2-3 steps.
- Movement-order example: first main lift of the session gets the full ramp; a second main/supplemental lift later in the session gets an abbreviated ramp since the lifter is already warm.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 18-workout-time-budget-warmups-set-method-prescriptions*
*Context gathered: 2026-09-15*
