# Phase 28: Adaptive TDEE & Activity Calibration - Pattern Map

**Mapped:** 2026-09-28
**Files analyzed:** 33 new/modified (incl. generated and test files)
**Analogs found:** 30 / 33 (3 generated artifacts have no hand-written analog, only a generator command)

All paths below are relative to `C:\Users\marti\AMS d.o.o\Herculex`. Line numbers were read on 2026-09-28 against branch `refactor/lib-restructure`.

## Corrections to RESEARCH.md the planner must absorb

These are things RESEARCH.md states or omits that the code contradicts. Each one changes the plan.

1. **Two more places must register the new synced table, or sync and fresh installs silently break.** RESEARCH.md only lists `schemaVersion`, `onUpgrade`, the drift dump and the supabase SQL. A synced table is also declared in:
   - `lib/data/local/database.dart:21-92` `@DriftDatabase(tables: [...])`. Without it `tdeeEstimates` does not exist as an accessor.
   - `lib/data/local/migrations/sync_backfill.dart:8-56` `syncedTableNames`. `onCreate` (`database.dart:117-122`) loops this list to create `idx_sync_uuid_<table>`, and `installSyncTriggers` uses it for the outbox triggers. Missing here means a fresh install never pushes the table.
   - `lib/data/sync/sync_table_specs.dart:112-392` `syncTableSpecs`. This is what decides a table is synced at all (see the header of `supabase/migrations/0015_...sql`, lines 1-9).
   - The upgrade branch must also create the `sync_uuid` unique index and call `installSyncTriggers(this)`, exactly as the `from < 32` and `from < 34` blocks do (`database.dart:809-820`, `836-848`). RESEARCH.md's snippet shows only `m.createTable(tdeeEstimates)`, which would leave upgraded installs with no outbox trigger.
2. **`baselineTargetsProvider` is not the only caller of `MacroTargets.fromProfile`.** Two others bypass it:
   - `lib/features/nutrition/presentation/views/nutrition_targets_view.dart:1387` (`TargetEditorView.initState`) pre-fills the very "Maintenance calories" field D-05 decorates. If this is not switched to `ref.read(baselineTargetsProvider)`, the badge would show one number and the field another.
   - `lib/features/profile/presentation/dream_physique_view.dart:410` (display only in `_buildSetupView`).
3. **`fromProfile` bakes the goal adjustment into "baseline".** `macro_targets.dart:37-44` adds -500 / +300 / 0 by `FitnessGoal`, and the editor then labels that number "Maintenance calories" (`nutrition_targets_view.dart:1405`). A measured TDEE is true maintenance. The planner must decide explicitly whether the new provider (a) returns pure TDEE and drops the goal delta, or (b) applies the same goal delta on top of the estimate to preserve today's behaviour. Doing neither cleanly double-applies the goal in some paths. The macro split (1.8 g/kg protein, 27.5% fat, carbs remainder, `macro_targets.dart:46-50`) must be extracted so both the cold-start and estimate paths share it.
4. **Existing widget tests will break silently if `baselineTargetsProvider` starts depending on a DB-backed provider.** `test/features/nutrition/nutrition_targets_view_test.dart:32-45` overrides only `sharedPreferencesProvider`, `profileProvider` and `nutritionTargetsProvider`. Any new provider that touches `appDatabaseProvider` must be added to that harness (and to `weekly_calories_test.dart`, `health_integration_phase6_test.dart`, the other two files that reference these providers) as `latestTdeeEstimateProvider.overrideWith((ref) => Stream.value(null))`, or the provider must degrade to the cold-start seed on loading/error.
5. **`averageWeeklyMacroProvider` is a bad style reference.** RESEARCH.md cites it (line ~887) as the house style for derive-from-history providers, but it calls `DateTime.now()` at `nutrition_providers.dart:892` and `nutritionHistoryProvider` does the same at `:877`. Same for `widgetMacroSyncControllerProvider` (`:791`) and `JointPainRepository.setStatus` (`joint_pain_repository.dart:45`). Copy their structure, not their clock access. `NutritionRepository` (`nutrition_repository.dart:11-15`) is the correct model: `Clock` injected through the constructor.
6. **`nutrition_providers.dart` is already ~930 lines and `nutrition_targets_view.dart` is 2617 lines** (RESEARCH.md says 1450+). New providers should go in a new `application/tdee_providers.dart`. Only the two-line edit to `baselineTargetsProvider` should touch `nutrition_providers.dart`. Watch for an import cycle: `tdee_providers.dart` must not import `nutrition_providers.dart` if `nutrition_providers.dart` imports it. Keep the recalibration controller (which needs `nutritionRepositoryProvider`) in a separate file from the `latestTdeeEstimateProvider` that `baselineTargetsProvider` watches, or let `TdeeEstimatesRepository` query `food_entries` itself.
7. **Three ActivityLevel edit surfaces exist, not one** (D-12/D-13): onboarding (`onboarding_view.dart:367-404`), Profile (`profile_view/_body.part.dart:438-456` with `_identity.part.dart:369-391` tiles), and the Nutrition goals sheet (`goals_view.dart:248-266`, `769-834`). D-13 names Profile only. Decide whether `goals_view` is relabelled too or left alone.
8. **`schema_v25/27/28/29_test.dart` still target `newVersion: 39` / `migrateAndValidate(db, 39)`** while `schemaVersion` is 44 (grep of `test/`). CLAUDE.md step 4 says to retarget them. Confirm whether they are currently failing or skipped before assuming the retarget is a one-line change.
9. **No `test/generated_migrations` fixture exists for v33, v35, v36.** Irrelevant here, but the new replay must start from `startAt(44)`, and `drift_schema_v44.json` / `schema_v44.dart` exist, so that works.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `lib/features/nutrition/domain/tdee_estimate.dart` (new) | model | transform | `lib/features/nutrition/domain/target_resolver.dart` (`TargetRule`, lines 6-27) | role-match |
| `lib/features/nutrition/domain/tdee_estimator.dart` (new) | service (pure) | transform | `lib/features/nutrition/domain/target_resolver.dart` + `diet_phase.dart` constants | exact (shape) |
| `lib/features/nutrition/domain/activity_classifier.dart` (new) | service (pure) | transform | `lib/features/health/domain/activity_adjuster.dart` | role-match |
| `lib/features/nutrition/domain/macro_targets.dart` (modify) | utility | transform | itself, lines 21-58 | exact |
| `lib/data/local/tables.dart` (add `TdeeEstimates`) | model (drift table) | CRUD | `JointPainLogs` (`tables.dart:1152-1169`) | exact |
| `lib/data/local/database.dart` (v45) | migration | batch | `from < 32` block (`:809-820`) + `from < 44 && to >= 44` guard style (`:1150`) | exact |
| `lib/data/local/migrations/sync_backfill.dart` (modify) | config | batch | `syncedTableNames` entry `'joint_pain_logs'` (`:53`) | exact |
| `lib/data/sync/sync_table_specs.dart` (modify) | config | request-response | `SyncTableSpec('body_measurements')` (`:141`) | exact |
| `drift_schemas/drift_schema_v45.json` (generated) | config | - | `drift_schema_v44.json` | generated |
| `test/generated_migrations/schema_v45.dart` + `schema.dart` (generated) | test fixture | - | `schema_v44.dart` | generated |
| `supabase/migrations/20260928000000_tdee_estimates_v45.sql` (new) | migration | CRUD | `supabase/migrations/0014_joint_pain_logs.sql` | exact |
| `lib/features/nutrition/data/tdee_estimates_repository.dart` (new) | repository | CRUD + read-aggregate | `nutrition_repository.dart` (Clock, ranges) + `joint_pain_repository.dart` (thin event-log shape) | role-match |
| `lib/features/nutrition/application/tdee_providers.dart` (new) | provider | event-driven / stream | `recovery_providers.dart:13-21` + `widgetMacroSyncControllerProvider` (`nutrition_providers.dart:790-872`) | role-match |
| `lib/features/nutrition/application/nutrition_providers.dart` (modify `:69-73`) | provider | request-response | itself | exact |
| `lib/app/app.dart` (modify `:691-702`) | config | event-driven | `ref.watch(widgetMacroSyncControllerProvider)` at `:695` | exact |
| `lib/features/nutrition/presentation/views/nutrition_targets_view.dart` (modify `:1387`, add badge near `:1593`) | component | request-response | `profile_view.dart` + `profile_view/*.part.dart` | exact (part-split pattern) |
| `lib/features/nutrition/presentation/sheets/tdee_estimate_sheet.dart` (new) | component (sheet) | request-response | `HxSheet` (`design_system/components/hx_sheet.dart`) + `goals_view.dart:769-834` | role-match |
| `lib/features/nutrition/presentation/widgets/tdee_estimate_badge.dart` OR `nutrition_targets_view/_tdee_badge.part.dart` (new) | component | request-response | `_MacroBadge` (`nutrition_targets_view.dart:1032`), `_PhaseChipButton` (`:600`) | role-match |
| `lib/features/onboarding/presentation/onboarding_view.dart` (copy edit `:371-374`) | component | request-response | itself | exact |
| `lib/features/profile/presentation/profile_view/_body.part.dart` (label edit `:439`) | component | request-response | itself | exact |
| `lib/features/nutrition/presentation/views/goals_view.dart` (optional `:799`) | component | request-response | itself | exact |
| `lib/features/profile/presentation/dream_physique_view.dart` (`:410`) | component | request-response | `baselineTargetsProvider` reads elsewhere | partial |
| `test/tdee_estimator_test.dart` (new) | test | transform | `test/diet_phase_test.dart` | exact |
| `test/activity_classifier_test.dart` (new) | test | transform | `test/diet_phase_test.dart` | exact |
| `test/target_resolver_test.dart` (new) | test | transform | `test/diet_phase_test.dart` | exact |
| `test/tdee_estimates_repository_test.dart` (new) | test | CRUD | `test/joint_pain_repository_test.dart` + `_FixedClock` in `test/fasting_repository_test.dart:8-12` | exact |
| `test/migration_test.dart` (retarget 44 to 45, add v44 to v45 replay) | test | batch | itself, lines 20-56 | exact |
| `test/tdee_supabase_migration_test.dart` (new) | test | file-I/O | `test/program_builder_supabase_migration_test.dart` | exact |
| `test/features/nutrition/nutrition_targets_view_test.dart` (extend) | test | request-response | itself, lines 32-45 | exact |
| `test/features/nutrition/tdee_providers_test.dart` (new) | test | event-driven | `test/features/nutrition/average_weekly_intake_test.dart` | role-match |
| `test/schema_v25/27/28/29_test.dart` (retarget) | test | batch | themselves | exact |

