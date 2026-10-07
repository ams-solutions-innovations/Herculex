# Phase 16: Exercise Programming Metadata & Discipline Taxonomy - Research

**Phase:** 16  
**Status:** Completed  
**Date:** 2026-09-13  
**Domain:** Exercise Catalog, Database Schema (v41), Discipline Taxonomy, Prerequisite Verification, Progressive Scaling Ladders  

---

## Executive Summary

Phase 16 equips the Herculex catalog, database runtime, and domain eligibility layer with first-class programming metadata: explicit difficulty levels, a 4-tier commonness taxonomy, five canonical discipline tags, technical prerequisite chains with dual-check verification, strict `basicWeights` modality guardrails, and ascending scaling groups for progressive regression.

Currently in schema v40, the catalog contains primitive columns (`programmingDifficulty`, `programmingCommonness`, `allowedTrainingStyles`, `technicalEligibility`) with incomplete coverage and coarse binary commonness (`basic` vs `specialty`). In Phase 16, schema v41 promotes all programming attributes to native, indexed database columns sourced from the authoritative curated asset `assets/data/exercise_programming_metadata.json`. The domain layer is strengthened with `ExerciseProgrammingEligibility` updates and a dedicated `ExerciseScalingResolver` service, guaranteeing that downstream generator phases (Phases 17–22) operate upon immutable, deterministic, explainable exercise candidates without silent relaxation or cross-modality contamination.

---

<user_constraints>
## User Constraints & Locked Decisions

### Locked Decisions (Verbatim from CONTEXT.md)

- **D-01:** Curated JSON asset (`assets/data/exercise_programming_metadata.json`) serves as the authoring source of truth. At import time, `ExerciseImporter` populates first-class columns on Drift `ExerciseCatalog` via schema v41 migration (`programmingDifficulty`, `programmingCommonness`, `disciplines`, `prerequisiteSlugs`, `scalingGroup`, `scalingOrder`, `competitionAnchor`, `specializationTags`).
- **D-02:** Array/list attributes (`disciplines`, `prerequisiteSlugs`, `specializationTags`) are stored as JSON-encoded text columns on `ExerciseCatalog`, maintaining consistency with existing `allowedTrainingStyles` and `requiredEquipmentKeys`.
- **D-03:** Scaling ladders use dedicated columns `scalingGroup` (TEXT, nullable) and `scalingOrder` (INTEGER, nullable) on `ExerciseCatalog` for fast indexed SQL ordering and traversal.
- **D-04:** `programmingCommonness` is expanded to the 4 explicit tiers: `basic`, `common`, `specialty`, and `manualOnly`. Existing uncurated and custom rows default conservatively to `manualOnly`.
- **D-05:** Prerequisite checks follow a dual-check model: a prerequisite is met if either (a) the user's `experienceLevel` equals or exceeds the movement's difficulty, OR (b) the user has verified logged completion of the prerequisite movement in `workout_exercises` history.
- **D-06:** Strict hard gate: If any `prerequisiteSlug` is unverified, the movement is disqualified from automatic candidate pools before scoring. Hard filters are never relaxed.
- **D-07:** Prerequisite pairings focus on foundational compound movements (e.g., muscle-up requires pull-up and dips; clean & jerk requires front squat and overhead press; planche requires push-up and dips).
- **D-08:** Movement-family resolution: Prerequisite satisfaction accepts either the exact exercise slug OR any variant sharing the canonical `movementSlug` (e.g. wide-grip pull-up satisfies pull-up).
- **D-09:** Exact 5 canonical disciplines are defined: `weights`, `calisthenics`, `crossfit`, `olympic`, `gpp`. Exercises can carry multiple discipline tags.
- **D-10:** `basicWeights` training style enforces a two-layer hard filter: modality must be standard gym equipment (`barbell`, `dumbbell`, `cable`, `machine_plate`, `machine_selectorized`, `bodyweight`) AND `programmingCommonness` must be `basic` or `common`, barring specialty bars (SSB, Swiss bar, axle, trap bar, cambered), boards, pins, and chains.
- **D-11:** Strict difficulty ceiling: Novice athletes receive only `novice`-difficulty movements across all slots, with zero silent relaxation for compound or accessory work.
- **D-12:** `competitionAnchor` and `specializationTags` (e.g., `squat-bottom`, `bench-lockout`) are modeled in schema v41 and curated for primary movements in Phase 16 to support downstream Phase 22.
- **D-13:** Ascending difficulty numbering: `scalingOrder = 1` represents the easiest/entry-level regression (e.g. assisted pull-up = 1, negative = 2, strict pull-up = 3, muscle-up = 4); automated regression steps downwards.
- **D-14:** Comprehensive scaling chains are curated for both gymnastics/calisthenics progressions (`vertical_pull`, `horizontal_push`, `dips`, `handstand_pushup`, `pistol_squat`) and foundational weight ladders (`squat`, `hinge`).
- **D-15:** Dedicated `ExerciseScalingResolver` domain service encapsulates scaling ladder traversal, returning the highest safe candidate or null with an explainable rationale.
- **D-16:** Strict group boundary: If no movement on a scaling ladder matches available gym equipment, return null / no safe candidate rather than silently crossing modalities or movement patterns.

