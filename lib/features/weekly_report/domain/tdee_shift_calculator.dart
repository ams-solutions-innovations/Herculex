/// TDEE drift card calculator for the weekly report (RPT-01, RPT-02, D-11).
///
/// Diffs two points of the `tdee_estimates` history instead of reading the
/// week's logged data: [newest] is the newest estimate at or before the window
/// end and [before] the newest one strictly before the week started (the caller
/// loads both through `TdeeEstimatesRepository.latestAtOrBefore` and
/// `latestBefore`).
///
/// Whether a shift is material is decided by `TdeeEstimator.isMaterialShift`
/// (strictly greater than the floor-or-percentage threshold), the same rule Phase 28 uses for
/// its hysteresis. It is deliberately not restated here.
///
/// Pure Dart: no Flutter, drift or wall-clock reads.
library;

import 'package:herculex/features/nutrition/domain/tdee_estimate.dart';
import 'package:herculex/features/nutrition/domain/tdee_estimator.dart';
import 'package:herculex/features/weekly_report/domain/weekly_report_sections.dart';

abstract final class TdeeShiftCalculator {
  /// Returns null when there is nothing to compare: no earlier estimate, no
  /// newest estimate, or a newest estimate that is only the onboarding cold
  /// start (a seeded number is not a measured drift).
  ///
  /// A shift that is not material still yields a section with
  /// `material == false` so the drift is stored for the facts; the actionable
  /// card shows only when `material` is true.
  static TdeeSection? compute({
    required TdeeEstimateResult? newest,
    required TdeeEstimateResult? before,
  }) {
    if (newest == null || before == null) return null;
    if (newest.method == TdeeMethod.coldStart) return null;

    return TdeeSection(
      oldKcal: before.kcal,
      newKcal: newest.kcal,
      deltaKcal: newest.kcal - before.kcal,
      material: TdeeEstimator.isMaterialShift(
        currentBaselineKcal: before.kcal,
        newEstimateKcal: newest.kcal,
      ),
      confidence: newest.confidence.name,
    );
  }
}
