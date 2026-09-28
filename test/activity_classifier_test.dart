import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/nutrition/domain/activity_classifier.dart';
import 'package:herculex/features/nutrition/domain/tdee_estimate.dart';

List<double> _days(int n, double steps) => List<double>.filled(n, steps);

ActivityClassification _classify({
  required List<double> steps,
  double workouts = 0,
  double seed = 1.55,
  double? activeKcal,
  double? sleep,
  double? restingHr,
}) {
  return ActivityClassifier.classify(
    dailySteps: steps,
    workoutsPerWeek: workouts,
    seedMultiplier: seed,
    activeKcalPerDay: activeKcal,
    sleepHoursPerNight: sleep,
    restingHr: restingHr,
  );
}

void main() {
  group('step anchors', () {
    test('7500 steps over 14 days is 1.375 with zero seed weight', () {
      final c = _classify(steps: _days(14, 7500));
      expect(c.isAvailable, isTrue);
      expect(c.multiplier, closeTo(1.375, 1e-9));
      expect(c.seedWeight, 0);
    });

    test('anchor values map to their factors', () {
      expect(_classify(steps: _days(14, 3000)).multiplier, closeTo(1.20, 1e-9));
      expect(
        _classify(steps: _days(14, 10000)).multiplier,
        closeTo(1.55, 1e-9),
      );
      expect(
        _classify(steps: _days(14, 15000)).multiplier,
        closeTo(1.725, 1e-9),
      );
    });

    test('steps outside the anchor range are clamped', () {
      expect(_classify(steps: _days(14, 500)).multiplier, closeTo(1.20, 1e-9));
      expect(
        _classify(steps: _days(14, 25000)).multiplier,
        closeTo(1.725, 1e-9),
      );
    });

    test('midpoint of two anchors interpolates linearly', () {
      expect(
        _classify(steps: _days(14, 8750)).multiplier,
        closeTo(1.4625, 1e-9),
      );
    });
  });

  group('training bonus', () {
    test('3 workouts per week at 7500 steps gives 1.435', () {
      final c = _classify(steps: _days(14, 7500), workouts: 3);
      expect(c.multiplier, closeTo(1.435, 1e-9));
    });

    test('bonus is capped at 0.10', () {
      final nine = _classify(steps: _days(14, 7500), workouts: 9);
      expect(nine.multiplier, closeTo(1.475, 1e-9));
      final five = _classify(steps: _days(14, 7500), workouts: 5);
      expect(five.multiplier, closeTo(1.475, 1e-9));
    });
  });

  group('final clamp', () {
    test('multiplier never exceeds 1.90', () {
      final c = _classify(steps: _days(3, 7500), seed: 3.0);
      expect(c.multiplier, 1.90);
    });

    test('multiplier never drops below 1.15', () {
      final c = _classify(steps: _days(3, 7500), seed: 0.5);
      expect(c.multiplier, 1.15);
    });
  });

  group('seed blending', () {
    test('7 step days blend half data and half seed', () {
      final c = _classify(steps: _days(7, 7500), seed: 1.725);
      expect(c.multiplier, closeTo(1.55, 1e-9));
      expect(c.seedWeight, closeTo(0.5, 1e-9));
    });

    test('seed is ignored once 14 step days exist', () {
      final a = _classify(steps: _days(14, 7500), seed: 1.2);
      final b = _classify(steps: _days(14, 7500), seed: 1.9);
      expect(a.multiplier, b.multiplier);
    });
  });

  group('availability', () {
    test('fewer than 3 step days is unavailable', () {
      expect(_classify(steps: _days(2, 9000)).isAvailable, isFalse);
      expect(_classify(steps: const []).isAvailable, isFalse);
      expect(
        identical(
          _classify(steps: _days(2, 9000)),
          ActivityClassification.unavailable,
        ),
        isTrue,
      );
    });

    test('exactly 3 step days is available', () {
      expect(_classify(steps: _days(3, 9000)).isAvailable, isTrue);
    });

    test('unavailable sentinel has zeroed fields and low confidence', () {
      const u = ActivityClassification.unavailable;
      expect(u.isAvailable, isFalse);
      expect(u.multiplier, 0);
      expect(u.confidence, TdeeConfidence.low);
      expect(u.stepDays, 0);
    });
  });

  group('confidence', () {
    test('medium at 10 or more step days, low below', () {
      expect(
        _classify(steps: _days(10, 8000)).confidence,
        TdeeConfidence.medium,
      );
      expect(
        _classify(steps: _days(14, 8000)).confidence,
        TdeeConfidence.medium,
      );
      expect(_classify(steps: _days(9, 8000)).confidence, TdeeConfidence.low);
      expect(_classify(steps: _days(3, 8000)).confidence, TdeeConfidence.low);
    });

    test('never high for any input', () {
      for (final n in [3, 7, 10, 14, 30]) {
        for (final w in [0.0, 3.0, 10.0]) {
          final c = _classify(
            steps: _days(n, 12000),
            workouts: w,
            activeKcal: 900,
            sleep: 8,
            restingHr: 50,
          );
          expect(c.confidence, isNot(TdeeConfidence.high));
        }
      }
    });
  });

  group('recorded-only inputs', () {
    test('active kcal, sleep and resting HR never change the multiplier', () {
      final base = _classify(steps: _days(14, 9000), workouts: 2);
      final withExtras = _classify(
        steps: _days(14, 9000),
        workouts: 2,
        activeKcal: 1200,
        sleep: 4,
        restingHr: 90,
      );
      expect(withExtras.multiplier, base.multiplier);
      expect(withExtras.confidence, base.confidence);
    });
  });

  group('toInputs', () {
    test('always carries the used inputs', () {
      final inputs = _classify(steps: _days(14, 7500), workouts: 3).toInputs();
      expect(inputs['avg_steps'], 7500);
      expect(inputs['step_days'], 14);
      expect(inputs['workouts_per_week'], 3);
      expect(inputs['activity_factor'], 1.435);
      expect(inputs['seed_weight'], 0);
      expect(inputs.containsKey('active_kcal'), isFalse);
      expect(inputs.containsKey('sleep_hours'), isFalse);
      expect(inputs.containsKey('resting_hr'), isFalse);
    });

    test('activity_factor is rounded to 3 decimals', () {
      // 1.375 + (623 / 2500) * 0.175 = 1.41861
      final inputs = _classify(steps: _days(14, 8123)).toInputs();
      expect(inputs['activity_factor'], 1.419);
    });

    test('recorded-only keys appear only when non-null', () {
      final inputs = _classify(
        steps: _days(14, 7500),
        activeKcal: 450,
        sleep: 7.5,
        restingHr: 58,
      ).toInputs();
      expect(inputs['active_kcal'], 450);
      expect(inputs['sleep_hours'], 7.5);
      expect(inputs['resting_hr'], 58);
    });
  });
}
