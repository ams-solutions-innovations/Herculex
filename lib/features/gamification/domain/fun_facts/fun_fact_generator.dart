import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/analytics/domain/muscle_recovery_v3.dart';
import 'package:herculex/features/analytics/domain/training_snapshot.dart';
import 'package:herculex/features/analytics/domain/weekly_muscle_volume.dart';
import 'package:herculex/features/gamification/domain/fun_facts/weight_equivalents.dart';
import 'package:herculex/features/recovery/domain/training_suggestion.dart';

enum FunFactKind {
  /// One exercise's tonnage in today's sessions.
  todayExercise,

  /// The heaviest single set logged today.
  todayHeaviestSet,

  /// This week's tonnage in one push/pull/legs bucket.
  weekCategory,

  /// Everything since Monday.
  weekTotal,

  /// Everything ever logged.
  lifetime,
}

/// A real-world comparison for the profile card. The domain picks the numbers;
/// the widget words them, so units stay a presentation concern.
class FunFact {
  const FunFact({
    required this.kind,
    required this.kg,
    required this.comparison,
    this.subject,
    this.category,
  });

  final FunFactKind kind;

  /// Tonnage, or the set's load for [FunFactKind.todayHeaviestSet].
  final double kg;
  final WeightComparison comparison;

  /// Exercise name for the per-exercise kinds.
  final String? subject;
  final MuscleCategory? category;
}

/// Picks one fun fact from the training history, preferring fresh news:
/// today beats this week beats lifetime. Within a tier the choice rotates by
/// calendar day, so the card is stable across rebuilds and changes overnight.
class FunFactGenerator {
  const FunFactGenerator();

  /// Today's tonnage on one exercise must reach this before it is "news".
  static const _minTodayExerciseKg = 1500.0;

  /// Lighter single sets are not worth comparing to an animal.
  static const _minHeavySetKg = 100.0;
  static const _minWeekCategoryKg = 3000.0;

  FunFact? generate({
    required TrainingSnapshot snapshot,
    required DateTime asOf,
  }) {
    final dayStart = DateTime(asOf.year, asOf.month, asOf.day);
    final weekStart = WeeklyMuscleVolume.weekStartOf(asOf);

    final musclesByExercise = <int, List<ExerciseMuscleData>>{};
    for (final m in snapshot.exerciseMuscles) {
      musclesByExercise.putIfAbsent(m.exerciseId, () => []).add(m);
    }

    final todayByExercise = <String, double>{};
    var heaviestToday = 0.0;
    final weekByCategory = <MuscleCategory, double>{};
    var weekTotal = 0.0;
    var lifetime = 0.0;

    for (final rs in snapshot.sets) {
      final at = rs.set.completedAt ?? rs.session.startedAt;
      if (at.isAfter(asOf)) continue;
      final tonnage = rs.tonnageKg;
      lifetime += tonnage;
      if (at.isBefore(weekStart)) continue;

      weekTotal += tonnage;
      final category = _dominantCategory(rs, musclesByExercise);
      if (category != null) {
        weekByCategory[category] = (weekByCategory[category] ?? 0) + tonnage;
      }
      if (at.isBefore(dayStart)) continue;

      todayByExercise[rs.exercise.name] =
          (todayByExercise[rs.exercise.name] ?? 0) + tonnage;
      if (rs.metric.isRepBased && rs.countedReps > 0) {
        if (rs.effectiveKg > heaviestToday) heaviestToday = rs.effectiveKg;
      }
    }

    final today = <FunFact>[
      for (final MapEntry(key: name, value: kg) in todayByExercise.entries)
        if (kg >= _minTodayExerciseKg)
          ?_fact(
            FunFactKind.todayExercise,
            kg,
            tonnageEquivalents,
            subject: name,
          ),
      if (heaviestToday >= _minHeavySetKg)
        ?_fact(
          FunFactKind.todayHeaviestSet,
          heaviestToday,
          singleLiftEquivalents,
        ),
    ];
    final week = <FunFact>[
      for (final MapEntry(key: category, value: kg) in weekByCategory.entries)
        if (kg >= _minWeekCategoryKg && category != MuscleCategory.core)
          ?_fact(
            FunFactKind.weekCategory,
            kg,
            tonnageEquivalents,
            category: category,
          ),
      ?_fact(FunFactKind.weekTotal, weekTotal, tonnageEquivalents),
    ];
    final ever = <FunFact>[
      ?_fact(FunFactKind.lifetime, lifetime, tonnageEquivalents),
    ];

    final tier = today.isNotEmpty
        ? today
        : week.isNotEmpty
        ? week
        : ever;
    if (tier.isEmpty) return null;
    // Stable order before rotating, so map iteration order cannot leak in.
    tier.sort((a, b) {
      final byKg = b.kg.compareTo(a.kg);
      return byKg != 0 ? byKg : a.kind.index.compareTo(b.kind.index);
    });
    final dayIndex = dayStart.difference(DateTime(2000)).inDays;
    return tier[dayIndex % tier.length];
  }

  static FunFact? _fact(
    FunFactKind kind,
    double kg,
    List<WeightEquivalent> catalog, {
    String? subject,
    MuscleCategory? category,
  }) {
    final comparison = WeightComparison.pick(kg, catalog);
    if (comparison == null) return null;
    return FunFact(
      kind: kind,
      kg: kg,
      comparison: comparison,
      subject: subject,
      category: category,
    );
  }

  /// The push/pull/legs/core bucket that gets most of the set's work, so each
  /// set's tonnage is counted once.
  static MuscleCategory? _dominantCategory(
    ResolvedSet rs,
    Map<int, List<ExerciseMuscleData>> musclesByExercise,
  ) {
    final weights = <MuscleCategory, double>{};
    for (final (muscle, w) in MuscleRecoveryV3.involvementFor(
      rs,
      musclesByExercise,
    )) {
      final c = MuscleCategories.byMuscle[muscle];
      if (c != null) weights[c] = (weights[c] ?? 0) + w;
    }
    MuscleCategory? best;
    for (final MapEntry(key: c, value: w) in weights.entries) {
      if (best == null || w > weights[best]!) best = c;
    }
    return best;
  }
}
