import '../../../data/local/database.dart';
import '../../workouts/domain/effective_load.dart';
import '../../workouts/domain/logging_metric.dart';
import '../../workouts/domain/set_type.dart';

/// One completed working set with everything the engines need resolved:
/// exercise attributes, equipment variant, bands/chains/accessories, and the
/// resulting effective load. Built once per snapshot so recovery, CNS, volume,
/// and PR engines all read identical numbers (V2 §23).
class ResolvedSet {
  final SetEntryData set;
  final WorkoutExerciseData workoutExercise;
  final WorkoutSessionData session;
  final ExerciseCatalogData exercise;
  final SetType setType;
  final List<BandContribution> bands;

  /// Names of accessories attached to this set, sorted (e.g. ["Belt",
  /// "Knee Sleeves"]). Drives per-combo PR grouping.
  final List<String> accessoryNames;

  /// Highest forearm multiplier among attached accessories (fat grips → 1.6).
  final double forearmMultiplier;

  final double effectiveKg;

  ResolvedSet({
    required this.set,
    required this.workoutExercise,
    required this.session,
    required this.exercise,
    required this.setType,
    required this.bands,
    required this.accessoryNames,
    required this.forearmMultiplier,
  }) : effectiveKg = EffectiveLoad.computeKg(
          weightKg: set.weightKg,
          bodyweightKg: set.bodyweightKg,
          includesBodyweight: exercise.supportsWeightedBodyweight,
          chainsKg: set.chainsKg,
          bands: bands,
        );

  /// What this exercise is measured in (EXR-05).
  LoggingMetric get metric => LoggingMetric.fromId(exercise.loggingMetric);

  /// Tonnage of this set, or zero when reps are not the unit of work.
  ///
  /// A sled push and a plank both store `reps = 0`, so the arithmetic would
  /// come out at zero anyway — but the exclusion is deliberately decided by
  /// the metric rather than by the stored numbers, because the numbers are a
  /// NOT NULL placeholder and the metric is the fact. A timed loaded carry
  /// that someone logs a rep count into must still not become tonnage.
  ///
  /// The gate is [LoggingMetric.isRepBased], not `isLoaded`: a bodyweight
  /// pull-up is rep work whose effective load is the athlete's own mass, and
  /// it keeps counting exactly as it did before this phase.
  double get tonnageKg => metric.isRepBased
      ? EffectiveLoad.tonnageKg(
          effectiveKg: effectiveKg, reps: set.reps, setType: setType)
      : 0.0;

  /// Reps this set contributes to a rep total, or zero for non-rep work.
  int get countedReps => metric.isRepBased ? set.reps : 0;

  String get equipmentVariant =>
      workoutExercise.equipmentVariant ?? exercise.modality;

  /// Accessory-combination key for PR grouping ("Raw" when none).
  String get accessoryCombo =>
      accessoryNames.isEmpty ? 'Raw' : accessoryNames.join(' + ');

  /// Weighted-bodyweight work is more CNS-costly: +2 on the 1–10 scale (§9).
  int get cnsScore => exercise.supportsWeightedBodyweight &&
          set.bodyweightKg != null &&
          set.weightKg > 0
      ? (exercise.cnsScore + 2).clamp(1, 10)
      : exercise.cnsScore;
}

/// Materialized view over the workout tables, joined in memory. Engines are
/// pure functions over [sets]; the snapshot owns all DB access.
class TrainingSnapshot {
  final List<ResolvedSet> sets;
  final List<ExerciseMuscleData> exerciseMuscles;

  const TrainingSnapshot({required this.sets, required this.exerciseMuscles});

