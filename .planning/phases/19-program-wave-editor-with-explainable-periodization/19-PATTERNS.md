# Phase 19: Program & Wave Editor with Explainable Periodization - Pattern Map

**Mapped:** 2026-09-16
**Files analyzed:** 7 (2 split into subfolders)
**Analogs found:** 7 / 7

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|--------------------|------|-----------|-----------------|---------------|
| `lib/features/programs/presentation/views/block_detail_view.dart` (retrofit + part-split, D-01) | view/controller | CRUD (drift reads via `StreamProvider`, writes via repository) | `lib/features/profile/presentation/profile_view.dart` (part/part-of split shape) + `lib/features/programs/presentation/views/program_review_view.dart` (`_WeekPicker`, wave/scope UI it retrofits from) | exact (split precedent) / role-match (UI retrofit) |
| `lib/features/programs/presentation/views/block_detail_view/_week_picker.part.dart` (or similar, new) | component (part file) | request-response (local `setState` week selection) | `program_review_view.dart` `_WeekPicker` (lines 435-477) | exact |
| `lib/features/programs/presentation/views/block_detail_view/_day_row.part.dart` (or similar, new) | component (part file) | CRUD (repository write + rematerialize) | `block_detail_view.dart` `_DayRow` (existing, being split as-is, lines 528-700) | exact |
| `lib/features/programs/presentation/sheets/exercise_replacement_sheet.dart` (new, extracted, D-02) | component (shared sheet) | request-response (modal bottom sheet returning a selection) | `program_review_view.dart` `ExerciseReplacementSheet`/`_ScopeChoice`/`ExerciseReplacementSelection` (lines 683-941) — verbatim move | exact (source of the extraction) |
| `lib/features/programs/presentation/views/program_review_view.dart` (modified: import extracted sheet, drop inline definition) | view | request-response | itself (pre-extraction) | exact |
| `lib/features/programs/domain/wave_label.dart` (new, D-05) | domain / utility (pure function) | transform | `lib/features/programs/data/programs_repository.dart` `replaceProgramExerciseSlot`'s wave-boundary walk (lines 938-948, read-only reuse) + `program_review_view.dart` `_loadRotations`/`_RotationSegment` (lines 147-218, wave-count segmentation) | role-match (algorithm shape, different tier: domain not data) |
| `lib/features/programs/presentation/views/program_method_guide_view.dart` (modified: `ProgramMethodGuide.forModel` `weeks` data only, D-06) | static data / view (unchanged rendering) | transform (data expansion, no new UI) | itself (`ProgramMethodGuideWeek` list literal, lines 122-323) | exact |
| `test/block_detail_view_test.dart` (new, Wave 0) | test | request-response (widget test) | `test/widgets/exercise_replacement_sheet_test.dart` (existing widget test structure) | role-match |
| `test/wave_label_test.dart` (new, Wave 0) | test | transform (pure function unit test) | `test/program_exercise_replacement_scope_test.dart` (existing unit test against drift schema, wave-boundary-walk assertions) | role-match |

## Pattern Assignments

### `lib/features/programs/presentation/views/block_detail_view.dart` (view, CRUD) — retrofit + split

**Analog for the split mechanics:** `lib/features/profile/presentation/profile_view.dart`

**Part declaration pattern** (`profile_view.dart` lines 35-39):
```dart
part 'profile_view/_auth.part.dart';
part 'profile_view/_body.part.dart';
part 'profile_view/_identity.part.dart';
part 'profile_view/_settings.part.dart';
part 'profile_view/_target_cards.part.dart';
```

**Part-of declaration** (`profile_view/_identity.part.dart` line 1):
```dart
part of '../profile_view.dart';
```

A second precedent for a `data/` file (not `presentation/`) confirms the same convention already lives inside `features/programs/` itself:
```dart
// Source: lib/features/programs/data/smart_program_planner.dart:22-24
part 'smart_program_planner/anchor_lock.part.dart';
part 'smart_program_planner/selection_explanation_writer.part.dart';
part 'smart_program_planner/slot_candidate_resolution.part.dart';
```

