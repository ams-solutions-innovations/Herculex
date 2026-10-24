import 'package:herculex/data/local/database.dart';
import 'package:herculex/data/local/exercise_biomechanics.dart';

class ExerciseSubstitution {
  /// Synergistic muscle groups that can cross-substitute ONLY in compound movements.
  static const Map<String, Set<String>> _compoundSynergies = {
    'Chest': {'Shoulders', 'Triceps'},
    'Shoulders': {'Chest', 'Triceps'},
    'Triceps': {'Chest', 'Shoulders'},
    'Back': {'Biceps', 'Rear Delts', 'Forearms', 'Traps'},
    'Biceps': {'Back', 'Forearms'},
    'Quads': {'Glutes', 'Adductors', 'Calves'},
    'Glutes': {'Hamstrings', 'Quads'},
    'Hamstrings': {'Glutes', 'Calves', 'Erectors'},
  };

  /// Calculates the matching score between an [original] exercise and a [candidate].
  /// Returns a Map containing:
  /// - 'score': the total score used for sorting (including history boost)
  /// - 'percentage': the base biomechanical match percentage (0 to 100)
  /// - 'isHistoryMatch': whether the user has recently performed this exercise
  static Map<String, dynamic> calculateMatch({
    required ExerciseCatalogData original,
    required ExerciseCatalogData candidate,
    required Set<int> recentExerciseIds,
  }) {
    if (original.id == candidate.id) {
      return {'score': 0.0, 'percentage': 0.0, 'isHistoryMatch': false};
    }

    final origCoarse = ExerciseBiomechanics.coarseMuscle(
      original.primaryMuscle,
    );
    final candCoarse = ExerciseBiomechanics.coarseMuscle(
      candidate.primaryMuscle,
    );

    final isSameExactMuscle =
        original.primaryMuscle.toLowerCase() ==
        candidate.primaryMuscle.toLowerCase();
    final isSameCoarseMuscle =
        origCoarse.toLowerCase() == candCoarse.toLowerCase();

    final origIsCompound = original.mechanics.toLowerCase() == 'compound';
    final candIsCompound = candidate.mechanics.toLowerCase() == 'compound';
    final isPushPullMatch =
        original.force.toLowerCase() == candidate.force.toLowerCase();

    // Strict muscle compatibility check:
    // If coarse muscle does not match, check if cross-muscle synergy is valid
    if (!isSameCoarseMuscle) {
      // Cross-muscle substitution is ONLY allowed for compound movements with matching force and documented synergy
      final hasSynergy =
          _compoundSynergies[origCoarse]?.contains(candCoarse) == true;

      if (!origIsCompound ||
          !candIsCompound ||
          !isPushPullMatch ||
          !hasSynergy) {
        // Complete mismatch (e.g. Quads for Chest, or isolation cross-muscle) -> DISQUALIFIED
        return {'score': 0.0, 'percentage': 0.0, 'isHistoryMatch': false};
      }
    }

    // Strict force vector check for isolation movements
    if (!origIsCompound && !isPushPullMatch) {
      return {'score': 0.0, 'percentage': 0.0, 'isHistoryMatch': false};
    }

    double baseScore = 0.0;

    // A. Target Muscle Match (Up to 50 points)
    if (isSameExactMuscle) {
      baseScore += 50.0;
    } else if (isSameCoarseMuscle) {
      baseScore += 45.0;
    } else {
      // Synergistic compound muscle (e.g. Dips for Close-Grip Bench)
      baseScore += 20.0;
    }

    // B. Movement Slug / Family / Pattern (Up to 25 points)
    if (original.movementSlug != null &&
        candidate.movementSlug != null &&
        original.movementSlug == candidate.movementSlug) {
      baseScore += 25.0;
    } else if (original.movementFamily != null &&
        candidate.movementFamily != null &&
        original.movementFamily == candidate.movementFamily) {
      baseScore += 20.0;
    } else if (original.movementPattern != null &&
        candidate.movementPattern != null &&
        original.movementPattern == candidate.movementPattern) {
      baseScore += 15.0;
    }

    // C. Mechanics Match (Compound vs Isolation) (Up to 15 points)
    if (original.mechanics.toLowerCase() == candidate.mechanics.toLowerCase()) {
      baseScore += 15.0;
    } else {
      baseScore += 5.0;
    }

    // D. Force & Movement Plane (Up to 10 points)
    if (isPushPullMatch) {
      baseScore += 5.0;
    }
    if (original.plane.toLowerCase() == candidate.plane.toLowerCase() &&
        original.plane.toLowerCase() != 'none') {
      baseScore += 5.0;
    }

    final isHistoryMatch = recentExerciseIds.contains(candidate.id);
    // Subtle +4.0 ranking boost for history, breaking ties among genuine matches
    final totalScore = baseScore + (isHistoryMatch ? 4.0 : 0.0);

    return {
      'score': totalScore,
      'percentage': baseScore.clamp(0.0, 100.0),
      'isHistoryMatch': isHistoryMatch,
    };
  }

