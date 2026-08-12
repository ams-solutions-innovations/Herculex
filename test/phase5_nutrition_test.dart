import 'dart:convert';

import 'package:drift/drift.dart' show Value;
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

import 'support/test_database.dart';

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
      final db = await openTestDatabase();
      addTearDown(db.close);

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
        final db = await openTestDatabase();
        addTearDown(db.close);
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
      final db = await openTestDatabase();
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
      final db = await openTestDatabase();
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
        final db = await openTestDatabase();
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

  // ── Phase 5 (wear-sync-race-conditions-remediation-plan): watch water
  // quick-add sync ────────────────────────────────────────────────────────
  //
  // The watch's "+500ml water" quick add previously only touched the
  // watch's own local MacroStore and was never sent to (or applied on) the
  // phone at all. addWaterMl is the phone-side write this newly-wired watch
  // -> phone message applies.
  group('Phase 5 — addWaterMl (watch water quick-add sync)', () {
    test('creates the day\'s DailySummaries row on first add', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);
      final repo = NutritionRepository(
        db,
        OpenFoodFactsClient(),
        _FixedClock(DateTime(2026, 6, 15, 12)),
      );

      await repo.addWaterMl(DateTime(2026, 6, 15), 500);

      final row = (await db.select(db.dailySummaries).get()).single;
      expect(row.dateIso, '2026-06-15');
      expect(row.waterMl, 500);
    });

    test('accumulates across repeated adds on the same day', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);
      final repo = NutritionRepository(
        db,
        OpenFoodFactsClient(),
        _FixedClock(DateTime(2026, 6, 15, 12)),
      );

      await repo.addWaterMl(DateTime(2026, 6, 15), 500);
      await repo.addWaterMl(DateTime(2026, 6, 15), 250);
      await repo.addWaterMl(DateTime(2026, 6, 15), 300);

      final row = (await db.select(db.dailySummaries).get()).single;
      expect(row.waterMl, 1050);
    });

    test('keeps separate days independent', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);
      final repo = NutritionRepository(
        db,
        OpenFoodFactsClient(),
        _FixedClock(DateTime(2026, 6, 15, 12)),
      );

      await repo.addWaterMl(DateTime(2026, 6, 15), 500);
      await repo.addWaterMl(DateTime(2026, 6, 16), 200);

      final rows = await db.select(db.dailySummaries).get();
      expect(rows, hasLength(2));
      expect(
        rows.singleWhere((r) => r.dateIso == '2026-06-15').waterMl,
        500,
      );
      expect(
        rows.singleWhere((r) => r.dateIso == '2026-06-16').waterMl,
        200,
      );
    });
  });

  // ── RB-05 Step 2: unfiltered id-lookup primitives ───────────────────────
  //
  // foodById / foodsByIds / watchFoodById / recipeById exist so history call
  // sites can resolve a known id directly instead of scanning a limited
  // search list. They are deliberately unfiltered by `deletedAt` — that
  // filter is Step 4's job.
  group('RB-05 Step 2 — id-lookup primitives', () {
    test('foodById returns the matching row and null for an unknown id', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);
      final repo = NutritionRepository(
        db,
        OpenFoodFactsClient(),
        _FixedClock(DateTime(2026, 6, 15, 12)),
      );

      final foodId = await db
          .into(db.foods)
          .insert(FoodsCompanion.insert(name: 'Direct Lookup', kcalPer100g: 90));

      expect((await repo.foodById(foodId))?.name, 'Direct Lookup');
      expect(await repo.foodById(foodId + 999), isNull);
    });

    test('foodsByIds batches a lookup keyed by id', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);
      final repo = NutritionRepository(
        db,
        OpenFoodFactsClient(),
        _FixedClock(DateTime(2026, 6, 15, 12)),
      );

      final id1 = await db
          .into(db.foods)
          .insert(FoodsCompanion.insert(name: 'Batch A', kcalPer100g: 10));
      final id2 = await db
          .into(db.foods)
          .insert(FoodsCompanion.insert(name: 'Batch B', kcalPer100g: 20));

      final byId = await repo.foodsByIds([id1, id2, id1 + id2 + 999]);
      expect(byId.length, 2);
      expect(byId[id1]?.name, 'Batch A');
      expect(byId[id2]?.name, 'Batch B');
      expect(await repo.foodsByIds(const []), isEmpty);
    });

    test('watchFoodById emits updates when the row changes', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);
      final repo = NutritionRepository(
        db,
        OpenFoodFactsClient(),
        _FixedClock(DateTime(2026, 6, 15, 12)),
      );

      final foodId = await db
          .into(db.foods)
          .insert(FoodsCompanion.insert(name: 'Watched', kcalPer100g: 50));

      final emissions = <String?>[];
      final sub = repo.watchFoodById(foodId).listen((f) => emissions.add(f?.name));
      await pumpEventQueue();

      await (db.update(db.foods)..where((t) => t.id.equals(foodId)))
          .write(const FoodsCompanion(name: Value('Renamed')));
      await pumpEventQueue();

      await sub.cancel();
      expect(emissions, ['Watched', 'Renamed']);
    });

    test('recipeById returns the matching row and null for an unknown id', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);
      final repo = NutritionRepository(
        db,
        OpenFoodFactsClient(),
        _FixedClock(DateTime(2026, 6, 15, 12)),
      );

      final recipeId = await repo.createRecipe(name: 'Direct Recipe');

      expect((await repo.recipeById(recipeId))?.name, 'Direct Recipe');
      expect(await repo.recipeById(recipeId + 999), isNull);
    });

    test(
      'foodById resolves a food past searchFoods\' 20-row limit '
      '(regression: id resolution no longer scans a truncated search list)',
      () async {
        final db = await openTestDatabase();
        addTearDown(db.close);
        final repo = NutritionRepository(
          db,
          OpenFoodFactsClient(),
          _FixedClock(DateTime(2026, 6, 15, 12)),
        );

        // 25 foods, alphabetically ordered by name — searchFoods('') caps at
        // 20, so the last few never appeared in a name-scan of that result.
        int? targetId;
        for (var i = 0; i < 25; i++) {
          final name = 'Food ${i.toString().padLeft(2, '0')}';
          final id = await db
              .into(db.foods)
              .insert(FoodsCompanion.insert(name: name, kcalPer100g: 100));
          if (i == 24) targetId = id;
        }

        final viaSearch = await repo.searchFoods('');
        expect(viaSearch.any((f) => f.id == targetId), isFalse);

        expect((await repo.foodById(targetId!))?.name, 'Food 24');
      },
    );
  });

  // ── RB-05 Step 3: write-time snapshots + snapshot-first reads ───────────
  //
  // logFood/logRecipe now freeze nutrition onto the entry at log time
  // (snapshot* columns); macrosForEntry/watchDailyTotalsForRange read those
  // columns first and only fall back to the live catalogue when
  // `snapshotBasis` is null (a pre-v24 row the migration couldn't backfill).
  group('RB-05 Step 3 — snapshot write + snapshot-first read', () {
    test(
      'a food entry\'s totals are unaffected by a later live food edit',
      () async {
        final db = await openTestDatabase();
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
                name: 'Chicken Breast',
                kcalPer100g: 200,
                proteinPer100g: const Value(30),
              ),
            );

        await repo.logFood(
          date: DateTime(2026, 6, 15),
          meal: Meal.lunch,
          foodId: foodId,
          grams: 100,
        );
        var entry = (await db.select(db.foodEntries).get()).single;
        expect(entry.snapshotBasis, isNotNull);
        expect(entry.snapshotKcal, 200);

        var totals = await repo.macrosForEntry(entry);
        expect(totals.kcal, 200);
        expect(totals.proteinG, 30);

        // Editing the catalogue row must not move history.
        await repo.updateCustomFood(
          id: foodId,
          name: 'Chicken Breast',
          kcalPer100g: 500,
          proteinPer100g: 60,
        );

        entry = (await db.select(db.foodEntries).get()).single;
        totals = await repo.macrosForEntry(entry);
        expect(totals.kcal, 200);
        expect(totals.proteinG, 30);
      },
    );

    test(
      'a recipe entry\'s totals are unaffected by a later live ingredient edit',
      () async {
        final db = await openTestDatabase();
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
                name: 'Oats',
                kcalPer100g: 200,
                sodiumMgPer100g: const Value(5),
              ),
            );
        final recipeId = await repo.createRecipe(name: 'Porridge', servings: 1);
        await repo.addIngredient(recipeId: recipeId, foodId: foodId, grams: 100);

        await repo.logRecipe(
          date: DateTime(2026, 6, 15),
          meal: Meal.breakfast,
          recipeId: recipeId,
          servings: 1,
        );
        var entry = (await db.select(db.foodEntries).get()).single;
        expect(entry.snapshotBasis, 'recipe serving');
        expect(entry.snapshotKcal, 200);

        var totals = await repo.macrosForEntry(entry);
        expect(totals.kcal, 200);
        expect(totals.micros['sodium'], 5);

        // Swap the ingredient for a smaller portion — the live per-serving
        // total halves, but the already-logged entry must not move.
        final ingredients = await repo.watchIngredients(recipeId).first;
        await repo.removeIngredient(ingredients.single.id);
        await repo.addIngredient(recipeId: recipeId, foodId: foodId, grams: 50);

        final livePer = await repo.recipeMacrosPerServing(recipeId);
        expect(livePer.kcal, 100);

        entry = (await db.select(db.foodEntries).get()).single;
        totals = await repo.macrosForEntry(entry);
        expect(totals.kcal, 200);
        expect(totals.micros['sodium'], 5);
      },
    );

    test(
      'a null-snapshot (pre-v24) entry keeps resolving against the live '
      'catalogue',
      () async {
        final db = await openTestDatabase();
        addTearDown(db.close);
        final repo = NutritionRepository(
          db,
          OpenFoodFactsClient(),
          _FixedClock(DateTime(2026, 6, 15, 12)),
        );

        final foodId = await db
            .into(db.foods)
            .insert(FoodsCompanion.insert(name: 'Legacy Row', kcalPer100g: 150));

        // Simulate a pre-v24 row the migration couldn't backfill: written
        // directly, bypassing logFood, so every snapshot* column is null.
        await db
            .into(db.foodEntries)
            .insert(
              FoodEntriesCompanion.insert(
                dateIso: '2026-06-15',
                meal: Meal.snack.name,
                foodId: Value(foodId),
                gramsOverride: const Value(100),
                portionAmount: const Value(100),
                portionUnit: const Value('g'),
              ),
            );
        var entry = (await db.select(db.foodEntries).get()).single;
        expect(entry.snapshotBasis, isNull);

        var totals = await repo.macrosForEntry(entry);
        expect(totals.kcal, 150);

        // Unlike a snapshotted entry, this one is still expected to move
        // with the catalogue — that's the documented fallback behavior, not
        // a regression.
        await repo.updateCustomFood(
          id: foodId,
          name: 'Legacy Row',
          kcalPer100g: 300,
        );
        totals = await repo.macrosForEntry(entry);
        expect(totals.kcal, 300);
      },
    );

    test(
      'recipeMacrosPerServing no longer drops micronutrients',
      () async {
        final db = await openTestDatabase();
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
                name: 'Spinach',
                kcalPer100g: 23,
                potassiumMgPer100g: const Value(550),
              ),
            );
        final recipeId = await repo.createRecipe(name: 'Salad', servings: 1);
        await repo.addIngredient(recipeId: recipeId, foodId: foodId, grams: 100);

        final per = await repo.recipeMacrosPerServing(recipeId);
        expect(per.kcal, 23);
        expect(per.micros['potassium'], 550);
        expect(per.hasMicros, isTrue);
      },
    );
  });
}
