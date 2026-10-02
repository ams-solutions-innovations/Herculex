# Phase 22: Primary Lift Strength Specialization - Pattern Map

**Mapped:** 2026-09-30
**Files analyzed:** 11 (9 edits to existing files, 2 deletions, 0-2 possible new widget files)
**Analogs found:** 11 / 11 (every file has a same-repo, same-feature analog — this phase extends
already-live surfaces, it doesn't start a new architectural pattern)

> **Note on scope:** Phase 22 is almost entirely edits to existing files, not new files. For each
> edit target below, the "analog" is the *existing sibling pattern in the same file* (e.g. the
> squat/deadlift branch in `_needsForPrimaryLift` is both the edit target's file and its own best
> template) plus one cross-file precedent for anything genuinely new (the warning-banner visual
> pattern, the guardrail pure-function shape). Line numbers were re-verified directly against the
> working tree on 2026-09-30 (RESEARCH.md's Pitfall 2 flags `actions.part.dart`'s citations as
> having drifted once already this session — re-grep at execution time, don't trust these numbers
> beyond that).

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `lib/features/programs/data/smart_program_planner.dart` (`_needsForPrimaryLift`, D-12) | data / pure-function planner | transform | same file, squat/deadlift branches (lines 1576-1596) | exact — same function, same switch statement, add 2 more branches |
| `lib/features/programs/data/smart_program_planner.dart` (`squatSpecialization` removal) | data / dead-code cleanup | transform | same file's own dead branch (lines 1439-1482) | exact — pure subtraction |
| `lib/features/programs/domain/squat_specialization.dart` | domain model (DELETE) | n/a | `PrimaryLiftSpecialization` (`primary_lift_specialization.dart`) — its superseding replacement | exact — confirmed-dead predecessor |
| `test/squat_specialization_test.dart` | test (DELETE) | n/a | n/a | exact — tests only the dead class |
| `lib/features/programs/domain/program_guardrails.dart` (new volume-floor + kg-ceiling checks, D-06/D-11) | domain / pure-function guardrail | transform | `ProgramGuardrails.validateConfiguration()` (same file, lines 159-192) | exact — identical shape, `GuardrailSeverity.warning`-only |
| `lib/features/programs/domain/primary_lift_specialization.dart` (optional kg-ceiling helper, D-11) | domain model | transform | `PrimaryLiftSpecialization.recommendedWeeks()` (same file, lines 78-88) — as an anti-pattern to avoid extending, not to copy | n/a — see Anti-Pattern note below |
| `lib/features/programs/presentation/views/block_builder_view/step_parameters_specialization.part.dart` (D-01–D-03 split-compat Apply, D-12 sticking-point helper copy) | presentation / modal state-mutation handler | request-response (in-memory setState) | same file's existing Apply `setState` block (lines 207-222) | exact — same handler, same file |
| `lib/features/programs/presentation/views/block_builder_view/step_parameters.part.dart` (exposures-per-week fix, optional embedded volume preview) | presentation / summary card | request-response | same file's existing specialization summary card (lines 220-282) | exact — same widget subtree |
| `lib/features/programs/presentation/views/block_builder_view/dialogs.part.dart` (`_showLengthPicker` onSelected, D-08–D-10) | presentation / bottom-sheet picker handler | request-response | same file's existing `onSelected` callback (line 243-245) | exact — same callback |
| `lib/features/programs/presentation/views/block_builder_view/actions.part.dart` (`_create()` Create-time checks, D-06/D-11) | presentation / async form-submit handler | request-response | `ProgramGuardrails.validateConfiguration()` call site (same file, lines 70-80) | exact — same method, same guardrail-call idiom |
| New volume-floor preview widget (if planner adds a sibling instead of extending `ProgramMuscleVolumeCard`) | component / read-only card | transform (render breakdown → rows) | `ProgramMuscleVolumeCard` (`program_muscle_volume_card.dart`, full file) + `AiBriefRejectionBanner` (`ai_brief_rejection_banner.dart`, full file) for the warning-tint treatment | role-match — card shell from one, `context.hx` token usage from the other |
| Warning banner for timeline/kg-increase/volume-floor (D-08–D-11, D-06) | component / presentational banner | transform (props → rendered warning) | `AiBriefRejectionBanner` (`ai_brief_rejection_banner.dart`, full file, 77 lines) | exact — UI-SPEC names this as the explicit reuse target |

## Pattern Assignments

### `lib/features/programs/data/smart_program_planner.dart` — `_needsForPrimaryLift` (D-12)

**Analog:** the existing squat/deadlift branches in the same function.

**Current full function** (`smart_program_planner.dart:1565-1622`):
```dart
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
      PrimaryLiftStickingPoint.bottom => const _SlotNeed(
        'squat', 'quad', SlotRole.supplemental,
      ),
      PrimaryLiftStickingPoint.lockout => const _SlotNeed(
        'hinge', 'glute', SlotRole.supplemental,
      ),
      _ => const _SlotNeed('lunge', 'quad', SlotRole.supplemental),
    },
    PrimaryLift.deadlift => switch (specialization.stickingPoint) {
      PrimaryLiftStickingPoint.offFloor => const _SlotNeed(
        'lunge', 'quad', SlotRole.supplemental,
      ),
      _ => const _SlotNeed('hinge', 'hamstring', SlotRole.supplemental),
    },
    // THE GAP (D-12): bench/OHP/pull-up share one generic branch today.
    PrimaryLift.benchPress ||
    PrimaryLift.overheadPress ||
    PrimaryLift.pullUp => const _SlotNeed('horizontal_pull', null, SlotRole.supplemental),
  };
  final isolation = switch (lift) {
    PrimaryLift.squat ||
    PrimaryLift.deadlift => const _SlotNeed(null, 'abs', SlotRole.isolation),
    PrimaryLift.benchPress || PrimaryLift.overheadPress => const _SlotNeed(
      null, 'tricep', SlotRole.isolation,
    ),
    PrimaryLift.pullUp => const _SlotNeed(null, 'bicep', SlotRole.isolation),
  };
  return [main, assistance,
    const _SlotNeed('horizontal_push', null, SlotRole.accessory),
    const _SlotNeed('horizontal_pull', null, SlotRole.accessory),
    isolation];
}
```

**Core pattern to mirror:** each `PrimaryLift` case is `switch (specialization.stickingPoint) { ... }`,
one lift-specific enum value gets an explicit branch, everything else (`midRange`/`lockout`/`unknown`)
shares a single `_` default. Squat is the one 2-branch outlier (`bottom` + `lockout`); deadlift's
1-branch-plus-default shape is the correct template for bench/OHP/pull-up since each of those three
has exactly one lift-specific `PrimaryLiftStickingPoint` value (`chest`, `bottom`-shared-with-squat,
`deadHang` respectively — see `primary_lift_specialization.dart:31-61`).

**`_SlotNeed` constructor signature** (`smart_program_planner.dart:1831-1846`, needed to write new branches):
```dart
class _SlotNeed {
  const _SlotNeed(
    this.pattern, this.muscle, this.role, {
    this.preferredSlugs = const {}, this.segment,
    this.metconGroupKey, this.metconFormat,
    this.metconCapSeconds, this.metconMinutes,
  });
  final String? pattern;
  final String? muscle;
  final SlotRole role;
  ...
}
```

**RESEARCH.md's concrete D-12 recommendation** (mechanically verified against the catalog's 14
`primaryMuscle` values and `SlotRoleEligibility.derive`'s `mechanics == 'compound'` requirement for
`SlotRole.supplemental` — see RESEARCH.md "Sticking-Point Assistance Mapping"):

