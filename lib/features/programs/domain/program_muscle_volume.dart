import 'package:drift/drift.dart' show OrderingTerm;
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/programs/domain/periodization.dart';
import 'package:herculex/features/programs/domain/program_csv.dart';
import 'package:herculex/features/programs/domain/split_template.dart';

/// One muscle group's volume contribution in weekly sets.
class MuscleVolumeEntry {
  final String muscle;
  final double sets;
  final double percentage;

  const MuscleVolumeEntry({
    required this.muscle,
    required this.sets,
    this.percentage = 0.0,
  });

  String get formattedSets {
    if (sets == sets.roundToDouble()) {
      return sets.toInt().toString();
    }
    return sets.toStringAsFixed(1);
  }
}

/// Volume breakdown for a single program week.
class WeeklyMuscleBreakdown {
  final int weekIndex;
  final String weekLabel;
  final double totalSets;
  final List<MuscleVolumeEntry> volumes;

  const WeeklyMuscleBreakdown({
    required this.weekIndex,
    required this.weekLabel,
    required this.totalSets,
    required this.volumes,
  });

  String get formattedTotalSets {
    if (totalSets == totalSets.roundToDouble()) {
      return totalSets.toInt().toString();
    }
    return totalSets.toStringAsFixed(1);
  }
}

/// Complete volume breakdown across a whole training program.
class ProgramVolumeBreakdown {
  final List<WeeklyMuscleBreakdown> weeks;
  final List<MuscleVolumeEntry> averageWeeklyVolumes;
  final double averageWeeklyTotalSets;

  const ProgramVolumeBreakdown({
    required this.weeks,
    required this.averageWeeklyVolumes,
    required this.averageWeeklyTotalSets,
  });

  static const empty = ProgramVolumeBreakdown(
    weeks: [],
    averageWeeklyVolumes: [],
    averageWeeklyTotalSets: 0,
  );

  bool get isEmpty => weeks.isEmpty || averageWeeklyTotalSets == 0;
  bool get isNotEmpty => !isEmpty;

  String get formattedAverageTotalSets {
    if (averageWeeklyTotalSets == averageWeeklyTotalSets.roundToDouble()) {
      return averageWeeklyTotalSets.toInt().toString();
    }
    return averageWeeklyTotalSets.toStringAsFixed(1);
  }
}

class ProgramVolumeCalculator {
  /// Normalizes granular muscle names to the canonical 13 primary display groups.
  static const Map<String, String> muscleCanonicalMap = {
    'Serratus': 'Chest',
    'Upper Chest': 'Chest',
    'Lower Chest': 'Chest',
    'Pectorals': 'Chest',
    'Lats': 'Back',
    'Upper Back': 'Back',
    'Lower Back': 'Back',
    'Erectors': 'Back',
    'Rhomboids': 'Back',
    'Front Delts': 'Shoulders',
    'Side Delts': 'Shoulders',
    'Rear Delts': 'Shoulders',
    'Deltoids': 'Shoulders',
    'Brachialis': 'Biceps',
    'Brachioradialis': 'Forearms',
    'Grip': 'Forearms',
    'Wrist Flexors': 'Forearms',
    'Wrist Extensors': 'Forearms',
    'Core': 'Abs',
    'Obliques': 'Abs',
    'Abdominals': 'Abs',
    'Hip Flexors': 'Quads',
    'Vastus Lateralis': 'Quads',
    'Rectus Femoris': 'Quads',
    'Adductors': 'Quads',
    'Abductors': 'Glutes',
    'Tibialis': 'Calves',
    'Soleus': 'Calves',
    'Gastrocnemius': 'Calves',
    'Upper Traps': 'Traps',
    'Middle Traps': 'Traps',
    'Lower Traps': 'Traps',
    'Sternocleidomastoid': 'Neck',
    'Splenius': 'Neck',
  };

  static String normalizeMuscle(String raw) {
    final trimmed = raw.trim();
    if (muscleCanonicalMap.containsKey(trimmed)) {
      return muscleCanonicalMap[trimmed]!;
    }
    // Case-insensitive check
    for (final entry in muscleCanonicalMap.entries) {
      if (entry.key.toLowerCase() == trimmed.toLowerCase()) {
        return entry.value;
      }
    }
    return trimmed;
  }

