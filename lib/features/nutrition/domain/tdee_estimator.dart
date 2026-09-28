import 'dart:math';

import 'package:herculex/features/nutrition/domain/tdee_estimate.dart';
import 'package:herculex/features/nutrition/domain/tdee_trend.dart';

// Downstream files keep importing WeightLog / TrendSeries from here.
export 'package:herculex/features/nutrition/domain/tdee_trend.dart';

/// Every tunable number of the adaptive-TDEE estimator, in one place.
///
/// CONTEXT fixed only the 70% food bar (D-02) and the switching behaviour
/// (D-03, D-04). The window, cadence, trigger and recency numbers are
/// Claude's-discretion values from RESEARCH (A1-A6) plus the recency rule, and
/// are expected to be retuned after real usage.
abstract final class TdeeTuning {
  /// Shortest window the observed path will use.
  static const int minWindowDays = 14;

  /// Candidate windows, widest first. The widest one that passes wins, so the
  /// user is never asked for a duration (TDEE-03).
  static const List<int> windowCandidates = [35, 28, 21, 14];

  /// Share of window days that must have food logged (D-02).
  static const double foodAdherenceBar = 0.70;

  /// Weigh-in floor per window: `max(minWeighIns, weighInsPerWeek * weeks)`.
  static const int minWeighIns = 4;
  static const int weighInsPerWeek = 2;

  /// The data must span at least this share of the candidate window.
  static const double minSpanFraction = 0.6;

  static const double ewmaAlpha = TrendSeries.defaultEwmaAlpha;

  /// Energy density of body-weight change.
  static const double kcalPerKg = 7700.0;

  /// Minimum calendar days between scheduled recalibrations.
  static const int cadenceDays = 7;

  /// Recalibration triggers besides the cadence.
  static const double weightShiftKg = 1.0;
  static const double stepShiftFraction = 0.25;

  /// Qualifying recalibrations needed to promote classifier -> observed (D-03).
  /// They must be at least [cadenceDays] apart: hysteresis counts elapsed
  /// time, not rows, so forced or trigger-driven runs a day apart never count.
  static const int hysteresisCycles = 2;

  /// Extra days an observed estimate is held after its gates stop passing
  /// before falling back to the classifier (D-04).
  static const int graceDays = 7;

  /// A fresh observed row is held until it is this old, then falls back.
  static const int observedHoldMaxAgeDays = cadenceDays + graceDays;

  /// The newest food-logged day AND the newest weigh-in must each be at most
  /// this many whole calendar days before `asOf` (age 0..6 passes, 7 fails).
  ///
  /// D-04 gives a 7-day cadence plus a 7-day grace, so the last fresh observed
  /// row is held until it is 14 days old and then falls back. For the hold to
  /// start at the first cadence run after logging stops, that run (7 days after
  /// the last fresh row) must be able to fail qualification. With a recency of
  /// 6, a user who logged up to the day of the last run has newest data 7 days
  /// old at the next run, fails the gate, and the row is held (aging) for one
  /// more cycle before the fallback at 14 days. A value of 7 or more would let
  /// a week-old window count as fresh and push the fallback a further cycle
  /// out, defeating the grace period. A user who logs on most days always has
  /// the newest data within 6 days. Worst case from the last log to the
  /// fallback is about three weeks. Claude's-discretion value, not a CONTEXT
  /// decision.
  static const int observedRecencyDays = cadenceDays - 1;

  /// A change is material when it exceeds the bigger of this floor or
  /// [materialShiftPct] of the current baseline (D-09).
  static const int materialShiftFloorKcal = 100;
  static const double materialShiftPct = 0.05;

  /// Plausibility rails (T-28-12): garbage inputs fall back to the classifier.
  static const int plausibleMinKcal = 1000;
  static const int plausibleMaxKcal = 6000;
  static const int minPlausibleIntakeKcal = 800;

  /// Food coverage at or above this earns high confidence.
  static const double highConfidenceCoverage = 0.85;
}

/// A measured maintenance estimate plus the numbers behind it.
class ObservedEstimate {
  const ObservedEstimate({
    required this.kcal,
    required this.windowDays,
    required this.spanDays,
    required this.loggedDaysInSpan,
    required this.meanIntakeKcal,
    required this.weightTrendDeltaKg,
    required this.weighIns,
    required this.coverage,
    required this.confidence,
  });

  final int kcal;

  /// The winning candidate window (35, 28, 21 or 14), a selection detail. The
  /// UI must never print it as the data span; it prints `spanDays + 1`.
  final int windowDays;

  /// Days between the first and last day actually used (end minus start). The
  /// data covers `spanDays + 1` calendar days.
  final int spanDays;

  /// Food-logged days inside the span (at most `spanDays + 1`).
  final int loggedDaysInSpan;
  final double meanIntakeKcal;
  final double weightTrendDeltaKg;
  final int weighIns;

  /// `loggedDaysInSpan / (spanDays + 1)`.
  final double coverage;
  final TdeeConfidence confidence;

  Map<String, Object?> toInputs() => {
    'mean_intake_kcal': meanIntakeKcal.round(),
    'logged_days': loggedDaysInSpan,
    'window_days': windowDays,
    'span_days': spanDays,
    'weight_trend_delta_kg': (weightTrendDeltaKg * 1000).round() / 1000,
    'weigh_ins': weighIns,
  };
}

/// Why a recalibration should run now.
enum RecalibrationReason {
  none,
  noEstimate,
  elapsed,
  weightTrendShift,
  activityShift,
  forced,
}