| Lift | Sticking point | `_SlotNeed` |
|---|---|---|
| benchPress | `chest` | `('horizontal_push', 'chest', SlotRole.supplemental)` |
| benchPress | default | `(null, 'back', SlotRole.supplemental)` |
| overheadPress | `bottom` | `('vertical_push', 'shoulder', SlotRole.supplemental)` |
| overheadPress | default | `(null, 'back', SlotRole.supplemental)` |
| pullUp | `deadHang` | `('vertical_pull', null, SlotRole.supplemental)` |
| pullUp | default | `(null, 'back', SlotRole.supplemental)` |

**Anti-pattern flagged by RESEARCH.md (do not repeat):** `'rear'` (used at lines 1498/1532 for the
existing pull/shoulder isolation slots) is never a substring of any real catalog `primaryMuscle`
value — it silently falls through. Verify any new muscle string is a substring of one of: `chest`,
`back`, `shoulders`, `biceps`, `triceps`, `forearms`, `abs`, `quads`, `hamstrings`, `glutes`,
`calves`, `adductors`, `abductors`, `neck`.

**Dead-code deletion targets** (all byte-verified 2026-09-30, `smart_program_planner.dart`):
```
48:    this.squatSpecialization,
99:  final SquatSpecialization? squatSpecialization;
494:      squatSpecialization: configuration.squatSpecialization,
1403:    SquatSpecialization? squatSpecialization,
1439-1482:  final isSquatFocused = ... (full dead branch — the switch AND the `final base = [...]`/
             `return` that consume it, not just the switch itself)
21:    import 'package:herculex/features/programs/domain/squat_specialization.dart';  (now-unused import)
```