### The Agent's Discretion

- Python tooling updates in `tool/build_exercises.py` and `tool/derive_movements.py` to keep json assets in sync.
- Specific default fallback values in Drift table definition for uncurated legacy rows (`manualOnly`, `advanced`, empty lists `[]`).
- Registration of `assets/data/exercise_programming_metadata.json` in `pubspec.yaml` (critical bug fix: currently omitted from `flutter.assets`).

### Deferred Ideas (Out of Scope for Phase 16)

- **Phase 17:** Unified `ProgramGenerationRequest`, deterministic candidate scoring, and selection rationales (`SelectionExplanation`).
- **Phase 18:** `SlotPrescriptionCodec`, `WorkoutDurationEstimator`, and `WarmupResolver`.
- **Phase 21:** Dedicated CrossFit blueprints (warmup, skill, metcon, cooldown) and conditioning engine.
- **Phase 22:** Primary lift strength specialization engine leveraging `competitionAnchor` and `specializationTags`.
- **Phase 24:** XP gamification events and 15 Herculex ranks.

</user_constraints>

---

<phase_requirements>
## Phase Requirements & Codebase Citations

| ID | Requirement Statement | Blueprint / Context Section | Codebase Target Locations |
|:---|:----------------------|:----------------------------|:--------------------------|
| **META-01** | Exercise catalog defines explicit `difficultyLevel` (novice, intermediate, advanced), `commonnessTier` (basic, common, specialty, manualOnly), and `disciplines`. | Blueprint §5 (Faza 1); CONTEXT D-01, D-02, D-04, D-09, D-12 | `lib/data/local/tables.dart`<br>`lib/data/local/database.dart`<br>`assets/data/exercise_programming_metadata.json`<br>`lib/data/local/exercise_importer.dart` |
| **META-02** | Technical movements enforce prerequisite checks (`prerequisiteSlugs`) before entering candidate pools. | Blueprint §3.1, §4.2, §5 (Faza 1); CONTEXT D-05, D-06, D-07, D-08 | `lib/features/programs/domain/exercise_programming_eligibility.dart`<br>`lib/features/programs/data/smart_program_planner.dart`<br>`assets/data/exercise_programming_metadata.json` |
| **META-03** | `basicWeights` training style restricts movements strictly to standard barbell, dumbbell, cable, and machine equipment without specialty bars/variants. | Blueprint §3.2, §4.1, §5 (Faza 1); CONTEXT D-10, D-11 | `lib/features/programs/domain/exercise_programming_eligibility.dart`<br>`lib/features/programs/domain/programming_models.dart`<br>`lib/data/local/exercise_importer.dart` |
| **META-04** | Scaling groups (`scalingGroup`, `scalingOrder`) allow automated progressive regression for advanced movements. | Blueprint §3.1, §5 (Faza 1); CONTEXT D-03, D-13, D-14, D-15, D-16 | `lib/features/programs/domain/exercise_scaling_resolver.dart`<br>`lib/data/local/tables.dart`<br>`assets/data/exercise_programming_metadata.json` |

</phase_requirements>

---

## Detailed Findings by Requirement Area

### 1. Schema Migration v40 -> v41 & Drift Code Generation

#### 1.1 Column Definitions on `ExerciseCatalog` (`lib/data/local/tables.dart`)
In `tables.dart` (lines 120–152), `ExerciseCatalog` requires adjustments:
1. `programmingDifficulty`: remains `text().nullable().withDefault(const Constant('advanced'))()`.
2. `programmingCommonness`: updated default per D-04 from `'specialty'` to `'manualOnly'`:
   `text().nullable().withDefault(const Constant('manualOnly'))()`.
3. New columns:
   - `disciplines`: `TextColumn get disciplines => text().nullable().withDefault(const Constant('[]'))();` (stores JSON list of canonical disciplines: `weights`, `calisthenics`, `crossfit`, `olympic`, `gpp`).
   - `prerequisiteSlugs`: `TextColumn get prerequisiteSlugs => text().nullable().withDefault(const Constant('[]'))();` (stores JSON list of exercise or movement slugs).
   - `scalingGroup`: `TextColumn get scalingGroup => text().nullable()();` (stores text scaling chain identifier, e.g. `vertical_pull`, `horizontal_push`, `dips`, `squat`, `hinge`).
   - `scalingOrder`: `IntColumn get scalingOrder => integer().nullable()();` (stores 1-indexed difficulty rank, 1 = easiest).
   - `competitionAnchor`: `TextColumn get competitionAnchor => text().nullable()();` (stores anchor identity for Phase 22, e.g. `squat`, `bench`, `deadlift`, `overhead_press`).
   - `specializationTags`: `TextColumn get specializationTags => text().nullable().withDefault(const Constant('[]'))();` (stores JSON list of sticking-point / movement tags, e.g. `["squat-bottom", "squat-mid"]`).