/// Pure adaptive-TDEE logic. No I/O, no wall clock: every method takes an
/// explicit `asOf`, so each branch is testable with fixed dates.
abstract final class TdeeEstimator {
  /// Observed expenditure: mean logged-day intake minus the change in the
  /// smoothed bodyweight trend times 7700 kcal/kg over the span (TDEE-01).
  ///
  /// Returns null unless some window passes every gate: recency, food
  /// adherence, weigh-in count, span, and the plausibility rails. The widest
  /// passing window wins (TDEE-03). Data dated after `asOf` is ignored.
  static ObservedEstimate? estimateObserved({
    required DateTime asOf,
    required Set<String> foodLoggedDays,
    required Map<String, double> dailyKcalByDate,
    required List<WeightLog> weightLogs,
  }) {
    final asOfDate = _dateOnly(asOf);
    final asOfDay = TrendSeries.dayNumber(asOfDate);

    final logs = [
      for (final l in weightLogs)
        if (TrendSeries.dayNumber(l.date) <= asOfDay) l,
    ];
    final weighDays = {for (final l in logs) TrendSeries.dayNumber(l.date)};

    // Step 0, recency: stale data can never count as fresh.
    final foodRecent = _hasFoodBetween(
      foodLoggedDays,
      asOfDate,
      asOfDay - TdeeTuning.observedRecencyDays,
      asOfDay,
    );
    final weightRecent = weighDays.any(
      (d) => asOfDay - d <= TdeeTuning.observedRecencyDays,
    );
    if (!foodRecent || !weightRecent) return null;

    final series = TrendSeries.fromLogs(logs);
    if (series.isEmpty) return null;
    final firstDay = TrendSeries.dayNumber(series.firstDate);
    final lastDay = TrendSeries.dayNumber(series.lastDate);

    for (final w in TdeeTuning.windowCandidates) {
      final windowStart = asOfDay - (w - 1);

      // Food gate (D-01, D-02), presence-based (RESEARCH Pitfall 3).
      final windowFood = _countFood(
        foodLoggedDays,
        asOfDate,
        asOfDay,
        windowStart,
        asOfDay,
      );
      if (windowFood < _ceilShare(TdeeTuning.foodAdherenceBar, w)) continue;

      // Weight gate (D-01): independent of the food gate.
      final weeks = (w + 6) ~/ 7;
      final needWeighIns = max(
        TdeeTuning.minWeighIns,
        TdeeTuning.weighInsPerWeek * weeks,
      );
      final half = windowStart + (w ~/ 2);
      final inWindow = [
        for (final d in weighDays)
          if (d >= windowStart && d <= asOfDay) d,
      ];
      if (inWindow.length < needWeighIns) continue;
      if (!inWindow.any((d) => d < half) || !inWindow.any((d) => d >= half)) {
        continue;
      }

      final start = max(windowStart, firstDay);
      final end = min(asOfDay, lastDay);
      final span = end - start;
      if (span < _ceilShare(TdeeTuning.minSpanFraction, w)) continue;

      final logged = <int>[
        for (var d = start; d <= end; d++)
          if (foodLoggedDays.contains(_iso(_addDays(asOfDate, d - asOfDay)))) d,
      ];
      if (logged.length < _ceilShare(TdeeTuning.foodAdherenceBar, span + 1)) {
        continue;
      }

      var sum = 0.0;
      for (final d in logged) {
        sum += dailyKcalByDate[_iso(_addDays(asOfDate, d - asOfDay))] ?? 0;
      }
      final meanIntake = sum / logged.length;
      if (meanIntake < TdeeTuning.minPlausibleIntakeKcal) continue;

      final delta =
          series.valueOn(_addDays(asOfDate, end - asOfDay)) -
          series.valueOn(_addDays(asOfDate, start - asOfDay));
      final tdee = meanIntake - delta * TdeeTuning.kcalPerKg / span;
      if (tdee < TdeeTuning.plausibleMinKcal ||
          tdee > TdeeTuning.plausibleMaxKcal) {
        continue;
      }

      final coverage = logged.length / (span + 1);
      final high =
          coverage >= TdeeTuning.highConfidenceCoverage &&
          inWindow.length >= 3 * weeks;
      return ObservedEstimate(
        kcal: tdee.round(),
        windowDays: w,
        spanDays: span,
        loggedDaysInSpan: logged.length,
        meanIntakeKcal: meanIntake,
        weightTrendDeltaKg: delta,
        weighIns: inWindow.length,
        coverage: coverage,
        confidence: high ? TdeeConfidence.high : TdeeConfidence.medium,
      );
    }
    return null;
  }

  static bool _hasFoodBetween(
    Set<String> food,
    DateTime asOfDate,
    int fromDay,
    int toDay,
  ) =>
      _countFood(
        food,
        asOfDate,
        TrendSeries.dayNumber(asOfDate),
        fromDay,
        toDay,
      ) >
      0;

  /// Food-logged days with day number in `[fromDay, toDay]`.
  static int _countFood(
    Set<String> food,
    DateTime asOfDate,
    int asOfDay,
    int fromDay,
    int toDay,
  ) {
    var n = 0;
    for (var d = fromDay; d <= toDay; d++) {
      if (food.contains(_iso(_addDays(asOfDate, d - asOfDay)))) n++;
    }
    return n;
  }

  /// `ceil(share * n)` immune to binary noise (0.7 * 10 must be 7, not 8).
  static int _ceilShare(double share, int n) => (share * n - 1e-9).ceil();

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _addDays(DateTime date, int days) =>
      DateTime(date.year, date.month, date.day + days);

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