  /// Maps an exercise name or catalog entry to its primary muscle group.
  static String resolveExerciseMuscle(
    String exerciseName, {
    Map<String, String>? exerciseToMuscle,
  }) {
    if (exerciseToMuscle != null) {
      final key = exerciseName.trim().toLowerCase();
      final direct = exerciseToMuscle[key];
      if (direct != null && direct.isNotEmpty) {
        return normalizeMuscle(direct);
      }
    }

    final lower = exerciseName.toLowerCase();
    if (lower.contains('shrug')) return 'Traps';
    if (lower.contains('neck')) return 'Neck';
    if (lower.contains('bench') ||
        lower.contains('chest') ||
        lower.contains('fly') ||
        lower.contains('push-up') ||
        lower.contains('pushup') ||
        lower.contains('pec')) {
      return 'Chest';
    }
    if (lower.contains('row') ||
        lower.contains('pull-up') ||
        lower.contains('pullup') ||
        lower.contains('pulldown') ||
        lower.contains('chin-up') ||
        lower.contains('deadlift') ||
        lower.contains('lat')) {
      if (lower.contains('upright row')) return 'Shoulders';
      if (lower.contains('romanian deadlift') || lower.contains('rdl'))
        return 'Hamstrings';
      return 'Back';
    }
    if (lower.contains('overhead press') ||
        lower.contains('military press') ||
        lower.contains('shoulder') ||
        lower.contains('lateral raise') ||
        lower.contains('front raise') ||
        lower.contains('upright row')) {
      return 'Shoulders';
    }
    if (lower.contains('bicep') ||
        (lower.contains('curl') &&
            !lower.contains('leg curl') &&
            !lower.contains('wrist curl') &&
            !lower.contains('neck curl'))) {
      if (lower.contains('reverse curl') || lower.contains('hammer curl')) {
        return 'Biceps';
      }
      return 'Biceps';
    }
    if (lower.contains('tricep') ||
        lower.contains('french press') ||
        lower.contains('skull crusher') ||
        lower.contains('skullcrusher') ||
        lower.contains('dip')) {
      return 'Triceps';
    }
    if (lower.contains('squat') ||
        lower.contains('leg press') ||
        lower.contains('leg extension') ||
        lower.contains('lunge') ||
        lower.contains('split squat')) {
      return 'Quads';
    }
    if (lower.contains('leg curl') ||
        lower.contains('romanian') ||
        lower.contains('rdl') ||
        lower.contains('good morning') ||
        lower.contains('hamstring')) {
      return 'Hamstrings';
    }
    if (lower.contains('hip thrust') || lower.contains('glute')) {
      return 'Glutes';
    }
    if (lower.contains('calf') || lower.contains('calves')) {
      return 'Calves';
    }
    if (lower.contains('crunch') ||
        lower.contains('sit-up') ||
        lower.contains('situp') ||
        lower.contains('plank') ||
        lower.contains('leg raise') ||
        lower.contains('russian twist') ||
        lower.contains('ab ')) {
      return 'Abs';
    }
    if (lower.contains('wrist') ||
        lower.contains('forearm') ||
        lower.contains('farmer') ||
        lower.contains('carry')) {
      return 'Forearms';
    }

    return 'Other';
  }

  /// Builds a fast exercise -> muscle lookup table from raw JSON or database catalog.
  static Map<String, String> buildExerciseMapFromJson(List<dynamic> jsonList) {
    final map = <String, String>{};
    for (final item in jsonList) {
      if (item is! Map<String, dynamic>) continue;
      final name = (item['name'] as String?)?.trim();
      final primaryMuscles = item['primaryMuscles'] as List?;
      String muscle = (item['primaryMuscle'] as String?) ?? 'Other';
      if (primaryMuscles != null && primaryMuscles.isNotEmpty) {
        muscle = primaryMuscles.first.toString();
      }
      if (name != null && name.isNotEmpty) {
        map[name.toLowerCase()] = normalizeMuscle(muscle);
      }
      final aka = item['aka'] as List?;
      if (aka != null) {
        for (final a in aka) {
          if (a is String && a.trim().isNotEmpty) {
            map[a.trim().toLowerCase()] = normalizeMuscle(muscle);
          }
        }
      }
    }
    return map;
  }

