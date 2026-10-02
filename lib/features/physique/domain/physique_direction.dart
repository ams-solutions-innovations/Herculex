import 'package:herculex/features/nutrition/domain/diet_phase.dart';

/// The deterministic direction decision and the reasons shown for it.
class PhysiqueDirectionDecision {
  const PhysiqueDirectionDecision({required this.phase, required this.reasons});

  final DietPhase phase;
  final List<String> reasons;
}

/// Shared direction rule: used by the legacy recommender card and by the
/// roadmap generator, so both always agree on the first phase.
abstract final class PhysiqueDirectionRule {
  static PhysiqueDirectionDecision? decide({
    required double weightKg,
    required double currentBfPercent,
    required double targetBfPercent,
    required double plannedWeightChangeKg,
    required bool prefersWeightLoss,
  }) {
    if (weightKg <= 0 ||
        currentBfPercent <= 0 ||
        currentBfPercent >= 70 ||
        targetBfPercent <= 0 ||
        targetBfPercent >= 70) {
      return null;
    }

    final bfGap = currentBfPercent - targetBfPercent;
    final plannedWeightChange = plannedWeightChangeKg;
    final absChange = plannedWeightChange.abs();

    if (bfGap >= 5 || (prefersWeightLoss && bfGap >= 2)) {
      return PhysiqueDirectionDecision(
        phase: DietPhase.cut,
        reasons: [
          'Your saved estimate is ${bfGap.toStringAsFixed(0)} percentage points above the target.',
          'The Dream Physique roadmap estimates ${_weightChangeText(plannedWeightChange)}.',
        ],
      );
    }

    if (plannedWeightChange >= 6 && bfGap <= 2) {
      return PhysiqueDirectionDecision(
        phase: DietPhase.bulk,
        reasons: [
          'Your roadmap calls for a meaningful gain of ${plannedWeightChange.toStringAsFixed(1)} kg.',
          'Your saved body-fat estimate is already close to the target range.',
        ],
      );
    }

    if (bfGap >= 2 || absChange <= 3) {
      return PhysiqueDirectionDecision(
        phase: DietPhase.recomp,
        reasons: [
          bfGap >= 2
              ? 'Your current estimate is moderately above the target, so a slower transition may be easier to sustain.'
              : 'The roadmap calls for a relatively small scale-weight change.',
          'This keeps the next phase flexible while you review training and progress data.',
        ],
      );
    }

    return PhysiqueDirectionDecision(
      phase: DietPhase.maingain,
      reasons: [
        'Your saved estimate is close to the target range.',
        'The roadmap suggests ${_weightChangeText(plannedWeightChange)}, which fits a gradual gain phase.',
      ],
    );
  }

  static String _weightChangeText(double changeKg) {
    if (changeKg == 0) return 'little scale-weight change';
    final amount = changeKg.abs().toStringAsFixed(1);
    return changeKg > 0
        ? 'about $amount kg of gain'
        : 'about $amount kg of loss';
  }
}