#### 1.2 Migration Logic in `AppDatabase` (`lib/data/local/database.dart`)
1. Increment `schemaVersion` from `40` to `41` (line 98).
2. In `onCreate`: Add creation of the scaling index:
   ```dart
   await customStatement(
     'CREATE INDEX IF NOT EXISTS idx_exercise_catalog_scaling '
     'ON exercise_catalog(scaling_group, scaling_order)',
   );
   ```
3. In `onUpgrade`: Add migration step `if (from < 41 && to >= 41)`:
   ```dart
   if (from < 41 && to >= 41) {
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

     await addIfMissing(exerciseCatalog, exerciseCatalog.disciplines);
     await addIfMissing(exerciseCatalog, exerciseCatalog.prerequisiteSlugs);
     await addIfMissing(exerciseCatalog, exerciseCatalog.scalingGroup);
     await addIfMissing(exerciseCatalog, exerciseCatalog.scalingOrder);
     await addIfMissing(exerciseCatalog, exerciseCatalog.competitionAnchor);
     await addIfMissing(exerciseCatalog, exerciseCatalog.specializationTags);

     await customStatement(
       'CREATE INDEX IF NOT EXISTS idx_exercise_catalog_scaling '
       'ON exercise_catalog(scaling_group, scaling_order)',
     );

     // Backfill conservative default for pre-v41 rows that had NULL or legacy 'specialty'
     // while leaving explicitly curated entries intact.
     final catalogueExists = await customSelect(
       "SELECT 1 FROM sqlite_master WHERE type = 'table' "
       "AND name = 'exercise_catalog'",
     ).getSingleOrNull();
     if (catalogueExists != null) {
       await ExerciseImporter.runFromAsset(this);
     }
   }
   ```

#### 1.3 Drift Schema Snapshot & Migration Generation Tooling
Following the established repository pattern in `test/migration_test.dart`:
1. `dart run drift_dev schema dump lib/data/local/database.dart drift_schemas/` -> outputs `drift_schemas/drift_schema_v41.json`.
2. `dart run drift_dev schema generate drift_schemas/ test/generated_migrations/` -> generates `test/generated_migrations/schema_v41.dart` and updates `schema.dart`.
3. `dart run build_runner build --delete-conflicting-outputs` (or `tool\codegen.ps1`) -> updates `lib/data/local/database.g.dart`.
4. Update `test/migration_test.dart` to assert current schema version 41 and add test: `upgrades cleanly from a generated v40 fixture to v41`.

#### 1.4 Supabase Cloud Migration Mirroring
In `supabase/migrations/20260913000000_exercise_programming_metadata_v41.sql`:
Mirror all local v41 changes for remote PostgreSQL schema consistency:
- Add columns: `disciplines` (default `'[]'`), `prerequisite_slugs` (default `'[]'`), `scaling_group` (text), `scaling_order` (integer), `competition_anchor` (text), `specialization_tags` (default `'[]'`).
- Update `programming_commonness` column default to `'manualOnly'`.
- Update check constraint: `check (programming_commonness in ('basic', 'common', 'specialty', 'manualOnly'))`.
- Create index: `create index if not exists idx_exercise_catalog_scaling on public.exercise_catalog(scaling_group, scaling_order);`.
- Update unit test in `test/exercise_programming_metadata_supabase_migration_test.dart` to verify v41 columns and constraints.

---

### 2. Asset Packaging Bug & Authoring Source of Truth

#### 2.1 Critical Asset Packaging Fix in `pubspec.yaml`
Investigation of `pubspec.yaml` (lines 89–100) revealed an urgent packaging defect:
`assets/data/exercise_programming_metadata.json` is **NOT** declared under `flutter.assets:`.
In Flutter release builds, only declared files are packaged in the app bundle. Without this declaration, `rootBundle.loadString(programmingMetadataAssetPath)` in `ExerciseImporter.runFromAsset` throws an exception, triggering the catch block and silently leaving every exercise at conservative table defaults (`manualOnly`, `advanced`).
**Fix:** Add `- assets/data/exercise_programming_metadata.json` to `pubspec.yaml` under `assets:`.

