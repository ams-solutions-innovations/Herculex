# Phase 21: CrossFit & GPP Training Tracks - Pattern Map

**Mapped:** 2026-09-16
**Files analyzed:** 16 (4 new domain, 5 modified core, 2 content/migration, 5 test)
**Analogs found:** 16 / 16

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `lib/features/programs/domain/session_segment.dart` | model (enum) | transform | `lib/features/workouts/domain/set_type.dart` | exact |
| `lib/features/programs/domain/crossfit_program_planner.dart` | service | CRUD (assembly) | `lib/features/programs/data/smart_program_planner.dart` (`_needsFor`/`_methodFor`) | role-match |
| `lib/features/programs/domain/gpp_program_planner.dart` | service | CRUD (assembly) | `lib/features/programs/data/smart_program_planner.dart` (`_needsFor` gpp branch) | exact |
| `lib/features/programs/domain/crossfit_scaling_policy.dart` | service | transform | `lib/features/programs/domain/exercise_scaling_resolver.dart` | exact |
| `lib/data/local/tables.dart` (modify: `ProgramExerciseSlots`, `ProgramDayExercises`, `WorkoutExercises`) | model (drift table) | CRUD | same file, `slotRole`/`plannedSlotRole` columns already on these tables | exact |
| `lib/data/local/database.dart` (modify: schemaVersion + onUpgrade) | migration | batch | same file, `if (from < 43 && to >= 43)` block (lines 1125-1140+) | exact |
| `supabase/migrations/NNNN_session_segment_v44.sql` | migration | batch | `supabase/migrations/20260915000000_slot_prescription_codec_v43.sql` | exact |
| `lib/features/workouts/data/planned_session_resolver.dart` (modify) | service | transform | same file, `slotRole`/`plannedSlotRole` threading (lines ~311-327, 355-372) | exact |
| `lib/features/workouts/data/circuits_repository.dart` (modify: program-day link) | service | CRUD | same file, `addCircuitToSession`/`addCircuitToTemplate` (lines 158-277) | exact |
| `lib/features/workouts/domain/workout_duration_estimator.dart` (modify: capped-duration) | utility | transform | same file, `estimateExercise`/`estimateSession` (lines 14-61) | exact |
| `lib/features/programs/data/smart_program_planner.dart` (modify: wire crossfit/gpp planners, guard) | service | CRUD | same file, `_needsFor`/`_methodFor` (lines 1158-1340) | exact |
| `assets/data/exercise_programming_metadata.json` (modify: curate `prerequisiteSlugs`) | config | batch | same file, existing `bar-muscle-up`/`handstand-push-up` entries | exact |
| `test/features/programs/domain/crossfit_program_planner_test.dart` | test | CRUD | `test/features/programs/smart_program_planner_test.dart` | role-match |
| `test/features/programs/domain/crossfit_scaling_policy_test.dart` | test | transform | `test/exercise_scaling_resolver_test.dart` | exact |
| `test/features/programs/domain/gpp_program_planner_test.dart` | test | CRUD | `test/features/programs/smart_program_planner_test.dart` (gpp guard sections) | exact |
| `test/features/workouts/planned_session_resolver_test.dart` (extend) | test | transform | same file if exists, else `test/features/workouts/workout_duration_estimator_test.dart` pattern | role-match |

## Pattern Assignments

### `lib/features/programs/domain/session_segment.dart` (model, transform)

**Analog:** `lib/features/workouts/domain/set_type.dart` (whole file, 68 lines — read in full)

**Core enum pattern** (`set_type.dart` lines 7-43, 66-67 — `SlotRole.fromId` at `slot_role.dart` lines 21-30 confirms the same convention project-wide):
```dart
enum SetType {
  standard('standard', 'Standard'),
  ...
  amrap('amrap', 'AMRAP', metaKeys: ['capSeconds', 'rounds']),
  emom('emom', 'EMOM', metaKeys: ['minutes', 'repsPerMinute']),
  forTime('for_time', 'For Time', metaKeys: ['elapsedSeconds']);

  const SetType(this.id, this.label, {this.metaKeys = const [], ...});

  final String id;
  final String label;

  static SetType fromId(String? id) =>
      values.firstWhere((t) => t.id == id, orElse: () => SetType.standard);
}
```

