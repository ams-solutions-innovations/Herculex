import 'dart:async';
import 'dart:convert';
import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/analytics/application/analytics_providers.dart';
import 'package:herculex/features/analytics/domain/weekly_muscle_volume.dart';
import 'package:herculex/features/fasting/application/fasting_providers.dart';
import 'package:herculex/features/fasting/domain/fasting_sync_snapshot.dart';
import 'package:herculex/features/health/application/health_providers.dart';
import 'package:herculex/features/nutrition/application/meal_slots_provider.dart';
import 'package:herculex/features/nutrition/application/tdee_providers.dart';
import 'package:herculex/features/nutrition/data/carb_cycle_service.dart';
import 'package:herculex/features/nutrition/data/gemini_food_analyzer_service.dart';
import 'package:herculex/features/nutrition/data/nutrition_repository.dart';
import 'package:herculex/features/nutrition/data/openfoodfacts_client.dart';
import 'package:herculex/features/nutrition/data/watch_command_inbox.dart';
import 'package:herculex/features/nutrition/data/wear_sync_contract.dart';
import 'package:herculex/features/nutrition/data/wear_sync_service.dart';
import 'package:herculex/features/nutrition/domain/carb_cycling.dart';
import 'package:herculex/features/nutrition/domain/daily_totals.dart';
import 'package:herculex/features/nutrition/domain/macro_targets.dart';
import 'package:herculex/features/nutrition/domain/meal.dart';
import 'package:herculex/features/nutrition/domain/meal_slots.dart';
import 'package:herculex/features/nutrition/domain/target_resolver.dart';
import 'package:herculex/features/nutrition/domain/tdee_estimate.dart';
import 'package:herculex/features/physique/application/effective_goal_provider.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:herculex/services/platform/widget_sync_service.dart';
import 'package:intl/intl.dart';

