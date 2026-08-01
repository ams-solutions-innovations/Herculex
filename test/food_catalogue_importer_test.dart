import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/nutrition/data/food_catalogue_importer.dart';
import 'package:herculex/features/nutrition/data/nutrition_repository.dart';
import 'package:herculex/features/nutrition/data/openfoodfacts_client.dart';
import 'package:herculex/core/clock.dart';

void main() {
  test('imports a catalogue fixture once and preserves source basis', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
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
}