  /// Computes the volume breakdown from a [ProgramCsvDocument].
  static ProgramVolumeBreakdown computeFromCsv(
    ProgramCsvDocument doc, {
    Map<String, String>? exerciseToMuscle,
  }) {
    if (doc.rows.isEmpty) return ProgramVolumeBreakdown.empty;

    final weekIndices = doc.rows.map((r) => r.weekIndex).toSet().toList()
      ..sort();
    final totalWeeks = doc.weeks > 0 ? doc.weeks : weekIndices.length;
    final model = PeriodizationModel.fromId(doc.periodizationModel);
    final plan = Periodization.plan(model, totalWeeks);

    final weeklyBreakdowns = <WeeklyMuscleBreakdown>[];
    final allMuscleSums = <String, double>{};

    for (var w = 0; w < totalWeeks; w++) {
      final weekPrescription = w < plan.length ? plan[w] : null;
      final isDeload = weekPrescription?.isDeload ?? false;
      final phase = weekPrescription?.blockPhase;

      String label = 'Week ${w + 1}';
      if (isDeload) {
        label = 'Week ${w + 1} (Deload)';
      } else if (phase != null && phase.isNotEmpty) {
        label =
            'Week ${w + 1} (${phase[0].toUpperCase()}${phase.substring(1)})';
      }

      final weekRows = doc.rows.where((r) => r.weekIndex == w).toList();
      // If the CSV only defines week 0, use week 0 template for remaining weeks
      final rowsToUse = weekRows.isNotEmpty
          ? weekRows
          : doc.rows.where((r) => r.weekIndex == 0).toList();

      final muscleSets = <String, double>{};
      double weekTotalSets = 0;

      for (final row in rowsToUse) {
        final muscle = resolveExerciseMuscle(
          row.exerciseName,
          exerciseToMuscle: exerciseToMuscle,
        );
        final sets = row.sets.toDouble();
        muscleSets[muscle] = (muscleSets[muscle] ?? 0.0) + sets;
        weekTotalSets += sets;
        allMuscleSums[muscle] = (allMuscleSums[muscle] ?? 0.0) + sets;
      }

      final entries = muscleSets.entries.map((e) {
        final pct = weekTotalSets > 0 ? (e.value / weekTotalSets) * 100 : 0.0;
        return MuscleVolumeEntry(muscle: e.key, sets: e.value, percentage: pct);
      }).toList()..sort((a, b) => b.sets.compareTo(a.sets));

      weeklyBreakdowns.add(
        WeeklyMuscleBreakdown(
          weekIndex: w,
          weekLabel: label,
          totalSets: weekTotalSets,
          volumes: entries,
        ),
      );
    }

    final averageTotalSets = weeklyBreakdowns.isEmpty
        ? 0.0
        : weeklyBreakdowns.map((w) => w.totalSets).reduce((a, b) => a + b) /
              totalWeeks;

    final avgEntries = allMuscleSums.entries.map((e) {
      final avgSets = e.value / totalWeeks;
      final pct = averageTotalSets > 0
          ? (avgSets / averageTotalSets) * 100
          : 0.0;
      return MuscleVolumeEntry(muscle: e.key, sets: avgSets, percentage: pct);
    }).toList()..sort((a, b) => b.sets.compareTo(a.sets));

    return ProgramVolumeBreakdown(
      weeks: weeklyBreakdowns,
      averageWeeklyVolumes: avgEntries,
      averageWeeklyTotalSets: averageTotalSets,
    );
  }

