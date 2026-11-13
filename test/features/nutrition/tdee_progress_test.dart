import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/design_system/theme/app_theme.dart';
import 'package:herculex/features/nutrition/domain/tdee_calibration_series.dart';
import 'package:herculex/features/nutrition/domain/tdee_progress.dart';
import 'package:herculex/features/nutrition/domain/tdee_trend.dart';
import 'package:herculex/features/nutrition/presentation/widgets/calibration_charts.dart';

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

void main() {
  final asOf = DateTime(2026, 10, 9, 12);
  DateTime ago(int days) => DateTime(asOf.year, asOf.month, asOf.day - days);

  CalibrationGate gate(CalibrationProgress p, String startsWith) =>
      p.gates.firstWhere((g) => g.label.startsWith(startsWith));

  group('CalibrationProgress', () {
    test('nothing logged: every gate is empty and not met', () {
      final p = CalibrationProgress.evaluate(
        asOf: asOf,
        foodLoggedDays: const {},
        weightLogs: const [],
      );
      expect(p.allMet, isFalse);
      expect(p.gates.every((g) => g.have == 0), isTrue);
    });

    test('food gate needs 10 of the last 14 days', () {
      Set<String> food(int n) => {for (var i = 0; i < n; i++) _iso(ago(i))};
      final nine = CalibrationProgress.evaluate(
        asOf: asOf,
        foodLoggedDays: food(9),
        weightLogs: const [],
      );
      final ten = CalibrationProgress.evaluate(
        asOf: asOf,
        foodLoggedDays: food(10),
        weightLogs: const [],
      );
      expect(gate(nine, 'Days with food').need, 10);
      expect(gate(nine, 'Days with food').met, isFalse);
      expect(gate(ten, 'Days with food').met, isTrue);
    });

    test('weigh-ins: 3 is short, 4 spread over both halves is enough', () {
      List<WeightLog> logs(List<int> ages) => [
        for (final a in ages) WeightLog(ago(a), 80),
      ];
      final three = CalibrationProgress.evaluate(
        asOf: asOf,
        foodLoggedDays: const {},
        weightLogs: logs([0, 3, 9]),
      );
      final four = CalibrationProgress.evaluate(
        asOf: asOf,
        foodLoggedDays: const {},
        weightLogs: logs([0, 3, 9, 12]),
      );
      expect(gate(three, 'Weigh-ins (').met, isFalse);
      expect(gate(four, 'Weigh-ins (').met, isTrue);
      expect(gate(four, 'Weigh-ins in both').met, isTrue);
    });

    test('weigh-ins only in the newest half miss the spread gate', () {
      final p = CalibrationProgress.evaluate(
        asOf: asOf,
        foodLoggedDays: const {},
        weightLogs: [
          for (final a in [0, 1, 2, 3]) WeightLog(ago(a), 80),
        ],
      );
      expect(gate(p, 'Weigh-ins (').met, isTrue);
      expect(gate(p, 'Weigh-ins in both').met, isFalse);
    });

    test('recency: newest log 7 days old fails, 6 days old passes', () {
      CalibrationProgress at(int age) => CalibrationProgress.evaluate(
        asOf: asOf,
        foodLoggedDays: {_iso(ago(age))},
        weightLogs: [WeightLog(ago(age), 80)],
      );
      expect(gate(at(7), 'Food and weight').met, isFalse);
      expect(gate(at(6), 'Food and weight').met, isTrue);
    });

    test('enough of everything is allMet', () {
      final p = CalibrationProgress.evaluate(
        asOf: asOf,
        foodLoggedDays: {for (var i = 0; i < 14; i++) _iso(ago(i))},
        weightLogs: [
          for (final a in [0, 3, 9, 12]) WeightLog(ago(a), 80),
        ],
      );
      expect(p.allMet, isTrue);
      expect(p.gates.every((g) => g.fraction == 1), isTrue);
    });
  });

  group('CalibrationSeries', () {
    test('lays weigh-ins, trend and intake on one day axis', () {
      final s = CalibrationSeries.build(
        asOf: asOf,
        days: 14,
        weightLogs: [
          WeightLog(ago(13), 80),
          WeightLog(ago(7), 79.4),
          WeightLog(ago(0), 78.8),
        ],
        dailyKcalByDate: {_iso(ago(0)): 2000, _iso(ago(1)): 3000},
      );
      expect(s.days, 14);
      expect(s.weighIns.map((p) => p.x), [0, 6, 13]);
      expect(s.trend.length, 14);
      expect(s.trend.first.y, 80);
      expect(s.trend.last.y, lessThan(80));
      expect(s.intake.map((p) => p.x), [12, 13]);
      expect(s.meanIntake, 2500);
      expect(s.dateAt(13), DateTime(asOf.year, asOf.month, asOf.day));
    });

    test('empty logs produce empty series without throwing', () {
      final s = CalibrationSeries.build(
        asOf: asOf,
        days: 14,
        weightLogs: const [],
        dailyKcalByDate: const {},
      );
      expect(s.hasWeight, isFalse);
      expect(s.hasIntake, isFalse);
      expect(s.trend, isEmpty);
      expect(s.meanIntake, isNull);
    });
  });

  group('Calibration charts rendering', () {
    testWidgets('WeightTrendChart and IntakeChart use clean axes and 4 date ticks', (
      tester,
    ) async {
      final oct25 = DateTime(2026, 10, 25);
      DateTime d(int offset) =>
          DateTime(oct25.year, oct25.month, oct25.day + offset);
      final series = CalibrationSeries.build(
        asOf: oct25,
        days: 28,
        weightLogs: [
          WeightLog(d(-20), 86.0),
          WeightLog(d(-19), 85.3),
          WeightLog(d(-17), 85.6),
          WeightLog(d(-16), 84.3),
          WeightLog(d(-15), 86.1),
          WeightLog(d(-14), 85.7),
          WeightLog(d(-12), 85.7),
          WeightLog(d(-10), 86.2),
          WeightLog(d(-8), 86.7),
          WeightLog(d(-7), 87.6),
          WeightLog(d(-5), 85.8),
          WeightLog(d(-3), 85.9),
        ],
        dailyKcalByDate: {
          for (var i = -21; i <= 0; i++) _iso(d(i)): i == -8 ? 3200 : 2100,
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  WeightTrendChart(series: series),
                  IntakeChart(series: series),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Clean rounded Y-axis labels on WeightTrendChart (84.0..88.0, step 1.0).
      expect(find.text('84.0'), findsOneWidget);
      expect(find.text('85.0'), findsOneWidget);
      expect(find.text('86.0'), findsOneWidget);
      expect(find.text('87.0'), findsOneWidget);
      expect(find.text('88.0'), findsOneWidget);

      // Clean rounded Y-axis labels on IntakeChart (0, 1,000, 2,000, 3,000, 4,000).
      expect(find.text('1,000'), findsOneWidget);
      expect(find.text('2,000'), findsOneWidget);
      expect(find.text('3,000'), findsOneWidget);
      expect(find.text('4,000'), findsOneWidget);
      // Never fractional third labels like 1,233 or 2,467.
      expect(find.text('1,233'), findsNothing);
      expect(find.text('2,467'), findsNothing);

      // Exactly 4 X-axis date labels per chart (28 Sep, 7 Oct, 16 Oct, 25 Oct),
      // not 22 overlapping date labels.
      expect(find.text('28 Sep'), findsNWidgets(2));
      expect(find.text('7 Oct'), findsNWidgets(2));
      expect(find.text('16 Oct'), findsNWidgets(2));
      expect(find.text('25 Oct'), findsNWidgets(2));
      expect(find.text('10 Oct'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
