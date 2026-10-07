# Phase 22: Primary Lift Strength Specialization - Context

**Gathered:** 2026-09-30
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 22 completes the Primary Lift Strength Specialization feature that is **already partially built and live in the builder** — a toggle in `block_builder_view`'s Step Parameters lets a user center a program on one lift (squat, deadlift, bench press, overhead press, pull-up) with a sticking-point selection, currently wired end-to-end through `PrimaryLiftSpecialization` → `smart_program_planner.dart`'s slot-need assembly. This phase does not build a new feature from scratch — it closes 3 real gaps against SPEC-01–03's acceptance criteria (verified against the live code, not assumed from the roadmap description):

1. Sticking-point selections only change assistance-exercise choice for squat and deadlift; bench press, overhead press, and pull-up all fall back to one generic `horizontal_pull` slot regardless of sticking point.
2. No timeline-realism warning exists anywhere — `PrimaryLiftSpecialization.recommendedWeeks()` computes a projection but nothing ever compares it against what the user actually selects.
3. Non-target muscle groups are never checked against a maintenance floor — the `VolumeBand`/`VolumeBands` domain model (`lib/features/programs/domain/volume_bands.dart`) is fully built but has zero callers anywhere in the app.

It also extends split support (specialization currently force-resets to Full Body 3x/week/Linear the moment it's toggled on) and removes dead code (the old squat-only `SquatSpecialization`/`SquatStickingPoint` class, superseded by `PrimaryLiftSpecialization` but never deleted — its `squatSpecialization` parameter in `smart_program_planner.dart` is never populated by any caller).

Phase 22 does not touch: the CrossFit/GPP planners (Phase 21, separate code paths gated by `TrainingStyle.isConditioningFirst`), the Herculex AI program-brief path (Phase 27, which explicitly never emits exercise-level detail), or Dream Physique/nutrition (Phase 23).

</domain>

<decisions>
## Implementation Decisions

### Split flexibility
- **D-01:** Specialization supports **Full Body, Upper/Lower, and PPL** splits — not full-body-only. The domain model (`PrimaryLift.appliesToDayLabel`) already half-supports this (matches `lower`/`leg` for squat/deadlift, `upper`/`push`/`pull` for the rest); this phase makes it real by not force-overriding a compatible split choice.
- **D-02:** **No "top-up" appearances.** The anchor lift only appears on days whose label already matches `appliesToDayLabel` — no extra guaranteed touch on non-matching days. Anchor-lift frequency (SPEC-02) is whatever the chosen split naturally gives it (e.g. squat specialization on a 4-day Upper/Lower gets 2x/week via the 2 lower days; full-body gets 3x/week).
- **D-03:** Resolving the "should enabling specialization force a specific split" question: **keep the user's existing split/days if it is already Full Body, Upper/Lower, or PPL; otherwise reset to Full Body/3-day/Linear** (the current default). This preserves today's safe fallback for incompatible splits (CrossFit, GPP-only, bro-split with no day-label match) while honoring D-01's flexibility for the three supported splits.
- User had no lift-specific objection to full-body (asked directly; answered "no preference") — D-01–D-03 apply uniformly across all 5 lifts, no per-lift split exception needed.

### Maintenance volume floor
- **D-04:** Wire the **real `VolumeBands` system** (not a new threshold model) via the existing `ProgramVolumeCalculator.computeFromTemplates` output — reuse over reinvention, and it matches SPEC-02's exact wording ("above baseline maintenance volume").
- **D-05:** **Warning-only, everywhere** — both the live preview and the Create-time check are advisory, matching `VolumeBand`'s existing tone elsewhere in the app (`VolumeVerdict` labels are informational: "Light"/"On target"/"Hard"/"Over", not error language). No blocking path — explicitly confirmed after Claude proposed this resolution and the user locked it in rather than choosing the blocking alternative offered.
- **D-06:** Check runs at **both** Create time (a guardrail-shaped pass, mirroring `ProgramGuardrails.validateConfiguration()`'s pattern) and as a live preview while the user configures specialization (reusing `ProgramVolumeCalculator.computeFromTemplates`, the same calculator `program_preview_view.dart` already uses).
- **D-07:** Scope is **whatever muscles actually appear in the generated plan** (naturally excludes untouched groups like Neck/Forearms since `ProgramVolumeCalculator` only sums muscles present in assigned exercises) — flag any group showing `VolumeVerdict.low`. No separate "affected groups" allowlist needed; this falls out of the existing calculator's behavior.

### Timeline realism warning
- **D-08:** **No new timeline/target-date field** in the specialization modal. `_weeks` is still auto-set to `_liftRecommendedWeeks` on Apply, exactly as today. The warning instead fires off the **existing Weeks picker** (Step Parameters → Block Length sheet, values `[4, 6, 8, 12, 16, 24]`, `dialogs.part.dart:_showLengthPicker`) — if the user opens it while specialization is active and picks a value shorter than `recommendedWeeks()`, that triggers the warning. This was explicitly reconciled with the user after an apparent contradiction in the raw answers (see DISCUSSION-LOG.md) — confirmed correct on the reconciliation question.
- **D-09:** When the chosen weeks is shorter than recommended: **inline warning + auto-adjust back to the recommended (realistic) weeks value.** Not a soft dismiss-and-keep, not a hard block.
- **D-10:** Threshold is **any shortfall at all** — no minimum-gap tolerance. Justified by the picker's own coarse granularity (steps of 2–8 weeks between the 6 discrete options mean there's no trivially-small gap to worry about nagging over).
- **D-11:** Also flag an **unrealistic kg increase outright**, independent of timeline — this needs its **own experience-aware ceiling**, not a reuse of `recommendedWeeks()`'s existing `>15kg`/`>30kg` tiering (which only scales weeks, doesn't itself flag "this increase is unrealistic regardless of how many weeks you give it"). Exact threshold numbers are left to research/planning informed by standard strength-progression norms per experience level.

