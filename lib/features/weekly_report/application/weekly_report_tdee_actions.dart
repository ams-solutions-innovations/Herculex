import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/features/nutrition/application/goals_providers.dart';
import 'package:herculex/features/nutrition/application/nutrition_providers.dart';
import 'package:herculex/features/nutrition/application/tdee_display_providers.dart';
import 'package:herculex/features/nutrition/data/nutrition_repository.dart';
import 'package:herculex/features/physique/application/physique_providers.dart';
import 'package:herculex/features/weekly_report/application/weekly_report_providers.dart';
import 'package:herculex/features/weekly_report/data/weekly_report_repository.dart';
import 'package:herculex/features/weekly_report/domain/iso_week.dart';
import 'package:herculex/features/weekly_report/domain/tdee_target_proposal.dart';

// This file holds the ONLY write path from the weekly report to the user's
// nutrition targets (TDEE-05, D-11). Both methods of [TdeeDecisionActions]
// are invoked from a user tap in `TdeeShiftCard` and nowhere else. Nothing in
// the narrative path, the service or the controller may call `upsertTarget`:
// the AI never writes, the user confirms.

/// Label used when the saved target row cannot be found.
const String fallbackTargetLabel = 'Target';

/// Whether the TDEE card may offer buttons for [week] (D-11): only the current
/// ISO week or the due week. Any other week is a read-only record.
bool isActionableWeek(IsoWeek week, DateTime now, IsoWeek? dueWeek) {
  return week == IsoWeek.fromDate(now) || (dueWeek != null && week == dueWeek);
}

/// The two user-confirmed outcomes of the TDEE shift card. Each records a
/// write-once decision on the report row.
class TdeeDecisionActions {
  TdeeDecisionActions(this._reports, this._nutrition);

  final WeeklyReportRepository _reports;
  final NutritionRepository _nutrition;

  /// Applies [proposal] to the user's saved target and records `updated`.
  ///
  /// Returns false, having written nothing, when the week has no report, a
  /// decision already exists, or the proposal cannot be stored as a decision.
  Future<bool> update({
    required IsoWeek week,
    required TdeeTargetProposal proposal,
    required String label,
  }) async {
    final kcal = proposal.kcal;
    if (kcal < WeeklyReportRepository.minDecisionKcal ||
        kcal > WeeklyReportRepository.maxDecisionKcal) {
      return false;
    }
    final record = await _reports.forWeek(week);
    if (record == null || record.tdeeDecision != null) return false;

    await _nutrition.upsertTarget(
      label: label,
      appliesTo: proposal.appliesTo,
      kcal: kcal,
      proteinG: proposal.proteinG,
      carbsG: proposal.carbsG,
      fatG: proposal.fatG,
      fiberG: proposal.fiberG,
    );
    return _reports.recordTdeeDecision(week, decision: 'updated', kcal: kcal);
  }

  /// Records `kept` at [currentKcal]. Never touches targets.
  Future<bool> keep({required IsoWeek week, required int currentKcal}) {
    return _reports.recordTdeeDecision(
      week,
      decision: 'kept',
      kcal: currentKcal,
    );
  }
}

final tdeeDecisionActionsProvider = Provider<TdeeDecisionActions>((ref) {
  return TdeeDecisionActions(
    ref.watch(weeklyReportRepositoryProvider),
    ref.watch(nutritionRepositoryProvider),
  );
});

/// The proposal for a stored shift (old estimate, new estimate), computed
/// against the user's CURRENT saved rule and safety limits: the minimum
/// calories floor and the editor eligibility (PHYS-04).
final tdeeTargetProposalProvider = FutureProvider.autoDispose
    .family<TdeeTargetProposalResult, (int oldKcal, int newKcal)>((
      ref,
      shift,
    ) async {
      final rule = await ref.watch(savedTargetForTodayProvider.future);
      final floor = ref.watch(
        minimumTargetsProvider.select((s) => s.effectiveMinCaloriesKcal),
      );
      final eligibility = ref.watch(physiqueEditorEligibilityProvider);
      return TdeeTargetProposalCalculator.compute(
        rule: rule,
        oldEstimateKcal: shift.$1,
        newEstimateKcal: shift.$2,
        minCaloriesKcal: floor,
        eligibility: eligibility,
      );
    });

/// Label of the saved target row for [appliesTo], or [fallbackTargetLabel].
final savedTargetLabelProvider = FutureProvider.autoDispose
    .family<String, String>((ref, appliesTo) async {
      final rows = await ref.watch(nutritionTargetsProvider.future);
      for (final row in rows) {
        if (row.appliesTo == appliesTo) return row.label;
      }
      return fallbackTargetLabel;
    });
