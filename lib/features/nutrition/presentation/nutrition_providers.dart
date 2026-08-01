import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../data/local/database.dart';
import '../../../services/widget_sync_service.dart';
import '../data/nutrition_repository.dart';
import '../data/openfoodfacts_client.dart';
import '../domain/daily_totals.dart';
import '../domain/macro_targets.dart';
import '../domain/carb_cycling.dart';
import '../domain/target_resolver.dart';
import '../domain/meal.dart';
import '../data/carb_cycle_service.dart';
import '../data/wear_sync_service.dart';
import '../../analytics/presentation/analytics_providers.dart';
import 'meal_slots_provider.dart';

/// Singleton [WidgetSyncService] for pushing data to Android home-screen widgets.
final widgetSyncServiceProvider = Provider<WidgetSyncService>((ref) {
  return WidgetSyncService();
});

final openFoodFactsClientProvider = Provider<OpenFoodFactsClient>((ref) {
  final c = OpenFoodFactsClient();
  ref.onDispose(c.dispose);
  return c;
});

final nutritionRepositoryProvider = Provider<NutritionRepository>((ref) {
  return NutritionRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(openFoodFactsClientProvider),
    ref.watch(clockProvider),
  );
});

/// Currently-viewed date in the Nutrition tab. Always a date-only value
/// (midnight, no time component) so the [entriesForDateProvider] /
/// [dailyTotalsProvider] family keys stay stable as the user pages between
/// days. Initialized from the injectable clock.
final selectedDateProvider = StateProvider<DateTime>((ref) {
  final n = ref.watch(clockProvider).now();
  return DateTime(n.year, n.month, n.day);
});

final entriesForDateProvider = StreamProvider.autoDispose
    .family<List<FoodEntryData>, DateTime>((ref, date) {
      return ref.watch(nutritionRepositoryProvider).watchEntriesForDate(date);
    });

final dailyTotalsProvider = StreamProvider.autoDispose
    .family<DailyTotals, DateTime>((ref, date) {
      return ref.watch(nutritionRepositoryProvider).watchDailyTotals(date);
    });

/// Profile-derived baseline target (Mifflin-St Jeor). Used as the fallback
/// when no day-specific rule applies.
final baselineTargetsProvider = Provider<MacroTargets?>((ref) {
  final profile = ref.watch(profileProvider).asData?.value;
  if (profile == null) return null;
  return MacroTargets.fromProfile(profile);
});

final nutritionTargetsProvider = StreamProvider<List<NutritionTargetData>>((
  ref,
) {
  return ref.watch(nutritionRepositoryProvider).watchTargets();
});

final activeDietScheduleProvider = StreamProvider<DietScheduleData?>((ref) {
  return ref.watch(nutritionRepositoryProvider).watchActiveDietSchedule();
});

/// Effective target for the selected date (§19): day-specific rule resolution
/// over training/rest/weekday/date scopes, then automated diet-schedule
/// reduction, falling back to the profile baseline.
final effectiveTargetsProvider = FutureProvider.autoDispose
    .family<MacroTargets?, DateTime>((ref, date) async {
      final repo = ref.watch(nutritionRepositoryProvider);
      final rows = await ref.watch(nutritionTargetsProvider.future);
      final schedule = await ref.watch(activeDietScheduleProvider.future);
      final baseline = ref.watch(baselineTargetsProvider);
      final isTrainingDay = await repo.trainedOn(date);

      // Apply burned calories if enabled in profile
      final profile = ref.watch(profileProvider).asData?.value;
      double extraCalories = 0;
      if (profile?.countBurnedCalories == true) {
        // We would need to fetch the active kcal for this specific date
        // Since healthSamples are synced daily, we can use the db directly or healthService.
        final healthSamples = await ref
            .read(appDatabaseProvider)
            .select(ref.read(appDatabaseProvider).healthSamples)
            .get();
        final isoDate =
            "\${date.year}-\${date.month.toString().padLeft(2, '0')}-\${date.day.toString().padLeft(2, '0')}";
        final sample = healthSamples
            .where((s) => s.dateIso == isoDate && s.kind == 'active_kcal')
            .firstOrNull;
        if (sample != null) {
          extraCalories = sample.value;
        }
      }

      var targets = TargetResolver.resolve(
        rules: [
          for (final r in rows)
            TargetRule(
              kcal: r.kcal,
              proteinG: r.proteinG,
              carbsG: r.carbsG,
              fatG: r.fatG,
              fiberG: r.fiberG,
              appliesTo: r.appliesTo,
            ),
        ],
        date: date,
        isTrainingDay: isTrainingDay,
        schedule: schedule == null
            ? null
            : DietScheduleRule(
                startDate: parseDateIso(schedule.startDateIso),
                reducePct: schedule.reducePct,
                intervalDays: schedule.intervalDays,
                active: schedule.active,
              ),
        fallback: baseline,
      );

      if (targets != null && extraCalories > 0) {
        // Add extra calories, distributing them across macros (e.g. 50% carbs, 25% protein, 25% fat)
        // 1g Carbs = 4 kcal, 1g Protein = 4 kcal, 1g Fat = 9 kcal
        targets = MacroTargets(
          kcal: targets.kcal + extraCalories.round(),
          proteinG: targets.proteinG + (extraCalories * 0.25 / 4).round(),
          carbsG: targets.carbsG + (extraCalories * 0.50 / 4).round(),
          fatG: targets.fatG + (extraCalories * 0.25 / 9).round(),
        );
      }
      return targets;
    });

