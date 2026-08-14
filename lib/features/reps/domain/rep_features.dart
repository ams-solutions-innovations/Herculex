import 'dart:math';

import 'rep_detector.dart';

/// The five-feature calibration vector derived from one set's detection result.
///
/// These five features are fixed by 10-CONTEXT ("RPE suggestion gating"), not
/// chosen here. This is the payload 10-01's `RepSetObservations.featuresJson`
/// stores as an opaque string and 10-05 trains its per-(user, exercise, device,
/// placement) least-squares fit on.
class RepFeatures {
  /// Serialised as the `'v'` key.
  ///
  /// Versioned from day one so 10-05 can *discard* vectors produced by an older
  /// detector rather than train on numbers that are not comparable. Bump this
  /// whenever a change to [RepDetector] moves the feature distribution.
  static const int version = 1;

  /// Mean trough-to-trough cycle duration, in milliseconds.
  final double meanPeriodMs;

  /// Coefficient of variation of the cycle periods (stddev / mean). A cadence
  /// regularity proxy; 0 for a perfectly metronomic set.
  final double periodCv;

  /// Mean cycle amplitude divided by the median cycle amplitude. A range-of-
  /// motion proxy that is scale-free, so it survives a device change.
  final double normalisedAmplitude;

  /// Last cycle period divided by the median of the first three. Above 1 means
  /// the final rep was slower than the opening cadence.
  ///
  /// **Null below 4 reps**, where "the first three" and "the last" overlap and
  /// the ratio measures nothing.
  final double? finalRepPeriodRatio;

  /// Last cycle amplitude divided by the median of the first three. Below 1
  /// means range of motion shrank across the set.
  ///
  /// **Null below 4 reps**, for the same reason.
  final double? amplitudeDecayRatio;

  const RepFeatures({
    required this.meanPeriodMs,
    required this.periodCv,
    required this.normalisedAmplitude,
    required this.finalRepPeriodRatio,
    required this.amplitudeDecayRatio,
  });

  /// Number of reps below which the two ratio features are undefined.
  static const int ratioMinReps = 4;

  /// How many leading cycles the ratio features compare the final cycle to.
  static const int ratioBaselineCycles = 3;

  factory RepFeatures.fromResult(RepDetectionResult r) {
    final periods = r.cyclePeriodsMs.map((e) => e.toDouble()).toList();
    final amps = List<double>.of(r.cycleAmplitudes);

    final meanPeriod = _mean(periods);
    final cv = meanPeriod == 0 ? 0.0 : _stddev(periods) / meanPeriod;
    final medianAmp = _median(amps);
    final normAmp = medianAmp == 0 ? 0.0 : _mean(amps) / medianAmp;

    // Guarded, not fabricated. 10-05 excludes a null from the fit; it must
    // never receive an invented number it cannot tell apart from a real one.
    double? periodRatio;
    double? ampRatio;
    if (periods.length >= ratioMinReps && amps.length >= ratioMinReps) {
      final basePeriod = _median(periods.take(ratioBaselineCycles).toList());
      final baseAmp = _median(amps.take(ratioBaselineCycles).toList());
      periodRatio = basePeriod == 0 ? null : periods.last / basePeriod;
      ampRatio = baseAmp == 0 ? null : amps.last / baseAmp;
    }

    return RepFeatures(
      meanPeriodMs: meanPeriod,
      periodCv: cv,
      normalisedAmplitude: normAmp,
      finalRepPeriodRatio: periodRatio,
      amplitudeDecayRatio: ampRatio,
    );
  }

  Map<String, dynamic> toJson() => {
        'v': version,
        'meanPeriodMs': meanPeriodMs,
        'periodCv': periodCv,
        'normalisedAmplitude': normalisedAmplitude,
        'finalRepPeriodRatio': finalRepPeriodRatio,
        'amplitudeDecayRatio': amplitudeDecayRatio,
      };

  /// Returns null when [j] was written by a different detector version, so a
  /// stale vector is dropped rather than silently mixed into a fit.
  static RepFeatures? fromJson(Map<String, dynamic> j) {
    if (j['v'] != version) return null;
    double? opt(Object? v) => v == null ? null : (v as num).toDouble();
    double req(Object? v) => (v as num?)?.toDouble() ?? 0.0;
    return RepFeatures(
      meanPeriodMs: req(j['meanPeriodMs']),
      periodCv: req(j['periodCv']),
      normalisedAmplitude: req(j['normalisedAmplitude']),
      finalRepPeriodRatio: opt(j['finalRepPeriodRatio']),
      amplitudeDecayRatio: opt(j['amplitudeDecayRatio']),
    );
  }

  // --- primitives -----------------------------------------------------------

  static double _mean(List<double> v) =>
      v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;

  static double _stddev(List<double> v) {
    if (v.length < 2) return 0;
    final m = _mean(v);
    final varSum = v.fold(0.0, (s, x) => s + (x - m) * (x - m));
    return sqrt(varSum / v.length);
  }

  static double _median(List<double> v) {
    if (v.isEmpty) return 0;
    final s = List<double>.of(v)..sort();
    final mid = s.length ~/ 2;
    return s.length.isOdd ? s[mid] : (s[mid - 1] + s[mid]) / 2;
  }
}