  /// Computes the volume breakdown from an active database program.
  static Future<ProgramVolumeBreakdown> computeFromDatabase(
    AppDatabase db,
    int programId,
  ) async {
    final program = await (db.select(
      db.programs,
    )..where((t) => t.id.equals(programId))).getSingleOrNull();
    if (program == null) return ProgramVolumeBreakdown.empty;

    final weeks =
        await (db.select(db.programWeeks)
              ..where((t) => t.programId.equals(programId))
              ..orderBy([(t) => OrderingTerm(expression: t.weekIndex)]))
            .get();

    final catalog = await db.select(db.exerciseCatalog).get();
    final muscles = await db.select(db.exerciseMuscles).get();

    final catalogById = {for (final e in catalog) e.id: e};
    final musclesByExercise = <int, List<ExerciseMuscleData>>{};
    for (final m in muscles) {
      musclesByExercise.putIfAbsent(m.exerciseId, () => []).add(m);
    }

    final weeklyBreakdowns = <WeeklyMuscleBreakdown>[];
    final allMuscleSums = <String, double>{};
    final totalWeeks = weeks.isNotEmpty ? weeks.length : program.weeks;

    for (final week in weeks) {
      final isDeload = Periodization.isPlannedDeload(
        model: PeriodizationModel.fromId(program.periodizationModel),
        totalWeeks: program.weeks,
        weekIndex: week.weekIndex,
      );
      final phase = week.blockPhase;
      String label = 'Week ${week.weekIndex + 1}';
      if (isDeload) {
        label = 'Week ${week.weekIndex + 1} (Deload)';
      } else if (phase != null && phase.isNotEmpty) {
        label =
            'Week ${week.weekIndex + 1} (${phase[0].toUpperCase()}${phase.substring(1)})';
      }

      final days = await (db.select(
        db.programDays,
      )..where((t) => t.programWeekId.equals(week.id))).get();
      final muscleSets = <String, double>{};
      double weekTotalSets = 0;

      for (final day in days) {
        if (day.isRest) continue;

        // Either inline exercises or template exercises
        if (day.templateId != null) {
          final tExercises = await (db.select(
            db.templateExercises,
          )..where((t) => t.templateId.equals(day.templateId!))).get();
          for (final te in tExercises) {
            final cat = catalogById[te.exerciseId];
            final mRows = musclesByExercise[te.exerciseId] ?? const [];
            final primaryMuscle =
                mRows.where((m) => m.role == 'primary').firstOrNull?.muscle ??
                cat?.primaryMuscle ??
                'Other';
            final muscle = normalizeMuscle(primaryMuscle);
            final sets = te.targetSets.toDouble();
            muscleSets[muscle] = (muscleSets[muscle] ?? 0.0) + sets;
            weekTotalSets += sets;
            allMuscleSums[muscle] = (allMuscleSums[muscle] ?? 0.0) + sets;
          }
        } else {
          final pExercises = await (db.select(
            db.programDayExercises,
          )..where((t) => t.programDayId.equals(day.id))).get();
          for (final pe in pExercises) {
            final cat = catalogById[pe.exerciseId];
            final mRows = musclesByExercise[pe.exerciseId] ?? const [];
            final primaryMuscle =
                mRows.where((m) => m.role == 'primary').firstOrNull?.muscle ??
                cat?.primaryMuscle ??
                'Other';
            final muscle = normalizeMuscle(primaryMuscle);
            final sets = pe.targetSets.toDouble();
            muscleSets[muscle] = (muscleSets[muscle] ?? 0.0) + sets;
            weekTotalSets += sets;
            allMuscleSums[muscle] = (allMuscleSums[muscle] ?? 0.0) + sets;
          }
        }
      }

      final entries = muscleSets.entries.map((e) {
        final pct = weekTotalSets > 0 ? (e.value / weekTotalSets) * 100 : 0.0;
        return MuscleVolumeEntry(muscle: e.key, sets: e.value, percentage: pct);
      }).toList()..sort((a, b) => b.sets.compareTo(a.sets));

      weeklyBreakdowns.add(
        WeeklyMuscleBreakdown(
          weekIndex: week.weekIndex,
          weekLabel: label,
          totalSets: weekTotalSets,
          volumes: entries,
        ),
      );
    }

    final averageTotalSets = weeklyBreakdowns.isEmpty
        ? 0.0
        : weeklyBreakdowns.map((w) => w.totalSets).reduce((a, b) => a + b) /
              (totalWeeks > 0 ? totalWeeks : 1);

    final avgEntries = allMuscleSums.entries.map((e) {
      final avgSets = e.value / (totalWeeks > 0 ? totalWeeks : 1);
      final pct = averageTotalSets > 0
          ? (avgSets / averageTotalSets) * 100
          : 0.0;
      return MuscleVolumeEntry(muscle: e.key, sets: avgSets, percentage: pct);
    }).toList()..sort((a, b) => b.sets.compareTo(a.sets));

    return ProgramVolumeBreakdown(
      weeks: weeklyBreakdowns,
      averageWeeklyVolumes: avgEntries,
      averageWeeklyTotalSets: averageTotalSets,
    );
  }

