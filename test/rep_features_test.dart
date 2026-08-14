import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/reps/domain/rep_detector.dart';
import 'package:herculex/features/reps/domain/rep_features.dart';

RepDetectionResult resultWith({
  required List<int> periods,
  required List<double> amps,
}) =>
    RepDetectionResult(
      repCount: periods.length,
      perRepConfidence: List.filled(periods.length, 1.0),
      setConfidence: 1,
      cyclePeriodsMs: periods,
      cycleAmplitudes: amps,
      missedRepSuspected: false,
    );

void main() {
  group('RepFeatures.fromResult ratio guards', () {
    test('both ratio features are null for a 3-rep result', () {
      final f = RepFeatures.fromResult(
        resultWith(periods: [2000, 2100, 2200], amps: [5.0, 4.8, 4.6]),
      );

      expect(f.finalRepPeriodRatio, isNull);
      expect(f.amplitudeDecayRatio, isNull);
      // The unguarded features are still real numbers.
      expect(f.meanPeriodMs, closeTo(2100, 0.001));
      expect(f.normalisedAmplitude, greaterThan(0));
    });

    test('both ratio features are non-null for a 5-rep result', () {
      final f = RepFeatures.fromResult(
        resultWith(
          periods: [2000, 2000, 2000, 2400, 3000],
          amps: [5.0, 5.0, 5.0, 4.0, 3.0],
        ),
      );

      // median of first three periods is 2000, last is 3000.
      expect(f.finalRepPeriodRatio, closeTo(1.5, 0.0001));
      // median of first three amplitudes is 5.0, last is 3.0.
      expect(f.amplitudeDecayRatio, closeTo(0.6, 0.0001));
    });

    test('4 reps is the boundary at which the ratios become defined', () {
      final three = RepFeatures.fromResult(
        resultWith(periods: [2000, 2000, 2000], amps: [5.0, 5.0, 5.0]),
      );
      final four = RepFeatures.fromResult(
        resultWith(periods: [2000, 2000, 2000, 2000], amps: [5.0, 5, 5, 5]),
      );

      expect(three.finalRepPeriodRatio, isNull);
      expect(three.amplitudeDecayRatio, isNull);
      expect(four.finalRepPeriodRatio, isNotNull);
      expect(four.amplitudeDecayRatio, isNotNull);
    });

    test('an empty result yields zeroed unguarded features and null ratios',
        () {
      final f = RepFeatures.fromResult(RepDetectionResult.empty);

      expect(f.meanPeriodMs, 0);
      expect(f.periodCv, 0);
      expect(f.normalisedAmplitude, 0);
      expect(f.finalRepPeriodRatio, isNull);
      expect(f.amplitudeDecayRatio, isNull);
    });
  });

  group('RepFeatures derived values', () {
    test('periodCv is exactly 0 for a perfectly regular period list', () {
      final f = RepFeatures.fromResult(
        resultWith(
          periods: [2000, 2000, 2000, 2000, 2000],
          amps: [5.0, 5.0, 5.0, 5.0, 5.0],
        ),
      );

      expect(f.periodCv, 0);
    });

    test('periodCv rises with cadence irregularity', () {
      final steady = RepFeatures.fromResult(
        resultWith(
          periods: [2000, 2010, 1990, 2000],
          amps: [5.0, 5, 5, 5],
        ),
      );
      final ragged = RepFeatures.fromResult(
        resultWith(
          periods: [1200, 2000, 3400, 2600],
          amps: [5.0, 5, 5, 5],
        ),
      );

      expect(ragged.periodCv, greaterThan(steady.periodCv));
    });

    test('normalisedAmplitude is 1 when mean equals median', () {
      final f = RepFeatures.fromResult(
        resultWith(periods: [2000, 2000, 2000], amps: [4.0, 5.0, 6.0]),
      );

      expect(f.normalisedAmplitude, closeTo(1.0, 1e-9));
    });
  });

  group('RepFeatures serialisation', () {
    test("toJson carries 'v' equal to RepFeatures.version", () {
      final f = RepFeatures.fromResult(
        resultWith(periods: [2000, 2000, 2000], amps: [5.0, 5, 5]),
      );

      expect(f.toJson()['v'], RepFeatures.version);
    });

    test('round-trips all five fields for a 5-rep set', () {
      final f = RepFeatures.fromResult(
        resultWith(
          periods: [2000, 2100, 2050, 2300, 2900],
          amps: [5.0, 4.9, 5.1, 4.2, 3.4],
        ),
      );

      final back = RepFeatures.fromJson(
        jsonDecode(jsonEncode(f.toJson())) as Map<String, dynamic>,
      )!;

      expect(back.meanPeriodMs, closeTo(f.meanPeriodMs, 1e-9));
      expect(back.periodCv, closeTo(f.periodCv, 1e-9));
      expect(back.normalisedAmplitude, closeTo(f.normalisedAmplitude, 1e-9));
      expect(back.finalRepPeriodRatio, closeTo(f.finalRepPeriodRatio!, 1e-9));
      expect(back.amplitudeDecayRatio, closeTo(f.amplitudeDecayRatio!, 1e-9));
    });

    test('round-trips nulls as nulls, not as zeroes', () {
      final f = RepFeatures.fromResult(
        resultWith(periods: [2000, 2100, 2200], amps: [5.0, 4.8, 4.6]),
      );

      final json = jsonDecode(jsonEncode(f.toJson())) as Map<String, dynamic>;
      expect(json['finalRepPeriodRatio'], isNull);
      expect(json['amplitudeDecayRatio'], isNull);

      final back = RepFeatures.fromJson(json)!;
      expect(back.finalRepPeriodRatio, isNull);
      expect(back.amplitudeDecayRatio, isNull);
    });

    test("fromJson returns null on a 'v' mismatch rather than throwing", () {
      final json = RepFeatures.fromResult(
        resultWith(periods: [2000, 2000, 2000, 2000], amps: [5.0, 5, 5, 5]),
      ).toJson();

      expect(RepFeatures.fromJson({...json, 'v': 0}), isNull);
      expect(RepFeatures.fromJson({...json, 'v': RepFeatures.version + 1}),
          isNull);
      expect(RepFeatures.fromJson({...json}..remove('v')), isNull);
    });
  });
}
