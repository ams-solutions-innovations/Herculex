import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/core/utils/clock.dart';
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
// are invoked from a user tap in `TdeeShiftCard` and nowhere else, and both
// go through `WeeklyReportRepository.applyTdeeDecision` so the target write and
// the decision record are one transaction. Nothing in the narrative path, the
// service or the controller may call `upsertTarget`: the AI never writes, the
// user confirms.

/// Label used when the saved target row cannot be found.
const String fallbackTargetLabel = 'Target';

/// Whether the TDEE card may offer buttons for [week] (D-11): only the current
/// ISO week or the due week. Any other week is a read-only record.
bool isActionableWeek(IsoWeek week, DateTime now, IsoWeek? dueWeek) {
  return week == IsoWeek.fromDate(now) || (dueWeek != null && week == dueWeek);
}

/// Outcome of a TDEE card action. Anything but [applied] wrote nothing.
enum TdeeActionResult {
  applied,
  alreadyDecided,
  stale,
  notActionable,
  invalidInput,
}

/// The two user-confirmed outcomes of the TDEE shift card. Each records a
/// write-once decision on the report row.
class TdeeDecisionActions {
  TdeeDecisionActions(
    this._reports,
    this._nutrition,
    this._clock,
    this._dueWeek,
    this._resolveProposal,
    this._labelFor,
  );

  final WeeklyReportRepository _reports;
  final NutritionRepository _nutrition;
  final Clock _clock;
  final IsoWeek? Function() _dueWeek;
  final Future<TdeeTargetProposalResult> Function(int oldKcal, int newKcal)
  _resolveProposal;
  final Future<String> Function(String appliesTo) _labelFor;

  bool _actionable(IsoWeek week) =>
      isActionableWeek(week, _clock.now(), _dueWeek());

  static bool _validKcal(int kcal) =>
      kcal >= WeeklyReportRepository.minDecisionKcal &&
      kcal <= WeeklyReportRepository.maxDecisionKcal;

  /// Applies the CURRENT proposal for the shift to the user's saved target and
  /// records `updated`, atomically. The proposal is re-resolved against the
  /// saved rule first; if its kcal or appliesTo differ from [displayed] the
  /// suggestion is out of date and nothing is written. The write always uses
  /// the freshly resolved macros, never the displayed ones.
  Future<TdeeActionResult> update({
    required IsoWeek week,
    required int oldEstimateKcal,
    required int newEstimateKcal,
    required TdeeTargetProposal displayed,
  }) async {
    if (!_actionable(week)) return TdeeActionResult.notActionable;
    if (!_validKcal(displayed.kcal)) return TdeeActionResult.invalidInput;

    final resolved = await _resolveProposal(oldEstimateKcal, newEstimateKcal);
    final fresh = resolved.proposal;
    if (resolved.status != TdeeProposalStatus.proposed ||
        fresh == null ||
        fresh.kcal != displayed.kcal ||
        fresh.appliesTo != displayed.appliesTo) {
      return TdeeActionResult.stale;
    }
    if (!_validKcal(fresh.kcal)) return TdeeActionResult.invalidInput;

    final label = await _labelFor(fresh.appliesTo);
    final done = await _reports.applyTdeeDecision(
      week,
      decision: 'updated',
      kcal: fresh.kcal,
      beforeRecord: () => _nutrition.upsertTarget(
        label: label,
        appliesTo: fresh.appliesTo,
        kcal: fresh.kcal,
        proteinG: fresh.proteinG,
        carbsG: fresh.carbsG,
        fatG: fresh.fatG,
        fiberG: fresh.fiberG,
      ),
    );
    return done ? TdeeActionResult.applied : TdeeActionResult.alreadyDecided;
  }

  /// Records `kept` at [currentKcal]. Never touches targets.
  Future<TdeeActionResult> keep({
    required IsoWeek week,
    required int currentKcal,
  }) async {
    if (!_actionable(week)) return TdeeActionResult.notActionable;
    if (!_validKcal(currentKcal)) return TdeeActionResult.invalidInput;
    final done = await _reports.applyTdeeDecision(
      week,
      decision: 'kept',
      kcal: currentKcal,
    );
    return done ? TdeeActionResult.applied : TdeeActionResult.alreadyDecided;
  }
}

final tdeeDecisionActionsProvider = Provider<TdeeDecisionActions>((ref) {
  // Everything live is read at call time (ref.read inside the closures), so
  // building this provider never depends on the proposal providers.
  return TdeeDecisionActions(
    ref.watch(weeklyReportRepositoryProvider),
    ref.watch(nutritionRepositoryProvider),
    ref.watch(clockProvider),
    () => ref.read(weeklyReportDueWeekProvider),
    (oldKcal, newKcal) {
      final provider = tdeeTargetProposalProvider((oldKcal, newKcal));
      // Drop any cached value so the current saved rule is used.
      ref.invalidate(provider);
      return ref.read(provider.future);
    },
    (appliesTo) {
      final provider = savedTargetLabelProvider(appliesTo);
      ref.invalidate(provider);
      return ref.read(provider.future);
    },
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