**Apply as:** A 5-value enum (`warmup`/`skill`/`strength`/`metcon`/`cooldown`) with `.id` string persisted, and a **nullable** `fromId` (unlike `SetType`/`SlotRole`'s non-null fallback) since `null` = "no segment" is a valid, common state for every non-CrossFit/GPP row per D-01. Research's own proposed code (RESEARCH.md lines 252-267) already matches this shape almost exactly — use it, but note it uses `firstWhereOrNull` (needs `package:collection`) instead of `firstWhere+orElse`; either is acceptable, `firstWhere+orElse` matches existing project convention slightly more closely if a sentinel "none" value were ever wanted, but per D-01 `null` must be a real, distinct return value, so `firstWhereOrNull` is correct here — do not coerce unknown/null ids to a default segment.

**CRITICAL naming collision to avoid:** Do NOT name this class `WorkSegment` — that name is taken by `lib/features/programs/domain/slot_prescription.dart`'s per-slot set-group class. Use `SessionSegment` (research's recommended name) or equivalent.

---

### `lib/features/programs/domain/crossfit_scaling_policy.dart` (service, transform)

**Analog:** `lib/features/programs/domain/exercise_scaling_resolver.dart` (68 lines core class, read in full)

**Imports pattern** (lines 1-5):
```dart
import 'dart:convert';

import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/programs/domain/exercise_programming_eligibility.dart';
import 'package:herculex/features/programs/domain/programming_models.dart';
```

