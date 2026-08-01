import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../nutrition/data/wear_sync_service.dart';
import '../../../app/providers.dart';
import '../../../data/local/database.dart';
import '../data/micro_workouts_repository.dart';
import '../data/templates_repository.dart';
import '../data/workouts_repository.dart';
import '../data/wear_workout_sync_service.dart';
import '../../analytics/presentation/analytics_providers.dart';
import '../../nutrition/presentation/nutrition_providers.dart';
import '../domain/calendar_service.dart';
import '../domain/session_summary.dart';

final workoutsRepositoryProvider = Provider<WorkoutsRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final clock = ref.watch(clockProvider);
  return WorkoutsRepository(db, clock);
});

final wearWorkoutSyncServiceProvider = Provider<WearWorkoutSyncService>((ref) {
  return WearWorkoutSyncService(
    ref.watch(workoutsRepositoryProvider),
    ref.watch(wearSyncServiceProvider),
    ref.watch(appDatabaseProvider),
    ref,
  );
});

final activeSessionProvider = StreamProvider<WorkoutSessionData?>((ref) {
  return ref.watch(workoutsRepositoryProvider).watchActiveSession();
});

final recentSessionsProvider = StreamProvider<List<WorkoutSessionData>>((ref) {
  return ref.watch(workoutsRepositoryProvider).watchRecentSessions();
});

final workoutSessionProvider = StreamProvider.family<WorkoutSessionData, int>((
  ref,
  sessionId,
) {
  return ref.watch(workoutsRepositoryProvider).watchSession(sessionId);
});

/// Headline totals for a finished session, backing the finish screen and its
/// shareable card. Reads the same snapshot the analytics engines use, so the
/// tonnage here matches the dashboard rather than being recomputed naively.
final sessionSummaryProvider = FutureProvider.autoDispose
    .family<SessionSummary, int>((ref, sessionId) async {
      final snapshot = await ref.watch(trainingSnapshotProvider.future);
      final session = await ref.watch(workoutSessionProvider(sessionId).future);
      return SessionSummary.fromSnapshot(
        snapshot: snapshot,
        sessionId: sessionId,
        name: (session.name?.trim().isNotEmpty ?? false)
            ? session.name!.trim()
            : 'Workout',
        startedAt: session.startedAt,
        endedAt: session.endedAt,
      );
    });

class ExerciseCatalogFilter {
  final String? query;
  final String? category;
  const ExerciseCatalogFilter({this.query, this.category});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExerciseCatalogFilter &&
          runtimeType == other.runtimeType &&
          query == other.query &&
          category == other.category;

  @override
  int get hashCode => query.hashCode ^ category.hashCode;
}

final exerciseCatalogProvider =
    StreamProvider.family<List<ExerciseCatalogData>, ExerciseCatalogFilter>((
      ref,
      filter,
    ) {
      return ref
          .watch(workoutsRepositoryProvider)
          .watchExercises(query: filter.query, category: filter.category);
    });

final sessionExercisesProvider =
    StreamProvider.family<List<WorkoutExerciseData>, int>((ref, sessionId) {
      return ref
          .watch(workoutsRepositoryProvider)
          .watchSessionExercises(sessionId);
    });

final setsForWorkoutExerciseProvider =
    StreamProvider.family<List<SetEntryData>, int>((ref, workoutExerciseId) {
      return ref
          .watch(workoutsRepositoryProvider)
          .watchSetsForWorkoutExercise(workoutExerciseId);
    });

/// (exerciseId) → [last completed working sets from prior session]
final lastPerformanceProvider = FutureProvider.family<List<SetEntryData>, int>((
  ref,
  exerciseId,
) async {
  return ref.watch(workoutsRepositoryProvider).lastPerformanceFor(exerciseId);
});

final recentExerciseIdsProvider = FutureProvider<Set<int>>((ref) async {
  return ref.watch(workoutsRepositoryProvider).getRecentExerciseIds();
});

final calendarServiceProvider = Provider<CalendarService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return CalendarService(db);
});

final templatesRepositoryProvider = Provider<TemplatesRepository>((ref) {
  return TemplatesRepository(ref.watch(appDatabaseProvider));
});

final workoutFoldersProvider = StreamProvider<List<WorkoutFolderData>>((ref) {
  return ref.watch(templatesRepositoryProvider).watchFolders();
});

final workoutTemplatesProvider =
    StreamProvider.family<List<WorkoutTemplateData>, int?>((ref, folderId) {
      return ref
          .watch(templatesRepositoryProvider)
          .watchTemplates(folderId: folderId);
    });

final templateExercisesProvider =
    StreamProvider.family<List<TemplateExerciseData>, int>((ref, templateId) {
      return ref
          .watch(templatesRepositoryProvider)
          .watchTemplateExercises(templateId);
    });

// ── V2 logging foundation (Phase 2) ──────────────────────────────────────────

/// Classic vs. Dynamic full-screen workout mode (§14). Session-scoped UI state.
final dynamicWorkoutModeProvider = StateProvider<bool>((_) => false);

final gymsProvider = StreamProvider<List<GymData>>((ref) {
  return ref.watch(gymsRepositoryProvider).watchGyms();
});

final accessoriesProvider = StreamProvider<List<AccessoryData>>((ref) {
  return ref.watch(accessoriesRepositoryProvider).watchAccessories();
});

final bandsProvider = StreamProvider<List<BandData>>((ref) {
  return ref.watch(accessoriesRepositoryProvider).watchBands();
});

