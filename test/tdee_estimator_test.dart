import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/nutrition/domain/activity_classifier.dart';
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

  // ---------------------------------------------------------------------
  // Task 2: recalibrate, shouldRecalibrate, isMaterialShift
  // ---------------------------------------------------------------------

  const steadyWeigh = [
    -27, -25, -23, -21, -19, -17, -15, -13, -11, -9, -7, -5, -3, -1, 0, //
  ];

  final classification = ActivityClassifier.classify(
    dailySteps: List.filled(14, 8000.0),
    workoutsPerWeek: 3,
    seedMultiplier: 1.375,
  );
  const bmr = 1800.0;
  const seedKcal = 2400.0;
  const seedInputs = <String, Object?>{'seed': true};

  TdeeEstimateResult row({
    required TdeeMethod method,
    required bool qualified,
    required int ageDays,
    int kcal = 2300,
    int windowDays = 14,
    Map<String, Object?> inputs = const {},
    DateTime? base,
  }) => TdeeEstimateResult(
    kcal: kcal,
    method: method,
    confidence: TdeeConfidence.medium,
    windowDays: windowDays,
    observedQualified: qualified,
    inputs: inputs,
    estimatedAt: day(-ageDays, base),
  );

  /// Recalibrates at [at]. By default the data qualifies for observed mode;
  /// pass `qualifying: false` for no data, or explicit [food] / [weigh]
  /// offsets (relative to [at]).
  TdeeEstimateResult recal({
    required DateTime at,
    List<TdeeEstimateResult> history = const [],
    bool qualifying = true,
    Iterable<int>? food,
    Iterable<int>? weigh,
    ActivityClassification? classified,
  }) {
    final f = food ?? (qualifying ? range(-27, 0) : const <int>[]);
    final w = weigh ?? (qualifying ? steadyWeigh : const <int>[]);
    return TdeeEstimator.recalibrate(
      asOf: at,
      foodLoggedDays: {for (final o in f) iso(day(o, at))},
      dailyKcalByDate: {for (final o in f) iso(day(o, at)): 2500.0},
      weightLogs: [for (final o in w) WeightLog(day(o, at), 80)],
      classification: classified ?? classification,
      bmrKcal: bmr,
      seedMaintenanceKcal: seedKcal,
      seedInputs: seedInputs,
      history: history,
    );
  }

  final classifierKcal = (bmr * classification.multiplier).round();

  group('recalibrate: promotion and hysteresis (D-03)', () {
    test('qualifying with empty history is not promoted', () {
      final r = recal(at: asOf);
      expect(r.method, TdeeMethod.classifier);
      expect(r.observedQualified, isTrue);
      expect(r.kcal, classifierKcal);
      expect(r.estimatedAt, asOf);
    });

    test('qualifying with empty history and no classifier is cold start', () {
      final r = recal(at: asOf, classified: ActivityClassification.unavailable);
      expect(r.method, TdeeMethod.coldStart);
      expect(r.observedQualified, isTrue);
      expect(r.kcal, seedKcal.round());
      expect(r.confidence, TdeeConfidence.low);
      expect(r.windowDays, 0);
      expect(r.inputs, seedInputs);
    });

    test('a qualified row at least 7 days old promotes', () {
      for (final age in [7, 20]) {
        final r = recal(
          at: asOf,
          history: [
            row(method: TdeeMethod.classifier, qualified: true, ageDays: age),
          ],
        );
        expect(r.method, TdeeMethod.observed, reason: 'age $age');
        expect(r.observedQualified, isTrue);
        expect(r.kcal, 2500);
        expect(r.windowDays, 35);
        expect(r.inputs['span_days'], 27);
      }
    });

    test('a coldStart qualified row promotes too', () {
      final r = recal(
        at: asOf,
        history: [
          row(method: TdeeMethod.coldStart, qualified: true, ageDays: 8),
        ],
      );
      expect(r.method, TdeeMethod.observed);
    });

    test('a qualified row 1 or 6 days old does not promote', () {
      for (final age in [1, 6]) {
        final r = recal(
          at: asOf,
          history: [
            row(method: TdeeMethod.classifier, qualified: true, ageDays: age),
          ],
        );
        expect(r.method, TdeeMethod.classifier, reason: 'age $age');
        expect(r.observedQualified, isTrue, reason: 'pending promotion');
      }
    });

    test('an unqualified previous row does not promote', () {
      final r = recal(
        at: asOf,
        history: [
          row(method: TdeeMethod.classifier, qualified: false, ageDays: 10),
        ],
      );
      expect(r.method, TdeeMethod.classifier);
      expect(r.observedQualified, isTrue);
    });

    test('two qualifying runs one day apart never promote', () {
      final r0 = recal(at: day(0));
      final r1 = recal(at: day(1), history: [r0]);
      expect(r1.method, isNot(TdeeMethod.observed));
      expect(r1.observedQualified, isTrue);
    });

    test('two qualifying runs 7 days apart promote', () {
      final r0 = recal(at: day(0));
      final r7 = recal(at: day(7), history: [r0]);
      expect(r7.method, TdeeMethod.observed);
    });

    test('a forced run restarts the 7-day clock', () {
      final r0 = recal(at: day(0));
      final r1 = recal(at: day(1), history: [r0]); // forced run
      // Day 7 sees the day-1 row only 6 days old.
      final r7 = recal(at: day(7), history: [r1, r0]);
      expect(r7.method, isNot(TdeeMethod.observed));
      // With the day-1 row as the newest, day 8 is exactly 7 days later.
      final r8 = recal(at: day(8), history: [r1, r0]);
      expect(r8.method, TdeeMethod.observed);
      // When the day-7 run is persisted, the next promotion is day 14.
      final r14 = recal(at: day(14), history: [r7, r1, r0]);
      expect(r14.method, TdeeMethod.observed);
    });

    test('an already-observed user stays observed and fresh at once', () {
      final r = recal(
        at: asOf,
        history: [
          row(
            method: TdeeMethod.observed,
            qualified: true,
            ageDays: 7,
            kcal: 2200,
          ),
        ],
      );
      expect(r.method, TdeeMethod.observed);
      expect(r.observedQualified, isTrue);
      expect(r.kcal, 2500);
      expect(r.isHeld, isFalse);
    });

    test('a held observed row also recovers to fresh when data qualifies', () {
      final r = recal(
        at: asOf,
        history: [
          row(method: TdeeMethod.observed, qualified: false, ageDays: 3),
          row(method: TdeeMethod.observed, qualified: true, ageDays: 10),
        ],
      );
      expect(r.method, TdeeMethod.observed);
      expect(r.observedQualified, isTrue);
    });
  });

  group('recalibrate: hold, grace and fallback (D-04)', () {
    test('holds the fresh observed estimate while it is under 14 days old', () {
      for (final age in [7, 13]) {
        final r = recal(
          at: asOf,
          qualifying: false,
          history: [
            row(
              method: TdeeMethod.observed,
              qualified: true,
              ageDays: age,
              kcal: 2650,
              windowDays: 28,
              inputs: const {'span_days': 20},
            ),
          ],
        );
        expect(r.method, TdeeMethod.observed, reason: 'age $age');
        expect(r.observedQualified, isFalse);
        expect(r.isHeld, isTrue);
        expect(r.kcal, 2650);
        expect(r.confidence, TdeeConfidence.low);
        expect(r.windowDays, 28);
        expect(r.inputs['held'], isTrue);
        expect(r.inputs['measured_at'], iso(day(-age)));
        expect(r.inputs['span_days'], 20);
        expect(r.estimatedAt, asOf);
      }
    });

    test('falls back once the fresh row is 14 days old', () {
      final r = recal(
        at: asOf,
        qualifying: false,
        history: [
          row(method: TdeeMethod.observed, qualified: true, ageDays: 14),
        ],
      );
      expect(r.method, TdeeMethod.classifier);
      expect(r.observedQualified, isFalse);
      expect(r.kcal, classifierKcal);
    });

    test('falls back to cold start when the classifier is unavailable', () {
      final r = recal(
        at: asOf,
        qualifying: false,
        classified: ActivityClassification.unavailable,
        history: [
          row(method: TdeeMethod.observed, qualified: true, ageDays: 20),
        ],
      );
      expect(r.method, TdeeMethod.coldStart);
      expect(r.observedQualified, isFalse);
    });

    test('consecutive held rows keep the same measured_at', () {
      final fresh = row(
        method: TdeeMethod.observed,
        qualified: true,
        ageDays: 10,
        kcal: 2600,
      );
      final held1 = row(
        method: TdeeMethod.observed,
        qualified: false,
        ageDays: 3,
        kcal: 2600,
        inputs: {'held': true, 'measured_at': iso(day(-10))},
      );
      final r = recal(at: asOf, qualifying: false, history: [held1, fresh]);
      expect(r.method, TdeeMethod.observed);
      expect(r.isHeld, isTrue);
      expect(r.inputs['measured_at'], iso(day(-10)));
      expect(r.kcal, 2600);
    });

    test('a held row with no fresh observed row behind it falls back', () {
      final r = recal(
        at: asOf,
        qualifying: false,
        history: [
          row(method: TdeeMethod.observed, qualified: false, ageDays: 2),
        ],
      );
      expect(r.method, TdeeMethod.classifier);
    });

    test('no observed rows: classifier when available, else cold start', () {
      final c = recal(at: asOf, qualifying: false);
      expect(c.method, TdeeMethod.classifier);
      expect(c.observedQualified, isFalse);
      expect(c.kcal, classifierKcal);
      expect(c.confidence, classification.confidence);
      expect(c.windowDays, ActivityClassifier.windowDays);
      expect(c.inputs, classification.toInputs());

      final s = recal(
        at: asOf,
        qualifying: false,
        classified: ActivityClassification.unavailable,
      );
      expect(s.method, TdeeMethod.coldStart);
      expect(s.kcal, seedKcal.round());
    });
  });

  group('recalibrate: recency composes with the grace period', () {
    // Dense food ending [foodEnd] days from asOf, weigh-ins through asOf.
    TdeeEstimateResult stale({required int foodEnd, required int freshAge}) =>
        recal(
          at: asOf,
          food: range(foodEnd - 34, foodEnd),
          weigh: everySecondDayEndingAt(0),
          history: [
            row(
              method: TdeeMethod.observed,
              qualified: true,
              ageDays: freshAge,
              kcal: 2400,
            ),
          ],
        );

    test('newest food 7 days old: fresh row 7 days old is held', () {
      final r = stale(foodEnd: -7, freshAge: 7);
      expect(r.method, TdeeMethod.observed);
      expect(r.observedQualified, isFalse);
      expect(r.inputs['measured_at'], iso(day(-7)));
    });

    test('newest food 7 days old: fresh row 14 days old falls back', () {
      final r = stale(foodEnd: -7, freshAge: 14);
      expect(r.method, TdeeMethod.classifier);
      expect(r.observedQualified, isFalse);
    });

    test('newest food 6 days old: stays observed and fresh', () {
      final r = stale(foodEnd: -6, freshAge: 7);
      expect(r.method, TdeeMethod.observed);
      expect(r.observedQualified, isTrue);
    });
  });

  group('shouldRecalibrate', () {
    TdeeEstimateResult last(int ageDays, {DateTime? at}) => TdeeEstimateResult(
      kcal: 2400,
      method: TdeeMethod.classifier,
      confidence: TdeeConfidence.medium,
      windowDays: 14,
      observedQualified: false,
      inputs: const {},
      estimatedAt: day(-ageDays, at),
    );

    RecalibrationReason check({
      required List<TdeeEstimateResult> history,
      List<WeightLog> weights = const [],
      Map<String, double> steps = const {},
      bool force = false,
      DateTime? at,
    }) => TdeeEstimator.shouldRecalibrate(
      asOf: at ?? asOf,
      history: history,
      weightLogs: weights,
      stepsByDate: steps,
      force: force,
    );

    test('empty history needs an estimate', () {
      expect(check(history: const []), RecalibrationReason.noEstimate);
    });

    test('force overrides the once-per-day gate', () {
      expect(
        check(history: [last(0)], force: true),
        RecalibrationReason.forced,
      );
    });

    test('a row from the same calendar day blocks everything else', () {
      final sameDay = TdeeEstimateResult(
        kcal: 2400,
        method: TdeeMethod.classifier,
        confidence: TdeeConfidence.medium,
        windowDays: 14,
        observedQualified: false,
        inputs: const {},
        estimatedAt: DateTime(2026, 9, 28, 6),
      );
      expect(
        check(
          history: [sameDay],
          at: DateTime(2026, 9, 28, 22),
          weights: [WeightLog(day(-1), 80), WeightLog(day(0), 95)],
        ),
        RecalibrationReason.none,
      );
    });

    test('elapsed fires at 7 days, not at 6', () {
      expect(check(history: [last(7)]), RecalibrationReason.elapsed);
      expect(check(history: [last(6)]), RecalibrationReason.none);
    });

    test('a trend shift of 1.0 kg fires, 0.9 kg does not', () {
      // Trend on the last row's day is 80; one day later it moves by
      // alpha * (weigh-in - 80).
      RecalibrationReason withWeight(double kg) => check(
        history: [last(1)],
        weights: [WeightLog(day(-1), 80), WeightLog(day(0), kg)],
      );
      expect(withWeight(90), RecalibrationReason.weightTrendShift);
      expect(withWeight(89), RecalibrationReason.none);
      expect(withWeight(70), RecalibrationReason.weightTrendShift);
    });

    test('weight shift needs at least two logs', () {
      expect(
        check(history: [last(1)], weights: [WeightLog(day(0), 95)]),
        RecalibrationReason.none,
      );
    });

    Map<String, double> steps(Map<int, double> byOffset) => {
      for (final e in byOffset.entries) iso(day(e.key)): e.value,
    };

    test('a 25% step-count shift fires, 24.9% does not', () {
      // Last row 6 days ago: previous window is [-19, -6], current [-13, 0].
      final prev = {-19: 8000.0, -18: 8000.0, -17: 8000.0};
      expect(
        check(
          history: [last(6)],
          steps: steps({...prev, -3: 10000, -2: 10000, -1: 10000, 0: 10000}),
        ),
        RecalibrationReason.activityShift,
      );
      expect(
        check(
          history: [last(6)],
          steps: steps({...prev, -3: 9990, -2: 9990, -1: 9990, 0: 9990}),
        ),
        RecalibrationReason.none,
      );
    });

    test('step shift needs 3 step days in each window', () {
      expect(
        check(
          history: [last(6)],
          steps: steps({-19: 8000, -18: 8000, -17: 8000, -1: 20000, 0: 20000}),
        ),
        RecalibrationReason.none,
      );
      expect(
        check(
          history: [last(6)],
          steps: steps({-19: 8000, -18: 8000, -2: 20000, -1: 20000, 0: 20000}),
        ),
        RecalibrationReason.none,
      );
    });
  });

  group('isMaterialShift (D-09)', () {
    bool material(int current, int next) => TdeeEstimator.isMaterialShift(
      currentBaselineKcal: current,
      newEstimateKcal: next,
    );

    test('2000: 5 percent ties with the 100 floor, strictly greater wins', () {
      expect(material(2000, 2100), isFalse);
      expect(material(2000, 2101), isTrue);
    });

    test('1500: the 100 floor beats 5 percent (75)', () {
      expect(material(1500, 1600), isFalse);
      expect(material(1500, 1601), isTrue);
    });

    test('3000: 5 percent (150) beats the floor', () {
      expect(material(3000, 3150), isFalse);
      expect(material(3000, 3151), isTrue);
    });

    test('works for a negative delta', () {
      expect(material(3000, 2850), isFalse);
      expect(material(3000, 2849), isTrue);
      expect(material(2000, 1900), isFalse);
      expect(material(2000, 1899), isTrue);
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
