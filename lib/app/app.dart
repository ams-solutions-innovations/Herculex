import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/units.dart';
import '../data/local/database.dart';
import '../features/analytics/presentation/analytics_providers.dart';
import '../features/nutrition/presentation/barcode_scanner_view.dart';
import '../features/nutrition/presentation/nutrition_providers.dart';
import '../features/shell/main_scaffold.dart';
import '../features/supplements/data/supplement_repository.dart';
import '../features/supplements/domain/supplement.dart';
import '../features/workouts/data/workout_notification_action_queue.dart';
import '../features/workouts/data/workout_quick_action_settings.dart';
import '../features/workouts/domain/ongoing_workout_surface_snapshot.dart';
import '../features/workouts/domain/workout_notification_command.dart';
import '../services/active_workout_surface_sync_policy.dart';
import '../features/workouts/presentation/workouts_providers.dart';
import '../services/workout_notification_service.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/theme_provider.dart';
import 'router.dart';

class HerculexApp extends ConsumerStatefulWidget {
  const HerculexApp({super.key});

  @override
  ConsumerState<HerculexApp> createState() => _HerculexAppState();
}

class _HerculexAppState extends ConsumerState<HerculexApp> {
  late final AppLifecycleListener _lifecycleListener;
  Timer? _workoutActionDrainTimer;
  bool _isDrainingWorkoutActions = false;
  Timer? _notificationSyncDebounce;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() {
      ref.read(authRepositoryProvider).hydrateFromNative();
    });
    WorkoutNotificationService.onNotificationTap = () {
      ref.read(mainTabIndexProvider.notifier).state = 2;
    };
    WorkoutNotificationService.onNotificationAction =
        (actionId, sessionId, setId) async => _applyWorkoutNotificationAction(
          actionId,
          sessionId: sessionId,
          targetSetId: setId,
        );
    WorkoutNotificationService.instance.init();
    Future<void>.microtask(_drainPendingWorkoutNotificationActions);

    // Listen for the scanner deep-link from the Scanner home-screen widget.
    // When the user taps the widget, Android sends 'openScanner' via
    // the widget MethodChannel. We push the barcode scanner route.
    const widgetChannel = MethodChannel('com.ams.herculex/widget');
    widgetChannel.setMethodCallHandler((call) async {
      if (call.method == 'openActiveWorkout' && mounted) {
        ref.read(mainTabIndexProvider.notifier).state = 2;
        ref.read(routerProvider).go('/app');
        return;
      }
      if (call.method == 'openScanner' && mounted) {
        // Navigate to the nutrition tab and open the scanner.
        // BarcodeScannerView is pushed as a full-screen route from
        // nutrition_view.dart — we replicate that here from the root navigator.
        final ctx = context;
        if (ctx.mounted) {
          await Navigator.of(ctx, rootNavigator: true).push(
            MaterialPageRoute(
              builder: (_) => const BarcodeScannerView(),
              fullscreenDialog: true,
            ),
          );
        }
      }
    });

    _lifecycleListener = AppLifecycleListener(
      onHide: _onBackground,
      onPause: _onBackground,
      onInactive: _onBackground,
      onResume: _onForeground,
      onShow: _onForeground,
    );
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    _stopPendingWorkoutActionDrain();
    _notificationSyncDebounce?.cancel();
    WorkoutNotificationService.instance.cancel();
    super.dispose();
  }

  void _onBackground() {
    _syncNotification();
  }

  void _onForeground() {
    _drainPendingWorkoutNotificationActions();
    _syncNotification();
  }

  /// Several independent providers (session exercises, and one per exercise's
  /// sets) can each fire a listener for the same underlying database write —
  /// e.g. completing a set touches both the sets table and, via cascading
  /// recalculation, the exercise row. Debouncing collapses those near-
  /// simultaneous triggers into a single native `update()` call instead of
  /// reposting the notification once per listener.
  void _syncNotification() {
    _notificationSyncDebounce?.cancel();
    _notificationSyncDebounce = Timer(
      const Duration(milliseconds: 200),
      _syncNotificationNow,
    );
  }

  /// Reads the supplement list and fires a notification for any supplement
  /// that has [SupplementSchedule.postWorkout] set.
  void _firePostWorkoutSupplementReminder() {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final repo = SupplementRepository(prefs);
      final postWorkout = repo
          .loadSupplements()
          .where((s) => s.schedule == SupplementSchedule.postWorkout)
          .map((s) => s.name)
          .toList();
      if (postWorkout.isNotEmpty) {
        WorkoutNotificationService.instance.showSupplementReminder(postWorkout);
      }
    } catch (_) {
      // Silently ignore — supplement reminder is non-critical.
    }
  }

  void _syncNotificationNow() {
    final sessionAsync = ref.read(activeSessionProvider);
    if (!sessionAsync.hasValue) {
      return;
    }
    final session = sessionAsync.asData?.value;
    if (shouldClearOngoingWorkoutSurface(sessionAsync)) {
      _stopPendingWorkoutActionDrain();
      WorkoutNotificationService.instance.cancel();
      return;
    }
    if (session == null) {
      return;
    }
    _startPendingWorkoutActionDrain();
    unawaited(_syncWorkoutNotificationFor(session));
  }

  Future<void> _syncWorkoutNotificationFor(WorkoutSessionData session) async {
    final repo = ref.read(workoutsRepositoryProvider);
    final target = await repo.activeNotificationTargetForSession(session.id);
    if (!mounted) return;
    final activeSession = ref.read(activeSessionProvider).asData?.value;
    if (activeSession?.id != session.id) return;

    final weightFormat = ref.read(weightFormatProvider);
    final snapshot = buildOngoingWorkoutSurfaceSnapshot(
      target: target,
      formatWeight: weightFormat.format,
      loadStepKg: ref.read(quickLoadStepProvider),
    );
    unawaited(
      WorkoutNotificationService.instance.showOrUpdate(
        sessionId: session.id,
        startedAt: session.startedAt,
        exerciseName: snapshot.exerciseName,
        workoutName: session.name,
        currentSet: snapshot.currentSet,
        totalSets: snapshot.totalSets,
        weightLabel: snapshot.weightLabel,
        loadStepLabel: snapshot.loadStepLabel,
        actions: snapshot.actions,
        targetSetId: snapshot.targetSetId,
        reps: snapshot.reps,
      ),
    );
  }

  Future<bool> _applyWorkoutNotificationAction(
    String actionId, {
    int? sessionId,
    int? targetSetId,
  }) async {
    final session = ref.read(activeSessionProvider).asData?.value;
    if (session == null) return false;
    if (sessionId != null && sessionId != session.id) return true;

    final repo = ref.read(workoutsRepositoryProvider);
    final target = await repo.activeNotificationTargetForSession(session.id);
    if (target == null) return false;
    if (targetSetId != null && target.set.id != targetSetId) return true;

    final targetSet = target.set;
    final patch = workoutNotificationPatchForAction(
      actionId: actionId,
      set: targetSet,
      weightStepKg: ref.read(quickLoadStepProvider),
    );
    if (patch == null) return true;

    await repo.updateSet(
      setId: targetSet.id,
      reps: patch.reps,
      weightKg: patch.weightKg,
      isCompleted: patch.isCompleted,
    );

    await _syncWorkoutNotificationFor(session);
    return true;
  }

  Future<void> _drainPendingWorkoutNotificationActions() async {
    if (_isDrainingWorkoutActions) return;
    _isDrainingWorkoutActions = true;
    final prefs = ref.read(sharedPreferencesProvider);
    try {
      final activeSessionId = ref.read(activeSessionProvider).asData?.value?.id;
      final fallbackDrain =
          PendingWorkoutNotificationActionQueue.drainForSession(
            prefs,
            activeSessionId,
          );
      final pending = [...fallbackDrain.actions];
      if (pending.isEmpty && fallbackDrain.remaining.isEmpty) return;

      final remaining = [...fallbackDrain.remaining];
      for (final action in pending) {
        final applied = await _applyWorkoutNotificationAction(
          action.actionId,
          sessionId: action.sessionId ?? activeSessionId,
          targetSetId: action.setId,
        );
        if (!applied) {
          remaining.add(
            PendingWorkoutNotificationAction(
              actionId: action.actionId,
              sessionId: activeSessionId,
              setId: action.setId,
            ),
          );
        }
      }
      await PendingWorkoutNotificationActionQueue.replace(prefs, remaining);
    } finally {
      _isDrainingWorkoutActions = false;
    }
  }

  void _startPendingWorkoutActionDrain() {
    if (_workoutActionDrainTimer?.isActive ?? false) return;
    _workoutActionDrainTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_drainPendingWorkoutNotificationActions()),
    );
  }

  void _stopPendingWorkoutActionDrain() {
    _workoutActionDrainTimer?.cancel();
    _workoutActionDrainTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    // Initialize wear sync listening.
    ref.watch(wearSyncControllerProvider);
    ref.watch(wearWorkoutSyncControllerProvider);

    // Initialize Android home-screen widget sync.
    ref.watch(widgetMacroSyncControllerProvider);
    ref.watch(widgetCnsSyncControllerProvider);
    ref.watch(widgetRecoverySyncControllerProvider);

    final router = ref.watch(routerProvider);
    WorkoutNotificationService.onNotificationTap = () {
      ref.read(mainTabIndexProvider.notifier).state = 2;
      router.go('/app');
    };

    // Keep notification in sync when active session changes.
    ref.listen(activeSessionProvider, (previous, next) {
      _syncNotification();
      // Fire post-workout supplement reminder when session transitions active→null.
      final hadSession = previous?.asData?.value != null;
      final hasSession = next.asData?.value != null;
      if (hadSession && !hasSession) {
        _firePostWorkoutSupplementReminder();
      }
    });

    ref.listen(unitsProvider, (_, _) => _syncNotification());
    ref.listen(quickLoadStepProvider, (_, _) => _syncNotification());

    final activeSession = ref.watch(activeSessionProvider).asData?.value;
    if (activeSession != null) {
      ref.listen(sessionExercisesProvider(activeSession.id), (_, next) {
        if (next.hasValue) {
          _syncNotification();
        }
      });

      final exercises =
          ref.watch(sessionExercisesProvider(activeSession.id)).asData?.value ??
          const [];
      for (final exercise in exercises) {
        ref.listen(setsForWorkoutExerciseProvider(exercise.id), (_, next) {
          if (next.hasValue) {
            _syncNotification();
          }
        });
      }
    }

    final themeMode = ref.watch(themeModeProvider);

    final platformBrightness = MediaQuery.platformBrightnessOf(context);
    final effectiveBrightness = switch (themeMode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => platformBrightness,
    };

    AppColors.brightness = effectiveBrightness;

    final isDark = effectiveBrightness == Brightness.dark;
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: isDark
            ? Brightness.light
            : Brightness.dark,
      ),
    );

    return MaterialApp.router(
      key: ValueKey(
        '${themeMode.name}_${effectiveBrightness.name}',
      ), // Rebuild widget tree when theme changes
      title: 'Herculex',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(gradient: AppColors.backgroundGradient),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
