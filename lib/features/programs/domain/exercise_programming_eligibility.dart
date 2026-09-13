/// Deterministic hard gate for automatically generated program exercises.
///
/// It deliberately has no scoring or fallback behavior. A missing or invalid
/// metadata value is interpreted as the conservative value, so a legacy or
/// custom movement cannot enter an automatic plan before it has been curated.
library;

import 'dart:convert';

import 'package:herculex/features/programs/domain/programming_models.dart';

class ExerciseProgrammingEligibility {
  const ExerciseProgrammingEligibility._();

  static bool allows({
    required ExperienceLevel experience,
    required TrainingStyle style,
    required String? difficulty,
    required String? commonness,
    required String? allowedTrainingStylesJson,
    required String? technicalEligibility,
    String? modality,
    String? requiredEquipmentKeysJson,
  }) {
    final resolvedDifficulty = _difficulty(difficulty);
    if (_difficultyRank(resolvedDifficulty) > _experienceRank(experience)) {
      return false;
    }

    final resolvedTechnicalEligibility = _technicalEligibility(
      technicalEligibility,
    );
    // Manual-only work is available through explicit exercise selection, but
    // it is never silently inserted by Smart Program Builder.
    if (resolvedTechnicalEligibility == 'manual_only') return false;
    // A technical-review movement has already been curated, but programming
    // it for a novice would still be an unsafe silent escalation.
    if (resolvedTechnicalEligibility == 'technical_review' &&
        experience == ExperienceLevel.novice) {
      return false;
    }

    final resolvedCommonness = _commonness(commonness);
    if (resolvedCommonness == 'manualOnly') return false;

    if (style == TrainingStyle.basic) {
      if (resolvedCommonness != 'basic' && resolvedCommonness != 'common') {
        return false;
      }

      if (modality != null) {
        const allowedBasicModalities = {
          'barbell',
          'dumbbell',
          'cable',
          'machine_plate',
          'machine_selectorized',
          'bodyweight',
        };
        if (!allowedBasicModalities.contains(modality)) return false;
      }

      if (requiredEquipmentKeysJson != null) {
        const barredEquipmentKeys = {
          'safety_squat_bar',
          'swiss_bar',
          'cambered_bar',
          'axle_bar',
          'trap_bar',
          'duffalo_bar',
          'chains',
          'reverse_hyper',
          'ghr',
          'belt_squat',
        };
        final equipmentKeys = _equipmentKeys(requiredEquipmentKeysJson);
        if (equipmentKeys.any(barredEquipmentKeys.contains)) return false;
      }
    }

    final styles = _styles(allowedTrainingStylesJson);
    return styles.any(style.allowedCatalogStyles.contains);
  }

  static String _difficulty(String? value) => switch (value) {
    'novice' || 'intermediate' || 'advanced' => value!,
    _ => 'advanced',
  };

  static int _difficultyRank(String value) => switch (value) {
    'novice' => 0,
    'intermediate' => 1,
    _ => 2,
  };

  static int _experienceRank(ExperienceLevel value) => switch (value) {
    ExperienceLevel.novice => 0,
    ExperienceLevel.intermediate => 1,
    ExperienceLevel.advanced => 2,
  };

  static String _commonness(String? value) => switch (value) {
    'basic' || 'common' || 'specialty' || 'manualOnly' => value!,
    _ => 'manualOnly',
  };

  static String _technicalEligibility(String? value) => switch (value) {
    'automatic' || 'technical_review' || 'manual_only' => value!,
    _ => 'manual_only',
  };

  static Set<String> _styles(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const {};
      return decoded.whereType<String>().toSet();
    } on FormatException {
      return const {};
    }
  }

  static Set<String> _equipmentKeys(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const {};
      return decoded.whereType<String>().toSet();
    } on FormatException {
      return const {};
    }
  }
}