final foodSearchProvider = StreamProvider.family<List<FoodData>, String?>((
  ref,
  query,
) {
  return ref.watch(nutritionRepositoryProvider).watchFoods(query: query);
});

final customFoodsProvider = StreamProvider.family<List<FoodData>, String?>((
  ref,
  query,
) {
  return ref.watch(nutritionRepositoryProvider).watchCustomFoods(query: query);
});

final recipesProvider = StreamProvider<List<RecipeData>>((ref) {
  return ref.watch(nutritionRepositoryProvider).watchRecipes();
});

final recipeIngredientsProvider =
    StreamProvider.family<List<RecipeIngredientData>, int>((ref, recipeId) {
      return ref.watch(nutritionRepositoryProvider).watchIngredients(recipeId);
    });

final recentFoodsProvider = FutureProvider<List<FoodData>>((ref) {
  return ref.watch(nutritionRepositoryProvider).recentFoods();
});

/// Group entries by meal for rendering meal sections.
final entriesByMealProvider = Provider.autoDispose
    .family<AsyncValue<Map<String, List<FoodEntryData>>>, DateTime>((
      ref,
      date,
    ) {
      final async = ref.watch(entriesForDateProvider(date));
      return async.whenData((entries) {
        final slots = ref.watch(mealSlotsProvider);
        final out = <String, List<FoodEntryData>>{
          for (final slot in slots) slot.key: <FoodEntryData>[],
        };
        for (final e in entries) {
          out.putIfAbsent(e.meal, () => <FoodEntryData>[]).add(e);
        }
        return out;
      });
    });

/// Auto-generated carb-cycle levels (Mon→Sun) for the selected date's week,
/// derived from the training snapshot (§19).
final generatedCarbCycleProvider = FutureProvider.autoDispose
    .family<List<CarbLevel>, DateTime>((ref, date) async {
      final snapshot = await ref.watch(trainingSnapshotProvider.future);
      return CarbCycleService.planForWeek(snapshot: snapshot, weekStart: date);
    });

final wearSyncServiceProvider = Provider<WearSyncService>((ref) {
  return WearSyncService();
});

final wearSyncControllerProvider = Provider<void>((ref) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  ref.listen<AsyncValue<DailyTotals>>(dailyTotalsProvider(today), (
    previous,
    next,
  ) {
    if (next.hasValue && next.value != null) {
      final totals = next.value!;
      ref
          .read(wearSyncServiceProvider)
          .syncMacros(totals.kcal.round(), totals.proteinG.round());
    }
  }, fireImmediately: true);
});

/// Syncs macro totals + targets to the Android home-screen pill widgets
/// every time [dailyTotalsProvider] or [effectiveTargetsProvider] emits.
final widgetMacroSyncControllerProvider = Provider<void>((ref) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final widgetSync = ref.watch(widgetSyncServiceProvider);

  ref.listen<AsyncValue<DailyTotals>>(dailyTotalsProvider(today), (
    _,
    next,
  ) async {
    if (!next.hasValue) return;
    final totals = next.value!;
    final targets =
        ref.read(effectiveTargetsProvider(today)).asData?.value ??
        ref.read(baselineTargetsProvider);
    await widgetSync.syncMacros(
      carbsCurrent: totals.carbsG.round(),
      carbsTarget: targets?.carbsG ?? 0,
      fatCurrent: totals.fatG.round(),
      fatTarget: targets?.fatG ?? 0,
      proteinCurrent: totals.proteinG.round(),
      proteinTarget: targets?.proteinG ?? 0,
    );
  }, fireImmediately: true);
});

/// Provider for multi-day daily totals history (up to 92 days back).
final nutritionHistoryProvider =
    StreamProvider.autoDispose<Map<String, DailyTotals>>((ref) {
      final now = DateTime.now();
      final endDate = DateTime(now.year, now.month, now.day);
      final startDate = endDate.subtract(const Duration(days: 92));
      return ref
          .watch(nutritionRepositoryProvider)
          .watchDailyTotalsForRange(startDate, endDate);
    });

/// Provider for Average Weekly Calories (past 7 days daily average).
final averageWeeklyCaloriesProvider = Provider.autoDispose<double?>((ref) {
  final history = ref.watch(nutritionHistoryProvider).asData?.value;
  if (history == null || history.isEmpty) return null;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  double totalKcal = 0;
  int count = 0;

  for (int i = 0; i < 7; i++) {
    final d = today.subtract(Duration(days: i));
    final iso = DateFormat('yyyy-MM-dd').format(d);
    if (history.containsKey(iso)) {
      totalKcal += history[iso]!.kcal;
      count++;
    }
  }

  if (count == 0) return 0.0;
  return totalKcal / count;
});
