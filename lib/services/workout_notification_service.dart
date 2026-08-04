import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../features/workouts/data/workout_notification_action_queue.dart';
import '../features/workouts/domain/ongoing_workout_surface_snapshot.dart';
import '../features/workouts/domain/workout_notification_command.dart';
import 'ongoing_workout_surface_bridge.dart' show OngoingWorkoutSurfaceBridge;

@pragma('vm:entry-point')
Future<void> workoutNotificationTapBackground(
  NotificationResponse details,
) async {
  final actionId = details.actionId;
  if (actionId == null || actionId.isEmpty) return;

  DartPluginRegistrant.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final target = workoutNotificationActionTargetFromPayload(details.payload);
  await PendingWorkoutNotificationActionQueue.enqueue(
    prefs,
    actionId,
    sessionId: target.sessionId,
    setId: target.setId,
  );
}

/// Shows / updates / cancels a persistent "Workout in progress" notification
/// whenever the app is backgrounded during an active session.
///
/// Call [init] once at startup, [showOrUpdate] when the session is active and
/// the app goes to background, and [cancel] when the session ends or the app
/// returns to foreground.
class WorkoutNotificationService {
  WorkoutNotificationService._();
  static final WorkoutNotificationService instance =
      WorkoutNotificationService._();

  static VoidCallback? onNotificationTap;
  static Future<void> Function(String actionId, int? sessionId, int? setId)?
  onNotificationAction;

  static const actionRepsDown = WorkoutNotificationActionIds.repsDown;
  static const actionRepsUp = WorkoutNotificationActionIds.repsUp;
  static const actionWeightDown = WorkoutNotificationActionIds.weightDown;
  static const actionWeightUp = WorkoutNotificationActionIds.weightUp;
  static const actionCompleteSet = WorkoutNotificationActionIds.completeSet;

  static const _channelId = 'workout_live';
  static const _restChannelId = 'workout_rest';
  static const _notifId = 1;
  static const _restNotifId = 2;
  static const _supplementNotifId = 3;
  static const _supplementChannelId = 'supplement_reminders';
  static const _flagOngoingEvent = 0x00000002;

  final _plugin = FlutterLocalNotificationsPlugin();
  Timer? _ticker;

