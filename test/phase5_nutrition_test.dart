import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/nutrition/data/nutrition_repository.dart';
import 'package:herculex/features/nutrition/data/openfoodfacts_client.dart';
import 'package:herculex/features/nutrition/domain/carb_cycling.dart';
import 'package:herculex/features/nutrition/domain/barcode_utils.dart';
import 'package:herculex/features/nutrition/domain/macro_targets.dart';
import 'package:herculex/features/nutrition/domain/meal.dart';
import 'package:herculex/features/nutrition/domain/target_resolver.dart';

class _FixedClock implements Clock {
  DateTime fixed;
  _FixedClock(this.fixed);
  @override
  DateTime now() => fixed;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TargetResolver — day-specific selection', () {
    const global = TargetRule(
      kcal: 2800,
      proteinG: 180,
      carbsG: 300,
      fatG: 80,
      appliesTo: 'global',
    );
    const training = TargetRule(
      kcal: 3500,
      proteinG: 200,
      carbsG: 450,
      fatG: 90,
      appliesTo: 'training_day',
    );
    const rest = TargetRule(
      kcal: 2400,
      proteinG: 180,
      carbsG: 200,
      fatG: 80,
      appliesTo: 'rest_day',
    );

    test('training day beats global', () {
      final r = TargetResolver.resolveRule(
        rules: [global, training, rest],
        date: DateTime(2026, 6, 15),
        isTrainingDay: true,
      );
      expect(r?.kcal, 3500);
    });

    test('rest day beats global on a non-training day', () {
      final r = TargetResolver.resolveRule(
        rules: [global, training, rest],
        date: DateTime(2026, 6, 15),
        isTrainingDay: false,
      );
      expect(r?.kcal, 2400);
    });

    test('specific date overrides everything', () {
      const dateRule = TargetRule(
        kcal: 4000,
        proteinG: 200,
        carbsG: 500,
        fatG: 100,
        appliesTo: 'date:2026-06-15',
      );
      final r = TargetResolver.resolveRule(
        rules: [global, training, dateRule],
        date: DateTime(2026, 6, 15),
        isTrainingDay: true,
      );
      expect(r?.kcal, 4000);
    });

    test('weekday rule matches the right day', () {
      // 2026-06-15 is a Monday (weekday 1).
      const monday = TargetRule(
        kcal: 3000,
        proteinG: 180,
        carbsG: 320,
        fatG: 85,
        appliesTo: 'weekday:1',
      );
      expect(
        TargetResolver.resolveRule(
          rules: [global, monday],
          date: DateTime(2026, 6, 15),
          isTrainingDay: false,
        )?.kcal,
        3000,
      );
      // Tuesday → falls back to global.
      expect(
        TargetResolver.resolveRule(
          rules: [global, monday],
          date: DateTime(2026, 6, 16),
          isTrainingDay: false,
        )?.kcal,
        2800,
      );
    });

