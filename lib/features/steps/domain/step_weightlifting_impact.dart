// Calculates specific physiological and programming adaptations for strength training
// based on daily step volume, NEAT fatigue, and glycogen depletion.
// Pure Dart: no Flutter or Drift dependencies.

import 'package:herculex/features/steps/domain/step_score_engine.dart';

/// Comprehensive weightlifting impact report for a given step volume.
class StepWeightliftingImpact {
  final int steps;
  final StepActivityZone zone;
  final double lowerBodyVolumeFactor;
  final double upperBodyVolumeFactor;
  final int estimatedGlycogenDepletionPercent;
  final int recommendedIntraWorkoutCarbsGrams;
  final int workCapacityScore;
  final String workCapacityLabel;
  final String legDayTacticalTip;
  final String upperDayTacticalTip;
  final String systemicFatigueStatus;
  final double expectedRpeShift;

  const StepWeightliftingImpact({
    required this.steps,
    required this.zone,
    required this.lowerBodyVolumeFactor,
    required this.upperBodyVolumeFactor,
    required this.estimatedGlycogenDepletionPercent,
    required this.recommendedIntraWorkoutCarbsGrams,
    required this.workCapacityScore,
    required this.workCapacityLabel,
    required this.legDayTacticalTip,
    required this.upperDayTacticalTip,
    required this.systemicFatigueStatus,
    required this.expectedRpeShift,
  });
}

/// Evaluation engine converting step telemetry into gym programming guidance.
class StepWeightliftingEngine {
  const StepWeightliftingEngine._();

  /// Calculates gym adaptations based on [steps] recorded.
  static StepWeightliftingImpact calculate({required int steps}) {
    final zone = StepScoreEngine.determineZone(steps);

    double lowerFactor;
    double upperFactor;
    int glycogenDepletion;
    int carbsGrams;
    int workCapacity;
    String workCapacityLabel;
    String legTip;
    String upperTip;
    String systemicStatus;
    double rpeShift;

    switch (zone) {
      case StepActivityZone.sedentary:
        lowerFactor = 1.0;
        upperFactor = 1.0;
        glycogenDepletion = 10;
        carbsGrams = 0;
        workCapacity = 65;
        workCapacityLabel = 'Stiff / Sluggish';
        legTip =
            'Tight hip flexors and cold tendons. Dedicate 6-8 minutes to dynamic hip openers (90/90, pigeon) and perform 2 additional ramp-up sets before heavy squats.';
        upperTip =
            'Thoracic mobility may be restricted from sitting. Mobilize t-spine and lats before benching or overhead pressing.';
        systemicStatus = 'Low Neuromuscular Priming';
        rpeShift = 0.0;
        break;

      case StepActivityZone.lightlyActive:
        lowerFactor = 1.0;
        upperFactor = 1.0;
        glycogenDepletion = 20;
        carbsGrams = 0;
        workCapacity = 80;
        workCapacityLabel = 'Adequate Aerobic Base';
        legTip =
            'Normal warm-up is sufficient. Joints are lubricated and ready for full scheduled squat/deadlift loading.';
        upperTip =
            'Zero upper-body interference. Proceed with target weights and repetitions.';
        systemicStatus = 'Fresh / Fully Recovered';
        rpeShift = 0.0;
        break;

      case StepActivityZone.optimal:
        lowerFactor = 1.0;
        upperFactor = 1.0;
        glycogenDepletion = 35;
        carbsGrams = 15;
        workCapacity = 95;
        workCapacityLabel = 'Peak PCr Clearance';
        legTip =
            'Goldilocks zone! Active hyperemia enhances nutrient delivery to quads and glutes without neural fatigue. Prime for heavy compound lifts.';
        upperTip =
            'Peak systemic recovery. High aerobic work capacity allows for shorter rest intervals between sets (2-3 min).';
        systemicStatus = 'Peak Readiness';
        rpeShift = 0.0;
        break;

      case StepActivityZone.highNeat:
        lowerFactor = 0.90; // -10% volume on legs
        upperFactor = 1.0;
        glycogenDepletion = 55;
        carbsGrams = 30;
        workCapacity = 85;
        workCapacityLabel = 'Elevated NEAT Load';
        legTip =
            'Moderate axial and calf/hamstring fatigue. If legs feel heavy during squats, reduce back-off volume by 1 set. Take 30-40g carbs 40 min prior.';
        upperTip =
            'Upper body remains uncompromised. Full programmed volume recommended.';
        systemicStatus = 'Mild Peripheral Fatigue';
        rpeShift = 0.5;
        break;

      case StepActivityZone.exhaustive:
        lowerFactor = 0.80; // -20% volume on legs
        upperFactor = 0.95;
        glycogenDepletion = 75;
        carbsGrams = 45;
        workCapacity = 60;
        workCapacityLabel = 'Glycogen Depleted';
        legTip =
            'Substantial quadriceps and lumbar erector fatigue. Cap top sets at RPE 8.0 to protect form. Drop 2 accessory sets and sip intra-workout carbs.';
        upperTip =
            'Core stabilizers may be fatigued from continuous upright walking. Use a lifting belt on overhead presses.';
        systemicStatus = 'Significant Leg Fatigue';
        rpeShift = 1.0;
        break;

      case StepActivityZone.extreme:
        lowerFactor = 0.70; // -30% volume or rest
        upperFactor = 0.85;
        glycogenDepletion = 90;
        carbsGrams = 60;
        workCapacity = 45;
        workCapacityLabel = 'Exhausted Musculature';
        legTip =
            'Severe peripheral fatigue (25k+ steps). High risk of lumbar flexion under heavy axial loads. Strongly recommend converting today into an active recovery or upper-only day.';
        upperTip =
            'Focus on machines with chest or back support to unload the spine. Consume fast-acting carbohydrates immediately.';
        systemicStatus = 'High Injury Risk / Exhausted';
        rpeShift = 1.5;
        break;
    }

    return StepWeightliftingImpact(
      steps: steps,
      zone: zone,
      lowerBodyVolumeFactor: lowerFactor,
      upperBodyVolumeFactor: upperFactor,
      estimatedGlycogenDepletionPercent: glycogenDepletion,
      recommendedIntraWorkoutCarbsGrams: carbsGrams,
      workCapacityScore: workCapacity,
      workCapacityLabel: workCapacityLabel,
      legDayTacticalTip: legTip,
      upperDayTacticalTip: upperTip,
      systemicFatigueStatus: systemicStatus,
      expectedRpeShift: rpeShift,
    );
  }
}