#### 2.2 Authoring Source of Truth (`assets/data/exercise_programming_metadata.json`)
The JSON structure must be enriched to provide authoritative data for all curated exercises:
```json
{
  "version": 2,
  "description": "Hand-curated program-generation metadata with discipline taxonomy, scaling ladders, and prerequisites.",
  "exercises": {
    "barbell-back-squat": {
      "difficulty": "novice",
      "commonness": "basic",
      "allowedTrainingStyles": ["weightlifting", "basic", "powerlifting", "crossfit"],
      "technicalEligibility": "automatic",
      "disciplines": ["weights", "crossfit"],
      "prerequisiteSlugs": [],
      "scalingGroup": "squat",
      "scalingOrder": 3,
      "competitionAnchor": "squat",
      "specializationTags": ["squat-bottom", "squat-mid", "squat-lockout"]
    },
    "ring-muscle-up": {
      "difficulty": "advanced",
      "commonness": "specialty",
      "allowedTrainingStyles": ["calisthenics"],
      "technicalEligibility": "manual_only",
      "disciplines": ["calisthenics"],
      "prerequisiteSlugs": ["pull-up", "chest-dips"],
      "scalingGroup": "vertical_pull",
      "scalingOrder": 7,
      "competitionAnchor": null,
      "specializationTags": []
    }
  }
}
```

---

### 3. Catalog Ingestion & Companion Mapping (`ExerciseImporter`)

In `lib/data/local/exercise_importer.dart`:
1. Expand `_ProgrammingProfile` class:
   ```dart
   class _ProgrammingProfile {
     const _ProgrammingProfile({
       required this.difficulty,
       required this.commonness,
       required this.allowedStyles,
       required this.technicalEligibility,
       required this.disciplines,
       required this.prerequisiteSlugs,
       this.scalingGroup,
       this.scalingOrder,
       this.competitionAnchor,
       required this.specializationTags,
     });

     final String difficulty;
     final String commonness;
     final List<String> allowedStyles;
     final String technicalEligibility;
     final List<String> disciplines;
     final List<String> prerequisiteSlugs;
     final String? scalingGroup;
     final int? scalingOrder;
     final String? competitionAnchor;
     final List<String> specializationTags;
   }
   ```
2. In `_programmingProfile()` parser:
   - Validate `commonness` against `{'basic', 'common', 'specialty', 'manualOnly'}`. Default to `'manualOnly'`.
   - Validate `disciplines` against canonical 5: `{'weights', 'calisthenics', 'crossfit', 'olympic', 'gpp'}`. Unknown tags are filtered out. Default to empty list `[]`.
   - Parse `prerequisiteSlugs` (List<String>), `specializationTags` (List<String>).
   - Parse `scalingGroup` (trimmed non-empty String or null), `scalingOrder` (int or null), `competitionAnchor` (String or null).
3. In `_upsert()`:
   - Populate `ExerciseCatalogCompanion` with:
     ```dart
     disciplines: Value(jsonEncode(programming.disciplines)),
     prerequisiteSlugs: Value(jsonEncode(programming.prerequisiteSlugs)),
     scalingGroup: Value(programming.scalingGroup),
     scalingOrder: Value(programming.scalingOrder),
     competitionAnchor: Value(programming.competitionAnchor),
     specializationTags: Value(jsonEncode(programming.specializationTags)),
     ```

---

### 4. Discipline Taxonomy & Commonness Tiers (META-01 & D-04, D-09, D-10, D-11)

#### 4.1 Canonical Disciplines (D-09)
Exactly 5 disciplines:
1. `weights`: Traditional resistance training (barbell, dumbbell, machine, cable).
2. `calisthenics`: Bodyweight leverage, gymnastics rings, bars, parallettes.
3. `crossfit`: Functional high-intensity, mixed modal, Olympic lifts, metcons.
4. `olympic`: Snatch, clean & jerk, overhead squat, variations.
5. `gpp`: General physical preparedness, cardio ergs (bike, rower, ski), carries, sleds.
Exercises may hold multiple tags (e.g., `power-clean` carries `['olympic', 'crossfit', 'weights']`).

#### 4.2 4-Tier Commonness Model (D-04)
1. `basic`: Universally standard, conventional lifts found in nearly any gym (e.g., Barbell Back Squat, Dumbbell Bench Press, Lat Pulldown, Standard Push-Up).
2. `common`: Standard accessory or popular compound variations (e.g., Incline Dumbbell Curl, Romanian Deadlift, Tricep Rope Pushdown, Bulgarian Split Squat).
3. `specialty`: Technical, powerlifting-specific, or specialized apparatus movements (e.g., Spoto Press, Board Press, Pin Squat, SSB Squat, Swiss Bar Row).
4. `manualOnly`: Advanced, dangerous, uncurated, or custom exercises that must never be auto-programmed (e.g., Hefesto, Steinborn Squat, uncurated legacy rows). Default for all uncurated rows.

