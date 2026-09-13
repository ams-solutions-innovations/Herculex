import 'dart:convert';

import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/programs/domain/exercise_programming_eligibility.dart';
import 'package:herculex/features/programs/domain/programming_models.dart';

class ScalingResolutionResult {
  const ScalingResolutionResult.success({
    required this.candidate,
    required this.rationale,
  }) : isSuccess = true;

  const ScalingResolutionResult.noSafeCandidate({
    required this.rationale,
  })  : candidate = null,
        isSuccess = false;

  final ExerciseCatalogData? candidate;
  final bool isSuccess;
  final String rationale;
}

/// Encapsulates ascending progressive regression ladder traversal.
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

    // Filter ladder candidates with strictly lower scalingOrder, sorted descending (highest regression first)
    final regressions = groupCandidates
        .where((e) =>
            e.scalingGroup == target.scalingGroup &&
            e.scalingOrder != null &&
            e.scalingOrder! < target.scalingOrder!)
        .toList()
      ..sort((a, b) => b.scalingOrder!.compareTo(a.scalingOrder!));

    for (final candidate in regressions) {
      // 1. Difficulty ceiling: Novices receive only novice movements
      final candDiff = candidate.programmingDifficulty;
      if (!_difficultySafe(candDiff, experience)) {
        continue;
      }

      // 2. Technical eligibility
      if (candidate.technicalEligibility == 'manual_only') continue;
      if (candidate.technicalEligibility == 'technical_review' &&
          experience == ExperienceLevel.novice) {
        continue;
      }

      // 3. Style, commonness & equipment constraints
      if (!ExerciseProgrammingEligibility.allows(
        experience: experience,
        style: style,
        difficulty: candidate.programmingDifficulty,
        commonness: candidate.programmingCommonness,
        allowedTrainingStylesJson: candidate.allowedTrainingStyles,
        technicalEligibility: candidate.technicalEligibility,
        modality: candidate.modality,
        requiredEquipmentKeysJson: candidate.requiredEquipmentKeys,
      )) {
        continue;
      }

      // 4. Equipment availability check
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

    // Strict group boundary enforcement (D-16): Never silently jump modalities or groups
    return ScalingResolutionResult.noSafeCandidate(
      rationale: 'No safe candidate found in scaling ladder "${target.scalingGroup}" '
          'matching available equipment and experience level.',
    );
  }

  static bool _difficultySafe(String? difficulty, ExperienceLevel experience) {
    final diffRank = switch (difficulty) {
      'novice' => 0,
      'intermediate' => 1,
      _ => 2,
    };
    final expRank = switch (experience) {
      ExperienceLevel.novice => 0,
      ExperienceLevel.intermediate => 1,
      ExperienceLevel.advanced => 2,
    };
    return diffRank <= expRank;
  }

  static bool _hasRequiredEquipment(
    ExerciseCatalogData exercise,
    Set<String> availableEquipmentKeys,
  ) {
    final raw = exercise.requiredEquipmentKeys;
    if (raw == null || raw.trim().isEmpty) return true;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return true;
      final required = decoded.whereType<String>().toSet();
      return required.every(availableEquipmentKeys.contains);
    } on FormatException {
      return false;
    }
  }
}
