import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/nutrition/application/minimum_reached_providers.dart';
import 'package:herculex/features/nutrition/domain/daily_totals.dart';
import 'package:herculex/features/nutrition/presentation/widgets/macro_chart.dart';
import 'package:intl/intl.dart';

DailyTotals _totals({double kcal = 0, double protein = 0}) => DailyTotals(
  kcal: kcal,
  proteinG: protein,
  carbsG: 0,
  fatG: 0,
  fiberG: 0,
  sodiumMg: 0,
  potassiumMg: 0,
  cholesterolMg: 0,
  micros: const {},
);

void main() {
  group('detectMinimumCrossings', () {
    test('fires when intake goes from below to at/above the floor', () {
      final c = detectMinimumCrossings(
        previous: _totals(kcal: 1400, protein: 120),
        next: _totals(kcal: 1500, protein: 130),
        minKcal: 1500,
        minProteinG: 150,
      );
      expect(c.calories, isTrue);
      expect(c.protein, isFalse);
    });

    test('both floors can be crossed by one entry', () {
      final c = detectMinimumCrossings(
        previous: _totals(kcal: 1000, protein: 100),
        next: _totals(kcal: 1800, protein: 160),
        minKcal: 1500,
        minProteinG: 150,
      );
      expect(c.calories && c.protein, isTrue);
    });

    test('does not refire once already above the floor', () {
      final c = detectMinimumCrossings(
        previous: _totals(kcal: 1600, protein: 160),
        next: _totals(kcal: 1900, protein: 190),
        minKcal: 1500,
        minProteinG: 150,
      );
      expect(c.any, isFalse);
    });

    test('already-announced floors stay quiet', () {
      final c = detectMinimumCrossings(
        previous: _totals(kcal: 1400),
        next: _totals(kcal: 1600),
        minKcal: 1500,
        minProteinG: null,
        alreadyCalories: true,
      );
      expect(c.any, isFalse);
    });

    test('null or non-positive floors never fire', () {
      final c = detectMinimumCrossings(
        previous: _totals(),
        next: _totals(kcal: 3000, protein: 300),
        minKcal: null,
        minProteinG: 0,
      );
      expect(c.any, isFalse);
    });
  });

  group('MacroTrendChart minimum line', () {
    Future<List<HorizontalLine>> lines(
      WidgetTester tester, {
      double? minValue,
    }) async {
      final now = DateTime.now();
      final iso = DateFormat('yyyy-MM-dd').format(now);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MacroTrendChart(
              historyMap: {iso: _totals(kcal: 2000, protein: 140)},
              macro: 'protein',
              range: '7d',
              targetValue: 180,
              minValue: minValue,
            ),
          ),
        ),
      );
      await tester.pump();
      final chart = tester.widget<LineChart>(find.byType(LineChart));
      return chart.data.extraLinesData.horizontalLines;
    }

    testWidgets('draws a second line when minValue is set', (tester) async {
      final l = await lines(tester, minValue: 150);
      expect(l.map((e) => e.y), [180, 150]);
    });

    testWidgets('draws only the target when minValue is null', (tester) async {
      final l = await lines(tester);
      expect(l.map((e) => e.y), [180]);
    });
  });
}