#### 4.3 Strict Difficulty Ceiling for Novices (D-11)
Novice athletes (`ExperienceLevel.novice`) MUST receive only `novice`-difficulty movements across ALL slots (compounds, secondaries, and accessories).
In `ExerciseProgrammingEligibility.allows`:
`_difficultyRank(resolvedDifficulty) <= _experienceRank(experience)`.
For Novice (rank 0), any movement with `intermediate` (rank 1) or `advanced` (rank 2) is strictly rejected. There is ZERO relaxation.

#### 4.4 Basic Weights Profile Hard Gate (META-03 & D-10)
When `style == TrainingStyle.basic` (or profile `basicWeights`):
1. **Layer 1: Modality Hard Filter:**
   Modality must belong strictly to:
   `{'barbell', 'dumbbell', 'cable', 'machine_plate', 'machine_selectorized', 'bodyweight'}`.
   Equipment must NOT require specialty bars (`safety_squat_bar`, `swiss_bar`, `cambered_bar`, `axle_bar`, `trap_bar`, `duffalo_bar`), boards, pins, or chains.
2. **Layer 2: Commonness Hard Filter:**
   `programmingCommonness` must be `'basic'` or `'common'`. Movements tagged `'specialty'` or `'manualOnly'` are disqualified immediately.

---

### 5. Prerequisite Verification Model (META-02 & D-05, D-06, D-07, D-08)

#### 5.1 Dual-Check Verification Architecture (D-05)
A candidate movement's `prerequisiteSlugs` are evaluated against a dual-check model:
A prerequisite is satisfied if **EITHER**:
- **Condition (a) Experience Check:** The user's `experienceLevel` equals or exceeds the prerequisite movement's `programmingDifficulty`.
  *Example:* An `advanced` athlete has experience rank 2. If a movement requires `pull-up` (difficulty: `intermediate`, rank 1), Condition (a) is met because `2 >= 1`.
  *Counter-example:* A `novice` athlete has experience rank 0. For `pull-up` (rank 1), `0 >= 1` is FALSE.
- **Condition (b) Verified History Check:** The user has logged verified completion of the prerequisite movement in `workout_exercises` history (session completed with logged sets).
  *Example:* Even if a user's profile is set to `novice`, if they have verified logs of `pull-up` in `workout_exercises`, Condition (b) is satisfied!

#### 5.2 Movement-Family Resolution (D-08)
When checking Condition (b) in workout history:
Prerequisite satisfaction accepts **EITHER**:
- The exact exercise slug (e.g. `pull-up`), **OR**
- Any variant sharing the same canonical `movementSlug` (e.g. `pull-up-wide-grip` or `pull-up-neutral-grip` share `movementSlug: "pull-up-vertical-pull"`).
This prevents false disqualification when a lifter performs a legitimate variation of the required foundational pattern.

#### 5.3 Strict Hard Gate Disqualification (D-06)
If any prerequisite slug in `prerequisiteSlugs` fails both Condition (a) and Condition (b):
The candidate movement is **DISQUALIFIED** immediately before candidate scoring. Hard filters are never relaxed.

#### 5.4 Curated Foundational Prerequisite Pairings (D-07)
- `ring-muscle-up` & `bar-muscle-up` -> `["pull-up", "chest-dips"]`
- `clean-and-jerk` -> `["front-squat", "overhead-press"]`
- `power-clean` -> `["conventional-deadlift", "front-squat"]`
- `power-snatch` & `squat-snatch` -> `["overhead-press", "conventional-deadlift"]`
- `full-planche` -> `["standard-push-up", "chest-dips"]`
- `pseudo-planche-push-up` -> `["standard-push-up"]`
- `handstand-push-up` -> `["pike-push-up"]`
- `pistol-squat` -> `["trx-assisted-pistol-squat"]` (or `bulgarian-split-squat`)
- `hefesto` -> `["pull-up", "chest-dips"]`

---

### 6. Scaling Groups & Automated Progressive Regression (META-04 & D-03, D-13, D-14, D-15, D-16)

#### 6.1 Ascending Difficulty Ordering (D-13)
Scaling ladders use 1-indexed ascending numbers where `scalingOrder = 1` represents the easiest / entry-level regression.
Regression steps downwards: `4 -> 3 -> 2 -> 1`.
Progression steps upwards: `1 -> 2 -> 3 -> 4`.

#### 6.2 Curated Scaling Chains (D-14)
1. **Vertical Pull (`vertical_pull`):**
   - 1: `assisted-pull-up-machine-wide-grip` (novice, basic, weights/calisthenics)
   - 2: `band-assisted-pull-up-wide-grip` (novice, basic, calisthenics)
   - 3: `negative-pull-up` (novice, basic, calisthenics)
   - 4: `pull-up` (intermediate, basic, calisthenics)
   - 5: `chest-to-bar-pull-up` (intermediate, common, calisthenics/crossfit)
   - 6: `bar-muscle-up` (advanced, specialty, calisthenics/crossfit)
   - 7: `ring-muscle-up` (advanced, specialty, calisthenics)

