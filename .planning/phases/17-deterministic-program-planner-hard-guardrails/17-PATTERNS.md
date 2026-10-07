# Phase 17: Deterministic Program Planner & Hard Guardrails - Pattern Map

**Mapped:** 2026-09-13
**Files analyzed:** 9 (3 modified existing, 3 new domain/data files, 1 new table, 1 modified table/schema, 1 new UI surface)
**Analogs found:** 9 / 9

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `lib/features/programs/domain/exercise_programming_eligibility.dart` (extend `allows`) | domain / pure gate function | request-response (predicate) | itself (existing file, extend in place) | exact |
| `lib/features/programs/domain/selection_explanation.dart` (new) | model | transform | `lib/features/programs/domain/exercise_scaling_resolver.dart` (`ScalingResolutionResult`) | exact — same "success/noSafeCandidate" sealed-result shape |
| `lib/features/programs/domain/joint_model.dart` (`JointModel.excludedMusclesFor` new static helper) | domain / pure utility | transform | `lib/features/recovery/domain/training_suggestion.dart` (`TrainingSuggestionEngine`'s inline `jointExcluded` set-builder, lines 86-92) | exact — literal extraction of that logic |
| `lib/features/programs/data/smart_program_planner.dart` (`SmartProgramConfiguration` — add `excludedMuscles`/`flaggedJoints` fields) | data / config model | CRUD (config input) | itself (existing file, extend in place) | exact |
| `lib/features/programs/data/smart_program_planner/slot_candidate_resolution.part.dart` (new) | data / service (part file) | request-response | `lib/features/profile/presentation/profile_view/_identity.part.dart` (`part of` split pattern) + `smart_program_planner.dart:257-480` (`_createStableSlots`, logic being extracted) | exact (structure) / exact (logic) |
| `lib/features/programs/data/smart_program_planner/anchor_lock.part.dart` (new) | data / service (part file) | event-driven (per-week state) | `smart_program_planner.dart:520-538` (rotation-assignment week loop being extended) | exact |
| `lib/features/programs/data/smart_program_planner/selection_explanation_writer.part.dart` (new) | data / repository-style writer | CRUD (insert) | `smart_program_planner.dart:481-518` (`ProgramExerciseSlotsCompanion`/`ProgramSlotPoolMembersCompanion` insert pattern) | exact |
| `lib/data/local/tables.dart` (`ProgramSlotExplanations` new table) | model / drift table | CRUD | `RotationAssignments` table (`tables.dart:890-912`) — same `{slotId, weekIndex}` unique-key shape, nullable-FK sibling | exact |
| `lib/data/local/database.dart` (`schemaVersion` 41→42, `onUpgrade if (from < 42)`) | migration | batch | `database.dart:1090` (`if (from < 41 && to >= 41)` block — most recent additive-table/column step) | exact |
| `lib/features/recovery/data/joint_pain_repository.dart` (caller resolves snapshot — no file change, but new call site in `block_builder_view.dart`) | controller (presentation call site) | request-response | `block_builder_view.dart:3265-3273` (existing `SmartProgramPlanner(...).populate(...)` call site, extend the `SmartProgramConfiguration(...)` args) | exact |
| Program day view empty-slot widget (new, exact file TBD by planner — likely `lib/features/programs/presentation/.../program_day_view` or similar) | component | request-response (read `ProgramSlotExplanations`) | No existing "gap" widget found in programs presentation; closest conceptual analog is any existing empty-state widget pattern in `design_system/components` (planner should search `design_system/components` for an `EmptyState`-style widget at implementation time) | role-match only — flagged in No Analog Found |
| `test/exercise_programming_eligibility_test.dart` (extend) | test | request-response | itself (existing file) | exact |
| `test/smart_program_planner_test.dart` (extend) | test | integration/CRUD | itself (existing file, uses real catalog via `ExerciseImporter.runFromJson`) | exact |
| `test/program_slot_explanations_test.dart` (new) | test | CRUD | `test/exercise_scaling_resolver_test.dart` style (hand-built `ExerciseCatalogData` fixtures, no asset loading) + `test/support/test_database.dart` (`openTestDatabase()`) | exact |

## Pattern Assignments

### `lib/features/programs/domain/exercise_programming_eligibility.dart` (domain, request-response — extend `allows`)

**Analog:** itself, current implementation

**Imports pattern** (lines 1-11):
```dart
/// Deterministic hard gate for automatically generated program exercises.
///
/// It deliberately has no scoring or fallback behavior. A missing or invalid
/// metadata value is interpreted as the conservative value, so a legacy or
/// custom movement cannot enter an automatic plan before it has been curated.
library;

import 'dart:convert';

import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/programs/domain/programming_models.dart';
```

**Core hard-gate pattern to extend** (lines 16-84) — add `primaryMuscle`/`excludedMuscles` params and an early-return check, mirroring the existing style of one `if (...) return false;` per hard condition, with a comment explaining *why* it's a hard gate:
```dart
static bool allows({
  required ExperienceLevel experience,
  required TrainingStyle style,
  required String? difficulty,
  required String? commonness,
  required String? allowedTrainingStylesJson,
  required String? technicalEligibility,
  String? modality,
  String? requiredEquipmentKeysJson,
  // NEW (D-05/D-06/D-07) — pre-resolved by the caller once per populate() run.
  String? primaryMuscle,
  Set<String> excludedMuscles = const {},
}) {
  final resolvedDifficulty = _difficulty(difficulty);
  if (_difficultyRank(resolvedDifficulty) > _experienceRank(experience)) {
    return false;
  }
  // NEW: injury/pain hard exclusion — same call-site placement as every
  // other hard condition above, no separate function/parallel gate.
  if (primaryMuscle != null && excludedMuscles.contains(primaryMuscle)) {
    return false;
  }
  // ...existing checks unchanged...
}
```

**Validation pattern for optional-field defaulting** (lines 146-171) — this `switch` pattern (unknown/null → most conservative value) is the established idiom for any new metadata field; reuse verbatim if a new field needs the same treatment:
```dart
static String _difficulty(String? value) => switch (value) {
  'novice' || 'intermediate' || 'advanced' => value!,
  _ => 'advanced',
};
```

---

### `lib/features/programs/domain/joint_model.dart` (extend — new `excludedMusclesFor` static helper)

**Analog:** `lib/features/recovery/domain/training_suggestion.dart` lines 66-92 (`TrainingSuggestionEngine`)

**Pattern to extract into `JointModel`** (mirrors `_jointExclusionWeight`/`jointExcluded` exactly, generalized to accept any `Map<String, JointPainStatus>` isFlagged predicate instead of `JointStressResult`/`DeloadUrgency`):
```dart
// Source: lib/features/recovery/domain/training_suggestion.dart:76,86-92
static const _jointExclusionWeight = 0.5;

final jointExcluded = <String>{
  for (final js in jointStress)
    if (js.urgency != DeloadUrgency.none)
      for (final entry
          in (JointModel.influencingMuscles[js.joint] ?? const {}).entries)
        if (entry.value >= _jointExclusionWeight) entry.key,
};
```
D-05 requires this be a single implementation shared by Recovery and Phase 17. Recommended new method on `JointModel` itself (`lib/features/recovery/domain/joint_model.dart`, existing file, has headroom — only 67 lines):
```dart
static Set<String> excludedMusclesFor(
  Map<String, JointPainStatus> statuses, {
  double weightThreshold = 0.5,
}) => {
  for (final status in statuses.values)
    if (status.isFlagged)
      for (final entry in (influencingMuscles[status.joint] ?? const {}).entries)
        if (entry.value >= weightThreshold) entry.key,
};
```
`JointPainStatus.isFlagged` (the predicate to use, not `DeloadUrgency`) is defined at `lib/features/recovery/data/joint_pain_repository.dart:27`: `bool get isFlagged => severity > 0;`. After adding this helper, refactor `TrainingSuggestionEngine.suggest`'s inline set-builder to call it too (matches D-05's "one source of truth" literally, not just conceptually) — but confirm `TrainingSuggestionEngine`'s `jointStress`/`JointStressResult` input shape maps cleanly to `JointPainStatus` before doing so; if the input shapes genuinely diverge, leave `TrainingSuggestionEngine` untouched and only add the new helper for Phase 17's own call site (do not force an unrelated refactor into this phase's scope).

---

### `lib/features/programs/domain/selection_explanation.dart` (new domain model)

**Analog:** `lib/features/programs/domain/exercise_scaling_resolver.dart` lines 7-21 (`ScalingResolutionResult`)

**Sealed success/failure result shape to mirror:**
```dart
// Source: lib/features/programs/domain/exercise_scaling_resolver.dart:7-21
class ScalingResolutionResult {
  const ScalingResolutionResult.success({
    required this.candidate,
    required this.rationale,
  }) : isSuccess = true;

  const ScalingResolutionResult.noSafeCandidate({
    required this.rationale,
  })  : candidate = null,
        isSuccess = false;

  final ExerciseCatalogData? candidate;
  final bool isSuccess;
  final String rationale;
}
```
`SelectionExplanation` should follow this exact two-named-constructor idiom (`.filled(exerciseId, rationale)` / `.empty(rationale)`), keeping it a plain Dart class (no Flutter import) per the file-organization note in RESEARCH.md, consistent with `program_guardrails.dart` and `exercise_scaling_resolver.dart` both being single-purpose domain files under 200 lines.

**Excluded-candidate stretch-goal shape to reuse if PLAN-04's optional depth is implemented:**
```dart
// Source: lib/features/programs/domain/exercise_scorer.dart:194-213
class ScorerResult {
  final List<ScoredExercise> ranked;
  final Relaxation relaxation;
  final Map<int, FilterReason> excluded; // exerciseId -> why it never got scored
}
```

---

### `lib/features/programs/data/smart_program_planner.dart` + new `smart_program_planner/*.part.dart` files (data, request-response / event-driven)

**Analog for the part-file split:** `lib/features/profile/presentation/profile_view.dart` + `lib/features/profile/presentation/profile_view/_identity.part.dart`

**Parent-file part declarations pattern** (`profile_view.dart` lines 35-39 — all imports live in the parent, `part` directives listed at the bottom of the import block):
```dart
part 'profile_view/_auth.part.dart';
part 'profile_view/_body.part.dart';
part 'profile_view/_identity.part.dart';
part 'profile_view/_settings.part.dart';
part 'profile_view/_target_cards.part.dart';
```

**Part-file header pattern** (`_identity.part.dart` line 1 — every part file's first line, no imports of its own):
```dart
part of '../profile_view.dart';
```
Apply the identical structure to `smart_program_planner.dart`, adding after existing imports:
```dart
part 'smart_program_planner/slot_candidate_resolution.part.dart';
part 'smart_program_planner/anchor_lock.part.dart';
part 'smart_program_planner/selection_explanation_writer.part.dart';
```
and each new file starting with:
```dart
part of '../smart_program_planner.dart';
```

**Existing imports block to keep centralized in the parent file** (`smart_program_planner.dart` lines 1-14):
```dart
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/programs/domain/exercise_programming_eligibility.dart';
import 'package:herculex/features/programs/domain/exercise_scorer.dart';
import 'package:herculex/features/programs/domain/periodization.dart';
import 'package:herculex/features/programs/domain/primary_lift_specialization.dart';
import 'package:herculex/features/programs/domain/program_guardrails.dart';
import 'package:herculex/features/programs/domain/programming_models.dart';
import 'package:herculex/features/programs/domain/rotation_policy.dart';
import 'package:herculex/features/programs/domain/slot_role.dart';
import 'package:herculex/features/programs/domain/squat_specialization.dart';
import 'package:herculex/features/workouts/domain/set_type.dart';
```
New part files will need `package:herculex/features/programs/domain/exercise_scaling_resolver.dart` and `package:herculex/features/programs/domain/selection_explanation.dart` added here (parts cannot add their own imports).

**`SmartProgramConfiguration` field-add pattern** (lines 16-86 — plain final fields with a doc comment explaining the "why", defaulted where sensible):
```dart
class SmartProgramConfiguration {
  const SmartProgramConfiguration({
    required this.goal,
    required this.experience,
    // ...existing params...
    this.excludedMuscles = const {},   // NEW, D-07
  });

  final TrainingGoal goal;
  final ExperienceLevel experience;
  // ...
  /// Precomputed once by the caller from JointPainRepository.watchCurrentStatuses()
  /// (D-07) — the planner never queries live joint-pain state itself.
  final Set<String> excludedMuscles;
}
```

**Candidate-filtering pattern to extend for the hard-filter/no-relax split** (`_createStableSlots`, lines 309-358 — this is the exact code D-01/D-02/D-06 modify):
```dart
var candidates = catalog.where((exercise) {
  if (used.contains(exercise.id)) return false;
  if (!equipment.allows(exercise)) return false;
  if (!_isEligibleForAutomaticProgramming(exercise, configuration)) {
    return false;
  }
  final patternMatches =
      need.pattern == null || exercise.movementPattern == need.pattern;
  final muscleMatches =
      need.muscle == null ||
      exercise.primaryMuscle.toLowerCase().contains(need.muscle!);
  if (!patternMatches || !muscleMatches) return false;
  final mask = SlotRoleEligibility.derive(/* ... */);
  if (!SlotRoleEligibility.allows(mask, need.role)) return false;
  if (method == SlotTrainingMethod.maxEffort &&
      exercise.maxEffortEligibility != MaxEffortEligibility.eligible.id) {
    return false;
  }
  return true;
}).toList();
if (candidates.isEmpty) {
  // Never leave a Smart slot empty: keep the role gate, then relax the
  // requested pattern/muscle. Equipment remains a hard filter in scorer.
  candidates = catalog.where((exercise) {
    // ... identical hard gates, pattern/muscle omitted ...
  }).toList();
}
```
`_isEligibleForAutomaticProgramming` is the call site to pass `primaryMuscle`/`excludedMuscles` through to the extended `ExerciseProgrammingEligibility.allows` (Pattern above). The `if (candidates.isEmpty)` fallback block is exactly D-02's "pattern/muscle may still relax" — keep its scope unchanged, do not add equipment/injury/style/experience/prerequisite relaxation to it.

**Crash-path to replace with a per-slot result type (Pitfall 1)** — the two `StateError` throws at lines 465-469 and 471-475:
```dart
if (ranked.isEmpty) {
  throw StateError(
    'No ${need.role.label.toLowerCase()} exercise is available for $dayLabel with the selected equipment.',
  );
}
final pool = ranked.take(6).toList(growable: false);
if (method == SlotTrainingMethod.maxEffort && pool.length < 3) {
  throw StateError(
    'Max Effort rotation for $dayLabel needs at least three suitable variations.',
  );
}
```
Per RESEARCH.md's Pitfall 1: only the *genuinely-still-a-bug* conditions (empty catalog entirely, max-effort pool < 3) should keep throwing. The D-01 "hard filters legitimately emptied this slot" case must be intercepted **before** reaching `ExerciseScorer.rank`/this `ranked.isEmpty` check — i.e., detect `candidates.isEmpty` after both the primary filter and the scaling-resolver consultation (D-03), and short-circuit to writing a `SelectionExplanation.empty(...)` + `continue` to the next slot, never entering the scorer/rank path at all for that slot.

**Anchor-lock insertion point** (`_createStableSlots`, the week loop at lines 520-538 — this is where `RotationAssignments` rows are built per week):
```dart
final assignments = <int, RotationAssignmentData>{};
final phases = RotationPolicy.phasesFor(model, program.weeks);
for (final week in weeks) {
  final epoch = policy.epochFor(week.weekIndex, phases: phases);
  final selected = pool[epoch % pool.length];
  final id = await _db
      .into(_db.rotationAssignments)
      .insert(
        RotationAssignmentsCompanion.insert(
          slotId: slotId,
          exerciseId: selected.candidate.exerciseId,
          weekIndex: week.weekIndex,
          reason: selected.why,
        ),
      );
  assignments[week.weekIndex] = await (_db.select(
    _db.rotationAssignments,
  )..where((t) => t.id.equals(id))).getSingle();
}
```
Per D-09/D-10, wrap `selected` resolution with the `lockedAnchors[slotKey]` check when `need.role == SlotRole.main` (see RESEARCH.md Pattern 2 for the exact intercept logic) — `lockedAnchors: Map<String, int>` is a local variable scoped to one `populate()` call, not a `SmartProgramConfiguration` field (confirmed by Pitfall 2: do not let this interact with the per-day `used` set, which lives in the outer per-slot loop at line 277, not this week loop).

**Insert pattern to mirror for `ProgramSlotExplanations` writes** (lines 481-518 — the `ProgramExerciseSlotsCompanion`/`ProgramSlotPoolMembersCompanion` insert style: `Value(...)` wrapping for nullable/optional columns, plain values for required ones):
```dart
final slotId = await _db
    .into(_db.programExerciseSlots)
    .insert(
      ProgramExerciseSlotsCompanion.insert(
        programId: program.id,
        slotKey: slotKey,
        daySlotLabel: dayLabel,
        orderIndex: order,
        role: Value(need.role.id),
        movementPattern: Value(need.pattern),
        primaryMuscle: Value(need.muscle),
        trainingMethod: Value(method.id),
        // ...
      ),
    );
for (final (poolIndex, scored) in pool.indexed) {
  await _db
      .into(_db.programSlotPoolMembers)
      .insert(
        ProgramSlotPoolMembersCompanion.insert(
          slotId: slotId,
          exerciseId: scored.candidate.exerciseId,
          orderIndex: Value(poolIndex),
          pinned: Value(poolIndex == 0),
        ),
      );
}
```

---

### `lib/data/local/tables.dart` (new `ProgramSlotExplanations` table)

**Analog:** `RotationAssignments` table, lines 890-912

**Pattern to mirror** (nullable FK via `.nullable().references(...)`, `{slotId, weekIndex}` unique key, `@DataClassName`):
```dart
// Source: lib/data/local/tables.dart:890-912
@DataClassName('RotationAssignmentData')
class RotationAssignments extends Table with SyncColumns, SyncTombstone {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get slotId => integer().references(
    ProgramExerciseSlots,
    #id,
    onDelete: KeyAction.cascade,
  )();
  IntColumn get exerciseId => integer().references(
    ExerciseCatalog,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get weekIndex => integer()();
  TextColumn get source => text().withDefault(const Constant('planned'))();
  TextColumn get reason => text()();
  TextColumn get variantConfigJson => text().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {slotId, weekIndex},
  ];
}
```
Per RESEARCH.md's recommendation, `ProgramSlotExplanations.chosenExerciseId` must be `.nullable()` (the one structural difference from `RotationAssignments.exerciseId`), and per A1 the table should likely **not** mix in `SyncColumns`/`SyncTombstone` if the local-only recommendation is accepted — confirm this decision explicitly in the plan before implementing, since every other table in this file does use those mixins and omitting them is a deviation from the dominant local pattern.

---

### `lib/data/local/database.dart` (schema bump: 41 → 42)

**Analog:** the most recent additive-table/column `onUpgrade` step, lines 1090-1096 (`if (from < 41 && to >= 41)`)

```dart
// Source: lib/data/local/database.dart:1090-1096 (most recent step, pattern to follow)
if (from < 41 && to >= 41) {
  final catalogueExists = await customSelect(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' "
    "AND name = 'exercise_catalog'",
  ).getSingleOrNull();
  if (catalogueExists != null) {
    // ...
  }
}
```
**Guarded `addColumn` idiom** (lines 1051-1063 — reusable if any *column* addition is needed elsewhere in this phase, e.g. if `ProgramExerciseSlots` needs a new column instead of only a new table):
```dart
Future<void> addIfMissing(
  TableInfo<Table, dynamic> table,
  GeneratedColumn column,
) async {
  final existing = await customSelect(
    "SELECT name FROM pragma_table_info('${table.actualTableName}')",
  ).get();
  if (existing.isEmpty) return;
  final names = existing.map((row) => row.read<String>('name')).toSet();
  if (!names.contains(column.$name)) {
    await m.addColumn(table, column);
  }
}
```
For a **new table** (this phase's case), no `addIfMissing` guard is needed — `m.createTable(...)` is the correct idiom (see any earlier `if (from < N)` block in this file that calls `m.createTable`, e.g. search `createTable` for the exact call signature at implementation time). `schemaVersion` is currently `41` (line 98); bump to `42` and add `if (from < 42 && to >= 42) { ... }` following the most recent block's `to >= N` guard style (this guard style appears from v28 onward and should be used, not the earlier bare `if (from < N)` style).

---

### `lib/features/programs/presentation/views/block_builder_view.dart` (controller call site — extend, not create)

**Analog:** itself, lines 3265-3273 (existing sole production call site of `SmartProgramPlanner.populate`)

```dart
// Source: lib/features/programs/presentation/views/block_builder_view.dart:3265-3273
createdProgramId = programId;

if (_buildMode != ProgramBuildMode.manual) {
  await SmartProgramPlanner(ref.read(appDatabaseProvider)).populate(
    programId,
    SmartProgramConfiguration(
      goal: _goal,
      experience: _experience,
      trainingStyle: _trainingStyle,
      // ... existing fields ...
    ),
  );
}
```
Per D-07, this call site must resolve `JointPainRepository.watchCurrentStatuses()` to a snapshot **before** this call and pass the derived `excludedMuscles` set into `SmartProgramConfiguration(...)`. `JointPainRepository` is obtained the same way other repositories are in this file (`ref.read(...Provider)` — check `app/providers.dart` for the existing `jointPainRepositoryProvider` name before adding a new one).

---

### Test files

**Analog for hand-built-fixture unit tests (no asset loading):** `test/exercise_scaling_resolver_test.dart` style — use for `test/program_slot_explanations_test.dart` and any new injury/pain unit tests in `test/exercise_programming_eligibility_test.dart`.

**Analog for in-memory DB setup:**
```dart
// Source: test/support/test_database.dart:16-25
Future<AppDatabase> openTestDatabase({bool foreignKeys = true}) async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  await db.customSelect('SELECT 1').getSingle();
  if (!foreignKeys) {
    await db.customStatement('PRAGMA foreign_keys = OFF');
  }
  return db;
}
```

**Analog for integration tests using the real curated catalog (existing style, keep using for "full program generation still works" tests only, per Pitfall 4):** `test/smart_program_planner_test.dart`'s `setUp` calling `ExerciseImporter.runFromJson` against `assets/data/exercises.json` + `assets/data/exercise_programming_metadata.json`.

## Shared Patterns

### Hard-gate-extension, not parallel-gate
**Source:** `lib/features/programs/domain/exercise_programming_eligibility.dart:16-84`
**Apply to:** injury/pain filtering (D-05/D-06) — every hard filter in this phase must be a new `if (...) return false;` inside `ExerciseProgrammingEligibility.allows`, never a second standalone function called from a different site in `smart_program_planner.dart`.

### Conservative-default `switch` for optional metadata
**Source:** `exercise_programming_eligibility.dart:146-171` (`_difficulty`, `_commonness`, `_technicalEligibility`)
```dart
static String _difficulty(String? value) => switch (value) {
  'novice' || 'intermediate' || 'advanced' => value!,
  _ => 'advanced',
};
```
**Apply to:** any new nullable metadata field this phase reads, per the Phase 16 "conservative default" convention CLAUDE.md/RESEARCH.md both call out.

### Sealed success/failure result object
**Source:** `exercise_scaling_resolver.dart:7-21` (`ScalingResolutionResult`)
**Apply to:** `SelectionExplanation` (new) — two named const constructors, one nullable field pinned by the discriminant, matches the codebase's existing idiom for "this operation might legitimately fail, and the failure needs a human-readable reason" rather than a thrown exception.

### `part`/`part of` file split for over-600-line files
**Source:** `lib/features/profile/presentation/profile_view.dart` + `profile_view/_identity.part.dart` (and the other `_*.part.dart` siblings)
**Apply to:** `smart_program_planner.dart` (already 1352 lines) — new logic goes in `smart_program_planner/*.part.dart` files, imports stay centralized in the parent, each part starts with `part of '../smart_program_planner.dart';`.

### Drift insert `Companion.insert` idiom
**Source:** `smart_program_planner.dart:481-518`
**Apply to:** `ProgramSlotExplanations` row writes — required columns as plain named args, optional/nullable columns wrapped in `Value(...)`.

### Guarded/versioned `onUpgrade` step
**Source:** `lib/data/local/database.dart:1090` (`if (from < 41 && to >= 41)`)
**Apply to:** the new `if (from < 42 && to >= 42) { ... m.createTable(...) ... }` block for `ProgramSlotExplanations`.

## No Analog Found

| File | Role | Data Flow | Reason |
|---|---|---|---|
| Empty-slot visible-gap widget (D-04, exact path TBD) | component | request-response | No existing "gap"/"missing item" empty-state widget was found scoped to `lib/features/programs/presentation/`. Planner should search `lib/design_system/components/` for a generic empty-state component to reuse (e.g. an existing card/banner style) before building one from scratch — this research pass did not have the program day view file in its required-reading list, so the closest current rendering surface (where filled slots are shown) is unidentified. Recommend the planner/researcher for this specific file locate the program day view first, then find its nearest empty-state analog inside `design_system/components`. |

## Metadata

**Analog search scope:** `lib/features/programs/domain/`, `lib/features/programs/data/`, `lib/features/recovery/domain/`, `lib/features/recovery/data/`, `lib/data/local/tables.dart`, `lib/data/local/database.dart`, `lib/features/profile/presentation/` (for the `part`/`part of` split precedent), `test/support/`, `test/*_test.dart`.
**Files scanned:** ~14 read in full or targeted sections (see individual excerpts above for exact line ranges).
**Pattern extraction date:** 2026-09-13