---

### `lib/features/programs/domain/program_guardrails.dart` — new D-06/D-11 checks

**Analog:** `ProgramGuardrails.validateConfiguration()`, same file, lines 159-192:
```dart
static List<ProgramGuardrailIssue> validateConfiguration({
  required ProgramBuildMode buildMode,
  required PeriodizationModel model,
  required SplitType split,
  required Map<String, SlotTrainingMethod> mainMethodByDayLabel,
}) {
  final issues = <ProgramGuardrailIssue>[];
  final explicitMaxEffort = mainMethodByDayLabel.values
      .where((m) => m == SlotTrainingMethod.maxEffort)
      .length;
  if (buildMode != ProgramBuildMode.manual && explicitMaxEffort > 2) {
    issues.add(
      const ProgramGuardrailIssue(
        code: 'config_max_effort_per_week',
        message: 'A Smart program can use at most two Max Effort patterns per week.',
        severity: GuardrailSeverity.blocking,
      ),
    );
  }
  ...
  return issues;
}
```

**Issue/severity shapes** (`program_guardrails.dart:1-20`):
```dart
enum GuardrailSeverity { warning, blocking }

class ProgramGuardrailIssue {
  const ProgramGuardrailIssue({
    required this.code, required this.message, required this.severity,
  });
  final String code;
  final String message;
  final GuardrailSeverity severity;
  bool get isBlocking => severity == GuardrailSeverity.blocking;
}
```

**Pattern to copy:** a static method on `ProgramGuardrails`, taking plain data (no drift reads),
returning `List<ProgramGuardrailIssue>`, appending `const ProgramGuardrailIssue(...)` per violation.
D-05 locks every new issue this phase adds to `severity: GuardrailSeverity.warning` — never
`blocking` — so the new check(s) must **never** be added to `actions.part.dart`'s
`configIssues.any((issue) => issue.isBlocking)` throw path (see below).

**Inputs available for the two new checks:**
- D-06 (volume floor): `Map<String, VolumeVerdict>` from `VolumeBands.verdicts(weeklySetsByGroup)`
  (`volume_bands.dart:154-162`) — iterate for `VolumeVerdict.low`, emit one issue per flagged group.
- D-11 (kg ceiling): `(targetKg - currentKg)` vs. an `ExperienceLevel`-keyed ceiling — RESEARCH.md's
  recommended defaults are `{novice: 50, intermediate: 30, advanced: 15}` kg, tagged `[ASSUMED]`,
  flagged for explicit confirmation (RESEARCH.md Assumptions Log A2) — implement as named constants,
  not magic numbers, per RESEARCH.md's own recommendation.

**Anti-pattern (RESEARCH.md, explicit):** do not add a new `GuardrailSeverity` value (e.g.
`.advisory`) — reuse `.warning` verbatim.

---

### `lib/features/programs/domain/volume_bands.dart` + `program_muscle_volume.dart` — D-04 wiring (no edit, just the call shape)

**Both files are UNCHANGED** — this phase's only job is calling them. Full signatures for the
planner/executor to use directly:

