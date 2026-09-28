import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/nutrition/domain/tdee_estimate.dart';
import 'package:herculex/features/nutrition/domain/tdee_estimator.dart';

/// Fixed reference date. Nothing in these tests reads the wall clock.
final DateTime asOf = DateTime(2026, 9, 28);

/// The calendar day [offset] days from [asOf] (0 = asOf, -27 = 27 days before).
DateTime day(int offset, [DateTime? base]) {
  final b = base ?? asOf;
  return DateTime(b.year, b.month, b.day + offset);
}

String iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

Set<String> foodDays(Iterable<int> offsets) => {
  for (final o in offsets) iso(day(o)),
};

Map<String, double> kcalFor(Iterable<int> offsets, double kcal) => {
  for (final o in offsets) iso(day(o)): kcal,
};

List<WeightLog> weighIns(Iterable<int> offsets, {double kg = 80}) => [
  for (final o in offsets) WeightLog(day(o), kg),
];

Iterable<int> range(int from, int to) => [for (var i = from; i <= to; i++) i];

/// Weigh-in offsets ending at [end] going back every second day for [count]
/// entries, so the newest weigh-in sits exactly on [end].
List<int> everySecondDayEndingAt(int end, {int count = 18}) => [
  for (var i = 0; i < count; i++) end - 2 * i,
];

ObservedEstimate? observed({
  required Iterable<int> food,
  required Iterable<int> weigh,
  double kcal = 2500,
  double kg = 80,
  DateTime? at,
}) {
  final when = at ?? asOf;
  return TdeeEstimator.estimateObserved(
    asOf: when,
    foodLoggedDays: foodDays(food),
    dailyKcalByDate: kcalFor(food, kcal),
    weightLogs: weighIns(weigh, kg: kg),
  );
}

/// 28 consecutive food days ending on [asOf], weigh-ins every second day from
/// the first day plus the last day (15 logs).
ObservedEstimate? steady28({DateTime? at}) => observed(
  food: range(-27, 0),
  weigh: [
    ...[for (var i = 0; i < 14; i++) -27 + 2 * i],
    0,
  ],
  at: at,
);

