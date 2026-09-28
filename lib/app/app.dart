import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/app/router/router.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/core/notifications/in_app_notification_overlay.dart';
import 'package:herculex/core/notifications/toast/hx_toast_overlay.dart';
import 'package:herculex/core/utils/units.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/theme/app_theme.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/theme/theme_provider.dart';
import 'package:herculex/features/analytics/application/analytics_providers.dart';
import 'package:herculex/features/buddy/application/buddy_providers.dart';
import 'package:herculex/features/dashboard/application/dashboard_providers.dart';
import 'package:herculex/features/fasting/application/fasting_providers.dart';
import 'package:herculex/features/fasting/data/fasting_schedule_action_queue.dart';
import 'package:herculex/features/fasting/domain/fasting_plan.dart';
import 'package:herculex/features/fasting/domain/fasting_schedule_occurrence.dart';
import 'package:herculex/features/notifications/application/notification_settings_provider.dart';
import 'package:herculex/features/notifications/data/notification_sync_service.dart';
import 'package:herculex/features/nutrition/application/nutrition_providers.dart';
import 'package:herculex/features/nutrition/application/tdee_recalibration_controller.dart';
import 'package:herculex/features/nutrition/domain/meal.dart';
import 'package:herculex/features/nutrition/presentation/dialogs/gemini_photo_analysis_dialog.dart';
import 'package:herculex/features/nutrition/presentation/sheets/food_picker_sheet.dart';
import 'package:herculex/features/nutrition/presentation/views/barcode_scanner_view.dart';
import 'package:herculex/features/shell/main_scaffold.dart';
import 'package:herculex/features/supplements/data/supplement_repository.dart';
import 'package:herculex/features/supplements/domain/supplement.dart';
import 'package:herculex/features/workouts/application/circuits_providers.dart';
import 'package:herculex/features/workouts/application/workout_bubble_controller.dart';
import 'package:herculex/features/workouts/application/workouts_providers.dart';
import 'package:herculex/features/workouts/data/workout_notification_action_queue.dart';
import 'package:herculex/features/workouts/data/workout_quick_action_settings.dart';
import 'package:herculex/features/workouts/domain/ongoing_workout_surface_snapshot.dart';
import 'package:herculex/features/workouts/domain/workout_notification_command.dart';
import 'package:herculex/features/workouts/presentation/sheets/exercise_picker_sheet.dart';
import 'package:herculex/services/ai/pending_ai_scan_service.dart';
import 'package:herculex/services/platform/active_workout_surface_sync_policy.dart';
import 'package:herculex/services/platform/workout_bubble_service.dart';
import 'package:herculex/services/platform/workout_notification_service.dart';
import 'package:image_picker/image_picker.dart';

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
  Timer? _fastingScheduleCheckTimer;

  /// Workout Bubble visibility inputs. The bubble is only ever shown while the
  /// app is in the background, so its state has to be tracked here rather than
  /// derived on demand — provider changes can move the bubble too (a workout
  /// ending on the watch, the setting being switched off).
  bool _appBackgrounded = false;
  bool _bubblePermissionGranted = false;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() {
      ref.read(authRepositoryProvider).hydrate();
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
    // Popup controls carry action IDs or value edits back to the app.
    WorkoutBubbleService.onAction = (actionId, sessionId, setId, value) async {
      await _applyWorkoutBubbleAction(
        actionId,
        sessionId: sessionId,
        targetSetId: setId,
        value: value,
      );
      await _syncBubble();
    };
    WorkoutBubbleService.instance.init();
    Future<void>.microtask(_refreshBubblePermission);
    Future<void>.microtask(_drainPendingWorkoutNotificationActions);
    Future<void>.microtask(_drainPendingFastingScheduleActions);
    Future<void>.microtask(_checkAndAutoStartFastingSchedules);
    _startFastingScheduleCheck();
    // An Android reboot clears exact alarms, and edits made offline before
    // the app last closed still need to reach the notification plugin —
    // full rehydrate on every launch, same reasoning as workout actions.
    Future<void>.microtask(_rehydrateFastingSchedules);
    // Same reasoning again: buddySessionControllerProvider comes back with
    // its default not-sharing state on every cold start, even when
    // buddy_sessions_local still has a live row and the shared exercise
    // list is sitting durably in the event log. Without this, a killed and
    // reopened app silently drops out of an active Gym Buddy session.
    Future<void>.microtask(
      () => ref.read(buddySessionControllerProvider.notifier).resumeIfActive(),
    );
    Future<void>.microtask(() {
      ref.read(notificationSyncServiceProvider).syncAll();
    });

    // Listen for the scanner deep-link from the Scanner home-screen widget.
    // When the user taps the widget, Android sends 'openScanner' via
    // the widget MethodChannel. We push the barcode scanner route.
    const widgetChannel = MethodChannel('com.ams.herculex/widget');
    widgetChannel.setMethodCallHandler((call) async {
      if (call.method == 'openActiveWorkout' && mounted) {
        final args = (call.arguments as Map?)?.cast<String, dynamic>();
        final action = args?['action'] as String?;
        ref.read(mainTabIndexProvider.notifier).state = 2;
        ref.read(routerProvider).go(AppRoutes.app);

        if (action == 'add_exercise') {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            final activeSession = ref.read(activeSessionProvider).valueOrNull;
            if (activeSession != null && mounted) {
              final results = await ExercisePickerSheet.show(context);
              if (results == null || results.isEmpty || !mounted) return;
              final repo = ref.read(workoutsRepositoryProvider);
              final circuitIds = <int>{};
              for (final result in results) {
                if (!mounted) return;
                if (result.circuitId != null) {
                  if (!circuitIds.contains(result.circuitId!)) {
                    circuitIds.add(result.circuitId!);
                    await ref
                        .read(circuitsRepositoryProvider)
                        .addCircuitToSession(
                          sessionId: activeSession.id,
                          circuitId: result.circuitId!,
                        );
                  }
                  continue;
                }
                final picked = result.exercise;
                final variant = result.equipmentVariant ?? picked.modality;
                await repo.addExerciseToSession(
                  sessionId: activeSession.id,
                  exerciseId: picked.id,
                  equipmentVariant: variant,
                );
              }
            }
          });
        }
        return;
      }
      if (call.method == 'openNutrition' && mounted) {
        ref.read(mainTabIndexProvider.notifier).state = 1;
        ref.read(routerProvider).go(AppRoutes.app);
        return;
      }
      if (call.method == 'addWater') {
        // Quick Actions widget's "+250 ml" button. Mirrors the same
        // DateTime.now() call already used for manual water logging in
        // nutrition_providers.dart — no UI to reflect a Clock override here.
        await ref
            .read(nutritionRepositoryProvider)
            .addWaterMl(DateTime.now(), 250);
        return;
      }
      if (call.method == 'openFoodSearch' && mounted) {
        ref.read(mainTabIndexProvider.notifier).state = 1;
        ref.read(routerProvider).go(AppRoutes.app);
        final ctx = context;
        if (ctx.mounted) {
          final now = DateTime.now();
          final date = DateTime(now.year, now.month, now.day);
          await FoodPickerSheet.show(ctx, date: date, mealKey: 'lunch');
        }
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
      if (call.method == 'openCameraFoodLog' && mounted) {
        // The Today's Calories widget's "Photo" button: go straight to the
        // camera, same as tapping "Take a photo of food" inside
        // FoodPickerSheet, instead of landing on the Nutrition tab and making
        // the user find the camera action themselves.
        ref.read(mainTabIndexProvider.notifier).state = 1;
        ref.read(routerProvider).go(AppRoutes.app);
        const mealKey = 'lunch'; // Same fallback openFoodSearch uses above.
        final now = DateTime.now();
        final date = DateTime(now.year, now.month, now.day);
        await ref
            .read(pendingAiScanServiceProvider)
            .setPendingContext(
              PendingAiScanContext(
                type: AiScanContextType.food,
                mealKey: mealKey,
                dateIso: date.toIso8601String(),
              ),
            );
        final picked = await ImagePicker().pickImage(
          source: ImageSource.camera,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 85,
        );
        await ref.read(pendingAiScanServiceProvider).clearPendingContext();
        final ctx = context;
        if (picked != null && ctx.mounted) {
          await GeminiPhotoAnalysisDialog.show(
            ctx,
            imageFile: File(picked.path),
            meal: Meal.fromName(mealKey),
            mealKey: mealKey,
            date: date,
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
    _stopFastingScheduleCheck();
    _notificationSyncDebounce?.cancel();
    WorkoutNotificationService.instance.cancel();
    WorkoutBubbleService.instance.hide();
    super.dispose();
  }

  void _onBackground() {
    _appBackgrounded = true;
    _stopFastingScheduleCheck();
    _syncNotification();
    unawaited(_syncBubble());
  }

  void _onForeground() {
    _appBackgrounded = false;
    _drainPendingWorkoutNotificationActions();
    _drainPendingFastingScheduleActions();
    unawaited(_checkAndAutoStartFastingSchedules());
    _startFastingScheduleCheck();
    _syncNotification();
    // Re-read on every resume: the user can revoke "Display over other apps"
    // from system settings at any time, and coming back is the only moment we
    // reliably get to notice.
    unawaited(_refreshBubblePermission());
  }

  /// Reconciles the bubble with the current session, setting and permission,
  /// and refreshes what its popup displays. Idempotent — the native side
  /// re-renders an already-visible bubble rather than rebuilding it, so this is
  /// also the update path after every set edit.
  ///
  /// [snapshot] lets a caller that already built one hand it over, so a set
  /// edit costs a single target query rather than one per surface.
  Future<void> _syncBubble({OngoingWorkoutSurfaceSnapshot? snapshot}) async {
    if (!WorkoutBubbleService.instance.isSupported) return;
    final sessionAsync = ref.read(activeSessionProvider);
    final visible = shouldShowWorkoutBubble(
      activeSession: sessionAsync,
      enabled: ref.read(workoutBubbleEnabledProvider),
      appBackgrounded: _appBackgrounded,
      permissionGranted: _bubblePermissionGranted,
    );
    // `valueOrNull`, not `asData`: an errored provider that retains a previous
    // session is `hasValue`, which the policy above accepts, but `asData` is
    // null for it.
    final session = sessionAsync.valueOrNull;
    if (!visible || session == null) {
      await WorkoutBubbleService.instance.hide();
      return;
    }

    final resolved = snapshot ?? await _surfaceSnapshotFor(session);
    if (!mounted) return;
    // An awaited query above can outlive the session it was started for.
    if (ref.read(activeSessionProvider).valueOrNull?.id != session.id) return;

    final stats =
        ref.read(activeSessionStatsProvider(session.id)).valueOrNull ??
        const LiveWorkoutStats();
    final weightFormat = ref.read(weightFormatProvider);
    final tonnageText = weightFormat.formatTonnage(stats.totalTonnageKg);
    final setsText = stats.totalSets == 0
        ? '0'
        : (stats.completedSets == stats.totalSets
              ? '${stats.totalSets}'
              : '${stats.completedSets} / ${stats.totalSets}');

    await WorkoutBubbleService.instance.show(
      sessionId: session.id,
      startedAtEpochMs: session.startedAt.millisecondsSinceEpoch,
      exerciseName: resolved.exerciseName,
      subtitle: resolved.subtitle,
      setNumber: resolved.currentSet != null ? '${resolved.currentSet}' : '1',
      weight: resolved.weightKg != null
          ? weightFormat.formatValue(resolved.weightKg!)
          : '-',
      reps: resolved.reps != null ? '${resolved.reps}' : '-',
      rpe: 'RPE',
      totalSetsText: setsText,
      tonnageText: tonnageText,
      lastSetText: resolved.lastSetSummary,
      targetSetId: resolved.targetSetId,
      actions: [
        for (final action in resolved.actions)
          <String, Object?>{
            'id': action.id,
            'label': action.label,
            // Which control is the primary one is a workout-domain call, so
            // it is decided here rather than by the native renderer matching
            // on an action ID it would have to keep in sync.
            'primary': action.id == WorkoutNotificationActionIds.completeSet,
          },
      ],
    );
  }

  Future<void> _refreshBubblePermission() async {
    if (!WorkoutBubbleService.instance.isSupported) return;
    final granted = await WorkoutBubbleService.instance.hasPermission();
    if (!mounted) return;
    _bubblePermissionGranted = granted;
    await _syncBubble();
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
      final notifSettings = ref.read(notificationSettingsProvider);
      if (!notifSettings.postWorkoutSupplementEnabled) return;

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
    final notifSettings = ref.read(notificationSettingsProvider);
    if (shouldClearOngoingWorkoutSurface(sessionAsync) ||
        !notifSettings.activeWorkoutBannerEnabled) {
      _stopPendingWorkoutActionDrain();
      WorkoutNotificationService.instance.cancel();
      // The bubble has its own setting and must not inherit the banner's;
      // on the live path below `_syncWorkoutNotificationFor` reconciles it
      // with the snapshot it already built.
      unawaited(_syncBubble());
      return;
    }
    if (session == null) {
      return;
    }
    _startPendingWorkoutActionDrain();
    unawaited(_syncWorkoutNotificationFor(session));
  }

  /// The display model shared by every ongoing-workout surface — the tray
  /// notification and the Workout Bubble's popup both render exactly this, so
  /// they can never disagree about which set the user is on.
  Future<OngoingWorkoutSurfaceSnapshot> _surfaceSnapshotFor(
    WorkoutSessionData session,
  ) async {
    final repo = ref.read(workoutsRepositoryProvider);
    final target = await repo.activeNotificationTargetForSession(session.id);
    final weightFormat = ref.read(weightFormatProvider);
    return buildOngoingWorkoutSurfaceSnapshot(
      target: target,
      formatWeight: weightFormat.format,
      loadStepKg: ref.read(quickLoadStepProvider),
    );
  }

  Future<void> _syncWorkoutNotificationFor(WorkoutSessionData session) async {
    final snapshot = await _surfaceSnapshotFor(session);
    if (!mounted) return;
    final activeSession = ref.read(activeSessionProvider).asData?.value;
    if (activeSession?.id != session.id) return;

    // Reuses the snapshot rather than letting the bubble query for its own.
    unawaited(_syncBubble(snapshot: snapshot));
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

  Future<bool> _applyWorkoutBubbleAction(
    String actionId, {
    int? sessionId,
    int? targetSetId,
    String? value,
  }) async {
    final session = ref.read(activeSessionProvider).asData?.value;
    if (session == null) return false;
    if (sessionId != null && sessionId != session.id) return true;

    final repo = ref.read(workoutsRepositoryProvider);
    final target = await repo.activeNotificationTargetForSession(session.id);
    if (target == null) return false;
    final targetSet = target.set;

    if (actionId == 'edit_weight' && value != null) {
      final weightFormat = ref.read(weightFormatProvider);
      final parsed = double.tryParse(value.replaceAll(',', '.'));
      if (parsed != null && parsed >= 0) {
        final kg = weightFormat.toKg(parsed);
        await repo.updateSet(setId: targetSet.id, weightKg: kg);
        await _syncWorkoutNotificationFor(session);
        return true;
      }
    } else if (actionId == 'edit_reps' && value != null) {
      final parsed = int.tryParse(value);
      if (parsed != null && parsed >= 0) {
        await repo.updateSet(setId: targetSet.id, reps: parsed);
        await _syncWorkoutNotificationFor(session);
        return true;
      }
    } else if (actionId == 'edit_rpe' && value != null) {
      final parsed = double.tryParse(value.replaceAll(',', '.'));
      if (parsed != null && parsed >= 0) {
        final rpeX10 = (parsed * 10).round();
        await repo.updateSet(setId: targetSet.id, rpeX10: rpeX10);
        await _syncWorkoutNotificationFor(session);
        return true;
      }
    } else if (actionId == 'complete_set') {
      final newCompleted = !targetSet.isCompleted;
      await repo.updateSet(setId: targetSet.id, isCompleted: newCompleted);
      await _syncWorkoutNotificationFor(session);
      return true;
    }

    return _applyWorkoutNotificationAction(
      actionId,
      sessionId: sessionId,
      targetSetId: targetSetId,
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

  /// Starts the fast a schedule reminds about, when it's set to autoStart —
  /// skipping if a fast is already running rather than ending it out from
  /// under the user. Shared by both the live tap handler and the
  /// background-tap drain below, since a background tap has no UI to
  /// navigate from anyway.
  Future<void> _startFastFromScheduleIfNeeded(int scheduleId) async {
    final repo = ref.read(fastingRepositoryProvider);
    final schedule = await repo.schedule(scheduleId);
    if (schedule == null || !schedule.autoStart) return;
    final active = await repo.activeSession();
    if (active != null) return;
    final targetSeconds = resolveScheduleTargetSeconds(
      schedule.planName,
      schedule.customTargetSeconds,
    );
    await repo.startSession(targetSeconds);

    final notifEnabled = ref
        .read(notificationSettingsProvider)
        .fastingGoalReachedEnabled;
    final plan = resolveSchedulePlan(schedule.planName);
    final planLabel = plan == FastingPlan.custom
        ? '${targetSeconds ~/ 3600}h'
        : plan.nameString;
    await ref
        .read(fastingNotificationSchedulerProvider)
        .scheduleFastingGoal(
          DateTime.now().add(Duration(seconds: targetSeconds)),
          planName: planLabel,
          enabled: notifEnabled,
        );
  }

  Future<void> _checkAndAutoStartFastingSchedules() async {
    try {
      final repo = ref.read(fastingRepositoryProvider);
      final scheduler = ref.read(fastingScheduleServiceProvider);
      final notifScheduler = ref.read(fastingNotificationSchedulerProvider);
      final notifEnabled = ref
          .read(notificationSettingsProvider)
          .fastingGoalReachedEnabled;
      await scheduler.checkAndAutoStartSchedules(
        repository: repo,
        notificationScheduler: notifScheduler,
        goalNotificationEnabled: notifEnabled,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Fasting auto-start check error: $e');
      }
    }
  }

  void _startFastingScheduleCheck() {
    if (_fastingScheduleCheckTimer?.isActive ?? false) return;
    _fastingScheduleCheckTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_checkAndAutoStartFastingSchedules()),
    );
  }

  void _stopFastingScheduleCheck() {
    _fastingScheduleCheckTimer?.cancel();
    _fastingScheduleCheckTimer = null;
  }

  Future<void> _handleFastingScheduleTap(int scheduleId) async {
    await _startFastFromScheduleIfNeeded(scheduleId);
    if (!mounted) return;
    final router = ref.read(routerProvider);
    router.go(AppRoutes.app);
    router.push(AppRoutes.fasting);
  }

  Future<void> _drainPendingFastingScheduleActions() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final ids = PendingFastingScheduleActionQueue.read(prefs);
    if (ids.isEmpty) return;
    await PendingFastingScheduleActionQueue.replace(prefs, const []);
    for (final id in ids) {
      await _startFastFromScheduleIfNeeded(id);
    }
  }

  Future<void> _rehydrateFastingSchedules() async {
    final repo = ref.read(fastingRepositoryProvider);
    final scheduler = ref.read(fastingScheduleServiceProvider);
    final schedules = await repo.watchSchedules().first;
    await scheduler.rescheduleAll(schedules);
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
    // Adaptive TDEE: recalibrates on app open, on resume and on ActivityLevel change
    ref.watch(tdeeRecalibrationControllerProvider);
    ref.watch(widgetCnsSyncControllerProvider);
    ref.watch(widgetRecoverySyncControllerProvider);
    ref.watch(widgetTrainingSyncControllerProvider);

    // Starts/stops Phase 10 cloud sync off the auth session — see
    // syncServiceProvider in app/providers.dart.
    ref.watch(syncServiceProvider);

    // Initialize local notification syncing across meals, supplements, fasting, daily log.
    ref.watch(notificationSyncServiceProvider);

    final router = ref.watch(routerProvider);
    WorkoutNotificationService.onNotificationTap = () {
      ref.read(mainTabIndexProvider.notifier).state = 2;
      router.go(AppRoutes.app);
    };
    WorkoutNotificationService.onFastingScheduleTap = _handleFastingScheduleTap;

    // Keep notification in sync when active session changes.
    ref.listen(activeSessionProvider, (previous, next) {
      _syncNotification();
      // A workout can also start or end while the app is backgrounded — most
      // often from the watch — so the bubble follows the session too, not just
      // the lifecycle transitions.
      unawaited(_syncBubble());
      // Fire post-workout supplement reminder when session transitions active→null.
      final hadSession = previous?.asData?.value != null;
      final hasSession = next.asData?.value != null;
      if (hadSession && !hasSession) {
        _firePostWorkoutSupplementReminder();
      }
    });

    ref.listen(unitsProvider, (_, _) => _syncNotification());
    ref.listen(quickLoadStepProvider, (_, _) => _syncNotification());
    ref.listen(notificationSettingsProvider, (_, _) => _syncNotification());
    ref.listen(
      workoutBubbleEnabledProvider,
      (_, _) => unawaited(_syncBubble()),
    );

    final activeSession = ref.watch(activeSessionProvider).asData?.value;
    if (activeSession != null) {
      ref.listen(activeWorkoutNotificationTargetProvider(activeSession.id), (
        _,
        next,
      ) {
        if (next.hasValue) {
          _syncNotification();
        }
      });
    }

    final themeMode = ref.watch(themeModeProvider);
    final colorTheme = ref.watch(appColorThemeProvider);

    final platformBrightness = MediaQuery.platformBrightnessOf(context);
    final effectiveBrightness = switch (themeMode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => platformBrightness,
    };

    AppColors.brightness = effectiveBrightness;
    AppColors.colorTheme = colorTheme;

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
        '${themeMode.name}_${effectiveBrightness.name}_${colorTheme.name}',
      ), // Rebuild widget tree when theme changes
      title: 'Herculex',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.buildTheme(Brightness.light, colorTheme),
      darkTheme: AppTheme.buildTheme(Brightness.dark, colorTheme),
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(gradient: AppColors.backgroundGradient),
          child: InAppNotificationHost(
            child: HxToastHost(child: child ?? const SizedBox.shrink()),
          ),
        );
      },
    );
  }
}
