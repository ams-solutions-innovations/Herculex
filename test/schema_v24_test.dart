import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/nutrition/data/nutrition_repository.dart';
import 'package:herculex/features/nutrition/data/openfoodfacts_client.dart';

/// A throwaway drift database used only to lay down a v23-shaped nutrition
/// schema on a file, so that reopening the file as [AppDatabase]
/// (schemaVersion 24) runs the real `onUpgrade` path from 23. Declaring no
/// tables keeps `createAll()` a no-op; the DDL below is the hand-written v23
/// shape of the four tables the v24 (RB-05) migration touches.
class _V23Fixture extends GeneratedDatabase {
  _V23Fixture(super.executor);

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];

  @override
  int get schemaVersion => 23;
}

class _FixedClock implements Clock {
  DateTime fixed;
  _FixedClock(this.fixed);
  @override
  DateTime now() => fixed;
}

const _v23Ddl = <String>[
  '''
  CREATE TABLE foods (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    brand TEXT NULL,
    barcode TEXT NULL,
    kcal_per100g REAL NOT NULL,
    protein_per100g REAL NOT NULL DEFAULT 0,
    carbs_per100g REAL NOT NULL DEFAULT 0,
    fat_per100g REAL NOT NULL DEFAULT 0,
    fiber_per100g REAL NULL,
    serving_grams REAL NULL,
    serving_label TEXT NULL,
    source TEXT NOT NULL DEFAULT 'local',
    image_url TEXT NULL,
    is_custom INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    sodium_mg_per100g REAL NULL,
    potassium_mg_per100g REAL NULL,
    cholesterol_mg_per100g REAL NULL,
    catalogue_id TEXT NULL,
    reference_basis TEXT NOT NULL DEFAULT '100 g',
    serving_amount REAL NULL,
    serving_unit TEXT NULL,
    category TEXT NULL,
    country TEXT NULL,
    source_metadata_json TEXT NULL)
  ''',
  '''
  CREATE TABLE recipes (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    servings INTEGER NOT NULL DEFAULT 1,
    notes TEXT NULL,
    created_at INTEGER NOT NULL)
  ''',
  '''
  CREATE TABLE recipe_ingredients (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    recipe_id INTEGER NOT NULL REFERENCES recipes (id) ON DELETE CASCADE,
    food_id INTEGER NOT NULL REFERENCES foods (id) ON DELETE RESTRICT,
    grams REAL NOT NULL)
  ''',
  '''
  CREATE TABLE food_entries (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    date_iso TEXT NOT NULL,
    meal TEXT NOT NULL,
    food_id INTEGER NULL REFERENCES foods (id) ON DELETE RESTRICT,
    recipe_id INTEGER NULL REFERENCES recipes (id) ON DELETE RESTRICT,
    servings REAL NOT NULL DEFAULT 1,
    grams_override REAL NULL,
    portion_amount REAL NULL,
    portion_unit TEXT NULL,
    logged_at INTEGER NOT NULL)
  ''',
];

