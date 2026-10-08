import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/nutrition/domain/tdee_trend.dart';
import 'package:herculex/features/physique/domain/physique_series.dart';
import 'package:herculex/features/physique/domain/physique_strength_series.dart';
import 'package:herculex/features/programs/domain/primary_lift_specialization.dart';
import 'package:herculex/features/programs/domain/programming_models.dart';

List<WeightLog> _linear(DateTime start, int days, double from, double to) => [
  for (var i = 0; i <= days; i++)
    WeightLog(
      DateTime(start.year, start.month, start.day + i),
      from + (to - from) * i / days,
    ),
];

void main() {
  final now = DateTime(2026, 10, 1);

  group('ChartRange', () {
    test('labels and window start', () {
      expect(ChartRange.month.label, '1M');
      expect(ChartRange.quarter.label, '3M');
      expect(ChartRange.all.label, 'All');
      expect(ChartRange.month.windowStart(now), DateTime(2026, 9, 1));
      expect(ChartRange.quarter.windowStart(now), DateTime(2026, 7, 3));
      expect(ChartRange.all.windowStart(now), isNull);
    });

    test('default range', () {
      expect(
        ChartRange.defaultFor(goalStartedAt: DateTime(2026, 9, 10), now: now),
        ChartRange.all,
      );
      expect(
        ChartRange.defaultFor(goalStartedAt: DateTime(2026, 8, 1), now: now),
        ChartRange.quarter,
      );
    });
  });

  group('weight series', () {
    test('empty and single point do not throw', () {
      for (final logs in [
        <WeightLog>[],
        [WeightLog(DateTime(2026, 9, 1), 80)],
      ]) {
        final d = PhysiqueSeriesBuilder.weight(
          logs: logs,
          now: now,
          range: ChartRange.all,
          goalStartedAt: DateTime(2026, 9, 1),
          phases: const [],
        );
        expect(d.trend, isEmpty);
        expect(d.isSparse, isTrue);
      }
    });

    test('window limits trend and raw points', () {
      final logs = _linear(DateTime(2026, 6, 1), 120, 90, 80);
      final d = PhysiqueSeriesBuilder.weight(
        logs: logs,
        now: now,
        range: ChartRange.month,
        goalStartedAt: DateTime(2026, 6, 1),
        phases: const [],
      );
      expect(d.trend.first.date, DateTime(2026, 9, 1));
      expect(d.raw.first.date, DateTime(2026, 9, 1));
      expect(d.raw.length, d.trend.length);
      expect(d.textSummary, startsWith('Down '));
      expect(d.textSummary, endsWith('kg over 1 month.'));
    });

    test('summary wording', () {
      WeightChartData build(double from, double to, ChartRange r) =>
          PhysiqueSeriesBuilder.weight(
            logs: _linear(DateTime(2026, 6, 1), 120, from, to),
            now: now,
            range: r,
            goalStartedAt: DateTime(2026, 6, 1),
            phases: const [],
          );
      expect(
        build(80, 80, ChartRange.quarter).textSummary,
        'No change over 3 months.',
      );
      expect(build(80, 90, ChartRange.quarter).textSummary, startsWith('Up '));
      expect(
        build(80, 90, ChartRange.quarter).textSummary,
        endsWith('over 3 months.'),
      );
    });

    test('phase bands: target ramp, flat maintain, ordered', () {
      final d = PhysiqueSeriesBuilder.weight(
        logs: _linear(DateTime(2026, 8, 1), 60, 85, 82),
        now: now,
        range: ChartRange.all,
        goalStartedAt: DateTime(2026, 8, 1),
        phases: [
          PhaseBandInput(
            phase: DietPhase.cut,
            plannedWeeks: 4,
            startedAt: DateTime(2026, 8, 1),
            startWeightKg: 85,
            targetWeightKg: 80,
          ),
          PhaseBandInput(
            phase: DietPhase.maintain,
            plannedWeeks: 4,
            startedAt: DateTime(2026, 8, 29),
            startWeightKg: 80,
            targetWeightKg: 90,
          ),
          const PhaseBandInput(phase: DietPhase.bulk, plannedWeeks: 4),
        ],
      );
      expect(d.bands.length, 2);
      final cut = d.bands[0];
      expect(cut.end, DateTime(2026, 8, 29));
      expect(cut.startLowKg, 84);
      expect(cut.startHighKg, 86);
      expect(cut.endLowKg, 79);
      expect(cut.endHighKg, 81);
      final maintain = d.bands[1];
      expect(maintain.endLowKg, 79);
      expect(maintain.endHighKg, 81);
    });
  });

  group('plan projection', () {
    // Weighs in daily to 2026-09-30 (82 kg); the plan has stops after that.
    WeightChartData build(
      List<ChartPoint> stops, {
      ChartRange range = ChartRange.all,
      List<WeightLog>? logs,
    }) => PhysiqueSeriesBuilder.weight(
      logs: logs ?? _linear(DateTime(2026, 8, 1), 60, 85, 82),
      now: now,
      range: range,
      goalStartedAt: DateTime(2026, 8, 1),
      phases: const [],
      planStops: stops,
    );

    final oct28 = ChartPoint(DateTime(2026, 10, 28), 80);
    final dec30 = ChartPoint(DateTime(2026, 12, 30), 80);
    final mar1 = ChartPoint(DateTime(2027, 3, 1), 84);

    test('starts at the last weigh-in and follows every stop', () {
      final d = build([oct28, dec30, mar1]);
      expect(d.projection.first.date, d.trend.last.date);
      expect(d.projection.first.value, d.trend.last.value);
      expect(d.projection.map((p) => p.date), [
        DateTime(2026, 9, 30),
        DateTime(2026, 10, 28),
        DateTime(2026, 12, 30),
        DateTime(2027, 3, 1),
      ]);
      expect(d.projection.last.value, 84);
    });

    test('stops are ordered by date and stops already behind are skipped', () {
      final d = build([
        mar1,
        ChartPoint(DateTime(2026, 9, 20), 83),
        ChartPoint(DateTime(2026, 9, 30), 82),
        oct28,
      ]);
      expect(d.projection.map((p) => p.date), [
        DateTime(2026, 9, 30),
        DateTime(2026, 10, 28),
        DateTime(2027, 3, 1),
      ]);
    });

    test('1M and 3M reach as far ahead as they look back', () {
      final month = build([
        ChartPoint(DateTime(2026, 11, 30), 79),
      ], range: ChartRange.month);
      // 30 of the 61 days to the stop, from wherever the trend ends.
      final from = month.projection.first.value;
      expect(month.projection.last.date, DateTime(2026, 10, 30));
      expect(
        month.projection.last.value,
        closeTo(from + (79 - from) * 30 / 61, 1e-9),
      );

      final quarter = build([oct28, dec30, mar1], range: ChartRange.quarter);
      // 90 days from Sep 30 is Dec 29, just before the Dec 30 stop.
      expect(quarter.projection.last.date, DateTime(2026, 12, 29));
      expect(quarter.projection.last.value, 80);
      expect(quarter.projection[1].date, DateTime(2026, 10, 28));
    });

    test('a stop inside the reach is kept as it is', () {
      final month = build([oct28], range: ChartRange.month);
      expect(month.projection.last.date, DateTime(2026, 10, 28));
      expect(month.projection.last.value, 80);
    });

    test('nothing ahead means no line', () {
      expect(build(const []).projection, isEmpty);
      expect(
        build([ChartPoint(DateTime(2026, 9, 1), 83)]).projection,
        isEmpty,
        reason: 'only stops in the past',
      );
      expect(
        build([oct28], logs: [WeightLog(DateTime(2026, 9, 1), 80)]).projection,
        isEmpty,
        reason: 'no trend to start from',
      );
    });
  });

  group('WeightTrendRate', () {
    test('null when under 7 days, slope otherwise', () {
      final short = TrendSeries.fromLogs(
        _linear(DateTime(2026, 9, 27), 3, 80, 79),
      );
      expect(WeightTrendRate.perWeekKg(short, DateTime(2026, 9, 30)), isNull);
      expect(WeightTrendRate.perWeekKg(TrendSeries.fromLogs([]), now), isNull);
      final series = TrendSeries.fromLogs(
        _linear(DateTime(2026, 8, 1), 60, 90, 80),
      );
      final rate = WeightTrendRate.perWeekKg(series, DateTime(2026, 9, 30))!;
      expect(rate, lessThan(0));
    });
  });

  group('e1RM series', () {
    StrengthSample s(
      DateTime d,
      double w,
      int reps, {
      String slug = 'barbell-bench-press',
      double? bw,
      bool incBw = false,
    }) => StrengthSample(
      date: d,
      exerciseSlug: slug,
      weightKg: w,
      reps: reps,
      bodyweightKg: bw,
      includesBodyweight: incBw,
    );

    test('filters lift, takes daily max, ignores bad reps, orders', () {
      final samples = [
        s(DateTime(2026, 9, 20, 18), 100, 5),
        s(DateTime(2026, 9, 20, 18, 30), 100, 1),
        s(DateTime(2026, 9, 10), 90, 5),
        s(DateTime(2026, 9, 12), 100, 15),
        s(DateTime(2026, 9, 14), 140, 5, slug: 'barbell-back-squat'),
        s(DateTime(2026, 9, 15), 0, 5),
        s(DateTime(2026, 5, 1), 100, 5),
      ];
      final pts = E1rmSeriesBuilder.build(
        samples: samples,
        lift: PrimaryLift.benchPress,
        now: now,
        range: ChartRange.month,
      );
      expect(pts.length, 2);
      expect(pts[0].date, DateTime(2026, 9, 10));
      expect(pts[1].date, DateTime(2026, 9, 20));
      expect(
        pts[1].value,
        closeTo(100 * (1 + 5 / 30) / 2 + 100 * 36 / 32 / 2, 0.01),
      );
      expect(pts[1].value, greaterThan(100));
      expect(
        E1rmSeriesBuilder.build(
          samples: samples,
          lift: PrimaryLift.benchPress,
          now: now,
          range: ChartRange.all,
        ).length,
        3,
      );
    });

    test('bodyweight is included for weighted bodyweight lifts', () {
      final pts = E1rmSeriesBuilder.build(
        samples: [
          s(DateTime(2026, 9, 20), 0, 1, slug: 'pull-up', bw: 80, incBw: true),
        ],
        lift: PrimaryLift.pullUp,
        now: now,
        range: ChartRange.month,
      );
      expect(pts.single.value, 80);
    });

    test('hasDataIn and defaultLift', () {
      final samples = [
        s(DateTime(2026, 9, 10), 90, 5),
        s(DateTime(2026, 9, 20), 140, 5, slug: 'barbell-back-squat'),
      ];
      expect(
        E1rmSeriesBuilder.hasDataIn(
          samples: samples,
          lift: PrimaryLift.deadlift,
          now: now,
          range: ChartRange.all,
        ),
        isFalse,
      );
      expect(
        E1rmSeriesBuilder.defaultLift(
          samples: samples,
          now: now,
          range: ChartRange.all,
        ),
        PrimaryLift.squat,
      );
      expect(
        E1rmSeriesBuilder.defaultLift(
          samples: const [],
          now: now,
          range: ChartRange.all,
        ),
        isNull,
      );
    });
  });

  group('training level series', () {
    List<DateTime> history(DateTime start, int weeks) => [
      for (var w = 0; w < weeks; w++)
        for (final dow in [0, 2, 4])
          DateTime(start.year, start.month, start.day + 7 * w + dow),
    ];

    test('fewer than 2 samples is empty', () {
      expect(
        TrainingLevelSeriesBuilder.build(
          sessionDates: [DateTime(2026, 9, 30)],
          now: now,
          range: ChartRange.all,
        ),
        isEmpty,
      );
      expect(
        TrainingLevelSeriesBuilder.build(
          sessionDates: const [],
          now: now,
          range: ChartRange.all,
        ),
        isEmpty,
      );
    });

    test('novice then intermediate for a year of 3 sessions per week', () {
      final pts = TrainingLevelSeriesBuilder.build(
        sessionDates: history(DateTime(2025, 9, 1), 56),
        now: now,
        range: ChartRange.all,
      );
      expect(pts.first.level, ExperienceLevel.novice);
      expect(pts.last.level, ExperienceLevel.intermediate);
    });

    test('never exceeds intermediate over 4 years at 3 per week', () {
      final pts = TrainingLevelSeriesBuilder.build(
        sessionDates: history(DateTime(2022, 10, 3), 208),
        now: now,
        range: ChartRange.all,
      );
      expect(pts, isNotEmpty);
      expect(pts.every((p) => p.level != ExperienceLevel.advanced), isTrue);
      expect(pts.last.level, ExperienceLevel.intermediate);
    });

    test('a long gap resets the streak to novice', () {
      final dates = [
        ...history(DateTime(2024, 1, 1), 52),
        ...history(DateTime(2026, 8, 31), 5),
      ];
      final pts = TrainingLevelSeriesBuilder.build(
        sessionDates: dates,
        now: now,
        range: ChartRange.all,
      );
      expect(pts.last.level, ExperienceLevel.novice);
    });

    test('window filters the samples', () {
      final pts = TrainingLevelSeriesBuilder.build(
        sessionDates: history(DateTime(2025, 9, 1), 56),
        now: now,
        range: ChartRange.month,
      );
      expect(pts.length, inInclusiveRange(4, 5));
    });
  });

  test('strength series source does not touch gamification', () {
    final src = File(
      'lib/features/physique/domain/physique_strength_series.dart',
    ).readAsStringSync();
    expect(src.contains('gamification'), isFalse);
  });
}
