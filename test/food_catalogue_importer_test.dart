import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/nutrition/data/food_catalogue_importer.dart';
import 'package:herculex/features/nutrition/data/nutrition_repository.dart';
import 'package:herculex/features/nutrition/data/openfoodfacts_client.dart';

import 'support/test_database.dart';

void main() {
  test('imports a catalogue fixture once and preserves source basis', () async {
    final db = await openTestDatabase();
    addTearDown(db.close);
    const fixture = '''{
      "schemaVersion":"herculex-food-catalogue/v1",
      "statistics":{"foodCount":1},
      "foods":[{
        "id":"TEST-1","name":"Test soup","barcode":"4006381333931",
        "referenceBasis":"Legacy serving (unverified)",
        "catalogue":{"brand":"Test brand","category":"Food","country":"Slovenia"},
        "serving":{"amount":1,"unit":"serving"},
        "nutrients":{"energy_kcal":120,"protein":4,"carbohydrates":10,"fat":6,"vitamin_c":2},
        "provenance":{"source":"fixture"}
      }]
    }''';

    await FoodCatalogueImporter.runIfNeeded(db, catalogueJson: fixture);
    await FoodCatalogueImporter.runIfNeeded(db, catalogueJson: fixture);

    final rows = await db.select(db.foods).get();
    expect(rows, hasLength(1));
    expect(rows.single.catalogueId, 'TEST-1');
    expect(rows.single.barcode, '4006381333931');
    expect(rows.single.referenceBasis, 'Legacy serving (unverified)');
    expect(rows.single.sourceMetadataJson, contains('vitamin_c'));

    final repo = NutritionRepository(db, OpenFoodFactsClient(), SystemClock());
    expect((await repo.lookupBarcode('4006381333931'))?.name, 'Test soup');
  });

  test(
    'a re-import updates a logged catalogue food in place under FK enforcement',
    () async {
      final db = await openTestDatabase();
      addTearDown(db.close);

      const fixtureV1 = '''{
      "schemaVersion":"herculex-food-catalogue/v1",
      "statistics":{"foodCount":1},
      "foods":[{
        "id":"TEST-1","name":"Test soup","barcode":"4006381333931",
        "referenceBasis":"Legacy serving (unverified)",
        "catalogue":{"brand":"Test brand","category":"Food","country":"Slovenia"},
        "serving":{"amount":1,"unit":"serving"},
        "nutrients":{"energy_kcal":120,"protein":4,"carbohydrates":10,"fat":6,"vitamin_c":2},
        "provenance":{"source":"fixture"}
      }]
    }''';

      await FoodCatalogueImporter.runIfNeeded(db, catalogueJson: fixtureV1);
      final firstImportRow = (await db.select(db.foods).get()).single;

      // Force a re-import: reset the marker so runIfNeeded doesn't short-circuit.
      await (db.delete(
        db.foodCatalogueMeta,
      )..where((t) => t.id.equals(1))).go();

      // Log an entry against the seeded catalogue food before re-importing —
      // this is the exact scenario that used to throw and roll back the
      // whole migration under FK enforcement (RESTRICT on food_entries).
      await db
          .into(db.foodEntries)
          .insert(
            FoodEntriesCompanion.insert(
              dateIso: '2026-01-01',
              meal: 'lunch',
              foodId: Value(firstImportRow.id),
            ),
          );

      const fixtureV2 = '''{
      "schemaVersion":"herculex-food-catalogue/v1",
      "statistics":{"foodCount":1},
      "foods":[{
        "id":"TEST-1","name":"Test soup (updated)","barcode":"4006381333931",
        "referenceBasis":"Legacy serving (unverified)",
        "catalogue":{"brand":"Test brand","category":"Food","country":"Slovenia"},
        "serving":{"amount":1,"unit":"serving"},
        "nutrients":{"energy_kcal":130,"protein":5,"carbohydrates":11,"fat":6,"vitamin_c":2},
        "provenance":{"source":"fixture"}
      }]
    }''';

      // Must not throw: the old code deleted every 'food_catalogue_v1' row
      // first, which would hit the RESTRICT edge and roll back the migration.
      await FoodCatalogueImporter.runIfNeeded(db, catalogueJson: fixtureV2);

      final rows = await db.select(db.foods).get();
      expect(rows, hasLength(1));
      expect(
        rows.single.id,
        firstImportRow.id,
        reason: 'updated in place, not replaced',
      );
      expect(rows.single.name, 'Test soup (updated)');
      expect(rows.single.kcalPer100g, 130);

      final entries = await db.select(db.foodEntries).get();
      expect(entries, hasLength(1));
      expect(entries.single.foodId, firstImportRow.id);
    },
  );

  test(
    'keeps named portions meaningful for scoops and individual nuggets',
    () async {
      final db = await openTestDatabase();
      addTearDown(db.close);
      const fixture = '''{
      "schemaVersion":"herculex-food-catalogue/v1",
      "statistics":{"foodCount":2},
      "foods":[
        {
          "id":"SCOOP-1","name":"Test whey","referenceBasis":"100 g",
          "catalogue":{"originalName":"Test whey"},
          "serving":{"amount":1,"unit":"scoop","weightGramsOrMl":30},
          "nutrients":{"energy_kcal":400,"protein":80,"carbohydrates":5,"fat":5}
        },
        {
          "id":"NUGGET-1","name":"Chicken nuggets (4 kosi)",
          "referenceBasis":"Legacy serving (unverified)",
          "catalogue":{"originalName":"Chicken nuggets (4 kosi)"},
          "serving":{"amount":1,"unit":"serving"},
          "nutrients":{"energy_kcal":160,"protein":8,"carbohydrates":10,"fat":8}
        }
      ]
    }''';

      await FoodCatalogueImporter.runIfNeeded(db, catalogueJson: fixture);
      final foods = await db.select(db.foods).get();
      final whey = foods.firstWhere((food) => food.catalogueId == 'SCOOP-1');
      final nuggets = foods.firstWhere(
        (food) => food.catalogueId == 'NUGGET-1',
      );
      expect(whey.servingLabel, '1 scoop (30 g)');
      expect(nuggets.servingLabel, '4 nugget');

      final repo = NutritionRepository(
        db,
        OpenFoodFactsClient(),
        SystemClock(),
      );
      final now = DateTime(2026, 1, 1);
      await repo.logFood(
        date: now,
        foodId: whey.id,
        portionAmount: 1,
        portionUnit: 'scoop',
      );
      await repo.logFood(
        date: now,
        foodId: nuggets.id,
        portionAmount: 1,
        portionUnit: 'nugget',
      );
      final entries = await db.select(db.foodEntries).get();
      final wheyTotals = await repo.macrosForEntry(entries[0]);
      final nuggetTotals = await repo.macrosForEntry(entries[1]);
      expect(wheyTotals.kcal, 120); // 30 g of 400 kcal / 100 g.
      expect(nuggetTotals.kcal, 40); // one of the labelled four nuggets.
    },
  );
}
