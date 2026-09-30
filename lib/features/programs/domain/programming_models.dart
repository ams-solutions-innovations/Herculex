/// Public vocabulary shared by the program builder, generation engine and
/// active workout snapshot. Persist enum [id] values, never enum indexes.
library;

import 'package:herculex/features/programs/domain/rotation_policy.dart';
import 'package:herculex/features/programs/domain/slot_prescription.dart';
import 'package:herculex/features/programs/domain/slot_role.dart';

enum ProgramBuildMode {
  smart('smart', 'Build it for me'),
  guided('guided', 'Guide me'),
  manual('manual', 'Start from scratch'),
  herculexAi('herculex_ai', 'Herculex AI');

  const ProgramBuildMode(this.id, this.label);
  final String id;
  final String label;

  static ProgramBuildMode fromId(String? id) => values.firstWhere(
    (value) => value.id == id,
    orElse: () => ProgramBuildMode.guided,
  );
}

enum TrainingGoal {
  hypertrophy('hypertrophy', 'Hypertrophy'),
  strength('strength', 'Strength'),
  powerbuilding('powerbuilding', 'Powerbuilding'),
  athletic('athletic', 'Athletic performance');

  const TrainingGoal(this.id, this.label);
  final String id;
  final String label;

  static TrainingGoal fromId(String? id) => values.firstWhere(
    (value) => value.id == id,
    orElse: () => TrainingGoal.hypertrophy,
  );
}

enum ExperienceLevel {
  novice('novice', 'Novice'),
  intermediate('intermediate', 'Intermediate'),
  advanced('advanced', 'Advanced');

  const ExperienceLevel(this.id, this.label);
  final String id;
  final String label;

  static ExperienceLevel fromId(String? id) => values.firstWhere(
    (value) => value.id == id,
    orElse: () => ExperienceLevel.novice,
  );

  /// Conservative, explainable recommendation. A photo is deliberately not an
  /// input: visible muscularity cannot establish training competence.
  static ExperienceRecommendation recommend({
    required int consistentTrainingMonths,
    required int sessionsLast12Weeks,
    required bool understandsRirRpe,
    required bool hasRunStructuredBlocks,
  }) {
    if (consistentTrainingMonths < 6 || sessionsLast12Weeks < 24) {
      return const ExperienceRecommendation(
        level: ExperienceLevel.novice,
        confidence: 0.85,
        reason: 'Less than six consistent months or 24 recent sessions.',
      );
    }
    if (consistentTrainingMonths >= 36 &&
        sessionsLast12Weeks >= 30 &&
        understandsRirRpe &&
        hasRunStructuredBlocks) {
      return const ExperienceRecommendation(
        level: ExperienceLevel.advanced,
        confidence: 0.9,
        reason: 'Three years of consistent training with structured blocks.',
      );
    }
    return const ExperienceRecommendation(
      level: ExperienceLevel.intermediate,
      confidence: 0.8,
      reason: 'Established training history without all advanced criteria.',
    );
  }
}

/// The exercise vocabulary selected for a Smart program. Values are persisted
/// by id at the builder boundary; [allowedCatalogStyles] is the curated
/// catalogue vocabulary used by the eligibility policy.
///
/// `fullBody2xGpp` keeps the strength work inside ordinary weight/basic
/// movements and can ask the planner for a low-complexity conditioning
/// finish. It does not imply advanced CrossFit skills or a high-fatigue WOD.
enum TrainingStyle {
  weightlifting('weightlifting', 'Weightlifting', {'weightlifting'}),
  calisthenics('calisthenics', 'Calisthenics', {'calisthenics'}),
  basic('basic', 'Basic equipment only', {'basic'}),
  crossfit('crossfit', 'CrossFit', {'crossfit'}),
  mixedCalisthenicsWeights(
    'mixed_calisthenics_weights',
    'Calisthenics + weights',
    {'calisthenics', 'weightlifting'},
  ),
  fullBody2xGpp('full_body_2x_gpp', 'Full body 2× + GPP', {
    'weightlifting',
    'basic',
  });

  const TrainingStyle(this.id, this.label, this.allowedCatalogStyles);
  final String id;
  final String label;
  final Set<String> allowedCatalogStyles;

  static TrainingStyle fromId(String? id) => values.firstWhere(
    (value) => value.id == id,
    orElse: () => TrainingStyle.weightlifting,
  );

  /// Whether this style normally adds a conservative GPP conditioning finish
  /// to a Full Body A/B session. A caller may still explicitly opt out through
  /// [SmartProgramConfiguration.includeGppConditioning].
  bool get includesGppConditioning => this == TrainingStyle.fullBody2xGpp;

  /// The first CrossFit slice is conditioning-first. Exercise selection still
  /// passes the same experience and technical-curation safety gates.
  bool get isConditioningFirst => this == TrainingStyle.crossfit;
}

class ExperienceRecommendation {
  const ExperienceRecommendation({
    required this.level,
    required this.confidence,
    required this.reason,
  });