### Sticking-point exercises
- **D-12:** Every lift (bench press, overhead press, pull-up) must branch its assistance slot need by sticking point, the same way squat and deadlift already do in `smart_program_planner.dart`'s `_needsForPrimaryLift`. **No lift may keep a single generic assistance slot regardless of sticking point** — this is the locked requirement.
- **Claude's discretion (explicitly delegated):** The exact assistance exercise/movement-pattern mapping for each lift × sticking-point combination (e.g. bench "off the chest" vs "lockout", OHP "bottom" vs "lockout", pull-up "dead hang") is left to research/planning, informed by standard strength/powerlifting assistance-exercise conventions. The user was offered the chance to specify exact exercises now and explicitly chose "principle is enough — planning fills in specifics."

### Dead code cleanup
- **Claude's discretion (flagged, not objected to):** `SquatSpecialization`/`SquatStickingPoint` (`lib/features/programs/domain/squat_specialization.dart`) and the unused `squatSpecialization` parameter threading in `smart_program_planner.dart` (lines 48, 99, 494, 1403, 1440–1466) should be deleted as part of this phase — confirmed dead (never populated by any caller; superseded by `PrimaryLiftSpecialization`). User was told this would be folded in during the phase intro and raised no objection.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Milestone & Requirements
- `docs/training-programs-physique-gamification-plan-2026-09-10.md` §"Faza 7 — strength specialization program" (lines ~486–528) — Architecture blueprint origin of SPEC-01–03: questionnaire fields (target lift, current 1RM/rep-test, target weight, target date/available time, experience, sticking point, bracing issue, pain/injury limits, days/duration/equipment, deload readiness), the `StrengthSpecializationGoal`/`LiftAssessment`/`StickingPoint`/`SpecializationRecommendation`/`SpecializationPlanner` types envisioned, and the explicit acceptance criteria (bottom/mid/top squat map to different variations; unrealistic deadline returns a warning + realistic range; anchor lift is never lost to novelty/rotation scoring; no muscle group falls below maintenance; missing equipment and pain are hard filters). Note: the current implementation already generalized beyond squat-only to 5 lifts — treat this doc as directional origin, not a literal spec of today's types.
- `.planning/REQUIREMENTS.md` SPEC-01–03 (lines 59–63) — Authoritative requirements for Phase 22.
- `.planning/ROADMAP.md` (Phase 22, lines 183–189) — Milestone phase goal and success criteria.
- `CLAUDE.md` — "No hand-written file over 600 lines" (relevant: `smart_program_planner.dart` and `block_builder_view/step_parameters_specialization.part.dart` are edit targets), "All time-of-day math goes through Clock" (if any date-based projection is added).