/// Singleton [WidgetSyncService] for pushing data to Android home-screen widgets.
final widgetSyncServiceProvider = Provider<WidgetSyncService>((ref) {
  return WidgetSyncService(clock: ref.watch(clockProvider));
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

/// Baseline target used as the fallback when no day-specific rule applies.
/// Maintenance comes from the adaptive estimate; the goal delta is re-added
/// once inside [MacroTargets.fromMaintenance]. Cold start is exactly the
/// legacy profile seed (D-08).
final baselineTargetsProvider = Provider<MacroTargets?>((ref) {
  final stored = ref.watch(profileProvider).asData?.value;
  if (stored == null) {
    return null;
  }
  // The running roadmap phase decides the direction; the stored goal is
  // only the fallback (and is left as the member set it).
  final profile = stored.copyWith(
    goal: ref.watch(effectiveFitnessGoalProvider),
  );
  final est = ref.watch(tdeeEstimateProvider);
  if (est == null || est.method == TdeeMethod.coldStart) {
    return MacroTargets.fromProfile(profile);
  }
  return MacroTargets.fromMaintenance(profile, est.kcal.toDouble());
});

final nutritionTargetsProvider = StreamProvider<List<NutritionTargetData>>((
  ref,
) {
  return ref.watch(nutritionRepositoryProvider).watchTargets();
});

/// One current version per scope plus scheduled changes; omit historical duplicates.
final visibleNutritionTargetsProvider =
    Provider<AsyncValue<List<NutritionTargetData>>>((ref) {
      final today = dateIso(ref.watch(localDayProvider));
      return ref.watch(nutritionTargetsProvider).whenData((rows) {
        final current = <String, NutritionTargetData>{};
        final future = <NutritionTargetData>[];
        for (final row in rows) {
          if (row.effectiveFromDateIso.compareTo(today) > 0) {
            future.add(row);
            continue;
          }
          final old = current[row.appliesTo];
          if (old == null ||
              row.effectiveFromDateIso.compareTo(old.effectiveFromDateIso) >
                  0) {
            current[row.appliesTo] = row;
          }
        }
        return [...current.values, ...future];
      });
    });

final activeDietScheduleProvider = StreamProvider<DietScheduleData?>((ref) {
  return ref.watch(nutritionRepositoryProvider).watchActiveDietSchedule();
});

/// Effective target for the selected date (§19): day-specific rule resolution
/// over training/rest/weekday/date scopes, then automated diet-schedule
/// reduction, falling back to the profile baseline.
final effectiveTargetsProvider = FutureProvider.autoDispose
    .family<MacroTargets?, DateTime>((ref, date) async {
      ref.watch(localDayProvider);
      final repo = ref.watch(nutritionRepositoryProvider);
      final rows = await ref.watch(nutritionTargetsProvider.future);
      final schedule = await ref.watch(activeDietScheduleProvider.future);
      final baseline = ref.watch(baselineTargetsProvider);
      final isTrainingDay = await repo.trainedOn(date);

      // Apply burned calories if enabled in profile
      final profile =
          ref.watch(profileProvider).valueOrNull ??
          await ref.watch(profileProvider.future);
      double extraCalories = 0;
      if (profile?.countBurnedCalories == true) {
        final now = ref.watch(clockProvider).now();
        final today = DateTime(now.year, now.month, now.day);
        final selectedDay = DateTime(date.year, date.month, date.day);
        final activeRead = ref.watch(lastDailyHealthReadProvider)?.activeKcal;
        if (selectedDay == today &&
            activeRead != null &&
            !activeRead.isAvailable) {
          extraCalories = 0;
        } else {
          // We fetch the active kcal for this specific date from health_samples
          final healthSamples = await ref
              .read(appDatabaseProvider)
              .select(ref.read(appDatabaseProvider).healthSamples)
              .get();
          final isoDate =
              "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
          final sample = healthSamples
              .where((s) => s.dateIso == isoDate && s.kind == 'active_kcal')
              .firstOrNull;
          if (sample != null) {
            extraCalories = sample.value;
          }
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
              effectiveFromDateIso: r.effectiveFromDateIso,
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

/// Unfiltered single-food lookup by id, for resolving a known [FoodEntryData]
/// or [RecipeIngredientData] reference rather than scanning search results.
final foodByIdProvider = FutureProvider.family<FoodData?, int>((ref, id) {
  return ref.watch(nutritionRepositoryProvider).foodById(id);
});

/// Batched counterpart of [foodByIdProvider].
final foodsByIdsProvider = FutureProvider.family<Map<int, FoodData>, List<int>>(
  (ref, ids) {
    return ref.watch(nutritionRepositoryProvider).foodsByIds(ids);
  },
);

/// Reactive counterpart of [foodByIdProvider], for widgets that need to
/// rebuild when the referenced food changes.
final watchFoodByIdProvider = StreamProvider.family<FoodData?, int>((ref, id) {
  return ref.watch(nutritionRepositoryProvider).watchFoodById(id);
});

final recipesProvider = StreamProvider<List<RecipeData>>((ref) {
  return ref.watch(nutritionRepositoryProvider).watchRecipes();
});

/// Unfiltered single-recipe lookup by id, for resolving a known
/// [FoodEntryData] reference rather than scanning [recipesProvider].
final recipeByIdProvider = FutureProvider.family<RecipeData?, int>((ref, id) {
  return ref.watch(nutritionRepositoryProvider).recipeById(id);
});

final recipeIngredientsProvider =
    StreamProvider.family<List<RecipeIngredientData>, int>((ref, recipeId) {
      return ref.watch(nutritionRepositoryProvider).watchIngredients(recipeId);
    });

final recentFoodsProvider = FutureProvider<List<FoodData>>((ref) {
  return ref.watch(nutritionRepositoryProvider).recentFoods();
});

/// Watches all unique foods previously logged in strictly descending order of
/// their latest log time.
final recentlyLoggedFoodsProvider = StreamProvider.autoDispose<List<FoodData>>((
  ref,
) {
  return ref.watch(nutritionRepositoryProvider).watchRecentlyLoggedFoods();
});

class FoodSuggestionParams {
  final int hour;
  final String? mealKey;

  const FoodSuggestionParams({required this.hour, this.mealKey});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FoodSuggestionParams &&
          runtimeType == other.runtimeType &&
          hour == other.hour &&
          mealKey == other.mealKey;

  @override
  int get hashCode => Object.hash(hour, mealKey);
}

/// Watches foods suggested for a given time of day / hour and/or active meal slot.
final suggestedFoodsProvider = StreamProvider.autoDispose
    .family<List<FoodData>, FoodSuggestionParams>((ref, params) {
      return ref
          .watch(nutritionRepositoryProvider)
          .watchSuggestedFoods(hour: params.hour, mealKey: params.mealKey);
    });

class FoodPairingParams {
  final int foodId;
  final String mealKey;

  const FoodPairingParams({required this.foodId, required this.mealKey});

  @override
  bool operator ==(Object other) =>
      other is FoodPairingParams &&
      other.foodId == foodId &&
      other.mealKey == mealKey;

  @override
  int get hashCode => Object.hash(foodId, mealKey);
}

/// Learns food combinations from the user's own previous meals.
final frequentlyPairedFoodsProvider = FutureProvider.autoDispose
    .family<List<FoodData>, FoodPairingParams>((ref, params) {
      return ref
          .watch(nutritionRepositoryProvider)
          .frequentlyPairedFoods(params.foodId, mealKey: params.mealKey);
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

final wearSyncRevisionAllocatorProvider = Provider<WearRevisionAllocator>((
  ref,
) {
  return WearRevisionAllocator(ref.watch(sharedPreferencesProvider), 'fasting');
});

final formattedFastingProvider = Provider<String>((ref) {
  final duration = ref.watch(fastingTimerTickerProvider).asData?.value;
  if (duration == null) {
    return '0h 0m';
  }
  return '${duration.inHours}h ${duration.inMinutes.remainder(60)}m';
});

class _WidgetMacroResumeObserver with WidgetsBindingObserver {
  _WidgetMacroResumeObserver(this.onResume);
  final VoidCallback onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      onResume();
    }
  }
}

final wearSyncControllerProvider = Provider<void>((ref) {
  final clock = ref.watch(clockProvider);
  DateTime getToday() {
    final now = clock.now();
    return DateTime(now.year, now.month, now.day);
  }

  final today = ref.watch(localDayProvider);
  final commandInbox = WatchCommandInbox(ref.read(appDatabaseProvider));

  Future<void> syncQuickAddToWear() async {
    final repo = ref.read(nutritionRepositoryProvider);
    final suggested = await repo.suggestedQuickAddFoods();
    final recent = await repo.recentQuickAddFoods();
    final recipes = await repo.quickAddRecipes();
    final mealSlots = ref.read(mealSlotsProvider);

    final entries = await repo.watchEntriesForDate(today).first;
    final loggedEntries = <Map<String, dynamic>>[];
    for (final entry in entries) {
      final macros = await repo.macrosForEntry(entry);
      String name = entry.snapshotName ?? '';
      if (name.isEmpty) {
        if (entry.foodId != null) {
          final food = await repo.foodById(entry.foodId!);
          name = food?.name ?? 'Food';
        } else if (entry.recipeId != null) {
          final recipe = await repo.recipeById(entry.recipeId!);
          name = recipe?.name ?? 'Recipe';
        } else {
          name = 'Food';
        }
      }

      final amount = entry.portionAmount ??
          entry.gramsOverride ??
          entry.snapshotServingAmount ??
          entry.snapshotServingGrams ??
          0.0;
      final unit = entry.portionUnit ??
          (entry.gramsOverride != null ? 'g' : entry.snapshotServingUnit ?? 'g');
      final formattedAmount = amount == amount.roundToDouble()
          ? amount.toStringAsFixed(0)
          : amount.toStringAsFixed(1);
      final portionText = entry.foodId != null
          ? '$formattedAmount $unit'
          : '${entry.servings.toStringAsFixed(entry.servings.truncateToDouble() == entry.servings ? 0 : 1)} serv';

      loggedEntries.add({
        'id': entry.id,
        'name': name,
        'mealKey': entry.meal,
        'portionAmount': amount.toDouble(),
        'portionUnit': unit,
        'portionText': portionText,
        'servings': entry.servings,
        'kcal': macros.kcal.round(),
        'protein': macros.proteinG.round(),
        'carbs': macros.carbsG.round(),
        'fat': macros.fatG.round(),
        'foodId': entry.foodId,
        'recipeId': entry.recipeId,
        'loggedAtEpochMs': entry.loggedAt.millisecondsSinceEpoch,
      });
    }

    final payload = jsonEncode({
      'mealSlots': [for (final slot in mealSlots) slot.toJson()],
      'items': [for (final item in suggested) item.toJson()],
      'suggested': [for (final item in suggested) item.toJson()],
      'recent': [for (final item in recent) item.toJson()],
      'recipes': [for (final item in recipes) item.toJson()],
      'loggedEntries': loggedEntries,
    });
    await ref.read(wearSyncServiceProvider).syncQuickAddFoods(payload);
  }

  Future<void> syncFastingToWear() async {
    final repo = ref.read(fastingRepositoryProvider);
    final session = await repo.activeSession();
    final lastSession = session == null
        ? (await repo.history(limit: 1)).firstOrNull
        : null;
    final nextFast = ref.read(nextScheduledFastProvider);
    final currentStage = ref.read(currentFastingStageProvider);
    final stageMsg = currentStage != null
        ? '${currentStage.hour}h: ${currentStage.stageName}'
        : null;
    final hasSchedule = ref.read(hasActiveFastingScheduleProvider);

    final revision = ref.read(wearSyncRevisionAllocatorProvider).next();
    await ref
        .read(wearSyncServiceProvider)
        .syncFastingSnapshot(
          encodeFastingSnapshot(
            session: session,
            lastSession: lastSession,
            nextFastStartTime: nextFast?.nextOccurrence,
            nextFastPlanName: nextFast?.planLabel,
            nextFastTargetSeconds: nextFast?.targetSeconds,
            hasSchedule: hasSchedule,
            currentStageMessage: stageMsg,
            revision: revision,
          ),
        );
  }

  Future<void> syncAllToWear() async {
    await syncFastingToWear();
    await syncQuickAddToWear();

    final currentToday = getToday();
    if (currentToday != today) {
      ref.invalidateSelf();
      return;
    }

    DailyTotals? totals = ref.read(dailyTotalsProvider(today)).valueOrNull;
    if (totals == null) {
      try {
        totals = await ref.read(dailyTotalsProvider(today).future);
      } catch (_) {}
    }
    totals ??= DailyTotals.empty;

    final fasting = ref.read(formattedFastingProvider);
    final volume = ref.read(weeklyMuscleVolumeProvider).asData?.value;

    String volumeJson = '[]';
    if (volume != null) {
      final list = volume.byMuscle
          .map(
            (m) => {'muscle': m.muscle, 'tonnage': m.tonnageKg, 'sets': m.sets},
          )
          .toList();
      volumeJson = jsonEncode(list);
    }

    final historyMap = ref.read(nutritionHistoryProvider).asData?.value ?? {};
    final trendsList = <Map<String, dynamic>>[];
    for (int i = 6; i >= 0; i--) {
      final d = today.subtract(Duration(days: i));
      final iso = DateFormat('yyyy-MM-dd').format(d);
      final dayLabel = DateFormat('E').format(d);
      final dayTotals = historyMap[iso];
      trendsList.add({
        'date': iso,
        'day': dayLabel,
        'calories': (dayTotals?.kcal ?? (i == 0 ? totals.kcal : 0.0)).round(),
        'protein': (dayTotals?.proteinG ?? (i == 0 ? totals.proteinG : 0.0))
            .round(),
        'carbs': (dayTotals?.carbsG ?? (i == 0 ? totals.carbsG : 0.0)).round(),
        'fats': (dayTotals?.fatG ?? (i == 0 ? totals.fatG : 0.0)).round(),
        'water': 0,
      });
    }

    MacroTargets? targets = ref
        .read(effectiveTargetsProvider(today))
        .valueOrNull;
    if (targets == null) {
      try {
        targets = await ref.read(effectiveTargetsProvider(today).future);
      } catch (_) {}
    }
    final baseline = ref.read(baselineTargetsProvider);

    final calorieGoal = targets?.kcal ?? baseline?.kcal ?? 2000;
    final proteinGoal = targets?.proteinG ?? baseline?.proteinG ?? 150;
    final carbsGoal = targets?.carbsG ?? baseline?.carbsG ?? 200;
    final fatGoal = targets?.fatG ?? baseline?.fatG ?? 65;
    final waterGoal = 2000;
    final waterMl = await ref
        .read(nutritionRepositoryProvider)
        .waterMlFor(today);

    final todayIso = DateFormat('yyyy-MM-dd').format(today);

    await ref
        .read(wearSyncServiceProvider)
        .syncMacros(
          totals.kcal.round(),
          totals.proteinG.round(),
          carbs: totals.carbsG.round(),
          fats: totals.fatG.round(),
          fasting: fasting,
          weeklyTonnage: volume?.totalTonnageKg ?? 0.0,
          weeklySets: volume?.totalSets ?? 0,
          weeklyVolumeJson: volumeJson,
          nutrientTrendsJson: jsonEncode(trendsList),
          calorieGoal: calorieGoal,
          proteinGoal: proteinGoal,
          carbsGoal: carbsGoal,
          fatGoal: fatGoal,
          waterGoal: waterGoal,
          waterMl: waterMl,
          day: todayIso,
        );
  }

  WearSyncService.onWatchFastingCommand = (commandJson) async {
    if (commandJson == null || commandJson.isEmpty) {
      return;
    }
    try {
      final decoded = jsonDecode(commandJson) as Map<String, dynamic>;
      final commandId = decoded['commandId'] as String?;
      if (commandId == null || commandId.isEmpty) {
        return;
      }
      if (await commandInbox.wasApplied('fasting', commandId)) {
        await ref
            .read(wearSyncServiceProvider)
            .markWatchFastingCommandApplied(commandId);
        return;
      }

      await commandInbox.applyOnce('fasting', commandId, () async {
        final action = (decoded['action'] as String? ?? '').toLowerCase();
        final repo = ref.read(fastingRepositoryProvider);
        final startedAtEpochMs = (decoded['startedAtEpochMs'] as num?)?.toInt();
        final endedAtEpochMs = (decoded['endedAtEpochMs'] as num?)?.toInt();
        final targetSeconds =
            (decoded['targetSeconds'] as num?)?.toInt() ?? 16 * 60 * 60;

        if (action == 'start') {
          final customStartTime = startedAtEpochMs != null
              ? DateTime.fromMillisecondsSinceEpoch(startedAtEpochMs)
              : null;
          await repo.startSession(
            targetSeconds,
            customStartTime: customStartTime,
          );
        } else if (action == 'stop') {
          await ref
              .read(fastingNotificationSchedulerProvider)
              .cancelFastingGoal();
          final active = await repo.activeSession();
          if (active != null) {
            await repo.endSession(
              completed: decoded['completed'] as bool? ?? true,
              // Preserve the watch's actual stop instant after an offline
              // period instead of incorrectly ending the fast at reconnect.
              endedAt: endedAtEpochMs != null
                  ? DateTime.fromMillisecondsSinceEpoch(endedAtEpochMs)
                  : null,
            );
          } else if (startedAtEpochMs != null) {
            final startedAt = DateTime.fromMillisecondsSinceEpoch(
              startedAtEpochMs,
            );
            final endedAt = endedAtEpochMs != null
                ? DateTime.fromMillisecondsSinceEpoch(endedAtEpochMs)
                : DateTime.now();
            await repo.insertCompletedSession(
              startedAt: startedAt,
              endedAt: endedAt,
              targetSeconds: targetSeconds,
              completed: decoded['completed'] as bool? ?? true,
            );
          }
        }

        // Only mark this command "seen" once the write above has actually
        // succeeded. Adding it on the initial check (as before) meant a
        // failed write still poisoned the dedupe set, so a retried delivery
        // of the exact same command was silently dropped forever instead of
        // reapplied — see Phase 2 of
        // docs/wear-sync-race-conditions-remediation-plan-2026-08-11.md
        // (ENG-07/10/12).
      });
      await ref
          .read(wearSyncServiceProvider)
          .markWatchFastingCommandApplied(commandId);
      await syncFastingToWear();
      ref.read(syncServiceProvider).pushOnce().catchError((_) {});
    } catch (_) {
      // Keep the native pending command until a later retry succeeds. Since
      // commandId is only added to appliedFastingCommands after a
      // successful write, that retry is reapplied rather than skipped as a
      // duplicate.
    }
  };

  WearSyncService.onWatchQuickAddCommand = (commandJson) async {
    if (commandJson == null || commandJson.isEmpty) {
      return;
    }
    try {
      final decoded = jsonDecode(commandJson) as Map<String, dynamic>;
      final commandId = decoded['commandId'] as String?;
      if (commandId == null || commandId.isEmpty) {
        return;
      }
      if (await commandInbox.wasApplied('quickadd', commandId)) {
        await ref
            .read(wearSyncServiceProvider)
            .markWatchQuickAddCommandApplied(commandId);
        return;
      }

      await commandInbox.applyOnce('quickadd', commandId, () async {
        final action = (decoded['action'] as String? ?? 'log').toLowerCase();
        if (action == 'delete') {
          final entryId = (decoded['entryId'] as num?)?.toInt();
          if (entryId != null && entryId > 0) {
            await ref.read(nutritionRepositoryProvider).deleteEntry(entryId);
          }
        } else if (action == 'update') {
          final entryId = (decoded['entryId'] as num?)?.toInt();
          if (entryId != null && entryId > 0) {
            final portionAmount = (decoded['portionAmount'] as num?)?.toDouble();
            final portionUnit = decoded['portionUnit'] as String?;
            final mealKey = decoded['mealKey'] as String?;
            final servings = (decoded['servings'] as num?)?.toDouble();
            await ref.read(nutritionRepositoryProvider).updateEntry(
              id: entryId,
              portionAmount: portionAmount,
              portionUnit: portionUnit,
              gramsOverride: (portionUnit == 'g' && portionAmount != null)
                  ? portionAmount
                  : null,
              mealKey: mealKey,
              servings: servings,
            );
          }
        } else {
          final recipeId = (decoded['recipeId'] as num?)?.toInt();
          final foodId = (decoded['foodId'] as num?)?.toInt();
          final mealKey = decoded['mealKey'] as String?;
          final portionAmount = (decoded['portionAmount'] as num?)?.toDouble();
          final portionUnit = decoded['portionUnit'] as String?;
          if (recipeId != null && recipeId > 0) {
            await ref
                .read(nutritionRepositoryProvider)
                .logRecipe(
                  date: watchCommandDate(decoded),
                  mealKey: mealKey,
                  recipeId: recipeId,
                  servings: (portionAmount != null && portionAmount > 0)
                      ? portionAmount
                      : 1.0,
                );
          } else if (foodId != null && foodId > 0) {
            await ref
                .read(nutritionRepositoryProvider)
                .logFood(
                  date: watchCommandDate(decoded),
                  mealKey: mealKey,
                  foodId: foodId,
                  portionAmount: portionAmount,
                  portionUnit: portionUnit,
                );
          }
        }

        // Only mark this command "seen" once the write above has actually
        // succeeded — see the matching comment in onWatchFastingCommand above.
      });
      await ref
          .read(wearSyncServiceProvider)
          .markWatchQuickAddCommandApplied(commandId);
      await syncAllToWear();
      ref.read(syncServiceProvider).pushOnce().catchError((_) {});
    } catch (_) {
      // Keep the native pending command until a later retry succeeds. Since
      // commandId is only added to appliedQuickAddCommands after a
      // successful write, that retry is reapplied rather than skipped as a
      // duplicate.
    }
  };

  // Phase 5 (docs/wear-sync-race-conditions-remediation-plan-2026-08-11.md,
  // "missing nutrition sync"): the watch's "+200 kcal" /
  // "+500ml water" / manual food quick-adds (NutritionViewModel.addCalories/
  // addWater/logFood) previously only touched the watch's own local
  // MacroStore and were never sent to the phone at all. Mirrors the
  // dedupe-after-success shape of the two handlers above. There's no
  // existing "raw macros, no catalog food" concept on the phone, so a
  // calorie/food quick-add is logged as a one-off custom food (created with
  // the reported macros per 100g, then logged at exactly 100g so the
  // contribution matches the reported totals exactly) rather than requiring
  // a new data model.
  WearSyncService.onWatchMacroCommand = (commandJson) async {
    if (commandJson == null || commandJson.isEmpty) {
      return;
    }
    try {
      final decoded = jsonDecode(commandJson) as Map<String, dynamic>;
      final commandId = decoded['commandId'] as String?;
      if (commandId == null || commandId.isEmpty) {
        return;
      }
      if (await commandInbox.wasApplied('macro', commandId)) {
        await ref
            .read(wearSyncServiceProvider)
            .markWatchMacroCommandApplied(commandId);
        return;
      }

      await commandInbox.applyOnce('macro', commandId, () async {
        final kind = (decoded['kind'] as String? ?? '').toLowerCase();
        final repo = ref.read(nutritionRepositoryProvider);
        switch (kind) {
          case 'water':
            final waterMl = (decoded['waterMl'] as num?)?.toInt() ?? 0;
            if (waterMl != 0) {
              await repo.addWaterMl(watchCommandDate(decoded), waterMl);
            }
            break;
          case 'calories':
            final calories = (decoded['calories'] as num?)?.toInt() ?? 0;
            if (calories > 0) {
              final food = await repo.createCustomFood(
                name: 'Quick Add (Watch)',
                kcalPer100g: calories.toDouble(),
              );
              await repo.logFood(
                date: watchCommandDate(decoded),
                foodId: food.id,
                portionAmount: 100,
                portionUnit: 'g',
              );
            }
            break;
          case 'food':
            final calories = (decoded['calories'] as num?)?.toInt() ?? 0;
            final protein = (decoded['protein'] as num?)?.toInt() ?? 0;
            final carbs = (decoded['carbs'] as num?)?.toInt() ?? 0;
            final fats = (decoded['fats'] as num?)?.toInt() ?? 0;
            if (calories > 0 || protein > 0 || carbs > 0 || fats > 0) {
              final food = await repo.createCustomFood(
                name: 'Quick Add (Watch)',
                kcalPer100g: calories.toDouble(),
                proteinPer100g: protein.toDouble(),
                carbsPer100g: carbs.toDouble(),
                fatPer100g: fats.toDouble(),
              );
              await repo.logFood(
                date: watchCommandDate(decoded),
                foodId: food.id,
                portionAmount: 100,
                portionUnit: 'g',
              );
            }
            break;
        }

        // Only mark this command "seen" once the write above has actually
        // succeeded — see the matching comment in onWatchFastingCommand above.
      });
      await ref
          .read(wearSyncServiceProvider)
          .markWatchMacroCommandApplied(commandId);
      await syncAllToWear();
      ref.read(syncServiceProvider).pushOnce().catchError((_) {});
    } catch (_) {
      // Keep the native pending command until a later retry succeeds. Since
      // commandId is only added to appliedMacroCommands after a successful
      // write, that retry is reapplied rather than skipped as a duplicate.
    }
  };

  WearSyncService.onWatchRamblerCommand = (commandJson) async {
    if (commandJson == null || commandJson.isEmpty) {
      return;
    }
    try {
      final decoded = jsonDecode(commandJson) as Map<String, dynamic>;
      final commandId = decoded['commandId'] as String?;
      if (commandId == null || commandId.isEmpty) {
        return;
      }
      if (await commandInbox.wasApplied('rambler', commandId)) {
        await ref
            .read(wearSyncServiceProvider)
            .markWatchRamblerCommandApplied(commandId);
        return;
      }

      final text = decoded['text'] as String? ?? '';
      final mealKey = decoded['mealKey'] as String? ?? 'lunch';

      if (text.trim().isEmpty) {
        throw const FormatException('Empty Rambler entry');
      }
      if (text.trim().isNotEmpty) {
        final analyzer = ref.read(geminiFoodAnalyzerServiceProvider);
        final result = await analyzer.analyzeRamblerText(
          text: text,
          preferredMealKey: mealKey,
        );

        await commandInbox.applyOnce('rambler', commandId, () async {
          final repo = ref.read(nutritionRepositoryProvider);
          final selectedMeal =
              (result.suggestedMealKey != null &&
                  result.suggestedMealKey!.isNotEmpty)
              ? result.suggestedMealKey!
              : mealKey;

          for (final item in result.items) {
            final food = await repo.createCustomFood(
              name: item.name,
              brand: 'Rambler AI',
              kcalPer100g: item.kcalPer100g,
              proteinPer100g: item.proteinPer100g,
              carbsPer100g: item.carbsPer100g,
              fatPer100g: item.fatPer100g,
              servingGrams: item.servingGrams,
              servingAmount: item.portionAmount,
              servingUnit: item.portionUnit,
              servingLabel:
                  '${item.portionAmount.toStringAsFixed(item.portionAmount % 1 == 0 ? 0 : 1)} ${item.portionUnit}${item.portionUnit == 'g' ? '' : ' (${item.servingGrams.toStringAsFixed(0)} g)'}',
            );

            await repo.logFood(
              date: watchCommandDate(decoded),
              mealKey: selectedMeal,
              foodId: food.id,
              portionAmount: item.portionAmount,
              portionUnit: item.portionUnit,
            );
          }
        });
      }
      await ref
          .read(wearSyncServiceProvider)
          .markWatchRamblerCommandApplied(commandId);
      await syncAllToWear();
      ref.read(syncServiceProvider).pushOnce().catchError((_) {});
    } catch (e) {
      debugPrint('Error processing watch rambler command: $e');
    }
  };

  Timer? nutritionSyncDebounce;
  ref.onDispose(() => nutritionSyncDebounce?.cancel());
  void scheduleNutritionSync() {
    nutritionSyncDebounce?.cancel();
    nutritionSyncDebounce = Timer(const Duration(milliseconds: 750), () {
      nutritionSyncDebounce = null;
      syncAllToWear();
    });
  }

  WearSyncService.onRequestNutritionSync = () {
    final currentDay = getToday();
    if (currentDay != today) {
      ref.invalidateSelf();
    } else {
      syncAllToWear();
    }
  };

  ref.listen<AsyncValue<DailyTotals>>(dailyTotalsProvider(today), (
    previous,
    next,
  ) {
    if (next.hasValue && next.value != null) {
      scheduleNutritionSync();
    }
  }, fireImmediately: true);

  ref.listen<AsyncValue<List<FoodEntryData>>>(entriesForDateProvider(today), (
    previous,
    next,
  ) {
    if (next.hasValue && next.value != null) {
      scheduleNutritionSync();
    }
  });

  ref.listen<List<MealSlot>>(mealSlotsProvider, (previous, next) {
    scheduleNutritionSync();
  });

  ref.listen<AsyncValue<FastingSessionData?>>(activeFastingSessionProvider, (
    previous,
    next,
  ) {
    if (next.hasValue) {
      syncFastingToWear();
      scheduleNutritionSync();
    }
  });

  ref.listen<AsyncValue<WeeklyMuscleVolume>>(weeklyMuscleVolumeProvider, (
    previous,
    next,
  ) {
    if (next.hasValue && next.value != null) {
      scheduleNutritionSync();
    }
  });

  ref.listen<AsyncValue<MacroTargets?>>(effectiveTargetsProvider(today), (
    previous,
    next,
  ) {
    if (next.hasValue) {
      scheduleNutritionSync();
    }
  });

  ref.listen<AsyncValue<Map<String, DailyTotals>>>(nutritionHistoryProvider, (
    previous,
    next,
  ) {
    if (next.hasValue) {
      scheduleNutritionSync();
    }
  });

  ref.listen<AsyncValue<List<RecipeData>>>(recipesProvider, (previous, next) {
    if (next.hasValue) {
      scheduleNutritionSync();
    }
  });

  final observer = _WidgetMacroResumeObserver(() {
    final currentDay = getToday();
    if (currentDay != today) {
      ref.invalidateSelf();
    } else {
      scheduleNutritionSync();
    }
  });
  WidgetsBinding.instance.addObserver(observer);
  ref.onDispose(() => WidgetsBinding.instance.removeObserver(observer));

  Timer? midnightTimer;
  final nowForMidnight = clock.now();
  final tomorrow = DateTime(
    nowForMidnight.year,
    nowForMidnight.month,
    nowForMidnight.day + 1,
  );
  final delayUntilMidnight =
      tomorrow.difference(nowForMidnight) + const Duration(seconds: 1);
  midnightTimer = Timer(delayUntilMidnight, () {
    ref.invalidateSelf();
  });
  ref.onDispose(() => midnightTimer?.cancel());
});

/// Syncs full nutrition totals + targets to the Android home-screen widgets
/// every time [dailyTotalsProvider] or [effectiveTargetsProvider] emits,
/// and re-checks freshness on app resume.
final widgetMacroSyncControllerProvider = Provider<void>((ref) {
  final clock = ref.watch(clockProvider);
  DateTime getToday() {
    final now = clock.now();
    return DateTime(now.year, now.month, now.day);
  }

  final today = ref.watch(localDayProvider);
  final widgetSync = ref.watch(widgetSyncServiceProvider);
  Timer? debounceTimer;

  Future<void> doSync() async {
    DailyTotals? totals = ref.read(dailyTotalsProvider(today)).valueOrNull;
    if (totals == null) {
      try {
        totals = await ref.read(dailyTotalsProvider(today).future);
      } catch (_) {}
    }
    if (totals == null) {
      return;
    }

    MacroTargets? targets = ref
        .read(effectiveTargetsProvider(today))
        .valueOrNull;
    if (targets == null) {
      try {
        targets = await ref.read(effectiveTargetsProvider(today).future);
      } catch (_) {}
    }

    final baseline = ref.read(baselineTargetsProvider);
    final profile =
        ref.read(profileProvider).valueOrNull ??
        await ref.read(profileProvider.future).catchError((_) => null);

    final isoDate = dateIso(today);
    double extraCalories = 0;
    try {
      final healthSamples = await ref
          .read(appDatabaseProvider)
          .select(ref.read(appDatabaseProvider).healthSamples)
          .get();
      final sample = healthSamples
          .where((s) => s.dateIso == isoDate && s.kind == 'active_kcal')
          .firstOrNull;
      if (sample != null) {
        extraCalories = sample.value;
      }
    } catch (_) {}

    final exerciseKcal = extraCalories.round();
    final foodKcal = totals.kcal.round();

    int baseGoalKcal = targets?.kcal ?? baseline?.kcal ?? 0;
    if (profile?.countBurnedCalories == true &&
        targets != null &&
        extraCalories > 0) {
      baseGoalKcal = (targets.kcal - exerciseKcal).clamp(0, 99999);
    } else if (targets != null) {
      baseGoalKcal = targets.kcal;
    }

    final remainingKcal = baseGoalKcal - foodKcal + exerciseKcal;

    await widgetSync.syncNutrition(
      baseGoalKcal: baseGoalKcal,
      foodKcal: foodKcal,
      exerciseKcal: exerciseKcal,
      remainingKcal: remainingKcal,
      carbsCurrent: totals.carbsG.round(),
      carbsTarget: targets?.carbsG ?? baseline?.carbsG ?? 0,
      fatCurrent: totals.fatG.round(),
      fatTarget: targets?.fatG ?? baseline?.fatG ?? 0,
      proteinCurrent: totals.proteinG.round(),
      proteinTarget: targets?.proteinG ?? baseline?.proteinG ?? 0,
    );
  }

  void scheduleSync() {
    debounceTimer?.cancel();
    debounceTimer = Timer(const Duration(milliseconds: 150), () {
      debounceTimer = null;
      doSync();
    });
  }

  ref.onDispose(() => debounceTimer?.cancel());

  ref.listen<AsyncValue<DailyTotals>>(dailyTotalsProvider(today), (_, next) {
    if (next.hasValue && next.value != null) {
      scheduleSync();
    }
  }, fireImmediately: true);

  ref.listen<AsyncValue<MacroTargets?>>(effectiveTargetsProvider(today), (
    _,
    next,
  ) {
    if (next.hasValue) {
      scheduleSync();
    }
  });

  ref.listen<MacroTargets?>(baselineTargetsProvider, (_, next) {
    scheduleSync();
  });

  ref.listen<AsyncValue<Profile?>>(profileProvider, (_, next) {
    if (next.hasValue) {
      scheduleSync();
    }
  });

  ref.listen<AsyncValue<Map<String, DailyTotals>>>(nutritionHistoryProvider, (
    _,
    next,
  ) {
    if (next.hasValue) {
      scheduleSync();
    }
  });

  final observer = _WidgetMacroResumeObserver(() {
    final currentDay = getToday();
    if (currentDay != today) {
      ref.invalidateSelf();
    } else {
      scheduleSync();
    }
  });
  WidgetsBinding.instance.addObserver(observer);
  ref.onDispose(() => WidgetsBinding.instance.removeObserver(observer));
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

/// Provider for 7-day average intake of a specific macro ('kcal', 'protein', 'carbs', 'fat').
/// Excludes today (in-progress day) and computes average across the past 7 completed days.
final averageWeeklyMacroProvider = Provider.autoDispose.family<double?, String>(
  (ref, macro) {
    final history = ref.watch(nutritionHistoryProvider).asData?.value;
    if (history == null || history.isEmpty) {
      return null;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    double total = 0;
    int count = 0;

    for (int i = 1; i <= 7; i++) {
      final d = today.subtract(Duration(days: i));
      final iso = DateFormat('yyyy-MM-dd').format(d);
      if (history.containsKey(iso)) {
        final totals = history[iso];
        if (totals != null) {
          final val = switch (macro) {
            'protein' => totals.proteinG,
            'carbs' => totals.carbsG,
            'fat' => totals.fatG,
            _ => totals.kcal,
          };
          if (val > 0 && !val.isNaN && !val.isInfinite) {
            total += val;
            count++;
          }
        }
      }
    }

    if (count == 0) {
      return null;
    }
    return total / count;
  },
);

/// Provider for Average Weekly Calories (past 7 days daily average).
final averageWeeklyCaloriesProvider = Provider.autoDispose<double?>((ref) {
  return ref.watch(averageWeeklyMacroProvider('kcal'));
});
