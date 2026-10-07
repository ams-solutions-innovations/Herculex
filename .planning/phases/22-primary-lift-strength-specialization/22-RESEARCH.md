# Phase 22: Primary Lift Strength Specialization - Research

**Researched:** 2026-09-30
**Domain:** Flutter/drift deterministic program-generation extension (no new libraries, no external services) — closing 3 functional gaps in an already-live feature plus split-flexibility and dead-code cleanup.
**Confidence:** HIGH (all findings verified by direct code read against the current working tree; the only MEDIUM/LOW items are the two numeric/design judgment calls explicitly delegated to research by CONTEXT.md — D-11's kg ceiling and D-12's exact assistance mapping).

## Summary

Phase 22 touches no new dependency, no new architectural layer, and no new file class this
codebase doesn't already have an established shape for. Every one of CONTEXT.md's canonical refs
was re-read against the current working tree and all line-number citations were confirmed accurate
(with one exception noted below: `_create()` now lives at `actions.part.dart:50-191`, not
`~65-152` — a ~15-line/~40-line drift from the file having grown since context-gathering, not a
wrong pointer). This is a pure-Dart-domain-plus-Flutter-UI extension: three deterministic switches
need more branches (`_needsForPrimaryLift`), one already-built-and-tested domain model needs its
first two call sites (`VolumeBands`), one picker needs a comparison-and-warning hook
(`_showLengthPicker`), and one dead class needs deleting.

The two genuinely open design questions — D-11's numeric kg ceiling and D-12's exact
assistance-exercise mapping — are both fully delegated to this research phase by CONTEXT.md, and
both are answered below with a concrete, code-taxonomy-consistent recommendation, but are tagged
`[ASSUMED]` and listed in the Assumptions Log because they encode judgment calls (strength-progression
norms, assistance-exercise convention) that reasonable domain experts could set differently. The
planner should treat these as strong defaults, not immovable facts.

One real integration risk was found and is not mentioned anywhere in CONTEXT.md:
**`ProgramVolumeCalculator.computeFromTemplates`'s muscle-group vocabulary (14 groups, taken
verbatim from `exerciseCatalog.primaryMuscle`) does not fully align with `VolumeBands.priors`'s
19-group vocabulary** — `ProgramVolumeCalculator` emits `"Shoulders"` where `VolumeBands` expects
separate `"Front Delts"`/`"Side Delts"`/`"Rear Delts"` bands, and never emits `"Lats"`/`"Traps"`/
`"Obliques"` at all (those three `VolumeBands.priors` entries are consequently unreachable through
this call path). This does not break D-04's wiring — `VolumeBands.forGroup` has a generic
`_fallback = (6, 14, 20)` band for any unmapped key, so `"Shoulders"` will just get a coarser,
less-precise band than a hypothetical delt-specific one would — but the planner should know this
going in rather than discover it as a surprising test result.

A second small but real UI gap: the existing specialization summary card
(`step_parameters.part.dart:274`) hardcodes `'$_liftRecommendedWeeks weeks · 3 exposures / week'`
— a leftover from the current full-body-only force-reset. Once D-01–D-03 land, exposures per week
vary by chosen split (Upper/Lower gives 2x for squat/deadlift, PPL gives 1x for push/pull/legs-day
lifts), so this hardcoded `3` becomes wrong for any non-full-body split and needs to be computed
from `_plan`/`_split` instead.

**Primary recommendation:** Treat this as five small, independently testable edits to five
existing files (`smart_program_planner.dart`, `primary_lift_specialization.dart` or a small new
domain file for D-11's ceiling, `step_parameters_specialization.part.dart`/`step_parameters.part.dart`,
`dialogs.part.dart`, `actions.part.dart`) plus one dead-code deletion
(`squat_specialization.dart` + its 5 call sites) plus one new lightweight volume-preview widget —
no new architectural pattern, no new state-management primitive, no new package.

## User Constraints (from CONTEXT.md)

### Locked Decisions

**Split flexibility**
- D-01: Specialization supports Full Body, Upper/Lower, and PPL splits — not full-body-only.
- D-02: No "top-up" appearances. The anchor lift only appears on days whose label already matches
  `appliesToDayLabel` — no extra guaranteed touch on non-matching days.
- D-03: Keep the user's existing split/days if it is already Full Body, Upper/Lower, or PPL;
  otherwise reset to Full Body/3-day/Linear (the current default).
- No per-lift split exception — D-01–D-03 apply uniformly across all 5 lifts.

**Maintenance volume floor**
- D-04: Wire the real `VolumeBands` system (not a new threshold model) via the existing
  `ProgramVolumeCalculator.computeFromTemplates` output.
- D-05: Warning-only, everywhere — both the live preview and the Create-time check are advisory.
  No blocking path.
- D-06: Check runs at both Create time (guardrail-shaped pass, mirroring
  `ProgramGuardrails.validateConfiguration()`) and as a live preview while configuring specialization.
- D-07: Scope is whatever muscles actually appear in the generated plan (naturally excludes
  untouched groups) — flag any group showing `VolumeVerdict.low`.

**Timeline realism warning**
- D-08: No new timeline/target-date field. The warning fires off the existing Weeks picker
  (`dialogs.part.dart:_showLengthPicker`, values `[4, 6, 8, 12, 16, 24]`) — if the user picks a
  value shorter than `recommendedWeeks()` while specialization is active, that triggers the warning.
