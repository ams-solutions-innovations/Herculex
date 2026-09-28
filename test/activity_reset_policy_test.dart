import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/nutrition/domain/activity_reset_policy.dart';
import 'package:herculex/features/nutrition/domain/tdee_estimate.dart';

TdeeEstimateResult _row(TdeeMethod method, {bool qualified = false}) =>
    TdeeEstimateResult(
      kcal: 2500,
      method: method,
      confidence: TdeeConfidence.medium,
      windowDays: 28,
      observedQualified: qualified,
      inputs: const {},
      estimatedAt: DateTime(2026, 9, 1, 8),
    );

void main() {
  group('isCalibrated', () {
    test('null is not calibrated', () {
      expect(ActivityResetPolicy.isCalibrated(null), isFalse);
    });
    test('coldStart is not calibrated', () {
      expect(
        ActivityResetPolicy.isCalibrated(_row(TdeeMethod.coldStart)),
        isFalse,
      );
    });
    test('classifier is calibrated', () {
      expect(
        ActivityResetPolicy.isCalibrated(_row(TdeeMethod.classifier)),
        isTrue,
      );
    });
    test('observed fresh and held are calibrated', () {
      expect(
        ActivityResetPolicy.isCalibrated(
          _row(TdeeMethod.observed, qualified: true),
        ),
        isTrue,
      );
      expect(
        ActivityResetPolicy.isCalibrated(_row(TdeeMethod.observed)),
        isTrue,
      );
    });
  });

  group('isMeasured', () {
    test('null, coldStart and classifier are not measured', () {
      expect(ActivityResetPolicy.isMeasured(null), isFalse);
      expect(
        ActivityResetPolicy.isMeasured(_row(TdeeMethod.coldStart)),
        isFalse,
      );
      expect(
        ActivityResetPolicy.isMeasured(_row(TdeeMethod.classifier)),
        isFalse,
      );
    });
    test('observed qualified is measured', () {
      expect(
        ActivityResetPolicy.isMeasured(
          _row(TdeeMethod.observed, qualified: true),
        ),
        isTrue,
      );
    });
    test('observed held (aging) is not measured', () {
      expect(
        ActivityResetPolicy.isMeasured(_row(TdeeMethod.observed)),
        isFalse,
      );
    });
  });

  group('actionFor', () {
    test('same level never acts', () {
      expect(
        ActivityResetPolicy.actionFor(isSameLevel: true, calibrated: true),
        ActivityResetAction.none,
      );
      expect(
        ActivityResetPolicy.actionFor(isSameLevel: true, calibrated: false),
        ActivityResetAction.none,
      );
    });
    test('calibrating saves immediately', () {
      expect(
        ActivityResetPolicy.actionFor(isSameLevel: false, calibrated: false),
        ActivityResetAction.saveNow,
      );
    });
    test('calibrated asks for confirmation', () {
      expect(
        ActivityResetPolicy.actionFor(isSameLevel: false, calibrated: true),
        ActivityResetAction.confirm,
      );
    });
  });

  group('copy', () {
    test('captions', () {
      expect(
        ActivityResetPolicy.caption(calibrated: false),
        "Your starting estimate. We'll refine it automatically as you log.",
      );
      expect(
        ActivityResetPolicy.caption(calibrated: true),
        'Manual reset. Use this only if your routine changed a lot. '
        'It reseeds the estimate and keeps your history.',
      );
    });
    test('snackbars', () {
      expect(
        ActivityResetPolicy.snackbar(measured: true),
        'Saved. Your estimate stays measured from your logs.',
      );
      expect(
        ActivityResetPolicy.snackbar(measured: false),
        "Saved. We'll use this as the starting point at the next "
        'recalibration.',
      );
    });
    test('dialog strings', () {
      expect(ActivityResetPolicy.dialogTitle, 'Reset activity level?');
      expect(
        ActivityResetPolicy.dialogBody,
        "This becomes your new starting point. It won't erase your "
        'calibration history.',
      );
      expect(ActivityResetPolicy.keepLabel, 'Keep Current Level');
      expect(ActivityResetPolicy.resetLabel, 'Reset Activity Level');
    });
  });
}
