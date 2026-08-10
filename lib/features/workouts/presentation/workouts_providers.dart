import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../nutrition/data/wear_sync_service.dart';
import '../../fasting/domain/fasting_sync_snapshot.dart';
import '../../fasting/presentation/fasting_providers.dart';
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

/// Tracks original endedAt timestamps when editing a completed workout session.
/// Map<sessionId, originalEndedAt>
final editingSessionOriginalEndedAtProvider = StateProvider<Map<int, DateTime>>(
  (_) => {},
);

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

/// The one Drift subscription over the exercise catalog. Everything that needs
/// exercises derives from this, so the table is read once rather than once per
/// filter combination.
final exerciseCatalogSnapshotProvider = StreamProvider<ExerciseCatalogSnapshot>(
  (ref) => ref.watch(workoutsRepositoryProvider).watchExerciseCatalog(),
);

/// Facet-filtered catalog view. Kept non-autoDispose because every caller uses
/// the same `const ExerciseCatalogFilter()`, so this is a single cached
/// instance — and the wear-sync provider holds a long-lived listener on it.
/// Free-text queries belong on [exerciseSearchProvider] instead.
final exerciseCatalogProvider =
    Provider.family<
      AsyncValue<List<ExerciseCatalogData>>,
      ExerciseCatalogFilter
    >((ref, filter) {
      return ref
          .watch(exerciseCatalogSnapshotProvider)
          .whenData(
            (snapshot) =>
                snapshot.select(query: filter.query, category: filter.category),
          );
    });

/// Relevance-ranked search for the exercise picker.
///
/// autoDispose because this is keyed on the live query string — one instance
/// per keystroke, all of which must be released. It ranks the already-cached
/// snapshot in memory, so a keystroke costs no database work.
final exerciseSearchProvider = Provider.autoDispose
    .family<AsyncValue<List<ExerciseCatalogData>>, ExerciseCatalogFilter>((
      ref,
      filter,
    ) {
      final recentIds =
          ref.watch(recentExerciseIdsProvider).asData?.value ?? const <int>{};
      return ref
          .watch(exerciseCatalogSnapshotProvider)
          .whenData(
            (snapshot) => snapshot.select(
              query: filter.query,
              category: filter.category,
              recentIds: recentIds,
            ),
          );
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
final lastPerformanceProvider =
    FutureProvider.family<LastPerformanceSnapshot?, int>((
      ref,
      exerciseId,
    ) async {
      return ref
          .watch(workoutsRepositoryProvider)
          .lastPerformanceSnapshotFor(exerciseId);
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

final templateExerciseSetsProvider =
    StreamProvider.family<List<TemplateSetData>, int>((
      ref,
      templateExerciseId,
    ) {
      return ref
          .watch(templatesRepositoryProvider)
          .watchTemplateSets(templateExerciseId);
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
    // Snapshot everything ref-derived up front — same reasoning as the
    // workoutFoldersProvider listener below: this provider's watched
    // streams can flag it as dirty mid-await, and any ref.read after that
    // throws ("Cannot use ref functions after the dependency of a provider
    // changed but before the provider rebuilt").
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final activeSession = ref.read(activeSessionProvider).asData?.value;
    final catalog = ref
        .read(exerciseCatalogProvider(const ExerciseCatalogFilter()))
        .asData
        ?.value;
    final totals = ref.read(dailyTotalsProvider(today)).asData?.value;
    final activeFast = ref.read(activeFastingSessionProvider).asData?.value;
    final wearSyncService = ref.read(wearSyncServiceProvider);

    if (activeSession != null) {
      await syncService.pushActiveSessionToWatch(activeSession);
    }
    if (catalog != null) {
      await syncService.syncCatalogToWatch(catalog);
    }
    if (totals != null) {
      await wearSyncService.syncMacros(
        totals.kcal.round(),
        totals.proteinG.round(),
        carbs: totals.carbsG.round(),
        fats: totals.fatG.round(),
      );
    }
    await wearSyncService.syncFastingSnapshot(
      encodeFastingSnapshot(
        session: activeFast,
        revision: ref.read(wearSyncRevisionAllocatorProvider).next(),
      ),
    );
  };

  // Handle session lifecycle end notifications
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
  });

  // Watch active session and all exercises & sets reactively.
  final activeSession = ref.watch(activeSessionProvider).asData?.value;
  if (activeSession != null) {
    final exercises =
        ref.watch(sessionExercisesProvider(activeSession.id)).asData?.value ??
        const <WorkoutExerciseData>[];

    for (final exercise in exercises) {
      ref.watch(setsForWorkoutExerciseProvider(exercise.id));
    }

    if (!syncService.shouldSkipOutboundSync) {
      Future.microtask(() {
        syncService.pushActiveSessionToWatch(activeSession);
      });
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
      final Map<int, List<TemplateSetData>> templateSets = {};

      // Capture the repository/db instances before any `await` — this
      // provider watches fast-changing streams (active session sets), which
      // can flag its own dependency as changed mid-await and make any
      // further ref.read/watch here throw ("Cannot use ref functions after
      // the dependency of a provider changed but before the provider
      // rebuilt"). Plain values captured up front sidestep that entirely.
      final templatesRepository = ref.read(templatesRepositoryProvider);
      final db = ref.read(appDatabaseProvider);

      // Include un-foldered templates
      final rootTemplates = await templatesRepository
          .watchTemplates(folderId: null)
          .first;
      allTemplates.addAll(rootTemplates);

      for (final folder in folders) {
        final templates = await templatesRepository
            .watchTemplates(folderId: folder.id)
            .first;
        allTemplates.addAll(templates);
      }

      for (final t in allTemplates) {
        final exercises = await templatesRepository
            .watchTemplateExercises(t.id)
            .first;
        templateExercises[t.id] = exercises;
        for (final exercise in exercises) {
          templateSets[exercise.id] = await templatesRepository
              .watchTemplateSets(exercise.id)
              .first;
        }
      }

      final catalog = await db.select(db.exerciseCatalog).get();
      syncService.syncTemplatesToWatch(
        allTemplates,
        templateExercises,
        templateSets,
        catalog,
      );
    }
  }, fireImmediately: true);
});