**Result-object pattern** (lines 7-21) — mirror this for policy decisions (e.g. `CrossfitLevelPolicyResult`) so callers get a rationale string, not just a value:
```dart
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

**Core "never silently relax" pattern** (lines 30-111, esp. 106-110) — the *exact* contract CF-02's level policy needs to replicate for time caps / complexity ceilings / recovery reserve: iterate candidates, apply hard gates in sequence (`continue` on failure), return `noSafeCandidate` with an explicit rationale if nothing passes — never a permissive fallback:
```dart
// Strict group boundary enforcement (D-16): Never silently jump modalities or groups
return ScalingResolutionResult.noSafeCandidate(
  rationale: 'No safe candidate found in scaling ladder "${target.scalingGroup}" '
      'matching available equipment and experience level.',
);
```

**Difficulty-ceiling helper pattern** (lines 113-125) — reuse this exact rank-comparison shape for the new time-cap-by-level / complexity-ceiling-by-level lookups:
```dart
static bool _difficultySafe(String? difficulty, ExperienceLevel experience) {
  final diffRank = switch (difficulty) {
    'novice' => 0,
    'intermediate' => 1,
    _ => 2,
  };
  final expRank = switch (experience) {
    ExperienceLevel.novice => 0,
    ExperienceLevel.intermediate => 1,
    ExperienceLevel.advanced => 2,
  };
  return diffRank <= expRank;
}
```

**Apply to:** `crossfit_scaling_policy.dart`'s time-cap-by-level table/multiplier, combo/complexity movement-count ceiling, and recovery-reserve spacing check — each should be a pure static method returning a typed result with rationale, called by `crossfit_program_planner.dart`, not inlined into the planner.

---

### `lib/features/programs/domain/crossfit_program_planner.dart` / `gpp_program_planner.dart` (service, CRUD-assembly)

**Analog:** `lib/features/programs/data/smart_program_planner.dart`, specifically `_needsFor` and `_methodFor` (lines 1158-1340)

**GPP guard pattern to preserve verbatim** (lines 1219-1224) — do not touch, but any new GPP segment content must compose with this, never replace it:
```dart
// A standalone GPP day is intentionally narrow: one conventional cardio
// / carry slot, not an opaque high-fatigue WOD. It remains easy to edit or
// remove through the normal program editor.
if (value.trim() == 'gpp') {
  return const [_SlotNeed(null, null, SlotRole.conditioning)];
}
```

**DE-guard pattern to preserve/regression-test** (lines 1178-1198):
```dart
if (model == PeriodizationModel.maxEffort &&
    experience != ExperienceLevel.novice &&
    stressRole == DayStressRole.dynamicTechnique &&
    role.isHeavy) {
  return SlotTrainingMethod.dynamicEffort;
}
...
if (role == SlotRole.conditioning) return SlotTrainingMethod.technique;
```
`role.isHeavy` is `main || supplemental` only (`slot_role.dart` line 34) — **every new GPP/CrossFit segment slot must stay off `SlotRole.main`/`supplemental`** to keep this guard intact (Pitfall 2 in RESEARCH.md).

**Slot-need declarative list pattern** (lines 1279-1334) — the existing per-day-label slot lists (e.g. `push` day) are the shape to mirror when `crossfit_program_planner.dart` assembles `[warmup?, skill?, strength?, metcon, cooldown?]`:
```dart
_SlotNeed('horizontal_push', null, SlotRole.main),
_SlotNeed('vertical_push', null, SlotRole.supplemental),
_SlotNeed('horizontal_push', null, SlotRole.accessory),
_SlotNeed(null, 'tricep', SlotRole.isolation),
_SlotNeed(null, 'shoulder', SlotRole.isolation),
```
New CrossFit/GPP segment slots should follow this `_SlotNeed`-equivalent shape but each carries the new `sessionSegment` tag alongside `SlotRole` — do not fold segment into `SlotRole` itself (D-01 naming/scope note).

**Do not inline into `smart_program_planner.dart`'s builder** — per RESEARCH.md's "Established Patterns" note (Phase 16 D-XX precedent), CrossFit/GPP get their own domain service files, called from `smart_program_planner.dart`'s existing entry points, not new `if` branches buried in `_needsFor`/`_methodFor` themselves beyond the minimal dispatch needed to invoke the new planner.

---

### `lib/data/local/tables.dart` (modify)

**Analog:** existing `slotRole`/`plannedSlotRole` columns on the same three tables (already read in full — `WorkoutExercises` lines 250-292, `ProgramDayExercises` lines 798-844, `ProgramExerciseSlots` lines 850-871)

**Column pattern to copy exactly**, one nullable text column added to each of the three tables, named consistently (`sessionSegment` on `ProgramExerciseSlots`/`ProgramDayExercises`, `plannedSessionSegment` on `WorkoutExercises`, mirroring the existing `role`/`slotRole`/`plannedSlotRole` naming ladder):
```dart
// ProgramDayExercises — mirror of the existing slotRole column shape (line 836),
// but nullable (null = no segment) rather than defaulted, per D-01.
TextColumn get sessionSegment => text().nullable()();
```
```dart
// WorkoutExercises — mirror of plannedSlotRole (line 285).
TextColumn get plannedSessionSegment => text().nullable()();
```

---

### `lib/data/local/database.dart` (modify: schemaVersion 43→44, onUpgrade)

**Analog:** the `if (from < 43 && to >= 43)` block (lines 1125-1140+) and the reusable `addIfMissing` helper duplicated at 40 and 43

**Pattern to copy exactly** (guard every `addColumn` against `pragma_table_info`, per CLAUDE.md's five-chores note and this file's own established convention):
```dart
if (from < 43 && to >= 43) {
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

  await addIfMissing(...);
}
```
**Apply as:** a new `if (from < 44 && to >= 44)` block, `schemaVersion` bumped from 43 to 44 (`database.dart:101`), calling `addIfMissing` for the three new `sessionSegment`/`plannedSessionSegment` columns across `ProgramExerciseSlots`, `ProgramDayExercises`, `WorkoutExercises`.

---

### `supabase/migrations/NNNN_session_segment_v44.sql` (new)

**Analog:** `supabase/migrations/20260915000000_slot_prescription_codec_v43.sql` (read in full, 9 lines)

**Pattern to copy exactly**:
```sql
-- SessionSegment tagging mirrors local Drift v44.
alter table public.program_exercise_slots
  add column if not exists session_segment text;

alter table public.program_day_exercises
  add column if not exists session_segment text;

alter table public.workout_exercises
  add column if not exists planned_session_segment text;
