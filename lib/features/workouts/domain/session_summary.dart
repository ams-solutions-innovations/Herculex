import '../../../core/notifications/in_app_notification_model.dart';
import '../../analytics/domain/muscle_recovery_v3.dart';
import '../../analytics/domain/training_snapshot.dart';

/// Headline numbers for one finished session, shown on the finish screen and
/// in the shareable card.
class SessionSummary {
  final int sessionId;
  final String name;
  final DateTime startedAt;
  final Duration duration;

  final int totalSets;
  final int totalReps;

  /// Tonnage in kg, using effective load (bands, chains, bodyweight).
  final double tonnageKg;

  final int exerciseCount;

  /// Muscle groups trained, heaviest first — at most a handful, for chips.
  final List<String> muscleGroups;

  /// Unlocked records and achievements for this session (for share card & review).
  final List<InAppNotificationItem> achievements;

  /// Photo path on local device, if attached.
  final String? photoPath;

  /// Total calories burned (in kcal).
  final int caloriesBurned;

  const SessionSummary({
    required this.sessionId,
    required this.name,
    required this.startedAt,
    required this.duration,
    required this.totalSets,
    required this.totalReps,
    required this.tonnageKg,
    required this.exerciseCount,
    required this.muscleGroups,
    this.achievements = const [],
    this.photoPath,
    this.caloriesBurned = 0,
  });

  /// Reduces a loaded [snapshot] to just [sessionId].
  static SessionSummary fromSnapshot({
    required TrainingSnapshot snapshot,
    required int sessionId,
    required String name,
    required DateTime startedAt,
    required DateTime? endedAt,
    List<InAppNotificationItem> achievements = const [],
    String? photoPath,
    int? savedCalories,
    double? userWeightKg,
  }) {
    final sets = [
      for (final rs in snapshot.sets)
        if (rs.session.id == sessionId) rs,
    ];

    final musclesByExercise = <int, List<String>>{};
    for (final m in snapshot.exerciseMuscles) {
      if (m.role != 'primary') continue;
      musclesByExercise
          .putIfAbsent(m.exerciseId, () => [])
          .add(MuscleRecoveryV3.alias[m.muscle] ?? m.muscle);
    }

    var reps = 0;
    var tonnage = 0.0;
    var explicitCalories = 0;
    final exerciseIds = <int>{};
    final muscleSets = <String, int>{};

    for (final rs in sets) {
      reps += rs.countedReps;
      tonnage += rs.tonnageKg;
      if (rs.set.calories != null && rs.set.calories! > 0) {
        explicitCalories += rs.set.calories!;
      }
      exerciseIds.add(rs.exercise.id);

      final muscles = musclesByExercise[rs.exercise.id] ??
          [
            MuscleRecoveryV3.alias[rs.exercise.primaryMuscle] ??
                rs.exercise.primaryMuscle
          ];
      for (final m in muscles) {
        muscleSets[m] = (muscleSets[m] ?? 0) + 1;
      }
    }

    final duration = (endedAt ?? startedAt).difference(startedAt);

    int finalCalories;
    if (savedCalories != null && savedCalories > 0) {
      finalCalories = savedCalories;
    } else if (explicitCalories > 0) {
      finalCalories = explicitCalories;
    } else {
      // Standard MET estimate for resistance / strength training: ~5.0 MET
      // Formula: kcal = MET * weight_kg * (duration_minutes / 60)
      final weight = userWeightKg != null && userWeightKg > 20 ? userWeightKg : 75.0;
      final minutes = duration.inMinutes > 0 ? duration.inMinutes : (sets.isNotEmpty ? sets.length * 2 : 1);
      final estimated = (5.0 * weight * (minutes / 60.0)).round();
      finalCalories = sets.isNotEmpty ? estimated.clamp(10, 3000) : 0;
    }

    final ranked = muscleSets.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return SessionSummary(
      sessionId: sessionId,
      name: name,
      startedAt: startedAt,
      duration: duration,
      totalSets: sets.length,
      totalReps: reps,
      tonnageKg: tonnage,
      exerciseCount: exerciseIds.length,
      muscleGroups: [for (final e in ranked.take(4)) e.key],
      achievements: achievements,
      photoPath: photoPath,
      caloriesBurned: finalCalories,
    );
  }

  /// `1h 12m` / `48m` — never a bare `0h`.
  String get durationLabel {
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60);
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  /// Tonnes above 1 t, kilograms below, matching the dashboard's formatting.
  /// Non-finite guard for the same reason as `WeightFormat.formatTonnage`:
  /// `round()` throws on NaN, and this is read from a `build()`.
  String get tonnageLabel => !tonnageKg.isFinite
      ? '0 kg'
      : tonnageKg >= 1000
          ? '${(tonnageKg / 1000).toStringAsFixed(1)} t'
          : '${tonnageKg.round()} kg';

  /// Format calories burned.
  String get caloriesLabel => '$caloriesBurned kcal';
}