```dart
// Source: lib/features/programs/domain/program_muscle_volume.dart:8-25 (MuscleVolumeEntry)
class MuscleVolumeEntry {
  final String muscle;
  final double sets;
  final double percentage;
  const MuscleVolumeEntry({required this.muscle, required this.sets, this.percentage = 0.0});
}

// Source: lib/features/programs/domain/program_muscle_volume.dart:50-68 (ProgramVolumeBreakdown)
class ProgramVolumeBreakdown {
  final List<WeeklyMuscleBreakdown> weeks;
  final List<MuscleVolumeEntry> averageWeeklyVolumes;
  final double averageWeeklyTotalSets;
  static const empty = ProgramVolumeBreakdown(weeks: [], averageWeeklyVolumes: [], averageWeeklyTotalSets: 0);
  bool get isEmpty => weeks.isEmpty || averageWeeklyTotalSets == 0;
}

// Source: lib/features/programs/domain/program_muscle_volume.dart:468-474 (call signature)
static Future<ProgramVolumeBreakdown> computeFromTemplates({
  required AppDatabase db,
  required Map<int, int?> templatesBySlot,
  required SplitPlan plan,
  required int weeks,
  required PeriodizationModel model,
});

// Source: lib/features/programs/domain/volume_bands.dart:154-162 (verdicts)
static Map<String, VolumeVerdict> verdicts(
  Map<String, num> weeklySetsByGroup, {
  Map<String, VolumeTolerance> tolerances = const {},
}) {
  return {
    for (final e in weeklySetsByGroup.entries)
      e.key: forGroup(e.key, tolerance: tolerances[e.key]).verdict(e.value),
  };
}
```

