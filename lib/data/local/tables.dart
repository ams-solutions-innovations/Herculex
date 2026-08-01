import 'package:drift/drift.dart';

/// Canonical exercise library. Most rows are seeded; user-created rows have
/// [isCustom] = true.
@DataClassName('ExerciseCatalogData')
class ExerciseCatalog extends Table {
  IntColumn get id => integer().autoIncrement()();
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
class WorkoutSessions extends Table {
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
}

@DataClassName('WorkoutExerciseData')
class WorkoutExercises extends Table {
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
class SetEntries extends Table {
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
}

// ── Nutrition ──────────────────────────────────────────────────────────────

/// All nutrient values are per-100g (or per-100ml for liquids); convert via
/// [servingGrams] when displaying a serving-sized macro.
@DataClassName('FoodData')
class Foods extends Table {
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
class NutritionTargets extends Table {
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
class DietSchedules extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get startDateIso => text()();
  RealColumn get reducePct => real()();
  IntColumn get intervalDays => integer()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
}

/// A generated weekly carb-cycle plan (§19): 7 day levels (high|med|low)
/// keyed off the week's Monday.
@DataClassName('CarbCyclePlanData')
class CarbCyclePlans extends Table {
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
class Recipes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  IntColumn get servings => integer().withDefault(const Constant(1))();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('RecipeIngredientData')
class RecipeIngredients extends Table {
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
class FoodEntries extends Table {
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
}

@DataClassName('DailySummaryData')
class DailySummaries extends Table {
  TextColumn get dateIso => text()();
  IntColumn get waterMl => integer().withDefault(const Constant(0))();
  RealColumn get weighInKg => real().nullable()();
  TextColumn get notes => text().nullable()();

  @override
  Set<Column> get primaryKey => {dateIso};
}

@DataClassName('FastingSessionData')
class FastingSessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  IntColumn get targetSeconds => integer()();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();
}

@DataClassName('ProgramData')
class Programs extends Table {
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
}

@DataClassName('ProgramWeekData')
class ProgramWeeks extends Table {
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
class ProgramDays extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get programWeekId =>
      integer().references(ProgramWeeks, #id, onDelete: KeyAction.cascade)();
  IntColumn get dayOfWeek => integer()();
  TextColumn get name => text()();
}

@DataClassName('ProgramDayExerciseData')
class ProgramDayExercises extends Table {
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
class ExerciseRotations extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get movementPattern => text().nullable()();
  IntColumn get rotateEveryWeeks => integer().withDefault(const Constant(2))();
}

@DataClassName('RotationMemberData')
class RotationMembers extends Table {
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
class MicroWorkouts extends Table {
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
class ExerciseProgressions extends Table {
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
class ScheduledWorkouts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get dateIso => text()();
  IntColumn get programDayId =>
      integer().references(ProgramDays, #id, onDelete: KeyAction.cascade)();
  IntColumn get completedSessionId => integer().nullable().references(
    WorkoutSessions,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get status => text().withDefault(const Constant('planned'))();
}

@DataClassName('ExternalEventData')
class ExternalEvents extends Table {
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
class CycleLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get dateIso => text()();
  TextColumn get phase =>
      text()(); // menstrual | follicular | ovulatory | luteal
  IntColumn get intensity => integer().withDefault(const Constant(3))();
  BoolColumn get manualOverride =>
      boolean().withDefault(const Constant(false))();
}

@DataClassName('CycleSettingData')
class CycleSettings extends Table {
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
}

// ── Workout Templates & Folders ────────────────────────────────────────────

/// A folder that groups workout templates (optional — templates without a
/// folderId are "unfiled").
@DataClassName('WorkoutFolderData')
class WorkoutFolders extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get emoji => text().withDefault(const Constant('💪'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// A reusable workout template. Optionally belongs to a folder.
@DataClassName('WorkoutTemplateData')
class WorkoutTemplates extends Table {
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
class TemplateExercises extends Table {
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

// ── V2 Logging Foundation (v10) ────────────────────────────────────────────

/// A gym profile. Sessions tag their gym so machine performance can be
/// compared per location while global analytics still aggregate everything.
@DataClassName('GymData')
class Gyms extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Lifting accessory catalog (belt, sleeves, wraps, straps, fat grips, chains
/// + user-defined). Seeded defaults have [isCustom] = false.
@DataClassName('AccessoryData')
class Accessories extends Table {
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
class Bands extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get color => text()();
  RealColumn get tensionKg => real()();
  BoolColumn get isCustom => boolean().withDefault(const Constant(false))();
}

/// Accessories toggled on a single set. PRs/1RM are reported per accessory
/// combination by grouping these rows.
@DataClassName('SetAccessoryData')
class SetAccessories extends Table {
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
class SetBands extends Table {
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
class MachineSettings extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get exerciseId =>
      integer().references(ExerciseCatalog, #id, onDelete: KeyAction.cascade)();
  IntColumn get gymId =>
      integer().nullable().references(Gyms, #id, onDelete: KeyAction.setNull)();
  TextColumn get label => text().nullable()();

  /// JSON object of free-form settings, e.g. {"seat":"6","angle":"45°"}.
  TextColumn get settingsJson => text()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// One body measurement sample. [metric] is a stable key (bodyweight | arms_l |
/// chest | waist | … | `custom:<name>`); values are metric units (kg / cm).
@DataClassName('BodyMeasurementData')
class BodyMeasurements extends Table {
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
