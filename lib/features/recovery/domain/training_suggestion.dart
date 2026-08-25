// lib/features/recovery/domain/training_suggestion.dart
import '../../analytics/domain/muscle_recovery_v3.dart';
import 'deload_urgency.dart';
import 'joint_model.dart';
import 'joint_stress_advisor.dart';
import 'muscle_deload_advisor.dart';

enum MuscleCategory { push, pull, legs, core }

/// A push/pull/legs/core tag for each of the 19 [MuscleRecoveryV3.groups] —
/// a different, coarser split than [MuscleRecoveryV3.alias] (which folds
/// source-dataset names onto the 19 canonical groups); this one buckets the
/// canonical groups themselves into trainable categories for the next workout, the same
/// PPL split implied elsewhere by `Programs.splitType`.
abstract final class MuscleCategories {
  static const byMuscle = <String, MuscleCategory>{
    'Chest': MuscleCategory.push,
    'Front Delts': MuscleCategory.push,
    'Side Delts': MuscleCategory.push,
    'Triceps': MuscleCategory.push,
    'Back': MuscleCategory.pull,
    'Lats': MuscleCategory.pull,
    'Traps': MuscleCategory.pull,
    'Rear Delts': MuscleCategory.pull,
    'Biceps': MuscleCategory.pull,
    'Forearms': MuscleCategory.pull,
    'Quads': MuscleCategory.legs,
    'Hamstrings': MuscleCategory.legs,
    'Glutes': MuscleCategory.legs,
    'Calves': MuscleCategory.legs,
    'Adductors': MuscleCategory.legs,
    'Abductors': MuscleCategory.legs,
    'Abs': MuscleCategory.core,
    'Obliques': MuscleCategory.core,
    'Neck': MuscleCategory.core,
  };
}

class TrainingSuggestion {
  final MuscleCategory bestCategory;

  /// Muscles in [bestCategory] at or above the trainable threshold and not
  /// excluded, best-recovered first.
  final List<String> readyMuscles;

  final List<String> excludedDeload;
  final List<String> excludedJointPain;
  final double categoryReadinessScore;
  final Map<MuscleCategory, double> allCategoryScores;

  const TrainingSuggestion({
    required this.bestCategory,
    required this.readyMuscles,
    required this.excludedDeload,
    required this.excludedJointPain,
    required this.categoryReadinessScore,
    required this.allCategoryScores,
  });
}

/// "What's best to train next" — ranks the push/pull/legs/core categories by
/// average recovery and picks the readiest one that still has at least one
/// trainable muscle, after excluding anything flagged for deload or loading
/// a flagged, over-threshold joint.
abstract final class TrainingSuggestionEngine {
  /// Looser than [MuscleRecoveryV3.recoveredScoreThreshold] (70): a same-day
  /// suggestion that only ever fires on fully-fresh muscles would go empty
  /// under any normal training cadence. 50 means "not still deeply
  /// fatigued" — a different, looser question than the RECOVERED badge asks.
  static const _trainableThreshold = 50;

  /// A muscle is excluded from the next workout when it's a meaningfully (>=0.5
  /// weight) contributing muscle to a joint that's currently flagged and
  /// over its stress threshold.
  static const _jointExclusionWeight = 0.5;

  static TrainingSuggestion suggest({
    required List<MuscleGroupRecovery> recovery,
    required List<MuscleDeloadSignal> deloadSignals,
    required List<JointStressResult> jointStress,
  }) {
    final deloadByMuscle = {for (final s in deloadSignals) s.muscle: s.urgency};

    final jointExcluded = <String>{
      for (final js in jointStress)
        if (js.urgency != DeloadUrgency.none)
          for (final entry in (JointModel.influencingMuscles[js.joint] ?? const {}).entries)
            if (entry.value >= _jointExclusionWeight) entry.key,
    };

    final byCategory = {for (final c in MuscleCategory.values) c: <MuscleGroupRecovery>[]};
    for (final r in recovery) {
      final category = MuscleCategories.byMuscle[r.muscle];
      if (category != null) byCategory[category]!.add(r);
    }

    final categoryScores = {
      for (final c in MuscleCategory.values)
        c: byCategory[c]!.isEmpty
            ? 0.0
            : byCategory[c]!.fold(0.0, (s, r) => s + r.recoveryScore) / byCategory[c]!.length,
    };

    bool usable(MuscleGroupRecovery r) =>
        deloadByMuscle[r.muscle] != DeloadUrgency.recommended && !jointExcluded.contains(r.muscle);

    final ranked = MuscleCategory.values.toList()
      ..sort((a, b) => categoryScores[b]!.compareTo(categoryScores[a]!));
    final best = ranked.firstWhere(
      (c) => byCategory[c]!.any(usable),
      orElse: () => ranked.first,
    );

    final inCategory = byCategory[best]!;
    final scoreByMuscle = {for (final r in inCategory) r.muscle: r.recoveryScore};
    final ready = inCategory
        .where((r) => r.recoveryScore >= _trainableThreshold && usable(r))
        .map((r) => r.muscle)
        .toList()
      ..sort((a, b) => scoreByMuscle[b]!.compareTo(scoreByMuscle[a]!));

    return TrainingSuggestion(
      bestCategory: best,
      readyMuscles: ready,
      excludedDeload: inCategory
          .where((r) => deloadByMuscle[r.muscle] == DeloadUrgency.recommended)
          .map((r) => r.muscle)
          .toList(),
      excludedJointPain:
          inCategory.where((r) => jointExcluded.contains(r.muscle)).map((r) => r.muscle).toList(),
      categoryReadinessScore: categoryScores[best]!,
      allCategoryScores: categoryScores,
    );
  }
}
