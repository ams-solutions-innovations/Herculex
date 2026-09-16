# Phase 19: Program & Wave Editor with Explainable Periodization - Research

**Researched:** 2026-09-16
**Domain:** Flutter/Riverpod/drift program editor retrofit — no new libraries, pure internal refactor + data-flow wiring
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** `block_detail_view.dart` (currently 710 lines, already over CLAUDE.md's 600-line hand-written-file limit) is retrofitted into the Week/Wave editor rather than building a separate `program_editor_view.dart`. Its `_WeekCard`-per-week scrollable list is replaced with a Week dropdown showing one active week at a time, plus a wave indicator strip. Split the file with `part`/`part of` into a subfolder (per CLAUDE.md) as part of this work, keeping the public import path unchanged.
- **D-02:** The `ExerciseReplacementSheet` and its `_ScopeChoice` widget, currently defined inline in `program_review_view.dart`, are extracted into a shared presentation widget/sheet file. Both `program_review_view.dart` (pre-commit) and the retrofitted `block_detail_view.dart` (post-commit) import the same sheet — no duplicated scope-picker UI.
- **D-03:** The day-level "link a template" swap (the `swap_horiz`/`link` icon in `_DayRow`, which relinks a whole day to a different `WorkoutTemplateData`) stays available on every day regardless of whether it already has exercises — it is a different, coarser operation than the new per-exercise replacement sheet; both coexist. Per-exercise replacement is the new, additional action; it does not remove or hide the day-level link icon.
- **D-04:** When `replaceProgramExerciseSlot` is invoked from the post-commit editor (not just pre-commit review), the caller follows it with `rematerializeProgram(programId)` — the exact same pattern `block_detail_view.dart`'s existing day-level swap already uses. `replaceProgramExerciseSlot` itself continues to only touch the `ProgramDayExercises` blueprint and `rotationAssignments`; it does not need to change to satisfy EDIT-03. `rematerializeProgram`'s existing "from today forward" boundary is accepted as-is for EDIT-03 — no separate status-based (planned/moved) filtering is added in this phase.
- **D-05:** The single "Exercise wave X of Y · Weeks A–B" label shown alongside "Week N of M" is computed from one anchor slot's `rotationAssignments`, not derived by merging all slots' wave boundaries. The anchor slot is the first `SlotRole.main` slot encountered in the week's own day/slot ordering (deterministic, matches the ordering Phase 17's anchor-lift-guarantee logic already walks). If a block has multiple `SlotRole.main` slots across different days, only the first one in iteration order drives the displayed wave label.
- **D-06:** `program_method_guide_view.dart`'s "Example block" section is expanded from today's 4 abbreviated milestone `ProgramMethodGuideWeek` entries per model to a literal one-row-per-week rendering for all 8 weeks, for every `PeriodizationModel` (linear, concurrent, block, maxEffort, none). Block periodization's phase transitions (accumulation → transmutation → realization) land on their real week numbers instead of being implied by gaps between milestone weeks 1/3/5/7.

### Claude's Discretion

- Exact Week-dropdown widget choice (`DropdownButton` vs a custom sheet/picker) and where the wave-strip visually sits relative to it — left to planning/UI work as long as EDIT-01's "Week N of M" + "Exercise wave X of Y · Weeks A–B" separation is met.
- Exact file/folder name for the `part`/`part of` split of `block_detail_view.dart` (D-01) and for the extracted shared replacement-sheet file (D-02).
- Whether `PeriodizationModel.none`'s guide (which today only shows 2 "Stable" milestone weeks, not tied to an 8-week block) also expands to 8 rows or keeps its shorter, non-periodized framing — left to planning, since "none" has no periodization phases to map onto week numbers.
- Exact wording/content for weeks that fall between today's existing milestone entries (e.g. Linear's currently-undescribed weeks 5–8, Block's weeks 2/4/6/8) — left to implementation as long as every week 1–8 has a row.

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| EDIT-01 | Program viewer renders single active week with dedicated Week dropdown and exercise wave indicators (`Week N of M`, `Wave X of Y`) | `block_detail_view.dart`'s existing `_WeekCard`/`programWeeksProvider` give the data layer for free; `program_review_view.dart`'s `_WeekPicker` (`DropdownButton`) is a direct UI precedent to reuse. New: D-05's anchor-slot wave-label pure function (see Pattern 3, `domain/wave_label.dart`) |
| EDIT-02 | Exercise replacements offer scoped choices: `thisWave`, `thisAndFutureWaves`, or `entireBlock` | Fully implemented already in `programs_repository.dart` (`ProgramExerciseReplacementScope`, `replaceProgramExerciseSlot`) and `program_review_view.dart` (`ExerciseReplacementSheet`); this phase's work is extraction (D-02) + new post-commit call site (D-04) |
| EDIT-03 | Program edits never mutate or overwrite previously started or completed workout occurrences | `rematerializeProgram`/`materializeProgram` already delete-and-rebuild only `status='planned' AND completedSessionId IS NULL` rows, optionally date-bounded — this property is inherent to the existing implementation, not new logic; see Pattern 2 and Pitfall 3 |
| EDIT-04 | Periodization options (Linear, Concurrent, Westside, Block) display dedicated educational guides with 8-week examples | `ProgramMethodGuide.forModel`'s `weeks` data list is the only piece that changes (D-06); `program_method_guide_view.dart`'s rendering is already a data-driven loop needing zero changes; `Periodization.plan`/block-phase percentages inform correct phase-transition week numbers |
</phase_requirements>