  final ExperienceLevel level;
  final double confidence;
  final String reason;
}

enum DayStressRole {
  intensity('intensity', 'Intensity'),
  volume('volume', 'Volume'),
  dynamicTechnique('dynamic_technique', 'Dynamic / Technique'),
  mixed('mixed', 'Mixed');

  const DayStressRole(this.id, this.label);
  final String id;
  final String label;

  static DayStressRole fromId(String? id) => values.firstWhere(
    (value) => value.id == id,
    orElse: () => DayStressRole.mixed,
  );
}

/// How explicit user-selected muscle priorities behave across a block.
/// This is deliberately separate from periodization: Concurrent can keep all
/// qualities present while the emphasis moves between selected muscles.
enum MuscleFocusWave {
  steady('steady', 'Keep focus every week'),
  alternating('alternating', 'Alternate focus by week');

  const MuscleFocusWave(this.id, this.label);
  final String id;
  final String label;
}

enum ExerciseAffinity {
  never('never', -1, 'Never'),
  okay('okay', 0, 'Okay'),
  liked('liked', 1, 'Like'),
  core('core', 2, 'Core lift');

  const ExerciseAffinity(this.id, this.score, this.label);
  final String id;
  final int score;
  final String label;

  static ExerciseAffinity fromScore(int score) => values.firstWhere(
    (value) => value.score == score,
    orElse: () => ExerciseAffinity.okay,
  );

  static ExerciseAffinity fromId(String? id) => values.firstWhere(
    (value) => value.id == id,
    orElse: () => ExerciseAffinity.okay,
  );
}

enum SlotTrainingMethod {
  auto('auto', 'Auto'),
  straightSets('straight_sets', 'Straight Sets'),
  doubleProgression('double_progression', 'Double Progression'),
  topSetBackoff('top_set_backoff', 'Top Set + Back-Off'),
  volumeWave('volume_wave', 'Volume Wave'),
  maxEffort('max_effort', 'Max Effort'),
  dynamicEffort('dynamic_effort', 'Dynamic Effort'),
  repetition('repetition', 'Repetition Method'),
  technique('technique', 'Technique / Tempo');

  const SlotTrainingMethod(this.id, this.label);
  final String id;
  final String label;

  bool get isHighIntensity => this == maxEffort || this == topSetBackoff;

  static SlotTrainingMethod fromId(String? id) => values.firstWhere(
    (value) => value.id == id,
    orElse: () => SlotTrainingMethod.auto,
  );
}

enum AdaptationMode {
  automaticNumeric('automatic_numeric'),
  reviewStructural('review_structural'),
  locked('locked');

  const AdaptationMode(this.id);
  final String id;
}

enum RotationAssignmentSource {
  planned('planned'),
  drifted('drifted'),
  manual('manual');

  const RotationAssignmentSource(this.id);
  final String id;
}

enum MaxEffortEligibility {
  eligible('suitable'),
  advancedOnly('advanced_manual'),
  ineligible('unsuitable');

  const MaxEffortEligibility(this.id);
  final String id;

  static MaxEffortEligibility fromId(String? id) => values.firstWhere(
    (value) => value.id == id,
    orElse: () => MaxEffortEligibility.ineligible,
  );
}

/// The progression contract attached to a generated slot. The selected
/// training method controls the session shape; this value controls what may
/// change after performance data arrives.
enum ProgressionRule {
  linearLoad('linear_load', 'Linear load'),
  doubleProgression('double_progression', 'Double progression'),
  topSetBackoff('top_set_backoff', 'Top set + back-off'),
  volumeWave('volume_wave', 'Volume wave'),
  variationPr('variation_pr', 'Variation PR'),
  dynamicQuality('dynamic_quality', 'Dynamic quality'),
  manual('manual', 'Manual');

  const ProgressionRule(this.id, this.label);
  final String id;
  final String label;

  static ProgressionRule fromId(String? id) => values.firstWhere(
    (value) => value.id == id,
    orElse: () => ProgressionRule.manual,
  );
}

/// Domain representation of one stable slot in a generated program. Database
/// rows store this in normalized form; this object is used by previews and
/// planners before persistence.
class ProgramExerciseSlot {
  const ProgramExerciseSlot({
    required this.key,
    required this.daySlotLabel,
    required this.orderIndex,
    required this.role,
    required this.candidateExerciseIds,
    required this.method,
    required this.progression,
    required this.prescription,
    required this.rotationPolicy,
    required this.fatigueBudget,
    this.movementPattern,
    this.primaryMuscle,
    this.userLocked = false,
    this.waveOverrideWeeks,
  });

  final String key;
  final String daySlotLabel;
  final int orderIndex;
  final SlotRole role;
  final String? movementPattern;
  final String? primaryMuscle;
  final List<int> candidateExerciseIds;
  final SlotTrainingMethod method;
  final ProgressionRule progression;
  final SlotPrescription prescription;
  final RotationPolicy rotationPolicy;
  final int fatigueBudget;
  final bool userLocked;
  final int? waveOverrideWeeks;
}