```
Name the file with a timestamp prefix matching the existing convention (`YYYYMMDDHHMMSS_description_vNN.sql`) — all three tables carry `SyncColumns`/`SyncTombstone` (confirmed by RESEARCH.md) so `SyncService`'s `SELECT *` forward means skipping this migration causes PGRST204 quarantine per CLAUDE.md's schema-bump warning.

---

### `lib/features/workouts/data/planned_session_resolver.dart` (modify)

**Analog:** the existing `slotRole`/`plannedSlotRole` threading in the same file (already read: `PlannedExerciseSnapshot` constructor lines 57-89, assembly lines 311-327, `materialize()` lines 351-372)

**Snapshot field pattern to mirror** (constructor, lines 57-89):
```dart
class PlannedExerciseSnapshot {
  const PlannedExerciseSnapshot({
    ...
    required this.slotRole,
    ...
  });
  final String slotRole;
  ...
}
```
Add `final String? sessionSegment;` alongside `slotRole` (nullable, unlike `slotRole` which always has a value).

**Assembly-site pattern to mirror** (line 316, inside the loop building `PlannedExerciseSnapshot`):
```dart
exercises.add(
  PlannedExerciseSnapshot(
    ...
    slotRole: role.id,
    ...
  ),
);
```
Read `pde.sessionSegment` (the new `ProgramDayExercises` column) the same way `role.id` is read, and pass it through.

**Materialize-site pattern to mirror** (lines 355-372, inside `WorkoutExercisesCompanion.insert`):
```dart
WorkoutExercisesCompanion.insert(
  ...
  plannedSlotRole: Value(exercise.slotRole),
  ...
),
```
Add `plannedSessionSegment: Value(exercise.sessionSegment),` in the same companion insert — this is the exact seam RESEARCH.md's Pitfall 1 warns is easy to miss (it happens "several files away from the schema change").

---

### `lib/features/workouts/data/circuits_repository.dart` (modify: program-day link)

**Analog:** `addCircuitToSession`/`addCircuitToTemplate` in the same file (lines 158-277, read in full above)

**Pattern to extend, not fork** — both existing methods follow: look up circuit → look up exercises → compute next `supersetGroup` → transaction inserting one row per circuit exercise with `supersetGroup: Value(group)`:
```dart
final maxGroup = existingSessionExercises
    .map((r) => r.supersetGroup ?? 0)
    .fold<int>(0, (a, b) => a > b ? a : b);