**Constraint (both precedents confirm):** part files declare zero imports of their
own — everything a part needs must already be imported at the top of the main file.
`block_detail_view.dart`'s current import block (verified, lines 1-14):
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/app_bottom_sheet.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/features/programs/application/programs_providers.dart';
import 'package:herculex/features/programs/data/programs_repository.dart';
import 'package:herculex/features/programs/domain/periodization.dart';
import 'package:herculex/features/programs/domain/split_template.dart';
import 'package:herculex/features/programs/presentation/sheets/template_picker_sheet.dart';
import 'package:herculex/features/programs/presentation/widgets/program_muscle_volume_card.dart';
import 'package:herculex/features/workouts/application/workouts_providers.dart';
```
Anything the new Week-dropdown/wave-strip/replace-trigger parts need beyond this
(e.g. `ExerciseCatalogData`, the new `exercise_replacement_sheet.dart`,
`ProgramExerciseReplacementScope`, the new `domain/wave_label.dart`) must be added
here, not in a part file.

**Analog for the Week-dropdown retrofit:** `program_review_view.dart` `_WeekPicker` (lines 435-477) — already solves "Week N of M" single-active-week selection with a `DropdownButton`:
```dart
// Source: lib/features/programs/presentation/views/program_review_view.dart:456-476
child: DropdownButtonHideUnderline(
  child: DropdownButton<int>(
    value: selectedWeekIndex,
    isExpanded: true,
    dropdownColor: AppColors.surfaceContainer,
    borderRadius: BorderRadius.circular(16),
    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: AppColors.onSurface,
    ),
    icon: const Icon(Icons.keyboard_arrow_down_rounded),
    onChanged: onChanged,
    items: [
      for (final weekIndex in weekIndices)
        DropdownMenuItem(
          value: weekIndex,
          child: Text('Week ${weekIndex + 1}'),
        ),
    ],
  ),
),
```
Note UI-SPEC requires `titleMedium` (17px/600) for the value text and "Week N of M"
copy (not the review screen's shorter "Week N" — adapt the label string, keep the
widget shape).

**Repository-write → rematerialize pattern (D-04), to reuse for the new per-exercise trigger** (existing in this exact file, `_DayRow._link`, lines 687-693):
```dart
// Source: lib/features/programs/presentation/views/block_detail_view.dart:687-693
Future<void> _link(BuildContext context, WidgetRef ref) async {
  final picked = await TemplatePickerSheet.show(context);
  if (picked == null) return;
  final repo = ref.read(programsRepositoryProvider);
  await repo.setProgramDayTemplate(day.id, picked.id);
  await repo.rematerializeProgram(program.id);
}
```
The new per-exercise replace handler must follow the same two-call shape (open sheet
→ repository write → `rematerializeProgram`), combining it with the pre-commit call
site's `replaceProgramExerciseSlot` invocation (see Shared Patterns below).

**Existing `_DayRow` icon-button sizing to match for the new "Replace this exercise" trigger** (lines 591-602):
```dart
IconButton(
  visualDensity: VisualDensity.compact,
  tooltip: 'Link a template',
  icon: Icon(
    day.templateId == null ? Icons.link_rounded : Icons.swap_horiz_rounded,
    size: 20,
    color: AppColors.primary,
  ),
  onPressed: () => _link(context, ref),
),
```

**Deload/phase-tint pattern to carry into the retrofitted single-week view** (`_WeekCard.build`, lines 352-397):
```dart
final isDeload = Periodization.isPlannedDeload(
  model: PeriodizationModel.fromId(widget.program.periodizationModel),
  totalWeeks: widget.program.weeks,
  weekIndex: widget.week.weekIndex,
);
// ...
color: (isDeload ? AppColors.tertiary : AppColors.primary).withValues(alpha: 0.15),
```

**Data source, unchanged, already `StreamProvider`s** (`lib/features/programs/application/programs_providers.dart:45-57`):
```dart
final programWeeksProvider = StreamProvider.family<List<ProgramWeekData>, int>((
  ref,
  programId,
) {
  return ref.watch(programsRepositoryProvider).watchProgramWeeks(programId);
});