**Wiring shape** (illustrative, from RESEARCH.md, both live and Create-time call sites use this):
```dart
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

**Known coverage gap (not a bug to fix, just to comment at the call site):**
`ProgramVolumeCalculator` emits `"Shoulders"` (14-group catalog vocabulary); `VolumeBands.priors` has
`"Front Delts"`/`"Side Delts"`/`"Rear Delts"` instead (19-group vocabulary) — `"Shoulders"` silently
gets `VolumeBands._fallback = (6, 14, 20)`, a real but coarser band, not a crash. `"Lats"`/`"Traps"`/
`"Obliques"` priors are simply unreachable through this call path. Document, don't build a
translation layer (D-04: "reuse over reinvention").

**Sequencing caveat (RESEARCH.md Open Question 2 / Assumption A4):** `_templatesBySlot` is empty
until Step 3 of the builder wizard; Step 1 is where specialization is configured. Render the live
volume-floor preview in Step 3+ (mirroring where `program_preview_view.dart` already calls this
same calculator — post-template-selection), not inside the Step 1 specialization modal.

---

### `lib/features/programs/presentation/views/block_builder_view/step_parameters_specialization.part.dart` (D-01–D-03, D-12 copy)

**Analog:** the file's own existing Apply `setState` block.

**Current force-reset block** (`step_parameters_specialization.part.dart:207-222`):
```dart
if (result == true && mounted) {
  setState(() {
    _specializationLift = tempLift;
    _currentSquatCtrl.text = currentCtrl.text.trim();
    _targetSquatCtrl.text = targetCtrl.text.trim();
    _liftStickingPoint = tempStickingPoint;
    _useLiftSpecialization = true;
    _split = SplitType.fullBody;
    _daysPerWeek = 3;
    _model = PeriodizationModel.linear;
    _weeks = _liftRecommendedWeeks;
    _clearCustomWeeklyPlacement();
  });
  return true;
}
```

**Edit shape for D-01–D-03:** wrap the `_split = SplitType.fullBody; _daysPerWeek = 3; _model =
PeriodizationModel.linear;` lines in a compatibility check — keep `_split`/`_daysPerWeek`/`_model`
unchanged if `_split` is already in the compatible set, else fall through to today's reset.
RESEARCH.md's verified compatibility set (cross-referenced against `PrimaryLift.appliesToDayLabel`'s
substring matching, see `split_template.dart:27-64` `SplitType` enum with `.slots`):
`{SplitType.fullBody, fullBodyLinear, fullBodyAb, upperLower, ppl}` unambiguous minimum, plus
`upperLowerFullBody` recommended-include (harmless superset) and `fullBodyAbGpp`
recommended-exclude (owned by a different training style/phase) — both tagged `[ASSUMED]`,
RESEARCH.md Assumptions Log A3.

**`PrimaryLift.appliesToDayLabel`** (the domain check D-01–D-03 build on top of, unchanged,
`primary_lift_specialization.dart:17-28`):
```dart
bool appliesToDayLabel(String label) {
  final value = label.toLowerCase();
  if (value.contains('full')) return true;
  return switch (this) {
    PrimaryLift.squat ||
    PrimaryLift.deadlift => value.contains('lower') || value.contains('leg'),
    _ => value.contains('upper') || value.contains('push') || value.contains('pull'),
  };
}
```

**D-12 copy pattern (`assistanceFocus`)** — already-shipped domain string, just needs a render site.
Full switch, `primary_lift_specialization.dart:90-112`:
```dart
String get assistanceFocus => switch ((lift, stickingPoint)) {
  (PrimaryLift.squat, PrimaryLiftStickingPoint.bottom) =>
    'Quad strength and a controlled squat pattern are prioritised.',
  ...
  (PrimaryLift.benchPress, PrimaryLiftStickingPoint.chest) =>
    'Chest volume and stable pressing technique are prioritised.',
  (PrimaryLift.benchPress, _) =>
    'Triceps and upper-back assistance are prioritised.',
  ...
  _ => 'Balanced assistance is prioritised for this primary lift.',
};
```
UI-SPEC's Copywriting Contract: render this string **verbatim**, never truncated/re-derived, in a
new `Text` widget under the sticking-point dropdown (existing dropdown at lines 122-154), styled
`theme.textTheme.bodySmall` + `context.hx.onSurfaceVariant` (NEW text uses `context.hx`, per
UI-SPEC — do not add more `AppColors.*` call sites, but the file's existing `AppColors.secondary`
lines, e.g. line 52/160, are unchanged/out of scope).

**Existing validation-error `SnackBar` pattern** to match for any new inline validation
(`step_parameters_specialization.part.dart:181-188`):
```dart
ScaffoldMessenger.of(context).showSnackBar(
  const SnackBar(content: Text('Please enter your current load (kg).')),
);
```

---

### `lib/features/programs/presentation/views/block_builder_view/step_parameters.part.dart` (exposures-per-week fix, optional embedded preview)

**Analog:** the file's own existing specialization summary card, lines 220-282.

**Hardcoded string to fix** (line 274):
```dart
Text(
  '$_liftRecommendedWeeks weeks · 3 exposures / week',
  style: theme.textTheme.bodySmall?.copyWith(color: AppColors.secondary),
),
```
Per RESEARCH.md Pitfall 3: once D-01–D-03 land, this `3` is wrong for Upper/Lower (2x) or PPL (1x)
splits. Replace with a computed exposure count from `_plan.trainingDays.where((day) =>
_specializationLift.appliesToDayLabel(day.label)).length` (or equivalent), not a literal.

**Card container shape to match for any new content added inside this block**
(`step_parameters.part.dart:222-231`):
```dart
Container(
  width: double.infinity,
  padding: const EdgeInsets.all(14),
  decoration: BoxDecoration(
    color: AppColors.primary.withValues(alpha: .08),
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: AppColors.primary.withValues(alpha: .35)),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [ /* existing rows */ ],
  ),
),
```

---

### `lib/features/programs/presentation/views/block_builder_view/dialogs.part.dart` — `_showLengthPicker` (D-08–D-10)

**Analog:** the picker's own existing `onSelected` callback.

**Full current method** (`dialogs.part.dart:206-251`):
```dart
@override
void _showLengthPicker(ThemeData theme) {
  const lengths = [4, 6, 8, 12, 16, 24];
  HxSheet.show(
    context,
    builder: (sheetContext) => HxSheet(
      scrollable: true,
      initialSize: 0.7,
      maxSize: 0.85,
      title: 'Block Length',
      subtitle: 'Total duration of this training mesocycle',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final w in lengths)
            _sheetOptionCard<int>(
              sheetContext: sheetContext,
              theme: theme,
              item: w,
              selectedItem: _weeks,
              title: '$w weeks',
              subtitle: switch (w) { /* ... */ },
              icon: Icons.calendar_today_rounded,
              isRecommended: w == 8,
              onSelected: (selected) {
                setState(() => _weeks = selected);
              },
            ),
        ],
      ),
    ),
  );
}
```

**Edit shape (D-08–D-10), from RESEARCH.md's illustrative shape:**
```dart
onSelected: (selected) {
  if (_useLiftSpecialization && selected < _liftRecommendedWeeks) {
    // D-09: auto-adjust, don't keep the user's shorter pick
    setState(() => _weeks = _liftRecommendedWeeks);
    // D-08/D-09: show inline warning (banner, not a blocking dialog) — see
    // AiBriefRejectionBanner pattern below. D-10: bare `<`, no epsilon.
  } else {
    setState(() => _weeks = selected);
  }
},
```
Note: `_showLengthPicker` uses `HxSheet`/`_sheetOptionCard` (the modern `context.hx`-native shell),
unlike `step_parameters_specialization.part.dart`'s legacy `showModalBottomSheet`/`AppColors` shell
— match whichever shell the edited call site already uses; do not migrate one to the other's style
as a side effect.

---

### `lib/features/programs/presentation/views/block_builder_view/actions.part.dart` — `_create()` (D-06, D-11)

**Analog:** the method's own existing `ProgramGuardrails.validateConfiguration()` call.

**Current guardrail call site** (`actions.part.dart:70-80`, confirmed live 2026-09-30 — matches
RESEARCH.md Pitfall 2's `_create()` range of 50-191, not CONTEXT.md's stale `~65-152`):
```dart
final configIssues = ProgramGuardrails.validateConfiguration(
  buildMode: _buildMode,
  model: _model,
  split: _split,
  mainMethodByDayLabel: _mainMethodByDayLabel,
);
if (configIssues.any((issue) => issue.isBlocking)) {
  throw StateError(
    configIssues.firstWhere((issue) => issue.isBlocking).message,
  );
}
```

**Pattern to copy:** call the new D-06/D-11 pure-function check(s) the same way, **immediately
after** this block — but critically, per D-05, **never** feed their results into the
`.any((issue) => issue.isBlocking)` throw path above. They must be surfaced through a separate,
non-blocking path (e.g. collected and shown via a confirmation banner before
`repo.createProgramFromSplit(...)` proceeds, or shown once as an informational aside) — exact UX is
explicitly left to planning by UI-SPEC's Component Inventory.

**Where `_primaryLiftSpecialization` is threaded into the planner** (already-existing, unchanged,
`actions.part.dart:152`):
```dart
primaryLiftSpecialization: _primaryLiftSpecialization,
```
This is the call site confirming `squatSpecialization` is never populated here (never passed to
`SmartProgramConfiguration(...)` in this file) — corroborating RESEARCH.md/CONTEXT.md's dead-code
claim independently.

---

### Warning banner for D-08–D-11 (timeline, kg-increase) and D-04–D-07 (volume-floor)

**Analog:** `AiBriefRejectionBanner` — the UI-SPEC's explicit, named reuse target.

**Full source** (`lib/features/programs/presentation/widgets/ai_brief_rejection_banner.dart`,
77 lines, reproduced in full since this is the primary visual template for all 3 new warnings):
```dart
class AiBriefRejectionBanner extends StatelessWidget {
  const AiBriefRejectionBanner({
    super.key, required this.heading, required this.body, required this.footer,
  });
  final String heading;
  final String body;
  final String footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    return Semantics(
      label: heading,
      child: Container(
        padding: const EdgeInsets.all(HxSpace.x3),
        decoration: BoxDecoration(
          color: hx.warning.withValues(alpha: .08),
          borderRadius: HxRadius.mdAll,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, size: 16, color: hx.warning),
                const SizedBox(width: HxSpace.x2),
                Expanded(
                  child: Text(heading, style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700, color: hx.warning,
                  )),
                ),
              ],
            ),
            const SizedBox(height: HxSpace.x2),
            Text(body, style: theme.textTheme.bodySmall),
            const SizedBox(height: HxSpace.x1),
            Text(footer, style: theme.textTheme.bodySmall?.copyWith(
              color: hx.onSurfaceVariant,
            )),
          ],
        ),
      ),
    );
  }
}
```

**Reuse decision (planning's call, per UI-SPEC Component Inventory):** either import this widget
directly (3-field heading/body/footer shape) for the timeline warning (which has a natural 3-part
copy: heading / body / auto-adjust confirmation), or build a 2-field sibling (heading/body only,
same `Container`/`Row`/`Icon`/`hx.warning` visual shape) for the kg-increase and volume-floor
warnings if their content doesn't need a third line. Do not invent a new banner visual style.

**Color/token usage this establishes as the house pattern for ALL new code this phase adds:**
`context.hx.warning` (`#FF9F0A` Classic Blue Dark — `hx_colors.dart:174`) exclusively for the 3 new
warning surfaces; `HxSpace.x1/x2/x3` (4/8/12px, `hx_geometry.dart`) for spacing;
`HxRadius.mdAll` for corner radius; `Icons.warning_amber_rounded` for the icon; never
`context.hx.primary`/accent for a warning; never `context.hx.danger` (D-05: no blocking/destructive
surfaces this phase).

