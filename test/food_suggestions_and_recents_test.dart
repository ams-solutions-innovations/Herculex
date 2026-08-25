import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/nutrition/data/nutrition_repository.dart';
import 'package:herculex/features/nutrition/data/openfoodfacts_client.dart';

import 'support/test_database.dart';

class _FixedClock implements Clock {
  DateTime fixed;
  _FixedClock(this.fixed);
  @override
  DateTime now() => fixed;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<int> insertFood(
    AppDatabase db, {
    required String name,
    double kcal = 100,
  }) {
    return db
        .into(db.foods)
        .insert(
          FoodsCompanion.insert(
            name: name,
            kcalPer100g: kcal,
            isCustom: const Value(true),
            source: const Value('local'),
          ),
        );
  }

  NutritionRepository repo(AppDatabase db, {Clock? clock}) =>
      NutritionRepository(db, OpenFoodFactsClient(), clock ?? const SystemClock());

  group('NutritionRepository.watchRecentlyLoggedFoods', () {
    test('returns unique foods ordered by latest loggedAt descending', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);

      final clock = _FixedClock(DateTime(2026, 8, 21, 12, 0));
      final r = repo(db, clock: clock);

      final oatmealId = await insertFood(db, name: 'Oatmeal');
      final eggsId = await insertFood(db, name: 'Eggs');
      final bananaId = await insertFood(db, name: 'Banana');
      final proteinBarId = await insertFood(db, name: 'Protein Bar');

      // Log foods at different timestamps
      await r.logFood(
        date: DateTime(2026, 8, 20),
        foodId: oatmealId,
        grams: 50,
        loggedAt: DateTime(2026, 8, 20, 8, 0),
      );
      await r.logFood(
        date: DateTime(2026, 8, 20),
        foodId: bananaId,
        grams: 100,
        loggedAt: DateTime(2026, 8, 20, 10, 0),
      );
      await r.logFood(
        date: DateTime(2026, 8, 21),
        foodId: eggsId,
        grams: 120,
        loggedAt: DateTime(2026, 8, 21, 7, 30),
      );
      // Re-log oatmeal later (so oatmeal becomes the most recently logged)
      await r.logFood(
        date: DateTime(2026, 8, 21),
        foodId: oatmealId,
        grams: 60,
        loggedAt: DateTime(2026, 8, 21, 11, 0),
      );

      final recents = await r.watchRecentlyLoggedFoods().first;

      // Expected order: Oatmeal (21st 11:00) -> Eggs (21st 7:30) -> Banana (20th 10:00)
      // Protein Bar was never logged so it should not appear.
      expect(recents.map((f) => f.name).toList(), ['Oatmeal', 'Eggs', 'Banana']);
    });

    test('excludes soft-deleted foods from recents', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);

      final clock = _FixedClock(DateTime(2026, 8, 21, 12, 0));
      final r = repo(db, clock: clock);

      final food1 = await insertFood(db, name: 'Food 1');
      final food2 = await insertFood(db, name: 'Food 2');

      await r.logFood(
        date: DateTime(2026, 8, 21),
        foodId: food1,
        grams: 100,
        loggedAt: DateTime(2026, 8, 21, 10, 0),
      );
      await r.logFood(
        date: DateTime(2026, 8, 21),
        foodId: food2,
        grams: 100,
        loggedAt: DateTime(2026, 8, 21, 9, 0),
      );

      await r.deleteFood(food1);

      final recents = await r.watchRecentlyLoggedFoods().first;
      expect(recents.map((f) => f.name).toList(), ['Food 2']);
    });
  });

  group('NutritionRepository.watchSuggestedFoods', () {
    test('suggests foods matching current hour and meal slot', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);

      final now = DateTime(2026, 8, 21, 8, 15);
      final clock = _FixedClock(now);
      final r = repo(db, clock: clock);

      final breakfastFood = await insertFood(db, name: 'Oatmeal & Berries');
      final lunchFood = await insertFood(db, name: 'Chicken Rice Bowl');
      final dinnerFood = await insertFood(db, name: 'Salmon & Broccoli');

      // User logged breakfast food at 8:00 AM for breakfast over several days
      for (int i = 1; i <= 3; i++) {
        await r.logFood(
          date: DateTime(2026, 8, 21 - i),
          mealKey: 'breakfast',
          foodId: breakfastFood,
          grams: 80,
          loggedAt: DateTime(2026, 8, 21 - i, 8, 0),
        );
      }

      // User logged lunch food at 13:00 for lunch
      for (int i = 1; i <= 3; i++) {
        await r.logFood(
          date: DateTime(2026, 8, 21 - i),
          mealKey: 'lunch',
          foodId: lunchFood,
          grams: 200,
          loggedAt: DateTime(2026, 8, 21 - i, 13, 0),
        );
      }

      // User logged dinner food at 19:30 for dinner
      for (int i = 1; i <= 3; i++) {
        await r.logFood(
          date: DateTime(2026, 8, 21 - i),
          mealKey: 'dinner',
          foodId: dinnerFood,
          grams: 250,
          loggedAt: DateTime(2026, 8, 21 - i, 19, 30),
        );
      }

      // Query suggestions for 8:00 AM Breakfast
      final morningSuggestions = await r.watchSuggestedFoods(
        hour: 8,
        mealKey: 'breakfast',
      ).first;

      expect(morningSuggestions.map((f) => f.name), contains('Oatmeal & Berries'));
      expect(morningSuggestions.map((f) => f.name), isNot(contains('Chicken Rice Bowl')));
      expect(morningSuggestions.map((f) => f.name), isNot(contains('Salmon & Broccoli')));

      // Query suggestions for 13:00 Lunch
      final lunchSuggestions = await r.watchSuggestedFoods(
        hour: 13,
        mealKey: 'lunch',
      ).first;

      expect(lunchSuggestions.map((f) => f.name), contains('Chicken Rice Bowl'));
      expect(lunchSuggestions.map((f) => f.name), isNot(contains('Oatmeal & Berries')));
      expect(lunchSuggestions.map((f) => f.name), isNot(contains('Salmon & Broccoli')));
    });

    test('excludes soft-deleted foods from suggestions', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);

      final now = DateTime(2026, 8, 21, 8, 0);
      final clock = _FixedClock(now);
      final r = repo(db, clock: clock);

      final food = await insertFood(db, name: 'Deleted Breakfast Food');
      await r.logFood(
        date: DateTime(2026, 8, 20),
        mealKey: 'breakfast',
        foodId: food,
        grams: 100,
        loggedAt: DateTime(2026, 8, 20, 8, 0),
      );

      await r.deleteFood(food);

      final suggestions = await r.watchSuggestedFoods(
        hour: 8,
        mealKey: 'breakfast',
      ).first;

      expect(suggestions.map((f) => f.name), isNot(contains('Deleted Breakfast Food')));
    });
  });
}