## Summary

This phase has no external-library risk: every capability EDIT-01–04 needs already exists
somewhere in `lib/features/programs/` — the work is extraction, reuse, and UI retrofit, not
new architecture. `replaceProgramExerciseSlot` and `ProgramExerciseReplacementScope`
(`thisWave`/`thisAndFutureWaves`/`entireBlock`) are fully implemented and tested against a
real drift schema in `programs_repository.dart` (lines 41-1049); `ExerciseReplacementSheet`
is fully implemented in `program_review_view.dart` (lines ~680-940); `rematerializeProgram`
already guarantees EDIT-03's "never mutate started workouts" property as a side effect of how
`materializeProgram` is written, not as new logic this phase must build. `SlotRole.main` (the
anchor for D-05's wave label) is an existing domain enum with an existing consumer pattern in
`smart_program_planner/anchor_lock.part.dart`. The `part`/`part of` split convention CLAUDE.md
requires for `block_detail_view.dart` already has three precedents in this exact codebase
(`profile_view.dart` → `profile_view/_*.part.dart`, `smart_program_planner.dart` →
`smart_program_planner/*.part.dart`).

The one genuinely new piece of domain logic is D-05's anchor-slot wave-label computation
(first `SlotRole.main` slot in day/slot iteration order, walk its `rotationAssignments` to
find the contiguous wave containing the currently-viewed week) — this is a small, pure
function over already-loaded data, not a new repository method, and can be tested in
isolation the same way `program_exercise_replacement_scope_test.dart` already tests
`replaceProgramExerciseSlot`'s wave-boundary walk.

**Primary recommendation:** Retrofit `block_detail_view.dart` in place (do not create a new
route/view file); extract `ExerciseReplacementSheet`+`_ScopeChoice` verbatim into a new shared
file under `lib/features/programs/presentation/sheets/`; add a pure `computeWaveLabel`-style
helper (new file, e.g. `lib/features/programs/domain/wave_label.dart`) for D-05 rather than
inlining the anchor-walk into the widget; expand `ProgramMethodGuide.forModel`'s `weeks` list
data only — the guide view's rendering code needs zero changes.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Week dropdown / single-active-week rendering (EDIT-01) | Presentation (`block_detail_view.dart`) | Application (`programWeeksProvider`, `programDaysProvider` — already exist) | Pure UI state (`selectedWeekIndex`); no new data needed, only re-rendering scope |
| Wave-indicator label computation (EDIT-01, D-05) | Domain (new pure function) | Data (`rotationAssignments`, `programExerciseSlots` reads) | Deterministic derivation from already-fetched rows; belongs in domain so it is unit-testable without a widget harness |
| Per-exercise replacement trigger + sheet (EDIT-02) | Presentation (extracted shared sheet) | Data (`replaceProgramExerciseSlot`) | UI already built in `program_review_view.dart`; only the call site and file location are new |
| Replacement scope semantics (`thisWave`/etc.) (EDIT-02) | Data (`programs_repository.dart`) | — | Fully implemented; zero changes needed for EDIT-02 itself |
| Post-commit propagation safety (EDIT-03) | Data (`rematerializeProgram`/`materializeProgram`) | — | Existing "planned + future-only" delete/rebuild boundary already satisfies EDIT-03; do not add a new status-filter layer (explicitly rejected in D-04) |
| Periodization guide 8-week content (EDIT-04) | Domain/static data (`ProgramMethodGuide.forModel`) | Presentation (`program_method_guide_view.dart`, unchanged) | Pure data expansion; the guide view is a dumb renderer over this data already |

## Standard Stack

No new packages. This phase touches only first-party code in `lib/features/programs/`.
`flutter analyze`/`flutter test`/`dart run tool/check_structure.dart` remain the only tooling
involved (per CLAUDE.md commands). No `pubspec.yaml` changes are expected — do not add one.

### Package Legitimacy Audit

Not applicable — no external packages are installed by this phase. Skip the legitimacy gate.

## Architecture Patterns

### System Architecture Diagram

```
BlockDetailView (retrofitted)
  │
  ├─ Week dropdown (new: selectedWeekIndex local state)
  │     │
  │     ▼
  ├─ programWeeksProvider(programId) ──┐  (existing StreamProvider, unchanged)
  │                                    │
  │     ┌──────────────────────────────┘
  │     ▼
  ├─ single active _WeekCard-equivalent (existing widget body, now shown once)
  │     │
  │     ├─ Wave-strip label ── computeWaveLabel(anchorSlot rows, weekIndex)  [NEW pure fn]
  │     │        reads: programExerciseSlots (role='main', first in day/slot order)
  │     │               rotationAssignments (per-week exerciseId for that slot)
  │     │
  │     └─ _DayRow (existing)
  │           ├─ "Link a template" icon (existing, unchanged, D-03: stays always-visible)
  │           └─ per-exercise row
  │                 └─ NEW "Replace this exercise" icon
  │                       │  tap →
  │                       ▼
  │                 ExerciseReplacementSheet (EXTRACTED, shared with program_review_view.dart)
  │                       │  on selection →
  │                       ▼
  │                 programsRepository.replaceProgramExerciseSlot(scope: …)
  │                       │
  │                       ▼
  │                 programsRepository.rematerializeProgram(programId)
  │                       │  (deletes/rebuilds only status='planned' AND dateIso >= today)
  │                       ▼
  │                 ScheduledWorkouts rows: past/started/completed rows untouched (EDIT-03)
  │
  └─ "?" navigation → ProgramMethodGuideView(model)
        └─ ProgramMethodGuide.forModel(model).weeks  [EXPANDED to 8 rows per D-06]
              rendered by existing Card/ListTile/CircleAvatar loop — no view changes
```

### Recommended Project Structure

```
lib/features/programs/
├── domain/
│   ├── periodization.dart                 # unchanged — Block phase source of truth for D-06 wording
│   ├── slot_role.dart                     # unchanged — SlotRole.main reused for D-05
│   └── wave_label.dart                    # NEW: pure anchor-slot wave-label computation (D-05)
├── data/
│   └── programs_repository.dart           # unchanged for EDIT-02/03 — already correct
├── presentation/
│   ├── sheets/
│   │   ├── template_picker_sheet.dart     # existing precedent for sheet file location
│   │   └── exercise_replacement_sheet.dart # NEW: extracted from program_review_view.dart (D-02)
│   └── views/
│       ├── program_review_view.dart       # updated: imports the extracted sheet instead of defining it
│       ├── program_method_guide_view.dart # unchanged rendering; only forModel() weeks data grows
│       └── block_detail_view/             # NEW subfolder for part/part-of split (D-01)
│           ├── _week_card.part.dart       # or similar — exact naming is Claude's discretion
│           └── _day_row.part.dart
└── application/
    └── programs_providers.dart            # unchanged — existing providers already sufficient
```

### Pattern 1: `part`/`part of` split for a >600-line hand-written file

**What:** CLAUDE.md forbids hand-written files over 600 lines; the fix is `part`/`part of`
into a subfolder named after the file, keeping the public import path unchanged.
**When to use:** `block_detail_view.dart` is already 710 lines before this phase's additions
(Week dropdown, wave-strip, per-exercise replace trigger will add more).
**Example (existing precedent in this codebase):**
```dart
// Source: lib/features/profile/presentation/profile_view.dart:35-39
part 'profile_view/_auth.part.dart';
part 'profile_view/_body.part.dart';
part 'profile_view/_identity.part.dart';
part 'profile_view/_settings.part.dart';
part 'profile_view/_target_cards.part.dart';
```
```dart
// Source: lib/features/profile/presentation/profile_view/_identity.part.dart:1
part of '../profile_view.dart';
```
**Constraint:** parts cannot have their own imports (CLAUDE.md) — anything a part widget needs
must already be imported in the main file (`block_detail_view.dart`). Verify current imports
(`drift`, `flutter_riverpod`, `database.dart`, `design_system/components.dart`,
`design_system/theme/colors.dart`, `haptics.dart`, `programs_providers.dart`,
`programs_repository.dart`, `periodization.dart`, `split_template.dart`,
`template_picker_sheet.dart`, `program_muscle_volume_card.dart`, `workouts_providers.dart`)
cover everything the split-out parts will need, or add to the main file's import list before
splitting.
**A second precedent exists** for a `data/` (not `presentation/`) file:
`lib/features/programs/data/smart_program_planner.dart` →
`smart_program_planner/{anchor_lock,slot_candidate_resolution,selection_explanation_writer}.part.dart`
— confirms the pattern is already used inside `features/programs/` itself, including for logic
adjacent to `ProgramExerciseSlots`/rotation concerns this phase also touches.

### Pattern 2: Repository write → `rematerializeProgram` (existing, reused as-is)

**What:** Every mutation that should reach future materialized sessions is followed by
`repo.rematerializeProgram(program.id)`. This is already the pattern for
`setProgramDayTemplate` (day-level link swap, `_DayRow._link`) and `deleteProgramDay`
(`_DayRow._remove`).
**When to use:** D-04 requires the exact same two-call pattern for the new per-exercise
replacement trigger.
**Example:**
```dart
// Source: lib/features/programs/presentation/views/block_detail_view.dart:687-693 (existing)
Future<void> _link(BuildContext context, WidgetRef ref) async {
  final picked = await TemplatePickerSheet.show(context);
  if (picked == null) return;
  final repo = ref.read(programsRepositoryProvider);
  await repo.setProgramDayTemplate(day.id, picked.id);
  await repo.rematerializeProgram(program.id);
}
```
```dart
// Source: lib/features/programs/presentation/views/program_review_view.dart:236-245 (existing,
// pre-commit call site — the pattern EDIT-02's post-commit call site must mirror, MINUS
// rematerializeProgram, which program_review_view.dart doesn't need because nothing is
// materialized yet at review stage)
await ref.read(programsRepositoryProvider).replaceProgramExerciseSlot(
  programDayExerciseId: item.row.id,
  replacementExerciseId: selection.exercise.id,
  scope: selection.scope,
);
Haptics.selection();
await _load();
```
The new post-commit call site in `block_detail_view.dart` must combine both: call
`replaceProgramExerciseSlot`, THEN `rematerializeProgram(program.id)` — this is the delta
D-04 requires and the only place `programs_repository.dart` itself is *not* expected to
change.

### Pattern 3: Wave-boundary walk (existing algorithm, reuse the logic shape for D-05)

`replaceProgramExerciseSlot` already computes `waveStart`/`waveEnd` by walking
`rotationAssignments` outward from the target week while `exerciseId` stays constant
(`programs_repository.dart:941-948`). D-05's wave-label needs the same walk, but read-only and
against the *anchor* slot (first `SlotRole.main` slot in iteration order) rather than the
slot being edited:
```dart
// Source: lib/features/programs/data/programs_repository.dart:938-948 (existing, read-only
// reuse pattern for the new wave_label.dart helper — do not duplicate this into the widget)
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
**Anchor slot selection (D-05):** the first `programExerciseSlots` row with
`role == SlotRole.main.id` (`'main'`), ordered the same way the day/slot iteration already
orders things elsewhere in this file (`orderIndex` on `programExerciseSlots`, then
`daySlotLabel`/day ordering) — reuse `ProgramExerciseSlots.orderIndex` as the tie-breaker
rather than inventing a new ordering, since it is already the column Phase 17's anchor-lift
logic and `program_review_view.dart:_loadRotations` both order by
(`programs_repository.dart` / `program_review_view.dart:154`).
**"Wave X of Y" numbering:** derive `Y` (total wave count) by walking the *entire* week range
with the same contiguous-run logic (not just locating the one wave containing the current
week) — segment the full `assignmentByWeek` sequence into contiguous runs, count them, and
find which 1-based run index contains the currently-viewed week. `program_review_view.dart`'s
`_loadRotations`/`_RotationLine`/`_RotationSegment` (lines 179-218) already does exactly this
segmentation for its "planned changes" bottom sheet — reuse or adapt that segmentation
function rather than reimplementing wave-counting from scratch.

### Anti-Patterns to Avoid

- **Don't fork `replaceProgramExerciseSlot` or add a new repository method for the post-commit
  case.** D-04 is explicit: the existing method is correct as-is; only the call site adds
  `rematerializeProgram` after it.
- **Don't compute the wave label by merging all slots' boundaries** (D-05 explicitly rejected
  "most common wave boundary across all slots" as an option) — anchor to the first
  `SlotRole.main` slot only.
- **Don't hide/remove the day-level "link a template" icon** once per-exercise replacement
  exists (D-03) — both actions coexist unconditionally.
- **Don't redesign `ExerciseReplacementSheet`'s visuals during extraction** — D-02 and the
  UI-SPEC both require the extraction to be behaviorally/pixel identical; this is a file move,
  not a redesign.
- **Don't give `PeriodizationModel.none` exactly the same 8-row treatment as periodized models
  without deciding first** — D-06 explicitly leaves this open; document the choice made,
  don't silently default without a note in the plan.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Scoped exercise replacement (thisWave/thisAndFutureWaves/entireBlock) | A new mutation method or scope enum | `ProgramExerciseReplacementScope` + `replaceProgramExerciseSlot` (`programs_repository.dart:41,883`) | Already implements the exact wave-boundary-walk semantics the blueprint's `A,A,B,B`→`C,C,B,B`/`C,C,C,C` acceptance criteria require, and is already covered by `test/program_exercise_replacement_scope_test.dart` |
| Replacement candidate ranking/search UI | A new picker widget | `ExerciseReplacementSheet` (to be extracted) + `ExerciseSubstitution.getRankedSubstitutes` | Fully built, already handles search, recency ranking, and match-percentage display |
| Future-schedule regeneration that must not touch started/completed sessions | New status-aware filtering logic | `rematerializeProgram`/`materializeProgram` (already deletes only `status='planned' AND completedSessionId IS NULL`, optionally date-bounded) | This *is* EDIT-03's safety property already; D-04 explicitly declines to add a second filtering layer |
| Deload/phase labelling for the wave strip | New deload-detection logic | `Periodization.isPlannedDeload` (`domain/periodization.dart:65`) | Already used by `_WeekCard`'s existing deload pill; reuse for the retrofitted single-week view's tinting per the UI-SPEC's `isDeload`/phase-tint carry-over note |

**Key insight:** Every "don't hand-roll" item in this phase is an existing, tested piece of
this exact codebase — the risk profile is almost entirely about correct wiring and file
layout, not new algorithm design.

## Common Pitfalls

### Pitfall 1: Treating `block_detail_view.dart`'s line-count problem as blocking, not concurrent
**What goes wrong:** Splitting the file first as a separate mechanical step, then adding
EDIT-01/02/05 features in a second pass, doubles the diff surface and risks the split landing
with dead/duplicate state.
**Why it happens:** It looks safer to "clean up first."
**How to avoid:** Plan the split and the new Week-dropdown/wave-strip/replace-trigger as one
coordinated change — decide the part boundaries (e.g. `_week_card.part.dart` owns the new
Week dropdown + wave strip, `_day_row.part.dart` owns the new per-exercise trigger) up front,
per D-01.
**Warning signs:** A plan that has "split file" as its own standalone task with no other logic
changes attached.

### Pitfall 2: Forgetting `part` files cannot have their own imports
**What goes wrong:** A part file references a symbol (e.g. `Haptics`, `AppColors`,
`ProgramExerciseReplacementScope`) not already imported in `block_detail_view.dart`'s header,
causing an analyzer error only visible after the split.
**Why it happens:** Content moved verbatim from `program_review_view.dart` (which has a
different import list) into a new part file under `block_detail_view.dart`.
**How to avoid:** Before moving code, diff the import lists of `program_review_view.dart` and
`block_detail_view.dart` — anything the moved `ExerciseReplacementSheet`-triggering code needs
(e.g. `ExerciseCatalog`, `appDatabaseProvider`) must be added to `block_detail_view.dart`'s
own import block, not to the part file.
**Warning signs:** `flutter analyze` reporting undefined identifiers only in the new part
file.

### Pitfall 3: Double-materializing or skipping `rematerializeProgram` on the new replace path
**What goes wrong:** Either forgetting the `rematerializeProgram` call after
`replaceProgramExerciseSlot` (leaving already-materialized future sessions stale — EDIT-03's
"edits reach future planned work" implicitly assumed by the blueprint) or calling it with
`futureOnly: false` (which would violate EDIT-03 by touching past sessions).
**Why it happens:** `program_review_view.dart`'s pre-commit call site does NOT call
`rematerializeProgram` (nothing is materialized yet before confirm) — copying that call site
verbatim into the post-commit editor silently drops the needed follow-up call.
**How to avoid:** Post-commit call site must be
`await repo.replaceProgramExerciseSlot(...); await repo.rematerializeProgram(program.id);`
using the default `futureOnly: true`. Never pass `futureOnly: false` from this phase's new
call site — that parameter is reserved for the initial-confirm materialization in
`program_review_view.dart:_confirm` (`rematerializeProgram(widget.programId, futureOnly: false)`)
which is a one-time "this program has never been scheduled before" case, not applicable here.
**Warning signs:** A widget test where replacing an exercise updates `programDayExercises`
correctly but the day's live `_DayRow` exercise summary (fed from
`programDayExerciseSummariesProvider`, a `StreamProvider`) doesn't refresh until the day is
scrolled off/on screen — a live-provider staleness smell distinct from a materialization bug,
but often mistaken for one; verify with a `ScheduledWorkouts` row check, not just a UI glance.

### Pitfall 4: Wave-count/label off-by-one at block boundaries
**What goes wrong:** "Wave X of Y" mislabels when the anchor slot's rotation is a single
exercise for the whole block (Y should be 1) or when a wave starts/ends exactly at week
0/last-week boundaries (`assignmentByWeek[waveStart - 1]` correctly returns `null` and stops
the walk — but a naive reimplementation might not guard the array-index case the same way).
**Why it happens:** The existing walk in `replaceProgramExerciseSlot` relies on
`Map<int, RotationAssignmentData>` lookups returning `null` for out-of-range week indices,
which naturally terminates the while-loop — a list-based reimplementation without this null
safety would need explicit bounds checks.
**How to avoid:** Reuse a `Map<int, RotationAssignmentData?>`-keyed lookup structure (as the
existing code does), not a raw `List` indexed by week, when building the D-05 helper.
**Warning signs:** A unit test with a single-wave (no rotation) block showing "Wave 1 of 4"
instead of "Wave 1 of 1", or a crash/incorrect result at week 0 or the final week.

### Pitfall 5: `PeriodizationModel.none`'s guide left inconsistent
**What goes wrong:** Expanding every model's `weeks` list to 8 rows except silently leaving
`none` at its current 2 rows (or vice versa) without the plan explicitly recording which
choice was made — D-06 leaves this to discretion but the plan must still pick one and record
it, or the plan-checker/verify-work step will flag an unexplained asymmetry.
**How to avoid:** Plan should explicitly state the `none` decision (recommend: keep it short,
since it has no periodization phases to map onto 8 weeks — this matches the existing
`ProgramMethodGuide` copy, "No periodization gives you a stable template", which is
fundamentally not an 8-week narrative).
**Warning signs:** `program_method_guide_test.dart`'s existing loop
(`for (final model in PeriodizationModel.values) { expect(guide.weeks, isNotEmpty); ... }`)
will still pass either way — it does NOT enforce a specific row count today, so this pitfall
won't be caught by the existing test; a new assertion should be added per-model (e.g.
`expect(guide.weeks.length, 8)` for the four periodized models) to lock in the decision.

## Code Examples

### Extracting `ExerciseReplacementSheet` (D-02) — target file shape

```dart
// NEW FILE: lib/features/programs/presentation/sheets/exercise_replacement_sheet.dart
// Move verbatim from program_review_view.dart lines ~680-940:
//   - ExerciseReplacementSheet (StatefulWidget) + its State class
//   - ExerciseReplacementSelection (result type)
//   - _ScopeChoice (private widget used only by the sheet)
// program_review_view.dart then imports this file and drops the moved code.
// block_detail_view.dart (or its new part file) imports the same file and calls:
final selection = await showModalBottomSheet<ExerciseReplacementSelection>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (context) => ExerciseReplacementSheet(current: current, candidates: all),
);
if (selection == null) return;
final repo = ref.read(programsRepositoryProvider);
await repo.replaceProgramExerciseSlot(
  programDayExerciseId: item.row.id, // the tapped ProgramDayExerciseData.id
  replacementExerciseId: selection.exercise.id,
  scope: selection.scope,
);
await repo.rematerializeProgram(program.id); // the delta vs. program_review_view.dart's call site
```

### Test files requiring an import-path update after D-02's extraction

`test/widgets/exercise_replacement_sheet_test.dart` currently imports
`ExerciseReplacementSheet` from
`package:herculex/features/programs/presentation/views/program_review_view.dart`
(line 7) — this import must change to the new extracted file's path once D-02 lands, or the
test will fail to compile (the symbol will no longer be exported from
`program_review_view.dart` unless that file re-exports it, which is not recommended — update
the import instead).

## State of the Art

Not applicable in the usual sense (no external library churn) — the relevant "state of the
art" is intra-repo: Phase 17/18 already built every primitive this phase assembles.

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|---------------|--------|
| All-weeks scrollable `_WeekCard` list in `block_detail_view.dart` | Single active-week view with Week dropdown + wave strip (this phase, D-01) | Phase 19 | Matches the pre-commit review screen's `_WeekPicker` pattern (`program_review_view.dart:435`), which already solved the "one week at a time" UX this phase needs — reuse its `DropdownButton` shape rather than inventing a new one |
| Exercise replacement only available pre-commit (`program_review_view.dart`) | Also available post-commit in the retrofitted editor (EDIT-02) | Phase 19 | `replaceProgramExerciseSlot`/`rematerializeProgram` were already written generically enough to support this without repository changes |
| Guide shows 4 abbreviated milestone weeks | Guide shows all 8 weeks literally (EDIT-04/D-06) | Phase 19 | Data-only change to `ProgramMethodGuide.forModel`; zero UI-layer changes needed |

**Deprecated/outdated:** None — no library versions or deprecated APIs are involved in this
phase.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The existing `program_review_view.dart` `_loadRotations`/`_RotationSegment` wave-segmentation logic (lines 147-218) can be reused/adapted for D-05's "Wave X of Y" total-count derivation rather than writing it from scratch | Pattern 3 | Low — worst case the planner writes a small new pure function instead of adapting the existing one; behavior is still achievable, just slightly more code than necessary |
| A2 | `ProgramExerciseSlots.orderIndex` combined with existing day/slot ordering is the correct deterministic tie-breaker for "first `SlotRole.main` slot in the week's own day/slot ordering" per D-05 | Pattern 3 | Medium — if the intended ordering is actually day-of-week first then slot orderIndex (not the reverse), the anchor slot chosen could differ from what Phase 17's anchor-lift logic uses; verify against `smart_program_planner/anchor_lock.part.dart`'s exact iteration order before finalizing the helper, since CONTEXT.md D-05 explicitly says this must match "the ordering Phase 17's anchor-lift-guarantee logic already walks" |
| A3 | No `pubspec.yaml`/dependency changes are needed for this phase | Standard Stack | Low — this is a pure refactor phase confirmed by reading all five canonical-ref files; would only be wrong if planning discovers a genuinely new UI primitive is needed beyond what UI-SPEC already scopes to existing `design_system/` components |

**If this table is empty:** N/A — see above.

## Open Questions (RESOLVED)

1. **Exact iteration order Phase 17's anchor-lift logic uses for "first `SlotRole.main` slot
   encountered in week order"**
   - What we know: `program_review_view.dart:_loadRotations` orders `programExerciseSlots` by
     `orderIndex` alone (not grouped by day first). `anchor_lock.part.dart` exists in
     `smart_program_planner/` and is the canonical reference D-05 cites but was not read in
     full during this research pass (file not opened — only located).
   - What's unclear: Whether "day order, then slot order within day" and "global slot
     orderIndex order" produce the same result for a typical block (they likely do, if
     `orderIndex` is assigned day-by-day during generation, but this should be confirmed by
     reading `anchor_lock.part.dart` directly during planning).
   - Recommendation: Planner or executor should read
     `lib/features/programs/data/smart_program_planner/anchor_lock.part.dart` directly before
     writing the D-05 helper, to confirm the exact ordering predicate rather than inferring it
     from `program_review_view.dart`'s incidental usage.
   - **RESOLVED:** Plan 19-01 Task 1 locks in day-then-orderIndex ordering via explicit test
     assertions in `test/wave_label_test.dart`.

2. **`PeriodizationModel.none`'s guide row count**
   - What we know: D-06 explicitly defers this to planning discretion.
   - What's unclear: Whether the plan will keep it at 2 rows or expand it.
   - Recommendation: Plan should state the choice explicitly (this research recommends keeping
     it short — see Pitfall 5) so the copywriting contract's "no TBD/duplicate description"
     rule has a concrete row count to apply to.
   - **RESOLVED:** Plan 19-03 Task 1 keeps `none` at 2 rows, with an in-code comment
     documenting the choice.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | `flutter_test` (bundled with Flutter SDK) |
| Config file | none — standard `flutter test` discovery over `test/` |
| Quick run command | `flutter test test/program_exercise_replacement_scope_test.dart test/program_method_guide_test.dart` |
| Full suite command | `flutter test` (redirect to a file per CLAUDE.md — do not pipe to `tail`, it loses the exit code) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| EDIT-01 | Single active week renders with Week dropdown + "Week N of M" / "Exercise wave X of Y · Weeks A–B" labels, never merged | widget | `flutter test test/block_detail_view_test.dart` | ❌ Wave 0 — no existing widget test file for `block_detail_view.dart` |
| EDIT-01 | Wave-label computation (anchor-slot walk, wave count/boundaries) | unit | `flutter test test/wave_label_test.dart` | ❌ Wave 0 — new pure-function test for the new `domain/wave_label.dart` helper |
| EDIT-02 | Post-commit replacement applies `thisWave`/`thisAndFutureWaves`/`entireBlock` scopes correctly | unit (repository) | `flutter test test/program_exercise_replacement_scope_test.dart` | ✅ exists — already covers `replaceProgramExerciseSlot`'s scope semantics against a real drift schema; extend if the post-commit call site needs distinct coverage of the `rematerializeProgram` follow-up |
| EDIT-02 | Extracted `ExerciseReplacementSheet` renders identically at both call sites | widget | `flutter test test/widgets/exercise_replacement_sheet_test.dart` | ✅ exists — update its import (see Pitfall/Code Examples section) after extraction; add a second call-site smoke test from `block_detail_view.dart` if the plan wants call-site parity verified directly |
| EDIT-03 | Started/completed `ScheduledWorkouts` rows are untouched by a post-commit replacement + rematerialize | unit (repository) | `flutter test test/program_exercise_replacement_scope_test.dart` (extend) or a new focused test | ❌ Wave 0 — no existing test asserts this specific "replace then rematerialize leaves in_progress/done rows alone" interaction; `materializeProgram`'s general "survivors" behavior is implicit, not directly asserted for this call sequence |
| EDIT-04 | Every `PeriodizationModel` guide has exactly 8 week rows (or the deliberately-chosen exception for `none`) | unit | `flutter test test/program_method_guide_test.dart` | ✅ exists but needs a new assertion — current test only checks `guide.weeks` is non-empty, not a row count; add `expect(guide.weeks.length, 8)` per periodized model |

### Sampling Rate
- **Per task commit:** `flutter test test/program_exercise_replacement_scope_test.dart test/program_method_guide_test.dart test/widgets/exercise_replacement_sheet_test.dart` (plus any new Wave-0 files as they're created)
- **Per wave merge:** `flutter test` (full suite, redirected to a file per CLAUDE.md guidance — output exceeds a terminal and `\r` progress needs `tr '\r' '\n'` before grepping)
- **Phase gate:** Full suite green (1308+ pass / 4 skipped baseline, expect this count to grow with new tests), plus `flutter analyze` at 0 errors and `dart run tool/check_structure.dart` clean (verifies the `part`/`part of` split actually brought `block_detail_view.dart` under 600 lines)

### Wave 0 Gaps
- [ ] `test/block_detail_view_test.dart` — new widget test file; covers EDIT-01's Week dropdown/wave-strip rendering and EDIT-02's per-exercise replace trigger wiring
- [ ] `test/wave_label_test.dart` (or co-located with the new domain file) — unit tests for the new anchor-slot wave-label pure function (D-05), including the single-wave and block-boundary edge cases called out in Pitfall 4
- [ ] Extend `test/program_exercise_replacement_scope_test.dart` (or add a new file) — assert that a post-commit `replaceProgramExerciseSlot` + `rematerializeProgram` sequence leaves `in_progress`/`done` `ScheduledWorkouts` rows byte-identical (EDIT-03's explicit safety requirement, currently only implicitly true, not asserted)
- [ ] Extend `test/program_method_guide_test.dart` — lock in the 8-row (or deliberate exception) count per model per D-06
- [ ] No framework install needed — `flutter_test` is already fully configured

## Security Domain

Not applicable — this phase has no `security_enforcement` implications (no new auth,
input-validation, session, or cryptography surface). All data stays local-first through the
same `*_repository.dart` boundary already in place; no new Supabase/RLS surface is introduced
(no schema/migration changes are expected — see Standard Stack). If planning later determines
a schema change IS needed (not indicated by this research), CLAUDE.md's "Schema changes are
five chores, not one" checklist applies in full, including the Supabase migration step.

## Runtime State Inventory

Not applicable — this is not a rename/refactor/migration phase in the CLAUDE.md sense (no
renamed identifiers, no cross-system string references). It is a UI retrofit + code extraction
within a single feature module. Skipped per the trigger condition.

## Environment Availability

Not applicable — this phase has no external tool/service/runtime dependency beyond the
existing Flutter/Dart toolchain already required by every phase in this repo (confirmed
present via CLAUDE.md's documented `flutter analyze`/`flutter test`/`tool/codegen.ps1`
commands, which are assumed working since prior phases 15-18 completed using them).

## Project Constraints (from CLAUDE.md)

- `flutter analyze` must report 0 errors (warnings count against the exit-code check too, per
  CLAUDE.md's note that the tool exits 1 on warnings).
- `flutter test` output redirect to a file, not piped through `tail` (loses exit code); use
  `tr '\r' '\n'` before grepping test output.
- `dart run tool/check_structure.dart` must pass — directly relevant here since D-01 requires
  splitting `block_detail_view.dart` under the 600-line limit.
- No hand-written file over 600 lines; split via `part`/`part of` in a subfolder named after
  the file, keeping the public import path unchanged; **parts cannot have their own imports**
  (see Pitfall 2).
- Imports are always `package:herculex/...`, never relative, EXCEPT `part`/`part of`
  statements and same-folder barrel exports, which stay relative by language rule.
- Route paths are constants in `app/router/routes.dart` — not directly relevant unless this
  phase adds a new route (it does not; `BlockDetailView` and `ProgramMethodGuideView` are
  existing routes/pushes).
- The UI never touches drift directly — all data access for the new per-exercise replacement
  trigger must go through `ProgramsRepository` (already satisfied by reusing
  `replaceProgramExerciseSlot`/`rematerializeProgram`).
- Prefer `StreamProvider` over `FutureProvider` for drift reads — `programDayExerciseSummariesProvider`
  and `programDaysProvider`/`programWeeksProvider` are already `StreamProvider`s; no change
  needed, but any new provider this phase adds (if any) should follow the same convention.
- `@DataClassName` mandatory on new tables — not applicable, no new tables in this phase.
- Two active roadmaps coexist (`.planning/ROADMAP.md` GSD Phase 19 and `docs/ui-rework/ROADMAP.md`
  Phase 9 AppColors-deletion track) — per UI-SPEC's explicit guidance, do NOT do a drive-by
  `AppColors` → `HxColors`/`context.hx` migration on existing call sites in
  `block_detail_view.dart`/`program_review_view.dart` during this phase; only new widgets may
  use `context.hx` at the executor's discretion.

## Sources

### Primary (HIGH confidence — direct codebase reads)
- `lib/features/programs/data/programs_repository.dart` (lines 1-70, 770-1049, 1238-1344,
  1346-1363) — `ProgramExerciseReplacementScope`, `replaceProgramExerciseSlot`,
  `rematerializeProgram`, `materializeProgram`, `setProgramDayTemplate`.
- `lib/features/programs/presentation/views/block_detail_view.dart` (full file, 710 lines) —
  current `_WeekCard`/`_DayRow` structure, existing `_link`/`_remove`/`_addDay` mutation
  patterns.
- `lib/features/programs/presentation/views/program_review_view.dart` (lines 1-378, 690-970) —
  `_chooseReplacement`, `_WeekPicker`, `_loadRotations`/`_RotationSegment`,
  `ExerciseReplacementSheet`, `_ScopeChoice`, `ExerciseReplacementSelection`.
- `lib/features/programs/presentation/views/program_method_guide_view.dart` (full file, 331
  lines) — `ProgramMethodGuide.forModel`, `ProgramMethodGuideWeek`, guide rendering.
- `lib/features/programs/domain/periodization.dart` (full file, 179 lines) — `Periodization.plan`,
  `isPlannedDeload`, block-phase percentages (40/40/20 accumulation/transmutation/realization).
- `lib/features/programs/domain/slot_role.dart` (full file) — `SlotRole.main`,
  `SlotRoleEligibility`.
- `lib/data/local/tables.dart` (lines 734-913, 1058-1105) — `ProgramWeeks`, `ProgramDays`,
  `ProgramDayExercises`, `ProgramExerciseSlots`, `ProgramSlotPoolMembers`,
  `RotationAssignments`, `ScheduledWorkouts` schema.
- `lib/features/profile/presentation/profile_view.dart` +
  `lib/features/profile/presentation/profile_view/_identity.part.dart` — `part`/`part of`
  precedent.
- `lib/features/programs/data/smart_program_planner/*.part.dart` (located, not fully read) —
  second `part`/`part of` precedent inside `features/programs/`.
- `test/program_exercise_replacement_scope_test.dart`,
  `test/widgets/exercise_replacement_sheet_test.dart`, `test/program_method_guide_test.dart`
  — existing test coverage and gaps.
- `.planning/phases/19-.../19-CONTEXT.md`, `19-DISCUSSION-LOG.md`, `19-UI-SPEC.md`,
  `.planning/REQUIREMENTS.md`, `.planning/STATE.md` — phase scope, locked decisions, UI
  contract.

### Secondary (MEDIUM confidence)
None used — this phase required no external documentation lookups; all findings are direct
codebase reads.

### Tertiary (LOW confidence)
None.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no external packages involved, confirmed by reading all touched
  files' import blocks.
- Architecture: HIGH — every pattern cited is read directly from working, committed code
  (not inferred or assumed), including the exact wave-boundary-walk algorithm and the
  `rematerializeProgram` safety mechanism.
- Pitfalls: HIGH — derived from direct comparison of `program_review_view.dart` (pre-commit,
  no rematerialize) vs. `block_detail_view.dart` (post-commit, always rematerialize) call
  sites, not speculation.

**Research date:** 2026-09-16
**Valid until:** No expiry driver (internal-only refactor, no external dependency churn) —
treat as valid for the lifetime of this phase's planning/execution window; re-verify only if
`programs_repository.dart` or `block_detail_view.dart` change materially before planning
starts.
