import 'package:intl/intl.dart';

import '../../../data/local/database.dart';
import '../../workouts/domain/set_type.dart';
import 'muscle_recovery_v3.dart';
import 'training_snapshot.dart';
import 'weekly_muscle_volume.dart';

enum VolumeTimeframe {
  thisWeek('This Week'),
  last7Days('Last 7 Days'),
  last30Days('Last 30 Days'),
  thisMonth('This Month'),
  allTime('All Time');

  final String label;
  const VolumeTimeframe(this.label);

  (DateTime?, DateTime?) dateRange(DateTime asOf) {
    switch (this) {
      case VolumeTimeframe.thisWeek:
        final start = WeeklyMuscleVolume.weekStartOf(asOf);
        return (start, asOf);
      case VolumeTimeframe.last7Days:
        final start = DateTime(asOf.year, asOf.month, asOf.day)
            .subtract(const Duration(days: 7));
        return (start, asOf);
      case VolumeTimeframe.last30Days:
        final start = DateTime(asOf.year, asOf.month, asOf.day)
            .subtract(const Duration(days: 30));
        return (start, asOf);
      case VolumeTimeframe.thisMonth:
        final start = DateTime(asOf.year, asOf.month, 1);
        return (start, asOf);
      case VolumeTimeframe.allTime:
        return (null, null);
    }
  }
}

enum MuscleRegion {
  upper('Upper Body'),
  lower('Lower Body'),
  core('Core');

  final String label;
  const MuscleRegion(this.label);

  static MuscleRegion fromMuscle(String muscle) {
    switch (muscle) {
      case 'Quads':
      case 'Hamstrings':
      case 'Glutes':
      case 'Calves':
      case 'Adductors':
      case 'Abductors':
        return MuscleRegion.lower;
      case 'Abs':
      case 'Obliques':
        return MuscleRegion.core;
      default:
        return MuscleRegion.upper;
    }
  }
}

/// Overview entry for a single muscle group over the selected timeframe.
class MuscleGroupOverviewItem {
  final String muscle;
  final MuscleRegion region;
  final double tonnageKg;
  final double sets;
  final int rawSets;
  final int exerciseCount;
  final int workoutCount;
  final DateTime? lastTrained;
  final double percentageOfMax;

  const MuscleGroupOverviewItem({
    required this.muscle,
    required this.region,
    required this.tonnageKg,
    required this.sets,
    required this.rawSets,
    required this.exerciseCount,
    required this.workoutCount,
    required this.lastTrained,
    required this.percentageOfMax,
  });
}

/// Aggregated volume overview across all muscle groups.
class MuscleVolumeOverviewData {
  final VolumeTimeframe timeframe;
  final DateTime? startDate;
  final DateTime? endDate;
  final double totalTonnageKg;
  final int totalSets;
  final int totalWorkouts;
  final int totalExercises;
  final List<MuscleGroupOverviewItem> groups;

  const MuscleVolumeOverviewData({
    required this.timeframe,
    required this.startDate,
    required this.endDate,
    required this.totalTonnageKg,
    required this.totalSets,
    required this.totalWorkouts,
    required this.totalExercises,
    required this.groups,
  });
}

/// Single set detail inside a workout exercise for a muscle.
class MuscleSetItem {
  final int setId;
  final int setIndex;
  final double weightKg;
  final int reps;
  final double effectiveKg;
  final double tonnageKg;
  final int? rpeX10;
  final SetType setType;
  final DateTime? completedAt;
  final List<String> accessoryNames;

  const MuscleSetItem({
    required this.setId,
    required this.setIndex,
    required this.weightKg,
    required this.reps,
    required this.effectiveKg,
    required this.tonnageKg,
    this.rpeX10,
    required this.setType,
    this.completedAt,
    required this.accessoryNames,
  });
}

/// Exercise performed in a session that targeted the target muscle group.
class MuscleWorkoutExerciseItem {
  final int exerciseId;
  final String exerciseName;
  final String role; // 'primary' | 'secondary' | 'stabilizer'
  final double roleWeight;
  final String equipmentVariant;
  final double exerciseTonnageKg;
  final int exerciseSetsCount;
  final List<MuscleSetItem> sets;

