import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/nutrition/data/nutrition_repository.dart';
import 'package:herculex/features/nutrition/data/openfoodfacts_client.dart';

import 'support/test_database.dart';

/// RB-05 Step 4: soft-delete activation. Covers the query filtering added in
/// 4a, the soft-delete writes added in 4b/4c, and the two 4d call-shape
/// decisions (`updateCustomFood` writes through; entries keep resolving a
/// soft-deleted food/recipe).
class _FixedClock implements Clock {
  final DateTime fixed;
  _FixedClock(this.fixed);
  @override
  DateTime now() => fixed;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<int> insertFood(
    AppDatabase db, {
    String name = 'Chicken',
    double kcal = 165,
    String? barcode,
  }) {
    return db
        .into(db.foods)
        .insert(
          FoodsCompanion.insert(
            name: name,
            kcalPer100g: kcal,
            isCustom: const Value(true),
            source: const Value('local'),
            barcode: Value(barcode),
          ),
        );
  }

  NutritionRepository repo(AppDatabase db, {Clock? clock}) =>
      NutritionRepository(db, OpenFoodFactsClient(), clock ?? const SystemClock());

  group('catalogue-facing reads exclude soft-deleted rows', () {
    test('watchFoods', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);
      final r = repo(db);
      final keptId = await insertFood(db, name: 'Kept');
      final deletedId = await insertFood(db, name: 'Deleted');
      await r.deleteFood(deletedId);

      final foods = await r.watchFoods().first;
      expect(foods.map((f) => f.id), contains(keptId));
      expect(foods.map((f) => f.id), isNot(contains(deletedId)));
    });

    test('searchFoods', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);
      final r = repo(db);
      final deletedId = await insertFood(db, name: 'Banana Bread');
      await r.deleteFood(deletedId);

      final results = await r.searchFoods('Banana');
      expect(results, isEmpty);
    });

    test('lookupBarcode does not resurrect a soft-deleted food', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);
      final r = repo(db);
      final deletedId = await insertFood(db, barcode: '0012345678905');
      await r.deleteFood(deletedId);

      final found = await r.lookupBarcode('0012345678905');
      expect(found, isNull);
    });

    test('watchCustomFoods', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);
      final r = repo(db);
      final deletedId = await insertFood(db, name: 'Custom Thing');
      await r.deleteFood(deletedId);

      final foods = await r.watchCustomFoods().first;
      expect(foods.map((f) => f.id), isNot(contains(deletedId)));
    });

    test('watchRecipes', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);
      final r = repo(db);
      final keptId = await r.createRecipe(name: 'Kept Recipe');
      final deletedId = await r.createRecipe(name: 'Deleted Recipe');
      await r.deleteRecipe(deletedId);

      final recipes = await r.watchRecipes().first;
      expect(recipes.map((x) => x.id), contains(keptId));
      expect(recipes.map((x) => x.id), isNot(contains(deletedId)));
    });

    test('recentFoods', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);
      final clock = _FixedClock(DateTime(2026, 6, 15));
      final r = repo(db, clock: clock);
      final deletedId = await insertFood(db, name: 'Frequently Logged');
      await r.logFood(date: clock.fixed, foodId: deletedId, grams: 100);
      await r.deleteFood(deletedId);

      final recent = await r.recentFoods();
      expect(recent.map((f) => f.id), isNot(contains(deletedId)));
    });
  });

  group('history-resolution lookups stay unfiltered', () {
    test('foodById/foodsByIds/watchFoodById still resolve a soft-deleted food', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);
      final r = repo(db);
      final id = await insertFood(db, name: 'Old Food');
      await r.deleteFood(id);

      expect((await r.foodById(id))?.name, 'Old Food');
      expect((await r.foodsByIds([id]))[id]?.name, 'Old Food');
      expect((await r.watchFoodById(id).first)?.name, 'Old Food');
    });

    test('recipeById still resolves a soft-deleted recipe', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);
      final r = repo(db);
      final id = await r.createRecipe(name: 'Old Recipe');
      await r.deleteRecipe(id);

      expect((await r.recipeById(id))?.name, 'Old Recipe');
    });

    test('macrosForEntry resolves an unsnapshotted entry against a soft-deleted food', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);
      final r = repo(db);
      final foodId = await insertFood(db, name: 'Old Food', kcal: 200);
      // Simulate a pre-v24 row: insert directly with no snapshot columns,
      // rather than going through logFood (which always snapshots now).
      final entryId = await db
          .into(db.foodEntries)
          .insert(
            FoodEntriesCompanion.insert(
              dateIso: '2026-01-01',
              meal: 'lunch',
              foodId: Value(foodId),
              portionAmount: const Value(100),
              portionUnit: const Value('g'),
            ),
          );
      await r.deleteFood(foodId);

      final entry = await (db.select(
        db.foodEntries,
      )..where((t) => t.id.equals(entryId))).getSingle();
      final totals = await r.macrosForEntry(entry);
      expect(totals.kcal, 200);
    });

    test('a logged entry keeps resolving via its snapshot after the food is deleted', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);
      final r = repo(db);
      final foodId = await insertFood(db, name: 'Snapshot Food', kcal: 300);
      await r.logFood(date: DateTime(2026, 1, 1), foodId: foodId, grams: 100);
      await r.deleteFood(foodId);

      final entries = await r.watchEntriesForDate(DateTime(2026, 1, 1)).first;
      expect(entries, hasLength(1));
      final totals = await r.macrosForEntry(entries.single);
      expect(totals.kcal, 300);
    });
  });

  group('updateCustomFood (4d decision: writes through unconditionally)', () {
    test('editing a soft-deleted food still succeeds and the edit persists', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);
      final r = repo(db);
      final id = await insertFood(db, name: 'Old Name', kcal: 100);
      await r.deleteFood(id);

      final updated = await r.updateCustomFood(
        id: id,
        name: 'New Name',
        kcalPer100g: 150,
      );

      expect(updated.name, 'New Name');
      expect(updated.kcalPer100g, 150);
      // The edit doesn't undo the soft delete — it's still hidden from
      // catalogue search either way.
      expect(updated.deletedAt, isNotNull);
    });
  });
}