final group = maxGroup + 1;
...
await _db.into(_db.workoutExercises).insert(
  WorkoutExercisesCompanion.insert(
    sessionId: sessionId,
    exerciseId: ce.exerciseId,
    orderIndex: nextOrder++,
    supersetGroup: Value(group),
    targetRestSeconds: Value(circuit.restSeconds),
  ),
);
```
**Apply to:** per RESEARCH.md's recommended option 1 (Metcon & Circuit Domain section), a new method (e.g. `materializeCircuitToProgramDay`) that writes `ProgramDayExercises` rows sharing a `supersetGroup`-equivalent, each tagged `sessionSegment = metcon`, following this exact loop-and-transaction shape rather than introducing a new `programDayId` FK on `WorkoutCircuits` (rejected alternative per RESEARCH.md's Alternatives Considered / design option 2).

---

### `lib/features/workouts/domain/workout_duration_estimator.dart` (modify: capped-duration)

**Analog:** `estimateExercise`/`estimateSession` in the same file (61 lines, read in full above)

**Pattern to mirror** — pure static method on the `abstract final class`, itemized not flat, returns `Duration`:
```dart
static Duration estimateExercise({
  required int workingSets,
  required int repsMin,
  required int repsMax,
  required int restSeconds,
  required SetType setType,
  List<WarmupStep> warmupSteps = const [],
  bool isUnilateral = false,
}) {
  ...
  return Duration(seconds: totalSeconds.round());
}
```
**Apply as:** a new static method (e.g. `estimateCappedSegment({required int capSeconds})`) that returns `Duration(seconds: capSeconds)` directly for AMRAP/EMOM/For-Time metcon segments — per RESEARCH.md Pitfall 3, document explicitly that the cap is used as a conservative upper bound, not a predicted actual duration. Feed its result into `estimateSession`'s existing `Iterable<Duration>` parameter (line 49-52) rather than changing that method's signature.

---

### `lib/features/programs/data/smart_program_planner.dart` (modify: wire in new planners + guard)

**Analog:** same file, `_needsFor`'s existing `gpp`/`trainingStyle.isConditioningFirst` branches (lines 1219-1229) — this is the exact dispatch point where `crossfit_program_planner.dart`/`gpp_program_planner.dart` get called from.

**Regression test target** (see Testing section below) — `_methodFor`/`_needsFor` combination at lines 1178-1198 + 1219-1224 is what the new "no GPP day ever produces `dynamicEffort`" test asserts against; do not change this logic's guard shape when integrating, only extend `_needsFor`'s dispatch.

---

### `assets/data/exercise_programming_metadata.json` (modify: curate `prerequisiteSlugs`)

**Analog:** existing correctly-gated entries in the same file — `bar-muscle-up`/`ring-muscle-up` (`prerequisiteSlugs: ['pull-up', 'chest-dips']`, `scalingGroup: 'vertical_pull'`) and `handstand-push-up` (`prerequisiteSlugs: ['pike-push-up']`, `scalingGroup: 'handstand_pushup'`) — confirmed via RESEARCH.md's direct JSON reads.

**Pattern to copy:** add matching `prerequisiteSlugs` arrays to `kipping-muscle-up`, `strict-muscle-up` (mirror `bar-muscle-up`'s `['pull-up', 'chest-dips']`), and the 6 Olympic-tagged exercises (`power-clean`, `hang-power-clean`, `clean-and-jerk`, `power-snatch`, `hang-snatch`, `squat-snatch`) per Phase 16's own stated-but-unshipped intent (front-squat/overhead-press → clean & jerk). This is a JSON data edit, not a schema change — no migration chore needed, but re-run `lib/data/local/exercise_importer.dart`'s import path (or its test) to confirm the new prerequisite data lands in drift rows.

## Shared Patterns

### "No safe candidate, never silently relax" (CLAUDE.md-aligned)
**Source:** `lib/features/programs/domain/exercise_scaling_resolver.dart` lines 30-111
**Apply to:** `crossfit_scaling_policy.dart` (all three D-06 axes), any new GPP/DE structural-exclude regression test, and `gpp_program_planner.dart`'s content selection — always return an explicit no-match result with rationale rather than falling through to a permissive default.

### Enum-with-`.id`-string persisted, safe `fromId` lookup
**Source:** `lib/features/workouts/domain/set_type.dart` lines 45-67, `lib/features/programs/domain/slot_role.dart` lines 21-30
**Apply to:** `session_segment.dart`'s new `SessionSegment` enum — same `.id` + `fromId` shape, but nullable-returning per D-01 (unlike the two analogs, which have non-null fallbacks).

### Additive drift schema bump — five chores, `addIfMissing` guard
**Source:** `lib/data/local/database.dart` lines 1049-1140 (v40/v43 precedent), `supabase/migrations/20260915000000_slot_prescription_codec_v43.sql`
**Apply to:** every one of the three new `sessionSegment`/`plannedSessionSegment` columns — schemaVersion bump, `onUpgrade` branch, drift schema dump/generate, `test/migration_test.dart` + `test/schema_v2*.dart` retargeting, and the matching Supabase migration, per CLAUDE.md's mandatory checklist.

### `SlotRole.isHeavy`-gated Dynamic Effort exclusion
**Source:** `lib/features/programs/data/smart_program_planner.dart` lines 1178-1198, 1219-1224; `lib/features/programs/domain/slot_role.dart` line 34
**Apply to:** every new GPP/CrossFit segment-slot assignment in `crossfit_program_planner.dart`/`gpp_program_planner.dart` — never assign `SlotRole.main`/`supplemental` to a GPP-day or metcon-segment slot; keep on `SlotRole.conditioning` (or a new non-heavy role if one is introduced) to preserve the existing structural guard.

### Superset-group-style row linking for multi-movement groups
**Source:** `lib/features/workouts/data/circuits_repository.dart` lines 172-216 (`addCircuitToSession`'s `supersetGroup` computation)
**Apply to:** the new circuit-to-program-day materialization method, and by extension how `crossfit_program_planner.dart` groups multi-movement metcon rows under one `sessionSegment = metcon` tag with a shared group number.

## No Analog Found

None — every file in scope has a strong existing analog in the codebase; this phase is explicitly additive glue over Phases 16-18's infrastructure (per RESEARCH.md's own framing), not greenfield architecture.

## Metadata

**Analog search scope:** `lib/features/programs/domain/`, `lib/features/programs/data/`, `lib/features/workouts/domain/`, `lib/features/workouts/data/`, `lib/data/local/`, `supabase/migrations/`, `assets/data/`, `test/` (targeted files named in RESEARCH.md's Validation Architecture section)
**Files scanned:** 12 read in full or targeted-range (slot_role.dart, set_type.dart, exercise_scaling_resolver.dart, tables.dart×3 sections, database.dart migration block, smart_program_planner.dart×2 sections, planned_session_resolver.dart×2 sections, circuits_repository.dart full, workout_duration_estimator.dart full, one Supabase migration full, two test file headers)
**Pattern extraction date:** 2026-09-16