  const MuscleWorkoutExerciseItem({
    required this.exerciseId,
    required this.exerciseName,
    required this.role,
    required this.roleWeight,
    required this.equipmentVariant,
    required this.exerciseTonnageKg,
    required this.exerciseSetsCount,
    required this.sets,
  });
}

/// Workout session containing exercises that targeted the muscle group.
class MuscleWorkoutSessionItem {
  final int sessionId;
  final String sessionName;
  final DateTime date;
  final int? sessionRpe;
  final double muscleTonnageKg;
  final double muscleSets;
  final int rawSetsCount;
  final List<MuscleWorkoutExerciseItem> exercises;

  const MuscleWorkoutSessionItem({
    required this.sessionId,
    required this.sessionName,
    required this.date,
    this.sessionRpe,
    required this.muscleTonnageKg,
    required this.muscleSets,
    required this.rawSetsCount,
    required this.exercises,
  });
}

/// Complete detailed breakdown for a specific muscle group.
class MuscleGroupDetailData {
  final String muscle;
  final MuscleRegion region;
  final VolumeTimeframe timeframe;
  final DateTime? startDate;
  final DateTime? endDate;
  final double totalTonnageKg;
  final double totalSets;
  final int rawSetsCount;
  final int totalReps;
  final int workoutsCount;
  final int distinctExercisesCount;
  final String? topExercise;
  final List<MuscleWorkoutSessionItem> workouts;

  const MuscleGroupDetailData({
    required this.muscle,
    required this.region,
    required this.timeframe,
    required this.startDate,
    required this.endDate,
    required this.totalTonnageKg,
    required this.totalSets,
    required this.rawSetsCount,
    required this.totalReps,
    required this.workoutsCount,
    required this.distinctExercisesCount,
    this.topExercise,
    required this.workouts,
  });
}

/// Pure computation engine for Muscle Volume Analytics.
abstract final class MuscleVolumeAnalyticsEngine {
  /// Computes overview statistics across all 19 muscle groups.
  static MuscleVolumeOverviewData computeOverview({
    required TrainingSnapshot snapshot,
    required DateTime asOf,
    required VolumeTimeframe timeframe,
  }) {
    final (start, end) = timeframe.dateRange(asOf);

    final musclesByExercise = <int, List<ExerciseMuscleData>>{};
    for (final m in snapshot.exerciseMuscles) {
      musclesByExercise.putIfAbsent(m.exerciseId, () => []).add(m);
    }

    final tonnage = {for (final g in MuscleRecoveryV3.groups) g: 0.0};
    final sets = {for (final g in MuscleRecoveryV3.groups) g: 0.0};
    final rawSets = {for (final g in MuscleRecoveryV3.groups) g: 0};
    final exercises = {for (final g in MuscleRecoveryV3.groups) g: <int>{}};
    final workouts = {for (final g in MuscleRecoveryV3.groups) g: <int>{}};
    final lastTrained = {for (final g in MuscleRecoveryV3.groups) g: <DateTime>[]};

    var totalOverallTonnage = 0.0;
    var totalOverallSets = 0;
    final allDistinctWorkouts = <int>{};
    final allDistinctExercises = <int>{};

    for (final rs in snapshot.sets) {
      final completedAt = rs.set.completedAt ?? rs.session.startedAt;
      if (start != null && completedAt.isBefore(start)) continue;
      if (end != null && completedAt.isAfter(end)) continue;

      totalOverallTonnage += rs.tonnageKg;
      totalOverallSets++;
      allDistinctWorkouts.add(rs.session.id);
      allDistinctExercises.add(rs.exercise.id);

      final involvement =
          MuscleRecoveryV3.involvementFor(rs, musclesByExercise);
      for (final (muscle, w) in involvement) {
        if (!tonnage.containsKey(muscle)) continue;
        tonnage[muscle] = tonnage[muscle]! + rs.tonnageKg * w;
        sets[muscle] = sets[muscle]! + (w >= 1.0 ? 1.0 : w);
        rawSets[muscle] = rawSets[muscle]! + 1;
        exercises[muscle]!.add(rs.exercise.id);
        workouts[muscle]!.add(rs.session.id);
        lastTrained[muscle]!.add(completedAt);
      }
    }

    // Find max tonnage among groups for relative progress bars
    var maxTonnage = 0.0;
    for (final val in tonnage.values) {
      if (val > maxTonnage) maxTonnage = val;
    }

    final groups = <MuscleGroupOverviewItem>[
      for (final g in MuscleRecoveryV3.groups)
        MuscleGroupOverviewItem(
          muscle: g,
          region: MuscleRegion.fromMuscle(g),
          tonnageKg: tonnage[g]!,
          sets: sets[g]!,
          rawSets: rawSets[g]!,
          exerciseCount: exercises[g]!.length,
          workoutCount: workouts[g]!.length,
          lastTrained: lastTrained[g]!.isEmpty
              ? null
              : (lastTrained[g]!..sort()).last,
          percentageOfMax: maxTonnage <= 0 ? 0.0 : (tonnage[g]! / maxTonnage).clamp(0.0, 1.0),
        ),
    ];

    return MuscleVolumeOverviewData(
      timeframe: timeframe,
      startDate: start,
      endDate: end,
      totalTonnageKg: totalOverallTonnage,
      totalSets: totalOverallSets,
      totalWorkouts: allDistinctWorkouts.length,
      totalExercises: allDistinctExercises.length,
      groups: groups,
    );
  }

