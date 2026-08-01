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
              ..where((t) => t.name.like('%$query%') | t.brand.like('%$query%'))
              ..limit(20))
            .get();
    // The owned catalogue is authoritative. [includeRemote] remains in the
    // signature for caller compatibility but no network request is made.
    return local;
  }

  /// Local-only exact lookup. Barcode identifiers remain strings.
  Future<FoodData?> lookupBarcode(String barcode) async {
    final normalized = normalizeBarcode(barcode);
    if (normalized == null) return null;
    return _findByBarcode(normalized.lookupCandidates);
  }

  Future<FoodData?> _findByBarcode(List<String> barcodes) async {
    for (final barcode in barcodes) {
      final exact = await (_db.select(
        _db.foods,
      )..where((t) => t.barcode.equals(barcode))).getSingleOrNull();
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
      ..orderBy([(t) => OrderingTerm(expression: t.name)]);
    if (query != null && query.trim().isNotEmpty) {
      final like = '%${query.trim()}%';
      q.where((t) => t.name.like(like) | t.brand.like(like));
    }
    return q.watch();
  }

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

  Future<void> deleteFood(int id) async {
    await (_db.delete(_db.foods)..where((t) => t.id.equals(id))).go();
  }

  // ── Recipes ────────────────────────────────────────────────────────────

  Stream<List<RecipeData>> watchRecipes() {
    return (_db.select(_db.recipes)..orderBy([
          (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
        ]))
        .watch();
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

  Future<void> deleteRecipe(int id) async {
    await _db.transaction(() async {
      await (_db.delete(
        _db.recipeIngredients,
      )..where((t) => t.recipeId.equals(id))).go();
      await (_db.delete(_db.recipes)..where((t) => t.id.equals(id))).go();
    });
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
    final recipe = await (_db.select(
      _db.recipes,
    )..where((t) => t.id.equals(recipeId))).getSingleOrNull();
    if (recipe == null) return DailyTotals.empty;

    final ings = await (_db.select(
      _db.recipeIngredients,
    )..where((t) => t.recipeId.equals(recipeId))).get();
    if (ings.isEmpty) return DailyTotals.empty;

    final foodIds = ings.map((i) => i.foodId).toSet().toList();
    final foods = await (_db.select(
      _db.foods,
    )..where((t) => t.id.isIn(foodIds))).get();
    final byId = {for (final f in foods) f.id: f};

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
          ),
        );
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
    await _db
        .into(_db.foodEntries)
        .insert(
          FoodEntriesCompanion.insert(
            dateIso: dateIso(date),
            meal: resolvedMeal,
            recipeId: Value(recipeId),
            servings: Value(servings),
            loggedAt: Value(loggedAt ?? _clock.now()),
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
  Future<DailyTotals> macrosForEntry(FoodEntryData entry) async {
    if (entry.foodId != null) {
      final food = await (_db.select(
        _db.foods,
      )..where((t) => t.id.equals(entry.foodId!))).getSingleOrNull();
      if (food == null) return DailyTotals.empty;
      return _totalsForFood(food, entry: entry);
    }
    if (entry.recipeId != null) {
      final per = await recipeMacrosPerServing(entry.recipeId!);
      return DailyTotals(
        kcal: per.kcal * entry.servings,
        proteinG: per.proteinG * entry.servings,
        carbsG: per.carbsG * entry.servings,
        fatG: per.fatG * entry.servings,
        fiberG: per.fiberG * entry.servings,
        sodiumMg: per.sodiumMg * entry.servings,
        potassiumMg: per.potassiumMg * entry.servings,
        cholesterolMg: per.cholesterolMg * entry.servings,
        micros: _scaleMicros(per.micros, entry.servings),
      );
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

      final foodIds = entries
          .map((e) => e.foodId)
          .whereType<int>()
          .toSet()
          .toList();
      final recipeIds = entries
          .map((e) => e.recipeId)
          .whereType<int>()
          .toSet()
          .toList();

      final foods = foodIds.isEmpty
          ? <FoodData>[]
          : await (_db.select(
              _db.foods,
            )..where((t) => t.id.isIn(foodIds))).get();
      final foodMap = {for (final f in foods) f.id: f};

      final recipeMacrosMap = <int, DailyTotals>{};
      for (final rId in recipeIds) {
        recipeMacrosMap[rId] = await recipeMacrosPerServing(rId);
      }

      for (final entry in entries) {
        DailyTotals entryTotals = DailyTotals.empty;
        if (entry.foodId != null && foodMap.containsKey(entry.foodId)) {
          final food = foodMap[entry.foodId]!;
          entryTotals = _totalsForFood(food, entry: entry);
        } else if (entry.recipeId != null &&
            recipeMacrosMap.containsKey(entry.recipeId)) {
          final per = recipeMacrosMap[entry.recipeId]!;
          entryTotals = DailyTotals(
            kcal: per.kcal * entry.servings,
            proteinG: per.proteinG * entry.servings,
            carbsG: per.carbsG * entry.servings,
            fatG: per.fatG * entry.servings,
            fiberG: per.fiberG * entry.servings,
            sodiumMg: per.sodiumMg * entry.servings,
            potassiumMg: per.potassiumMg * entry.servings,
            cholesterolMg: per.cholesterolMg * entry.servings,
            micros: _scaleMicros(per.micros, entry.servings),
          );
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

  double _portionFactor(FoodData food, double amount, String unit) {
    final basis = food.referenceBasis.toLowerCase();
    if (unit == 'serving') return amount;
    if (basis.contains('legacy serving')) {
      final servingWeight = food.servingGrams;
      if (unit == 'g' && servingWeight != null && servingWeight > 0) {
        return amount / servingWeight;
      }
      return amount;
    }
    if (basis.contains('100 ml')) return amount / 100.0;
    return amount / 100.0;
  }

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
    final foods = await (_db.select(
      _db.foods,
    )..where((t) => t.id.isIn(ids))).get();
    // Preserve frequency order.
    final byId = {for (final f in foods) f.id: f};
    return [for (final id in ids) byId[id]].whereType<FoodData>().toList();
  }
}