---

## Pattern Assignments

### `lib/features/nutrition/domain/tdee_estimate.dart` (model, transform)

**Analog:** `lib/features/nutrition/domain/target_resolver.dart` lines 1-42. Plain const value classes that mirror a DB row "without depending on the generated DB class, so the resolver stays pure / unit-testable."

**Imports pattern** (line 1): one `package:herculex/...` import, no Flutter, no drift.

**Value-class pattern** (lines 6-27):
```dart
class TargetRule {
  final int kcal;
  final int proteinG;
  ...
  /// `global` | `training_day` | `rest_day` | `weekday:N` | `date:yyyy-mm-dd`
  final String appliesTo;

  const TargetRule({
    required this.kcal,
    ...
    required this.appliesTo,
  });

  MacroTargets get macros =>
      MacroTargets(kcal: kcal, proteinG: proteinG, carbsG: carbsG, fatG: fatG);
}
```
**Enum-with-label pattern** (`profile.dart:23-41`): `enum X { a, b; String get label => switch (this) {...} static X fromName... }`. Use this for `TdeeMethod { observed, classifier, coldStart }` and `TdeeConfidence { high, medium, low }`. Add a `fromName` with an `orElse` default (see `Meal.fromName` in `meal.dart:23-24`) because RESEARCH.md's security table requires validating the closed-vocabulary TEXT columns at the repository boundary.

Keep the `TdeeEstimateResult` free of `TdeeEstimateData` (the generated drift class), same as `TargetRule` is free of `NutritionTargetData`.

---

### `lib/features/nutrition/domain/tdee_estimator.dart` (service, transform)

**Analog:** `lib/features/nutrition/domain/target_resolver.dart` (static methods over plain data, date passed in) and `lib/features/nutrition/domain/diet_phase.dart:74-93` (all tunables as named `static const` on one class).

**Tunable-constants pattern** (`diet_phase.dart:74-93`):
```dart
  static const defaultCutPct = 20.0;
  static const defaultBulkPct = 10.0;
  static const defaultMaingainSurplusKcal = 150;
  ...
  static const maintainFatShare = 0.275;
```
Put the A1-A6 assumption constants (min/default/cap window 14/28/35, 70% food bar, weight-log floor, `hysteresisCycles = 2`, grace 7 days, `ewmaAlpha = 0.1`, `kcalPerKg = 7700.0`, shift floor 100 kcal / 5%) in one `abstract final class`/static-const block at the top of this file. The RESEARCH.md Assumptions Log says these must be trivially retunable.

