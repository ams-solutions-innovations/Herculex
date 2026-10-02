import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/physique/domain/physique_guardrails.dart';
import 'package:herculex/features/physique/domain/physique_tuning.dart';

/// Three-state outcome of a physique check-in (D-11). Never a score.
enum CheckInVerdict {
  onTrack('on_track'),
  offTrack('off_track'),
  inconclusive('inconclusive');

  const CheckInVerdict(this.wireValue);
  final String wireValue;

  static CheckInVerdict fromWire(Object? value) {
    for (final v in CheckInVerdict.values) {
      if (v.wireValue == value) return v;
    }
    return CheckInVerdict.inconclusive;
  }
}

/// The AI's directional band, in [-1, 1]: negative means regressing relative
/// to the previous check-in, positive means progressing.
class CheckInBand {
  const CheckInBand._(this.low, this.high);

  /// Clamps both ends to [-1, 1] and swaps them when reversed. Throws
  /// [ArgumentError] for non-finite input.
  factory CheckInBand.clamped(double low, double high) {
    if (!low.isFinite || !high.isFinite) {
      throw ArgumentError('Band bounds must be finite: $low, $high');
    }
    final a = low.clamp(-1.0, 1.0).toDouble();
    final b = high.clamp(-1.0, 1.0).toDouble();
    return a <= b ? CheckInBand._(a, b) : CheckInBand._(b, a);
  }

  final double low;
  final double high;

  double get width => high - low;
}

class CheckInEvidence {
  const CheckInEvidence({
    required this.band,
    required this.confidence,
    this.reason = '',
    this.limitations = const [],
  });

  final CheckInBand band;
  final AssessmentConfidence confidence;
  final String reason;
  final List<String> limitations;
}

/// Turns untrusted AI evidence into a verdict deterministically. Fails closed
/// to inconclusive; the measured trend can only temper an on-track result.
abstract final class CheckInVerdictClassifier {
  static CheckInVerdict classify({
    required CheckInEvidence evidence,
    required DietPhase phase,
    double? measuredWeeklyTrendKg,
  }) {
    if (evidence.confidence == AssessmentConfidence.low ||
        evidence.confidence == AssessmentConfidence.unknown) {
      return CheckInVerdict.inconclusive;
    }
    final band = evidence.band;
    if (band.width > PhysiqueTuning.bandMaxWidth) {
      return CheckInVerdict.inconclusive;
    }
    const neutral = PhysiqueTuning.bandNeutralThreshold;
    if (band.low <= neutral && band.high >= -neutral) {
      return CheckInVerdict.inconclusive;
    }
    if (band.high < -neutral) return CheckInVerdict.offTrack;

    // band.low > neutral: on track unless the scale disagrees.
    if (_contradicts(phase, measuredWeeklyTrendKg)) {
      return CheckInVerdict.inconclusive;
    }
    return CheckInVerdict.onTrack;
  }

  static bool _contradicts(DietPhase phase, double? trend) {
    if (trend == null || !trend.isFinite) return false;
    const rate = PhysiqueTuning.trendContradictionKgPerWeek;
    return switch (phase) {
      DietPhase.cut => trend > rate,
      DietPhase.bulk || DietPhase.maingain => trend < -rate,
      DietPhase.maintain ||
      DietPhase.recomp => trend.abs() > PhysiqueTuning.maintainDriftKgPerWeek,
    };
  }
}
