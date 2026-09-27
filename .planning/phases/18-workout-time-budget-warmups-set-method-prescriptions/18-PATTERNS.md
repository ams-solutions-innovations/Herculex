# Phase 18: Workout Time Budget, Warmups & Set Method Prescriptions - Pattern Map

**Mapped:** 2026-09-15
**Files analyzed:** 16
**Analogs found:** 13 / 16

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `lib/features/programs/domain/slot_prescription_codec.dart` (new) | model/codec (domain) | transform (JSON encode/decode) | `lib/features/programs/domain/slot_prescription.dart` (`WorkSegment`/`SlotPrescription`, itself) | role-match (sibling in same file/domain, no codec precedent exists) |
| `lib/features/programs/domain/slot_prescription.dart` (modify — add `toJson`/`fromJson` or codec hooks) | model | transform | itself (existing `format()`/`scaled()`/`copyWith` value-object conventions) | exact |
| `lib/features/workouts/domain/workout_duration_estimator.dart` (new) | service (domain) | transform (pure calculation) | `lib/features/programs/data/smart_program_planner.dart` `_timePlanFor` (lines 1354-1385) — the single existing time-estimation rule being replaced | role-match |
| `lib/features/workouts/domain/warmup_resolver.dart` (new) | service (domain) | transform (pure calculation) | `lib/features/workouts/data/planned_session_resolver.dart` `_automaticWarmups`/`_maxEffortSets` (lines 497-524, 592-648) — the fixed ramp tables being replaced | exact (replaces this code directly) |
| `lib/features/programs/data/smart_program_planner.dart` (modify — replace `templateSets` JSON write + `_timePlanFor`) | service (data) | CRUD (program generation writes `ProgramDayExercisesCompanion`) | itself | exact |
| `lib/features/workouts/data/planned_session_resolver.dart` (modify — `_resolvePrescription`, drop `_automaticWarmups`/`_maxEffortSets`/`_copiedTemplateSets`, read codec column) | service (data) | CRUD/transform (resolves DB rows → `PlannedSessionSnapshot`) | itself | exact |
| `lib/features/workouts/domain/set_type.dart` (modify — expose which `SetType`s are "advanced/intensity" for gating) | model (enum) | transform | itself | exact |
| `lib/features/workouts/presentation/widgets/set_type_menu.dart` (modify — hard-hide advanced items for `SlotRole.main`) | component | request-response (bottom-sheet selection UI) | itself | exact |
| `lib/features/programs/presentation/views/program_preview_view.dart` (modify — render codec set detail) | component (view) | request-response | itself | exact |
| `lib/features/programs/presentation/widgets/week_board.dart` (modify) | component | request-response | itself | exact |
| `lib/features/programs/presentation/widgets/day_column_card.dart` (modify) | component | request-response | itself | exact |
| `lib/features/programs/presentation/sheets/day_detail_sheet.dart` (modify) | component | request-response | itself | exact |
| `lib/features/programs/presentation/views/block_builder_view.dart` (modify — wire opt-in toggle near lines 781-790, otherwise untouched per D-03) | component (view) | request-response | itself | exact |
| `lib/data/local/tables.dart` (modify — new/replaced codec column on `ProgramDayExercises`, likely also `WorkoutExercises`/`SetEntries` if the resolved session also stores codec-shaped data) | model (drift table def) | CRUD | itself (`prescriptionJson` column, `tables.dart:836-837`) | exact |
| `lib/data/local/database.dart` (modify — `schemaVersion` bump + `onUpgrade` step) | config/migration | batch | itself, `onUpgrade` step for `from < 41`/`from < 42` (lines 1093-1124) | exact |
| `supabase/migrations/NNNN_slot_prescription_codec_v43.sql` (new) | migration | batch | `supabase/migrations/20260913000000_exercise_programming_metadata_v41.sql` | exact |
| `test/support/test_database.dart` (reused, not modified) | test util | — | itself | exact |

## Pattern Assignments

### `lib/features/programs/domain/slot_prescription_codec.dart` (model/codec, transform)

**Analog:** `lib/features/programs/domain/slot_prescription.dart` (whole file, esp. lines 39-129, 135-175)