  /// Takes the original exercise, a list of all candidates from the catalog,
  /// and the user's recent exercise history, returning a list of ranked substitute candidates.
  static List<RankedSubstitution> getRankedSubstitutes({
    required ExerciseCatalogData original,
    required List<ExerciseCatalogData> candidates,
    required Set<int> recentExerciseIds,
  }) {
    final List<RankedSubstitution> results = [];

    for (final candidate in candidates) {
      if (candidate.id == original.id) continue;

      final match = calculateMatch(
        original: original,
        candidate: candidate,
        recentExerciseIds: recentExerciseIds,
      );

      final double score = match['score'] as double;
      final double percentage = match['percentage'] as double;
      final bool isHistoryMatch = match['isHistoryMatch'] as bool;

      // Only include candidates that have genuine biomechanical relevance
      if (score > 0 && percentage >= 20.0) {
        results.add(
          RankedSubstitution(
            exercise: candidate,
            score: score,
            percentage: percentage.round(),
            isHistoryMatch: isHistoryMatch,
          ),
        );
      }
    }

    // Sort descending by score (highest match & recently performed first)
    results.sort((a, b) => b.score.compareTo(a.score));
    return results;
  }

  /// Returns substitutes for [original] filtered by a free-text [query].
  ///
  /// With an empty query only biomechanically relevant candidates are
  /// returned (same as [getRankedSubstitutes]). With a non-empty query the
  /// biomechanical matches that satisfy the query come first (still ranked by
  /// score), followed by **every other** catalog exercise matching the query,
  /// regardless of biomechanical similarity. Those extra results carry a
  /// `percentage` of 0 (see [RankedSubstitution.isBiomechanicalMatch]).
  static List<RankedSubstitution> searchSubstitutes({
    required ExerciseCatalogData original,
    required List<ExerciseCatalogData> candidates,
    required Set<int> recentExerciseIds,
    required String query,
  }) {
    final ranked = getRankedSubstitutes(
      original: original,
      candidates: candidates,
      recentExerciseIds: recentExerciseIds,
    );
    final tokens = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return ranked;

    bool matchesQuery(ExerciseCatalogData e) {
      final haystack = '${e.name} ${e.primaryMuscle} ${e.equipment}'
          .toLowerCase();
      return tokens.every(haystack.contains);
    }

    final rankedMatches = ranked
        .where((m) => matchesQuery(m.exercise))
        .toList();
    final rankedIds = {for (final m in ranked) m.exercise.id};

    final needle = tokens.join(' ');
    int relevance(ExerciseCatalogData e) {
      final name = e.name.toLowerCase();
      if (name == needle) return 0;
      if (name.startsWith(needle)) return 1;
      if (name.contains(needle)) return 2;
      if (tokens.every(name.contains)) return 3;
      return 4; // matched only via muscle / equipment
    }

    final others =
        candidates
            .where(
              (e) =>
                  e.id != original.id &&
                  !rankedIds.contains(e.id) &&
                  matchesQuery(e),
            )
            .toList()
          ..sort((a, b) {
            final byRelevance = relevance(a).compareTo(relevance(b));
            if (byRelevance != 0) return byRelevance;
            final aRecent = recentExerciseIds.contains(a.id);
            final bRecent = recentExerciseIds.contains(b.id);
            if (aRecent != bRecent) return aRecent ? -1 : 1;
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });

    return [
      ...rankedMatches,
      for (final e in others)
        RankedSubstitution(
          exercise: e,
          score: 0,
          percentage: 0,
          isHistoryMatch: recentExerciseIds.contains(e.id),
        ),
    ];
  }
}

class RankedSubstitution {
  final ExerciseCatalogData exercise;
  final double score;
  final int percentage;
  final bool isHistoryMatch;

  const RankedSubstitution({
    required this.exercise,
    required this.score,
    required this.percentage,
    required this.isHistoryMatch,
  });

  /// False for search results that are not biomechanically similar to the
  /// original exercise (included only because they matched the search query).
  bool get isBiomechanicalMatch => percentage > 0;
}
