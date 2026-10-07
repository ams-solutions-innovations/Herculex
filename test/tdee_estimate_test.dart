import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/nutrition/domain/tdee_estimate.dart';

TdeeEstimateResult _result({
  required TdeeMethod method,
  TdeeConfidence confidence = TdeeConfidence.medium,
  bool observedQualified = false,
}) {
  return TdeeEstimateResult(
    kcal: 2500,
    method: method,
    confidence: confidence,
    windowDays: 14,
    observedQualified: observedQualified,
    inputs: const {},
    estimatedAt: DateTime(2026, 9, 28),
  );
}

void main() {
  group('TdeeMethod.fromName', () {
    test('round-trips known names', () {
      expect(TdeeMethod.fromName('observed'), TdeeMethod.observed);
      expect(TdeeMethod.fromName('classifier'), TdeeMethod.classifier);
      expect(TdeeMethod.fromName('coldStart'), TdeeMethod.coldStart);
    });

    test('null and garbage fall back to coldStart', () {
      expect(TdeeMethod.fromName(null), TdeeMethod.coldStart);
      expect(TdeeMethod.fromName('garbage'), TdeeMethod.coldStart);
    });
  });

  group('TdeeConfidence.fromName', () {
    test('round-trips known names', () {
      expect(TdeeConfidence.fromName('high'), TdeeConfidence.high);
      expect(TdeeConfidence.fromName('medium'), TdeeConfidence.medium);
      expect(TdeeConfidence.fromName('low'), TdeeConfidence.low);
    });

    test('null and garbage fall back to low', () {
      expect(TdeeConfidence.fromName(null), TdeeConfidence.low);
      expect(TdeeConfidence.fromName('garbage'), TdeeConfidence.low);
    });

    test('labels are capitalised words', () {
      expect(TdeeConfidence.high.label, 'High');
      expect(TdeeConfidence.medium.label, 'Medium');
      expect(TdeeConfidence.low.label, 'Low');
    });
  });

  group('TdeeEstimateResult.badgeState', () {
    test('observed and qualified is measured', () {
      final r = _result(method: TdeeMethod.observed, observedQualified: true);
      expect(r.badgeState, TdeeBadgeState.measured);
      expect(r.isHeld, isFalse);
    });

    test('observed and not qualified is measuredAging', () {
      final r = _result(method: TdeeMethod.observed);
      expect(r.badgeState, TdeeBadgeState.measuredAging);
      expect(r.isHeld, isTrue);
    });

    test('classifier is classified', () {
      final r = _result(method: TdeeMethod.classifier);
      expect(r.badgeState, TdeeBadgeState.classified);
      expect(r.isHeld, isFalse);
    });

    test('coldStart is calibrating', () {
      final r = _result(method: TdeeMethod.coldStart);
      expect(r.badgeState, TdeeBadgeState.calibrating);
      expect(r.isHeld, isFalse);
    });
  });

  group('TdeeBadgeState.label', () {
    test('measured labels', () {
      expect(
        TdeeBadgeState.measured.label(TdeeConfidence.high),
        'Measured · High confidence',
      );
      expect(
        TdeeBadgeState.measured.label(TdeeConfidence.medium),
        'Measured · Medium confidence',
      );
    });

    test('measuredAging ignores confidence', () {
      for (final c in TdeeConfidence.values) {
        expect(
          TdeeBadgeState.measuredAging.label(c),
          'Measured · Aging estimate',
        );
      }
    });

    test('classified labels', () {
      expect(
        TdeeBadgeState.classified.label(TdeeConfidence.medium),
        'Classified · Medium confidence',
      );
      expect(
        TdeeBadgeState.classified.label(TdeeConfidence.low),
        'Classified · Low confidence',
      );
    });

    test('classified high is clamped to medium', () {
      expect(
        TdeeBadgeState.classified.label(TdeeConfidence.high),
        'Classified · Medium confidence',
      );
    });

    test('calibrating label is the locked D-08 wording', () {
      for (final c in TdeeConfidence.values) {
        expect(
          TdeeBadgeState.calibrating.label(c),
          'Calibrating — using onboarding estimate',
        );
      }
    });
  });
}
