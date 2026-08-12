import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/clock.dart';
import '../../../data/local/database.dart';
import '../domain/barcode_utils.dart';
import '../domain/daily_totals.dart';
import '../domain/meal.dart';
import 'openfoodfacts_client.dart';

class NutritionRepository {
  final AppDatabase _db;
  final Clock _clock;

  NutritionRepository(this._db, OpenFoodFactsClient _, this._clock);

  // ── Foods ──────────────────────────────────────────────────────────────

  Stream<List<FoodData>> watchFoods({String? query}) {
    final q = _db.select(_db.foods)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm(expression: t.name)]);
    if (query != null && query.trim().isNotEmpty) {
      final like = '%${query.trim()}%';
      q.where((t) => t.name.like(like) | t.brand.like(like));
    }
    return q.watch();
  }

  /// Local-only catalogue search. [includeRemote] remains for API
  /// compatibility, but this app deliberately does not make network calls.
  Future<List<FoodData>> searchFoods(
    String query, {
    bool includeRemote = false,
  }) async {
    final local =
        await (_db.select(_db.foods)
              ..where((t) => t.deletedAt.isNull())
              ..where((t) => t.name.like('%$query%') | t.brand.like('%$query%'))
              ..limit(20))
            .get();
    // The owned catalogue is authoritative. [includeRemote] remains in the
    // signature for caller compatibility but no network request is made.
    return local;
  }

  /// Unfiltered single-row lookup by primary key, deliberately not scoped
  /// by `deletedAt` — history needs to resolve a food regardless of whether
  /// it's still visible in catalogue search.
  Future<FoodData?> foodById(int id) {
    return (_db.select(_db.foods)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// Batched counterpart of [foodById] for call sites resolving several ids
  /// at once. Unfiltered by `deletedAt` for the same reason.
  Future<Map<int, FoodData>> foodsByIds(Iterable<int> ids) async {
    final idList = ids.toSet().toList();
    if (idList.isEmpty) return {};
    final foods = await (_db.select(
      _db.foods,
    )..where((t) => t.id.isIn(idList))).get();
    return {for (final f in foods) f.id: f};
  }

  /// Reactive counterpart of [foodById]. Unfiltered by `deletedAt` for the
  /// same reason.
  Stream<FoodData?> watchFoodById(int id) {
    return (_db.select(
      _db.foods,
    )..where((t) => t.id.equals(id))).watchSingleOrNull();
  }

  /// Local-only exact lookup. Barcode identifiers remain strings.
  Future<FoodData?> lookupBarcode(String barcode) async {
    final normalized = normalizeBarcode(barcode);
    if (normalized == null) return null;
    return _findByBarcode(normalized.lookupCandidates);
  }

  Future<FoodData?> _findByBarcode(List<String> barcodes) async {
    for (final barcode in barcodes) {
      final exact = await (_db.select(_db.foods)
            ..where((t) => t.barcode.equals(barcode))
            ..where((t) => t.deletedAt.isNull()))
          .getSingleOrNull();
      if (exact != null) return exact;
    }
    return null;
  }

  Future<FoodData> createCustomFood({
    required String name,
    String? brand,
    String? barcode,
    required double kcalPer100g,
    double proteinPer100g = 0,
    double carbsPer100g = 0,
    double fatPer100g = 0,
    double? servingGrams,
    String? servingLabel,
    String referenceBasis = '100 g',
    double? servingAmount,
    String? servingUnit,
    String? sourceMetadataJson,
    double? sodiumMgPer100g,
    double? potassiumMgPer100g,
    double? cholesterolMgPer100g,
  }) async {
    final id = await _db
        .into(_db.foods)
        .insert(
          FoodsCompanion.insert(
            name: name,
            brand: Value(brand),
            barcode: Value(
              barcode == null ? null : normalizeBarcode(barcode)?.value,
            ),
            kcalPer100g: kcalPer100g,
            proteinPer100g: Value(proteinPer100g),
            carbsPer100g: Value(carbsPer100g),
            fatPer100g: Value(fatPer100g),
            servingGrams: Value(servingGrams),
            servingLabel: Value(servingLabel),
            referenceBasis: Value(referenceBasis),
            servingAmount: Value(servingAmount),
            servingUnit: Value(servingUnit),
            sourceMetadataJson: Value(sourceMetadataJson),
            source: const Value('local'),
            isCustom: const Value(true),
            sodiumMgPer100g: Value(sodiumMgPer100g),
            potassiumMgPer100g: Value(potassiumMgPer100g),
            cholesterolMgPer100g: Value(cholesterolMgPer100g),
          ),
        );
    return (_db.select(_db.foods)..where((t) => t.id.equals(id))).getSingle();
  }

  Stream<List<FoodData>> watchCustomFoods({String? query}) {
    final q = _db.select(_db.foods)
      ..where((t) => t.isCustom.equals(true) | t.source.equals('local'))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm(expression: t.name)]);
    if (query != null && query.trim().isNotEmpty) {
      final like = '%${query.trim()}%';
      q.where((t) => t.name.like(like) | t.brand.like(like));
    }
    return q.watch();
  }

  /// RB-05: writes through unconditionally, including for a soft-deleted
  /// food. Deliberate — every UI path that reaches the edit sheet resolves
  /// its target food through [watchCustomFoods]/[watchFoods]/[searchFoods],
  /// which (4a) already exclude soft-deleted rows, so a soft-deleted food is
  /// unreachable here in normal use. Blocking it here too would be
  /// validation against a case the UI can't produce. And since Step 3's
  /// snapshots already insulate logged history from a food's live values,
  /// there's no correctness reason to block it even in a hypothetical direct
  /// call — the edit stays invisible to search either way.
  Future<FoodData> updateCustomFood({
    required int id,
    required String name,
    String? brand,
    String? barcode,
    required double kcalPer100g,
    double proteinPer100g = 0,
    double carbsPer100g = 0,
    double fatPer100g = 0,
    double? servingGrams,
    String? servingLabel,
    String referenceBasis = '100 g',
    double? servingAmount,
    String? servingUnit,
    String? sourceMetadataJson,
    double? sodiumMgPer100g,
    double? potassiumMgPer100g,
    double? cholesterolMgPer100g,
  }) async {
    await (_db.update(_db.foods)..where((t) => t.id.equals(id))).write(
      FoodsCompanion(
        name: Value(name),
        brand: Value(brand),
        barcode: Value(
          barcode == null ? null : normalizeBarcode(barcode)?.value,
        ),
        kcalPer100g: Value(kcalPer100g),
        proteinPer100g: Value(proteinPer100g),
        carbsPer100g: Value(carbsPer100g),
        fatPer100g: Value(fatPer100g),
        servingGrams: Value(servingGrams),
        servingLabel: Value(servingLabel),
        referenceBasis: Value(referenceBasis),
        servingAmount: Value(servingAmount),
        servingUnit: Value(servingUnit),
        sourceMetadataJson: Value(sourceMetadataJson),
        sodiumMgPer100g: Value(sodiumMgPer100g),
        potassiumMgPer100g: Value(potassiumMgPer100g),
        cholesterolMgPer100g: Value(cholesterolMgPer100g),
      ),
    );
    return (_db.select(_db.foods)..where((t) => t.id.equals(id))).getSingle();
  }

  /// RB-05: soft delete. Hides the food from every catalogue-facing query
  /// (4a) while `food_entries` / `recipe_ingredients` keep pointing at the
  /// still-present row, so both RESTRICT edges stay satisfiable and history
  /// (via the unfiltered [foodById]/[foodsByIds]) keeps resolving its name
  /// and snapshot context. `food_micros` rows are left in place — they have
  /// no read path anywhere in the app (verified: only written by the
  /// catalogue importer, never queried), so there's nothing to keep in sync.
  Future<void> deleteFood(int id) async {
    await (_db.update(_db.foods)..where((t) => t.id.equals(id))).write(
      FoodsCompanion(deletedAt: Value(_clock.now())),
    );
  }

  // ── Recipes ────────────────────────────────────────────────────────────

  Stream<List<RecipeData>> watchRecipes() {
    return (_db.select(_db.recipes)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  /// Unfiltered single-row lookup by primary key, deliberately not scoped
  /// by `deletedAt` — see [foodById].
  Future<RecipeData?> recipeById(int id) {
    return (_db.select(
      _db.recipes,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<int> createRecipe({
    required String name,
    int servings = 1,
    String? notes,
  }) {
    return _db
        .into(_db.recipes)
        .insert(
          RecipesCompanion.insert(
            name: name,
            servings: Value(servings),
            notes: Value(notes),
          ),
        );
  }

  Future<void> updateRecipe({
    required int id,
    required String name,
    int servings = 1,
    String? notes,
  }) async {
    await (_db.update(_db.recipes)..where((t) => t.id.equals(id))).write(
      RecipesCompanion(
        name: Value(name),
        servings: Value(servings),
        notes: Value(notes),
      ),
    );
  }

  /// RB-05: soft delete, mirroring [deleteFood]. `recipe_ingredients` rows
  /// are left in place rather than cascade-deleted — [recipeMacrosPerServing]
  /// still reads them directly (unfiltered by `deletedAt`, same as
  /// [recipeById]) to resolve a pre-v24 entry that was never snapshotted and
  /// now points at a soft-deleted recipe.
  Future<void> deleteRecipe(int id) async {
    await (_db.update(_db.recipes)..where((t) => t.id.equals(id))).write(
      RecipesCompanion(deletedAt: Value(_clock.now())),
    );
  }

  Stream<List<RecipeIngredientData>> watchIngredients(int recipeId) {
    return (_db.select(
      _db.recipeIngredients,
    )..where((t) => t.recipeId.equals(recipeId))).watch();
  }

  Future<void> addIngredient({
    required int recipeId,
    required int foodId,
    required double grams,
  }) async {
    await _db
        .into(_db.recipeIngredients)
        .insert(
          RecipeIngredientsCompanion.insert(
            recipeId: recipeId,
            foodId: foodId,
            grams: grams,
          ),
        );
  }

  Future<void> removeIngredient(int id) async {
    await (_db.delete(
      _db.recipeIngredients,
    )..where((t) => t.id.equals(id))).go();
  }

  /// Macros per serving for a recipe.
  Future<DailyTotals> recipeMacrosPerServing(int recipeId) async {
    final recipe = await recipeById(recipeId);
    if (recipe == null) return DailyTotals.empty;

    final ings = await (_db.select(
      _db.recipeIngredients,
    )..where((t) => t.recipeId.equals(recipeId))).get();
    if (ings.isEmpty) return DailyTotals.empty;

    final byId = await foodsByIds(ings.map((i) => i.foodId));

    var totals = DailyTotals.empty;
    for (final ing in ings) {
      final food = byId[ing.foodId];
      if (food == null) continue;
      final factor = ing.grams / 100.0;
      totals = totals.plus(
        kcal: food.kcalPer100g * factor,
        proteinG: food.proteinPer100g * factor,
        carbsG: food.carbsPer100g * factor,
        fatG: food.fatPer100g * factor,
        fiberG: (food.fiberPer100g ?? 0) * factor,
        sodiumMg: (food.sodiumMgPer100g ?? 0) * factor,
        potassiumMg: (food.potassiumMgPer100g ?? 0) * factor,
        cholesterolMg: (food.cholesterolMgPer100g ?? 0) * factor,
        micros: _microsForFood(food, factor),
      );
    }

    final servings = recipe.servings == 0 ? 1 : recipe.servings;
    return DailyTotals(
      kcal: totals.kcal / servings,
      proteinG: totals.proteinG / servings,
      carbsG: totals.carbsG / servings,
      fatG: totals.fatG / servings,
      fiberG: totals.fiberG / servings,
      sodiumMg: totals.sodiumMg / servings,
      potassiumMg: totals.potassiumMg / servings,
      cholesterolMg: totals.cholesterolMg / servings,
      micros: _scaleMicros(totals.micros, 1 / servings),
    );
  }

  // ── Entries (the daily diary) ──────────────────────────────────────────

  Stream<List<FoodEntryData>> watchEntriesForDate(DateTime date) {
    final iso = dateIso(date);
    return (_db.select(_db.foodEntries)
          ..where((t) => t.dateIso.equals(iso))
          ..orderBy([(t) => OrderingTerm(expression: t.loggedAt)]))
        .watch();
  }

  Future<void> logFood({
    required DateTime date,
    Meal? meal,
    String? mealKey,
    required int foodId,
    double? grams,
    double? portionAmount,
    String? portionUnit,
    double servings = 1,
    DateTime? loggedAt,
  }) async {
    final resolvedMeal = mealKey ?? meal?.name ?? Meal.snack.name;
    final amount = portionAmount ?? grams;
    if (amount == null || amount <= 0) return;
    final unit = portionUnit ?? 'g';
    // Total consumed = servings × portion size, so a "2 × 30 g" entry stores
    // the 60 g the macros are actually computed from.
    final total = amount * (servings <= 0 ? 1 : servings);
    // RB-05: freeze the food's nutrition profile onto the entry so later
    // edits/deletes of the catalogue row don't move this entry's history. A
    // missing food (shouldn't happen via normal UI flow) degrades gracefully
    // to an un-snapshotted row, which the read path falls back on.
    final food = await foodById(foodId);
    await _db
        .into(_db.foodEntries)
        .insert(
          FoodEntriesCompanion.insert(
            dateIso: dateIso(date),
            meal: resolvedMeal,
            foodId: Value(foodId),
            servings: const Value(1),
            gramsOverride: Value(unit == 'g' ? total : null),
            portionAmount: Value(total),
            portionUnit: Value(unit),
            // §22 fix: stamp loggedAt from the local Clock so it agrees with
            // the local-derived dateIso. SQLite's default CURRENT_TIMESTAMP is
            // UTC, which drifts entries onto the wrong calendar day for users
            // behind UTC and corrupts recentFoods' loggedAt cutoff.
            loggedAt: Value(loggedAt ?? _clock.now()),
            snapshotBasis: food == null
                ? const Value.absent()
                : Value(food.referenceBasis),
            snapshotName: food == null ? const Value.absent() : Value(food.name),
            snapshotBrand: food == null ? const Value.absent() : Value(food.brand),
            snapshotKcal:
                food == null ? const Value.absent() : Value(food.kcalPer100g),
            snapshotProteinG: food == null
                ? const Value.absent()
                : Value(food.proteinPer100g),
            snapshotCarbsG:
                food == null ? const Value.absent() : Value(food.carbsPer100g),
            snapshotFatG:
                food == null ? const Value.absent() : Value(food.fatPer100g),
            snapshotFiberG:
                food == null ? const Value.absent() : Value(food.fiberPer100g),
            snapshotSodiumMg: food == null
                ? const Value.absent()
                : Value(food.sodiumMgPer100g),
            snapshotPotassiumMg: food == null
                ? const Value.absent()
                : Value(food.potassiumMgPer100g),
            snapshotCholesterolMg: food == null
                ? const Value.absent()
                : Value(food.cholesterolMgPer100g),
            snapshotServingGrams: food == null
                ? const Value.absent()
                : Value(food.servingGrams),
            snapshotServingAmount: food == null
                ? const Value.absent()
                : Value(food.servingAmount),
            snapshotServingUnit: food == null
                ? const Value.absent()
                : Value(food.servingUnit),
            snapshotMicrosJson: food == null
                ? const Value.absent()
                : Value(_encodeMicrosOrNull(_microsForFood(food, 1.0))),
          ),
        );
  }

  /// Adds [deltaMl] to the day's logged water intake, creating the
  /// [DailySummaries] row if today doesn't have one yet. This is the phone
  /// side of the watch's "+500ml water" quick add (Phase 5 of
  /// docs/wear-sync-race-conditions-remediation-plan-2026-08-11.md, ENG-16
  /// "missing nutrition sync") — `waterMl` already existed on this table for
  /// unrelated reasons (health-platform sync) but nothing previously wrote
  /// to it from a user action.
  Future<void> addWaterMl(DateTime date, int deltaMl) async {
    final iso = dateIso(date);
    await _db.transaction(() async {
      final existing = await (_db.select(
        _db.dailySummaries,
      )..where((t) => t.dateIso.equals(iso))).getSingleOrNull();
      final newTotal = (existing?.waterMl ?? 0) + deltaMl;
      await _db
          .into(_db.dailySummaries)
          .insertOnConflictUpdate(
            DailySummariesCompanion.insert(
              dateIso: iso,
              waterMl: Value(newTotal),
            ),
          );
    });
  }

  Future<void> logRecipe({
    required DateTime date,
    Meal? meal,
    String? mealKey,
    required int recipeId,
    required double servings,
    DateTime? loggedAt,
  }) async {
    final resolvedMeal = mealKey ?? meal?.name ?? Meal.snack.name;
    // RB-05: freeze the recipe's per-serving nutrition onto the entry, same
    // rationale as logFood. `snapshotBasis` uses the 'recipe serving'
    // sentinel the v24 backfill established (nutrition_snapshot_backfill.dart)
    // so the read path can tell a recipe snapshot from a food snapshot.
    // snapshot_serving_* stays unset for recipe entries — the read path
    // scales by entry.servings, not a portion factor.
    final recipe = await recipeById(recipeId);
    final per = recipe == null ? null : await recipeMacrosPerServing(recipeId);
    await _db
        .into(_db.foodEntries)
        .insert(
          FoodEntriesCompanion.insert(
            dateIso: dateIso(date),
            meal: resolvedMeal,
            recipeId: Value(recipeId),
            servings: Value(servings),
            loggedAt: Value(loggedAt ?? _clock.now()),
            snapshotBasis: per == null
                ? const Value.absent()
                : const Value('recipe serving'),
            snapshotName:
                recipe == null ? const Value.absent() : Value(recipe.name),
            snapshotKcal: per == null ? const Value.absent() : Value(per.kcal),
            snapshotProteinG:
                per == null ? const Value.absent() : Value(per.proteinG),
            snapshotCarbsG:
                per == null ? const Value.absent() : Value(per.carbsG),
            snapshotFatG: per == null ? const Value.absent() : Value(per.fatG),
            snapshotFiberG:
                per == null ? const Value.absent() : Value(per.fiberG),
            snapshotSodiumMg:
                per == null ? const Value.absent() : Value(per.sodiumMg),
            snapshotPotassiumMg:
                per == null ? const Value.absent() : Value(per.potassiumMg),
            snapshotCholesterolMg:
                per == null ? const Value.absent() : Value(per.cholesterolMg),
            snapshotMicrosJson: per == null
                ? const Value.absent()
                : Value(_encodeMicrosOrNull(per.micros)),
          ),
        );
  }

  Future<void> deleteEntry(int id) async {
    await (_db.delete(_db.foodEntries)..where((t) => t.id.equals(id))).go();
  }

  Future<void> updateEntry({
    required int id,
    double? servings,
    double? gramsOverride,
    double? portionAmount,
    String? portionUnit,
    String? mealKey,
    DateTime? loggedAt,
  }) async {
    await (_db.update(_db.foodEntries)..where((t) => t.id.equals(id))).write(
      FoodEntriesCompanion(
        servings: servings != null ? Value(servings) : const Value.absent(),
        gramsOverride:
            gramsOverride != null ? Value(gramsOverride) : const Value.absent(),
        portionAmount:
            portionAmount != null ? Value(portionAmount) : const Value.absent(),
        portionUnit:
            portionUnit != null ? Value(portionUnit) : const Value.absent(),
        meal: mealKey != null ? Value(mealKey) : const Value.absent(),
        loggedAt: loggedAt != null ? Value(loggedAt) : const Value.absent(),
      ),
    );
  }

  /// Resolves an entry's macro contribution, handling both food and recipe.
  ///
  /// RB-05: snapshot-first. A non-null `snapshotBasis` means the entry froze
  /// its nutrition at log time, so totals come straight from the entry's own
  /// snapshot* columns with no food/recipe table touched at all — that's what
  /// keeps history from moving when the catalogue is edited or a food/recipe
  /// is deleted. `snapshotBasis == null` marks a pre-v24 row the migration
  /// couldn't backfill (no matching catalogue row existed then either), so it
  /// falls back to today's live-catalogue resolution via the Step 2 id-lookup
  /// primitives.
  Future<DailyTotals> macrosForEntry(FoodEntryData entry) async {
    if (entry.foodId != null) {
      if (entry.snapshotBasis != null) return _totalsForFoodSnapshot(entry);
      final food = await foodById(entry.foodId!);
      if (food == null) return DailyTotals.empty;
      return _totalsForFood(food, entry: entry);
    }
    if (entry.recipeId != null) {
      if (entry.snapshotBasis != null) return _totalsForRecipeSnapshot(entry);
      final per = await recipeMacrosPerServing(entry.recipeId!);
      return _scaleTotals(per, entry.servings);
    }
    return DailyTotals.empty;
  }

  /// Stream of pre-computed totals for a date. Re-emits when entries change.
  Stream<DailyTotals> watchDailyTotals(DateTime date) async* {
    await for (final entries in watchEntriesForDate(date)) {
      var totals = DailyTotals.empty;
      for (final e in entries) {
        final m = await macrosForEntry(e);
        totals = totals.plus(
          kcal: m.kcal,
          proteinG: m.proteinG,
          carbsG: m.carbsG,
          fatG: m.fatG,
          fiberG: m.fiberG,
          sodiumMg: m.sodiumMg,
          potassiumMg: m.potassiumMg,
          cholesterolMg: m.cholesterolMg,
          micros: m.micros,
        );
      }
      yield totals;
    }
  }

  /// Stream of pre-computed daily totals for dates within [startDate] and [endDate] (inclusive).
  Stream<Map<String, DailyTotals>> watchDailyTotalsForRange(
    DateTime startDate,
    DateTime endDate,
  ) async* {
    final startIso = dateIso(startDate);
    final endIso = dateIso(endDate);

    final entriesQuery = _db.select(_db.foodEntries)
      ..where(
        (t) =>
            t.dateIso.isBiggerOrEqualValue(startIso) &
            t.dateIso.isSmallerOrEqualValue(endIso),
      )
      ..orderBy([(t) => OrderingTerm(expression: t.dateIso)]);

    await for (final entries in entriesQuery.watch()) {
      final resultMap = <String, DailyTotals>{};

      // Only entries without a snapshot need the live catalogue at all — a
      // snapshotted entry resolves entirely from its own row below.
      final unsnapshotted = entries.where((e) => e.snapshotBasis == null);
      final foodIds = unsnapshotted
          .map((e) => e.foodId)
          .whereType<int>()
          .toSet();
      final recipeIds = unsnapshotted
          .map((e) => e.recipeId)
          .whereType<int>()
          .toSet();

      final foodMap = await foodsByIds(foodIds);

      final recipeMacrosMap = <int, DailyTotals>{};
      for (final rId in recipeIds) {
        recipeMacrosMap[rId] = await recipeMacrosPerServing(rId);
      }

      for (final entry in entries) {
        DailyTotals entryTotals = DailyTotals.empty;
        if (entry.foodId != null) {
          if (entry.snapshotBasis != null) {
            entryTotals = _totalsForFoodSnapshot(entry);
          } else if (foodMap.containsKey(entry.foodId)) {
            entryTotals = _totalsForFood(foodMap[entry.foodId]!, entry: entry);
          }
        } else if (entry.recipeId != null) {
          if (entry.snapshotBasis != null) {
            entryTotals = _totalsForRecipeSnapshot(entry);
          } else if (recipeMacrosMap.containsKey(entry.recipeId)) {
            entryTotals = _scaleTotals(
              recipeMacrosMap[entry.recipeId]!,
              entry.servings,
            );
          }
        }

        final existing = resultMap[entry.dateIso] ?? DailyTotals.empty;
        resultMap[entry.dateIso] = existing.plus(
          kcal: entryTotals.kcal,
          proteinG: entryTotals.proteinG,
          carbsG: entryTotals.carbsG,
          fatG: entryTotals.fatG,
          fiberG: entryTotals.fiberG,
          sodiumMg: entryTotals.sodiumMg,
          potassiumMg: entryTotals.potassiumMg,
          cholesterolMg: entryTotals.cholesterolMg,
          micros: entryTotals.micros,
        );
      }
      yield resultMap;
    }
  }

  DailyTotals _totalsForFood(FoodData food, {FoodEntryData? entry}) {
    final amount =
        entry?.portionAmount ??
        entry?.gramsOverride ??
        food.servingAmount ??
        food.servingGrams ??
        100;
    final unit =
        entry?.portionUnit ??
        (entry?.gramsOverride != null ? 'g' : food.servingUnit ?? 'g');
    final factor = _portionFactor(food, amount, unit);
    return DailyTotals(
      kcal: food.kcalPer100g * factor,
      proteinG: food.proteinPer100g * factor,
      carbsG: food.carbsPer100g * factor,
      fatG: food.fatPer100g * factor,
      fiberG: (food.fiberPer100g ?? 0) * factor,
      sodiumMg: (food.sodiumMgPer100g ?? 0) * factor,
      potassiumMg: (food.potassiumMgPer100g ?? 0) * factor,
      cholesterolMg: (food.cholesterolMgPer100g ?? 0) * factor,
      micros: _microsForFood(food, factor),
    );
  }

  double _portionFactor(FoodData food, double amount, String unit) =>
      _portionFactorForBasis(food.referenceBasis, food.servingGrams, amount, unit);

  /// Basis-driven core of [_portionFactor], extracted so the snapshot read
  /// path ([_totalsForFoodSnapshot]) can reproduce the exact same math off
  /// `entry.snapshotBasis`/`entry.snapshotServingGrams` without touching the
  /// live `foods` table.
  double _portionFactorForBasis(
    String basis,
    double? servingGrams,
    double amount,
    String unit,
  ) {
    final b = basis.toLowerCase();
    if (unit == 'serving') return amount;
    if (b.contains('legacy serving')) {
      if (unit == 'g' && servingGrams != null && servingGrams > 0) {
        return amount / servingGrams;
      }
      return amount;
    }
    if (b.contains('100 ml')) return amount / 100.0;
    return amount / 100.0;
  }

  /// RB-05 snapshot-first totals for a food entry: identical portion math to
  /// [_totalsForFood], but sourced entirely from `entry.snapshot*` columns
  /// instead of a live [FoodData] row.
  DailyTotals _totalsForFoodSnapshot(FoodEntryData entry) {
    final amount =
        entry.portionAmount ??
        entry.gramsOverride ??
        entry.snapshotServingAmount ??
        entry.snapshotServingGrams ??
        100;
    final unit =
        entry.portionUnit ??
        (entry.gramsOverride != null ? 'g' : entry.snapshotServingUnit ?? 'g');
    final factor = _portionFactorForBasis(
      entry.snapshotBasis!,
      entry.snapshotServingGrams,
      amount,
      unit,
    );
    final micros = entry.snapshotMicrosJson == null
        ? const <String, double>{}
        : _scaleMicros(_decodeMicros(entry.snapshotMicrosJson!), factor);
    return DailyTotals(
      kcal: (entry.snapshotKcal ?? 0) * factor,
      proteinG: (entry.snapshotProteinG ?? 0) * factor,
      carbsG: (entry.snapshotCarbsG ?? 0) * factor,
      fatG: (entry.snapshotFatG ?? 0) * factor,
      fiberG: (entry.snapshotFiberG ?? 0) * factor,
      sodiumMg: (entry.snapshotSodiumMg ?? 0) * factor,
      potassiumMg: (entry.snapshotPotassiumMg ?? 0) * factor,
      cholesterolMg: (entry.snapshotCholesterolMg ?? 0) * factor,
      micros: micros,
    );
  }

  /// RB-05 snapshot-first totals for a recipe entry. Unlike food snapshots,
  /// the recipe snapshot columns already hold *per-serving* totals (mirroring
  /// [recipeMacrosPerServing]'s output at log time), so there's no portion
  /// factor — only the entry's own `servings` multiplier, same as the live
  /// recipe path.
  DailyTotals _totalsForRecipeSnapshot(FoodEntryData entry) {
    final per = DailyTotals(
      kcal: entry.snapshotKcal ?? 0,
      proteinG: entry.snapshotProteinG ?? 0,
      carbsG: entry.snapshotCarbsG ?? 0,
      fatG: entry.snapshotFatG ?? 0,
      fiberG: entry.snapshotFiberG ?? 0,
      sodiumMg: entry.snapshotSodiumMg ?? 0,
      potassiumMg: entry.snapshotPotassiumMg ?? 0,
      cholesterolMg: entry.snapshotCholesterolMg ?? 0,
      micros: entry.snapshotMicrosJson == null
          ? const {}
          : _decodeMicros(entry.snapshotMicrosJson!),
    );
    return _scaleTotals(per, entry.servings);
  }

  DailyTotals _scaleTotals(DailyTotals totals, double factor) => DailyTotals(
    kcal: totals.kcal * factor,
    proteinG: totals.proteinG * factor,
    carbsG: totals.carbsG * factor,
    fatG: totals.fatG * factor,
    fiberG: totals.fiberG * factor,
    sodiumMg: totals.sodiumMg * factor,
    potassiumMg: totals.potassiumMg * factor,
    cholesterolMg: totals.cholesterolMg * factor,
    micros: _scaleMicros(totals.micros, factor),
  );

  Map<String, double> _microsForFood(FoodData food, double factor) {
    final nutrients = <String, double>{};
    final metadata = food.sourceMetadataJson;
    if (metadata != null) {
      try {
        final root = jsonDecode(metadata) as Map<String, dynamic>;
        final source = root['nutrients'];
        if (source is Map) {
          for (final item in source.entries) {
            if (item.value is num && item.key != 'energy_kcal') {
              nutrients[item.key.toString()] =
                  (item.value as num).toDouble() * factor;
            }
          }
        }
      } catch (_) {
        // Legacy/custom rows may not have a JSON payload.
      }
    }
    void fallback(String key, double? value) {
      if (!nutrients.containsKey(key) && value != null) {
        nutrients[key] = value * factor;
      }
    }

    fallback('fiber', food.fiberPer100g);
    fallback('sodium', food.sodiumMgPer100g);
    fallback('potassium', food.potassiumMgPer100g);
    fallback('cholesterol', food.cholesterolMgPer100g);
    return nutrients;
  }

  Map<String, double> _scaleMicros(Map<String, double> values, double factor) =>
      {for (final item in values.entries) item.key: item.value * factor};

  /// Decodes a `snapshotMicrosJson` blob — the flat, already-resolved
  /// `{"vitamin_c": 4.0}` map `_microsForFood`/the v24 backfill produce, not
  /// the raw `sourceMetadataJson` provenance blob.
  Map<String, double> _decodeMicros(String json) {
    try {
      final root = jsonDecode(json) as Map<String, dynamic>;
      return {
        for (final item in root.entries)
          if (item.value is num) item.key: (item.value as num).toDouble(),
      };
    } catch (_) {
      return const {};
    }
  }

  /// Inverse of [_decodeMicros] for writing a snapshot: null when empty, so
  /// `snapshotBasis` stays the sole "has snapshot" sentinel (an empty `{}`
  /// would otherwise be indistinguishable from "not snapshotted").
  String? _encodeMicrosOrNull(Map<String, double> micros) =>
      micros.isEmpty ? null : jsonEncode(micros);

  // ── Nutrition targets, diet schedules, carb plans (v12, §19) ────────────

  Stream<List<NutritionTargetData>> watchTargets() {
    return _db.select(_db.nutritionTargets).watch();
  }

  /// Upserts the target for a scope key (one row per [appliesTo]). Conflict
  /// target is the [appliesTo] unique key, not the primary key, so re-saving
  /// the same scope updates rather than throwing.
  Future<void> upsertTarget({
    required String label,
    required String appliesTo,
    required int kcal,
    required int proteinG,
    required int carbsG,
    required int fatG,
    int? fiberG,
  }) async {
    await _db
        .into(_db.nutritionTargets)
        .insert(
          NutritionTargetsCompanion.insert(
            label: label,
            appliesTo: Value(appliesTo),
            kcal: kcal,
            proteinG: proteinG,
            carbsG: carbsG,
            fatG: fatG,
            fiberG: Value(fiberG),
          ),
          onConflict: DoUpdate(
            (old) => NutritionTargetsCompanion.custom(
              label: Constant(label),
              kcal: Constant(kcal),
              proteinG: Constant(proteinG),
              carbsG: Constant(carbsG),
              fatG: Constant(fatG),
              fiberG: fiberG == null ? const Constant(null) : Constant(fiberG),
            ),
            target: [_db.nutritionTargets.appliesTo],
          ),
        );
  }

  Future<void> deleteTarget(int id) async {
    await (_db.delete(
      _db.nutritionTargets,
    )..where((t) => t.id.equals(id))).go();
  }

  Stream<DietScheduleData?> watchActiveDietSchedule() {
    return (_db.select(_db.dietSchedules)
          ..where((t) => t.active.equals(true))
          ..orderBy([
            (t) => OrderingTerm(
              expression: t.startDateIso,
              mode: OrderingMode.desc,
            ),
          ])
          ..limit(1))
        .watchSingleOrNull();
  }

  Future<int> startDietSchedule({
    required DateTime startDate,
    required double reducePct,
    required int intervalDays,
  }) async {
    return _db.transaction(() async {
      // Only one active schedule at a time.
      await (_db.update(_db.dietSchedules)..where((t) => t.active.equals(true)))
          .write(const DietSchedulesCompanion(active: Value(false)));
      return _db
          .into(_db.dietSchedules)
          .insert(
            DietSchedulesCompanion.insert(
              startDateIso: dateIso(startDate),
              reducePct: reducePct,
              intervalDays: intervalDays,
            ),
          );
    });
  }

  Future<void> stopDietSchedules() async {
    await (_db.update(_db.dietSchedules)..where((t) => t.active.equals(true)))
        .write(const DietSchedulesCompanion(active: Value(false)));
  }

  Future<void> saveCarbCyclePlan({
    required DateTime weekStart,
    required String dayLevelsJson,
    bool auto = true,
  }) async {
    await _db
        .into(_db.carbCyclePlans)
        .insert(
          CarbCyclePlansCompanion.insert(
            weekStartIso: dateIso(weekStart),
            dayLevelsJson: dayLevelsJson,
            auto: Value(auto),
          ),
          onConflict: DoUpdate(
            (old) => CarbCyclePlansCompanion.custom(
              dayLevelsJson: Constant(dayLevelsJson),
              auto: Constant(auto),
            ),
            target: [_db.carbCyclePlans.weekStartIso],
          ),
        );
  }

  Future<CarbCyclePlanData?> carbCyclePlanForWeek(DateTime weekStart) {
    return (_db.select(_db.carbCyclePlans)
          ..where((t) => t.weekStartIso.equals(dateIso(weekStart))))
        .getSingleOrNull();
  }

  /// Whether the user trained on [date] (any completed session that day) —
  /// drives training-day vs rest-day target selection.
  Future<bool> trainedOn(DateTime date) async {
    final from = DateTime(date.year, date.month, date.day);
    final to = from.add(const Duration(days: 1));
    final row =
        await (_db.select(_db.workoutSessions)
              ..where(
                (t) =>
                    t.endedAt.isNotNull() &
                    t.startedAt.isBiggerOrEqualValue(from) &
                    t.startedAt.isSmallerThanValue(to),
              )
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }

  /// Top N foods most frequently logged in the last 30 days.
  Future<List<FoodData>> recentFoods({int limit = 20}) async {
    final cutoff = _clock.now().subtract(const Duration(days: 30));
    final entries =
        await (_db.select(_db.foodEntries)..where(
              (t) =>
                  t.foodId.isNotNull() &
                  t.loggedAt.isBiggerOrEqualValue(cutoff),
            ))
            .get();

    final counts = <int, int>{};
    for (final e in entries) {
      final id = e.foodId;
      if (id == null) continue;
      counts[id] = (counts[id] ?? 0) + 1;
    }
    if (counts.isEmpty) return const [];

    final topIds = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final ids = topIds.take(limit).map((e) => e.key).toList();
    final foods = await (_db.select(_db.foods)
          ..where((t) => t.id.isIn(ids))
          ..where((t) => t.deletedAt.isNull()))
        .get();
    // Preserve frequency order.
    final byId = {for (final f in foods) f.id: f};
    return [for (final id in ids) byId[id]].whereType<FoodData>().toList();
  }

  /// The same ranking as [recentFoods], pre-resolved to a default portion's
  /// macro totals — for surfaces (like the watch) that can't run their own
  /// per-100g × grams math against the local catalogue.
  Future<List<QuickAddFoodItem>> quickAddFoods({int limit = 12}) async {
    final foods = await recentFoods(limit: limit);
    return [for (final food in foods) _quickAddItemForFood(food)];
  }

  QuickAddFoodItem _quickAddItemForFood(FoodData food) {
    final totals = _totalsForFood(food);
    final amount = food.servingAmount ?? food.servingGrams ?? 100;
    final unit = food.servingUnit ?? 'g';
    final label = food.servingLabel ?? '${_fmtPortionAmount(amount)} $unit';
    return QuickAddFoodItem(
      foodId: food.id,
      name: food.name,
      kcal: totals.kcal,
      proteinG: totals.proteinG,
      carbsG: totals.carbsG,
      fatG: totals.fatG,
      portionAmount: amount,
      portionUnit: unit,
      portionLabel: label,
    );
  }

  String _fmtPortionAmount(double amount) {
    return amount == amount.roundToDouble()
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(1);
  }
}

/// A recent/frequently-logged food resolved to a single default-portion
/// macro snapshot, for a tap-to-log quick-add surface.
class QuickAddFoodItem {
  final int foodId;
  final String name;
  final double kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final double portionAmount;
  final String portionUnit;
  final String portionLabel;

  const QuickAddFoodItem({
    required this.foodId,
    required this.name,
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.portionAmount,
    required this.portionUnit,
    required this.portionLabel,
  });
}