**Existing value-object conventions to mirror** (`WorkSegment`, lines 39-49, 78-98):
```dart
class WorkSegment {
  const WorkSegment({
    required this.sets,
    required this.repsMin,
    int? repsMax,
    this.intent = Intent.rir2,
    this.percentOf1Rm,
    this.setType = SetType.standard,
    this.restSeconds,
    this.meta = const {},
  }) : repsMax = repsMax ?? repsMin;
  ...
  WorkSegment copyWith({...}) { ... }
}
```
No `toJson`/`fromJson` exists anywhere on `SlotPrescription`/`WorkSegment`/`Intent` today (confirmed by grep) — the codec is genuinely new. Model it as a **separate encode/decode class** (`SlotPrescriptionCodec.encode(SlotPrescription) -> String`, `.decode(String) -> SlotPrescription`) rather than adding `toJson` directly onto the domain class, matching this codebase's existing separation of "plain Dart domain model" (`slot_prescription.dart`, no Flutter/JSON import) from "how it's persisted" (JSON assembly lives in the **data** layer today, e.g. `smart_program_planner.dart`'s inline `jsonEncode({...})` at lines 1370-1383, and `planned_session_resolver.dart`'s `_copiedTemplateSets`/`jsonDecode` at lines 554-588). Keep the codec itself in `domain/` (per CONTEXT D-01 note) but written as plain Dart with `dart:convert` only — no drift/Flutter imports, consistent with `slot_prescription.dart`'s own import list (single import: `set_type.dart`).

**Versioned-envelope precedent** — the closest existing "versioned JSON blob with a discriminator" pattern in this codebase is the ad-hoc `templateSets` shape being replaced:
```dart
// smart_program_planner.dart:1371-1383 — the shape being superseded
prescriptionJson: jsonEncode({
  'templateSets': [
    {
      'setOrder': 1,
      'targetRepsMin': 12,
      'targetRepsMax': 20,
      'setType': SetType.myoReps.id,
      'setTypeMetaJson': jsonEncode({'activationReps': 15, 'miniSets': 3}),
    },
  ],
}),
```
and its decode counterpart:
```dart
// planned_session_resolver.dart:554-588 — _copiedTemplateSets
static List<PlannedSetSnapshot>? _copiedTemplateSets(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final rows = decoded['templateSets'];
    if (rows is! List || rows.isEmpty) return null;
    return [ ... ];
  } catch (_) {
    return null;
  }
}
```
Per D-04, the new codec does **not** need to read this old shape — but the try/catch-around-`jsonDecode`-returning-null-on-failure idiom is the established error-handling convention for this codebase's ad-hoc JSON columns and should carry over to the new codec's `decode`.

**Enum `id`/`fromId` serialization idiom to reuse for the wire format** (`Intent`, lines 8-35; `SlotRole`, `slot_role.dart` lines 5-30; `SetType`, `set_type.dart` lines 45-67):
```dart
const Intent(this.id, this.label, {required this.rir});
final String id;
static Intent fromId(String? id) =>
    values.firstWhere((i) => i.id == id, orElse: () => Intent.rir2);
```
Every stable-string enum in this codebase follows `id` field + `fromId(String?)` with a safe fallback (never throws on unknown/legacy values) — the codec's JSON keys for `Intent`/`SetType`/`SlotRole` should serialize via `.id` and decode via `.fromId(...)`, not `.name`.

---

### `lib/features/workouts/domain/workout_duration_estimator.dart` (service, transform)

**Analog:** `lib/features/programs/data/smart_program_planner.dart`, `_timePlanFor` (lines 1354-1385) — the single rule being replaced, and the surrounding `_Target`/`_TimePlan` value types used to carry results back into generation.