**Copy templates (UI-SPEC, verbatim):**
- Timeline: heading "Not enough time to progress safely"; body "{recommendedWeeks} weeks is a more
  realistic target for a {currentKg}→{targetKg} kg {liftLabel}. We've adjusted your block to
  {recommendedWeeks} weeks."; snackbar footer "Block length adjusted to {recommendedWeeks} weeks to
  match your specialization target."
- Kg-increase: heading "That's a big jump"; body "Adding {increaseKg} kg to your {liftLabel} is
  outside typical progress for {experienceLevel} lifters, even over {weeks} weeks. Consider a
  smaller target or a longer block."
- Volume-floor (Create-time): heading "Some muscle groups will fall below maintenance volume"; body
  "{muscleGroup} would get {weeklySets} sets/week with this specialization, below the
  {minimum}-set minimum for maintenance. You can still create this block."

---

### Volume-floor live-preview surface (D-04/D-06/D-07 rendering half)

**Analog:** `ProgramMuscleVolumeCard` (full file, `program_muscle_volume_card.dart`) — the existing
card shell already used by `program_preview_view.dart` for the exact same
`ProgramVolumeBreakdown`/`MuscleVolumeEntry` data shape.

**Existing call site to mirror** (`program_preview_view.dart:87-90`):
```dart
ProgramMuscleVolumeCard(
  breakdown: breakdown,
  title: 'Weekly Volume per Muscle Group',
),
```