**Pure-static, time-as-parameter pattern** (`target_resolver.dart:96-108`):
```dart
  static int reductionSteps(DietScheduleRule schedule, DateTime date) {
    ...
    final today = DateTime(date.year, date.month, date.day);
    final days = today.difference(start).inDays;
```
`TdeeEstimator.estimate(..., required DateTime asOf)`. Never call `DateTime.now()` (CLAUDE.md Clock rule; RESEARCH.md Pitfall 1).

**Pure static pow helper precedent** (`target_resolver.dart:157-163`): the file hand-rolls `_pow` rather than importing `dart:math`. Not required to copy, but shows the domain layer's dependency-minimal style.

**Date-key convention:** use `dateIso(DateTime)` / `parseDateIso(String)` from `lib/features/nutrition/domain/meal.dart:27-45` for `yyyy-MM-dd` keys. Do not re-implement (`joint_pain_repository.dart:103-104` and `nutrition_providers.dart:117` both hand-roll it, which is the drift to avoid). `meal.dart` imports Flutter icons (line 20 shows `Icons.cookie_outlined`), so importing it into `domain/` violates "domain is plain Dart". Either keep the estimator's inputs keyed by `DateTime`/`String` and let the repository format them, or note that `TargetResolver` already inlines its own ISO formatting (`target_resolver.dart:68-71`). Recommend inlining a private `_iso` in the estimator to keep the domain file Flutter-free.

**Formula bodies:** copy from RESEARCH.md "Code Examples" (observed-expenditure, `ewmaTrend` with gap-fill, `isMaterialShift`). These have no closer real analog. One correction: `ewmaTrend` should return the trend at both window start and end (the observed formula needs `startTrendWeightKg` and `endTrendWeightKg`), not a single scalar.

---

### `lib/features/nutrition/domain/activity_classifier.dart` (service, transform)

**Analog:** `lib/features/health/domain/activity_adjuster.dart` lines 1-77. CONTEXT.md and RESEARCH.md both say shape reference only.

