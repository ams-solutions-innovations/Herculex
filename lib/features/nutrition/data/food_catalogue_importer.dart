import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:drift/drift.dart';

import '../../../data/local/database.dart';

/// Imports the bundled v1 catalogue into the existing Foods table.
///
/// The importer is intentionally independent of the repository so it can run
/// during database creation/migration and be tested with a small JSON fixture.
class FoodCatalogueImporter {
  static const schemaVersion = 'herculex-food-catalogue/v1';
  static const assetPath = 'assets/data/food_database_eu.v1.json';

  static Future<void> runIfNeeded(AppDatabase db, {String? catalogueJson}) async {
    final marker = await (db.select(db.foodCatalogueMeta)..limit(1)).getSingleOrNull();
    if (marker?.schemaVersion == schemaVersion && marker?.foodCount != null) return;

    final raw = catalogueJson ?? await rootBundle.loadString(assetPath);
    final document = jsonDecode(raw) as Map<String, dynamic>;
    if (document['schemaVersion'] != schemaVersion) {
      throw StateError('Unsupported food catalogue schema');
    }
    final foods = (document['foods'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final expected = (document['statistics'] as Map?)?['foodCount'];
    if (expected is! int || foods.length != expected) {
      throw StateError('Food catalogue count does not match its metadata');
    }

    await db.transaction(() async {
      // A missing marker means the previous import did not complete. Only
      // seeded rows with no logged history are replaceable outright; custom
      // foods always remain. Catalogue rows still referenced by a food_entry
      // or recipe_ingredient must not be deleted here — under FK enforcement
      // that RESTRICT edge would throw and roll back the whole migration.
      // They are updated in place below instead.
      final referencedFoodIds = <int>{
        ...await (db.selectOnly(db.foodEntries, distinct: true)
              ..addColumns([db.foodEntries.foodId])
              ..where(db.foodEntries.foodId.isNotNull()))
            .map((row) => row.read(db.foodEntries.foodId)!)
            .get(),
        ...await (db.selectOnly(db.recipeIngredients, distinct: true)
              ..addColumns([db.recipeIngredients.foodId]))
            .map((row) => row.read(db.recipeIngredients.foodId)!)
            .get(),
      };

      final existingCatalogueRows = await (db.select(
        db.foods,
      )..where((t) => t.source.equals('food_catalogue_v1'))).get();

      final staleIds = existingCatalogueRows
          .where((f) => !referencedFoodIds.contains(f.id))
          .map((f) => f.id)
          .toList();
      if (staleIds.isNotEmpty) {
        await (db.delete(db.foods)..where((t) => t.id.isIn(staleIds))).go();
      }

      final existingByCatalogueId = {
        for (final f in existingCatalogueRows)
          if (f.catalogueId != null && !staleIds.contains(f.id))
            f.catalogueId!: f,
      };

      for (var start = 0; start < foods.length; start += 250) {
        final end = (start + 250).clamp(0, foods.length);
        final chunk = foods.sublist(start, end);
        await db.batch((batch) {
          for (final item in chunk) {
            final companion = _foodCompanion(item);
            final existing = existingByCatalogueId[item['id']?.toString()];
            if (existing != null) {
              batch.update(
                db.foods,
                companion,
                where: (t) => t.id.equals(existing.id),
              );
            } else {
              batch.insert(db.foods, companion);
            }
          }
        });
      }

      await db.into(db.foodCatalogueMeta).insertOnConflictUpdate(
            FoodCatalogueMetaCompanion.insert(
              id: const Value(1),
              schemaVersion: schemaVersion,
              foodCount: foods.length,
              importedAt: DateTime.now(),
            ),
          );
    });
  }

  static FoodsCompanion _foodCompanion(Map<String, dynamic> item) {
    final nutrients = _map(item['nutrients']);
    final catalogue = _map(item['catalogue']);
    final serving = _map(item['serving']);
    final metadata = <String, dynamic>{
      'nutrients': nutrients,
      'dietaryClaims': item['dietaryClaims'],
      'allergens': item['allergens'],
      'provenance': item['provenance'],
      'quality': item['quality'],
    }..removeWhere((_, value) => value == null);

    final amount = _number(serving['amount']);
    final weight = _number(serving['weightGramsOrMl']);
    final unit = serving['unit']?.toString();
    final label = amount == null && unit == null
        ? null
        : '${amount ?? ''}${unit == null ? '' : ' $unit'}'.trim();

    return FoodsCompanion.insert(
      name: item['name']?.toString() ?? 'Unknown food',
      brand: Value(catalogue['brand']?.toString()),
      barcode: Value(item['barcode']?.toString()),
      kcalPer100g: _number(nutrients['energy_kcal']) ?? 0,
      proteinPer100g: Value(_number(nutrients['protein']) ?? 0),
      carbsPer100g: Value(_number(nutrients['carbohydrates']) ?? 0),
      fatPer100g: Value(_number(nutrients['fat']) ?? 0),
      fiberPer100g: Value(_number(nutrients['fiber'])),
      servingGrams: Value(weight),
      servingLabel: Value(label),
      source: const Value('food_catalogue_v1'),
      isCustom: const Value(false),
      sodiumMgPer100g: Value(_number(nutrients['sodium'])),
      potassiumMgPer100g: Value(_number(nutrients['potassium'])),
      cholesterolMgPer100g: Value(_number(nutrients['cholesterol'])),
      catalogueId: Value(item['id']?.toString()),
      referenceBasis: Value(item['referenceBasis']?.toString() ?? '100 g'),
      servingAmount: Value(amount),
      servingUnit: Value(unit),
      category: Value(catalogue['category']?.toString()),
      country: Value(catalogue['country']?.toString()),
      sourceMetadataJson: Value(jsonEncode(metadata)),
    );
  }

  static Map<String, dynamic> _map(dynamic value) =>
      value is Map ? value.cast<String, dynamic>() : <String, dynamic>{};

  static double? _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}
