import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// Sync identity columns shared by every table that participates in Phase 10
/// cloud sync. `syncUuid` is the row's identity in Postgres (client-generated
/// so offline inserts already have an id); `updatedAt` is a purely local
/// "last touched" timestamp, unrelated to conflict resolution — the server's
/// own `updated_at` is the LWW clock. `syncedAt` is null until the row has
/// been successfully pushed at least once.
///
/// `Foods`/`Recipes` already declare their own `deletedAt` (v24 RB-05
/// tombstone) and must not mix in [SyncTombstone] a second time; every other
/// synced table mixes in both.
mixin SyncColumns on Table {
  TextColumn get syncUuid =>
      text().nullable().clientDefault(() => const Uuid().v4())();
  DateTimeColumn get updatedAt =>
      dateTime().nullable().clientDefault(() => DateTime.now())();
  DateTimeColumn get syncedAt => dateTime().nullable()();
}

mixin SyncTombstone on Table {
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

/// Canonical exercise library. Most rows are seeded; user-created rows have
/// [isCustom] = true.
@DataClassName('ExerciseCatalogData')
class ExerciseCatalog extends Table with SyncColumns, SyncTombstone {
  IntColumn get id => integer().autoIncrement()();

  /// Stable identity (v17), kebab-case, unique across seeded rows.
  ///
  /// [name] is display text and will change as the catalog is corrected; the
  /// importer matches on this instead so a rename updates the row in place
  /// rather than inserting a duplicate and orphaning every logged set that
  /// referenced the old row. Null on custom and pre-v17 rows.
  TextColumn get slug => text().nullable()();

  TextColumn get name => text()();
  // Legacy coarse muscle group (Chest|Back|Shoulders|Quads|…). Kept for
  // back-compat; granular involvement lives in [ExerciseMuscles].
  TextColumn get primaryMuscle => text()();
  TextColumn get equipment => text()();
  // compound | isolation
  TextColumn get mechanics => text()();
  // push | pull | static
  TextColumn get force => text()();
  // horizontal | vertical | axial | none
  TextColumn get plane => text()();
  IntColumn get defaultRestSeconds =>
      integer().withDefault(const Constant(120))();
  BoolColumn get isCustom => boolean().withDefault(const Constant(false))();

  // ── Exercise Intelligence (v8) ──
  /// Denormalized alias blob for quick search; canonical aliases live in
  /// [ExerciseAliases]. Display always uses [name].
  TextColumn get aka => text().nullable()();
  // strength | hypertrophy | powerlifting | calisthenics | crossfit | cardio | mobility
  TextColumn get category => text().withDefault(const Constant('strength'))();
  // Coarse: squat | hinge | horizontal_push | vertical_push | horizontal_pull |
  // vertical_pull | lunge | carry | core | isolation | other
  TextColumn get movementPattern => text().nullable()();

  /// Original granular pattern text from the source dataset (fidelity).
  TextColumn get movementPatternRaw => text().nullable()();
  // barbell | dumbbell | machine_plate | machine_selectorized | cable | smith |
  // kettlebell | band | bodyweight | other
  TextColumn get modality => text().withDefault(const Constant('barbell'))();

  /// CNS fatigue cost, 1–10. Drives recovery + max-effort logic.
  IntColumn get cnsScore => integer().withDefault(const Constant(3))();

  /// Systemic recovery demand, 1–5.
  IntColumn get recoveryImpact => integer().withDefault(const Constant(3))();
  // weight_reps | reps | time | distance | time_distance | weight_time
  TextColumn get loggingMetric =>
      text().withDefault(const Constant('weight_reps'))();

  /// Enables the "+ added weight" field & bodyweight-base calculations.
  BoolColumn get supportsWeightedBodyweight =>
      boolean().withDefault(const Constant(false))();

  /// JSON list of attachment labels, e.g. ["rope","v-bar"]. Null = none.
  TextColumn get attachments => text().nullable()();

  /// False = attributes were machine-derived and not yet human-reviewed.
  BoolColumn get isReviewed => boolean().withDefault(const Constant(false))();

  /// Movement-family key grouping equipment variants of the same movement
  /// (e.g. "Incline Barbell Bench" + "Incline Dumbbell Press" share one
  /// family). Drives the collapsed picker. Computed at import time; null on
  /// legacy/custom rows until backfilled.
  TextColumn get movementFamily => text().nullable()();

  // ── Movement layer (v18) ──
  /// Authored movement this exercise belongs to (`assets/data/movements.json`),
  /// e.g. every equipment variant of a curl shares `curl-isolation`. Supersedes
  /// the derived [movementFamily] for picker grouping; null means the exercise
  /// stands alone.
  TextColumn get movementSlug => text().nullable()();

  /// JSON array of modalities this exercise can plausibly be performed with,
  /// taken from its movement. Null means no swap is offered.
  ///
  /// Replaces the previous hardcoded free-weight family, which offered a Smith
  /// Machine option on a selectorized hamstring curl.
  TextColumn get allowedEquipment => text().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {name, equipment},
  ];
}

/// Normalized muscle involvement — the recovery engine's primary input.
@DataClassName('ExerciseMuscleData')
class ExerciseMuscles extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get exerciseId =>
      integer().references(ExerciseCatalog, #id, onDelete: KeyAction.cascade)();
  TextColumn get muscle => text()();
  // primary | secondary | stabilizer
  TextColumn get role => text()();
  RealColumn get contribution => real().withDefault(const Constant(1.0))();

  @override
  List<Set<Column>> get uniqueKeys => [
    {exerciseId, muscle, role},
  ];
}

/// Search aliases. Searching any alias returns the parent exercise; the parent's
/// [ExerciseCatalog.name] remains the only displayed name.
@DataClassName('ExerciseAliasData')
class ExerciseAliases extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get exerciseId =>
      integer().references(ExerciseCatalog, #id, onDelete: KeyAction.cascade)();
  TextColumn get alias => text()();
}

@DataClassName('WorkoutSessionData')
class WorkoutSessions extends Table with SyncColumns, SyncTombstone {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().nullable()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  TextColumn get notes => text().nullable()();
  // Overall session RPE 1-10 (optional)
  IntColumn get sessionRpe => integer().nullable()();

