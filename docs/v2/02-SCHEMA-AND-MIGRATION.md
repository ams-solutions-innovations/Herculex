# Herculex V2 — Database Schema Proposal & Migration Plan

All changes are **additive** (new tables + nullable/defaulted columns). No existing column is renamed, retyped, or dropped, so every existing row remains valid with zero data rewriting. `exercises.json` and `ExerciseImporter` are untouched.

> **Schema is at v23** (this doc's tables above describe up through v12; see
> `docs/fk-enforcement-remediation-progress.md` for what v13–v23 added, most
> recently RB-04's FK enforcement work). As of v23, **`PRAGMA foreign_keys`
> is ON** for every connection (`beforeOpen` in `lib/data/local/database.dart`)
> — all 36 declared `references(..., onDelete: KeyAction.x)` edges are live,
> not just declared. Consequently:
> - Migrations still run with FKs **OFF** — `onCreate`/`onUpgrade` execute
>   inside drift's migration transaction, and SQLite silently ignores the
>   pragma when set inside one, so `beforeOpen` (after the transaction
>   commits) is the only correct place to turn it on. Do not move it.
> - Any future constraint change (rename/retype/drop a column involved in a
>   FK, or change an `onDelete` action) cannot be a plain `ALTER TABLE` —
>   SQLite can't alter a declared constraint in place. Use the 12-step
>   `legacy_alter_table` rebuild recipe recorded in the plan doc referenced
>   above, and dump a `drift_schemas/` snapshot (via `dart run drift_dev
>   schema dump`, kept up to date per "Schema tooling" below) before making
>   the change, since `TableMigration` needs one.

## Schema v10 — Logging Foundation (Phase 1)

### New tables

```
gyms                 id, name, isDefault(bool, def false), createdAt
accessories          id, name, kind(belt|knee_sleeves|wrist_wraps|straps|fat_grips|chains|custom),
                     forearmMultiplier(real, def 1.0), isCustom(bool), seeded defaults
bands                id, name, color, tensionKg(real), isCustom(bool), seeded common set
set_accessories      id, setEntryId→set_entries(cascade), accessoryId→accessories(restrict),
                     UNIQUE(setEntryId, accessoryId)
set_bands            id, setEntryId→set_entries(cascade), bandId→bands(restrict),
                     count(int, def 1), mode(assistance|resistance)
machine_settings     id, exerciseId→exercise_catalog(cascade), gymId→gyms(nullable, setNull),
                     label, settingsJson, updatedAt        # saved configs, recalled per gym
body_measurements    id, dateIso, metric(text: bodyweight|arms_l|arms_r|chest|waist|hips|
                     thigh_l|thigh_r|calf_l|calf_r|neck|back|custom:<name>), value(real)
progress_photos      id, dateIso, pose(front|side|back), filePath(local only), notes
```

### Altered tables (new columns only)

```
workout_sessions   + gymId(nullable → gyms, setNull)
workout_exercises  + equipmentVariant(text, nullable; null ⇒ catalog modality)
                   + machineConfigJson(text, nullable; per-log machine settings snapshot)
set_entries        + setType(text, def 'standard')        # see SetType registry below
                   + setTypeMetaJson(text, nullable)      # dropPercent, pauseSeconds, miniSets…
                   + bodyweightKg(real, nullable)         # BW snapshot for weighted-BW total load
                   + chainsKg(real, nullable)             # avg chain contribution at lockout/2
```

`SetType` registry (domain enum, stored as text — extensible without migration):
`standard, warmup, drop, rest_pause, partials, myo_reps, pyramid, forced, negatives,
pause (meta: pauseSeconds), mechanical_drop, giant, pre_exhaustion, twenty_ones,
volume_20x60 (meta: percent), down_sets (meta: startReps, decrement), amrap, emom, for_time`.
Supersets keep using the existing `WorkoutExercises.supersetGroup`.

### Effective load (single source of truth, used by ALL engines)

```
effectiveKg = weightKg
            + (supportsWeightedBodyweight && bodyweightKg != null ? bodyweightKg : 0)
            + Σ bands: tensionKg × count × (mode == resistance ? +0.5 : −0.5)   # avg over ROM
            + (chainsKg ?? 0)                                                    # already averaged
tonnage     = effectiveKg × reps × setTypeVolumeFactor(setType, meta)
```

## Schema v11 — Periodization & Micro Workouts (Phase 4)

```
exercise_rotations      id, name, movementPattern, rotateEveryWeeks(1–4)
rotation_members        id, rotationId(cascade), exerciseId(restrict), orderIndex
program_day_exercises   + rotationId(nullable), + setType, + percentOf1Rm(nullable),
                        + equipmentVariant(nullable)
programs                + periodizationModel(linear|concurrent|block|max_effort|none)
program_weeks           + blockPhase(accumulation|transmutation|realization, nullable)
                        + intensityFactor(real, def 1.0)
micro_workouts          id, name, exerciseId(restrict), targetReps, timesPerDay,
                        intervalHours, active(bool)
micro_workout_logs      id, microWorkoutId(cascade), completedAt, reps
exercise_progressions   id, exerciseId, goal(strength|hypertrophy|fat_loss|endurance|athletic),
                        weeklyIncreasePct(real, def 5.0), enabled
```

## Schema v12 — Nutrition Expansion (Phase 5)

```
foods                + sodiumMgPer100g, potassiumMgPer100g, cholesterolMgPer100g (nullable)
food_micros          id, foodId(cascade), nutrient(text), amountPer100g, unit
nutrition_targets    id, label, kcal, proteinG, carbsG, fatG, fiberG(nullable),
                     appliesTo(global|training_day|rest_day|weekday:<n>|date:<iso>)
diet_schedules       id, startDateIso, reducePct, intervalDays, active
carb_cycle_plans     id, weekStartIso, dayLevelsJson('["high","med","low",…]'), auto(bool)
```

## Migration plan

1. Each version bump follows the existing pattern: `m.createTable(...)` / `m.addColumn(...)` in `onUpgrade`, then idempotent seeding (accessories, bands) guarded by a count check.
2. **Back-fill rules:** `equipmentVariant = NULL` reads as the catalog row's `modality` (the spec's "null equipment ⇒ default barbell/dumbbell based on original modality") — implemented in the read path, no data rewrite needed.
3. Old sets have `setType = 'standard'` via column default — historic tonnage is unchanged because `setTypeVolumeFactor('standard') = 1`.
4. `ExerciseImporter.runFromAsset` re-runs are already idempotent (unique key `(name, equipment)`); v10 does not re-run it.
5. **Tests:** `test/schema_v10_test.dart` verifies fresh-create seeds + defaults; effective-load unit tests pin tonnage math; existing `exercise_importer_test.dart` and `recovery_engine_test.dart` must stay green (back-compat proof).

## Indexes

Drift creates FK indexes implicitly only for `references()` lookups via query plans; add explicit indexes where queries filter hot paths:
`set_entries(workoutExerciseId)`, `set_accessories(setEntryId)`, `food_entries(dateIso)`,
`body_measurements(dateIso, metric)`, `workout_sessions(gymId)` — added as `customStatement` in the v10 branch.