  /// Computes detailed workout history and exercise logs for a specific muscle group.
  static MuscleGroupDetailData computeMuscleDetail({
    required TrainingSnapshot snapshot,
    required String muscle,
    required DateTime asOf,
    required VolumeTimeframe timeframe,
  }) {
    final (start, end) = timeframe.dateRange(asOf);

    final musclesByExercise = <int, List<ExerciseMuscleData>>{};
    for (final m in snapshot.exerciseMuscles) {
      musclesByExercise.putIfAbsent(m.exerciseId, () => []).add(m);
    }

    // Filter sets matching the date range and targeting this muscle
    final matchingSets = <(ResolvedSet, String role, double weight)>[];
    final exerciseFrequency = <String, int>{};

    for (final rs in snapshot.sets) {
      final completedAt = rs.set.completedAt ?? rs.session.startedAt;
      if (start != null && completedAt.isBefore(start)) continue;
      if (end != null && completedAt.isAfter(end)) continue;

      final rows = musclesByExercise[rs.exercise.id] ?? const [];
      var matched = false;
      if (rows.isNotEmpty) {
        for (final r in rows) {
          final mappedMuscle = MuscleRecoveryV3.alias[r.muscle] ?? r.muscle;
          if (mappedMuscle.toLowerCase() == muscle.toLowerCase()) {
            final w = (MuscleRecoveryV3.roleWeight[r.role] ?? 0) * r.contribution;
            matchingSets.add((rs, r.role, w));
            matched = true;
            break;
          }
        }
      } else {
        final mappedMuscle = MuscleRecoveryV3.alias[rs.exercise.primaryMuscle] ??
            rs.exercise.primaryMuscle;
        if (mappedMuscle.toLowerCase() == muscle.toLowerCase()) {
          matchingSets.add((rs, 'primary', 1.0));
          matched = true;
        }
      }

      if (matched) {
        exerciseFrequency[rs.exercise.name] =
            (exerciseFrequency[rs.exercise.name] ?? 0) + 1;
      }
    }

    // Group matching sets by WorkoutSession -> WorkoutExercise
    final setsBySession = <int, List<(ResolvedSet, String, double)>>{};
    final sessionMap = <int, WorkoutSessionData>{};

    for (final item in matchingSets) {
      final rs = item.$1;
      setsBySession.putIfAbsent(rs.session.id, () => []).add(item);
      sessionMap[rs.session.id] = rs.session;
    }

    var totalTonnageKg = 0.0;
    var totalSets = 0.0;
    var rawSetsCount = 0;
    var totalReps = 0;
    final distinctExercises = <int>{};

    final workoutItems = <MuscleWorkoutSessionItem>[];

    for (final entry in setsBySession.entries) {
      final sessionId = entry.key;
      final session = sessionMap[sessionId]!;
      final sessionSets = entry.value;

      var sessionTonnage = 0.0;
      var sessionMuscleSets = 0.0;
      var sessionRawSets = 0;

      // Group by WorkoutExercise
      final exercisesInSession =
          <int, List<(ResolvedSet, String, double)>>{};
      for (final s in sessionSets) {
        exercisesInSession.putIfAbsent(s.$1.workoutExercise.id, () => []).add(s);
      }

      final exerciseItems = <MuscleWorkoutExerciseItem>[];

      for (final weEntry in exercisesInSession.entries) {
        final weSets = weEntry.value;
        final first = weSets.first.$1;
        final role = weSets.first.$2;
        final roleWeight = weSets.first.$3;

        var exTonnage = 0.0;
        final setList = <MuscleSetItem>[];

        for (final item in weSets) {
          final rs = item.$1;
          final w = item.$3;
          final setTonnage = rs.tonnageKg;

          exTonnage += setTonnage;
          sessionTonnage += setTonnage * w;
          sessionMuscleSets += (w >= 1.0 ? 1.0 : w);
          sessionRawSets++;
          totalReps += rs.countedReps;
          distinctExercises.add(rs.exercise.id);

          setList.add(MuscleSetItem(
            setId: rs.set.id,
            setIndex: rs.set.setIndex,
            weightKg: rs.set.weightKg,
            reps: rs.countedReps,
            effectiveKg: rs.effectiveKg,
            tonnageKg: setTonnage,
            rpeX10: rs.set.rpeX10,
            setType: rs.setType,
            completedAt: rs.set.completedAt,
            accessoryNames: rs.accessoryNames,
          ));
        }

        setList.sort((a, b) => a.setIndex.compareTo(b.setIndex));

        exerciseItems.add(MuscleWorkoutExerciseItem(
          exerciseId: first.exercise.id,
          exerciseName: first.exercise.name,
          role: role,
          roleWeight: roleWeight,
          equipmentVariant: first.equipmentVariant,
          exerciseTonnageKg: exTonnage,
          exerciseSetsCount: setList.length,
          sets: setList,
        ));
      }

      totalTonnageKg += sessionTonnage;
      totalSets += sessionMuscleSets;
      rawSetsCount += sessionRawSets;

      workoutItems.add(MuscleWorkoutSessionItem(
        sessionId: sessionId,
        sessionName: _formatSessionName(session),
        date: session.startedAt,
        sessionRpe: session.sessionRpe,
        muscleTonnageKg: sessionTonnage,
        muscleSets: sessionMuscleSets,
        rawSetsCount: sessionRawSets,
        exercises: exerciseItems,
      ));
    }

    // Sort workouts newest first
    workoutItems.sort((a, b) => b.date.compareTo(a.date));

    // Find top exercise
    String? topExercise;
    var maxFreq = 0;
    for (final e in exerciseFrequency.entries) {
      if (e.value > maxFreq) {
        maxFreq = e.value;
        topExercise = e.key;
      }
    }

    return MuscleGroupDetailData(
      muscle: muscle,
      region: MuscleRegion.fromMuscle(muscle),
      timeframe: timeframe,
      startDate: start,
      endDate: end,
      totalTonnageKg: totalTonnageKg,
      totalSets: totalSets,
      rawSetsCount: rawSetsCount,
      totalReps: totalReps,
      workoutsCount: workoutItems.length,
      distinctExercisesCount: distinctExercises.length,
      topExercise: topExercise,
      workouts: workoutItems,
    );
  }

  static String _formatSessionName(WorkoutSessionData session) {
    final name = session.name?.trim() ?? '';
    if (name.isNotEmpty) return name;
    return 'Workout • ${DateFormat('HH:mm').format(session.startedAt)}';
  }
}
