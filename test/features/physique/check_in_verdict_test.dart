import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/physique/domain/check_in_verdict.dart';
import 'package:herculex/features/physique/domain/physique_guardrails.dart';

typedef _Case = ({
  String name,
  double low,
  double high,
  AssessmentConfidence conf,
  DietPhase phase,
  double? trend,
  CheckInVerdict expected,
});

_Case _c(
  String name,
  double low,
  double high,
  CheckInVerdict expected, {
  AssessmentConfidence conf = AssessmentConfidence.high,
  DietPhase phase = DietPhase.cut,
  double? trend,
}) => (
  name: name,
  low: low,
  high: high,
  conf: conf,
  phase: phase,
  trend: trend,
  expected: expected,
);

void main() {
  const on = CheckInVerdict.onTrack;
  const off = CheckInVerdict.offTrack;
  const inc = CheckInVerdict.inconclusive;
  final cases = <_Case>[
    _c('low confidence', 0.5, 0.7, inc, conf: AssessmentConfidence.low),
    _c('unknown confidence', 0.5, 0.7, inc, conf: AssessmentConfidence.unknown),
    _c('wide band', 0.1, 1.0, inc),
    _c('width exactly 0.8 passes', 0.2, 1.0, on),
    _c('neutral overlap', -0.1, 0.5, inc),
    _c('low exactly 0.15 is neutral', 0.15, 0.5, inc),
    _c('low just above 0.15 on track', 0.16, 0.5, on),
    _c('high exactly -0.15 is neutral', -0.5, -0.15, inc),
    _c('high below -0.15 off track', -0.6, -0.2, off),
    _c(
      'medium confidence on track',
      0.3,
      0.6,
      on,
      conf: AssessmentConfidence.medium,
    ),
    _c('cut trend up downgrades', 0.3, 0.6, inc, trend: 0.2),
    _c('cut trend exactly 0.1 keeps', 0.3, 0.6, on, trend: 0.1),
    _c('cut trend down keeps', 0.3, 0.6, on, trend: -0.5),
    _c(
      'bulk trend down downgrades',
      0.3,
      0.6,
      inc,
      phase: DietPhase.bulk,
      trend: -0.2,
    ),
    _c('bulk trend up keeps', 0.3, 0.6, on, phase: DietPhase.bulk, trend: 0.3),
    _c(
      'maingain trend down downgrades',
      0.3,
      0.6,
      inc,
      phase: DietPhase.maingain,
      trend: -0.2,
    ),
    _c(
      'maintain big drift downgrades',
      0.3,
      0.6,
      inc,
      phase: DietPhase.maintain,
      trend: 0.5,
    ),
    _c(
      'recomp drift down downgrades',
      0.3,
      0.6,
      inc,
      phase: DietPhase.recomp,
      trend: -0.5,
    ),
    _c(
      'recomp small drift keeps',
      0.3,
      0.6,
      on,
      phase: DietPhase.recomp,
      trend: 0.3,
    ),
    _c('null trend keeps', 0.3, 0.6, on),
    _c('off track never changed by trend', -0.6, -0.2, off, trend: -1.0),
    _c('off track kept with contradicting trend', -0.6, -0.2, off, trend: 0.5),
    _c('inconclusive never upgraded by trend', -0.1, 0.5, inc, trend: -1.0),
  ];

  for (final c in cases) {
    test(c.name, () {
      final v = CheckInVerdictClassifier.classify(
        evidence: CheckInEvidence(
          band: CheckInBand.clamped(c.low, c.high),
          confidence: c.conf,
        ),
        phase: c.phase,
        measuredWeeklyTrendKg: c.trend,
      );
      expect(v, c.expected);
    });
  }

  test('wire values round trip, unknown falls back', () {
    expect(CheckInVerdict.onTrack.wireValue, 'on_track');
    expect(CheckInVerdict.offTrack.wireValue, 'off_track');
    expect(CheckInVerdict.inconclusive.wireValue, 'inconclusive');
    for (final v in CheckInVerdict.values) {
      expect(CheckInVerdict.fromWire(v.wireValue), v);
    }
    expect(CheckInVerdict.fromWire('nonsense'), inc);
    expect(CheckInVerdict.fromWire(null), inc);
  });

  test('band clamps, swaps and rejects non-finite', () {
    final b = CheckInBand.clamped(2, -3);
    expect(b.low, -1);
    expect(b.high, 1);
    final swapped = CheckInBand.clamped(0.5, 0.2);
    expect(swapped.low, 0.2);
    expect(swapped.high, 0.5);
    expect(() => CheckInBand.clamped(double.nan, 0), throwsArgumentError);
    expect(() => CheckInBand.clamped(0, double.infinity), throwsArgumentError);
  });
}
