import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/nutrition/domain/tdee_estimate.dart';
import 'package:herculex/features/weekly_report/domain/tdee_shift_calculator.dart';

TdeeEstimateResult _est(
  int kcal, {
  TdeeMethod method = TdeeMethod.observed,
  TdeeConfidence confidence = TdeeConfidence.medium,
}) => TdeeEstimateResult(
  kcal: kcal,
  method: method,
  confidence: confidence,
  windowDays: 28,
  observedQualified: true,
  inputs: const {},
  estimatedAt: DateTime(2026, 10, 1),
);

void main() {
  group('TdeeShiftCalculator materiality', () {
    test('delta of exactly 100 at 2500 is not material (5% is 125)', () {
      final s = TdeeShiftCalculator.compute(
        newest: _est(2600),
        before: _est(2500),
      )!;
      expect(s.material, isFalse);
      expect(s.deltaKcal, 100);
    });

    test('2500 -> 2640 is material and carries the section fields', () {
      final s = TdeeShiftCalculator.compute(
        newest: _est(2640, confidence: TdeeConfidence.high),
        before: _est(2500),
      )!;
      expect(s.oldKcal, 2500);
      expect(s.newKcal, 2640);
      expect(s.deltaKcal, 140);
      expect(s.material, isTrue);
      expect(s.confidence, 'high');
    });

    test('1500 -> 1610 is material (floor 100, 5% is 75)', () {
      final s = TdeeShiftCalculator.compute(
        newest: _est(1610),
        before: _est(1500),
      )!;
      expect(s.material, isTrue);
      expect(s.deltaKcal, 110);
    });

    test('1500 -> 1600 is not material: the boundary is strict', () {
      final s = TdeeShiftCalculator.compute(
        newest: _est(1600),
        before: _est(1500),
      )!;
      expect(s.material, isFalse);
      expect(s.deltaKcal, 100);
    });

    test('a downward shift is signed and judged by magnitude', () {
      final s = TdeeShiftCalculator.compute(
        newest: _est(2360),
        before: _est(2500),
      )!;
      expect(s.deltaKcal, -140);
      expect(s.material, isTrue);
    });

    test('a non-material shift still yields a section', () {
      final s = TdeeShiftCalculator.compute(
        newest: _est(2510),
        before: _est(2500),
      )!;
      expect(s.material, isFalse);
      expect(s.deltaKcal, 10);
    });
  });

  group('TdeeShiftCalculator no section', () {
    test('null without an earlier estimate', () {
      expect(
        TdeeShiftCalculator.compute(newest: _est(2600), before: null),
        isNull,
      );
    });

    test('null without a newest estimate', () {
      expect(
        TdeeShiftCalculator.compute(newest: null, before: _est(2600)),
        isNull,
      );
    });

    test('null when the newest estimate is a cold start', () {
      expect(
        TdeeShiftCalculator.compute(
          newest: _est(3000, method: TdeeMethod.coldStart),
          before: _est(2000),
        ),
        isNull,
      );
    });

    test('a cold-start earlier estimate is still a valid baseline', () {
      final s = TdeeShiftCalculator.compute(
        newest: _est(2700),
        before: _est(2400, method: TdeeMethod.coldStart),
      );
      expect(s, isNotNull);
      expect(s!.material, isTrue);
    });
  });
}
