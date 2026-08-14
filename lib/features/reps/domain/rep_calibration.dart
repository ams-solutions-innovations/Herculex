import 'dart:convert';
import 'dart:math' as math;

import '../../../data/local/database.dart';
import 'rep_features.dart';
import 'rpe_estimator.dart';

/// Where a per (slug, source, placement, sensorType) profile stands.
///
///  * [insufficient] — too few surviving rows or sessions to trust anything
///    beyond the raw count; equivalent to not-yet-attempted.
///  * [countOnly] — enough rows and sessions to have *attempted* an RPE fit,
///    but the fit's own leave-one-out error is not good enough to trust.
///    Not an error state — see 10-CONTEXT "Confidence and fallback states".
///  * [calibrated] — [RpeEstimator.gatePasses] holds; an RPE suggestion may
///    be offered.
enum CalibrationStatus { insufficient, countOnly, calibrated }

/// A per (slug, source, placement, sensorType) learning profile, computed on
/// demand from that exact tuple's confirmed observations rather than stored
/// as a denormalised blob — recomputing from around 30 rows is cheap and
/// removes an entire class of staleness bug.
///
/// **Invalidation by key, not by event:** the profile key is the four-part
/// tuple this class is built from (via
/// `RepTrackingRepository.observationsFor`). A change to any one component —
/// placement, source, sensor type — means a different set of rows, and
/// therefore a fresh [CalibrationProfile] starting at [CalibrationStatus
/// .insufficient]. Switching back restores the old key's rows untouched.
/// This falls out of the repository's exact-match query and needs no
/// explicit invalidation logic here.
class CalibrationProfile {
  const CalibrationProfile._({
    required this.sampleCount,
    required this.distinctSessionCount,
    required this.medianCadenceMs,
    required this.cadenceSpread,
    required this.model,
    required this.looMae,
    required this.status,
    RpeEstimator? estimator,
  }) : _estimator = estimator;

  /// Rows surviving the [RepFeatures.fromJson] version filter. A `v`
  /// mismatch (an older detector's vector) drops the row entirely — training
  /// across detector versions would silently corrupt the model (T-10-22).
  final int sampleCount;

  /// Distinct `sessionId` values among the surviving rows.
  final int distinctSessionCount;

  /// Used to seed this user's detector thresholds. Computed across every
  /// surviving row, including ones with no confirmed RPE — cadence needs no
  /// RPE label to be meaningful.
  final double medianCadenceMs;
  final double cadenceSpread;

  /// The fitted ridge model, or null unless [status] is
  /// [CalibrationStatus.calibrated]. A model may exist internally (via
  /// [_estimator]) even when this is null — [status] decides whether it has
  /// earned the right to be surfaced, not whether a fit was attempted.
  final RpeModel? model;

  /// The fit's own leave-one-out MAE in RPE points, or null when the fit
  /// could not run (fewer than two rows with a confirmed RPE and no null
  /// feature). Populated regardless of [status] — useful for diagnostics
  /// even when the model hasn't earned [CalibrationStatus.calibrated].
  final double? looMae;

  final CalibrationStatus status;

  /// Present whenever a fit was attempted, regardless of [status] — the
  /// private route [estimate] uses so a not-yet-calibrated profile can still
  /// answer "no suggestion" without re-deriving the gate here.
  final RpeEstimator? _estimator;

  /// Builds a profile from one (slug, source, placement, sensorType)
  /// tuple's rows, oldest-first or in any order — order does not matter
  /// here, only membership.
  factory CalibrationProfile.fromObservations(
    List<RepSetObservationData> rows,
  ) {
    final surviving = <(RepSetObservationData, RepFeatures)>[];
    for (final row in rows) {
      final Map<String, dynamic> raw;
      try {
        raw = jsonDecode(row.featuresJson) as Map<String, dynamic>;
      } on FormatException {
        // Not a feature-vector shape this profile can use — treated the
        // same as a version mismatch: dropped, never fabricated.
        continue;
      }
      final features = RepFeatures.fromJson(raw);
      if (features == null) continue; // 'v' mismatch — an older detector.
      surviving.add((row, features));
    }

    final sampleCount = surviving.length;
    final distinctSessionCount =
        surviving.map((e) => e.$1.sessionId).toSet().length;

    final periods = [for (final e in surviving) e.$2.meanPeriodMs];
    final medianCadenceMs = _median(periods);
    final cadenceSpread = _stddev(periods);

    // Only rows with a confirmed RPE train the model — a user who never
    // enters one never gets a suggestion, and that needs no special
    // handling. They still contributed to the cadence stats above.
    final rpeRows = [
      for (final e in surviving)
        if (e.$1.confirmedRpeX10 != null)
          RpeTrainingRow(features: e.$2, rpe: e.$1.confirmedRpeX10! / 10.0),
    ];

    final estimator = RpeEstimator.fit(
      rows: rpeRows,
      sampleCount: sampleCount,
      distinctSessionCount: distinctSessionCount,
    );

    // Isolates the count/session portion of the single named gate predicate
    // by feeding it a looMae that always passes (0.0 <= 1.0) — this
    // profile never restates the 10/3 thresholds itself, so a future
    // threshold change still happens in exactly one place
    // (`RpeEstimator.gatePasses`).
    final dataSufficient = RpeEstimator.gatePasses(
      sampleCount: sampleCount,
      distinctSessionCount: distinctSessionCount,
      looMae: 0.0,
    );
    final calibrated = RpeEstimator.gatePasses(
      sampleCount: sampleCount,
      distinctSessionCount: distinctSessionCount,
      looMae: estimator.looMae,
    );

    final status = calibrated
        ? CalibrationStatus.calibrated
        : (dataSufficient
            ? CalibrationStatus.countOnly
            : CalibrationStatus.insufficient);

    return CalibrationProfile._(
      sampleCount: sampleCount,
      distinctSessionCount: distinctSessionCount,
      medianCadenceMs: medianCadenceMs,
      cadenceSpread: cadenceSpread,
      model: calibrated ? estimator.model : null,
      looMae: estimator.looMae,
      status: status,
      estimator: estimator,
    );
  }

  /// Null whenever [status] is not [CalibrationStatus.calibrated], [f]
  /// carries a null feature, or no fit could run — a thin pass-through to
  /// the estimator's own gate/clamp/round logic so callers never
  /// re-implement it.
  double? estimate(RepFeatures f) => _estimator?.estimate(f);

  static double _median(List<double> v) {
    if (v.isEmpty) return 0;
    final s = List<double>.of(v)..sort();
    final mid = s.length ~/ 2;
    return s.length.isOdd ? s[mid] : (s[mid - 1] + s[mid]) / 2;
  }

  static double _stddev(List<double> v) {
    if (v.length < 2) return 0;
    final m = v.reduce((a, b) => a + b) / v.length;
    final varSum = v.fold(0.0, (s, x) => s + (x - m) * (x - m));
    return math.sqrt(varSum / v.length);
  }
}