**Row-rendering pattern to copy the *shape* of, but not reuse the private class directly**
(`program_muscle_volume_card.dart:221-263`, `_buildMuscleRow`):
```dart
Widget _buildMuscleRow(ThemeData theme, MuscleVolumeEntry item, double maxSets) {
  final ratio = maxSets > 0 ? (item.sets / maxSets).clamp(0.05, 1.0) : 0.0;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(item.muscle, style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600, // <- UI-SPEC requires the NEW
            )),                            //    instance render this at
            // ...sets/percentage...        //    REGULAR weight instead.
          ],
        ),
        // ...fractional-fill bar (Stack of two Containers)...
      ],
    ),
  );
}
```

**Critical constraint (RESEARCH.md Anti-Pattern + UI-SPEC Typography Exception, both explicit):**
do NOT extend `_ProgramMuscleVolumeCardState._buildMuscleRow` in place, and do NOT thread a new
optional parameter through the existing private `State` class. It is shared with
`program_preview_view.dart`'s unrelated call site and uses `AppColors.*` + `FontWeight.w600` rows.
Build a **new, small, `context.hx`-native widget** for this phase's embedded/live-preview instance,
reusing the row *shape* (label + set-count + percentage + fill bar) but at regular font weight and
`context.hx` tokens, not `AppColors.*`. `VolumeVerdict.low`-flagged rows should tint with
`context.hx.warning` (label "Light", blurb "Below the volume that usually drives progress" — both
render verbatim from `volume_bands.dart:13`, do not invent new labels).

**Empty-state precedent to copy** (`program_muscle_volume_card.dart:39`):
```dart
if (breakdown.isEmpty) return const SizedBox.shrink();
```

## Shared Patterns

### Pure-function guardrail/issue shape
**Source:** `lib/features/programs/domain/program_guardrails.dart` (`ProgramGuardrailIssue`,
`GuardrailSeverity`, `validateConfiguration()` at lines 159-192)
**Apply to:** the new D-06 (volume-floor) and D-11 (kg-ceiling) Create-time checks — same
`List<Issue>`-returning static-method shape, `severity: GuardrailSeverity.warning` only (never
`.blocking` — D-05).