  /// Gym the session was performed at (v10). Null = no gym / single-gym user.
  IntColumn get gymId =>
      integer().nullable().references(Gyms, #id, onDelete: KeyAction.setNull)();

  /// Set when this session is an auto-created micro-workout completion (v11,
  /// §20) — lets the micro-workout checklist count today's completions while
  /// the sets still flow through every engine as normal training.
  IntColumn get microWorkoutId => integer().nullable().references(
    MicroWorkouts,
    #id,
    onDelete: KeyAction.setNull,
  )();

  /// Stable session identity for the phone<->watch sync wire protocol (v22,
  /// Phase 1 of wear-sync remediation). Generated once when the session
  /// starts and reused as `entityId` on every message about it, including
  /// its end — unlike the local autoincrement [id], which was never sent on
  /// session end and offered nothing for the watch side to compare against.
  TextColumn get sessionUuid => text().nullable()();

  /// Gym Buddy live-session identity (v29). Nullable and null for every solo
  /// workout; set for the duration of a buddy session so BUD-07 can compute
  /// a VS comparison later. This is a synced column on an otherwise-synced
  /// table, unlike the two buddy mirror tables below.
  TextColumn get buddySessionId => text().nullable()();
}

@DataClassName('WorkoutExerciseData')
class WorkoutExercises extends Table with SyncColumns, SyncTombstone {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sessionId =>
      integer().references(WorkoutSessions, #id, onDelete: KeyAction.cascade)();
  IntColumn get exerciseId => integer().references(
    ExerciseCatalog,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get orderIndex => integer()();
  // Same group number across rows ⇒ superset. Null = standalone.
  IntColumn get supersetGroup => integer().nullable()();
  IntColumn get targetRestSeconds => integer().nullable()();

  // ── Logging variants (v10) ──
  /// Equipment the exercise was actually performed with (barbell | dumbbell |
  /// smith | cable | machine_plate | machine_selectorized | bodyweight | …).
  /// Null ⇒ the catalog row's default [ExerciseCatalog.modality].
  TextColumn get equipmentVariant => text().nullable()();

  /// Machine settings snapshot for this log, JSON object
  /// (e.g. {"seat":"6","angle":"45°"}). Null for non-machine work.
  TextColumn get machineConfigJson => text().nullable()();
}

@DataClassName('SetEntryData')
class SetEntries extends Table with SyncColumns, SyncTombstone {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get workoutExerciseId => integer().references(
    WorkoutExercises,
    #id,
    onDelete: KeyAction.cascade,
  )();
  IntColumn get setIndex => integer()();
  RealColumn get weightKg => real()();
  IntColumn get reps => integer()();
  // RPE 1-10 (half-points allowed → stored × 10 to keep int math simple)
  IntColumn get rpeX10 => integer().nullable()();
  BoolColumn get isWarmup => boolean().withDefault(const Constant(false))();
  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get completedAt => dateTime().nullable()();

  // ── Advanced set types & effective load inputs (v10) ──
  /// Set type id from the [SetType] domain registry (standard | drop |
  /// rest_pause | partials | myo_reps | pause | down_sets | …).
  TextColumn get setType => text().withDefault(const Constant('standard'))();

  /// Type-specific metadata, JSON object (dropPercent, pauseSeconds,
  /// miniSets, startReps, decrement, …). Null for plain sets.
  TextColumn get setTypeMetaJson => text().nullable()();

  /// User bodyweight snapshot at logging time. Set for weighted-bodyweight
  /// exercises so total load = weightKg + bodyweightKg.
  RealColumn get bodyweightKg => real().nullable()();

  /// Average chain contribution over the ROM, already halved (kg at lockout/2).
  RealColumn get chainsKg => real().nullable()();

  // ── Non-rep logging metrics (v31, EXR-05) ──
  //
  // Three nullable columns, one per [SetField] that is not weight or reps.
  // Which of them a given set fills is decided by its exercise's
  // `loggingMetric` (see `features/workouts/domain/logging_metric.dart`) —
  // a Plank fills `durationSeconds`, a Sled Push fills `weightKg` and
  // `distanceM`, a bike sprint fills `durationSeconds` and `calories`.
  //
  // Nullable rather than defaulted to zero on purpose: null means "this metric
  // does not apply to this movement", while 0 would mean "logged, and it was
  // zero". Analytics has to tell those apart — a duration-only set with
  // `weightKg = 0` must contribute no tonnage, not zero-weight tonnage, and a
  // sled push must not be counted as `reps` work it never had.
  //
  // [reps] and [weightKg] stay NOT NULL because every existing row has them
  // and because widening them would silently break every query that assumes
  // otherwise; a non-rep set writes 0 into them and is excluded from
  // rep/tonnage aggregation by its metric, not by its stored numbers.

  /// Work duration in seconds — a hold, a carry, or a cardio interval.
  IntColumn get durationSeconds => integer().nullable()();

  /// Distance covered, in metres. Metres rather than the user's display unit:
  /// the same rule the rest of the schema follows for kilograms.
  RealColumn get distanceM => real().nullable()();

  /// Calories as reported by an erg or bike console. Not an estimate the app
  /// computes — it is a number the machine displayed and the user copied.
  IntColumn get calories => integer().nullable()();
}

// ── Nutrition ──────────────────────────────────────────────────────────────

/// All nutrient values are per-100g (or per-100ml for liquids); convert via
/// [servingGrams] when displaying a serving-sized macro.
@DataClassName('FoodData')
class Foods extends Table with SyncColumns {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get brand => text().nullable()();
  TextColumn get barcode => text().nullable()();
  RealColumn get kcalPer100g => real()();
  RealColumn get proteinPer100g => real().withDefault(const Constant(0))();
  RealColumn get carbsPer100g => real().withDefault(const Constant(0))();
  RealColumn get fatPer100g => real().withDefault(const Constant(0))();
  RealColumn get fiberPer100g => real().nullable()();
  RealColumn get servingGrams => real().nullable()();
  TextColumn get servingLabel => text().nullable()(); // e.g. "1 cup", "1 slice"
  TextColumn get source =>
      text().withDefault(const Constant('local'))(); // local | openfoodfacts
  TextColumn get imageUrl => text().nullable()();
  BoolColumn get isCustom => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  // ── Expanded nutrition (v12, §19) ──
  RealColumn get sodiumMgPer100g => real().nullable()();
  RealColumn get potassiumMgPer100g => real().nullable()();
  RealColumn get cholesterolMgPer100g => real().nullable()();

  /// Stable ID from the bundled catalogue; null for user-created/legacy foods.
  TextColumn get catalogueId => text().nullable()();

  /// 100 g, 100 ml, or a source-labelled serving basis.
  TextColumn get referenceBasis =>
      text().withDefault(const Constant('100 g'))();
  RealColumn get servingAmount => real().nullable()();
  TextColumn get servingUnit => text().nullable()();
  TextColumn get category => text().nullable()();
  TextColumn get country => text().nullable()();

  /// Full source nutrients/provenance/claims payload for later micro views.
  TextColumn get sourceMetadataJson => text().nullable()();

  /// RB-05 soft delete. Non-null hides the row from every catalogue-facing
  /// query while `food_entries` / `recipe_ingredients` keep referencing it,
  /// so both RESTRICT edges stay satisfiable and history keeps its name and
  /// brand context. Nullable DateTime rather than a bool: it records *when*,
  /// and the "hidden" predicate stays a single `IS NULL`.
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

/// Free-form micronutrients per food (vitamins, minerals), per-100g (§19).
@DataClassName('FoodMicroData')
class FoodMicros extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get foodId =>
      integer().references(Foods, #id, onDelete: KeyAction.cascade)();
  TextColumn get nutrient => text()(); // e.g. "Vitamin C", "Iron"
  RealColumn get amountPer100g => real()();
  TextColumn get unit => text()(); // mg | µg | IU

  @override
  List<Set<Column>> get uniqueKeys => [
    {foodId, nutrient},
  ];
}

/// Import marker for the bundled food catalogue. A marker makes the large
/// asset a one-time migration instead of a per-launch parse/import.
@DataClassName('FoodCatalogueMetaData')
class FoodCatalogueMeta extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  TextColumn get schemaVersion => text()();
  IntColumn get foodCount => integer()();
  DateTimeColumn get importedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Calorie + macro target, scoped by [appliesTo] (§19). One global row plus
/// optional training-day / rest-day / weekday / specific-date overrides.
@DataClassName('NutritionTargetData')
class NutritionTargets extends Table with SyncColumns, SyncTombstone {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get label => text()();
  IntColumn get kcal => integer()();
  IntColumn get proteinG => integer()();
  IntColumn get carbsG => integer()();
  IntColumn get fatG => integer()();
  IntColumn get fiberG => integer().nullable()();
  // global | training_day | rest_day | weekday:<1-7> | date:<yyyy-mm-dd>
  TextColumn get appliesTo => text().withDefault(const Constant('global'))();

  @override
  List<Set<Column>> get uniqueKeys => [
    {appliesTo},
  ];
}

/// Automated dieting schedule (§19): reduce calories by [reducePct] every
/// [intervalDays], starting [startDateIso]. The active schedule scales the
/// resolved daily target down over time.
@DataClassName('DietScheduleData')
class DietSchedules extends Table with SyncColumns, SyncTombstone {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get startDateIso => text()();
  RealColumn get reducePct => real()();
  IntColumn get intervalDays => integer()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
}

/// A generated weekly carb-cycle plan (§19): 7 day levels (high|med|low)
/// keyed off the week's Monday.
@DataClassName('CarbCyclePlanData')
class CarbCyclePlans extends Table with SyncColumns, SyncTombstone {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get weekStartIso => text()();

  /// JSON array of 7 strings, Mon→Sun: ["high","low","med",…].
  TextColumn get dayLevelsJson => text()();
  BoolColumn get auto => boolean().withDefault(const Constant(true))();

  @override
  List<Set<Column>> get uniqueKeys => [
    {weekStartIso},
  ];
}

@DataClassName('RecipeData')
class Recipes extends Table with SyncColumns {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  IntColumn get servings => integer().withDefault(const Constant(1))();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// RB-05 soft delete. Non-null hides the row from every catalogue-facing
  /// query while `food_entries` / `recipe_ingredients` keep referencing it,
  /// so both RESTRICT edges stay satisfiable and history keeps its name and
  /// brand context. Nullable DateTime rather than a bool: it records *when*,
  /// and the "hidden" predicate stays a single `IS NULL`.
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

@DataClassName('RecipeIngredientData')
class RecipeIngredients extends Table with SyncColumns, SyncTombstone {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get recipeId =>
      integer().references(Recipes, #id, onDelete: KeyAction.cascade)();
  IntColumn get foodId =>
      integer().references(Foods, #id, onDelete: KeyAction.restrict)();
  RealColumn get grams => real()();
}

/// One row per logged food/recipe per meal per day.
/// Exactly one of [foodId] / [recipeId] is populated.
@DataClassName('FoodEntryData')
class FoodEntries extends Table with SyncColumns, SyncTombstone {
  IntColumn get id => integer().autoIncrement()();
  // Stored as yyyy-mm-dd to keep date math timezone-stable in queries.
  TextColumn get dateIso => text()();
  TextColumn get meal => text()(); // breakfast | lunch | dinner | snack
  IntColumn get foodId => integer().nullable().references(
    Foods,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get recipeId => integer().nullable().references(
    Recipes,
    #id,
    onDelete: KeyAction.restrict,
  )();

  /// Servings consumed when logging a recipe; ignored for raw foods.
  RealColumn get servings => real().withDefault(const Constant(1))();

  /// Grams override for raw foods; ignored for recipes.
  RealColumn get gramsOverride => real().nullable()();

  /// Exact user-entered amount and its unit (g, ml, serving, etc.).
  RealColumn get portionAmount => real().nullable()();
  TextColumn get portionUnit => text().nullable()();
  DateTimeColumn get loggedAt => dateTime().withDefault(currentDateAndTime)();

  // ── RB-05 nutrition snapshot ──
  // Frozen at log time so historical totals never move when the catalogue is
  // edited or a food is deleted. These hold the food's *per-basis* nutrition
  // profile, not computed totals, so `_portionFactor` still runs at read time
  // and `updateEntry`'s portion edits keep rescaling correctly.
  //
  // `snapshotBasis` is the sentinel: null ⇒ a pre-v24 row the migration could
  // not backfill ⇒ fall back to the live catalogue. For food entries it holds
  // the food's `referenceBasis`; for recipe entries the literal
  // 'recipe serving', and the values below are per-serving totals.
  //
  // Every column is nullable with no default. A `required` generated ctor
  // param would break the synthetic preview draft at log_entry_sheet.dart:991,
  // and a `DEFAULT 0` would be indistinguishable from a measured zero — the
  // exact bug class this fixes.
  TextColumn get snapshotBasis => text().nullable()();
  TextColumn get snapshotName => text().nullable()();
  TextColumn get snapshotBrand => text().nullable()();
  RealColumn get snapshotKcal => real().nullable()();
  RealColumn get snapshotProteinG => real().nullable()();
  RealColumn get snapshotCarbsG => real().nullable()();
  RealColumn get snapshotFatG => real().nullable()();
  RealColumn get snapshotFiberG => real().nullable()();
  RealColumn get snapshotSodiumMg => real().nullable()();
  RealColumn get snapshotPotassiumMg => real().nullable()();
  RealColumn get snapshotCholesterolMg => real().nullable()();
  RealColumn get snapshotServingGrams => real().nullable()();
  RealColumn get snapshotServingAmount => real().nullable()();
  TextColumn get snapshotServingUnit => text().nullable()();

  /// The already-resolved micronutrient map — `_microsForFood`'s output at
  /// factor 1.0, flat `{"vitamin_c": 4.0}`. Not the raw `sourceMetadataJson`
  /// blob, which also carries claims/allergens/provenance and would be an
  /// order of magnitude larger per row. Null when the map is empty;
  /// `snapshotBasis` remains the sole "has snapshot" sentinel.
  TextColumn get snapshotMicrosJson => text().nullable()();
}

@DataClassName('DailySummaryData')
class DailySummaries extends Table with SyncColumns, SyncTombstone {
  TextColumn get dateIso => text()();
  IntColumn get waterMl => integer().withDefault(const Constant(0))();
  RealColumn get weighInKg => real().nullable()();
  TextColumn get notes => text().nullable()();

  @override
  Set<Column> get primaryKey => {dateIso};
}

@DataClassName('FastingSessionData')
class FastingSessions extends Table with SyncColumns, SyncTombstone {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  IntColumn get targetSeconds => integer()();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();
}

/// A recurring "notify to start" fasting reminder (v27). [daysOfWeek] is a
/// bitmask, bit `weekday - 1` per Dart's `DateTime.weekday` (Mon=bit 0 .. Sun
/// = bit 6). [planName] is a [FastingPlan] enum name; when it's `'custom'`,
/// [customTargetSeconds] holds the target (otherwise null — the plan enum's
/// own target applies). [autoStart] starts the session the moment the user
/// taps the notification, skipping if a fast is already active; when false,
/// tapping only opens the Fasting page for the user to review and start
/// manually. True silent background auto-start (no tap at all) isn't
/// reliable on either platform without a native background-execution
/// dependency this app doesn't carry, so it's out of scope — see
/// `fasting_schedule_service.dart`.
@DataClassName('FastingScheduleData')
class FastingSchedules extends Table with SyncColumns, SyncTombstone {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get planName => text()();
  IntColumn get customTargetSeconds => integer().nullable()();
  IntColumn get daysOfWeek => integer()();
  IntColumn get startTimeMinutes => integer()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  BoolColumn get autoStart => boolean().withDefault(const Constant(false))();
}

@DataClassName('ProgramData')
class Programs extends Table with SyncColumns, SyncTombstone {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  IntColumn get weeks => integer().withDefault(const Constant(4))();
  TextColumn get type => text().withDefault(const Constant('block'))();
  TextColumn get progressionStrategy =>
      text().withDefault(const Constant('volume'))();
  BoolColumn get createdByUser => boolean().withDefault(const Constant(true))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  // linear | concurrent | block | max_effort | none (v11, §12)
  TextColumn get periodizationModel =>
      text().withDefault(const Constant('none'))();

  // ── Split & rotation (v21) ──
  /// full_body | upper_lower | ppl | ab | abc | bro | custom
  TextColumn get splitType => text().withDefault(const Constant('custom'))();

  /// weekly = days map to [ProgramDays.dayOfWeek] 1–7 and repeat every calendar
  /// week; cycle = days map to [ProgramDays.cycleDayIndex] 0..cycleLength-1 and
  /// repeat every [cycleLength] days independently of the calendar week.
  TextColumn get scheduleMode => text().withDefault(const Constant('weekly'))();

  /// Length of one rotation in days. Null (or 7) for weekly programs.
  IntColumn get cycleLength => integer().nullable()();

  /// Generator input, kept so the skeleton can be regenerated on edit.
  IntColumn get daysPerWeek => integer().nullable()();

  /// Anchor date (yyyy-MM-dd) the schedule was materialized from, so
  /// re-materializing after an edit does not need to re-ask for a start date.
  TextColumn get startDateIso => text().nullable()();

  /// Exactly one non-archived program is the block shown in the Blocks tab.
  /// The invariant is enforced only by `ProgramsRepository.setActiveProgram`;
  /// never write this column from anywhere else.
  BoolColumn get isActive => boolean().withDefault(const Constant(false))();
}

@DataClassName('ProgramWeekData')
class ProgramWeeks extends Table with SyncColumns, SyncTombstone {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get programId =>
      integer().references(Programs, #id, onDelete: KeyAction.cascade)();
  IntColumn get weekIndex => integer()();
  RealColumn get adjustmentFactor => real().withDefault(const Constant(1.0))();
  // accumulation | transmutation | realization — block periodization (v11)
  TextColumn get blockPhase => text().nullable()();

  /// Intensity multiplier applied to the week's prescribed loads.
  RealColumn get intensityFactor => real().withDefault(const Constant(1.0))();
}

@DataClassName('ProgramDayData')
class ProgramDays extends Table with SyncColumns, SyncTombstone {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get programWeekId =>
      integer().references(ProgramWeeks, #id, onDelete: KeyAction.cascade)();

  /// 1–7 (Mon–Sun). Meaningful only when [cycleDayIndex] is null. For cycle
  /// programs this column is NOT NULL and cannot be relaxed (additive-only
  /// migrations), so it is written as the filler `(cycleDayIndex % 7) + 1` and
  /// must never be read — branch on `cycleDayIndex != null` first.
  IntColumn get dayOfWeek => integer()();
  TextColumn get name => text()();

  // ── Template link, ordering & rotation (v21) ──
  /// Live reference to a workout template. Editing the template changes every
  /// future scheduled session generated from this day; the content is
  /// snapshotted only when the workout is actually started. Null → fall back to
  /// the day's inline [ProgramDayExercises].
  IntColumn get templateId => integer().nullable().references(
    WorkoutTemplates,
    #id,
    onDelete: KeyAction.setNull,
  )();

  /// Order among days sharing the same slot (two-a-days). 0-based, dense within
  /// a `(programWeekId, dayOfWeek | cycleDayIndex)` pair.
  IntColumn get orderIndex => integer().withDefault(const Constant(0))();

  /// The split slot this day fills: 'Push', 'Upper', 'A', 'Full Body B'.
  TextColumn get slotLabel => text().nullable()();

  /// 0-based position in the rotation cycle. AUTHORITATIVE when non-null; see
  /// the note on [dayOfWeek].
  IntColumn get cycleDayIndex => integer().nullable()();

  /// Explicit rest slot inside a cycle. Never materialized to a scheduled
  /// workout; rendered as a rest marker in the builder preview and week board.
  BoolColumn get isRest => boolean().withDefault(const Constant(false))();

  /// Default time of day (minutes since midnight) sessions on this day
  /// materialize with (v28). Null means no particular time. Copied onto each
  /// new [ScheduledWorkouts.startTimeMinutes] row at materialization time —
  /// editing it and re-materializing only reaches future untouched `planned`
  /// occurrences, same as [templateId].
  IntColumn get startTimeMinutes => integer().nullable()();
}

@DataClassName('ProgramDayExerciseData')
class ProgramDayExercises extends Table with SyncColumns, SyncTombstone {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get programDayId =>
      integer().references(ProgramDays, #id, onDelete: KeyAction.cascade)();
  IntColumn get exerciseId => integer().references(
    ExerciseCatalog,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get targetSets => integer().withDefault(const Constant(3))();
  IntColumn get targetRepsMin => integer().nullable()();
  IntColumn get targetRepsMax => integer().nullable()();
  IntColumn get targetRpe => integer().nullable()();
  IntColumn get orderIndex => integer()();

  // ── Periodization & rotation (v11, §12) ──
  /// When set, the actual exercise is picked from the rotation pool for the
  /// current week (accommodation law); [exerciseId] is the pool's default.
  IntColumn get rotationId => integer().nullable().references(
    ExerciseRotations,
    #id,
    onDelete: KeyAction.setNull,
  )();

  /// Prescribed set type (standard | drop | rest_pause | …).
  TextColumn get setType => text().withDefault(const Constant('standard'))();

  /// Load prescription as % of 1RM (max-effort / linear models).
  RealColumn get percentOf1Rm => real().nullable()();

  /// Prescribed equipment variant; null = exercise default.
  TextColumn get equipmentVariant => text().nullable()();
}

/// A pool of exercise variations for one movement pattern. The program
/// rotates the active member every [rotateEveryWeeks] weeks (§12).
@DataClassName('ExerciseRotationData')
class ExerciseRotations extends Table with SyncColumns, SyncTombstone {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get movementPattern => text().nullable()();
  IntColumn get rotateEveryWeeks => integer().withDefault(const Constant(2))();
}

@DataClassName('RotationMemberData')
class RotationMembers extends Table with SyncColumns, SyncTombstone {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get rotationId => integer().references(
    ExerciseRotations,
    #id,
    onDelete: KeyAction.cascade,
  )();
  IntColumn get exerciseId => integer().references(
    ExerciseCatalog,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get orderIndex => integer()();
}

/// Scheduled micro workout (§20), e.g. "50 pushups every 3 hours". Completions
/// write real workout sessions/sets so volume, recovery, and analytics see
/// them like any other training.
@DataClassName('MicroWorkoutData')
class MicroWorkouts extends Table with SyncColumns, SyncTombstone {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  IntColumn get exerciseId => integer().references(
    ExerciseCatalog,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get targetReps => integer()();

  /// Times per day the task should be performed.
  IntColumn get timesPerDay => integer().withDefault(const Constant(1))();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Per-exercise progressive-overload override (§16). Absent row = goal default.
@DataClassName('ExerciseProgressionData')
class ExerciseProgressions extends Table with SyncColumns, SyncTombstone {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get exerciseId =>
      integer().references(ExerciseCatalog, #id, onDelete: KeyAction.cascade)();
  // strength | muscle_gain | fat_loss | endurance | athletic
  TextColumn get goal => text().withDefault(const Constant('muscle_gain'))();
  RealColumn get weeklyIncreasePct => real().withDefault(const Constant(5.0))();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  @override
  List<Set<Column>> get uniqueKeys => [
    {exerciseId},
  ];
}

@DataClassName('ScheduledWorkoutData')
class ScheduledWorkouts extends Table with SyncColumns, SyncTombstone {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get dateIso => text()();
  IntColumn get programDayId =>
      integer().references(ProgramDays, #id, onDelete: KeyAction.cascade)();
  IntColumn get completedSessionId => integer().nullable().references(
    WorkoutSessions,
    #id,
    onDelete: KeyAction.setNull,
  )();
  /// planned | in_progress | done | moved | skipped — see `ScheduleStatus`.
  TextColumn get status => text().withDefault(const Constant('planned'))();

  // ── Ownership, ordering & per-occurrence overrides (v21) ──
  /// Owning program. Lets re-materializing one block leave every other block's
  /// schedule untouched.
  IntColumn get programId => integer().nullable().references(
    Programs,
    #id,
    onDelete: KeyAction.cascade,
  )();

  /// Order within the same [dateIso], across all programs. 0-based, dense.
  IntColumn get orderIndex => integer().withDefault(const Constant(0))();

  /// Which repetition of the program day produced this row (week number for
  /// block programs, cycle number for rotating ones). Together with
  /// [programDayId] this is the identity key that lets re-materialize skip rows
  /// the user has already touched.
  IntColumn get occurrenceIndex => integer().withDefault(const Constant(0))();

  /// One-off template swap for this occurrence only. Wins over
  /// [ProgramDays.templateId] when resolving the session to start.
  IntColumn get templateIdOverride => integer().nullable().references(
    WorkoutTemplates,
    #id,
    onDelete: KeyAction.setNull,
  )();

  /// Time of day (minutes since midnight) this specific occurrence is
  /// scheduled to start (v28). Initialized from
  /// [ProgramDays.startTimeMinutes] at materialization, freely editable per
  /// occurrence afterward — there is no separate "override" column because,
  /// unlike the template link, nothing in the UI needs to distinguish "this
  /// session's own time" from "inherited from the day's default".
  IntColumn get startTimeMinutes => integer().nullable()();
}

@DataClassName('ExternalEventData')
class ExternalEvents extends Table with SyncColumns, SyncTombstone {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get dateFromIso => text()();
  TextColumn get dateToIso => text()();
  TextColumn get type => text()();
  TextColumn get notes => text().nullable()();
}

@DataClassName('HealthSampleData')
class HealthSamples extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get dateIso => text()();
  TextColumn get kind =>
      text()(); // steps | sleep_hours | active_kcal | resting_hr
  RealColumn get value => real()();
}

@DataClassName('CycleLogData')
class CycleLogs extends Table with SyncColumns, SyncTombstone {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get dateIso => text()();
  TextColumn get phase =>
      text()(); // menstrual | follicular | ovulatory | luteal
  IntColumn get intensity => integer().withDefault(const Constant(3))();
  BoolColumn get manualOverride =>
      boolean().withDefault(const Constant(false))();
}

@DataClassName('CycleSettingData')
class CycleSettings extends Table with SyncColumns, SyncTombstone {
  IntColumn get id => integer().withDefault(const Constant(1))();
  IntColumn get avgCycleDays => integer().withDefault(const Constant(28))();
  IntColumn get avgPeriodDays => integer().withDefault(const Constant(5))();
  DateTimeColumn get lastPeriodStart => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('PendingSyncOpData')
class PendingSyncOps extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entityType =>
      text()(); // profile | program | recipe | food | exercise
  TextColumn get entityId => text()(); // local unique identifier (UUID)
  TextColumn get operation => text()(); // upsert | delete
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  // ── Phase 10 sync (v25) ──
  /// Filled in by [SyncService] at push time — SQLite triggers have no auth
  /// context, so this stays null until the outbox is actually drained.
  TextColumn get userId => text().nullable()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get nextRetryAt => dateTime().nullable()();
}

/// Per-table delta-pull cursor (§Phase 10 sync, v25). Lives in Drift rather
/// than SharedPreferences so it survives the same backup/restore path as the
/// rest of local data.
@DataClassName('SyncCursorData')
class SyncCursors extends Table {
  TextColumn get entityType => text()();
  TextColumn get cursorIso => text()();

  @override
  Set<Column> get primaryKey => {entityType};
}

// ── Workout Templates & Folders ────────────────────────────────────────────

/// A folder that groups workout templates (optional — templates without a
/// folderId are "unfiled").
@DataClassName('WorkoutFolderData')
class WorkoutFolders extends Table with SyncColumns, SyncTombstone {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get emoji => text().withDefault(const Constant('💪'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// A reusable workout template. Optionally belongs to a folder.
@DataClassName('WorkoutTemplateData')
class WorkoutTemplates extends Table with SyncColumns, SyncTombstone {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get notes => text().nullable()();
  IntColumn get folderId => integer().nullable().references(
    WorkoutFolders,
    #id,
    onDelete: KeyAction.setNull,
  )();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get lastUsedAt => dateTime().nullable()();
}

/// One exercise slot inside a template, with optional set targets.
@DataClassName('TemplateExerciseData')
class TemplateExercises extends Table with SyncColumns, SyncTombstone {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get templateId => integer().references(
    WorkoutTemplates,
    #id,
    onDelete: KeyAction.cascade,
  )();
  IntColumn get exerciseId => integer().references(
    ExerciseCatalog,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get orderIndex => integer()();
  IntColumn get targetSets => integer().withDefault(const Constant(3))();
  IntColumn get targetRepsMin => integer().nullable()();
  IntColumn get targetRepsMax => integer().nullable()();
  IntColumn get targetRestSeconds => integer().nullable()();
  IntColumn get supersetGroup => integer().nullable()();
}

/// Prescribed sets inside a template exercise.
@DataClassName('TemplateSetData')
class TemplateSets extends Table with SyncColumns, SyncTombstone {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get templateExerciseId => integer().references(
    TemplateExercises,
    #id,
    onDelete: KeyAction.cascade,
  )();
  IntColumn get setOrder => integer()();
  TextColumn get setType => text().withDefault(const Constant('standard'))();
  TextColumn get setTypeMetaJson => text().nullable()();
  IntColumn get targetReps => integer().nullable()();
  IntColumn get targetRepsMin => integer().nullable()();
  IntColumn get targetRepsMax => integer().nullable()();
  RealColumn get targetWeightKg => real().nullable()();
  BoolColumn get isWarmup => boolean().withDefault(const Constant(false))();
}

// ── V2 Logging Foundation (v10) ────────────────────────────────────────────

/// A gym profile. Sessions tag their gym so machine performance can be
/// compared per location while global analytics still aggregate everything.
@DataClassName('GymData')
class Gyms extends Table with SyncColumns, SyncTombstone {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Lifting accessory catalog (belt, sleeves, wraps, straps, fat grips, chains
/// + user-defined). Seeded defaults have [isCustom] = false.
@DataClassName('AccessoryData')
class Accessories extends Table with SyncColumns, SyncTombstone {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  // belt | knee_sleeves | wrist_wraps | straps | fat_grips | chains | custom
  TextColumn get kind => text()();

  /// Multiplier applied to forearm involvement in the recovery engine
  /// (fat grips > 1.0; everything else 1.0).
  RealColumn get forearmMultiplier => real().withDefault(const Constant(1.0))();
  BoolColumn get isCustom => boolean().withDefault(const Constant(false))();
}

/// Resistance/assistance band catalog with estimated tension. Seeded with
/// common colors; users can add brand-specific bands.
@DataClassName('BandData')
class Bands extends Table with SyncColumns, SyncTombstone {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get color => text()();
  RealColumn get tensionKg => real()();
  BoolColumn get isCustom => boolean().withDefault(const Constant(false))();
}

/// Accessories toggled on a single set. PRs/1RM are reported per accessory
/// combination by grouping these rows.
@DataClassName('SetAccessoryData')
class SetAccessories extends Table with SyncColumns, SyncTombstone {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get setEntryId =>
      integer().references(SetEntries, #id, onDelete: KeyAction.cascade)();
  IntColumn get accessoryId =>
      integer().references(Accessories, #id, onDelete: KeyAction.restrict)();

  @override
  List<Set<Column>> get uniqueKeys => [
    {setEntryId, accessoryId},
  ];
}

/// Bands attached to a single set. [mode] decides the sign of the band's
/// contribution to effective load (resistance adds, assistance subtracts).
@DataClassName('SetBandData')
class SetBands extends Table with SyncColumns, SyncTombstone {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get setEntryId =>
      integer().references(SetEntries, #id, onDelete: KeyAction.cascade)();
  IntColumn get bandId =>
      integer().references(Bands, #id, onDelete: KeyAction.restrict)();
  IntColumn get count => integer().withDefault(const Constant(1))();
  // assistance | resistance
  TextColumn get mode => text().withDefault(const Constant('resistance'))();
}

/// Saved machine configuration per exercise (optionally per gym), recalled
/// when the user logs the same machine again.
@DataClassName('MachineSettingData')
class MachineSettings extends Table with SyncColumns, SyncTombstone {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get exerciseId =>
      integer().references(ExerciseCatalog, #id, onDelete: KeyAction.cascade)();
  IntColumn get gymId =>
      integer().nullable().references(Gyms, #id, onDelete: KeyAction.setNull)();
  TextColumn get label => text().nullable()();

  /// JSON object of free-form settings, e.g. {"seat":"6","angle":"45°"}.
  TextColumn get settingsJson => text()();

  /// "Last recalled" UX timestamp (unrelated to sync — [SyncColumns] also
  /// declares an `updatedAt`, but this table's own predates it and keeps its
  /// original meaning; it maps to the remote `recalled_at` column so it never
  /// collides with the server's authoritative sync clock).
  @override
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// One body measurement sample. [metric] is a stable key (bodyweight | arms_l |
/// chest | waist | … | `custom:<name>`); values are metric units (kg / cm).
@DataClassName('BodyMeasurementData')
class BodyMeasurements extends Table with SyncColumns, SyncTombstone {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get dateIso => text()();
  TextColumn get metric => text()();
  RealColumn get value => real()();
}

/// Progress photo pointer. [filePath] is a device-local path under the app
/// documents dir — photos never leave the device.
@DataClassName('ProgressPhotoData')
class ProgressPhotos extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get dateIso => text()();
  // front | side | back
  TextColumn get pose => text()();
  TextColumn get filePath => text()();
  TextColumn get notes => text().nullable()();
}

// ── Assisted rep tracking (v26) ────────────────────────────────────────────
//
// The three tables below are **local-only by design** (REP-04, Phase 10
// CONTEXT "Persistence and sync"). None of them mixes in [SyncColumns] or
// [SyncTombstone], and none appears in `syncedTableNames`
// (`lib/data/local/migrations/sync_backfill.dart`) or in `syncTableSpecs`
// (`lib/data/sync/sync_table_specs.dart`) — adding a name to either list
// installs an outbox trigger and puts motion-derived data on the wire.
// Calibration is specific to one user, on one device, in one placement, so
// it is not meaningful anywhere else. `test/rep_local_only_test.dart` asserts
// this positively against `sqlite_master` rather than by source grep.

/// Single-row global rep-tracking consent and defaults.
///
/// [consentGrantedAt] is the master gate: null means the dedicated consent
/// screen has not been completed and **no** rep-tracking code may run,
/// regardless of any per-exercise preference row.
@DataClassName('RepTrackingSettingData')
class RepTrackingSettings extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Null ⇒ consent screen not completed. The single authority for whether
  /// the tracker may run at all.
  DateTimeColumn get consentGrantedAt => dateTime().nullable()();

  /// Bumping this in code forces re-consent when data handling changes.
  IntColumn get consentVersion => integer().withDefault(const Constant(1))();

  /// wrist | phone
  TextColumn get defaultSource => text().nullable()();

  /// pocket_front | armband | null. Must be non-null before the phone source
  /// is usable (REP-02).
  TextColumn get phonePlacement => text().nullable()();
  BoolColumn get hapticsEnabled => boolean().withDefault(const Constant(true))();

  /// The single global switch (v30).
  ///
  /// Replaces per-exercise opt-in as the thing that turns tracking on.
  /// Eligibility is now a property of the exercise — derived from
  /// `assets/data/rep_tracking_profiles.json`, which covers the whole
  /// catalogue — so asking the user to opt in exercise by exercise was asking
  /// them to re-derive physics the app already knows.
  ///
  /// Defaults to false, and consent still gates it: this switch is only
  /// reachable once the consent screen has been completed, and turning it on
  /// can never bypass `consentGrantedAt`.
  BoolColumn get autoCountEnabled =>
      boolean().withDefault(const Constant(false))();
}

/// Per-exercise opt-in, keyed by [ExerciseCatalog.slug] rather than by
/// `exerciseId` so a catalogue re-import cannot orphan a preference.
@DataClassName('RepTrackingExercisePrefData')
/// Per-exercise **override**, not opt-in.
///
/// Before v30 a row here with `enabled = true` was what turned tracking on for
/// one exercise. From v30 the global switch does that, and this table only
/// records deliberate exceptions: a row with `enabled = false` means "never
/// track this one, even though it is measurable and the global switch is on".
///
/// The reinterpretation needs no data migration and loses no intent. A row
/// left over from the old model with `enabled = false` was a user saying "not
/// this exercise", which is exactly what it still means; a row with
/// `enabled = true` becomes a no-op, which is also what the user wanted. What
/// changes is the default for a **missing** row: it used to mean off and now
/// means follow the global switch, which is safe because that switch defaults
/// to off.
class RepTrackingExercisePrefs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get exerciseSlug => text()();
  BoolColumn get enabled => boolean().withDefault(const Constant(false))();

  /// wrist | phone. Null ⇒ fall back to [RepTrackingSettings.defaultSource].
  TextColumn get preferredSource => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {exerciseSlug},
  ];
}

/// One row per confirmed set that had tracking active — the calibration
/// training set 10-05 consumes.
///
/// **No raw sample column of any kind.** Raw accelerometer arrays live in
/// memory for the duration of the set and are discarded at set end (REP-04);
/// only the derived feature vector ([featuresJson]) and the user-confirmed
/// outcome persist.
@DataClassName('RepSetObservationData')
class RepSetObservations extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get exerciseSlug => text()();
  IntColumn get sessionId => integer()();

  /// Deliberately a plain nullable int and **not** a `references(...)` edge:
  /// a discarded set must leave no dangling FK, and these rows must survive
  /// set deletion so calibration history stays continuous.
  IntColumn get setEntryId => integer().nullable()();
  DateTimeColumn get recordedAt => dateTime()();

  /// wrist | phone
  TextColumn get source => text()();

  /// pocket_front | armband | null (wrist source).
  TextColumn get placement => text().nullable()();

  /// linear_acceleration | accelerometer. Recorded because the two are not
  /// interchangeable for calibration — a profile must not mix them.
  TextColumn get sensorType => text()();
  IntColumn get detectedReps => integer()();
  IntColumn get confirmedReps => integer()();

  /// 0–1.
  RealColumn get confidence => real()();
  IntColumn get suggestedRpeX10 => integer().nullable()();
  IntColumn get confirmedRpeX10 => integer().nullable()();

  /// The derived feature vector; its schema is owned by 10-02.
  TextColumn get featuresJson => text()();
}

// ── Gym Buddy live workout (v29) ───────────────────────────────────────────
//
// The two tables below are **local-only by design** (BUD-02/BUD-04, phase 11
// CONTEXT). Neither mixes in [SyncColumns] or [SyncTombstone], and neither
// appears in `syncedTableNames` (`lib/data/local/migrations/sync_backfill.dart`)
// or in `syncTableSpecs` (`lib/data/sync/sync_table_specs.dart`) — the
// authoritative rows live in Postgres and arrive over the realtime buddy
// channel, and pushing them through the outbox would create a second
// conflicting delivery path for the same rows. `test/buddy/buddy_local_only_test.dart`
// asserts this positively against `sqlite_master` rather than by source grep.

/// Local mirror of one Gym Buddy live session, one row per device per
/// session. Not synced: the server-assigned [buddySessionId] plus
/// [WorkoutSessions.buddySessionId] are what let BUD-07 compute a VS
/// comparison after the fact.
@DataClassName('BuddySessionsLocalData')
class BuddySessionsLocal extends Table {
  TextColumn get buddySessionId => text()(); // uuid, server-assigned
  IntColumn get workoutSessionId => integer()
      .references(WorkoutSessions, #id, onDelete: KeyAction.cascade)();
  TextColumn get role => text()(); // 'host' | 'guest'
  TextColumn get partnerDisplayName => text().nullable()();
  TextColumn get partnerAvatarUrl => text().nullable()();
  IntColumn get lastSeenSeq => integer().withDefault(const Constant(0))();
  DateTimeColumn get joinedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {buddySessionId};
}

/// Local mirror of the shared choreography for one Gym Buddy session, one
/// row per slot per device. Not synced — see the section comment above.
///
/// Invariant, asserted in 11-07's tests: `workoutExerciseId != null` XOR
/// (`unresolvedUuid != null` OR `unresolvedSlug != null`). A slot is either
/// materialised locally or a placeholder — never both, never neither.
@DataClassName('BuddyChoreographySlotData')
class BuddyChoreographySlots extends Table {
  TextColumn get buddySessionId => text()();
  TextColumn get slotId => text()(); // uuid, minted by whoever added the slot

  // Nullable: a slot whose exerciseRef this device cannot resolve is a
  // visible PLACEHOLDER with no local WorkoutExercises row (research
  // Pitfall 8). Making this non-null would make the placeholder
  // unrepresentable and force the silent-drop failure mode the pitfall
  // exists to prevent.
  IntColumn get workoutExerciseId => integer().nullable().references(
    WorkoutExercises,
    #id,
    onDelete: KeyAction.cascade,
  )();

  // The unresolved reference is retained so the slot can be resolved later
  // (partner rebuilds, catalogue updates) and so replace can target it.
  TextColumn get unresolvedUuid => text().nullable()();
  TextColumn get unresolvedSlug => text().nullable()();
  TextColumn get placeholderLabel => text().nullable()();

  // The SHARED choreography position. Distinct from
  // WorkoutExercises.orderIndex, which only orders rows that exist locally —
  // a placeholder has none, but must still hold its place in the shared
  // ordering.
  IntColumn get orderIndex => integer()();

  @override
  Set<Column> get primaryKey => {buddySessionId, slotId};
}