final setAccessoriesProvider =
    StreamProvider.family<List<SetAccessoryData>, int>((ref, setEntryId) {
      return ref
          .watch(accessoriesRepositoryProvider)
          .watchSetAccessories(setEntryId);
    });

final setBandsProvider = StreamProvider.family<List<SetBandData>, int>((
  ref,
  setEntryId,
) {
  return ref.watch(accessoriesRepositoryProvider).watchSetBands(setEntryId);
});

/// Latest logged bodyweight — snapshotted onto weighted-bodyweight sets (§9).
final latestBodyweightProvider = FutureProvider<double?>((ref) {
  return ref.watch(measurementsRepositoryProvider).latestBodyweightKg();
});

final microWorkoutsRepositoryProvider = Provider<MicroWorkoutsRepository>((
  ref,
) {
  return MicroWorkoutsRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(clockProvider),
  );
});

/// Active micro workouts with today's completion counts (§20).
final microWorkoutsTodayProvider = StreamProvider<List<MicroWorkoutStatus>>((
  ref,
) {
  return ref.watch(microWorkoutsRepositoryProvider).watchTodayStatus();
});

/// Per-exercise progression override row (§16). Null = no override set.
final exerciseProgressionProvider =
    FutureProvider.family<ExerciseProgressionData?, int>((ref, exerciseId) {
      return ref
          .watch(exerciseProgressionsRepositoryProvider)
          .forExercise(exerciseId);
    });

final wearWorkoutSyncControllerProvider = Provider<void>((ref) {
  // Need to eagerly load the sync service so its callbacks are registered.
  final syncService = ref.watch(wearWorkoutSyncServiceProvider);

  // Handle explicit sync requests from watch
  WearSyncService.onRequestSync = () async {
    final activeSession = ref.read(activeSessionProvider).asData?.value;
    if (activeSession != null) {
      await syncService.pushActiveSessionToWatch(activeSession);
    }
    final catalog = ref
        .read(exerciseCatalogProvider(const ExerciseCatalogFilter()))
        .asData
        ?.value;
    if (catalog != null) {
      await syncService.syncCatalogToWatch(catalog);
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final totals = ref.read(dailyTotalsProvider(today)).asData?.value;
    if (totals != null) {
      await ref
          .read(wearSyncServiceProvider)
          .syncMacros(
            totals.kcal.round(),
            totals.proteinG.round(),
            carbs: totals.carbsG.round(),
            fats: totals.fatG.round(),
          );
    }
  };

  // Session content changes below are the single source of outbound active
  // workout snapshots. This listener only tears down the watch session when
  // the phone session ends, avoiding duplicate start pushes during creation.
  ref.listen<AsyncValue<WorkoutSessionData?>>(activeSessionProvider, (
    previous,
    next,
  ) {
    if (next.hasValue &&
        next.value == null &&
        previous?.hasValue == true &&
        previous?.value != null) {
      syncService.notifySessionEnded();
    }
  }, fireImmediately: true);

  // Watch session exercise changes during an active workout session
  final activeSession = ref.watch(activeSessionProvider).asData?.value;
  if (activeSession != null) {
    void pushActiveSessionSnapshot() {
      if (!syncService.shouldSkipOutboundSync) {
        syncService.pushActiveSessionToWatch(activeSession);
      }
    }

    ref.listen<AsyncValue<List<WorkoutExerciseData>>>(
      sessionExercisesProvider(activeSession.id),
      (previous, next) {
        if (next.hasValue) {
          pushActiveSessionSnapshot();
        }
      },
      fireImmediately: true,
    );

    final exercises =
        ref.watch(sessionExercisesProvider(activeSession.id)).asData?.value ??
        const <WorkoutExerciseData>[];
    for (final exercise in exercises) {
      ref.listen<AsyncValue<List<SetEntryData>>>(
        setsForWorkoutExerciseProvider(exercise.id),
        (previous, next) {
          if (next.hasValue) {
            pushActiveSessionSnapshot();
          }
        },
      );
    }
  }

  // Watch exercise catalog and sync custom exercises to watch
  ref.listen(exerciseCatalogProvider(const ExerciseCatalogFilter()), (
    previous,
    next,
  ) {
    if (next.hasValue && next.value != null) {
      syncService.syncCatalogToWatch(next.value!);
    }
  }, fireImmediately: true);

  // Watch templates and sync to watch
  // We sync all templates across all folders
  ref.listen<AsyncValue<List<WorkoutFolderData>>>(workoutFoldersProvider, (
    previous,
    next,
  ) async {
    if (next.hasValue) {
      final folders = next.value ?? [];
      final List<WorkoutTemplateData> allTemplates = [];
      final Map<int, List<TemplateExerciseData>> templateExercises = {};

      // Include un-foldered templates
      final rootTemplates = await ref
          .read(templatesRepositoryProvider)
          .watchTemplates(folderId: null)
          .first;
      allTemplates.addAll(rootTemplates);

      for (final folder in folders) {
        final templates = await ref
            .read(templatesRepositoryProvider)
            .watchTemplates(folderId: folder.id)
            .first;
        allTemplates.addAll(templates);
      }

      for (final t in allTemplates) {
        templateExercises[t.id] = await ref
            .read(templatesRepositoryProvider)
            .watchTemplateExercises(t.id)
            .first;
      }

      final catalog = await ref
          .read(appDatabaseProvider)
          .select(ref.read(appDatabaseProvider).exerciseCatalog)
          .get();
      syncService.syncTemplatesToWatch(
        allTemplates,
        templateExercises,
        catalog,
      );
    }
  }, fireImmediately: true);
});
