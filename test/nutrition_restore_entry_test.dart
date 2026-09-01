import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/nutrition/data/nutrition_repository.dart';
import 'package:herculex/features/nutrition/data/openfoodfacts_client.dart';

import 'support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'NutritionRepository deleteEntry and restoreEntry restores food item',
    () async {
      final db = await openTestDatabase();
      addTearDown(db.close);
      final repo = NutritionRepository(
        db,
        OpenFoodFactsClient(),
        const SystemClock(),
      );

      final foodId = await db
          .into(db.foods)
          .insert(
            FoodsCompanion.insert(name: 'Protein Shake', kcalPer100g: 80),
          );

      final entryId = await repo.logFood(
        date: DateTime(2026, 8, 30),
        mealKey: 'breakfast',
        foodId: foodId,
        servings: 1.0,
        grams: 250,
      );

      var entries = await repo.watchEntriesForDate(DateTime(2026, 8, 30)).first;
      expect(entries.length, 1);
      final originalEntry = entries.first;

      // Delete entry
      await repo.deleteEntry(originalEntry.id);
      entries = await repo.watchEntriesForDate(DateTime(2026, 8, 30)).first;
      expect(entries.isEmpty, isTrue);

      // Restore entry
      await repo.restoreEntry(originalEntry);
      entries = await repo.watchEntriesForDate(DateTime(2026, 8, 30)).first;
      expect(entries.length, 1);
      expect(entries.first.foodId, foodId);
      expect(entries.first.gramsOverride, 250);

      await db.close();
    },
  );
}