2. **Horizontal Push (`horizontal_push`):**
   - 1: `incline-push-up` (novice, basic, calisthenics)
   - 2: `standard-push-up` (novice, basic, calisthenics)
   - 3: `decline-push-up` (intermediate, common, calisthenics)
   - 4: `diamond-push-up` (intermediate, common, calisthenics)
   - 5: `pseudo-planche-push-up` (advanced, specialty, calisthenics)
   - 6: `full-planche` (advanced, specialty, calisthenics)

3. **Dips (`dips`):**
   - 1: `bench-dip` (novice, basic, calisthenics)
   - 2: `band-assisted-dip` (novice, basic, calisthenics)
   - 3: `chest-dips` (intermediate, basic, calisthenics)
   - 4: `ring-dips` (advanced, specialty, calisthenics)

4. **Handstand Push-Up (`handstand_pushup`):**
   - 1: `pike-push-up` (intermediate, common, calisthenics)
   - 2: `handstand-push-up` (advanced, specialty, calisthenics)

5. **Pistol Squat (`pistol_squat`):**
   - 1: `trx-assisted-pistol-squat` (intermediate, common, calisthenics)
   - 2: `pistol-squat` (advanced, specialty, calisthenics)

6. **Foundational Squat Ladder (`squat`):**
   - 1: `dumbbell-squat` / `dumbbell-front-squat` (novice, basic, weights)
   - 2: `front-squat` (intermediate, basic, weights)
   - 3: `barbell-back-squat` (novice/intermediate, basic, weights)

7. **Foundational Hinge Ladder (`hinge`):**
   - 1: `dumbbell-romanian-deadlift` (novice, basic, weights)
   - 2: `romanian-deadlift` (intermediate, basic, weights)
   - 3: `conventional-deadlift` (intermediate, basic, weights)

#### 6.3 Domain Service: `ExerciseScalingResolver` (D-15, D-16)
Lives in `lib/features/programs/domain/exercise_scaling_resolver.dart`.
Contract:
```dart
class ScalingResolutionResult {
  const ScalingResolutionResult.success({
    required this.candidate,
    required this.rationale,
  }) : isSuccess = true;

  const ScalingResolutionResult.noSafeCandidate({
    required this.rationale,
  }) : candidate = null, isSuccess = false;

  final ExerciseCatalogData? candidate;
  final bool isSuccess;
  final String rationale;
}

class ExerciseScalingResolver {
  const ExerciseScalingResolver();

  /// Traverses down [target]'s scaling ladder to find the highest difficulty
  /// candidate that satisfies all hard guardrails (experience ceiling,
  /// equipment availability, training style, and prerequisites).
  ScalingResolutionResult regress({
    required ExerciseCatalogData target,
    required List<ExerciseCatalogData> groupCandidates,
    required ExperienceLevel experience,
    required TrainingStyle style,
    required Set<String> availableEquipmentKeys,
    required Set<String> completedExerciseSlugs,
    required Set<String> completedMovementSlugs,
    required Map<String, ExerciseCatalogData> catalogBySlug,
  }) {
    if (target.scalingGroup == null || target.scalingOrder == null) {
      return ScalingResolutionResult.noSafeCandidate(
        rationale: '${target.name} does not belong to a scaling ladder.',
      );
    }

    // Filter ladder candidates with strictly lower scalingOrder, sorted descending
    final regressions = groupCandidates
        .where((e) =>
            e.scalingGroup == target.scalingGroup &&
            e.scalingOrder != null &&
            e.scalingOrder! < target.scalingOrder!)
        .toList()
      ..sort((a, b) => b.scalingOrder!.compareTo(a.scalingOrder!));

    for (final candidate in regressions) {
      // 1. Difficulty ceiling
      if (_difficultyRank(candidate.programmingDifficulty) > _experienceRank(experience)) {
        continue;
      }
      // 2. Technical eligibility
      if (candidate.technicalEligibility == 'manual_only') continue;
      if (candidate.technicalEligibility == 'technical_review' && experience == ExperienceLevel.novice) {
        continue;
      }
      // 3. Style & commonness
      if (!ExerciseProgrammingEligibility.allows(
        experience: experience,
        style: style,
        difficulty: candidate.programmingDifficulty,
        commonness: candidate.programmingCommonness,
        allowedTrainingStylesJson: candidate.allowedTrainingStyles,
        technicalEligibility: candidate.technicalEligibility,
      )) {
        continue;
      }
      // 4. Equipment check
      if (!_hasRequiredEquipment(candidate, availableEquipmentKeys)) {
        continue;
      }
      // 5. Prerequisites check
      if (!ExerciseProgrammingEligibility.verifyPrerequisites(
        prerequisiteSlugsJson: candidate.prerequisiteSlugs,
        userExperience: experience,
        completedExerciseSlugs: completedExerciseSlugs,
        completedMovementSlugs: completedMovementSlugs,
        catalogBySlug: catalogBySlug,
      )) {
        continue;
      }

      return ScalingResolutionResult.success(
        candidate: candidate,
        rationale: 'Regressed from ${target.name} (order ${target.scalingOrder}) '
            'to ${candidate.name} (order ${candidate.scalingOrder}) based on safety gates.',
      );
    }

    // Strict boundary enforcement (D-16): Never silently jump modalities or groups
    return ScalingResolutionResult.noSafeCandidate(
      rationale: 'No safe candidate found in scaling ladder "${target.scalingGroup}" '
          'matching available equipment and experience level.',
    );
  }
}
```