void main() {
  group('TrendSeries', () {
    test('interpolates gaps and smooths with alpha 0.1', () {
      final s = TrendSeries.fromLogs([
        WeightLog(day(0), 80.0),
        WeightLog(day(2), 82.0),
      ]);
      expect(s.valueOn(day(0)), closeTo(80.0, 1e-9));
      // day 1 interpolates to 81: 80 + 0.1 * (81 - 80)
      expect(s.valueOn(day(1)), closeTo(80.1, 1e-9));
      // day 2: 80.1 + 0.1 * (82 - 80.1)
      expect(s.valueOn(day(2)), closeTo(80.29, 1e-9));
    });

    test('is flat before the first and after the last log', () {
      final s = TrendSeries.fromLogs([
        WeightLog(day(0), 80.0),
        WeightLog(day(2), 82.0),
      ]);
      expect(s.valueOn(day(-5)), 80.0);
      expect(s.valueOn(day(9)), closeTo(80.29, 1e-9));
    });

    test('keeps the later of two logs on the same date', () {
      final s = TrendSeries.fromLogs([
        WeightLog(DateTime(2026, 9, 28, 20), 81.0),
        WeightLog(DateTime(2026, 9, 28, 7), 79.0),
      ]);
      expect(s.valueOn(day(0)), 81.0);
      final t = TrendSeries.fromLogs([
        WeightLog(day(0), 79.0),
        WeightLog(day(0), 81.0),
      ]);
      expect(t.valueOn(day(0)), 81.0);
    });

    test('an empty list yields an empty series', () {
      expect(TrendSeries.fromLogs(const []).isEmpty, isTrue);
    });

    test('firstDate and lastDate are date-only', () {
      final s = TrendSeries.fromLogs([
        WeightLog(DateTime(2026, 9, 20, 13, 30), 80),
        WeightLog(DateTime(2026, 9, 25, 6), 80),
      ]);
      expect(s.firstDate, DateTime(2026, 9, 20));
      expect(s.lastDate, DateTime(2026, 9, 25));
    });
  });

  group('estimateObserved: formula and window selection', () {
    test('steady state: 28 dense days picks the 35-day candidate', () {
      final e = steady28()!;
      expect(e.kcal, 2500);
      expect(e.windowDays, 35);
      expect(e.spanDays, 27);
      expect(e.loggedDaysInSpan, 28);
      final inputs = e.toInputs();
      expect(inputs['window_days'], 35);
      expect(inputs['span_days'], 27);
      expect(inputs['logged_days'], 28);
    });

    test('24 dense days fails the 35-day food gate and picks 28', () {
      final e = observed(
        food: range(-23, 0),
        weigh: [
          ...[for (var i = 0; i < 12; i++) -23 + 2 * i],
          0,
        ],
      )!;
      expect(e.windowDays, 28);
      expect(e.spanDays, 23);
      expect(e.kcal, 2500);
    });

    test('data dense only for the last 14 days picks 14 despite old data', () {
      final e = observed(
        food: [...range(-13, 0), -30, -25],
        weigh: everySecondDayEndingAt(0, count: 18),
      )!;
      expect(e.windowDays, 14);
    });

    test('data failing every window returns null', () {
      // 9 of the last 14 days logged: 64% < 70%.
      final e = observed(
        food: [...range(-12, -9), ...range(-4, 0)],
        weigh: everySecondDayEndingAt(0, count: 10),
      );
      expect(e, isNull);
    });

    test('mean intake is over logged days only', () {
      final e = observed(
        food: [...range(-13, -9), ...range(-4, 0)],
        weigh: [-13, -10, -7, -4, -1, 0],
        kcal: 2000,
      )!;
      expect(e.windowDays, 14);
      expect(e.kcal, 2000);
      expect(e.meanIntakeKcal, 2000);
      expect(e.loggedDaysInSpan, 10);
      expect(e.confidence, TdeeConfidence.medium);
    });

    test('food gate is 70%: 9 of 14 fails, 10 of 14 passes', () {
      final weigh = [-13, -10, -7, -4, -1, 0];
      expect(
        observed(food: [...range(-12, -9), ...range(-4, 0)], weigh: weigh),
        isNull,
      );
      expect(
        observed(food: [...range(-13, -9), ...range(-4, 0)], weigh: weigh),
        isNotNull,
      );
    });

    test('a logged day with 0 kcal still counts as logged', () {
      final food = [...range(-13, -9), ...range(-4, 0)];
      final kcal = kcalFor(food, 2200)..[iso(day(0))] = 0;
      final e = TdeeEstimator.estimateObserved(
        asOf: asOf,
        foodLoggedDays: foodDays(food),
        dailyKcalByDate: kcal,
        weightLogs: weighIns([-13, -10, -7, -4, -1, 0]),
      )!;
      expect(e.loggedDaysInSpan, 10);
      expect(e.kcal, 1980);
    });

    test('a falling trend raises TDEE above intake, rising lowers it', () {
      List<WeightLog> ramp(double from, double to) => [
        for (var i = 0; i <= 13; i += 1)
          WeightLog(day(i - 13), from + (to - from) * i / 13),
      ];
      final falling = ramp(80.0, 79.5);
      final fEst = TdeeEstimator.estimateObserved(
        asOf: asOf,
        foodLoggedDays: foodDays(range(-13, 0)),
        dailyKcalByDate: kcalFor(range(-13, 0), 2000),
        weightLogs: falling,
      )!;
      final series = TrendSeries.fromLogs(falling);
      final delta = series.valueOn(day(0)) - series.valueOn(day(-13));
      expect(delta, lessThan(0));
      expect(fEst.windowDays, 14);
      expect(fEst.kcal, (2000 - delta * 7700 / 13).round());
      expect(fEst.kcal, greaterThan(2000));

      final gEst = TdeeEstimator.estimateObserved(
        asOf: asOf,
        foodLoggedDays: foodDays(range(-13, 0)),
        dailyKcalByDate: kcalFor(range(-13, 0), 2000),
        weightLogs: ramp(80.0, 80.5),
      )!;
      expect(gEst.kcal, lessThan(2000));
    });

    test('the two gates are independent: dense food, thin weigh-ins', () {
      final food = range(-13, 0);
      // 3 weigh-ins: fails the 4 minimum.
      expect(observed(food: food, weigh: [-13, -6, 0]), isNull);
      // 4 weigh-ins but none in the first half of the window.
      expect(observed(food: food, weigh: [-6, -4, -2, 0]), isNull);
      // 4 weigh-ins with one in each half passes.
      expect(observed(food: food, weigh: [-13, -8, -4, 0]), isNotNull);
    });

    test('weigh-in minimum scales with the window', () {
      // 21 food days pass the 28-day food gate (21 >= 20) but 7 weigh-ins
      // fail its 8 minimum. The 21-day window needs 6 and passes.
      final e = observed(
        food: range(-20, 0),
        weigh: [-20, -17, -14, -11, -8, -4, 0],
      );
      expect(e!.windowDays, 21);
    });

    test('inputs carry the documented keys and span_days is an int', () {
      final inputs = steady28()!.toInputs();
      for (final key in [
        'mean_intake_kcal',
        'logged_days',
        'window_days',
        'span_days',
        'weight_trend_delta_kg',
        'weigh_ins',
      ]) {
        expect(inputs.containsKey(key), isTrue, reason: key);
      }
      expect(inputs['span_days'], isA<int>());
      expect(
        inputs['logged_days'] as int,
        lessThanOrEqualTo((inputs['span_days'] as int) + 1),
      );
    });

    test('confidence is high with dense coverage and enough weigh-ins', () {
      expect(steady28()!.confidence, TdeeConfidence.high);
    });
  });

  group('estimateObserved: recency rule', () {
    // 35-day dense food ending at foodEnd, weigh-ins every second day ending
    // at weighEnd, both otherwise dense enough for every other gate.
    ObservedEstimate? recency({
      required int foodEnd,
      required int weighEnd,
      Iterable<int> extraFood = const [],
      Iterable<int> extraWeigh = const [],
      DateTime? at,
    }) => observed(
      food: [...range(foodEnd - 34, foodEnd), ...extraFood],
      weigh: [...everySecondDayEndingAt(weighEnd, count: 18), ...extraWeigh],
      at: at,
    );

    test('control: newest data 6 days old passes', () {
      expect(recency(foodEnd: -6, weighEnd: -6), isNotNull);
    });

    test('newest food and weigh-in both 7 days old fails', () {
      expect(recency(foodEnd: -7, weighEnd: -7), isNull);
    });

    test('food through asOf: weigh-in 7 days old fails, 6 passes', () {
      expect(recency(foodEnd: 0, weighEnd: -7), isNull);
      expect(recency(foodEnd: 0, weighEnd: -6), isNotNull);
    });

    test('weigh-ins through asOf: food 7 days old fails, 6 passes', () {
      expect(recency(foodEnd: -7, weighEnd: 0), isNull);
      expect(recency(foodEnd: -6, weighEnd: 0), isNotNull);
    });

    test('no food or no weigh-in inside the recency range fails', () {
      expect(observed(food: const [], weigh: range(-20, 0)), isNull);
      expect(observed(food: range(-20, 0), weigh: const []), isNull);
    });

    test('data dated after asOf never counts as recent', () {
      expect(
        recency(
          foodEnd: -7,
          weighEnd: -7,
          extraFood: [1, 2, 3],
          extraWeigh: [1, 2],
        ),
        isNull,
      );
    });

    test('time of day is ignored', () {
      final early = steady28(at: DateTime(2026, 9, 28, 0, 5))!;
      final late = steady28(at: DateTime(2026, 9, 28, 23, 55))!;
      expect(early.kcal, late.kcal);
      expect(early.windowDays, late.windowDays);
      expect(early.toInputs(), late.toInputs());
    });
  });

  group('estimateObserved: sanity rails', () {
    test('mean intake below 800 kcal returns null', () {
      expect(
        observed(
          food: range(-27, 0),
          weigh: [
            ...[for (var i = 0; i < 14; i++) -27 + 2 * i],
            0,
          ],
          kcal: 700,
        ),
        isNull,
      );
    });

    test('TDEE below 1000 or above 6000 returns null', () {
      final weigh = [
        ...[for (var i = 0; i < 14; i++) -27 + 2 * i],
        0,
      ];
      expect(observed(food: range(-27, 0), weigh: weigh, kcal: 900), isNull);
      expect(observed(food: range(-27, 0), weigh: weigh, kcal: 6500), isNull);
      expect(
        observed(food: range(-27, 0), weigh: weigh, kcal: 1000),
        isNotNull,
      );
      expect(
        observed(food: range(-27, 0), weigh: weigh, kcal: 6000),
        isNotNull,
      );
    });
  });
}