### Existing Specialization Implementation (read before touching)
- `lib/features/programs/domain/primary_lift_specialization.dart` — `PrimaryLift`, `PrimaryLiftStickingPoint`, `PrimaryLiftSpecialization` — the current, live, 5-lift domain model. `recommendedWeeks()` and `assistanceFocus` live here.
- `lib/features/programs/domain/squat_specialization.dart` — the **dead** predecessor (`SquatSpecialization`/`SquatStickingPoint`), confirmed unreachable — see D-13 (dead code cleanup) above.
- `lib/features/programs/presentation/views/block_builder_view/step_parameters_specialization.part.dart` — The specialization modal UI (`_showSpecializationModal`), lift/sticking-point pickers, `_defaultTargetFor`. This is where D-08's timeline logic and D-12's sticking-point-aware UI text would extend.
- `lib/features/programs/presentation/views/block_builder_view/step_parameters.part.dart` (~line 200–260, ~line 330) — The specialization toggle switch and the existing Weeks display/picker trigger (D-08 hooks here).
- `lib/features/programs/presentation/views/block_builder_view/dialogs.part.dart` (`_showLengthPicker`, lines ~207–249) — The existing Block Length picker (`[4, 6, 8, 12, 16, 24]` weeks) that D-08/D-09/D-10's warning must hook into.
- `lib/features/programs/presentation/views/block_builder_view/actions.part.dart` (`_create()`, ~line 65–152) — Where `_primaryLiftSpecialization` is read and passed into `ProgramGenerationRequest`; likely home for the Create-time guardrail check (D-06).
- `lib/features/programs/data/smart_program_planner.dart` — `_needsFor`, `_needsForPrimaryLift` (~line 1401–1622), `ProgramGenerationRequest.primaryLiftSpecialization`/`.squatSpecialization` fields (~line 99–100). The slot-need assembly that D-01–D-03 (split gating) and D-12 (sticking-point branching) both edit.

### Volume & Guardrail Domain
- `lib/features/programs/domain/volume_bands.dart` — `VolumeBand`, `VolumeVerdict`, `VolumeBands.forGroup`/`.verdicts` — the currently-unwired system D-04 wires in. `VolumeBands.priors` has the 19 canonical muscle groups and their (minimum, adaptive, maximum) weekly-set bands.
- `lib/features/programs/domain/program_muscle_volume.dart` — `ProgramVolumeCalculator.computeFromTemplates` — the existing weekly-sets-per-muscle calculator (already used by `program_preview_view.dart`) that D-04/D-06 reuse as `VolumeBands.verdicts()`'s input.
- `lib/features/programs/presentation/widgets/program_muscle_volume_card.dart` and `lib/features/programs/presentation/views/program_preview_view.dart` — Existing UI precedent for displaying a volume breakdown; the live-preview half of D-06 likely extends or reuses this pattern.
- `lib/features/programs/domain/program_guardrails.dart` — `ProgramGuardrailIssue`, `GuardrailSeverity`, `ProgramGuardrails.validateConfiguration()` — the existing pure-function-returning-issues pattern (warning/blocking severity) that D-06's Create-time check and D-11's increase-realism check should structurally match, even though D-05 locks the specialization-specific checks to warning-only.

