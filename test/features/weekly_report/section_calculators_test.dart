import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/weekly_report/domain/iso_week.dart';
import 'package:herculex/features/weekly_report/domain/nutrition_section_calculator.dart';

void main() {
  // 2026-09-28 is a Monday: ISO week 2026-W40 runs 09-28 .. 10-04.
  final week = IsoWeek.fromDate(DateTime(2026, 9, 28));

  group('NutritionSectionCalculator', () {
    NutritionWeekInputs inputs({
      Set<String>? days,
      Map<String, double>? kcal,
      Map<String, double>? protein,
      Map<String, ({int kcal, int proteinG})>? targets,
      List<FoodEntryName>? foods,
    }) => NutritionWeekInputs(
      loggedDays: days ?? {'2026-09-28', '2026-09-29', '2026-09-30'},
      kcalByDate:
          kcal ??
          {'2026-09-28': 2400, '2026-09-29': 2600, '2026-09-30': 0},
      proteinByDate:
          protein ??
          {'2026-09-28': 150, '2026-09-29': 170, '2026-09-30': 0},
      targetByDate:
          targets ??
          {
            for (final d in ['2026-09-28', '2026-09-29', '2026-09-30'])
              d: (kcal: 2500, proteinG: 160),
          },
      foodEntries: foods ?? const [],
    );

    test('week sanity: the fixture week is 2026-W40', () {
      expect(week, const IsoWeek(2026, 40));
      expect(week.startIso, '2026-09-28');
      expect(week.endIso, '2026-10-04');
    });

    test('presence-based averages, targets and adherence', () {
      final s = NutritionSectionCalculator.compute(
        week: week,
        inputs: inputs(),
      )!;
      expect(s.daysLogged, 3);
      // A logged day with 0 kcal still counts: (2400 + 2600 + 0) / 3.
      expect(s.avgKcal, 1667);
      expect(s.avgProteinG, 107);
      expect(s.targetKcal, 2500);
      expect(s.targetProteinG, 160);
      // 2400 and 2600 are within 250 of 2500; 0 is not.
      expect(s.adherenceDays, 2);
    });

    test('adherence band is the named 10 percent constant', () {
      expect(NutritionSectionCalculator.adherenceBandFraction, 0.10);
      final onEdge = NutritionSectionCalculator.compute(
        week: week,
        inputs: inputs(
          days: {'2026-09-28', '2026-09-29'},
          kcal: {'2026-09-28': 2750, '2026-09-29': 2751},
        ),
      )!;
      expect(onEdge.adherenceDays, 1);
    });

    test('no targets -> target and adherence fields are null', () {
      final s = NutritionSectionCalculator.compute(
        week: week,
        inputs: inputs(targets: const {}),
      )!;
      expect(s.targetKcal, isNull);
      expect(s.targetProteinG, isNull);
      expect(s.adherenceDays, isNull);
      expect(s.daysLogged, 3);
    });

    test('targets are averaged over logged days that have one', () {
      final s = NutritionSectionCalculator.compute(
        week: week,
        inputs: inputs(
          targets: {
            '2026-09-28': (kcal: 2000, proteinG: 100),
            '2026-09-29': (kcal: 3000, proteinG: 200),
            // 09-30 has no target.
          },
        ),
      )!;
      expect(s.targetKcal, 2500);
      expect(s.targetProteinG, 150);
    });

    test('no logged days returns null', () {
      expect(
        NutritionSectionCalculator.compute(
          week: week,
          inputs: inputs(days: <String>{}),
        ),
        isNull,
      );
    });

    test('days outside the week are ignored', () {
      final s = NutritionSectionCalculator.compute(
        week: week,
        inputs: inputs(
          days: {'2026-09-27', '2026-09-28', '2026-10-05'},
          kcal: {'2026-09-27': 9000, '2026-09-28': 2000, '2026-10-05': 9000},
          protein: {'2026-09-27': 900, '2026-09-28': 100, '2026-10-05': 900},
          targets: {
            '2026-09-27': (kcal: 9000, proteinG: 900),
            '2026-09-28': (kcal: 2000, proteinG: 100),
          },
        ),
      )!;
      expect(s.daysLogged, 1);
      expect(s.avgKcal, 2000);
      expect(s.targetKcal, 2000);
      expect(s.adherenceDays, 1);
    });

    test('only out-of-week days logged returns null', () {
      expect(
        NutritionSectionCalculator.compute(
          week: week,
          inputs: inputs(days: {'2026-09-27'}),
        ),
        isNull,
      );
    });

    test('topFoods: count desc, name asc, max 3, trimmed, capped', () {
      final long = 'x' * 80;
      final s = NutritionSectionCalculator.compute(
        week: week,
        inputs: inputs(
          foods: [
            const FoodEntryName(key: 'a', name: 'Oats'),
            const FoodEntryName(key: 'a', name: 'Oats'),
            const FoodEntryName(key: 'b', name: '  Banana '),
            const FoodEntryName(key: 'b', name: 'Banana'),
            const FoodEntryName(key: 'c', name: 'Apple'),
            const FoodEntryName(key: 'd', name: 'Zucchini'),
            const FoodEntryName(key: 'e', name: '   '),
            const FoodEntryName(key: 'e', name: ''),
            FoodEntryName(key: 'f', name: long),
            FoodEntryName(key: 'f', name: long),
            FoodEntryName(key: 'f', name: long),
          ],
        ),
      )!;
      expect(s.topFoods.map((f) => f.name).toList(), [
        'x' * 60,
        'Banana',
        'Oats',
      ]);
      expect(s.topFoods.map((f) => f.count).toList(), [3, 2, 2]);
    });

    test('equal inputs give equal output (no clock involved)', () {
      final a = NutritionSectionCalculator.compute(
        week: week,
        inputs: inputs(),
      )!.toJson();
      final b = NutritionSectionCalculator.compute(
        week: week,
        inputs: inputs(),
      )!.toJson();
      expect(a, b);
    });

    test('copyWith replaces only targetByDate', () {
      final base = inputs(targets: const {});
      final filled = base.copyWith(
        targetByDate: {'2026-09-28': (kcal: 2500, proteinG: 160)},
      );
      expect(filled.loggedDays, base.loggedDays);
      expect(filled.kcalByDate, base.kcalByDate);
      expect(filled.targetByDate, hasLength(1));
      expect(base.copyWith().targetByDate, isEmpty);
    });
  });
}