---

### 7. Specialization Anchors & Tags (D-12)

To establish the architectural foundation for Phase 22 (Primary Lift Strength Specialization):
- Primary competition lifts declare `competitionAnchor`:
  - Squat family: `"squat"`
  - Bench Press family: `"bench"`
  - Deadlift family: `"deadlift"`
  - Overhead Press family: `"overhead_press"`
- Specialized variations declare `specializationTags` identifying weak points:
  - Bottom / off-the-chest / out-of-the-hole: `["squat-bottom"]`, `["bench-bottom"]`, `["deadlift-floor"]`, `["ohp-bottom"]` (e.g. Paused Squat, Deficit Deadlift, Spoto Press)
  - Mid-range / transition: `["squat-mid"]`, `["bench-mid"]`, `["deadlift-mid"]` (e.g. Pin Squat, Board Press)
  - Lockout / triceps / glutes: `["squat-lockout"]`, `["bench-lockout"]`, `["deadlift-lockout"]`, `["ohp-lockout"]` (e.g. Close Grip Bench Press, Rack Pull, Block Pull)
In Phase 16, schema v41 models and populates these columns in Drift and Supabase, enabling Phase 22 to query them directly without further schema migrations.

---

## Common Pitfalls & Edge Cases

| Area | Potential Pitfall | Prevention / Mitigation Strategy |
|:-----|:------------------|:---------------------------------|
| **Asset Loading** | `assets/data/exercise_programming_metadata.json` not bundled into release APK/bundle. | Declare `- assets/data/exercise_programming_metadata.json` under `flutter.assets:` in `pubspec.yaml`. Verify in test using `rootBundle`. |
| **Schema Migration** | `programmingCommonness` default value mismatch between Drift schema, Dart companion, and tests. | Update `tables.dart` default to `'manualOnly'`, update companion fallback, update Supabase column default, and update tests expecting `'manualOnly'`. |
| **Prerequisite Resolution** | Prerequisite slug mismatch (e.g., exercise slug `pull-up` vs `pull-up-wide-grip` vs movement slug `pull-up-vertical-pull`). | Implement D-08 movement-family lookup: compare both the exact exercise slug and the associated `movementSlug`. |
| **Scaling Boundaries** | Equipment exhaustion on a calisthenics ladder causing silent fallback to a barbell movement. | Strict group boundary (D-16): `ExerciseScalingResolver` stays strictly within the matching `scalingGroup`. If equipment is unavailable, returns `noSafeCandidate` with explainable rationale. |
| **Novice Floor Escalation** | Novice athlete receiving an intermediate movement because no novice movement was available in a slot. | Strict difficulty ceiling (D-11): Never relax `programmingDifficulty` for novices. If no novice movement exists, slot must report no safe candidate. |
| **Specialty Bar Leakage** | Specialty bar variants (e.g., Swiss bar curl, SSB lunge) appearing in `basicWeights`. | Enforce D-10 two-layer check: modality whitelist AND commonness tier (`basic` or `common`) AND specialty key exclusion (`safety_squat_bar`, `swiss_bar`, etc.). |
| **Drift Code Generation** | Running migration tests without updating `drift_schemas/` snapshot and `test/generated_migrations/`. | Always execute `dart run drift_dev schema dump`, then `dart run drift_dev schema generate`, then `tool\codegen.ps1`. |

---

## Validation Architecture

### 1. Test Framework & Execution Strategy
- **Framework:** `flutter_test` with in-memory SQLite (`openTestDatabase()` from `test/support/test_database.dart`) and Drift native migration testing (`SchemaVerifier` from `package:drift_dev/api/migrations_native.dart`).
- **Code Generation:** `dart run drift_dev schema dump`, `dart run drift_dev schema generate`, and `dart run build_runner build`.