  /// Loads every completed, non-warmup set with its attachments resolved.
  static Future<TrainingSnapshot> load(AppDatabase db) async {
    final results = await Future.wait([
      (db.select(db.setEntries)..where((t) => t.deletedAt.isNull())).get(),
      (db.select(db.workoutExercises)..where((t) => t.deletedAt.isNull()))
          .get(),
      (db.select(db.workoutSessions)..where((t) => t.deletedAt.isNull()))
          .get(),
      (db.select(db.exerciseCatalog)..where((t) => t.deletedAt.isNull()))
          .get(),
      db.select(db.exerciseMuscles).get(),
      (db.select(db.setAccessories)..where((t) => t.deletedAt.isNull()))
          .get(),
      (db.select(db.setBands)..where((t) => t.deletedAt.isNull())).get(),
      (db.select(db.accessories)..where((t) => t.deletedAt.isNull())).get(),
      (db.select(db.bands)..where((t) => t.deletedAt.isNull())).get(),
    ]);
    final setRows = results[0] as List<SetEntryData>;
    final weRows = results[1] as List<WorkoutExerciseData>;
    final sessionRows = results[2] as List<WorkoutSessionData>;
    final catalog = results[3] as List<ExerciseCatalogData>;
    final muscles = results[4] as List<ExerciseMuscleData>;
    final setAccessories = results[5] as List<SetAccessoryData>;
    final setBands = results[6] as List<SetBandData>;
    final accessories = results[7] as List<AccessoryData>;
    final bands = results[8] as List<BandData>;

    final weById = {for (final w in weRows) w.id: w};
    final sessionById = {for (final s in sessionRows) s.id: s};
    final exById = {for (final e in catalog) e.id: e};
    final accessoryById = {for (final a in accessories) a.id: a};
    final bandById = {for (final b in bands) b.id: b};

    final accessoriesBySet = <int, List<AccessoryData>>{};
    for (final sa in setAccessories) {
      final a = accessoryById[sa.accessoryId];
      if (a != null) accessoriesBySet.putIfAbsent(sa.setEntryId, () => []).add(a);
    }
    final bandsBySet = <int, List<BandContribution>>{};
    for (final sb in setBands) {
      final b = bandById[sb.bandId];
      if (b == null) continue;
      bandsBySet.putIfAbsent(sb.setEntryId, () => []).add(BandContribution(
            tensionKg: b.tensionKg,
            count: sb.count,
            isResistance: sb.mode == 'resistance',
          ));
    }

    final resolved = <ResolvedSet>[];
    for (final set in setRows) {
      if (!set.isCompleted || set.isWarmup) continue;
      final we = weById[set.workoutExerciseId];
      if (we == null) continue;
      final session = sessionById[we.sessionId];
      final ex = exById[we.exerciseId];
      if (session == null || ex == null) continue;

      final setAccs = accessoriesBySet[set.id] ?? const <AccessoryData>[];
      final setBandsList = bandsBySet[set.id] ?? const <BandContribution>[];

      final names = setAccs.map((a) => a.name).toList();
      for (final b in setBandsList) {
        final modeStr = b.isResistance ? 'Res.' : 'Ast.';
        final sign = b.isResistance ? '+' : '-';
        final avgKg = b.averageKg.abs();
        final fmtKg = avgKg.truncateToDouble() == avgKg
            ? avgKg.toStringAsFixed(0)
            : avgKg.toStringAsFixed(1);
        names.add('Band ($modeStr $sign${fmtKg}kg)');
      }
      if (set.chainsKg != null && set.chainsKg! > 0) {
        final cVal = set.chainsKg!;
        final cFmt = cVal.truncateToDouble() == cVal
            ? cVal.toStringAsFixed(0)
            : cVal.toStringAsFixed(1);
        names.add('Chains (${cFmt}kg)');
      }
      names.sort();

      var forearm = 1.0;
      for (final a in setAccs) {
        if (a.forearmMultiplier > forearm) forearm = a.forearmMultiplier;
      }

      resolved.add(ResolvedSet(
        set: set,
        workoutExercise: we,
        session: session,
        exercise: ex,
        setType: SetType.fromId(set.setType),
        bands: setBandsList,
        accessoryNames: names,
        forearmMultiplier: forearm,
      ));
    }

    return TrainingSnapshot(sets: resolved, exerciseMuscles: muscles);
  }
}