### Prior Phase Context
- `.planning/phases/21-crossfit-gpp-training-tracks/21-CONTEXT.md` — Establishes the repo convention (from the milestone blueprint) that "CrossFit/specialization/gamification must not be added as extra `if` statements in the existing builder" — own domain model and tested policy per feature. Relevant precedent for how D-12's sticking-point branching and D-04's volume check should be structured (planning's call, not re-litigated here).
- `.planning/phases/27-herculex-ai-program-generation/27-CONTEXT.md` and `.planning/phases/26-herculex-ai-knowledge-base-brand-unification/26-CONTEXT.md` — No direct overlap with this phase's domain; skimmed for conflicts, none found.

### 1RM / Strength Tracking (considered, not adopted this phase)
- `lib/features/workouts/domain/one_rep_max.dart` — `OneRepMax.estimate` (Epley/Brzycki average). `lib/features/analytics/data/analytics_repository.dart` (~line 90–124) — existing top-N estimated-1RM query. These were surfaced during codebase scouting as a possible auto-fill source for the specialization modal's "current load" field (today it's 100% manual entry with a static per-lift default guess), but this was **not raised as a discussion area** and is **not decided** — flag for research/planning to assess whether it's in-scope opportunistic reuse or explicitly deferred.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `PrimaryLiftSpecialization`/`PrimaryLift`/`PrimaryLiftStickingPoint` (`primary_lift_specialization.dart`): the live, working 5-lift domain model — this phase extends it, does not replace it.
- `ProgramVolumeCalculator.computeFromTemplates` (`program_muscle_volume.dart`): already computes weekly-sets-per-muscle from a builder-time template selection — exactly the input `VolumeBands.verdicts()` needs (D-04).
- `VolumeBands` (`volume_bands.dart`): fully built min/adaptive/max band model with population priors for 19 muscle groups — currently zero callers anywhere in the app; this phase is its first real consumer.
- `ProgramGuardrails` (`program_guardrails.dart`): established pure-function `List<ProgramGuardrailIssue>` pattern with `GuardrailSeverity` — structural precedent for any new Create-time check, even though this phase's checks are warning-only per D-05.
- Existing Weeks picker (`dialogs.part.dart:_showLengthPicker`): the hook point for D-08/D-09/D-10's timeline warning — no new UI surface needed for weeks selection itself.

### Established Patterns
- `StreamProvider` over `FutureProvider` for drift reads (CLAUDE.md house rule) — applies if any new repository/provider is added (none identified as strictly necessary yet; specialization logic today is pure-Dart domain + in-memory builder state).
- `ProgramGuardrailIssue`'s severity-tagged, pure-function-returning-issues shape is the established idiom for "check a configuration, surface problems" in this codebase — informs D-06's and D-11's implementation shape even though severity stays `warning` per D-05.

### Integration Points
- Split gating (D-01–D-03) integrates in `smart_program_planner.dart`'s `_needsFor`/day-label matching and wherever `block_builder_view` currently force-resets `_split`/`_daysPerWeek`/`_model` on specialization Apply (`step_parameters_specialization.part.dart:214-216`).
- Volume floor (D-04–D-07) integrates between `ProgramVolumeCalculator` (already computes the numbers) and `VolumeBands.verdicts()` (already computes the verdict) — the missing piece is purely the call site(s): one at Create time, one as a live preview.
- Timeline warning (D-08–D-11) integrates at the Weeks picker's `onSelected` callback (`dialogs.part.dart:244`) and/or at Create time in `actions.part.dart`, comparing against `PrimaryLiftSpecialization.recommendedWeeks()`.
- Sticking-point branching (D-12) integrates in `smart_program_planner.dart`'s `_needsForPrimaryLift` (~line 1575–1604), extending the existing `switch (lift)` pattern that already branches correctly for squat and deadlift.

</code_context>

<specifics>
## Specific Ideas

- The reconciliation moment in the Timeline realism area is worth downstream agents reading directly in DISCUSSION-LOG.md: the user's answers to "add a new timeline field?" (no) and "warn when the chosen timeline is shorter than recommended?" (yes, with auto-adjust) only cohere together because the warning reuses the *existing* Weeks picker rather than adding a new field — this was explicitly confirmed, not assumed.
- User had no per-lift objection to full-body specialization (asked directly whether pull-up or upper-body lifts specifically felt wrong under full-body-only) — answered "no preference," which is why D-01–D-03 apply uniformly rather than carving out an exception.

</specifics>

<deferred>
## Deferred Ideas

None raised as scope creep during discussion — all four areas stayed within the phase boundary. The 1RM-autofill idea (see canonical_refs, "1RM / Strength Tracking") is noted as **surfaced but not decided**, not deferred to a future phase — it's a candidate for this phase's own scope, left for research/planning to assess, not pushed out.

</deferred>

---

*Phase: 22-primary-lift-strength-specialization*
*Context gathered: 2026-09-30*
