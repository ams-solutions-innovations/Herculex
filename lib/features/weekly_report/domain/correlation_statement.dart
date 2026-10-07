/// Fixed-template correlation sentences for the weekly report (RPT-05, D-12).
///
/// A statistical relationship between sleep, resting heart rate and training is
/// only ever put in front of the user through the sentences in this file. They
/// say "tended to" (correlation, never causation), they are produced only when
/// there is enough data to say anything (see [CorrelationStatement.minSamples]
/// and [CorrelationStatement.minR2]), and their direction comes from the points
/// themselves because `BiometricCorrelationResult.r2` carries no sign. The
/// result's own free-text getter is deliberately not used: it is worded as a
/// recommendation, which is exactly the claim the report must not make.
///
/// Pure Dart: no Flutter, drift or wall-clock reads.
library;

import 'package:herculex/features/analytics/domain/biometric_correlations.dart';

/// Which pair of series a statement is about.
enum CorrelationKind {
  /// Sleep hours (x) against average session RPE (y).
  sleepRpe('sleep_rpe'),

  /// Resting heart rate (x) against session tonnage (y).
  hrTonnage('hr_tonnage');

  const CorrelationKind(this.wireName);

  /// Value stored in `CorrelationLine.kind`.
  final String wireName;
}

/// Sign of the relationship between x and y.
enum CorrelationDirection { positive, negative, none }

/// One user-visible relationship sentence plus the facts it was built from.
class CorrelationStatement {
  const CorrelationStatement._({
    required this.kind,
    required this.direction,
    required this.sampleSize,
    required this.text,
  });

  /// Builds the sentence for [kind] from [result].
  ///
  /// A relationship is stated only when [BiometricCorrelationResult.sampleSize]
  /// is at least [minSamples], [BiometricCorrelationResult.r2] is at least
  /// [minR2] and the points have a non-degenerate covariance; otherwise the
  /// neutral "No clear relationship yet" sentence is produced.
  factory CorrelationStatement.from({
    required CorrelationKind kind,
    required BiometricCorrelationResult result,
  }) {
    final n = result.sampleSize;
    final strong = n >= minSamples && result.r2.isFinite && result.r2 >= minR2;
    final direction = strong
        ? _direction(result.points)
        : CorrelationDirection.none;
    return CorrelationStatement._(
      kind: kind,
      direction: direction,
      sampleSize: n,
      text: _text(kind, direction, n),
    );
  }

  /// Fewest paired observations before a relationship may be stated.
  ///
  /// Assumption A3 (29-RESEARCH): the existing analytics code treats under 3 as
  /// insufficient, which is too weak for a sentence the user will read as a
  /// finding. Kept as a named constant so it is easy to revisit.
  static const int minSamples = 8;

  /// Smallest R-squared before a relationship may be stated (A3): the existing
  /// "moderate" boundary in the analytics code.
  static const double minR2 = 0.3;

  final CorrelationKind kind;
  final CorrelationDirection direction;
  final int sampleSize;

  /// The sentence shown in the report and sent to the model as a fact.
  final String text;

  /// Sign of the sample covariance of x against y, or none when it cannot be
  /// determined (fewer than two points, a constant series, non-finite values).
  static CorrelationDirection _direction(List<CorrelationPoint> points) {
    final n = points.length;
    if (n < 2) return CorrelationDirection.none;
    var sumX = 0.0;
    var sumY = 0.0;
    for (final p in points) {
      if (!p.x.isFinite || !p.y.isFinite) return CorrelationDirection.none;
      sumX += p.x;
      sumY += p.y;
    }
    final meanX = sumX / n;
    final meanY = sumY / n;
    var cov = 0.0;
    var varX = 0.0;
    var varY = 0.0;
    for (final p in points) {
      final dx = p.x - meanX;
      final dy = p.y - meanY;
      cov += dx * dy;
      varX += dx * dx;
      varY += dy * dy;
    }
    // A constant series has no direction; the tolerance absorbs the rounding of
    // the mean so ten identical values never read as a tiny non-zero slope.
    const epsilon = 1e-9;
    if (!cov.isFinite || varX <= epsilon || varY <= epsilon) {
      return CorrelationDirection.none;
    }
    if (cov > 0) return CorrelationDirection.positive;
    if (cov < 0) return CorrelationDirection.negative;
    return CorrelationDirection.none;
  }

  static String _text(CorrelationKind kind, CorrelationDirection d, int n) {
    if (d == CorrelationDirection.none) {
      return switch (kind) {
        CorrelationKind.sleepRpe =>
          'No clear relationship yet between sleep and session RPE (n = $n).',
        CorrelationKind.hrTonnage =>
          'No clear relationship yet between resting heart rate and session '
              'volume (n = $n).',
      };
    }
    final word = d == CorrelationDirection.positive ? 'higher' : 'lower';
    return switch (kind) {
      CorrelationKind.sleepRpe =>
        'On days with more sleep, your session RPE tended to be $word '
            '(n = $n).',
      CorrelationKind.hrTonnage =>
        'On days with a higher resting heart rate, your session volume tended '
            'to be $word (n = $n).',
    };
  }
}