```dart
// smart_program_planner.dart:1354-1369 — current (single-rule) time logic,
// showing the "static method on the resolver taking a Configuration object,
// returning a small value type" shape to follow for the estimator
static _TimePlan _timePlanFor({
  required SlotRole role,
  required _Target target,
  required SmartProgramConfiguration configuration,
}) {
  final canCompress =
      configuration.allowTimeSavingSetTechniques &&
      configuration.workoutDurationMinutes <= 45 &&
      role == SlotRole.isolation;
  if (!canCompress) return _TimePlan.standard(target);
  ...
}
```
The new `WorkoutDurationEstimator` should be a pure/static-method domain class (no Flutter, no drift) callable from `smart_program_planner.dart`'s generation loop, mirroring how `_timePlanFor` is invoked per-slot inside the same loop that builds `_Target`s. Since D-05 requires feedback into generation (trim until ±10%), structure it as `estimate(session) -> Duration` plus a separate trim-decision entry point consumed by the planner's slot loop — keep the *trimming policy* (D-07: accessory/isolation first) in `smart_program_planner.dart` (the existing home of slot-priority logic, see `priorityLevel`/`focusWeight` handling at lines 1330-1341) and the *pure estimate* in the new domain file, matching the existing split between "domain enums/pure functions" and "data-layer orchestration with DB access."