/// Seed covering every `_portionFactor` branch from
/// `test/phase5_nutrition_test.dart`, reusing its pinned constants:
///   - food 1 "Fortified Drink": a `'100 ml'` basis food with source-JSON
///     micros (vitamin_c, iron). Entry 1 logs 250 ml -> 500 kcal / 25 g
///     protein / vitamin_c 10 / iron 3.75 (factor 2.5).
///   - food 2 "Legacy Bar": a `'Legacy serving (unverified)'` basis food
///     with a 50 g serving weight and a magnesium micro. Entry 2 logs 2
///     servings (unit 'serving') and entry 3 logs a 100 g `gramsOverride`
///     with no portionAmount/portionUnit -- both resolve to factor 2 ->
///     500 kcal / magnesium 40.
///   - recipe 1 "Test Recipe" (2 servings, ingredients = food 1 @ 100 g +
///     food 2 @ 100 g) -> per-serving totals: kcal (200 + 250) / 2 = 225,
///     protein (10 + 0) / 2 = 5. Entry 4 logs 2 servings of it.
///   - entry 5: both `food_id` and `recipe_id` NULL, the post-v23
///     FK-repair orphan shape -- must not crash the backfill and must stay
///     unsnapshotted.
const _v23Seed = <String>[
  '''
  INSERT INTO foods (id, name, kcal_per100g, protein_per100g, reference_basis,
    created_at, source_metadata_json)
  VALUES (1, 'Fortified Drink', 200, 10, '100 ml',
    strftime('%s', '2026-06-01'), '{"nutrients":{"vitamin_c":4,"iron":1.5}}')
  ''',
  '''
  INSERT INTO foods (id, name, kcal_per100g, serving_grams, serving_amount,
    serving_unit, reference_basis, created_at, source_metadata_json)
  VALUES (2, 'Legacy Bar', 250, 50, 1, 'serving',
    'Legacy serving (unverified)', strftime('%s', '2026-06-01'),
    '{"nutrients":{"magnesium":20}}')
  ''',
  '''
  INSERT INTO recipes (id, name, servings, created_at)
  VALUES (1, 'Test Recipe', 2, strftime('%s', '2026-06-01'))
  ''',
  'INSERT INTO recipe_ingredients (id, recipe_id, food_id, grams) '
      'VALUES (1, 1, 1, 100)',
  'INSERT INTO recipe_ingredients (id, recipe_id, food_id, grams) '
      'VALUES (2, 1, 2, 100)',
  '''
  INSERT INTO food_entries (id, date_iso, meal, food_id, servings,
    portion_amount, portion_unit, logged_at)
  VALUES (1, '2026-06-15', 'breakfast', 1, 1, 250, 'ml',
    strftime('%s', '2026-06-15 08:00:00'))
  ''',
  '''
  INSERT INTO food_entries (id, date_iso, meal, food_id, servings,
    portion_amount, portion_unit, logged_at)
  VALUES (2, '2026-06-15', 'lunch', 2, 1, 2, 'serving',
    strftime('%s', '2026-06-15 12:00:00'))
  ''',
  '''
  INSERT INTO food_entries (id, date_iso, meal, food_id, servings,
    grams_override, logged_at)
  VALUES (3, '2026-06-15', 'snack', 2, 1, 100,
    strftime('%s', '2026-06-15 16:00:00'))
  ''',
  '''
  INSERT INTO food_entries (id, date_iso, meal, recipe_id, servings,
    logged_at)
  VALUES (4, '2026-06-15', 'dinner', 1, 2,
    strftime('%s', '2026-06-15 19:00:00'))
  ''',
  '''
  INSERT INTO food_entries (id, date_iso, meal, servings, logged_at)
  VALUES (5, '2026-06-16', 'breakfast', 1,
    strftime('%s', '2026-06-16 08:00:00'))
  ''',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File dbFile;
  late AppDatabase db;
  late NutritionRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('herculex_v24_');
    dbFile = File('${tempDir.path}/app.sqlite');

    // 1. Lay down the v23 schema + fixture rows and stamp user_version = 23.
    final fixture = _V23Fixture(NativeDatabase(dbFile));
    for (final stmt in [..._v23Ddl, ..._v23Seed]) {
      await fixture.customStatement(stmt);
    }
    await fixture.close();

    // 2. Reopen as the real database — this runs onUpgrade(23 -> 24).
    db = AppDatabase.forTesting(NativeDatabase(dbFile));
    await db.customStatement('PRAGMA foreign_keys = ON');
    // Force the migration to run before the assertions.
    await db.select(db.foods).get();
    repo = NutritionRepository(
      db,
      OpenFoodFactsClient(),
      _FixedClock(DateTime(2026, 6, 15, 12)),
    );
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  group('v23 -> v24 migration (RB-05 nutrition snapshot)', () {
    test('reaches schema version 24', () async {
      final row = await db.customSelect('PRAGMA user_version').getSingle();
      expect(row.data.values.first, 24);
    });

    test('food entry snapshot copies the food row basis untouched', () async {
      final entry = await (db.select(
        db.foodEntries,
      )..where((t) => t.id.equals(1))).getSingle();
      expect(entry.snapshotBasis, '100 ml');
      expect(entry.snapshotName, 'Fortified Drink');
      expect(entry.snapshotBrand, isNull);
      expect(entry.snapshotKcal, 200);
      expect(entry.snapshotProteinG, 10);
      expect(entry.snapshotCarbsG, 0);
      expect(entry.snapshotFatG, 0);
      expect(entry.snapshotFiberG, isNull);
      expect(entry.snapshotServingGrams, isNull);
      expect(entry.snapshotServingAmount, isNull);
      expect(entry.snapshotServingUnit, isNull);
      expect(entry.snapshotMicrosJson, '{"vitamin_c":4.0,"iron":1.5}');
    });

    test(
      'backfilled snapshot reproduces the live 100 ml portion math',
      () async {
        final entry = await (db.select(
          db.foodEntries,
        )..where((t) => t.id.equals(1))).getSingle();
        final totals = await repo.macrosForEntry(entry);
        expect(totals.kcal, 500);
        expect(totals.proteinG, 25);
        expect(totals.micros['vitamin_c'], 10);
        expect(totals.micros['iron'], 3.75);
      },
    );

    test(
      'backfilled snapshot reproduces the live legacy-serving math for '
      'both a serving-unit and a gramsOverride entry',
      () async {
        final servingEntry = await (db.select(
          db.foodEntries,
        )..where((t) => t.id.equals(2))).getSingle();
        expect(servingEntry.snapshotBasis, 'Legacy serving (unverified)');
        expect(servingEntry.snapshotKcal, 250);
        expect(servingEntry.snapshotServingGrams, 50);
        expect(servingEntry.snapshotServingAmount, 1);
        expect(servingEntry.snapshotServingUnit, 'serving');
        expect(servingEntry.snapshotMicrosJson, '{"magnesium":20.0}');
        final servingTotals = await repo.macrosForEntry(servingEntry);
        expect(servingTotals.kcal, 500);
        expect(servingTotals.micros['magnesium'], 40);

        final gramsEntry = await (db.select(
          db.foodEntries,
        )..where((t) => t.id.equals(3))).getSingle();
        // Same underlying food -> identical basis snapshot regardless of
        // how this particular entry was portioned.
        expect(gramsEntry.snapshotKcal, 250);
        final gramsTotals = await repo.macrosForEntry(gramsEntry);
        expect(gramsTotals.kcal, 500);
        expect(gramsTotals.micros['magnesium'], 40);
      },
    );

    test(
      'recipe entry snapshot holds per-serving totals, scaled at read time '
      'by entry.servings',
      () async {
        final entry = await (db.select(
          db.foodEntries,
        )..where((t) => t.id.equals(4))).getSingle();
        expect(entry.snapshotBasis, 'recipe serving');
        expect(entry.snapshotName, 'Test Recipe');
        expect(entry.snapshotKcal, 225);
        expect(entry.snapshotProteinG, 5);
        expect(entry.snapshotCarbsG, 0);
        expect(entry.snapshotFatG, 0);
        // Recipe entries never carry a serving-grams/amount/unit snapshot —
        // the read path scales by entry.servings, not a portion factor.
        expect(entry.snapshotServingGrams, isNull);
        expect(entry.snapshotMicrosJson, isNull);

        final totals = await repo.macrosForEntry(entry);
        expect(totals.kcal, 450); // 225 per serving * 2 logged servings
        expect(totals.proteinG, 10);
      },
    );

    test(
      'an entry with no food_id and no recipe_id stays unsnapshotted and '
      'does not crash the backfill',
      () async {
        final entry = await (db.select(
          db.foodEntries,
        )..where((t) => t.id.equals(5))).getSingle();
        expect(entry.snapshotBasis, isNull);
        expect(entry.foodId, isNull);
        expect(entry.recipeId, isNull);

        final totals = await repo.macrosForEntry(entry);
        expect(totals.kcal, 0);
      },
    );

    test('foods and recipes gained a nullable deletedAt column', () async {
      final food = await (db.select(
        db.foods,
      )..where((t) => t.id.equals(1))).getSingle();
      expect(food.deletedAt, isNull);

      final recipe = await (db.select(
        db.recipes,
      )..where((t) => t.id.equals(1))).getSingle();
      expect(recipe.deletedAt, isNull);
    });
  });
}
