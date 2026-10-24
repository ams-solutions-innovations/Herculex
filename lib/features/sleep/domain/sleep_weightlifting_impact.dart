// Physiological evaluation of sleep duration on strength training and CNS readiness.
// Pure Dart: no Flutter or Drift dependencies.

/// Readiness tier for weightlifting and high-intensity resistance training.
enum LiftingReadinessLevel { peak, normal, cautious, compromised }

/// Relative injury risk associated with neuromuscular fatigue and altered proprioception.
enum InjuryRiskLevel { low, moderate, elevated, high }

/// Detailed physiological impact profile of sleep on resistance training.
class SleepWeightliftingImpact {
  final LiftingReadinessLevel readinessLevel;
  final double volumeFactor;
  final int cnsReadinessPercent;
  final int strengthCapacityPercent;
  final double maxRecommendedRpe;
  final InjuryRiskLevel injuryRisk;
  final String statusBadge;
  final String headline;
  final String cnsExplanation;
  final String muscleRepairExplanation;
  final List<String> tacticalTips;

  const SleepWeightliftingImpact({
    required this.readinessLevel,
    required this.volumeFactor,
    required this.cnsReadinessPercent,
    required this.strengthCapacityPercent,
    required this.maxRecommendedRpe,
    required this.injuryRisk,
    required this.statusBadge,
    required this.headline,
    required this.cnsExplanation,
    required this.muscleRepairExplanation,
    required this.tacticalTips,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SleepWeightliftingImpact &&
          runtimeType == other.runtimeType &&
          readinessLevel == other.readinessLevel &&
          volumeFactor == other.volumeFactor &&
          cnsReadinessPercent == other.cnsReadinessPercent &&
          strengthCapacityPercent == other.strengthCapacityPercent &&
          maxRecommendedRpe == other.maxRecommendedRpe &&
          injuryRisk == other.injuryRisk &&
          statusBadge == other.statusBadge &&
          headline == other.headline &&
          cnsExplanation == other.cnsExplanation &&
          muscleRepairExplanation == other.muscleRepairExplanation;

  @override
  int get hashCode => Object.hash(
    readinessLevel,
    volumeFactor,
    cnsReadinessPercent,
    strengthCapacityPercent,
    maxRecommendedRpe,
    injuryRisk,
    statusBadge,
    headline,
    cnsExplanation,
    muscleRepairExplanation,
  );

  @override
  String toString() =>
      'SleepWeightliftingImpact(readiness: ${readinessLevel.name}, CNS: $cnsReadinessPercent%, badge: "$statusBadge")';
}

/// Evaluation engine translating nightly sleep telemetry into weightlifting adjustments.
class SleepWeightliftingEngine {
  const SleepWeightliftingEngine._();

  /// Evaluates sleep metrics to produce actionable strength training adjustments.
  static SleepWeightliftingImpact evaluate({
    required double sleepHours,
    double? deepSleepHours,
    double? remSleepHours,
    double? sleepDebt,
    double? restingHr,
  }) {
    final effectiveDebt = sleepDebt ?? 0.0;

    // Peak: 8.0+ hours, minimal debt
    if (sleepHours >= 8.0 && effectiveDebt <= 1.0) {
      return _buildPeakImpact(restingHr: restingHr);
    }

    // Normal: 7.0 - 7.9 hours, or 8+ with moderate accumulated debt
    if (sleepHours >= 7.0 && effectiveDebt <= 2.0) {
      return _buildNormalImpact(restingHr: restingHr);
    }

    // Cautious: 5.5 - 6.9 hours, or significant debt
    if (sleepHours >= 5.5) {
      return _buildCautiousImpact(
        sleepHours: sleepHours,
        deepHours: deepSleepHours,
        restingHr: restingHr,
      );
    }

    // Compromised: < 5.5 hours
    return _buildCompromisedImpact(
      sleepHours: sleepHours,
      restingHr: restingHr,
    );
  }

  static SleepWeightliftingImpact _buildPeakImpact({double? restingHr}) {
    final tips = [
      'Capitalize on peak CNS readiness: prioritize primary compound lifts and heavy working sets early in the workout.',
      'Working sets up to RPE 9.0-9.5 (1 RIR) are cleared for top compound lifts.',
      'Full programmed volume is recommended; consider adding a high-yield accessory set if feeling primed.',
      'Maintain standard 3-5 minute inter-set rest intervals on compound lifts.',
    ];

    if (restingHr != null && restingHr > 75.0) {
      tips.add(
        'Resting HR is slightly elevated; extend movement-specific warmups by 2 minutes.',
      );
    }

    return SleepWeightliftingImpact(
      readinessLevel: LiftingReadinessLevel.peak,
      volumeFactor: 1.05,
      cnsReadinessPercent: 100,
      strengthCapacityPercent: 100,
      maxRecommendedRpe: 9.5,
      injuryRisk: InjuryRiskLevel.low,
      statusBadge: 'FULL CAPACITY (100%)',
      headline: 'Peak Neuromuscular Drive & Maximal Output',
      cnsExplanation:
          'Complete slow-wave and REM sleep cycles restored cortical excitability and cleared accumulated adenosine. '
          'High-threshold motor unit recruitment, action potential rate coding, and neuromuscular synchronization are operating at peak efficiency.',
      muscleRepairExplanation:
          'Full-duration stage 3/4 NREM sleep triggered maximal nocturnal Human Growth Hormone (HGH) secretion pulses. '
          'Muscle protein synthesis (MPS) and myofibrillar repair are complete, fully restoring contractile tissue.',
      tacticalTips: tips,
    );
  }

  static SleepWeightliftingImpact _buildNormalImpact({double? restingHr}) {
    final tips = [
      'Execute programmed working sets and prescribed loads without modification.',
      'Dedicate 5-8 minutes to specific movement warmups to fully prime neuromuscular pathways.',
      'Cap top working sets at RPE 8.5-9.0 (1-2 RIR); avoid unplanned grinding sets to technical failure.',
      'Maintain consistent intra-workout hydration and electrolyte balance.',
    ];

    return SleepWeightliftingImpact(
      readinessLevel: LiftingReadinessLevel.normal,
      volumeFactor: 1.00,
      cnsReadinessPercent: 90,
      strengthCapacityPercent: 98,
      maxRecommendedRpe: 9.0,
      injuryRisk: InjuryRiskLevel.low,
      statusBadge: 'NORMAL CAPACITY (95%)',
      headline: 'Solid Training Capacity & Central Drive',
      cnsExplanation:
          'Sufficient acetylcholine and dopamine resynthesis supports baseline neural drive. '
          'Proprioceptive feedback and motor unit firing rates remain stable across conventional training intensities.',
      muscleRepairExplanation:
          'Adequate slow-wave sleep achieved baseline tissue turnover and glycogen replenishment. '
          'Muscular fatigue recovery is well within typical limits.',
      tacticalTips: tips,
    );
  }

  static SleepWeightliftingImpact _buildCautiousImpact({
    required double sleepHours,
    double? deepHours,
    double? restingHr,
  }) {
    final tips = [
      'Trim 1-2 accessory sets per exercise or drop back-off volume by 15-20%.',
      'Cap intensity strictly at RPE 8.0 (keep 2-3 reps in reserve) to protect the central nervous system.',
      'Extend rest intervals by 60-90 seconds between heavy compound sets to ensure complete phosphocreatine resynthesis.',
      'Consider cluster sets (short 15-20s intra-set pauses) to maintain movement velocity without accumulating excessive fatigue.',
    ];

    if (deepHours != null && deepHours < 0.75) {
      tips.add(
        'Deep sleep was below 45 minutes; be mindful of delayed core stabilizer engagement on squats/deadlifts.',
      );
    }

    return SleepWeightliftingImpact(
      readinessLevel: LiftingReadinessLevel.cautious,
      volumeFactor: 0.85,
      cnsReadinessPercent: 75,
      strengthCapacityPercent: 95,
      maxRecommendedRpe: 8.0,
      injuryRisk: InjuryRiskLevel.moderate,
      statusBadge: 'CNS DEFICIT - CUT VOLUME 15%',
      headline: 'Mild Central Fatigue - Autoregulate Volume',
      cnsExplanation:
          'Partial sleep restriction attenuates central drive and motor cortex excitability due to incomplete adenosine clearance. '
          'Rate of force development (RFD) is blunted, slowing peak barbell velocity by approximately 5-10%.',
      muscleRepairExplanation:
          'Truncated slow-wave duration lowered nighttime HGH secretion and elevated morning cortisol. '
          'Myofibrillar repair is incomplete, resulting in heightened perceived muscle soreness.',
      tacticalTips: tips,
    );
  }

  static SleepWeightliftingImpact _buildCompromisedImpact({
    required double sleepHours,
    double? restingHr,
  }) {
    final isCritical = sleepHours < 4.5;
    final tips = [
      'Avoid maximal 1-3RM attempts and ballistic compound lifts (heavy cleans, maximum deadlifts).',
      'Substitute free-weight axial loading with chest-supported machines or leg press to reduce lumbar strain.',
      'Reduce total working sets by 25-30% and leave at least 3-4 reps in reserve (max RPE 7.0-7.5).',
      'Prioritize mobility, gentle warmups, and post-workout nutrition over chasing volume.',
    ];

    return SleepWeightliftingImpact(
      readinessLevel: LiftingReadinessLevel.compromised,
      volumeFactor: 0.75,
      cnsReadinessPercent: 60,
      strengthCapacityPercent: 92,
      maxRecommendedRpe: 7.5,
      injuryRisk: isCritical ? InjuryRiskLevel.high : InjuryRiskLevel.elevated,
      statusBadge: 'CNS COMPROMISED - CUT VOLUME 25%',
      headline: 'Substantial Neuromuscular Impairment - Deload Advised',
      cnsExplanation:
          'Substantial sleep deprivation impairs neural conduction velocity, blunts high-threshold motor unit recruitment, and slows motor reaction times. '
          'Dynamic spinal stabilization and proprioception under heavy axial load are severely compromised.',
      muscleRepairExplanation:
          'Suppressed nocturnal anabolism and elevated systemic catabolic markers elevate tissue vulnerability. '
          'Risk of micro-trauma exceeding the physiological recovery threshold is significantly heightened.',
      tacticalTips: tips,
    );
  }
}