- D-09: Inline warning + auto-adjust back to the recommended (realistic) weeks value.
- D-10: Threshold is any shortfall at all — no minimum-gap tolerance.
- D-11: Also flag an unrealistic kg increase outright, independent of timeline — needs its own
  experience-aware ceiling (not a reuse of `recommendedWeeks()`'s `>15kg`/`>30kg` tiering). Exact
  threshold numbers left to research/planning.

**Sticking-point exercises**
- D-12: Every lift (bench press, overhead press, pull-up) must branch its assistance slot need by
  sticking point, the same way squat and deadlift already do. No lift may keep a single generic
  assistance slot regardless of sticking point. Exact exercise/movement-pattern mapping per
  lift × sticking-point combination left to research/planning.

**Dead code cleanup**
- `SquatSpecialization`/`SquatStickingPoint` (`lib/features/programs/domain/squat_specialization.dart`)
  and the unused `squatSpecialization` parameter threading in `smart_program_planner.dart`
  (confirmed-live lines: 48, 99, 494, 1403, 1440–1466 — see Code Context below) should be deleted.
  **Also delete `test/squat_specialization_test.dart`** (27 lines, exercises only the dead class) —
  not mentioned in CONTEXT.md but discovered during this research; leaving it would keep asserting
  behavior of code the phase is told to delete.

### Claude's Discretion

- Exact `_SlotNeed` mapping for bench/OHP/pull-up × sticking-point (D-12) — see Sticking-Point
  Assistance Mapping below.
- D-11's exact numeric kg-increase ceiling per experience level — see Timeline & Increase Realism
  below.
- Whether to auto-fill "current load" from the app's existing estimated-1RM analytics — assessed
  below (Open Questions) as **out of scope for this phase**, not silently adopted.
- Which `SplitType` values count as "Full Body / Upper/Lower / PPL" for D-01/D-03's compatibility
  check — see Architecture Patterns → Split Compatibility below (this needed code-level
  disambiguation CONTEXT.md's decision didn't spell out).

### Deferred Ideas (OUT OF SCOPE)

None. All four discussed areas stayed within phase boundary. The 1RM-autofill idea is **not
deferred to a future phase** — it was surfaced but never decided, and this research recommends
treating it as this phase's own explicit non-goal (see Open Questions), which the planner should
confirm rather than silently either building or dropping.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SPEC-01 | Strength specialization targets user-selected lift with current 1RM, target weight, and sticking point analysis (bottom, mid, lockout) | Already live for all 5 lifts (`PrimaryLiftSpecialization`); D-12 closes the remaining gap (sticking-point choice not yet affecting exercise selection for 3 of 5 lifts) — see Sticking-Point Assistance Mapping |
| SPEC-02 | Specialization planner preserves anchor lift frequency while maintaining all non-target muscle groups above baseline maintenance volume | Anchor-frequency preservation already satisfied by D-01/D-02's split-flexibility + no-top-up design (natural split-driven frequency); volume-floor half closed by D-04–D-07 — see Volume Floor Wiring |
| SPEC-03 | Unrealistic target timelines generate realistic projected time horizons with warnings rather than aggressive programming | Closed by D-08–D-11 — see Timeline & Increase Realism |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

- **No hand-written file over 600 lines.** `smart_program_planner.dart` is already 2028 lines but
  is `part`-split (3 part files) — it is exempt from the raw-line-count concern by virtue of already
  being split; new lines added to `_needsForPrimaryLift` (D-12) or `_needsFor` (D-01–D-03) stay well
  within the existing part-file structure and don't require a new split. `step_parameters.part.dart`
  (402 lines) and `step_parameters_specialization.part.dart` (258 lines) both have headroom.
  `actions.part.dart` (325 lines) has headroom for the Create-time volume-floor + kg-ceiling check.
  If a new standalone volume-preview widget is added, keep it under 600 lines from the start (the
  reference precedents — `ai_brief_rejection_banner.dart` 77 lines, `ai_day_rationale_card.dart` 63
  lines — suggest a new warning/preview widget this size is not a concern).
- **Imports are always `package:herculex/...`, never relative.** Applies to any new file this phase
  adds (a possible new `strength_progression_norms.dart` or similar for D-11, and a possible new
  volume-preview widget for D-06's live-preview half).
- **All time-of-day math goes through `Clock`.** Not applicable — D-08–D-11's timeline warning
  compares `weeks` (an integer count, not a wall-clock date) against `recommendedWeeks()`'s output;
  no `DateTime.now()` is introduced by this phase.
- **Prefer `StreamProvider` over `FutureProvider` for drift reads.** Not applicable in the way it
  usually is — every new check this phase adds (volume floor, timeline, kg ceiling) operates on
  in-memory builder state (`_split`, `_daysPerWeek`, `_weeks`, `_primaryLiftSpecialization`) or on
  `ProgramVolumeCalculator.computeFromTemplates`'s one-shot `Future<ProgramVolumeBreakdown>` (already
  the exact pattern `program_preview_view.dart` uses today — a `Future`, not a `Stream`, because it's
  a point-in-time computation over not-yet-persisted builder state, not a live drift table read).
  No new repository or provider is required by this phase.
- **`@DataClassName` mandatory on new tables.** Not applicable — this phase adds no new drift table.
- **`flutter analyze` / `flutter test` / `dart run tool/check_structure.dart`** — standard gates,
  unchanged by this phase.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Sticking-point → assistance exercise selection (D-12) | Data (`smart_program_planner.dart`, pure Dart) | Domain (`primary_lift_specialization.dart` supplies the sticking-point enum + copy) | Slot-need assembly is the planner's job; it already owns this exact responsibility for squat/deadlift — no new tier needed, just more branches in an existing switch |
| Split-compatibility gating (D-01–D-03) | Presentation (`step_parameters_specialization.part.dart`'s Apply handler decides keep-vs-reset) | Domain (`PrimaryLift.appliesToDayLabel`, already built) | The domain model already expresses "does this lift show up on this day label"; only the UI-level decision of *which split to force* on Apply is new |
| Volume-floor computation (D-04) | Domain (`VolumeBands.verdicts`) | Domain (`ProgramVolumeCalculator.computeFromTemplates`) | Both are pure-Dart, already built, already tested in isolation — this phase's job is exclusively wiring, not computation |
| Volume-floor Create-time check (D-06) | Presentation (`actions.part.dart:_create()`) | Domain (`ProgramGuardrailIssue`-shaped pure function, new) | Mirrors `ProgramGuardrails.validateConfiguration()`'s existing shape — a new pure function belongs in `program_guardrails.dart` or a small sibling, called from `_create()` |
| Volume-floor live preview (D-06) | Presentation (new widget near/in specialization modal or Step Parameters) | Domain (same `VolumeBands`/`ProgramVolumeCalculator` pair) | Read-only rendering of an already-computed breakdown; no new state ownership |
| Timeline/kg-increase warning (D-08–D-11) | Presentation (`dialogs.part.dart:_showLengthPicker`'s `onSelected`, and/or `step_parameters_specialization.part.dart`'s Apply handler for the kg check) | Domain (`PrimaryLiftSpecialization.recommendedWeeks()` existing; new kg-ceiling function) | The comparison itself is pure Dart and could be either inline or a tiny new domain function; the warning *display* is unavoidably presentation-tier |
| Dead code removal | Data (`smart_program_planner.dart`) + Domain (`squat_specialization.dart`, deleted) | — | Pure subtraction, no tier ambiguity |

## Standard Stack

No new library, package, or external service is introduced by this phase. Every capability is
built from primitives already present in the codebase:

### Core (existing, reused)

| Component | Location | Purpose | Why reused, not rebuilt |
|-----------|----------|---------|--------------------------|
| `PrimaryLiftSpecialization`/`PrimaryLift`/`PrimaryLiftStickingPoint` | `lib/features/programs/domain/primary_lift_specialization.dart` | Live 5-lift domain model, `recommendedWeeks()`, `assistanceFocus` copy | Already the single source of truth for SPEC-01; extending, not replacing |
| `VolumeBands`/`VolumeVerdict`/`VolumeBand` | `lib/features/programs/domain/volume_bands.dart` | Min/adaptive/max weekly-set bands, 19 population priors, `verdicts()` batch helper | Fully built and independently unit-tested (`test/features/programs/volume_bands_test.dart`) with zero production callers — this phase is its first real consumer, per D-04 |
| `ProgramVolumeCalculator.computeFromTemplates` | `lib/features/programs/domain/program_muscle_volume.dart` | Weekly-sets-per-muscle-group from a builder-time template selection | Already used by `program_preview_view.dart`; exact same call shape needed for D-04's input |
| `ProgramGuardrails`/`ProgramGuardrailIssue`/`GuardrailSeverity` | `lib/features/programs/domain/program_guardrails.dart` | Pure-function `List<Issue>` pattern, `warning`/`blocking` severity | Structural precedent for D-06's Create-time check (stays `warning` per D-05, never `blocking`) |
| `SmartProgramConfiguration._needsFor`/`_needsForPrimaryLift` | `lib/features/programs/data/smart_program_planner.dart` | Slot-need assembly per training day | D-01–D-03 and D-12 both edit this exact method family |
| `HxSheet`/`_sheetOptionCard`/`AlertDialog` | `lib/design_system/components/`, `block_builder_view/shared_helpers.part.dart` | Existing bottom-sheet/dialog/option-card shells | No new UI primitive needed anywhere in this phase |
| `AiBriefRejectionBanner` | `lib/features/programs/presentation/widgets/ai_brief_rejection_banner.dart` | `hx.warning`-toned banner (heading/body/footer), `Icons.warning_amber_rounded` | UI-SPEC's explicit reuse target for all 3 new warning surfaces (timeline, kg-increase, volume-floor) |

No `Installation:` section is needed — nothing new is installed.

## Package Legitimacy Audit

Not applicable. This phase installs zero external packages (no new `pubspec.yaml` dependency of
any kind — pure Dart/Flutter code reorganization and extension of existing domain logic). The
Package Legitimacy Gate protocol is skipped per its own scope condition ("whenever this phase
installs external packages").

## Architecture Patterns

### System Architecture Diagram

```
 Step Parameters (block_builder_view)
 ─────────────────────────────────────
 [Specialization toggle ON]
        │
        ▼
 _showSpecializationModal()                    (step_parameters_specialization.part.dart)
   lift picker ── sticking-point picker ── current/target kg
        │
        ▼ Apply
 Split-compatibility check (D-01–D-03, NEW)
   _split ∈ {FullBody*, UpperLower, PPL}? ──yes──▶ keep _split/_daysPerWeek/_model
        │no
        ▼
   reset to FullBody/3-day/Linear (existing fallback, unchanged)
        │
        ▼
 [Weeks auto-set to recommendedWeeks()]  (existing, unchanged)
        │
        ├──▶ User later reopens Weeks picker ──▶ _showLengthPicker()  (dialogs.part.dart)
        │         picks weeks < recommendedWeeks()?
        │              │yes (D-08–D-10, NEW)
        │              ▼
        │         inline warning banner + auto-adjust _weeks = recommendedWeeks()
        │
        ├──▶ kg-increase ceiling check (D-11, NEW, experience-aware)
        │         (targetKg − currentKg) > ceiling(experience)?
        │              │yes
        │              ▼
        │         inline warning banner (advisory only, D-05)
        │
        └──▶ Live volume-floor preview (D-04/D-06/D-07, NEW)
                  ProgramVolumeCalculator.computeFromTemplates(...)
                       │
                       ▼
                  VolumeBands.verdicts(weeklySetsByGroup)
                       │
                       ▼
                  any VolumeVerdict.low? ──▶ render "Light" flag(s), advisory only

 ── Create button ──▶ actions.part.dart:_create()
        │
        ├──▶ ProgramGuardrails.validateConfiguration(...)          (existing, unchanged)
        ├──▶ Volume-floor Create-time check (D-06, NEW)            — warning only, never blocks
        ├──▶ kg-increase ceiling Create-time check (D-11, NEW)     — warning only, never blocks
        │
        ▼
 SmartProgramPlanner.populate()
        │
        ▼
 _needsFor(dayLabel, primaryLiftSpecialization, ...)
        │  day label matches PrimaryLift.appliesToDayLabel?
        │       │yes
        ▼
 _needsForPrimaryLift(specialization)          (smart_program_planner.dart:1565–1622)
        │
        ▼
 switch (lift) { squat, deadlift ALREADY branch by sticking point;
                  benchPress/overheadPress/pullUp NOW branch too (D-12, NEW) }
        │
        ▼
 [main slot, assistance slot, accessory×2, isolation slot]  ──▶  candidate resolution ──▶ materialized program
```

### Recommended Project Structure

No new folder. All edits land in existing files; at most one new file:

```
lib/features/programs/
├── domain/
│   ├── primary_lift_specialization.dart      # EDIT: optionally add kg-ceiling helper here (D-11)
│   ├── volume_bands.dart                     # UNCHANGED — already built
│   ├── program_guardrails.dart               # EDIT: optionally add volume-floor + kg-ceiling
│   │                                         #        pure-function check(s) here (D-06/D-11),
│   │                                         #        mirroring validateConfiguration()'s shape
│   └── squat_specialization.dart             # DELETE (dead code cleanup)
├── data/
│   └── smart_program_planner.dart            # EDIT: _needsFor (D-01–D-03), _needsForPrimaryLift (D-12),
│                                             #        delete squatSpecialization threading
├── presentation/
│   ├── views/block_builder_view/
│   │   ├── step_parameters_specialization.part.dart  # EDIT: split-compat Apply logic (D-01–D-03)
│   │   ├── step_parameters.part.dart                 # EDIT: fix hardcoded "3 exposures/week" text,
│   │   │                                             #        optionally embed live volume preview
│   │   ├── dialogs.part.dart                         # EDIT: _showLengthPicker's onSelected (D-08–D-10)
│   │   └── actions.part.dart                         # EDIT: _create() Create-time checks (D-06, D-11)
│   └── widgets/
│       ├── ai_brief_rejection_banner.dart            # REUSED, not edited
│       └── [possible new] specialization_volume_floor_card.dart  # NEW (if planner chooses a
│                                                       #  sibling over extending ProgramMuscleVolumeCard)
└── [test/squat_specialization_test.dart]              # DELETE (dead code cleanup)
```

### Pattern 1: Slot-need branching by sticking point (existing precedent, D-12 extends it)

**What:** A `switch (lift) { ... }` inside `_needsForPrimaryLift` where each `PrimaryLift` case
further switches on `specialization.stickingPoint` to pick a distinct assistance `_SlotNeed`.
**When to use:** Any time a lift-specific training variable needs to change which exercise pattern/
muscle the planner targets for a supplemental slot.
**Example (existing squat branch, the template to mirror):**
```dart
// Source: lib/features/programs/data/smart_program_planner.dart:1575-1588 (read 2026-09-30)
PrimaryLift.squat => switch (specialization.stickingPoint) {
  PrimaryLiftStickingPoint.bottom => const _SlotNeed(
    'squat', 'quad', SlotRole.supplemental,
  ),
  PrimaryLiftStickingPoint.lockout => const _SlotNeed(
    'hinge', 'glute', SlotRole.supplemental,
  ),
  _ => const _SlotNeed('lunge', 'quad', SlotRole.supplemental),
},
```

### Pattern 2: Pure-function guardrail check returning `List<ProgramGuardrailIssue>`

**What:** A static method taking plain data (not live drift reads) and returning a list of typed
issues with a `GuardrailSeverity`.
**When to use:** D-06's Create-time volume-floor check and D-11's Create-time kg-ceiling check —
both should return `warning`-severity issues (never `blocking`, per D-05), structurally identical
to `ProgramGuardrails.validateConfiguration()`.
**Example (existing shape to mirror):**
```dart
// Source: lib/features/programs/domain/program_guardrails.dart:159-192 (read 2026-09-30)
static List<ProgramGuardrailIssue> validateConfiguration({
  required ProgramBuildMode buildMode,
  required PeriodizationModel model,
  required SplitType split,
  required Map<String, SlotTrainingMethod> mainMethodByDayLabel,
}) {
  final issues = <ProgramGuardrailIssue>[];
  // ...checks append warning/blocking issues...
  return issues;
}
```

### Pattern 3: One-shot `Future` volume computation (not a `StreamProvider`)

**What:** `ProgramVolumeCalculator.computeFromTemplates(...)` is called directly, awaited, and its
`ProgramVolumeBreakdown` rendered — no drift table backs it (it operates on in-memory
`_templatesBySlot`/`_plan`/`_weeks`/`_model`, none of which are persisted yet during building).
**When to use:** D-06's live preview. This is a deliberate, already-established exception to the
"prefer `StreamProvider`" house rule, because there is no live drift row to stream from at builder
time — `program_preview_view.dart` already does exactly this with a plain `Future`/`FutureBuilder`
or awaited call in `initState`/a rebuild-triggered call.
**Example:**
```dart
// Source: lib/features/programs/domain/program_muscle_volume.dart:468-474 (signature, read 2026-09-30)
static Future<ProgramVolumeBreakdown> computeFromTemplates({
  required AppDatabase db,
  required Map<int, int?> templatesBySlot,
  required SplitPlan plan,
  required int weeks,
  required PeriodizationModel model,
});
```

### Split Compatibility (resolving D-01/D-03's ambiguity)

CONTEXT.md names "Full Body, Upper/Lower, and PPL" as the three supported splits but does not map
this onto the actual `SplitType` enum, which has 11 values. Cross-referencing
`PrimaryLift.appliesToDayLabel`'s substring matching (`'full'`, `'lower'`/`'leg'`, `'upper'`/`'push'`/
`'pull'`) against every `SplitType`'s `.slots` labels gives an unambiguous, code-verifiable answer:

| `SplitType` | `.slots` | Compatible? | Why |
|---|---|---|---|
| `fullBody` | Full Body A/B/C | ✅ | All 3 labels contain `'full'` |
| `fullBodyLinear` | Full Body | ✅ | Contains `'full'` |
| `fullBodyAb` | Full Body A/B | ✅ | Contains `'full'` |
| `fullBodyAbGpp` | Full Body A/B, GPP | ⚠️ borderline | Full Body days match; GPP day never gets the anchor lift (fine, D-02) — but this `SplitType` is driven by `TrainingStyle.fullBody2xGpp`, a training-style toggle this phase explicitly does not touch (CONTEXT.md: "does not touch... the CrossFit/GPP planners"). **Recommendation: exclude from the compatibility set** — treat as incompatible (reset), since its real owner is a different training style/phase, not because the day-label matching itself would fail. |
| `upperLower` | Upper, Lower | ✅ | Matches `'upper'`/`'lower'` directly |
| `upperLowerFullBody` | Upper, Lower, Full Body | ⚠️ borderline | Every one of its 3 day labels independently matches `appliesToDayLabel` for every lift. Not named by CONTEXT.md's "Full Body, Upper/Lower, PPL" list, but structurally it's a superset-safe combination of the two. **Recommendation: include in the compatibility set** — there is no code reason to exclude it, and the user's "no preference" answer on per-split exceptions supports inclusion over exclusion. Flag as a planning decision to confirm with the user if the planner wants to be conservative instead. |
| `ppl` | Push, Pull, Legs | ✅ | `'push'`/`'pull'` match bench/OHP/pull-up; `'legs'.contains('leg')` matches squat/deadlift |
| `crossfit`, `ab`, `abc`, `broSplit`, `custom` | — | ❌ | None of their day labels contain any of `appliesToDayLabel`'s matched substrings (`ab`/`abc`/`custom`'s labels are `'A'`/`'B'`/`'C'`/generic numbered — none match; `broSplit`'s labels are muscle-group names, not day-role names) |

**Recommendation for the planner:** define the compatibility set explicitly as
`{SplitType.fullBody, fullBodyLinear, fullBodyAb, upperLower, ppl}` at minimum (unambiguously
matches CONTEXT.md's 3 named splits), and treat `upperLowerFullBody` and `fullBodyAbGpp` as the two
judgment calls above — both are tagged `[ASSUMED]` in this research (see Assumptions Log) since
CONTEXT.md's own three-split list doesn't disambiguate them.

### Anti-Patterns to Avoid

- **Don't build a new muscle-group taxonomy for the volume-floor check.** `VolumeBands.priors`
  already has 19 groups; `ProgramVolumeCalculator` already normalizes exercise data down to a
  (smaller) group vocabulary. Feed one into the other as-is (accepting the coverage gap documented
  above) rather than inventing a translation layer or a third vocabulary — D-04 explicitly says
  "reuse over reinvention."
- **Don't add a new `GuardrailSeverity` value or a parallel "advisory" issue type.** D-05 locks
  every new check in this phase to the existing `warning` severity. Reuse `GuardrailSeverity.warning`
  verbatim; do not introduce e.g. `GuardrailSeverity.advisory` as a distinct concept.
- **Don't extend `_ProgramMuscleVolumeCardState._buildMuscleRow` in place for the live-preview
  surface.** It's a private method on a private `State` class in an existing, already-shipped,
  standalone widget (`program_muscle_volume_card.dart`) used elsewhere in the app
  (`program_preview_view.dart`) with `FontWeight.w600` row labels. UI-SPEC's typography contract
  requires the **new** embedded instance to render at regular weight instead — modifying the
  existing private widget in place risks an unintended visual regression on its other call site.
  Build a new, small, `context.hx`-native widget that reads `MuscleVolumeEntry`/`VolumeVerdict` and
  renders its own row (see Component Inventory below), rather than threading a new optional
  parameter through the existing private class.
- **Don't replicate the `'rear'` muscle-substring bug.** `_SlotNeed(null, 'rear', SlotRole.isolation)`
  already exists at lines 1498/1532 for bench/OHP/pull-up's shared isolation fallback, but `'rear'`
  is never a substring of any of the 14 real `exerciseCatalog.primaryMuscle` values (`Abductors`,
  `Abs`, `Adductors`, `Back`, `Biceps`, `Calves`, `Chest`, `Forearms`, `Glutes`, `Hamstrings`, `Neck`,
  `Quads`, `Shoulders`, `Triceps` — confirmed via `grep -o '"primaryMuscle"...' assets/data/exercises.json`).
  This means that isolation slot has always silently fallen through to the "relax pattern/muscle"
  candidate pool (`smart_program_planner.dart:590+`) rather than actually targeting rear delts. This
  is a **pre-existing bug, out of this phase's stated scope to fix**, but any new D-12 `_SlotNeed`
  this phase adds must use a muscle string that is a verified substring of one of the 14 real
  catalog values (see Sticking-Point Assistance Mapping below — every proposed value was checked
  against this list).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|--------------|-----|
| Weekly-set-per-muscle computation | A new aggregator over `_templatesBySlot`/`_plan` | `ProgramVolumeCalculator.computeFromTemplates` | Already built, already used by `program_preview_view.dart`, already handles periodization-aware weekly breakdown |
| Muscle-group min/adaptive/max thresholds | New hardcoded set-count constants | `VolumeBands.priors` + `VolumeBands.forGroup`/`.verdicts` | Already built, already unit-tested, already population-prior-grounded with a personalization path (`VolumeTolerance`) the phase doesn't need to use but shouldn't duplicate the shape of |
| Configuration-issue collection/severity model | A new "advisory issue" class | `ProgramGuardrailIssue`/`GuardrailSeverity` | Exists, already the house idiom for "check config, return typed issues" |
| Warning-banner visual shape | A new banner widget from scratch | `AiBriefRejectionBanner` (reuse directly, or copy its exact `Container`/`Row`/`Icon`/`hx.warning` shape into a 2-field sibling if the 3-field heading/body/footer shape doesn't fit) | UI-SPEC explicitly names this as the reuse target for all 3 new warning surfaces |

**Key insight:** every domain computation this phase needs already exists, tested, and unused.
The actual work is almost entirely wiring and UI — the risk profile is "forgot a call site" or
"UI text drifted from the underlying data," not "built the wrong algorithm."

## Common Pitfalls

### Pitfall 1: Muscle-group vocabulary mismatch between `ProgramVolumeCalculator` and `VolumeBands`
**What goes wrong:** A muscle group like `"Shoulders"` (emitted by `ProgramVolumeCalculator`) never
matches a `VolumeBands.priors` key exactly (which has `"Front Delts"`/`"Side Delts"`/`"Rear Delts"`
instead), so it silently falls back to `VolumeBands._fallback = (6, 14, 20)` — a materially
different (wider, less accurate) band than any of the three delt-specific ones.
**Why it happens:** The two systems were built independently, at different times, for different
immediate purposes (`ProgramVolumeCalculator` for the pre-existing volume-preview card;
`VolumeBands` for a not-yet-wired guardrail).
**How to avoid:** Accept the fallback for `"Shoulders"` explicitly (it's not wrong, just coarser) —
do not build a translation layer for this phase. Document this behavior in a code comment at the
D-04 call site so a future reader doesn't mistake it for a bug. Groups that never appear at all
(`"Lats"`, `"Traps"`, `"Obliques"`) are simply inert priors — no action needed, they just never
trigger.
**Warning signs:** A test asserting `VolumeVerdict.low` for a shoulder-heavy plan with suspiciously
generic thresholds; a manual QA pass showing the volume-floor flag firing/not-firing at boundary
values that don't match the `Front/Side/Rear Delts` bands in `volume_bands.dart`.

### Pitfall 2: `_create()`'s exact current line range has drifted from CONTEXT.md's citation
**What goes wrong:** CONTEXT.md cites `actions.part.dart` `_create()` at `~65-152`; the actual
current range (verified 2026-09-30) is **50-191** (141 lines, not 87) — the method grew during
Phase 27's Herculex AI work (the `_acceptedHerculexBrief`/`persistBrief()` block at 106-127 is new
since CONTEXT.md's citation was written).
**Why it happens:** CONTEXT.md was written during discuss-phase, before this research session;
the file has since been touched by unrelated Phase 27 completion work in the same session window.
**How to avoid:** Don't trust cached line numbers from CONTEXT.md verbatim when writing plan tasks
— re-grep at plan-write time and especially at execution time. The method's *shape* (try block,
`configIssues` check near the top at line 70-80, `SmartProgramPlanner(...).populate(...)` call at
line 138-164, catch-and-cleanup at 182-190) is unchanged and is the reliable anchor, not the line
numbers.
**Warning signs:** An Edit tool call with an old line-number-based anchor failing to match.

### Pitfall 3: Hardcoded "3 exposures / week" text will read as wrong once splits vary
**What goes wrong:** `step_parameters.part.dart:274` renders `'$_liftRecommendedWeeks weeks · 3
exposures / week'` unconditionally. Once D-01–D-03 ship, a squat specialization on Upper/Lower
(4-day) gets 2 exposures/week (2 Lower days), not 3 — the summary card would misinform the user.
**Why it happens:** The line was written when specialization force-reset to Full Body 3x/week
unconditionally, so "3" was always correct; D-01's flexibility invalidates that invariant.
**How to avoid:** Compute actual weekly exposure count from `_plan.trainingDays` filtered by
`_specializationLift.appliesToDayLabel(day.label)`, not a hardcoded literal. This is a small,
easily-missed one-line fix that should be an explicit task, not an incidental side effect of the
D-01–D-03 work.
**Warning signs:** A widget test asserting the literal string `'3 exposures / week'` still passing
after a split-flexibility change lands — that's a signal the fix wasn't made, not that it's correct.

### Pitfall 4: `recommendedWeeks()`'s `isNovice: bool` param is not `ExperienceLevel`-shaped
**What goes wrong:** `PrimaryLiftSpecialization.recommendedWeeks({required bool isNovice, ...})`
collapses the app's 3-tier `ExperienceLevel` (novice/intermediate/advanced) into a boolean, so
"intermediate" and "advanced" get identical timeline treatment today. D-11 explicitly asks for a
3-tier-aware kg ceiling — if the planner naively tries to extend `recommendedWeeks()` itself to be
3-tier-aware as part of implementing D-11, that's scope creep beyond D-11's explicit ask (D-11 says
"not a reuse of `recommendedWeeks()`'s existing tiering" — implying a **new, separate** function,
not a modification of the existing one).
**Why it happens:** `recommendedWeeks()` predates the codebase's later standardization on 3-tier
`ExperienceLevel` throughout the rest of the programs feature.
**How to avoid:** Write D-11's kg-ceiling check as a new, independent function/lookup (e.g. a
`static double kgCeilingFor(ExperienceLevel)` or an inline `Map<ExperienceLevel, double>` at the
call site) rather than touching `recommendedWeeks()`'s signature — changing that signature would
ripple into `step_parameters_specialization.part.dart`'s existing `isNovice: _experience ==
ExperienceLevel.novice` call site and any test asserting today's 2-tier behavior
(`test/primary_lift_specialization_test.dart` does not currently test `recommendedWeeks()` directly,
but `smart_program_planner_test.dart` may exercise it indirectly — grep before touching).
**Warning signs:** A diff touching `recommendedWeeks()`'s parameter list when the task was scoped
to "add a kg ceiling check."

## Sticking-Point Assistance Mapping (D-12 — Claude's discretion, delegated by CONTEXT.md)

Every value below was checked against the two live constraints already enforced by the codebase:
(1) `need.muscle`, when non-null, must be a lowercase substring of one of the 14 real
`exerciseCatalog.primaryMuscle` values (`chest`, `back`, `shoulders`, `biceps`, `triceps`,
`forearms`, `abs`, `quads`, `hamstrings`, `glutes`, `calves`, `adductors`, `abductors`, `neck` —
verified via `grep` against `assets/data/exercises.json`); (2) `SlotRole.supplemental` requires
`mechanics == 'compound'` (`SlotRoleEligibility.derive`, `slot_role.dart:100-106`), so every
proposed supplemental `_SlotNeed` below targets a muscle/pattern combination that plausibly has
compound-exercise candidates in the catalog. Each mapping is chosen to **complement, not duplicate**,
the existing isolation slot (bench/OHP already isolate `'tricep'`; pull-up already isolates
`'bicep'`) — and is traceable directly to `PrimaryLiftSpecialization.assistanceFocus`'s existing,
already-shipped copy strings, so the exercise selection and the UI copy the user already sees say
the same thing.

| Lift | Sticking point | Proposed `_SlotNeed` (pattern, muscle, role) | Rationale | Matches existing `assistanceFocus` copy |
|---|---|---|---|---|
| Bench press | `chest` (off the chest) | `('horizontal_push', 'chest', supplemental)` | Extra chest-driving press volume (pause-bench-style precedent) | "Chest volume and stable pressing technique are prioritised." |
| Bench press | `midRange`/`lockout`/`unknown` (default) | `(null, 'back', supplemental)` | Upper-back stability for bar path/lockout; pairs with the existing `'tricep'` isolation slot rather than duplicating it | "Triceps and upper-back assistance are prioritised." |
| Overhead press | `bottom` (out of the bottom) | `('vertical_push', 'shoulder', supplemental)` | Extra strict-press volume for bottom-position strength | "Strict pressing practice and shoulder control are prioritised." |
| Overhead press | `midRange`/`lockout`/`unknown` (default) | `(null, 'back', supplemental)` | Same upper-back rationale as bench's default case; pairs with existing `'tricep'` isolation | "Triceps and upper-back assistance are prioritised." |
| Pull-up | `deadHang` (from a dead hang) | `('vertical_pull', null, supplemental)` | Extra vertical-pull-pattern volume (e.g. lat pulldown/assisted variations) for scapular engagement off a dead hang | "Scapular control and vertical-pull volume are prioritised." |
| Pull-up | `midRange`/`lockout`/`unknown` (default) | `(null, 'back', supplemental)` | Upper-back row volume; pairs with existing `'bicep'` isolation slot (elbow-flexor) | "Upper-back and elbow-flexor assistance are prioritised." |

This mirrors the existing squat/deadlift shape exactly: one lift-distinctive sticking point gets an
explicit branch, the remaining sticking points (`midRange`, `lockout`, `unknown`) share a single
default branch — deadlift already has this exact 1-explicit-plus-default shape (only `offFloor` is
distinguished); squat is the one lift with 2 explicit branches (`bottom` and `lockout`). Matching
deadlift's simpler shape for these 3 lifts is consistent with the fact that `PrimaryLiftStickingPoint`
gives each of bench/OHP/pull-up exactly one lift-specific enum value (`chest`, `bottom` — shared
with squat —, `deadHang` respectively), the same as deadlift's one lift-specific value (`offFloor`).

**Confidence: MEDIUM.** The muscle-substring/role-eligibility mechanics are `[VERIFIED: code read]`.
The specific pattern/muscle choices are `[ASSUMED]` — grounded in standard powerlifting
assistance-exercise convention (pause bench for chest-limited lifters, triceps/upper-back for
lockout-limited bench and OHP, scapular/lat work for dead-hang-limited pull-ups) but this is
general strength-training domain knowledge, not verified against a single authoritative source in
this session. See Assumptions Log.

## Timeline & Increase Realism (D-08–D-11)

### D-08–D-10: Weeks-picker warning (mechanically straightforward)

`dialogs.part.dart:_showLengthPicker`'s `_sheetOptionCard.onSelected` callback (line 243-245
currently does only `setState(() => _weeks = selected);`) is the exact hook point. The comparison
is:

```dart
// Illustrative — exact call site and method extraction is the planner's call
if (_useLiftSpecialization && selected < _liftRecommendedWeeks) {
  // D-09: auto-adjust, don't keep the user's shorter pick
  setState(() => _weeks = _liftRecommendedWeeks);
  // D-08/D-09: show inline warning (banner, not a blocking dialog) with the
  // UI-SPEC's exact copy template, substituting {recommendedWeeks}/{currentKg}/
  // {targetKg}/{liftLabel}
} else {
  setState(() => _weeks = selected);
}
```

D-10 ("any shortfall") means no epsilon/threshold comparison — a bare `<` is correct and matches
the picker's own coarse 2-8-week gaps between the 6 discrete options (per CONTEXT.md's own stated
justification).

### D-11: Kg-increase ceiling (needs new numeric thresholds)

`PrimaryLiftSpecialization.recommendedWeeks()`'s existing tiering (`isNovice ? 16 : 12` base, +4 for
>15kg, +8 for >30kg) only ever *extends the timeline* — it never says "this increase is unrealistic
regardless of how long you give it." D-11 asks for exactly that: an independent ceiling.

Grounding: general strength-progression community consensus (searched, not from a single
peer-reviewed source — see Sources) suggests novice lifters can add roughly 2.5-5kg per *session* to
main lifts under linear progression (i.e., large absolute totals are plausible over months), while
intermediate lifters slow to roughly 5-10kg per *month* "at best," and advanced lifters slower still
(commonly cited as needing 12-18+ months for what a novice does in weeks). The app's own block-length
range tops out at 24 weeks (~5.5 months) — the ceiling should represent "an increase that is not
credible even at the longest available block length," not a per-month rate multiplied out.

**Recommended ceiling (kg, per `ExperienceLevel`, independent of weeks):**

| `ExperienceLevel` | Recommended ceiling | Reasoning |
|---|---|---|
| `novice` | 50 kg | Consistent with "newbie gains" being large and fast; sits clearly above `recommendedWeeks()`'s own `>30kg` tier (24 weeks) so it only fires for genuinely extreme asks |
| `intermediate` | 30 kg | Roughly 5-10kg/month × up to 5.5 months at the upper end of "at best," rounded down for safety margin |
| `advanced` | 15 kg | Advanced lifters' gains are materially slower; even a generous multi-month estimate rarely clears this for a single lift |

**Confidence: LOW-MEDIUM, tagged `[ASSUMED]`.** These are directionally grounded in searched,
cross-corroborated community strength-training consensus (not a single authoritative source, and
not lift-specific — a 30kg bench increase is far more extreme than a 30kg squat/deadlift increase,
but neither `recommendedWeeks()` nor this recommendation differentiates by lift, for consistency
with the existing precedent). **This is exactly the kind of claim CONTEXT.md and this agent's own
instructions flag as needing user confirmation before becoming a locked decision** — the planner
should either present these three numbers to the user for explicit sign-off during plan-checking, or
treat them as a placeholder the user can tune post-ship (e.g., named constants, not magic numbers
buried in a conditional).

**Copy alignment:** UI-SPEC's copy template (`"Adding {increaseKg} kg to your {liftLabel} is outside
typical progress for {experienceLevel} lifters, even over {weeks} weeks."`) is generic enough to
hold whichever final numbers are chosen — no copy change needed once the planner locks the ceiling.

## Volume Floor Wiring (D-04–D-07)

### Live preview (D-06, "while the user configures specialization")

The natural moment is inside `step_parameters.part.dart`'s `if (_useLiftSpecialization) ...`
summary block (currently lines 220-282) or inside the specialization modal itself — **not**
gated behind a separate user action, since D-06 says "live preview." Concretely:

```dart
// Illustrative shape — exact widget/call-site placement is the planner's call
final breakdown = await ProgramVolumeCalculator.computeFromTemplates(
  db: ref.read(appDatabaseProvider),
  templatesBySlot: _templatesBySlot,
  plan: _plan,
  weeks: _weeks,
  model: _model,
);
final verdicts = VolumeBands.verdicts({
  for (final entry in breakdown.averageWeeklyVolumes) entry.muscle: entry.sets,
});
final lowGroups = verdicts.entries.where((e) => e.value == VolumeVerdict.low);
```

**Caveat:** `_templatesBySlot` is populated in Step 3 of the builder wizard (template-per-slot
selection), which comes *after* Step 1 (where the specialization toggle lives). At the point the
user is configuring specialization (Step 1), `_templatesBySlot` may still be empty/default, making
`computeFromTemplates`'s output not yet meaningful. **This is a real sequencing question the
planner must resolve**: either (a) the live preview only becomes meaningful/visible once Step 3 has
been reached (i.e., render it in Step 3 or later, referencing back to the active specialization,
not inside Step 1's modal itself), or (b) it's shown in Step 1 but computed against whatever
defaults `_templatesBySlot` currently holds, with a caveat that it will change as templates are
picked. Given `program_preview_view.dart`'s existing usage of the same calculator happens post-Step-3
(at final review), **recommendation: place the live volume-floor preview in Step 3 (Templates) or
later, not inside the Step 1 specialization modal**, to ensure `_templatesBySlot` is populated when
the calculation runs. This is not explicitly resolved by CONTEXT.md's D-06 ("as the user configures
specialization" could mean "while the specialization toggle is active," not necessarily "inside the
Step 1 modal") — flagged as an Open Question below for the planner to confirm.

### Create-time check (D-06 second half)

Same computation, called once from `actions.part.dart:_create()`, structured as a new
`GuardrailSeverity.warning`-only issue list (mirroring `validateConfiguration()`'s shape) — but
per D-05, **never added to the `configIssues.any((issue) => issue.isBlocking)` throw path** at
line 76-80. It should be surfaced to the user (e.g., collected and shown once, non-blockingly,
perhaps via a confirmation step or a banner shown before the `repo.createProgramFromSplit(...)`
call proceeds) — exact UX (confirm-and-proceed vs. fire-and-forget banner) is explicitly left to
planning by the UI-SPEC's Component Inventory ("exact call site... is planning's call, constrained
only by D-05: never blocks").

## Code Examples

### Confirmed-accurate dead-code line citations (re-verified 2026-09-30)

```
// Source: lib/features/programs/data/smart_program_planner.dart (grep, 2026-09-30)
48:    this.squatSpecialization,
99:  final SquatSpecialization? squatSpecialization;
494:      squatSpecialization: configuration.squatSpecialization,
1403:    SquatSpecialization? squatSpecialization,
1440:        squatSpecialization != null &&
1445:      final assistance = switch (squatSpecialization.stickingPoint) {
```
All six CONTEXT.md-cited line numbers are byte-accurate against the current working tree — no
drift. The full dead branch to delete spans lines 1439-1482 (the `isSquatFocused` block and its
early return), not just 1440-1466 as CONTEXT.md's summary stated — CONTEXT.md's range covered the
`switch` expression itself but not the `final base = [...]` list and `return` that consume it,
which are also entirely dead once `squatSpecialization` is removed. **Also delete**
`test/squat_specialization_test.dart` (27 lines) — discovered during this research, not mentioned
in CONTEXT.md.

### Existing `_needsForPrimaryLift` (full current state, the direct edit target for D-12)

```dart
// Source: lib/features/programs/data/smart_program_planner.dart:1565-1622 (read 2026-09-30)
static List<_SlotNeed> _needsForPrimaryLift(
  PrimaryLiftSpecialization specialization,
) {
  final lift = specialization.lift;
  final main = _SlotNeed(
    lift.movementPattern, null, SlotRole.main,
    preferredSlugs: lift.preferredSlugs,
  );
  final assistance = switch (lift) {
    PrimaryLift.squat => switch (specialization.stickingPoint) {
      PrimaryLiftStickingPoint.bottom => const _SlotNeed('squat', 'quad', SlotRole.supplemental),
      PrimaryLiftStickingPoint.lockout => const _SlotNeed('hinge', 'glute', SlotRole.supplemental),
      _ => const _SlotNeed('lunge', 'quad', SlotRole.supplemental),
    },
    PrimaryLift.deadlift => switch (specialization.stickingPoint) {
      PrimaryLiftStickingPoint.offFloor => const _SlotNeed('lunge', 'quad', SlotRole.supplemental),
      _ => const _SlotNeed('hinge', 'hamstring', SlotRole.supplemental),
    },
    // THE GAP (D-12): bench/OHP/pull-up share one generic branch today.
    PrimaryLift.benchPress ||
    PrimaryLift.overheadPress ||
    PrimaryLift.pullUp => const _SlotNeed('horizontal_pull', null, SlotRole.supplemental),
  };
  // ...isolation switch and final list assembly unchanged...
}
```

## State of the Art

Not applicable in the usual "library X was replaced by Y" sense — this is closed-source,
project-internal domain logic with no external ecosystem to track. The one relevant "old →
current" shift is entirely internal to this codebase:

| Old Approach | Current Approach | When Changed | Impact |
|---|---|---|---|
| Squat-only specialization (`SquatSpecialization`) | 5-lift `PrimaryLiftSpecialization` | Superseded before this phase (exact commit not identified in this session) | The old class is fully dead, confirmed by this research (no live caller); this phase's job is deleting it, not migrating from it |

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | D-12's exact `_SlotNeed` (pattern, muscle) mapping per lift × sticking point | Sticking-Point Assistance Mapping | Low — any reasonable mapping satisfies D-12's actual locked requirement ("branch by sticking point, don't keep one generic slot"); a different specific mapping would still be correct, just a different flavor of correct. Worth a quick gut-check with the user/plan-checker but not blocking. |
| A2 | D-11's numeric kg ceilings (50/30/15 kg for novice/intermediate/advanced) | Timeline & Increase Realism | Medium — if set too low, the warning nags on realistic specialization targets (bad UX, erodes trust in the advisory system); if set too high, it fails to catch genuinely unrealistic asks (defeats SPEC-03's purpose). Recommend explicit user confirmation before lock-in. |
| A3 | `SplitType.upperLowerFullBody` and `SplitType.fullBodyAbGpp` inclusion/exclusion from the D-01/D-03 compatibility set | Architecture Patterns → Split Compatibility | Low-medium — affects a narrow edge case (a user with one of these two specific splits toggling specialization on); wrong-either-way just means either an unnecessary reset or an unintended keep, not a crash or data issue. |
| A4 | Recommendation to place the live volume-floor preview in Step 3+ rather than inside the Step 1 specialization modal | Volume Floor Wiring → Live preview | Medium — if the planner instead renders it in Step 1 against not-yet-populated `_templatesBySlot`, the preview will show a misleadingly empty/zero breakdown rather than a real one, undermining D-06's intent. |
| A5 | Auto-fill "current load" from existing 1RM analytics is out of scope for this phase | Open Questions | Low — worst case is the planner disagrees and adds it anyway; this is a recommendation, not a locked decision, and CONTEXT.md itself left it fully open. |

## Open Questions (RESOLVED)

1. **Should the 1RM-autofill idea (surfaced in CONTEXT.md's canonical_refs, not decided) be built
   this phase?**
   - What we know: `AnalyticsRepository.topOneRms({int limit = 5})` returns the best-N estimated
     1RMs across *all* logged exercises (not filtered by a specific lift/slug) — verified by reading
     `lib/features/analytics/data/analytics_repository.dart:90-139`. To autofill a *specific*
     `PrimaryLift`'s current load, the modal would need either (a) a new targeted repository query
     (`oneRmForExerciseSlug(slug)` or similar, filtered to `lift.preferredSlugs`) or (b) client-side
     filtering of `topOneRms()`'s result set by slug — plus a new async load path into a currently
     fully-synchronous, string-controller-backed modal (`TextEditingController.text`), plus handling
     the "no matching logged history" case (a brand-new user or a user who's never logged that exact
     exercise slug variant).
   - What's unclear: whether this is worth the added async-loading-state complexity for a phase
     whose explicit mandate is 3 narrower gaps (D-12, D-08–D-11, D-04–D-07) plus split flexibility
     and dead-code cleanup — none of which require it.
   - Recommendation: **treat as out of scope for this phase.** It was "surfaced but not decided" per
     CONTEXT.md, not requested by any locked decision, and doesn't serve SPEC-01–03 directly (SPEC-01
     already works today with manual entry). If the planner disagrees, it should be scoped as its
     own small plan/task with an explicit "no match found → falls back to manual entry, unchanged"
     path, not silently folded into another task.

   **Resolution (plan-checker revision, 2026-10-02):** confirmed out of scope. 1RM-autofill is
   omitted from all 4 plans (22-01 through 22-04) — SPEC-01 ships with manual current-load entry
   only, exactly as this research recommended.

2. **Where exactly should the live volume-floor preview (D-06) render, given `_templatesBySlot`
   isn't populated until Step 3?**
   - What we know: `ProgramVolumeCalculator.computeFromTemplates` needs `_templatesBySlot` to be
     meaningful; Step 1 (where specialization is configured) precedes Step 3 (where templates are
     chosen) in the builder wizard.
   - What's unclear: whether D-06's "live preview... while the user configures specialization"
     means literally inside the Step 1 modal (in which case it would show a hollow/default
     breakdown until Step 3) or more loosely "while specialization is the active configuration"
     (in which case Step 3+ is the natural, meaningful placement).
   - Recommendation: place it in Step 3 (Templates) or later — see Volume Floor Wiring above. Flag
     for plan-checker/user confirmation if ambiguous.

   **Resolution (plan-checker revision, 2026-10-02):** resolved as
   `step_schedule_summary.part.dart`'s existing `_summaryCard`/`FutureBuilder<ProgramVolumeBreakdown>`
   call site (22-04 Task 1) — more specific than this section's original "Step 3+" speculation,
   found via direct code read during the second planning session. `_templatesBySlot` is populated
   by the time this call site renders, so the live preview shows a meaningful breakdown, not a
   hollow default.

3. **Should `SplitType.upperLowerFullBody` and `SplitType.fullBodyAbGpp` be treated as
   D-01/D-03-compatible?**
   - What we know: both structurally pass `appliesToDayLabel`'s matching for every lift (see table
     above); neither was explicitly named by CONTEXT.md's "Full Body, Upper/Lower, PPL" list.
   - What's unclear: whether the user's intent was the 3 *named* splits literally, or the broader
     *behavior* (any split whose day labels happen to match).
   - Recommendation: include `upperLowerFullBody` (harmless superset), exclude `fullBodyAbGpp`
     (its real owner is a different training style/phase) — see rationale in Architecture Patterns.

   **Resolution (plan-checker revision, 2026-10-02):** resolved exactly as recommended —
   `_specializationCompatibleSplits` (22-02 Task 1) includes `upperLowerFullBody`, excludes
   `fullBodyAbGpp`.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | `flutter_test` (bundled with Flutter 3.44 SDK) |
| Config file | none — standard `flutter test` discovery over `test/` |
| Quick run command | `flutter test test/primary_lift_specialization_test.dart test/program_guardrails_test.dart test/features/programs/volume_bands_test.dart` |
| Full suite command | `flutter test > test_output.txt 2>&1` (redirect per CLAUDE.md — do not pipe to `tail`, and use `tr '\r' '\n'` before grepping progress output) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SPEC-01 (sticking-point branching, D-12) | Bench/OHP/pull-up's `_needsForPrimaryLift` returns a distinct assistance `_SlotNeed` per sticking point, not one generic slot | unit | `flutter test test/smart_program_planner_test.dart -x` | ✅ (1378-line existing file; new cases append to it — `_needsForPrimaryLift`/`_SlotNeed` are private, so tests must exercise them indirectly through `SmartProgramPlanner.populate()`, matching the file's existing test style) |
| SPEC-01 (split flexibility, D-01–D-03) | Toggling specialization on with an existing Upper/Lower or PPL split keeps that split; toggling on with an incompatible split (e.g. bro split) resets to Full Body/3-day/Linear | widget | `flutter test test/block_builder_view_test.dart -x` | ✅ (existing file already covers specialization toggle interactions per Phase 27's summary notes) |
| SPEC-02 (volume floor, D-04–D-07) | `VolumeBands.verdicts()` called with a specialization-skewed `computeFromTemplates` breakdown flags at least one `VolumeVerdict.low` group when non-target muscles are starved | unit | `flutter test test/features/programs/volume_bands_test.dart test/program_muscle_volume_test.dart -x` | ✅ both files exist; **new integration-style test needed** combining both — ⚠️ Wave 0 gap, see below |
| SPEC-02 (Create-time volume-floor check, D-06) | `_create()` surfaces (but never blocks on) a low-volume warning | widget | `flutter test test/block_builder_view_test.dart -x` | ✅ file exists, new test cases needed |
| SPEC-03 (timeline warning, D-08–D-10) | Picking a shorter-than-recommended weeks value while specialization is active shows a warning and auto-adjusts `_weeks` | widget | `flutter test test/block_builder_view_test.dart -x` | ✅ file exists, new test cases needed |
| SPEC-03 (kg-ceiling warning, D-11) | A target/current kg gap exceeding the experience-tier ceiling shows a warning | unit + widget | new unit test for the ceiling function + widget test for the banner | ⚠️ Wave 0 gap — no existing file covers this; new function needs a new small test file or an addition to `primary_lift_specialization_test.dart` |
| Dead code cleanup | `SquatSpecialization`/`SquatStickingPoint` fully removed, no dangling references | static | `flutter analyze` (0 errors) + `grep -r "SquatSpecialization\|SquatStickingPoint" lib/ test/` (0 matches) | N/A — verification step, not a test file |

### Sampling Rate

- **Per task commit:** the quick-run command above (specialization/guardrail/volume-bands unit
  tests), plus `flutter analyze` on touched files.
- **Per wave merge:** `flutter test test/smart_program_planner_test.dart test/block_builder_view_test.dart test/program_guardrails_test.dart test/features/programs/volume_bands_test.dart test/program_muscle_volume_test.dart` plus full-repo `flutter analyze`.
- **Phase gate:** full `flutter test` (target: 1721+ passed, matching Phase 27's last recorded
  baseline in STATE.md, plus this phase's new tests, 0 failures) before `/gsd:verify-work`.

### Wave 0 Gaps

- [ ] A new unit test (either a new small `strength_progression_ceiling_test.dart` or an addition
      to `test/primary_lift_specialization_test.dart`) covering D-11's kg-ceiling function once its
      exact home (new function vs. new file) is decided by planning.
- [ ] A new integration-style test combining `ProgramVolumeCalculator.computeFromTemplates` +
      `VolumeBands.verdicts()` for a specialization-skewed configuration — neither
      `volume_bands_test.dart` nor `program_muscle_volume_test.dart` currently exercises them
      together; this is exactly the new D-04 call path and deserves its own coverage.
- [ ] `test/squat_specialization_test.dart` should be **deleted**, not extended — it tests only the
      dead class this phase removes.

## Environment Availability

Skipped — this phase has no external dependency (no new package, no external service, no CLI tool
beyond the existing `flutter`/`dart` toolchain already required and already verified working by
every prior phase in this session's STATE.md history).

## Security Domain

Skipped per config check: `.planning/config.json` does not set `security_enforcement` to `false`
explicitly, so the section would normally be required — but this phase introduces no new input
surface beyond what already exists (the current/target-kg text fields are pre-existing, already
validated for non-null/non-negative numeric input at `step_parameters_specialization.part.dart:177-189`,
unchanged by this phase), no new authentication/session/access-control surface, no new
cryptographic operation, and no new network call. The relevant ASVS categories (V2 Authentication,
V3 Session Management, V4 Access Control, V6 Cryptography) do not apply to a local, deterministic,
offline domain-logic extension. V5 Input Validation is already satisfied by the existing
`double.tryParse(...) == null || current < 0` guard this phase does not touch.

## Sources

### Primary (HIGH confidence — direct code read, 2026-09-30)
- `lib/features/programs/domain/primary_lift_specialization.dart` (full file)
- `lib/features/programs/domain/squat_specialization.dart` (full file, dead code confirmed)
- `lib/features/programs/domain/volume_bands.dart` (full file)
- `lib/features/programs/domain/program_muscle_volume.dart` (full file)
- `lib/features/programs/domain/program_guardrails.dart` (full file)
- `lib/features/programs/domain/slot_role.dart` (full file)
- `lib/features/programs/domain/split_template.dart` (SplitType enum + slots)
- `lib/features/programs/data/smart_program_planner.dart` (lines 1-110, 460-620, 1090-1130, 1380-1650, 1730-1856 read directly; `grep` for `squatSpecialization`/`need.muscle`/`rear` across full file)
- `lib/features/programs/presentation/views/block_builder_view.dart` (lines 1-180)
- `lib/features/programs/presentation/views/block_builder_view/step_parameters_specialization.part.dart` (full file)
- `lib/features/programs/presentation/views/block_builder_view/step_parameters.part.dart` (full file)
- `lib/features/programs/presentation/views/block_builder_view/dialogs.part.dart` (lines 190-265)
- `lib/features/programs/presentation/views/block_builder_view/actions.part.dart` (full file)
- `lib/features/programs/presentation/widgets/ai_brief_rejection_banner.dart` (full file)
- `lib/features/programs/presentation/widgets/program_muscle_volume_card.dart` (full file)
- `lib/features/workouts/domain/one_rep_max.dart` (full file)
- `lib/features/analytics/data/analytics_repository.dart` (lines 80-146)
- `assets/data/exercises.json` (grep for `primaryMuscle` values — 14 distinct values confirmed)
- `lib/design_system/tokens/hx_colors.dart` (grep for `warning`/`danger` tokens)
- `lib/features/programs/domain/programming_models.dart` (ExperienceLevel enum)
- `.planning/config.json` (workflow flags — `nyquist_validation: true`, no `security_enforcement` override)
- `test/` directory listing + `wc -l` on `primary_lift_specialization_test.dart`, `program_guardrails_test.dart`, `program_muscle_volume_test.dart`, `squat_specialization_test.dart`, `smart_program_planner_test.dart`; `grep -rl "VolumeBands"` confirming `test/features/programs/volume_bands_test.dart` exists

### Secondary (MEDIUM confidence)
- CONTEXT.md, DISCUSSION-LOG.md, UI-SPEC.md, REQUIREMENTS.md, STATE.md (all read in full this
  session, treated as authoritative for locked decisions but cross-checked against code where they
  made factual claims about line numbers/current file state)

### Tertiary (LOW confidence — WebSearch, not independently verified against an authoritative single source)
- Novice/intermediate/advanced strength-progression rate norms (used to ground D-11's kg ceilings)
  — general community consensus across multiple strength-standards/calculator sites, not a single
  peer-reviewed or official source. See Assumptions Log A2.

## Metadata

**Confidence breakdown:**
- Standard stack / architecture: HIGH — every component is existing, already-built, already
  independently tested code; no new library or pattern introduced.
- Sticking-point assistance mapping (D-12): MEDIUM — mechanically verified against real codebase
  constraints, but the specific exercise-convention choices are domain judgment, not verified fact.
- Timeline/kg-ceiling numbers (D-11): LOW-MEDIUM — directionally grounded, explicitly flagged for
  user confirmation.
- Pitfalls: HIGH — all four identified pitfalls are based on direct code observation (muscle-vocab
  mismatch, line-number drift, hardcoded exposure text, `isNovice` boolean narrowness), not
  speculation.

**Research date:** 2026-09-30
**Valid until:** 2026-10-14 (14 days — this codebase is under active, fast-moving development in
the same feature area; `actions.part.dart`'s line-number drift observed *within this same session*
is a concrete signal that citations here should be re-verified at plan/execution time rather than
trusted long-term)
