import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/analytics/domain/biometric_correlations.dart';
import 'package:herculex/features/weekly_report/domain/causal_language_guard.dart';
import 'package:herculex/features/weekly_report/domain/correlation_statement.dart';

/// [n] points whose x rises by 1 per point; y rises (slope > 0) or falls.
BiometricCorrelationResult _result({
  required int n,
  required double slope,
  double r2 = 0.5,
}) {
  return BiometricCorrelationResult(
    points: [
      for (var i = 0; i < n; i++) CorrelationPoint(i + 5.0, 10 + slope * i),
    ],
    r2: r2,
    sampleSize: n,
  );
}

void main() {
  group('CorrelationStatement thresholds', () {
    test('constants are named and fixed', () {
      expect(CorrelationStatement.minSamples, 8);
      expect(CorrelationStatement.minR2, 0.3);
    });

    test('wire names', () {
      expect(CorrelationKind.sleepRpe.wireName, 'sleep_rpe');
      expect(CorrelationKind.hrTonnage.wireName, 'hr_tonnage');
    });
  });

  group('CorrelationStatement sleep vs RPE', () {
    test('negative covariance -> lower RPE', () {
      final s = CorrelationStatement.from(
        kind: CorrelationKind.sleepRpe,
        result: _result(n: 10, slope: -0.2),
      );
      expect(
        s.text,
        'On days with more sleep, your session RPE tended to be lower (n = 10).',
      );
      expect(s.direction, CorrelationDirection.negative);
      expect(s.sampleSize, 10);
      expect(s.kind, CorrelationKind.sleepRpe);
    });

    test('positive covariance -> higher RPE', () {
      final s = CorrelationStatement.from(
        kind: CorrelationKind.sleepRpe,
        result: _result(n: 10, slope: 0.2),
      );
      expect(
        s.text,
        'On days with more sleep, your session RPE tended to be higher (n = 10).',
      );
      expect(s.direction, CorrelationDirection.positive);
    });

    test('too few samples -> neutral sentence', () {
      final s = CorrelationStatement.from(
        kind: CorrelationKind.sleepRpe,
        result: _result(n: 7, slope: -0.2),
      );
      expect(
        s.text,
        'No clear relationship yet between sleep and session RPE (n = 7).',
      );
      expect(s.direction, CorrelationDirection.none);
    });

    test('exactly minSamples with r2 on the boundary is stated', () {
      final s = CorrelationStatement.from(
        kind: CorrelationKind.sleepRpe,
        result: _result(n: 8, slope: -0.2, r2: 0.3),
      );
      expect(s.direction, CorrelationDirection.negative);
    });

    test('r2 below the floor -> neutral sentence', () {
      final s = CorrelationStatement.from(
        kind: CorrelationKind.sleepRpe,
        result: _result(n: 12, slope: -0.2, r2: 0.29),
      );
      expect(
        s.text,
        'No clear relationship yet between sleep and session RPE (n = 12).',
      );
      expect(s.direction, CorrelationDirection.none);
    });
  });

  group('CorrelationStatement resting HR vs tonnage', () {
    test('negative -> lower volume', () {
      final s = CorrelationStatement.from(
        kind: CorrelationKind.hrTonnage,
        result: _result(n: 9, slope: -50),
      );
      expect(
        s.text,
        'On days with a higher resting heart rate, your session volume tended '
        'to be lower (n = 9).',
      );
      expect(s.direction, CorrelationDirection.negative);
    });

    test('positive -> higher volume', () {
      final s = CorrelationStatement.from(
        kind: CorrelationKind.hrTonnage,
        result: _result(n: 9, slope: 50),
      );
      expect(
        s.text,
        'On days with a higher resting heart rate, your session volume tended '
        'to be higher (n = 9).',
      );
      expect(s.direction, CorrelationDirection.positive);
    });

    test('too few samples / weak r2 -> neutral sentence', () {
      final few = CorrelationStatement.from(
        kind: CorrelationKind.hrTonnage,
        result: _result(n: 7, slope: 50),
      );
      expect(
        few.text,
        'No clear relationship yet between resting heart rate and session '
        'volume (n = 7).',
      );
      expect(few.direction, CorrelationDirection.none);

      final weak = CorrelationStatement.from(
        kind: CorrelationKind.hrTonnage,
        result: _result(n: 11, slope: 50, r2: 0.1),
      );
      expect(weak.direction, CorrelationDirection.none);
      expect(weak.sampleSize, 11);
    });
  });

  group('CorrelationStatement degenerate input', () {
    test('zero covariance never divides by zero', () {
      final s = CorrelationStatement.from(
        kind: CorrelationKind.sleepRpe,
        result: BiometricCorrelationResult(
          points: [for (var i = 0; i < 10; i++) CorrelationPoint(i + 1.0, 7)],
          r2: 0.9,
          sampleSize: 10,
        ),
      );
      expect(s.direction, CorrelationDirection.none);
      expect(s.text, startsWith('No clear relationship yet'));
    });

    test('fewer than two points yields none', () {
      for (final points in [
        <CorrelationPoint>[],
        [const CorrelationPoint(7, 6)],
      ]) {
        final s = CorrelationStatement.from(
          kind: CorrelationKind.hrTonnage,
          result: BiometricCorrelationResult(
            points: points,
            r2: 0.9,
            sampleSize: 20,
          ),
        );
        expect(s.direction, CorrelationDirection.none);
      }
    });

    test('non-finite points yield none', () {
      final s = CorrelationStatement.from(
        kind: CorrelationKind.sleepRpe,
        result: BiometricCorrelationResult(
          points: [
            for (var i = 0; i < 10; i++)
              CorrelationPoint(i.toDouble(), i == 3 ? double.nan : i * 1.0),
          ],
          r2: 0.9,
          sampleSize: 10,
        ),
      );
      expect(s.direction, CorrelationDirection.none);
    });

    test('direction comes from the points, not from r2 or interpretation', () {
      // r2 says "strong", the existing interpretation getter would say
      // "Strong correlation detected ... shifts targets positively".
      final result = _result(n: 10, slope: -0.4, r2: 0.95);
      expect(result.interpretation, contains('Strong'));
      final s = CorrelationStatement.from(
        kind: CorrelationKind.sleepRpe,
        result: result,
      );
      expect(s.direction, CorrelationDirection.negative);
      expect(s.text, contains('lower'));
      expect(s.text, isNot(contains('Strong')));
    });
  });

  group('CorrelationStatement wording', () {
    test('every template passes the causal guard and says "tended to"', () {
      final texts = <String>[];
      for (final kind in CorrelationKind.values) {
        for (final slope in [-1.0, 1.0]) {
          for (final n in [5, 8, 20]) {
            texts.add(
              CorrelationStatement.from(
                kind: kind,
                result: _result(n: n, slope: slope, r2: 0.8),
              ).text,
            );
          }
        }
        texts.add(
          CorrelationStatement.from(
            kind: kind,
            result: _result(n: 10, slope: 1, r2: 0.0),
          ).text,
        );
      }
      for (final t in texts) {
        expect(CausalLanguageGuard.firstViolation([t]), isNull, reason: t);
      }
      expect(CausalLanguageGuard.firstViolation(texts), isNull);
      final stated = texts.where((t) => !t.startsWith('No clear'));
      expect(stated, isNotEmpty);
      for (final t in stated) {
        expect(t, contains('tended to'));
      }
    });
  });
}