final programDaysProvider = StreamProvider.family<List<ProgramDayData>, int>((
  ref,
  weekId,
) {
  return ref.watch(programsRepositoryProvider).watchProgramDaysForWeek(weekId);
});
```

---

### `lib/features/programs/presentation/sheets/exercise_replacement_sheet.dart` (new, D-02)

**Analog / verbatim source:** `program_review_view.dart` lines 683-941 (`ExerciseReplacementSheet`, `_ExerciseReplacementSheetState`, `ExerciseReplacementSelection`, `_ScopeChoice`).

**Full move — imports needed by the moved code** (cross-reference `program_review_view.dart`'s header, lines 1-17):
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/data/local/database.dart';               // ExerciseCatalogData
import 'package:herculex/design_system/components/components.dart'; // HxSheet
import 'package:herculex/design_system/components/premium_text_field.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/features/programs/data/programs_repository.dart'; // ProgramExerciseReplacementScope
import 'package:herculex/features/workouts/domain/exercise_substitution.dart';
```
(`recentExerciseIdsProvider` is referenced by the state class — confirm its owning
file/import when moving; not yet located in this pass, verify during planning.)

**Core widget shape** (`program_review_view.dart:741-897`, sheet body — scope picker
+ search + ranked list), copy verbatim:
```dart
return HxSheet(
  scrollable: false,
  title: 'Choose a replacement',
  subtitle: 'Biomechanically similar options for ${widget.current.name}.',
  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
  child: SizedBox(
    height: MediaQuery.sizeOf(context).height * .64,
    child: Column(
      children: [
        PremiumTextField(...),
        // "Apply replacement to" + Wrap of three _ScopeChoice pills
        // helper copy switch(_scope) { ... }
        // Expanded ListView.separated of ranked candidates
      ],
    ),
  ),
);
```

**Scope pill widget, copy verbatim** (`program_review_view.dart:912-941`):
```dart
class _ScopeChoice extends StatelessWidget {
  const _ScopeChoice({
    required this.label,
    required this.selected,
    required this.onTap,
    this.recommended = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool recommended;

  @override
  Widget build(BuildContext context) => ChoiceChip(
    label: Text(recommended ? '$label · Recommended' : label),
    selected: selected,
    onSelected: (_) => onTap(),
    selectedColor: AppColors.primary.withValues(alpha: .16),
    side: BorderSide(
      color: selected ? AppColors.primary : AppColors.outlineVariant.withValues(alpha: .55),
    ),
    labelStyle: TextStyle(
      color: selected ? AppColors.primary : AppColors.secondary,
      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
    ),
  );
}
```

**Call-site pattern both `program_review_view.dart` and `block_detail_view.dart` must use after extraction:**
```dart
final selection = await showModalBottomSheet<ExerciseReplacementSelection>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (context) => ExerciseReplacementSheet(current: current, candidates: all),
);
if (selection == null) return;
```

**Test import to update after extraction:** `test/widgets/exercise_replacement_sheet_test.dart` currently imports `ExerciseReplacementSheet` from `package:herculex/features/programs/presentation/views/program_review_view.dart` — repoint to the new `presentation/sheets/exercise_replacement_sheet.dart` path.