### Warning-tone banner (`context.hx.warning`)
**Source:** `lib/features/programs/presentation/widgets/ai_brief_rejection_banner.dart` (full file)
**Apply to:** all 3 new warning surfaces this phase introduces (timeline shortfall, kg-increase
ceiling, volume-floor shortfall) — both the live-preview and Create-time instances. `Icons.
warning_amber_rounded`, `hx.warning`/`hx.warning.withValues(alpha: .08)`, `HxSpace.x1/x2/x3`,
`HxRadius.mdAll`. Never `context.hx.primary` (accent) or `context.hx.danger` for these surfaces.

### `context.hx` tokens for all NEW code, `AppColors.*` untouched for existing lines
**Source:** UI-SPEC "Design System" section + `ai_brief_rejection_banner.dart`/
`ai_day_rationale_card.dart` (Phase 27 precedent)
**Apply to:** every new `Text`/`Container`/spacing literal this phase adds inside
`step_parameters_specialization.part.dart`, `step_parameters.part.dart`, `dialogs.part.dart`, and
any new widget file. The surrounding pre-existing `AppColors.*` lines in those files are explicitly
out of this phase's migration scope — do not touch them, only avoid adding more.

### `_SlotNeed` switch-on-sticking-point idiom
**Source:** `lib/features/programs/data/smart_program_planner.dart` (`_needsForPrimaryLift`,
squat/deadlift branches, lines 1576-1596)
**Apply to:** the new bench/OHP/pull-up branches in the same function (D-12) — one explicit branch
for the lift's single lift-specific `PrimaryLiftStickingPoint`, one `_` default for the rest.

### `ProgramVolumeCalculator.computeFromTemplates` → `VolumeBands.verdicts()` pipeline
**Source:** `lib/features/programs/domain/program_muscle_volume.dart:468-474` +
`lib/features/programs/domain/volume_bands.dart:154-162`, already composed once in
`program_preview_view.dart` (via `presetProgramVolumeProvider`, not shown here — a
`FutureProvider`-backed one-shot Future, matching the "not a `StreamProvider`" exception documented
in RESEARCH.md for builder-time in-memory state)
**Apply to:** both the D-06 live preview (Step 3+, per the sequencing caveat above) and the D-06
Create-time check in `actions.part.dart`.

## No Analog Found

None. Every file/edit target in this phase has at least a role-match, and the large majority
(9 of 11) have an exact same-file or same-feature analog, because this phase is defined as closing
gaps in an already-live feature rather than building new surfaces. The two items with only a
partial/precedent-based match (the possible new volume-floor preview widget, and whichever banner
variant the planner chooses to build vs. reuse) are flagged above with explicit "planning's call"
notes rather than a hard prescription, per UI-SPEC's own Component Inventory language.

## Metadata

**Analog search scope:** `lib/features/programs/domain/`, `lib/features/programs/data/`,
`lib/features/programs/presentation/views/block_builder_view/`,
`lib/features/programs/presentation/views/program_preview_view.dart`,
`lib/features/programs/presentation/widgets/`, `lib/design_system/tokens/`
**Files read in full or targeted sections:** `primary_lift_specialization.dart`,
`squat_specialization.dart`, `program_guardrails.dart`, `volume_bands.dart`,
`program_muscle_volume.dart` (lines 1-75, 460-563), `smart_program_planner.dart` (lines 1-110,
470-510, 1380-1650, 1830-1852), `step_parameters_specialization.part.dart` (full, 258 lines),
`step_parameters.part.dart` (full, 402 lines), `dialogs.part.dart` (lines 180-270),
`actions.part.dart` (full, 325 lines), `ai_brief_rejection_banner.dart` (full, 77 lines),
`program_muscle_volume_card.dart` (full, 289 lines), `program_preview_view.dart` (lines 1-96),
`split_template.dart` (lines 27-64, `SplitType` enum), `hx_colors.dart` (grep for
`warning`/`danger`/`onSurfaceVariant`), `hx_geometry.dart` (grep for `HxSpace`/`HxRadius`).
**Pattern extraction date:** 2026-09-30