**Itemization inputs (D-06)** — unilateral-work and rest-pause/myo-reps mini-set costs are values the estimator needs from `SetType` (`set_type.dart` lines 45-51, `volumeFactor`/`cnsFactor`) and from `WorkSegment.meta` (`slot_prescription.dart` lines 63-64, `meta['miniSets']`/`meta['restSeconds']` — see `SetType.restPause`/`myoReps`'s declared `metaKeys` at `set_type.dart:10-17`). Read set-count/timing directly off `WorkSegment`/`SetType`, do not re-derive from strings.

---

### `lib/features/workouts/domain/warmup_resolver.dart` (service, transform)

**Analog:** `lib/features/workouts/data/planned_session_resolver.dart`, `_automaticWarmups` (lines 497-524) and `_maxEffortSets` (lines 592-648) — the exact code this file replaces (D-10).

```dart
// planned_session_resolver.dart:497-524 — fixed ramp table being replaced;
// shows the PlannedSetSnapshot construction pattern the resolver expects
static List<PlannedSetSnapshot> _automaticWarmups({
  required SlotRole role,
  required String mechanics,
  required String modality,
}) {
  final eligible =
      (role == SlotRole.main || role == SlotRole.supplemental) &&
      mechanics == 'compound' &&
      const {'barbell', 'dumbbell', 'kettlebell'}.contains(modality);
  if (!eligible) return const [];
  final ramps = role == SlotRole.main
      ? const [(0.40, 8), (0.55, 5), (0.70, 2)]
      : const [(0.40, 8), (0.60, 4)];
  return [
    for (final (index, ramp) in ramps.indexed)
      PlannedSetSnapshot(
        index: index + 1,
        repsMin: ramp.$2,
        repsMax: ramp.$2,
        isWarmup: true,
        setType: 'standard',
        intent: Intent.technical.id,
        rir: Intent.technical.rir,
        rpeX10: (Intent.technical.rpe * 10).round(),
        percentOf1Rm: ramp.$1,
      ),
  ];
}
```
`WarmupResolver` should keep the exact same output contract (`List<PlannedSetSnapshot>`, `isWarmup: true`, `intent: Intent.technical.id`) so `planned_session_resolver.dart`'s call site (lines 279-292, the `[...automaticWarmups, ...workingSets]` splice with re-indexing) needs zero changes beyond swapping the call. Per D-08/D-09, replace the fixed `(percent, reps)` tuple list with a computed ramp keyed on target `%1RM` (density) and a `isFirstHeavyLiftInSession` flag (abbreviation) — both of these are values the caller (`planned_session_resolver.dart`, which already tracks `role`, iterates `day.exercises` in `orderIndex` order, and resolves `prescription.prescription.segments.first.percentOf1Rm`) can supply without new state.

**`_maxEffortSets`'s explicit-ramp-then-work pattern** (lines 592-648) is the other reference for "how ramps are represented as ordinary `PlannedSetSnapshot`s with `isWarmup: true`" — reuse this shape for `WarmupResolver`'s output rather than inventing a separate warmup type.

---

### `lib/features/programs/data/smart_program_planner.dart` (service, CRUD — modify)

**Analog:** itself. `SmartProgramConfiguration` (fields `workoutDurationMinutes` line ~context, `allowTimeSavingSetTechniques` lines 38/86) is the existing config surface D-05/D-11 extend.

```dart
// smart_program_planner.dart:38, 86
this.allowTimeSavingSetTechniques = false,
...
final bool allowTimeSavingSetTechniques;
```
No new field name is prescribed by CONTEXT — extend this existing boolean's *meaning* (global opt-in for drop/rest-pause/myo/AMRAP per D-11) rather than adding a parallel flag, and keep it read at the same call site (`_timePlanFor`, being replaced) plus wherever set-type selection happens during generation.

---

### `lib/features/workouts/data/planned_session_resolver.dart` (service, CRUD/transform — modify)

**Analog:** itself, `_resolvePrescription` (lines 402-478) — "the reference implementation the codec's decode path must match exactly" per CONTEXT's Integration Points note. Any codec-decode path added here must produce output structurally identical to what `_resolvePrescription` + `_setsFromPrescription` (lines 526-552) already produce, since D-02 requires preview/session byte-parity.

```dart
// planned_session_resolver.dart:526-552 — canonical SlotPrescription -> PlannedSetSnapshot list
// (the function the codec's decode path must reproduce for D-02 parity)
static List<PlannedSetSnapshot> _setsFromPrescription(
  SlotPrescription prescription,
) {
  final out = <PlannedSetSnapshot>[];
  var index = 1;
  for (final segment in prescription.segments) {
    for (var i = 0; i < segment.sets; i++) {
      out.add(PlannedSetSnapshot(
        index: index++,
        repsMin: segment.repsMin,
        repsMax: segment.repsMax,
        isWarmup: false,
        setType: segment.setType.id,
        intent: segment.intent.id,
        rpeX10: (segment.intent.rpe * 10).round(),
        rir: segment.intent.rir,
        percentOf1Rm: segment.percentOf1Rm,
        setTypeMetaJson: segment.meta.isEmpty ? null : jsonEncode(segment.meta),
      ));
    }
  }
  return out;
}
```

---

### `lib/features/workouts/presentation/widgets/set_type_menu.dart` (component, request-response — modify)

**Analog:** itself, the category-filtered item lists (lines 446-454) and per-category rendering loops (lines 579-631).

```dart
// set_type_menu.dart:446-454 — existing category filter idiom to extend
static final List<SetTypeInfo> _hypertrophyItems = SetTypeInfo.all
    .where((i) => i.category == SetTypeCategory.hypertrophy)
    .toList();
```
D-13 requires a hard hide (no visible-but-blocked state) for `SlotRole.main`. The cleanest fit with existing structure: thread a `bool allowAdvancedTechniques` (derived from `role != SlotRole.main` — reusing D-12's exact predicate — combined with the program's `allowTimeSavingSetTechniques` toggle) into `SetTypeMenu`/`SetTypeMenu.show(...)`, and filter `_hypertrophyItems`/relevant AMRAP entry the same way `_hypertrophyItems` is already built — i.e. add a `.where(...)` clause at the same three list-construction sites (lines 446-454), not a runtime disabled-state on the tile widgets (`_SquircleSetTypeTile` has no disabled/greyed rendering today — do not add one, since D-13 wants pure absence).

**Static registry to extend for "is this an advanced/gated technique" predicate:** `SetTypeInfo.all`/`SetTypeCategory.hypertrophy` (lines 72-341) already groups drop/restPause/myoReps under `hypertrophy` category, and `amrap` under `timed`. The gating predicate needs to special-case `amrap` (per D-13's explicit list) since it's in a different `SetTypeCategory` than the other three — do not gate the whole `timed` category.

---

### `lib/features/programs/presentation/views/program_preview_view.dart`, `week_board.dart`, `day_column_card.dart`, `day_detail_sheet.dart` (components, request-response — modify)

**Analog:** each other / themselves — these four files form one existing call chain (`program_preview_view.dart` → `week_board.dart` → `day_column_card.dart` → `day_detail_sheet.dart`) rendering session-level info only today; D-02 upgrades all four to render codec-decoded set-by-set detail. No external analog needed — read the current props/data each widget receives from its parent and extend that same prop-drilling chain to carry decoded `SlotPrescription`/`WorkSegment` data (via `SlotPrescriptionCodec.decode`) down from wherever `program_preview_view.dart` currently fetches program data.

*(Not read in full this pass — line-numbered excerpts were not required since the pattern is "extend the existing prop chain," not "copy from an unrelated analog." When planning, read these four files directly for their current data-fetching provider and prop signatures before drafting the PLAN.)*

---

### `lib/features/programs/presentation/views/block_builder_view.dart` (component, request-response — modify, narrow scope per D-03)

**Analog:** itself, the existing `allowTimeSavingSetTechniques` switch UI at lines ~781-790 (per CONTEXT canonical_refs). D-11's opt-in toggle is this existing switch's semantics extended, not new UI — locate and reuse the exact `Switch`/`SwitchListTile` widget already there; do not add a second toggle.

---

### `lib/data/local/tables.dart` + `lib/data/local/database.dart` (model/migration — modify)

**Analog:** itself. Existing `prescriptionJson` column on `ProgramDayExercises`:
```dart
// lib/data/local/tables.dart:836-837
TextColumn get prescriptionWhy => text().nullable()();
TextColumn get prescriptionJson => text().nullable()();
```
**`onUpgrade` guarded-addColumn idiom** (`database.dart:1093-1121`, the most recent step, `from < 41`):
```dart
if (from < 41 && to >= 41) {
  final catalogueExists = await customSelect(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' "
    "AND name = 'exercise_catalog'",
  ).getSingleOrNull();
  if (catalogueExists != null) {
    final existingColumns = (await customSelect(
      "SELECT name FROM pragma_table_info('exercise_catalog')",
    ).get()).map((r) => r.read<String>('name')).toSet();
    final newColumns = <GeneratedColumn>[];
    for (final col in exerciseCatalog.$columns) {
      if (!existingColumns.contains(col.$name)) newColumns.add(col);
    }
    await m.alterTable(TableMigration(exerciseCatalog, newColumns: newColumns));
  }
}
if (from < 42 && to >= 42) {
  await m.createTable(programSlotExplanations);
}
```
Current `schemaVersion => 42` (`database.dart:101`). Phase 18's new/replaced codec column is `schemaVersion => 43`, with a new `if (from < 43 && to >= 43) { ... }` block following this exact `pragma_table_info` guard idiom (per CLAUDE.md: "Guard `addColumn` steps against `pragma_table_info` rather than running them unconditionally"). Note the codebase's per-column `addIfMissing` helper (`database.dart:1054-1066`, `from < 40` block) is the reusable local closure pattern for guarding a single new column if only one column is added.

**Test retargeting per CLAUDE.md checklist** — `test/migration_test.dart` calls `verifier.migrateAndValidate(db, 42)` at every replay call site (13 occurrences found); each becomes `43`. `test/generated_migrations/schema_v42.dart` is the newest fixture (`ProgramDayExercises extends Table with TableInfo` at line 4028) — dump a new `schema_v43.dart`/`drift_schema_v43.json` per the standard `drift_dev schema dump`/`generate` commands in CLAUDE.md, and add one new replay test from `schema_v42.dart` (mirroring the existing "newest fixture" replay blocks, e.g. lines 136-153/247-258 in `migration_test.dart`).

---

### `supabase/migrations/NNNN_slot_prescription_codec_v43.sql` (migration, batch — new)

**Analog:** `supabase/migrations/20260913000000_exercise_programming_metadata_v41.sql` (most recent), full file:
```sql
alter table public.exercise_catalog
  alter column programming_commonness set default 'manualOnly',
  add column if not exists disciplines text not null default '[]',
  ...;

alter table public.exercise_catalog
  drop constraint if exists exercise_catalog_programming_commonness_check;
alter table public.exercise_catalog
  add constraint exercise_catalog_programming_commonness_check
    check (...) not valid;
alter table public.exercise_catalog
  validate constraint exercise_catalog_programming_commonness_check;
```
Naming convention: `YYYYMMDDHHMMSS_description_vNN.sql` where `vNN` matches the drift `schemaVersion`. Use `add column if not exists` (idempotent), and the `drop constraint if exists` → `add constraint ... not valid` → `validate constraint` three-step for any check constraints on the new codec column's version/shape (if one is added). Per CLAUDE.md, this migration is only required **if the table is synced** — confirm `program_day_exercises` (or wherever the codec column lands) is in `SyncService`'s synced-table list before writing it.

## Shared Patterns

### Enum stable-string serialization
**Source:** `slot_role.dart:21-30`, `set_type.dart:45-67`, `slot_prescription.dart:22-34`
**Apply to:** `SlotPrescriptionCodec` wire format for `Intent`, `SetType`, `SlotRole`
```dart
final String id;
static T fromId(String? id) => values.firstWhere((e) => e.id == id, orElse: () => <safeDefault>);
```
Always serialize via `.id`, decode via `.fromId(...)` with a non-throwing fallback — never `.name`/`.index`.

### `PlannedSetSnapshot` as the universal resolved-set shape
**Source:** `planned_session_resolver.dart` (`_automaticWarmups`, `_setsFromPrescription`, `_maxEffortSets`, `_copiedTemplateSets` — all four independently construct `PlannedSetSnapshot` lists)
**Apply to:** `WarmupResolver`, `WorkoutDurationEstimator`, and the codec's decode path
Every warmup/working-set producer in this codebase converges on `List<PlannedSetSnapshot>` before `PrescriptionResolver` splices/re-indexes them (`planned_session_resolver.dart:279-292`, `.indexed.map((entry) => entry.$2.copyWith(index: entry.$1 + 1))`). New warmup/estimator code should target this same output type so the splice-and-reindex call site needs no changes.

### `SlotRole.isHeavy` / `SlotRole.main` as the eligibility gate
**Source:** `slot_role.dart:34` (`bool get isHeavy => this == SlotRole.main || this == SlotRole.supplemental;`)
**Apply to:** D-07 (trim protection: `isHeavy`), D-12/D-13 (technique gating: `== SlotRole.main` specifically, not `isHeavy`)
Do not conflate these two predicates — D-07 uses the broader `isHeavy`, D-12 uses the narrower `== SlotRole.main` directly (no existing `isMain`-style getter; add one to `slot_role.dart` if repeated 3+ times, otherwise inline `role == SlotRole.main`).

### `pragma_table_info`-guarded additive migrations
**Source:** `database.dart:1054-1066`, `1093-1121`
**Apply to:** the new `schemaVersion => 43` `onUpgrade` block
Every additive column/table change since v40 checks `pragma_table_info`/`sqlite_master` before altering, because hand-written migration-test fixtures sit at varying points of schema completeness. New steps must follow this guard, per CLAUDE.md's explicit instruction.

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `lib/features/programs/domain/slot_prescription_codec.dart` | codec | transform | No versioned JSON codec exists anywhere in the codebase today — closest precedent is the ad-hoc, unversioned `templateSets` blob being replaced (see excerpt above), which is explicitly *not* a pattern to imitate (no version field, no schema). Design fresh per CONTEXT's "Claude's Discretion" note on wire-format naming. |
| `lib/features/workouts/domain/workout_duration_estimator.dart` | service | transform | No existing duration/time-budget estimator; `_timePlanFor` is a single fixed rule (isolation + ≤45min → myo-reps), not a per-exercise itemized estimate. Build from D-06's itemization list directly. |
| `lib/features/workouts/domain/warmup_resolver.dart` | service | transform | Existing warmup logic (`_automaticWarmups`, `_maxEffortSets`) is fixed-table, not formula-driven; D-08/D-09's intensity/order-scaling has no existing analog beyond the output-shape contract (`PlannedSetSnapshot`) noted above. |

## Metadata

**Analog search scope:** `lib/features/programs/`, `lib/features/workouts/`, `lib/data/local/`, `supabase/migrations/`, `test/`
**Files scanned:** ~12 read in full/targeted excerpt, plus directory listings of `supabase/migrations/` and `drift_schemas/`
**Pattern extraction date:** 2026-09-15