**Existing sheet-file-location precedent** confirming `presentation/sheets/` is the
right directory:
`lib/features/programs/presentation/sheets/template_picker_sheet.dart` (already used
by `block_detail_view.dart`'s `_link`).

---

### `lib/features/programs/domain/wave_label.dart` (new, pure function, D-05)

**Analog for the wave-boundary walk algorithm** (`programs_repository.dart:938-948`, read-only reuse — do not duplicate into a widget):
```dart
// Source: lib/features/programs/data/programs_repository.dart:938-948
final activeExerciseId =
    assignmentByWeek[originalWeek.weekIndex]?.exerciseId ?? original.exerciseId;
var waveStart = originalWeek.weekIndex;
var waveEnd = originalWeek.weekIndex;
while (assignmentByWeek[waveStart - 1]?.exerciseId == activeExerciseId) {
  waveStart--;
}
while (assignmentByWeek[waveEnd + 1]?.exerciseId == activeExerciseId) {
  waveEnd++;
}
```
Pitfall 4 (RESEARCH.md) is explicit: keep the `Map<int, RotationAssignmentData?>`
keyed lookup (not a raw `List`) so out-of-range week indices naturally return `null`
and terminate the walk — do not reimplement with manual bounds checks.

**Analog for wave-count segmentation ("Wave X of Y")** (`program_review_view.dart:179-218`, `_loadRotations`'s per-slot segment builder — adapt, don't duplicate verbatim since the target here is a single anchor slot, not all slots):
```dart
// Source: lib/features/programs/presentation/views/program_review_view.dart:184-212
String? activeName;
var start = 0;
for (var week = 0; week < weeks.length; week++) {
  final name = nameById[byWeek[week]?.exerciseId] ?? 'Selected exercise';
  if (activeName == null) {
    activeName = name;
    start = week;
  } else if (name != activeName) {
    segments.add(_RotationSegment(startWeek: start, endWeek: week - 1, exerciseName: activeName));
    activeName = name;
    start = week;
  }
}
if (activeName != null) {
  segments.add(_RotationSegment(startWeek: start, endWeek: weeks.length - 1, exerciseName: activeName));
}
```

**Anchor-slot predicate** (`SlotRole.main`, `lib/features/programs/domain/slot_role.dart:5-19`):
```dart
enum SlotRole {
  main('main', 'Main', 1),
  supplemental('supplemental', 'Supplemental', 2),
  accessory('accessory', 'Accessory', 4),
  isolation('isolation', 'Isolation', 8),
  conditioning('conditioning', 'Conditioning', 16);
  // ...
  static SlotRole fromId(String? id) =>
      values.firstWhere((r) => r.id == id, orElse: () => SlotRole.accessory);
}
```
Filter `programExerciseSlots` rows to `role == SlotRole.main.id` ('main'), then order
by `orderIndex` — matches both `program_review_view.dart:_loadRotations`'s slot query
ordering (`OrderingTerm(expression: t.orderIndex)`, line 154) and
`smart_program_planner/anchor_lock.part.dart`'s `SlotRole.main`-gated anchor logic
(lines 6-32) cited by D-05/A2 in RESEARCH.md. **Open question from RESEARCH.md (A2):**
read `anchor_lock.part.dart` in full during implementation to confirm whether the
intended order is "day order, then slot orderIndex within day" vs. a flat
`orderIndex` sort — this pattern map only confirms the two known reference points,
not the final answer.

**Signature shape to follow** (pure function, no repository/widget dependency —
matches this codebase's other domain pure-function style, e.g. `Periodization.isPlannedDeload`):
```dart
// Source: lib/features/programs/domain/periodization.dart (existing pure static method style)
static bool isPlannedDeload({
  required PeriodizationModel model,
  required int totalWeeks,
  required int weekIndex,
}) { /* ... */ }
```
`computeWaveLabel` should follow this same "named-params static method on a small
domain class, no side effects" shape.

---

### `lib/features/programs/presentation/views/program_method_guide_view.dart` (data-only change, D-06)

**Analog:** itself — `ProgramMethodGuide.forModel`'s existing `weeks` list literal shape (lines 158-179 shown for `linear`):
```dart
weeks: [
  ProgramMethodGuideWeek(
    1,
    'Base',
    'Establish crisp technique and a repeatable working load.',
  ),
  ProgramMethodGuideWeek(
    2,
    'Build',
    'Add a small load or rep improvement while volume stays steady.',
  ),
  // ...
],
```
Rendering is untouched — the loop is purely data-driven:
```dart
// Source: lib/features/programs/presentation/views/program_method_guide_view.dart:54-68
...guide.weeks.map(
  (week) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    color: AppColors.surfaceContainerLowest,
    child: ListTile(
      leading: CircleAvatar(
        backgroundColor: AppColors.primary.withValues(alpha: .12),
        foregroundColor: AppColors.primary,
        child: Text('${week.number}'),
      ),
      title: Text(week.title),
      subtitle: Text(week.description),
    ),
  ),
),
```
Expand each `PeriodizationModel` case's `weeks` list to 8 `ProgramMethodGuideWeek`
entries (block's existing 4 entries — weeks 1/3/5/7 — already carry the correct
phase titles/descriptions; add weeks 2/4/6/8 following the same one-sentence
imperative voice). Per D-06/Pitfall 5, `PeriodizationModel.none` (currently 2 rows,
lines 309-320) is left at planning's discretion — RESEARCH.md recommends keeping it
short since it has no periodization phases to map onto 8 weeks; whichever choice is
made must be stated explicitly in the plan.

---

## Shared Patterns

### Repository write → `rematerializeProgram` (D-04)
**Source:** `lib/features/programs/presentation/views/block_detail_view.dart:687-693` (`_DayRow._link`) and `:695-699` (`_DayRow._remove`)
**Apply to:** the new post-commit per-exercise replacement handler in
`block_detail_view.dart`
```dart
final repo = ref.read(programsRepositoryProvider);
await repo.replaceProgramExerciseSlot(
  programDayExerciseId: item.row.id,
  replacementExerciseId: selection.exercise.id,
  scope: selection.scope,
);
await repo.rematerializeProgram(program.id); // default futureOnly: true — never pass false here
```
**Critical distinction:** `program_review_view.dart`'s pre-commit call site
(`_chooseReplacement`, lines 221-246) does NOT call `rematerializeProgram` — nothing
is materialized yet at review stage. Copying that call site verbatim into
`block_detail_view.dart` silently drops the required follow-up call (RESEARCH.md
Pitfall 3). The post-commit site must add the `rematerializeProgram` line.

### Scoped exercise replacement (`ProgramExerciseReplacementScope`)
**Source:** `lib/features/programs/data/programs_repository.dart:41-45, 883-1040`
**Apply to:** both `program_review_view.dart` and `block_detail_view.dart` replacement call sites — fully implemented, zero changes needed.
```dart
enum ProgramExerciseReplacementScope {
  thisWave,
  thisAndFutureWaves,
  entireBlock,
}
```

### `AppColors` static shim (unchanged this phase)
**Source:** used throughout `block_detail_view.dart` and `program_review_view.dart`
(e.g. `AppColors.surfaceContainer`, `AppColors.primary`, `AppColors.secondary`).
**Apply to:** all edits within these two existing files — per UI-SPEC, do NOT do a
drive-by `AppColors` → `HxColors`/`context.hx` migration here (separate
`docs/ui-rework/` Phase 9 track owns that). New files (`exercise_replacement_sheet.dart`
verbatim-moved content keeps `AppColors.*` as-is since it's a move, not a rewrite;
`wave_label.dart` has no UI/color surface at all) may use `context.hx` at the
executor's discretion only where there is no existing convention to preserve.

### Deload/phase tint
**Source:** `lib/features/programs/presentation/views/block_detail_view.dart:352-397` (`_WeekCard`), using `lib/features/programs/domain/periodization.dart` `Periodization.isPlannedDeload`
**Apply to:** the retrofitted single-active-week view's Week dropdown / wave-strip tinting, per UI-SPEC's explicit carry-over instruction.

## No Analog Found

None — every file this phase touches has a direct, already-built analog in this
exact codebase (this phase is extraction/retrofit, not new architecture, per
RESEARCH.md).

## Metadata

**Analog search scope:** `lib/features/programs/` (data, domain, presentation/views,
presentation/sheets), `lib/features/profile/presentation/profile_view.dart` (split
precedent), `test/` (existing coverage for updated import paths).
**Files scanned:** `block_detail_view.dart`, `program_review_view.dart`,
`program_method_guide_view.dart`, `programs_repository.dart` (targeted ranges),
`slot_role.dart`, `profile_view.dart` (header), `smart_program_planner.dart`
(header), `smart_program_planner/anchor_lock.part.dart` (targeted grep),
`programs_providers.dart` (targeted ranges).
**Pattern extraction date:** 2026-09-16