**Result-class + static-method shape** (lines 1-33):
```dart
class ActivityAdjustmentResult {
  final double volumeFactor;
  final String statusLabel;
  final String message;

  const ActivityAdjustmentResult({ ... });

  static const normal = ActivityAdjustmentResult(...);
  static const unavailable = ActivityAdjustmentResult(...);   // explicit "no data" sentinel
}

class ActivityBasedAdjuster {
  static ActivityAdjustmentResult suggest({
    required double todaySteps,
    required double baselineSteps,
    double? sleepHours,
    double? restingHr,
  }) { ... }
}
```
Copy: (a) a named `unavailable` sentinel for "no HealthSamples at all" so the caller falls through to cold start; (b) optional `sleepHours`/`restingHr` params (secondary, confidence-affecting only per RESEARCH.md #6); (c) `double` averages in, plain result out. Do not copy its step thresholds (25000/18000/14000), which drive training volume, not TDEE.

The `HealthSamples` `kind` values are `steps | sleep_hours | active_kcal | resting_hr` (`tables.dart:1125-1126`), but `health_service.dart:535-536` also writes `food_kcal` and `weight_kg` rows into the same table. The classifier must filter by kind and must not treat those as activity.

**Anchor-interpolation:** no analog. Use RESEARCH.md's 3000 to 1.20, 7500 to 1.375, 10000 to 1.55, 15000 to 1.725 table. Return a `double multiplier`, never an `ActivityLevel`.

---

### `lib/features/nutrition/domain/macro_targets.dart` (modify, transform)

**Analog:** itself. Current code to split (lines 21-58):
```dart
  static MacroTargets? fromProfile(Profile profile) {
    final w = profile.weightKg; final h = profile.heightCm; final a = profile.ageYears;
    if (w == null || h == null || a == null) return null;

    final offset = (profile.sex == BiologicalSex.female) ? -161 : 5;
    final bmr = 10 * w + 6.25 * h - 5 * a + offset;
    final multiplier = switch (profile.activityLevel) {
      ActivityLevel.sedentary => 1.2,
      ActivityLevel.lightlyActive => 1.375,
      ActivityLevel.active => 1.55,
      ActivityLevel.veryActive => 1.725,
    };
    final tdee = bmr * multiplier;
    final adjusted = tdee + switch (profile.goal) { ...-500 / +300 / 0 };

    final protein = (w * 1.8).round();
    final fatKcal = adjusted * 0.275;
    ...
```
Refactor into three pieces, keeping `fromProfile`'s signature and return unchanged (14 call sites, see Shared Patterns):
1. `static double? bmr(Profile)`: Mifflin-St Jeor, null-guarded.
2. `static double multiplierFor(ActivityLevel)`: the switch above (cold-start seed and D-14 reseed).
3. `static MacroTargets fromKcal(Profile, double kcal)` or `fromMultiplier(profile, multiplier)`: goal adjustment plus macro split. RESEARCH.md Open Question 2 leaves the name open. `fromProfile` becomes `fromMultiplier(profile, multiplierFor(profile.activityLevel))`.

This file is 59 lines and has **no existing test** (`test/` has no `macro_targets_test.dart`). Add a characterization test before refactoring: for each `ActivityLevel` x `FitnessGoal`, snapshot the current `fromProfile` output, then assert the refactor is byte-identical.

Note the existing doc comment (lines 16-20) says "Assumes male; sex isn't captured" but the code at line 28 does read `profile.sex`. Update the comment while in there.

---

### `lib/data/local/tables.dart` add `TdeeEstimates` (model, CRUD)

**Analog:** `JointPainLogs` (`tables.dart:1152-1169`), the closest "append-mostly, synced, user-scoped event log". Place it next to it, not at the end, so the "health-adjacent synced" doc comment convention is kept.

```dart
/// One joint-pain status change ... Synced: deliberately user-entered
/// health-adjacent data ...
@DataClassName('JointPainLogData')
class JointPainLogs extends Table with SyncColumns, SyncTombstone {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get dateIso => text()();
  DateTimeColumn get loggedAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get joint => text()(); // one of JointModel.joints
  IntColumn get severity => integer().withDefault(const Constant(1))();
  TextColumn get note => text().nullable()();
}
```
`@DataClassName('TdeeEstimateData')` is mandatory (CLAUDE.md; default pluralisation makes `TdeeEstimate` clash-free here but the annotation is a house rule). Columns per RESEARCH.md: `dateIso`, `method`, `confidence`, `windowDays`, `kcal`, `inputsJson`. `SyncColumns` (`tables.dart:14-20`) supplies `syncUuid`, `updatedAt`, `syncedAt`; `SyncTombstone` (`:22-24`) supplies `deletedAt`.

**Timestamp column decision:** CONTEXT D-11 says "timestamp" and RESEARCH.md's cadence code uses `last.estimatedAt`, but RESEARCH.md's schema has only `dateIso`. Two estimates on one day would be indistinguishable and `updatedAt` is a sync clock, not a domain field (see `SyncTableSpec.columnRenames` doc, `sync_table_specs.dart:87-91`, for what happens when a local `updated_at` means something else). If an `estimatedAt DateTimeColumn` is added, it **must** be registered in the spec's `dateTimeColumns: ['estimated_at']` and be `timestamptz` in Postgres. Analog: `SyncTableSpec('joint_pain_logs', dateTimeColumns: ['logged_at'])` at `sync_table_specs.dart:144`, with `logged_at timestamptz not null default now()` at `0014_joint_pain_logs.sql:13`.

Doc-comment convention: every table carries a comment explaining why it is or is not synced. State that `HealthSamples` (`tables.dart:1121-1128`) is not.

---

### `lib/data/local/database.dart` (v45 bump) (migration, batch)

**Three edits, all in one file.**

**1. Table list** (`database.dart:21-92`): add `TdeeEstimates,` (analog: `JointPainLogs,` at `:53`).

**2. Version** (`:101`): `int get schemaVersion => 44;` to `45`.

**3. `onUpgrade` branch.** Best combined analog is the sync-table creation idiom from `from < 32` (`:809-820`) written in the newer `&& to >= N` guard style from `:1150`:
```dart
      if (from < 32) {
        await m.createTable(jointPainLogs);
        await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_sync_uuid_joint_pain_logs '
          'ON joint_pain_logs(sync_uuid)',
        );
        await installSyncTriggers(this);
      }
```
```dart
      if (from < 44 && to >= 44) {
        ... addIfMissing helper using pragma_table_info ...
```
For a new table the equivalent is:
```dart
      if (from < 45 && to >= 45) {
        await m.createTable(tdeeEstimates);
        await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_sync_uuid_tdee_estimates '
          'ON tdee_estimates(sync_uuid)',
        );
        await installSyncTriggers(this);
      }
```
CLAUDE.md says to guard against fixtures that are too narrow or already current. `m.createTable` on a table that already exists throws. `from < 42` (`:1122-1124`) calls `m.createTable(programSlotExplanations)` unguarded and passes because no fixture is built from current definitions at v41 or below. Confirm the same is true for v44 by running the new replay. If it throws, guard with `sqlite_master` (same idiom as `beforeOpen` at `:1208`).

**Do not** hand-write an index for `date_iso`. RESEARCH.md suggests one. Local queries at one row per ~week do not need it, and an extra index is one more thing the `schema dump` snapshot must match. The Postgres-side `(user_id, updated_at, id)` index is the one that matters (see the SQL section).

**Fresh installs:** `onCreate` (`:105-132`) needs no edit beyond adding the table to `syncedTableNames`, because it does `m.createAll()` then loops `syncedTableNames` for the unique index and calls `installSyncTriggers`.

---

### `lib/data/local/migrations/sync_backfill.dart` (config, batch)

**Analog:** the list at `:8-56`. Append `'tdee_estimates',` after `'workout_circuits'`/`'circuit_exercises'` (the last two entries are appended in creation order, not dependency order, at `:53-55`; the list header says it "mirrors" the SQL, and `sync_table_specs.dart:394-398` says the *specs* list carries the dependency order). No FK dependencies, so no ordering constraint.

---

### `lib/data/sync/sync_table_specs.dart` (config, request-response)

**Analog:** `:141-144`, plain tables with no FK, no local-only columns:
```dart
  const SyncTableSpec('body_measurements'),
  const SyncTableSpec('cycle_logs'),
  const SyncTableSpec('cycle_settings', dateTimeColumns: ['last_period_start']),
  const SyncTableSpec('joint_pain_logs', dateTimeColumns: ['logged_at']),
```
Add `const SyncTableSpec('tdee_estimates'),` (plus `dateTimeColumns: ['estimated_at']` if that column is added) in the Level 0 block (no synced-table dependency). No `fkFields`: the table has none.

`SyncService._buildRemotePayload` does `SELECT *` and forwards every column that is not a registered FK, localOnly, or dateTime column (`0015_...sql:4-6`). Therefore **every local column name, snake_cased, must exist in Postgres** (`date_iso`, `method`, `confidence`, `window_days`, `kcal`, `inputs_json`). A mismatch is a PGRST204 and quarantine after 8 attempts.

---

### `supabase/migrations/20260928000000_tdee_estimates_v45.sql` (migration, CRUD)

**Analog:** `supabase/migrations/0014_joint_pain_logs.sql` (whole file, 42 lines). RESEARCH.md's SQL block is a faithful copy and is correct. Points to carry over:

- Table shape (lines 9-19): `id uuid primary key`, `user_id uuid not null references auth.users(id) on delete cascade`, domain columns, `updated_at timestamptz not null default now()`, `deleted_at timestamptz`.
- Four owner-only policies with the `<table>_<op>_own` naming (lines 23-30).
- Trigger names `t_set_updated_at_<table>` and `t_record_tombstone_<table>` reusing `set_updated_at()` and `public.record_sync_tombstone()` (lines 33-39).
- `alter publication supabase_realtime add table public.<table>;` (line 41).
- Header comment explaining why the wiring is spelled out here rather than in the 0003-0005 loops (lines 1-8).

**Additions RESEARCH.md missed:**
- Add `create index if not exists tdee_estimates_user_updated_idx on public.tdee_estimates (user_id, updated_at, id);`. `0017_sync_indexes.sql:30-53` adds exactly this composite index to every synced table because `SupabaseSyncBackendService.pull()` does `where user_id = ? and updated_at > ? order by updated_at, id`. A post-0017 table without it is a sequential scan on every pull (same pattern as `0017` line 49, format `<table>_user_updated_idx`).
- Filename: the two most recent conventions are `20260916000000_session_segment_v44.sql` (timestamp + `_vNN`) and `0021_ai_usage_bump_per_kind.sql` (numeric, Phase 26). RESEARCH.md picked the timestamp form; keep it.
- Header must state the ordering warning in `0015` lines 23-25: apply before any client carrying local v45 reaches a user. CLAUDE.md says `0015` and `0016` are already outstanding and must be applied first.
- `date_iso text not null` matches `joint_pain_logs.date_iso` (line 12).

Add a plan task to *verify against project ref `ldzgyzigvbwofbswitrv`* (CLAUDE.md Gotchas; RESEARCH.md Pitfall 7). This is a checkpoint, not code.

---

### `lib/features/nutrition/data/tdee_estimates_repository.dart` (repository, CRUD + aggregate reads)

**Analogs:** `lib/features/recovery/data/joint_pain_repository.dart` (thin synced event-log repo, `AppDatabase` constructor, insert via `Companion.insert`, `watch` with `deletedAt.isNull()`), and `lib/features/nutrition/data/nutrition_repository.dart` (Clock injection and date-range queries).

**Constructor + Clock pattern** (`nutrition_repository.dart:11-15`), use this, not JointPainRepository's:
```dart
class NutritionRepository {
  final AppDatabase _db;
  final Clock _clock;

  NutritionRepository(this._db, OpenFoodFactsClient _, this._clock);
```
Imports:
```dart
import 'package:drift/drift.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
```

**Insert pattern** (`joint_pain_repository.dart:46-56`):
```dart
    await _db
        .into(_db.jointPainLogs)
        .insert(
          JointPainLogsCompanion.insert(
            dateIso: _formatDateIso(now),
            loggedAt: Value(now),
            joint: joint,
            severity: Value(severity),
            note: Value(note),
          ),
        );
```
Validate `method`/`confidence` against the enums here, before insert (RESEARCH.md ASVS V5).

**Latest-row query** (`measurements_repository.dart:140-153`): the model for `latestEstimate()` (no `isCurrent` flag, per RESEARCH.md #7):
```dart
    final row =
        await (_db.select(_db.bodyMeasurements)
              ..where((t) => t.metric.equals('bodyweight'))
              ..orderBy([
                (t) => OrderingTerm(expression: t.dateIso, mode: OrderingMode.desc),
              ])
              ..limit(1))
            .getSingleOrNull();
```
Add `..where((t) => t.deletedAt.isNull())` as `joint_pain_repository.dart:64` does, since the table is a tombstone table. Add a secondary `OrderingTerm.desc(t.id)` as `joint_pain_repository.dart:65-68` does so two estimates on one `dateIso` order deterministically. This is the strongest argument for an `estimatedAt` column, or at minimum for `id` tie-break.

**Stream for display** (`joint_pain_repository.dart:62-70`): `.watch()` on the query, mapped to the domain result. CLAUDE.md prefers `StreamProvider` for drift reads.

**Range query for the adherence gate** (`nutrition_repository.dart:637-643`):
```dart
    final entriesQuery = _db.select(_db.foodEntries)
      ..where(
        (t) =>
            t.dateIso.isBiggerOrEqualValue(startIso) &
            t.dateIso.isSmallerOrEqualValue(endIso),
      )
```
The adherence gate needs distinct `dateIso` presence, not summed macros (RESEARCH.md Pitfall 3). Use `selectOnly(distinct: true)` with `addColumns([dateIso])`, as `health_service.dart:272-278` does:
```dart
        await (_db.selectOnly(_db.healthSamples, distinct: true)
              ..addColumns([_db.healthSamples.dateIso])
              ..where(_db.healthSamples.kind.equals('steps')))
            .get();
```
**Must also exclude soft-deleted rows** (`t.deletedAt.isNull()`): `food_entries` and `body_measurements` are tombstone tables, and neither `watchDailyTotalsForRange` (line 637) nor `latestBodyweightKg` (measurements_repository.dart:143) filters them. Deleted food entries would otherwise count as logged days. Check what `deleteMeasurement` (`measurements_repository.dart:111-121`) does: it hard-deletes via `_db.delete(...)`, so the tombstone trigger path applies; but `foods` uses `deletedAt.isNull()` at `nutrition_repository.dart:21`, so the convention is present.

**Daily kcal per day for the intake mean:** the estimator needs per-day kcal, not just presence. `watchDailyTotalsForRange` (`nutrition_repository.dart:630-699`) already computes `Map<String, DailyTotals>` per `dateIso` including snapshot/recipe resolution. Reuse it via `NutritionRepository` (`.first` of the stream, or extract a `Future` sibling) rather than re-deriving kcal from `food_entries` rows. This is the "Don't Hand-Roll" row in RESEARCH.md.

**Bodyweight logs:** `MeasurementsRepository.watchMetric('bodyweight')` (`:60-65`) returns `List<BodyMeasurementData>` ordered by `dateIso`; `logMeasurement` (`:87-109`) enforces one sample per metric per day, so no same-day dedupe is needed.

**Logged training count (classifier "workouts/week"):** analog `NutritionRepository.trainedOn` (`nutrition_repository.dart:1033-1047`): `workoutSessions` where `endedAt.isNotNull()` and `startedAt` in range.

**HealthSamples averages:** analog `HealthService.getAverageSteps` (`health_service.dart:246-270`) filters by `kind` and `dateIso >= cutoff` and averages `.value`. Note it divides by sample count (days with data), which is the right semantics for "avg steps/day over days with data". Accept `Clock` and compute the cutoff from `_clock.now()` (line 247-248), never `DateTime.now()`.

**Provider wiring:** see `tdee_providers.dart` below.

---

### `lib/features/nutrition/application/tdee_providers.dart` (provider, event-driven / stream)

**Analog A (repo + stream provider):** `lib/features/recovery/application/recovery_providers.dart:13-21`:
```dart
final jointPainRepositoryProvider = Provider<JointPainRepository>((ref) {
  return JointPainRepository(ref.watch(appDatabaseProvider));
});

final jointPainStatusesProvider = StreamProvider<Map<String, JointPainStatus>>((
  ref,
) {
  return ref.watch(jointPainRepositoryProvider).watchCurrentStatuses();
});
```
For Clock injection, model on `nutritionRepositoryProvider` (`nutrition_providers.dart:40-46`) which passes `ref.watch(clockProvider)`; `clockProvider` is re-exported from `package:herculex/app/providers.dart` (`providers.dart:25`).

Providers to define: `tdeeEstimatesRepositoryProvider`, `latestTdeeEstimateProvider` (`StreamProvider`, a single-row query), and a recalibration controller.

**Analog B (controller):** `widgetMacroSyncControllerProvider` (`nutrition_providers.dart:790-872`). A `Provider<void>` that `ref.listen`s to inputs and does async work, registered once in `app.dart:695` via `ref.watch(...)`. Copy the structure:
```dart
final widgetMacroSyncControllerProvider = Provider<void>((ref) {
  ...
  Future<void> doSync() async { ... }
  ref.listen<AsyncValue<DailyTotals>>(dailyTotalsProvider(today), (_, next) {
    if (next.hasValue && next.value != null) { doSync(); }
  }, fireImmediately: true);
```
Do **not** copy `final now = DateTime.now();` at line 791. Use `ref.watch(clockProvider).now()`.

RESEARCH.md Pattern 2 sketches a `FutureProvider<void>` gate. The house precedent for "do something once at startup" is the `Provider<void>` watched in `app.dart`, not a `FutureProvider` (a `FutureProvider` is lazy and nothing would watch it). Pick the `Provider<void>` shape and register it in `app.dart` next to line 695. Guard the async body with `try { } catch (_) {}` the way `doSync` does at `:807-818`, since recalibration is background work that must never surface an error state (D-08: "never an error state").

**`autoDispose`:** the baseline path is read by ~14 widgets. Do not make `latestTdeeEstimateProvider` `autoDispose`, or every screen rebuild reruns the query.

---

### `lib/features/nutrition/application/nutrition_providers.dart` (modify `:69-73`)

**Current:**
```dart
/// Profile-derived baseline target (Mifflin-St Jeor). Used as the fallback
/// when no day-specific rule applies.
final baselineTargetsProvider = Provider<MacroTargets?>((ref) {
  final profile = ref.watch(profileProvider).asData?.value;
  if (profile == null) return null;
  return MacroTargets.fromProfile(profile);
});
```
Keep the type `Provider<MacroTargets?>` (14 call sites `ref.watch(baselineTargetsProvider)`, listed in Shared Patterns). Add `ref.watch(latestTdeeEstimateProvider).asData?.value`; if null, return `MacroTargets.fromProfile(profile)` unchanged (D-08 cold start). Otherwise return the estimate-based targets via the extracted `fromKcal`/`fromMultiplier`. The `.asData?.value` idiom is the one the line above already uses.

No change to `effectiveTargetsProvider` (`:88-163`) or `TargetResolver`. Confirm by test (see `test/target_resolver_test.dart`) that `fallback: baseline` (`:149`) is only used when `resolveRule` returns null, i.e. TDEE-04 holds by construction (`target_resolver.dart:151`: `final base = rule?.macros ?? fallback;`).

Add the one-line comment RESEARCH.md #8 asks for at the `DietPhaseCalculator.apply(baselineKcal:` call site noting PHYS-04 belongs at or after that call. That call site is `nutrition_targets_view.dart:204` and `:1449`.

---

### `lib/app/app.dart` (modify around `:691-702`)

**Analog:** the block already there:
```dart
    // Initialize Android home-screen widget sync.
    ref.watch(widgetMacroSyncControllerProvider);
    ...
    ref.watch(syncServiceProvider);
```
Add `ref.watch(tdeeRecalibrationControllerProvider);` with a one-line comment, in the same style. There is no background scheduler (RESEARCH.md; `pubspec.yaml` has no `workmanager`), so app-open plus foreground is the only trigger available. `app.dart` already has app-lifecycle handling and `ref.listen(activeSessionProvider, ...)` at `:715` as precedent for reacting to state changes there. If a resume-triggered recheck is wanted, hook it there rather than in a widget.

---

### `nutrition_targets_view.dart` (modify) and new badge / sheet files (component)

**Structure analog:** `lib/features/profile/presentation/profile_view.dart` + `profile_view/` folder:
```dart
// profile_view.dart:35-39
part 'profile_view/_auth.part.dart';
part 'profile_view/_body.part.dart';
...
// profile_view/_body.part.dart:1
part of '../profile_view.dart';
```
CLAUDE.md and `docs/ARCHITECTURE.md:122-131`: "Parts cannot have their own imports; everything lives in the library file." `nutrition_targets_view.dart` currently has **no** `part` directives; its imports are lines 1-17 and the first declaration is at line 18 (`extension DietPhaseUi`). If a part is used, all imports the part needs go in the library file. `part` filenames use the `_name.part.dart` form inside a folder named after the file (`nutrition_targets_view/`).

**Recommendation (planner decides):** the detail sheet as a public `presentation/sheets/tdee_estimate_sheet.dart`, and the badge as a small public widget in `presentation/widgets/`. Reasons: (1) `docs/ARCHITECTURE.md:44-56` says the filename suffix decides the folder, and nutrition is already split, so `*_sheet.dart` belongs in `sheets/`; (2) ARCHITECTURE.md:130-131 says reusable sub-widgets should be promoted to `widgets/`, and Phase 29's weekly report (D-07/D-10) will want the same estimate-vs-target comparison; (3) a `part` cannot carry imports and cannot be imported by another screen. The only edit inside the 2617-line file is then the badge placement at ~`:1593` and the `:1387` fix. Either route keeps the file from growing materially.

**Where the badge goes** (`nutrition_targets_view.dart:1593-1603`):
```dart
        _NumField(
          controller: _maintenanceKcal,
          label: 'Maintenance calories',
          suffix: 'kcal',
          onChanged: (_) => _applyPhase(_phase),
        ),
        const SizedBox(height: 6),
        Text(
          _phase.subtitle,
          style: TextStyle(color: hx.onSurfaceVariant, fontSize: 12),
        ),
```
The badge goes between the field and the subtitle, or on the same row.

**Also read from `QuickPhasePlanner`** (`:190`, `final baseline = ref.watch(baselineTargetsProvider); final baselineKcal = baseline?.kcal ?? 2500;`) and the hard-coded `'TDEE Maintenance'` label at `:398`. Both silently pick up the new value with no edit; verify visually.

**Sheet shell:** `lib/design_system/components/hx_sheet.dart:11-61`:
```dart
  static Future<T?> show<T>(BuildContext context, {required WidgetBuilder builder}) {
    return showModalBottomSheet<T>(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent, builder: builder,
    );
  }
```
Constructor: `HxSheet(title:, subtitle:, child:, scrollable:, pinnedBottom:)`. Use `HxSheet.show(context, builder: (_) => HxSheet(title: 'How this is estimated', child: ...))`. Do **not** copy `goals_view.dart:769-834`'s `_ActivityLevelSheet`, which hand-rolls the container and reads `AppColors` (the shim that UI-rework Phase 9 is deleting). Use `context.hx` tokens (`hx.onSurfaceVariant`, `HxSpace.x5`) as `nutrition_targets_view.dart` does at `:1602` and `hx_sheet.dart:90-91`.

**Badge styling analog:** the pill at `nutrition_targets_view.dart:385-406` (padding 10x6, `phaseColor.withValues(alpha: 0.15)` fill, 0.4 alpha border, radius 10, bold 12pt text). Reuse the shape; take colours from `context.hx`, not raw `Color(0xFF...)`.

**Tap-to-expand:** wrap in `InkWell`/`GestureDetector` calling `HxSheet.show`. The sheet reads `latestTdeeEstimateProvider`, the current saved `nutritionTargetsProvider` global row (D-07), and decodes `inputsJson` with `dart:convert` (same import as `nutrition_providers.dart:2`). Snapshot vs live is Open Question 3; recommend the snapshot.

**Fix `:1387`:** replace
```dart
    final profile = ref.read(profileProvider).asData?.value;
    final baseline = profile == null ? null : MacroTargets.fromProfile(profile);
```
with `final baseline = ref.read(baselineTargetsProvider);` (keep `profile` only if still used; `_bodyweightKg` at `:1440` reads it separately).

---

### Activity-level copy changes (component)

D-12 to D-15 are copy and label edits only. **No write-path change**, and `profile.activityLevel` stays the seed (`macro_targets.dart:30`).

| Surface | Location | Current | Change |
|---|---|---|---|
| Onboarding | `onboarding_view.dart:371-374` | `"What is your activity level?"` heading, `displayMedium` | D-12 copy: "How active are you right now? We'll refine this automatically as you log." |
| Profile | `profile_view/_body.part.dart:438-456` | `_SectionHeader('Activity Level')` then `_ActivityTile` list, saved via `_onFieldChanged()` | D-13 relabel as a manual reset/nudge, visible after calibration. `_SectionHeader` is used the same way at `:472` (`'App Settings'`). |
| Profile tile descriptions | `_identity.part.dart:387-392` | static `_descriptions` map | probably unchanged |
| Nutrition goals sheet | `goals_view.dart:248-266`, `799` | `_editActivityLevel` saves via `localProfileRepositoryProvider.save(profile.copyWith(activityLevel: level))` | Decide (see Correction 7) |

D-14/D-15 (reseed only; does not force method back to "Calibrating" when observed mode qualifies) fall out of the design for free: the write path only changes `profile.activityLevel`; the estimator's method selection never reads it except for the cold-start seed and classifier seed. Assert with a test. `profile_view/_body.part.dart:206` builds the whole `Profile` from local state on every field change, so verify that saving does not trigger anything that clears `tdee_estimates` history.

---

## Test Pattern Assignments

### Domain unit tests: `test/tdee_estimator_test.dart`, `test/activity_classifier_test.dart`, `test/target_resolver_test.dart`

**Analog:** `test/diet_phase_test.dart`. Flat `group` / `test`, plain `flutter_test`, one import of the file under test, no ProviderContainer:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';

void main() {
  group('DietPhaseCalculator.apply', () {
    test('maintain leaves calories untouched', () {
      final t = DietPhaseCalculator.apply(
        phase: DietPhase.maintain, baselineKcal: 2500, bodyweightKg: 80,
      );
      expect(t.kcal, 2500);
```
Top-level `test/` is where domain tests live (`test/diet_phase_test.dart`, `test/streaks_test.dart`), matching RESEARCH.md's `flutter test test/tdee_estimator_test.dart` commands. (There is also a `test/features/<name>/` tree, used for newer nutrition tests such as `test/features/nutrition/minimum_targets_test.dart`. Either location passes the RESEARCH.md commands only if those commands are updated to match.)

`test/target_resolver_test.dart` for TDEE-04: assert `TargetResolver.resolve(rules: [globalRule], fallback: baseline)` returns the rule's `macros`, not `fallback`, and that `fallback` is returned when `rules` is empty. Also boundary tests for `isMaterialShift` at exactly the 100 kcal and 5% thresholds (`>` not `>=`, per RESEARCH.md's code and D-09 "exceeds").

### Repository test: `test/tdee_estimates_repository_test.dart`

**Analog:** `test/joint_pain_repository_test.dart:1-47` (`openTestDatabase()`, `setUp`/`tearDown` closing the DB) plus the `_FixedClock` idiom (13 test files copy-paste it; e.g. `test/fasting_repository_test.dart:8-12`):
```dart
class _FixedClock implements Clock {
  DateTime time;
  _FixedClock(this.time);
  @override
  DateTime now() => time;
}
```
`openTestDatabase()` (`test/support/test_database.dart:19-28`) uses an in-memory `AppDatabase.forTesting`, which has `seedFoodCatalogue = false` (`database.dart:98`), so no food catalogue interferes with adherence counts.

Also add a test that the `tdee_estimates` table gets an outbox trigger, modelled on `test/buddy/buddy_local_only_test.dart` but inverted: assert it *is* in `syncedTableNames` and `syncTableOrder`, and that an insert enqueues a `pending_sync_ops` row. That test is the guard against Correction 1.

### Migration test: `test/migration_test.dart`

**Analog:** the file itself.
- Header comment (`:3`): `drift_schema_v44.json` to `v45`.
- Every `verifier.migrateAndValidate(db, 44)` (roughly 20 call sites: lines 23, 30, 62, 93, 137, 206 ... 336) to `45`.
- Add the new step test, modelled on `:26-56` (currently v43 to v44), and change that test's target from 44 to 45:
```dart
  test('upgrades cleanly from a generated v44 fixture to v45', () async {
    final connection = await verifier.startAt(44);
    final db = AppDatabase.forTesting(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 45);

    final columns = await db.customSelect('PRAGMA table_info(tdee_estimates)').get();
    expect(columns.map((row) => row.read<String>('name')), contains('inputs_json'));
  });
```
- Assert the sync wiring landed on upgrade: query `sqlite_master` for `idx_sync_uuid_tdee_estimates` and for a trigger on `tdee_estimates` (the `sqlite_master` trigger query is the technique cited in `11-03-SUMMARY.md`).

The two `schema dump` / `schema generate` commands in CLAUDE.md produce `drift_schemas/drift_schema_v45.json` and `test/generated_migrations/schema_v45.dart`, and update `schema.dart`. There is no hand-written analog for these; run the generators.

### Supabase SQL test: `test/tdee_supabase_migration_test.dart`

**Analog:** `test/program_builder_supabase_migration_test.dart` (56 lines). Read the file as text, lowercase it, assert on `create table`, `enable row level security`, owner policy names, the trigger names, and `alter publication supabase_realtime add table`. Adjust the assertions for the `0014` style (unqualified `create table tdee_estimates`, `user_id = auth.uid()`), not the `v39` style (`create table public.$table`, `(select auth.uid()) = user_id`). Add an assertion that every local drift column name appears in the SQL, which is a cheap guard for the PGRST204 failure mode.

### Widget test extension: `test/features/nutrition/nutrition_targets_view_test.dart`

**Analog:** itself. Extend `testApp` overrides (`:32-45`) with `latestTdeeEstimateProvider.overrideWith((ref) => Stream.value(null))` so the existing four tests keep passing (Correction 4), then add new cases per state (observed / classifier / coldStart / stale) using overrides of `latestTdeeEstimateProvider` with fixture `TdeeEstimateData` values. Pattern to follow:
```dart
      await tester.pumpWidget(testApp(const TargetEditorView()));
      await tester.pumpAndSettle();
      expect(find.text('DIETING PHASE'), findsOneWidget);
```
`TargetEditorView` tests should assert that the pre-filled maintenance field equals the estimate, not `MacroTargets.fromProfile(...)` (regression test for `:1387`).

### Provider test: `test/features/nutrition/tdee_providers_test.dart`

**Analog:** `test/features/nutrition/average_weekly_intake_test.dart:38-57`: `ProviderContainer(overrides: [...])`, `addTearDown(container.dispose)`, `await container.read(x.future)`. Override `clockProvider` with a `_FixedClock` and `appDatabaseProvider` with `openTestDatabase()` for the controller test. Do not copy that file's `DateTime.now()` use at line 12.

---

## Shared Patterns

### Clock discipline (all new code)
**Source:** `lib/core/utils/clock.dart:1-13`; re-exported by `package:herculex/app/providers.dart:25`.
**Apply to:** `tdee_estimator.dart` (via an `asOf` parameter), `tdee_estimates_repository.dart` (constructor `Clock`), `tdee_providers.dart` (`ref.watch(clockProvider).now()`), all tests (`_FixedClock`).
Known violators not to copy: `nutrition_providers.dart:791`, `:877`, `:892`; `joint_pain_repository.dart:45`; `measurements_repository.dart:34`.

### Imports
**Source:** CLAUDE.md. Always `package:herculex/...`; `part`/`part of` stay relative. Cross-directory `export` is not lint-covered.

### Riverpod: stream for drift reads, `Provider<void>` for startup controllers
**Source:** `recovery_providers.dart:17-21` (stream), `nutrition_providers.dart:790` (controller), `app.dart:695` (registration).

### Manual target always wins (TDEE-04)
**Source:** `target_resolver.dart:138-155` and `nutrition_providers.dart:127-150`.
```dart
    final base = rule?.macros ?? fallback;
```
No new flag or column is needed (RESEARCH.md anti-pattern: no `isManual` on `TdeeEstimates`). Only a test is missing.

### Callers of `baselineTargetsProvider` (all keep working if the type stays `Provider<MacroTargets?>`)
`dashboard_providers.dart:164`, `dashboard_view.dart:427`, `recipe_builder_view.dart:141`, `nutrition_view.dart:263`, `nutrition_targets_view.dart:190`, `nutrient_overview_view.dart:29`, `trend_cards.dart:29`, `hercul_providers.dart:206`, `calorie_meal_goals_view.dart:15`, `calorie_macro_goals_view.dart:13`, `nutrition_providers.dart:93,422,423,801,802`, `log_entry_sheet.dart:1351`, `goals_providers.dart:337`, `profile_view/_target_cards.part.dart:15`.
Note `hercul_providers.dart:206` and `nutrition_providers.dart:422,801` use `ref.read`, so they see whatever value is current at read time. That is fine for cold-start but means a slow first estimate emission will be visible there as the seed value.

### Synced-table registration checklist (five places, plus SQL)
1. `tables.dart` class with `SyncColumns, SyncTombstone` and `@DataClassName`.
2. `database.dart` `@DriftDatabase(tables: [...])` list.
3. `sync_backfill.dart` `syncedTableNames`.
4. `sync_table_specs.dart` `syncTableSpecs`.
5. `database.dart` `onUpgrade` block with `createTable`, unique `sync_uuid` index, `installSyncTriggers`.
6. `supabase/migrations/*.sql` with RLS, triggers, publication, and the `(user_id, updated_at, id)` index.
Follow with CLAUDE.md steps 2-4 (dump, generate, retarget tests).

### Error handling for background work
**Source:** `nutrition_providers.dart:807-818`: `try { ... } catch (_) {}` around DB reads inside the sync controller. Recalibration must never throw into the UI; the fallback is always the cold-start seed (D-08).

### Security: owner-only RLS
**Source:** `0014_joint_pain_logs.sql:21-30`. All four operations, `user_id = auth.uid()`. Treat `inputs_json` as display-only (RESEARCH.md security table).

---

## No Analog Found

| File / Concern | Role | Data Flow | Reason |
|---|---|---|---|
| EWMA with linear gap-fill (inside `tdee_estimator.dart`) | utility | transform | No smoothing or time-series code exists under `lib/features/nutrition/domain/`. Use RESEARCH.md's snippet, corrected to return start and end trend. |
| Continuous step-anchor interpolation (inside `activity_classifier.dart`) | utility | transform | `ActivityBasedAdjuster` uses stepped thresholds, not interpolation. Coefficients are LOW confidence (A7). |
| Method-hysteresis / grace-period state machine | service | event-driven | Nothing similar. The persisted `tdee_estimates` history is the state (RESEARCH.md #3, #4): "2 consecutive qualifying rows" and "last observed row age < 7 days" are queries over recent rows. Needs the repository to return the last N rows, not just the latest. |
| `drift_schema_v45.json`, `schema_v45.dart` | generated | - | Produced by `dart run drift_dev schema dump` / `schema generate`. |

---

## Open items for the planner (not decided by CONTEXT or RESEARCH)

1. Goal-adjustment handling (Correction 3): pure maintenance vs preserve `-500/+300`.
2. Whether `tdee_estimates` gets an `estimatedAt` `DateTimeColumn` (affects SQL, `dateTimeColumns` spec, ordering, and the 7-day cadence math; RESEARCH.md uses `last.estimatedAt` but its schema lacks it).
3. Badge and sheet as `part` files (CONTEXT/RESEARCH wording) vs public `widgets/` + `sheets/` files (ARCHITECTURE.md wording). Recommendation above is public files.
4. Whether `goals_view.dart`'s activity sheet is relabelled (D-13 names only Profile).
5. What to do with the stale `schema_v25/27/28/29_test.dart` targets (39 vs 44).
6. Phase 23 (PHYS-04) is not built; add only the comment at the two `DietPhaseCalculator.apply` call sites.

## Metadata

**Analog search scope:** `lib/features/nutrition/**`, `lib/features/health/**`, `lib/features/recovery/{data,application}`, `lib/features/measurements/data`, `lib/features/profile/{domain,presentation}`, `lib/features/onboarding/presentation`, `lib/data/local/**`, `lib/data/sync/sync_table_specs.dart`, `lib/design_system/components/hx_sheet.dart`, `lib/app/{app,providers}.dart`, `supabase/migrations/**`, `test/**` (migration, sync, nutrition, support), `drift_schemas/`, `docs/ARCHITECTURE.md`.
**Files scanned:** ~55 read or grepped directly.
**Pattern extraction date:** 2026-09-28
