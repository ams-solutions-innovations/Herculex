part of '../workouts_providers.dart';

final wearWorkoutSyncControllerProvider = Provider<void>((ref) {
  // Need to eagerly load the sync service so its callbacks are registered.
  final syncService = ref.watch(wearWorkoutSyncServiceProvider);
  ref.watch(mediaSyncServiceProvider);

  // Handle explicit sync requests from watch
  WearSyncService.onRequestSync = () async {
    // Snapshot everything ref-derived up front — same reasoning as the
    // workoutFoldersProvider listener below: this provider's watched
    // streams can flag it as dirty mid-await, and any ref.read after that
    // throws ("Cannot use ref functions after the dependency of a provider
    // changed but before the provider rebuilt").
    final activeSession = ref.read(activeSessionProvider).asData?.value;
    final catalog = ref
        .read(exerciseCatalogProvider(const ExerciseCatalogFilter()))
        .asData
        ?.value;
    final wearSyncService = ref.read(wearSyncServiceProvider);

    if (activeSession != null) {
      await syncService.pushActiveSessionToWatch(activeSession);
    }
    if (catalog != null) {
      await syncService.syncCatalogToWatch(catalog);
    }
    final cns = ref.read(cnsTrendsProvider).asData?.value;
    if (cns != null) {
      await wearSyncService.syncCns(
        readinessPct: (cns.readiness * 100).round(),
        status: cns.status,
      );
    }
  };

  // Watch active session and all exercises & sets reactively.
  final activeSession = ref.watch(activeSessionProvider).asData?.value;
  ref.watch(mediaSyncServiceProvider).setWorkoutActive(activeSession != null);
  if (activeSession != null) {
    final exercises =
        ref.watch(sessionExercisesProvider(activeSession.id)).asData?.value ??
        const <WorkoutExerciseData>[];

    for (final exercise in exercises) {
      ref.watch(setsForWorkoutExerciseProvider(exercise.id));
    }

    Future.microtask(() {
      syncService.scheduleOutboundSync(activeSession);
    });
  } else {
    if (!syncService.shouldSkipOutboundSync &&
        syncService.hasActiveSyncedSession) {
      Future.microtask(() {
        syncService.notifySessionEnded();
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

  // Push every template (all folders) plus today's scheduled workout to the
  // watch. Runs when templates change and again when the schedule changes.
  List<WorkoutFolderData>? queuedFolders;
  Future<void>? templatePushDrain;
  var templateSyncDisposed = false;
  ref.onDispose(() {
    templateSyncDisposed = true;
  });
  Future<void> pushTemplatesToWatch(List<WorkoutFolderData> folders) async {
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
    final scheduledService = ref.read(scheduledWorkoutServiceProvider);

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
    final scheduledToday = await scheduledService.todaysWorkouts();
    if (templateSyncDisposed) {
      return;
    }
    await syncService.syncTemplatesToWatch(
      allTemplates,
      templateExercises,
      templateSets,
      catalog,
      scheduledToday: scheduledToday,
    );
  }

  void requestTemplatePush(List<WorkoutFolderData> folders) {
    queuedFolders = folders;
    if (templatePushDrain != null) {
      return;
    }
    templatePushDrain =
        Future<void>(() async {
          while (!templateSyncDisposed && queuedFolders != null) {
            final pending = queuedFolders!;
            queuedFolders = null;
            try {
              await pushTemplatesToWatch(pending);
            } on Object catch (error) {
              debugPrint(
                'Workout library sync will retry on the next change: $error',
              );
            }
          }
        }).whenComplete(() {
          templatePushDrain = null;
        });
    unawaited(templatePushDrain);
  }

  ref.listen<AsyncValue<List<WorkoutFolderData>>>(workoutFoldersProvider, (
    previous,
    next,
  ) {
    if (next.hasValue) {
      requestTemplatePush(next.value ?? []);
    }
  }, fireImmediately: true);

  ref.listen<AsyncValue<List<TodaysScheduledWorkout>>>(
    todaysScheduledWorkoutsProvider,
    (previous, next) {
      final folders = ref.read(workoutFoldersProvider).valueOrNull;
      if (next.hasValue && folders != null) {
        requestTemplatePush(folders);
      }
    },
  );
});