### 2. Test Suites & Verification Plan

1. **Schema v41 Migration & Tooling Suite (`test/migration_test.dart`)**
   - Assert current schema version is `41`.
   - Validate clean upgrade from generated v40 fixture to v41.
   - Replay legacy fixtures from v23, v24, v39, v40 up to v41.
   - Command: `flutter test test/migration_test.dart`

2. **Supabase Cloud Schema Synchronization Suite (`test/exercise_programming_metadata_supabase_migration_test.dart`)**
   - Verify `supabase/migrations/20260913000000_exercise_programming_metadata_v41.sql` contains all columns: `disciplines`, `prerequisite_slugs`, `scaling_group`, `scaling_order`, `competition_anchor`, `specialization_tags`.
   - Verify check constraint on `programming_commonness` includes `'basic'`, `'common'`, `'specialty'`, `'manualOnly'`.
   - Command: `flutter test test/exercise_programming_metadata_supabase_migration_test.dart`

3. **Catalog Metadata Ingestion & Default Fallback Suite (`test/exercise_programming_metadata_test.dart`)**
   - Verify ingestion of curated exercises with disciplines, prerequisites, scaling groups, and specialization tags.
   - Verify uncurated rows default conservatively to `manualOnly`, `advanced`, and empty lists.
   - Verify unknown disciplines or commonness values are safely rejected or defaulted.
   - Command: `flutter test test/exercise_programming_metadata_test.dart`

4. **Domain Hard Gating & Basic Weights Suite (`test/exercise_programming_eligibility_test.dart`)**
   - Verify strict novice difficulty ceiling across all movement patterns.
   - Verify `basicWeights` hard gate: blocks specialty bars (SSB, Swiss bar, cambered, trap bar), boards, pins, chains.
   - Verify dual-check prerequisite verification: (a) experience meets prerequisite difficulty, and (b) logged history satisfies prerequisite with movement-family alias resolution.
   - Command: `flutter test test/exercise_programming_eligibility_test.dart`

5. **Exercise Scaling Resolver Suite (`test/exercise_scaling_resolver_test.dart`)**
   - Verify descending ladder traversal from ascending `scalingOrder` (e.g., ring muscle-up -> bar muscle-up -> pull-up -> negative -> assisted).
   - Verify strict group boundary (D-16): returns `noSafeCandidate` on equipment exhaustion without crossing modalities.
   - Verify explainable rationale output on success and failure.
   - Command: `flutter test test/exercise_scaling_resolver_test.dart`

6. **End-to-End Program Planner Regression Suite (`test/smart_program_planner_test.dart`)**
   - Verify existing generator plans (Upper/Lower, Full Body, Conjugate, Concurrent) continue to pass without regression.
   - Command: `flutter test test/smart_program_planner_test.dart`

---

## Plan Decomposition Recommendation

To ensure clean, incremental, and verified execution, Phase 16 should be structured into **3 focused plans**:

1. **Plan 16-01: Schema v41 Migration, Drift Codegen & Asset Packaging (META-01)**
   - Add new columns to `ExerciseCatalog` in `tables.dart`.
   - Update `schemaVersion` to 41, add `onUpgrade` block and scaling index in `database.dart`.
   - Add `assets/data/exercise_programming_metadata.json` to `pubspec.yaml`.
   - Create Supabase migration `20260913000000_exercise_programming_metadata_v41.sql`.
   - Run drift dump, drift generate, and build_runner codegen.
   - Update and verify `test/migration_test.dart` and `test/exercise_programming_metadata_supabase_migration_test.dart`.

2. **Plan 16-02: Curated Asset Ingestion, Companion Mapping & Disciplines (META-01, META-03)**
   - Curate `assets/data/exercise_programming_metadata.json` with disciplines (5 canonical), 4-tier commonness, prerequisites, scaling chains, and specialization anchors.
   - Update `ExerciseImporter` companion mapping and profile validation.
   - Update `ExerciseProgrammingEligibility` with 4-tier commonness, novice ceiling, and `basicWeights` two-layer hard filter.
   - Update and verify `test/exercise_programming_metadata_test.dart` and `test/exercise_programming_eligibility_test.dart`.

3. **Plan 16-03: Prerequisite Verification & Progressive Scaling Resolver (META-02, META-04)**
   - Implement prerequisite dual-check logic in `ExerciseProgrammingEligibility` with movement-family resolution (`movementSlug`).
   - Implement `ExerciseScalingResolver` domain service with ascending ladder regression, strict group boundaries, and explainable rationales.
   - Create comprehensive unit test suite `test/exercise_scaling_resolver_test.dart`.
   - Run full regression suite across planner and catalog tests to verify zero regressions.

---

## RESEARCH COMPLETE