    test('falls back to profile baseline when no rule matches', () {
      const baseline = MacroTargets(
        kcal: 2600,
        proteinG: 170,
        carbsG: 280,
        fatG: 78,
      );
      final t = TargetResolver.resolve(
        rules: const [],
        date: DateTime(2026, 6, 15),
        isTrainingDay: true,
        fallback: baseline,
      );
      expect(t?.kcal, 2600);
    });
  });

  group('TargetResolver — automated diet schedule', () {
    const base = MacroTargets(kcal: 3000, proteinG: 200, carbsG: 350, fatG: 80);

    test('no reduction before the first interval elapses', () {
      final schedule = DietScheduleRule(
        startDate: DateTime(2026, 6, 1),
        reducePct: 5,
        intervalDays: 14,
      );
      final t = TargetResolver.applySchedule(
        base: base,
        schedule: schedule,
        date: DateTime(2026, 6, 10),
      );
      expect(t.kcal, 3000);
    });

    test(
      'compounding reduction after multiple intervals; protein preserved',
      () {
        final schedule = DietScheduleRule(
          startDate: DateTime(2026, 6, 1),
          reducePct: 10,
          intervalDays: 7,
        );
        // 21 days later → 3 steps → 3000 × 0.9^3 = 2187.
        final t = TargetResolver.applySchedule(
          base: base,
          schedule: schedule,
          date: DateTime(2026, 6, 22),
        );
        expect(t.kcal, 2187);
        expect(t.proteinG, 200); // preserved on a cut
        // Deficit came out of carbs/fat: energy roughly balances.
        final energy = t.proteinG * 4 + t.carbsG * 4 + t.fatG * 9;
        expect((energy - t.kcal).abs(), lessThan(15));
      },
    );

    test('reductionSteps counts elapsed intervals', () {
      final schedule = DietScheduleRule(
        startDate: DateTime(2026, 6, 1),
        reducePct: 5,
        intervalDays: 10,
      );
      expect(TargetResolver.reductionSteps(schedule, DateTime(2026, 6, 1)), 0);
      // June 1 + 21 days = June 22 → 2 full 10-day intervals elapsed.
      expect(TargetResolver.reductionSteps(schedule, DateTime(2026, 6, 22)), 2);
      expect(TargetResolver.reductionSteps(schedule, DateTime(2026, 6, 20)), 1);
    });
  });

  group('CarbCycling', () {
    test('hardest, most compound day gets HIGH; rest day gets LOW', () {
      final week = [
        const DayTrainingSignal(
          weekdayIndex: 0,
          cnsLoad: 8,
          compoundDensity: 0.9,
          isTrainingDay: true,
        ), // heavy
        const DayTrainingSignal(
          weekdayIndex: 1,
          cnsLoad: 3,
          compoundDensity: 0.3,
          isTrainingDay: true,
        ), // light
        const DayTrainingSignal(
          weekdayIndex: 2,
          cnsLoad: 5,
          compoundDensity: 0.5,
          isTrainingDay: true,
        ), // medium
        const DayTrainingSignal(weekdayIndex: 3), // rest
        const DayTrainingSignal(weekdayIndex: 4), // rest
        const DayTrainingSignal(weekdayIndex: 5), // rest
        const DayTrainingSignal(weekdayIndex: 6), // rest
      ];
      final plan = CarbCycling.generate(week);
      expect(plan, hasLength(7));
      expect(plan[0], CarbLevel.high);
      expect(plan[3], CarbLevel.low); // rest day
      expect(plan[1], CarbLevel.low); // lightest training day
    });

    test('no training info → flat medium week', () {
      final plan = CarbCycling.generate([
        for (var i = 0; i < 7; i++) DayTrainingSignal(weekdayIndex: i),
      ]);
      expect(plan.every((l) => l == CarbLevel.medium), isTrue);
    });

    test('carb grams scale per level off a baseline', () {
      expect(CarbCycling.carbsForLevel(CarbLevel.medium, 300), 300);
      expect(CarbCycling.carbsForLevel(CarbLevel.high, 300), 390);
      expect(CarbCycling.carbsForLevel(CarbLevel.low, 300), 195);
    });
  });

  group('§22 food-log timezone fix', () {
    test('loggedAt is stamped from the local clock, matching dateIso', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await db.customStatement('PRAGMA foreign_keys = ON');

      // Clock set to local 11:30pm — under SQLite's UTC CURRENT_TIMESTAMP this
      // would have rolled to the next day for users behind UTC.
      final clock = _FixedClock(DateTime(2026, 6, 15, 23, 30));
      final repo = NutritionRepository(db, OpenFoodFactsClient(), clock);

      final foodId = await db
          .into(db.foods)
          .insert(FoodsCompanion.insert(name: 'Test Rice', kcalPer100g: 130));
      await repo.logFood(
        date: DateTime(2026, 6, 15),
        meal: Meal.dinner,
        foodId: foodId,
        grams: 200,
      );

      final entry = (await db.select(db.foodEntries).get()).single;
      expect(entry.dateIso, '2026-06-15');
      // loggedAt agrees with the local clock and lands on the same day.
      expect(entry.loggedAt, DateTime(2026, 6, 15, 23, 30));
      expect(dateIso(entry.loggedAt), entry.dateIso);
    });
  });

  group('Database-backed targets', () {
    test(
      'day-specific targets resolve correctly given a real training session',
      () async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        await db.customStatement('PRAGMA foreign_keys = ON');
        final clock = _FixedClock(DateTime(2026, 6, 15, 12));
        final repo = NutritionRepository(db, OpenFoodFactsClient(), clock);

        await repo.upsertTarget(
          label: 'Rest',
          appliesTo: 'rest_day',
          kcal: 2400,
          proteinG: 180,
          carbsG: 200,
          fatG: 80,
        );
        await repo.upsertTarget(
          label: 'Train',
          appliesTo: 'training_day',
          kcal: 3500,
          proteinG: 200,
          carbsG: 450,
          fatG: 90,
        );

        // No session yet → rest day.
        expect(await repo.trainedOn(DateTime(2026, 6, 15)), isFalse);

        // Log a completed session today.
        await db
            .into(db.workoutSessions)
            .insert(
              WorkoutSessionsCompanion.insert(
                startedAt: DateTime(2026, 6, 15, 10),
                endedAt: Value(DateTime(2026, 6, 15, 11)),
              ),
            );
        expect(await repo.trainedOn(DateTime(2026, 6, 15)), isTrue);

        // upsert dedups by scope.
        await repo.upsertTarget(
          label: 'Train',
          appliesTo: 'training_day',
          kcal: 3600,
          proteinG: 200,
          carbsG: 460,
          fatG: 92,
        );
        final rows = await repo.watchTargets().first;
        expect(rows.where((r) => r.appliesTo == 'training_day'), hasLength(1));
        expect(
          rows.singleWhere((r) => r.appliesTo == 'training_day').kcal,
          3600,
        );
      },
    );
  });

  group('Nutrition portions and micronutrients', () {
    test('scales a 100 ml food and keeps source micronutrients', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = NutritionRepository(
        db,
        OpenFoodFactsClient(),
        _FixedClock(DateTime(2026, 6, 15, 12)),
      );
      final foodId = await db
          .into(db.foods)
          .insert(
            FoodsCompanion.insert(
              name: 'Fortified Drink',
              kcalPer100g: 200,
              proteinPer100g: const Value(10),
              referenceBasis: const Value('100 ml'),
              sourceMetadataJson: Value(
                jsonEncode({
                  'nutrients': {'vitamin_c': 4, 'iron': 1.5},
                }),
              ),
            ),
          );

      await repo.logFood(
        date: DateTime(2026, 6, 15),
        meal: Meal.breakfast,
        foodId: foodId,
        portionAmount: 250,
        portionUnit: 'ml',
      );
      final entry = (await db.select(db.foodEntries).get()).single;
      final totals = await repo.macrosForEntry(entry);

      expect(totals.kcal, 500);
      expect(totals.proteinG, 25);
      expect(totals.micros['vitamin_c'], 10);
      expect(totals.micros['iron'], 3.75);
    });

    test('scales a legacy serving basis by serving or gram input', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = NutritionRepository(
        db,
        OpenFoodFactsClient(),
        _FixedClock(DateTime(2026, 6, 15, 12)),
      );
      final foodId = await db
          .into(db.foods)
          .insert(
            FoodsCompanion.insert(
              name: 'Legacy Bar',
              kcalPer100g: 250,
              servingGrams: const Value(50),
              servingAmount: const Value(1),
              servingUnit: const Value('serving'),
              referenceBasis: const Value('Legacy serving (unverified)'),
              sourceMetadataJson: Value(
                jsonEncode({
                  'nutrients': {'magnesium': 20},
                }),
              ),
            ),
          );

      await repo.logFood(
        date: DateTime(2026, 6, 15),
        meal: Meal.snack,
        foodId: foodId,
        portionAmount: 2,
        portionUnit: 'serving',
      );
      var entry = (await db.select(db.foodEntries).get()).single;
      var totals = await repo.macrosForEntry(entry);
      expect(totals.kcal, 500);
      expect(totals.micros['magnesium'], 40);

      await repo.deleteEntry(entry.id);
      await repo.logFood(
        date: DateTime(2026, 6, 15),
        meal: Meal.snack,
        foodId: foodId,
        portionAmount: 100,
        portionUnit: 'g',
      );
      entry = (await db.select(db.foodEntries).get()).single;
      totals = await repo.macrosForEntry(entry);
      expect(totals.kcal, 500);
      expect(totals.micros['magnesium'], 40);
    });
  });

  group('Local barcode recovery', () {
    test(
      'lookup accepts a normalized UPC-A and preserves custom barcode',
      () async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        final repo = NutritionRepository(
          db,
          OpenFoodFactsClient(),
          _FixedClock(DateTime(2026, 6, 15, 12)),
        );

        final foodId = await db
            .into(db.foods)
            .insert(
              FoodsCompanion.insert(
                name: 'UPC item',
                barcode: const Value('0036000291452'),
                kcalPer100g: 100,
              ),
            );
        expect((await repo.lookupBarcode('036000291452'))?.id, foodId);
        expect(await repo.lookupBarcode('036000291453'), isNull);

        final custom = await repo.createCustomFood(
          name: 'Scanned custom',
          kcalPer100g: 120,
          barcode: normalizeBarcode('4006381333931')!.value,
        );
        expect(custom.barcode, '4006381333931');
      },
    );
  });
}
