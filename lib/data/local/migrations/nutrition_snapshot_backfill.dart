import 'dart:convert';

import 'package:drift/drift.dart';

/// Per-pass counts produced by [backfillNutritionSnapshots], for logging and
/// for tests to assert on.
class NutritionSnapshotBackfillReport {
  const NutritionSnapshotBackfillReport({
    required this.foodEntries,
    required this.recipeEntries,
    required this.microsFoods,
  });

  /// Rows updated by the food-entry snapshot pass.
  final int foodEntries;

  /// Rows updated by the recipe-entry snapshot pass.
  final int recipeEntries;

  /// Distinct foods whose micronutrients were copied onto referencing
  /// entries.
  final int microsFoods;
}

/// RB-05 v24 migration: freezes each diary entry's nutrition at log time so
/// history stops moving when the catalogue is edited or a food is deleted.
///
/// Takes [GeneratedDatabase] rather than `AppDatabase` so it can run from
/// both a migration and a test. Written against raw `customStatement` /
/// `customSelect` / `customUpdate` only — migration code must stay frozen
/// against the schema version it shipped with (drift table accessors track
/// the *current* schema, not the historical one), per `fk_repair.dart`.
///
/// Runs with `PRAGMA foreign_keys` off (migrations always do), so every
/// statement here is a plain, unenforced `UPDATE`.
Future<NutritionSnapshotBackfillReport> backfillNutritionSnapshots(
  GeneratedDatabase db,
) async {
  // ── Pass 1: food entries — pure SQL column copy. Storing the nutrient
  // basis rather than computed totals means this is a direct copy of the
  // matching `foods` row, with no `_portionFactor` reproduction needed.
  // Correlated subqueries rather than `UPDATE ... FROM` (SQLite 3.33+):
  // `sqlite3_flutter_libs` bundles a new enough engine everywhere, but a
  // migration is the one place zero version risk beats terseness.
  final foodEntries = await db.customUpdate('''
    UPDATE food_entries SET
      snapshot_basis          = (SELECT f.reference_basis        FROM foods f WHERE f.id = food_entries.food_id),
      snapshot_name           = (SELECT f.name                   FROM foods f WHERE f.id = food_entries.food_id),
      snapshot_brand          = (SELECT f.brand                  FROM foods f WHERE f.id = food_entries.food_id),
      snapshot_kcal           = (SELECT f.kcal_per100g           FROM foods f WHERE f.id = food_entries.food_id),
      snapshot_protein_g      = (SELECT f.protein_per100g        FROM foods f WHERE f.id = food_entries.food_id),
      snapshot_carbs_g        = (SELECT f.carbs_per100g          FROM foods f WHERE f.id = food_entries.food_id),
      snapshot_fat_g          = (SELECT f.fat_per100g            FROM foods f WHERE f.id = food_entries.food_id),
      snapshot_fiber_g        = (SELECT f.fiber_per100g          FROM foods f WHERE f.id = food_entries.food_id),
      snapshot_sodium_mg      = (SELECT f.sodium_mg_per100g      FROM foods f WHERE f.id = food_entries.food_id),
      snapshot_potassium_mg   = (SELECT f.potassium_mg_per100g   FROM foods f WHERE f.id = food_entries.food_id),
      snapshot_cholesterol_mg = (SELECT f.cholesterol_mg_per100g FROM foods f WHERE f.id = food_entries.food_id),
      snapshot_serving_grams  = (SELECT f.serving_grams          FROM foods f WHERE f.id = food_entries.food_id),
      snapshot_serving_amount = (SELECT f.serving_amount         FROM foods f WHERE f.id = food_entries.food_id),
      snapshot_serving_unit   = (SELECT f.serving_unit           FROM foods f WHERE f.id = food_entries.food_id)
    WHERE food_id IS NOT NULL
      AND snapshot_basis IS NULL
      AND EXISTS (SELECT 1 FROM foods f WHERE f.id = food_entries.food_id)
  ''');

  // ── Pass 2: recipe entries. `recipeMacrosPerServing` uses `ing.grams /
  // 100.0` unconditionally and never calls `_portionFactor`, so this is
  // exactly SQL-expressible. The `CASE` reproduces `recipe.servings == 0 ?
  // 1 : recipe.servings`; `COALESCE(f.<col>, 0)` reproduces the `?? 0`
  // fallbacks on the nullable food columns. Ingredients pointing at a
  // missing food are excluded via the `JOIN`, matching `if (food == null)
  // continue`.
  final recipeEntries = await db.customUpdate('''
    UPDATE food_entries SET
      snapshot_basis = 'recipe serving',
      snapshot_name  = (SELECT r.name FROM recipes r WHERE r.id = food_entries.recipe_id),
      snapshot_kcal = COALESCE((SELECT SUM(f.kcal_per100g * ri.grams / 100.0)
          FROM recipe_ingredients ri JOIN foods f ON f.id = ri.food_id
          WHERE ri.recipe_id = food_entries.recipe_id), 0)
        / (SELECT CASE WHEN r.servings = 0 THEN 1 ELSE r.servings END
           FROM recipes r WHERE r.id = food_entries.recipe_id),
      snapshot_protein_g = COALESCE((SELECT SUM(f.protein_per100g * ri.grams / 100.0)
          FROM recipe_ingredients ri JOIN foods f ON f.id = ri.food_id
          WHERE ri.recipe_id = food_entries.recipe_id), 0)
        / (SELECT CASE WHEN r.servings = 0 THEN 1 ELSE r.servings END
           FROM recipes r WHERE r.id = food_entries.recipe_id),
      snapshot_carbs_g = COALESCE((SELECT SUM(f.carbs_per100g * ri.grams / 100.0)
          FROM recipe_ingredients ri JOIN foods f ON f.id = ri.food_id
          WHERE ri.recipe_id = food_entries.recipe_id), 0)
        / (SELECT CASE WHEN r.servings = 0 THEN 1 ELSE r.servings END
           FROM recipes r WHERE r.id = food_entries.recipe_id),
      snapshot_fat_g = COALESCE((SELECT SUM(f.fat_per100g * ri.grams / 100.0)
          FROM recipe_ingredients ri JOIN foods f ON f.id = ri.food_id
          WHERE ri.recipe_id = food_entries.recipe_id), 0)
        / (SELECT CASE WHEN r.servings = 0 THEN 1 ELSE r.servings END
           FROM recipes r WHERE r.id = food_entries.recipe_id),
      snapshot_fiber_g = COALESCE((SELECT SUM(COALESCE(f.fiber_per100g, 0) * ri.grams / 100.0)
          FROM recipe_ingredients ri JOIN foods f ON f.id = ri.food_id
          WHERE ri.recipe_id = food_entries.recipe_id), 0)
        / (SELECT CASE WHEN r.servings = 0 THEN 1 ELSE r.servings END
           FROM recipes r WHERE r.id = food_entries.recipe_id),
      snapshot_sodium_mg = COALESCE((SELECT SUM(COALESCE(f.sodium_mg_per100g, 0) * ri.grams / 100.0)
          FROM recipe_ingredients ri JOIN foods f ON f.id = ri.food_id
          WHERE ri.recipe_id = food_entries.recipe_id), 0)
        / (SELECT CASE WHEN r.servings = 0 THEN 1 ELSE r.servings END
           FROM recipes r WHERE r.id = food_entries.recipe_id),
      snapshot_potassium_mg = COALESCE((SELECT SUM(COALESCE(f.potassium_mg_per100g, 0) * ri.grams / 100.0)
          FROM recipe_ingredients ri JOIN foods f ON f.id = ri.food_id
          WHERE ri.recipe_id = food_entries.recipe_id), 0)
        / (SELECT CASE WHEN r.servings = 0 THEN 1 ELSE r.servings END
           FROM recipes r WHERE r.id = food_entries.recipe_id),
      snapshot_cholesterol_mg = COALESCE((SELECT SUM(COALESCE(f.cholesterol_mg_per100g, 0) * ri.grams / 100.0)
          FROM recipe_ingredients ri JOIN foods f ON f.id = ri.food_id
          WHERE ri.recipe_id = food_entries.recipe_id), 0)
        / (SELECT CASE WHEN r.servings = 0 THEN 1 ELSE r.servings END
           FROM recipes r WHERE r.id = food_entries.recipe_id)
    WHERE recipe_id IS NOT NULL
      AND snapshot_basis IS NULL
      AND EXISTS (SELECT 1 FROM recipes r WHERE r.id = food_entries.recipe_id)
  ''');
  // `snapshot_serving_*` stays NULL for recipe entries — the read path
  // scales by `entry.servings`, not by a portion factor.

  // ── Pass 3: micros, Dart-side, O(distinct foods) not O(entries).
  // `_microsForFood` filters non-numeric JSON values and skips the
  // `energy_kcal` key, which SQL can't do cleanly. Iterating distinct
  // referenced foods (not entries) keeps a diary with thousands of entries
  // but few distinct foods cheap.
  final rows = await db.customSelect('''
    SELECT DISTINCT f.id, f.source_metadata_json, f.fiber_per100g,
           f.sodium_mg_per100g, f.potassium_mg_per100g, f.cholesterol_mg_per100g
    FROM foods f JOIN food_entries e ON e.food_id = f.id
  ''').get();

  var microsFoods = 0;
  for (final row in rows) {
    final micros = <String, double>{};
    final metadata = row.read<String?>('source_metadata_json');
    if (metadata != null) {
      try {
        final root = jsonDecode(metadata) as Map<String, dynamic>;
        final source = root['nutrients'];
        if (source is Map) {
          for (final item in source.entries) {
            if (item.value is num && item.key != 'energy_kcal') {
              micros[item.key.toString()] = (item.value as num).toDouble();
            }
          }
        }
      } catch (_) {
        // Legacy/custom rows may not have a JSON payload.
      }
    }
    void fallback(String key, double? value) {
      if (!micros.containsKey(key) && value != null) {
        micros[key] = value;
      }
    }

    fallback('fiber', row.read<double?>('fiber_per100g'));
    fallback('sodium', row.read<double?>('sodium_mg_per100g'));
    fallback('potassium', row.read<double?>('potassium_mg_per100g'));
    fallback('cholesterol', row.read<double?>('cholesterol_mg_per100g'));

    if (micros.isEmpty) continue;
    microsFoods++;
    await db.customUpdate(
      'UPDATE food_entries SET snapshot_micros_json = ? '
      'WHERE food_id = ? AND snapshot_micros_json IS NULL',
      variables: [Variable(jsonEncode(micros)), Variable(row.read<int>('id'))],
    );
  }

  return NutritionSnapshotBackfillReport(
    foodEntries: foodEntries,
    recipeEntries: recipeEntries,
    microsFoods: microsFoods,
  );
}