  /// Cached answer to "does the native renderer own notification [_notifId]?".
  /// True on Android 16+, where the native side posts a promotable Live Update on
  /// the same id — a second publisher would immediately overwrite it with a
  /// non-promotable notification. Cached because it cannot change at runtime and
  /// the ticker would otherwise hit the platform channel on every tick.
  bool? _nativeOwnsOngoingSurface;

  Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iOS = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _guard(() async {
      await _plugin.initialize(
        const InitializationSettings(android: android, iOS: iOS),
        onDidReceiveNotificationResponse: (details) async {
          final actionId = details.actionId;
          if (actionId != null && actionId.isNotEmpty) {
            final target = workoutNotificationActionTargetFromPayload(
              details.payload,
            );
            await onNotificationAction?.call(
              actionId,
              target.sessionId,
              target.setId,
            );
            return;
          }
          onNotificationTap?.call();
        },
        onDidReceiveBackgroundNotificationResponse:
            workoutNotificationTapBackground,
      );

      // Request permission on Android 13+.
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    });
  }

  /// Runs a notification-plugin call, swallowing platform-channel failures so a
  /// missing channel (tests) or a device that blocks notifications can never
  /// crash the app. Errors are logged in debug only.
  Future<void> _guard(Future<void> Function() body) async {
    try {
      await body();
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          'WorkoutNotificationService: notification call skipped ($e)',
        );
      }
    }
  }

  /// Start ticking a live notification that updates the elapsed time every
  /// second. Safe to call multiple times - restarts the ticker if already running.
  Future<void> showOrUpdate({
    required int sessionId,
    required DateTime startedAt,
    required String exerciseName,
    String? workoutName,
    int? currentSet,
    int? totalSets,
    String? weightLabel,
    String? loadStepLabel,
    List<OngoingWorkoutSurfaceAction>? actions,
    int? targetSetId,
    int? reps,
    Future<void> Function()? afterPost,
  }) async {
    _ticker?.cancel();
    final nativeOwnsSurface = await _nativeOwnsOngoingSurfaceNotification();
    if (!nativeOwnsSurface) {
      await _post(
        startedAt: startedAt,
        sessionId: sessionId,
        exerciseName: exerciseName,
        workoutName: workoutName,
        currentSet: currentSet,
        totalSets: totalSets,
        weightLabel: weightLabel,
        loadStepLabel: loadStepLabel,
        actions: actions,
        targetSetId: targetSetId,
        reps: reps,
      );
    }
    await afterPost?.call();
    // Elapsed time is drawn by the notification chronometer (`when` +
    // `usesChronometer`), so reposting at 1 Hz bought nothing and Android
    // rate-limits it anyway.
    _ticker = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!nativeOwnsSurface) {
        await _post(
          startedAt: startedAt,
          sessionId: sessionId,
          exerciseName: exerciseName,
          workoutName: workoutName,
          currentSet: currentSet,
          totalSets: totalSets,
          weightLabel: weightLabel,
          loadStepLabel: loadStepLabel,
          actions: actions,
          targetSetId: targetSetId,
          reps: reps,
        );
      }
      await afterPost?.call();
    });
  }

  /// Whether the native Live Update renderer is the sole publisher of
  /// [_notifId]. Below Android 16 (and on iOS, or when the platform channel is
  /// unavailable) this is false and the `flutter_local_notifications` path stays
  /// the only publisher.
  Future<bool> _nativeOwnsOngoingSurfaceNotification() async {
    final cached = _nativeOwnsOngoingSurface;
    if (cached != null) return cached;
    final capabilities = await OngoingWorkoutSurfaceBridge.instance
        .getCapabilities();
    return _nativeOwnsOngoingSurface = capabilities.android16Plus;
  }

  Future<void> _post({
    required DateTime startedAt,
    required int sessionId,
    required String exerciseName,
    String? workoutName,
    int? currentSet,
    int? totalSets,
    String? weightLabel,
    String? loadStepLabel,
    List<OngoingWorkoutSurfaceAction>? actions,
    int? targetSetId,
    int? reps,
  }) async {
    final elapsed = _fmt(DateTime.now().difference(startedAt));
    final title = (workoutName != null && workoutName.isNotEmpty)
        ? '$workoutName - $elapsed'
        : 'Workout $elapsed';

    final StringBuffer bodyBuf = StringBuffer(exerciseName);
    if (currentSet != null) {
      bodyBuf.write(' - Set $currentSet');
      if (totalSets != null && totalSets > 0) {
        bodyBuf.write('/$totalSets');
      }
    }
    if (weightLabel != null && reps != null) {
      bodyBuf.write(' ($weightLabel x $reps)');
    } else if (reps != null) {
      bodyBuf.write(' ($reps reps)');
    }

    final androidActions = _androidActionsFor(
      actions,
      loadStepLabel: loadStepLabel,
    );

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      'Live Workout',
      channelDescription: 'Shows elapsed time during an active workout',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true, // cannot be dismissed by swipe
      onlyAlertOnce: true, // no sound/vibration on updates
      showWhen: true,
      when: startedAt.millisecondsSinceEpoch,
      usesChronometer: true,
      chronometerCountDown: false,
      icon: '@mipmap/ic_launcher',
      category: AndroidNotificationCategory.workout,
      visibility: NotificationVisibility.private,
      additionalFlags: Int32List.fromList(<int>[_flagOngoingEvent]),
      actions: androidActions,
    );
    const iOSDetails = DarwinNotificationDetails(
      presentAlert: false,
      presentBadge: false,
      presentSound: false,
    );
    await _guard(
      () => _plugin.show(
        _notifId,
        title,
        bodyBuf.toString(),
        NotificationDetails(android: androidDetails, iOS: iOSDetails),
        payload: workoutNotificationActionTargetPayload(
          sessionId: sessionId,
          setId: targetSetId,
        ),
      ),
    );
  }

  List<AndroidNotificationAction> _androidActionsFor(
    List<OngoingWorkoutSurfaceAction>? actions, {
    String? loadStepLabel,
  }) {
    final source =
        actions ?? _fallbackSurfaceActions(loadStepLabel: loadStepLabel);
    return [
      for (final action in source)
        AndroidNotificationAction(
          action.id,
          action.label,
          showsUserInterface: false,
          cancelNotification: false,
        ),
    ];
  }

  List<OngoingWorkoutSurfaceAction> _fallbackSurfaceActions({
    String? loadStepLabel,
  }) {
    return buildOngoingWorkoutSurfaceActions(
      loadStepLabel: loadStepLabel ?? 'Load',
    );
  }

  Future<void> scheduleRestTimer(int seconds, String exerciseName) async {
    final scheduledDate = tz.TZDateTime.now(
      tz.local,
    ).add(Duration(seconds: seconds));
    await _guard(
      () => _plugin.zonedSchedule(
        _restNotifId,
        'Rest finished',
        exerciseName,
        scheduledDate,
        const NotificationDetails(
          // Its own channel on purpose: `workout_live` is created at
          // IMPORTANCE_LOW, and a channel's importance is fixed at creation, so
          // requesting Importance.max there was silently downgraded and the rest
          // alert never made a sound.
          android: AndroidNotificationDetails(
            _restChannelId,
            'Rest Timer',
            channelDescription: 'Alerts when a rest period finishes',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      ),
    );
  }

  /// Stop the ticker and dismiss the notification.
  Future<void> cancel() async {
    _ticker?.cancel();
    _ticker = null;
    await _guard(() => _plugin.cancel(_notifId));
    await cancelRestTimer();
  }

  Future<void> cancelRestTimer() async {
    await _guard(() => _plugin.cancel(_restNotifId));
  }

  /// Fires a one-shot notification reminding the user to take post-workout
  /// supplements. Safe to call from the workout session end handler.
  Future<void> showSupplementReminder(List<String> supplementNames) async {
    if (supplementNames.isEmpty) return;
    final body = supplementNames.length == 1
        ? supplementNames.first
        : supplementNames.join(', ');
    const androidDetails = AndroidNotificationDetails(
      _supplementChannelId,
      'Supplement Reminders',
      channelDescription: 'Reminds you to take post-workout supplements',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );
    const iOSDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: true,
    );
    await _guard(
      () => _plugin.show(
        _supplementNotifId,
        'Post-workout supplements',
        body,
        const NotificationDetails(android: androidDetails, iOS: iOSDetails),
      ),
    );
  }

  Future<void> cancelSupplementReminder() async {
    await _guard(() => _plugin.cancel(_supplementNotifId));
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

@visibleForTesting
String workoutNotificationActionTargetPayload({
  required int sessionId,
  int? setId,
}) {
  return jsonEncode(<String, Object?>{'sessionId': sessionId, 'setId': setId});
}

@visibleForTesting
WorkoutNotificationActionTarget workoutNotificationActionTargetFromPayload(
  String? payload,
) {
  if (payload == null || payload.isEmpty) {
    return const WorkoutNotificationActionTarget();
  }
  try {
    final decoded = jsonDecode(payload);
    if (decoded is Map<String, Object?>) {
      return WorkoutNotificationActionTarget(
        sessionId: decoded['sessionId'] as int?,
        setId: decoded['setId'] as int?,
      );
    }
  } catch (_) {
    return const WorkoutNotificationActionTarget();
  }
  return const WorkoutNotificationActionTarget();
}

class WorkoutNotificationActionTarget {
  final int? sessionId;
  final int? setId;

  const WorkoutNotificationActionTarget({this.sessionId, this.setId});
}
