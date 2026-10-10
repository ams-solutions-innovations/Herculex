import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/health/domain/sleep_recovery.dart';
import 'package:herculex/features/health/domain/sleep_summary.dart';

SleepSummary _night({
  required double asleepHours,
  double? inBedHours,
  double? deepShare,
  double? remShare,
  int? awakenings,
}) {
  final asleep = asleepHours * 60;
  return SleepSummary(
    inBedMinutes: (inBedHours ?? asleepHours) * 60,
    asleepMinutes: asleep,
    deepMinutes: deepShare == null ? null : asleep * deepShare,
    remMinutes: remShare == null ? null : asleep * remShare,
    lightMinutes: deepShare == null || remShare == null
        ? null
        : asleep * (1 - deepShare - remShare),
    awakenings: awakenings,
  );
}

void main() {
  group('SleepRecovery', () {
    test('no sleep data is no effect, never a penalty', () {
      expect(SleepRecovery.assess(null), isNull);
      expect(SleepRecovery.rateMultiplierFor(null), 1.0);
    });

    test('a full, well-structured night leaves recovery at baseline', () {
      final a = SleepRecovery.assess(
        _night(
          asleepHours: 8,
          inBedHours: 8.5,
          deepShare: 0.17,
          remShare: 0.22,
          awakenings: 1,
        ),
      )!;

      expect(a.score, greaterThanOrEqualTo(95));
      expect(a.rateMultiplier, 1.0);
    });

    test('a stage-less 7.5h night is not penalised for missing stages', () {
      final a = SleepRecovery.assess(_night(asleepHours: 7.5))!;

      expect(a.rateMultiplier, 1.0);
    });

    test('short sleep slows recovery, more so the shorter it is', () {
      final six = SleepRecovery.rateMultiplierFor(_night(asleepHours: 6));
      final five = SleepRecovery.rateMultiplierFor(_night(asleepHours: 5));
      final three = SleepRecovery.rateMultiplierFor(_night(asleepHours: 3));

      expect(six, lessThan(1.0));
      expect(five, lessThan(six));
      expect(three, lessThan(five));
    });

    test('poor structure slows recovery even at the same duration', () {
      final good = SleepRecovery.rateMultiplierFor(
        _night(
          asleepHours: 6,
          inBedHours: 6.4,
          deepShare: 0.17,
          remShare: 0.22,
          awakenings: 1,
        ),
      );
      final bad = SleepRecovery.rateMultiplierFor(
        _night(
          asleepHours: 6,
          inBedHours: 8,
          deepShare: 0.04,
          remShare: 0.08,
          awakenings: 7,
        ),
      );

      expect(bad, lessThan(good));
    });

    test('the multiplier is bounded to [0.75, 1.0] whatever the night', () {
      final worst = SleepRecovery.assess(
        _night(
          asleepHours: 1,
          inBedHours: 9,
          deepShare: 0,
          remShare: 0,
          awakenings: 20,
        ),
      )!;
      final best = SleepRecovery.assess(
        _night(asleepHours: 11, deepShare: 0.3, remShare: 0.3, awakenings: 0),
      )!;

      expect(worst.rateMultiplier, SleepRecovery.minRateMultiplier);
      expect(best.rateMultiplier, 1.0);
      expect(worst.score, inInclusiveRange(0, 100));
      expect(best.score, inInclusiveRange(0, 100));
    });

    test('a night with no sleep in it is not assessed', () {
      expect(
        SleepRecovery.assess(
          const SleepSummary(inBedMinutes: 60, asleepMinutes: 0),
        ),
        isNull,
      );
    });
  });
}