  /// Computes the volume breakdown during program building from templates and split plan.
  static Future<ProgramVolumeBreakdown> computeFromTemplates({
    required AppDatabase db,
    required Map<int, int?> templatesBySlot,
    required SplitPlan plan,
    required int weeks,
    required PeriodizationModel model,
  }) async {
    final catalog = await db.select(db.exerciseCatalog).get();
    final muscles = await db.select(db.exerciseMuscles).get();

    final catalogById = {for (final e in catalog) e.id: e};
    final musclesByExercise = <int, List<ExerciseMuscleData>>{};
    for (final m in muscles) {
      musclesByExercise.putIfAbsent(m.exerciseId, () => []).add(m);
    }

    // Map slot index -> List<TemplateExerciseData>
    final slotExercises = <int, List<TemplateExerciseData>>{};
    for (final entry in templatesBySlot.entries) {
      final templateId = entry.value;
      if (templateId == null) continue;
      final tExercises = await (db.select(
        db.templateExercises,
      )..where((t) => t.templateId.equals(templateId))).get();
      slotExercises[entry.key] = tExercises;
    }

    final periodizationPlan = Periodization.plan(model, weeks);
    final weeklyBreakdowns = <WeeklyMuscleBreakdown>[];
    final allMuscleSums = <String, double>{};

    for (var w = 0; w < weeks; w++) {
      final prescription = w < periodizationPlan.length
          ? periodizationPlan[w]
          : null;
      final isDeload = prescription?.isDeload ?? false;
      final phase = prescription?.blockPhase;
      String label = 'Week ${w + 1}';
      if (isDeload) {
        label = 'Week ${w + 1} (Deload)';
      } else if (phase != null && phase.isNotEmpty) {
        label =
            'Week ${w + 1} (${phase[0].toUpperCase()}${phase.substring(1)})';
      }

      final muscleSets = <String, double>{};
      double weekTotalSets = 0;

      for (final day in plan.trainingDays) {
        final tExercises = slotExercises[day.slotIndex] ?? const [];
        for (final te in tExercises) {
          final cat = catalogById[te.exerciseId];
          final mRows = musclesByExercise[te.exerciseId] ?? const [];
          final primaryMuscle =
              mRows.where((m) => m.role == 'primary').firstOrNull?.muscle ??
              cat?.primaryMuscle ??
              'Other';
          final muscle = normalizeMuscle(primaryMuscle);
          final sets = te.targetSets.toDouble();
          muscleSets[muscle] = (muscleSets[muscle] ?? 0.0) + sets;
          weekTotalSets += sets;
          allMuscleSums[muscle] = (allMuscleSums[muscle] ?? 0.0) + sets;
        }
      }

      final entries = muscleSets.entries.map((e) {
        final pct = weekTotalSets > 0 ? (e.value / weekTotalSets) * 100 : 0.0;
        return MuscleVolumeEntry(muscle: e.key, sets: e.value, percentage: pct);
      }).toList()..sort((a, b) => b.sets.compareTo(a.sets));

      weeklyBreakdowns.add(
        WeeklyMuscleBreakdown(
          weekIndex: w,
          weekLabel: label,
          totalSets: weekTotalSets,
          volumes: entries,
        ),
      );
    }

    final averageTotalSets = weeklyBreakdowns.isEmpty
        ? 0.0
        : weeklyBreakdowns.map((w) => w.totalSets).reduce((a, b) => a + b) /
              (weeks > 0 ? weeks : 1);

    final avgEntries = allMuscleSums.entries.map((e) {
      final avgSets = e.value / (weeks > 0 ? weeks : 1);
      final pct = averageTotalSets > 0
          ? (avgSets / averageTotalSets) * 100
          : 0.0;
      return MuscleVolumeEntry(muscle: e.key, sets: avgSets, percentage: pct);
    }).toList()..sort((a, b) => b.sets.compareTo(a.sets));

    return ProgramVolumeBreakdown(
      weeks: weeklyBreakdowns,
      averageWeeklyVolumes: avgEntries,
      averageWeeklyTotalSets: averageTotalSets,
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
