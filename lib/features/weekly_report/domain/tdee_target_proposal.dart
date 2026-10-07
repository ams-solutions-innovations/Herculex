/// The "Update my target to X kcal" proposal of the TDEE shift card (D-11).
///
/// OQ2 decision (user-confirmed 2026-10-03): X is a delta-preserving update of
/// the user's SAVED manual target rule, not "set the target to the new
/// maintenance":
///
///   X = saved rule kcal + (newEstimate - oldEstimate), rounded to 10 kcal
///
/// Protein and fat grams are kept and carbs absorb the remainder, and the
/// proposal keeps the rule's `appliesTo` scope.
///
/// Replacing the target with the new maintenance figure was rejected because
/// it would silently erase a deliberate cut or bulk the user chose, and it
/// would bypass the PHYS-04 eligibility gate (a restricted member could be
/// handed a surplus through the back door). The delta approach keeps the
/// user's chosen offset from maintenance and routes every increase through the
/// same clamps the target editor uses.
///
/// Pure Dart: no Flutter, Riverpod or drift.
library;

import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/nutrition/domain/phase_eligibility.dart';
import 'package:herculex/features/nutrition/domain/target_resolver.dart';

/// What [TdeeTargetProposalCalculator.compute] concluded.
enum TdeeProposalStatus {
  /// A usable proposal exists.
  proposed,

  /// The user has no saved manual rule; the baseline already follows the
  /// estimate (TDEE-04), so there is nothing to update.
  noSavedRule,

  /// The clamps leave the target where it is, or the result is unstorable.
  noChange,

  /// Protein and fat alone would use more than the proposed calories.
  belowMacroFloor,
}

/// A concrete replacement for the saved rule.
class TdeeTargetProposal {
  const TdeeTargetProposal({
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.appliesTo,
    this.fiberG,
  });

  final int kcal;
  final int proteinG;
  final int carbsG;
  final int fatG;
  final int? fiberG;
  final String appliesTo;
}

class TdeeTargetProposalResult {
  const TdeeTargetProposalResult(this.status, [this.proposal]);

  final TdeeProposalStatus status;

  /// Non-null only when [status] is [TdeeProposalStatus.proposed].
  final TdeeTargetProposal? proposal;
}

abstract final class TdeeTargetProposalCalculator {
  /// Range a decision kcal may be stored in; mirrors
  /// `WeeklyReportRepository.minDecisionKcal` / `maxDecisionKcal`, which would
  /// reject the decision after the target had already been written.
  static const int minStorableKcal = 800;
  static const int maxStorableKcal = 6000;

  static TdeeTargetProposalResult compute({
    required TargetRule? rule,
    required int oldEstimateKcal,
    required int newEstimateKcal,
    int? minCaloriesKcal,
    PhaseEligibility? eligibility,
  }) {
    if (rule == null) {
      return const TdeeTargetProposalResult(TdeeProposalStatus.noSavedRule);
    }

    var delta = newEstimateKcal - oldEstimateKcal;
    // PHYS-04: a restricted member never gets an unclamped increase. Maingain
    // is the surplus proxy the target editor uses.
    if (eligibility != null && eligibility.isRestricted && delta > 0) {
      delta = eligibility.clampDelta(DietPhase.maingain, delta);
    }
    if (delta == 0) {
      return const TdeeTargetProposalResult(TdeeProposalStatus.noChange);
    }

    var kcal = _roundToTen(rule.kcal + delta);
    if (minCaloriesKcal != null && kcal < minCaloriesKcal) {
      kcal = minCaloriesKcal;
    }
    if (kcal == rule.kcal || kcal < minStorableKcal || kcal > maxStorableKcal) {
      return const TdeeTargetProposalResult(TdeeProposalStatus.noChange);
    }

    final remainder = kcal - rule.proteinG * 4 - rule.fatG * 9;
    if (remainder < 0) {
      return const TdeeTargetProposalResult(TdeeProposalStatus.belowMacroFloor);
    }

    return TdeeTargetProposalResult(
      TdeeProposalStatus.proposed,
      TdeeTargetProposal(
        kcal: kcal,
        proteinG: rule.proteinG,
        carbsG: (remainder / 4).round(),
        fatG: rule.fatG,
        fiberG: rule.fiberG,
        appliesTo: rule.appliesTo,
      ),
    );
  }

  /// Nearest 10, halves up. Targets are positive, so `round()` (half away
  /// from zero) is half-up here.
  static int _roundToTen(int value) => (value / 10).round() * 10;
}
