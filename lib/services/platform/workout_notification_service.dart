import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:herculex/features/fasting/data/fasting_schedule_action_queue.dart';
import 'package:herculex/features/fasting/domain/fasting_schedule_payload.dart';
import 'package:herculex/features/supplements/data/pending_supplement_action_queue.dart';
import 'package:herculex/features/supplements/data/supplement_notification_scheduler.dart';
import 'package:herculex/features/supplements/data/supplement_repository.dart';
import 'package:herculex/features/supplements/domain/supplement_notification_payload.dart';
import 'package:herculex/features/weekly_report/data/weekly_report_action_queue.dart';
import 'package:herculex/features/weekly_report/domain/weekly_report_notification_payload.dart';
import 'package:herculex/features/workouts/data/workout_notification_action_queue.dart';
import 'package:herculex/features/workouts/domain/ongoing_workout_surface_snapshot.dart';
import 'package:herculex/features/workouts/domain/workout_notification_command.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

@pragma('vm:entry-point')
Future<void> workoutNotificationTapBackground(
  NotificationResponse details,
) async {
  DartPluginRegistrant.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  // Weekly-report taps are payload-only too (no action buttons), so this must
  // precede the actionId guard. Queue a flag only: no generation here (RPT-03).
  if (await handleWeeklyReportBackgroundTap(details.payload, prefs)) return;

  // Fasting-schedule notifications are identified by payload, not actionId
  // (they have no action buttons — the default tap itself is "start now" or
  // "open to review", decided by FastingScheduleData.autoStart once the app
  // is running again) so this check must come before the actionId guard
  // below, which would otherwise just return on a bare tap.
  final scheduleId = fastingScheduleIdFromPayload(details.payload);
  if (scheduleId != null) {
    await PendingFastingScheduleActionQueue.enqueue(prefs, scheduleId);
    return;
  }

  // Supplement notifications handle action buttons (Done, Snooze) and background taps.
  if (await handleSupplementBackgroundTap(details, prefs)) return;

  final actionId = details.actionId;
  if (actionId == null || actionId.isEmpty) return;

  final target = workoutNotificationActionTargetFromPayload(details.payload);
  await PendingWorkoutNotificationActionQueue.enqueue(
    prefs,
    actionId,
    sessionId: target.sessionId,
    setId: target.setId,
  );
}

/// Background-isolate half of the weekly-report tap: queues an open flag and
/// reports whether [payload] was the weekly marker. Does no other work.
@visibleForTesting
Future<bool> handleWeeklyReportBackgroundTap(
  String? payload,
  SharedPreferences prefs,
) async {
  if (!isWeeklyReportPayload(payload)) return false;
  await PendingWeeklyReportOpenQueue.enqueue(prefs);
  return true;
}

/// Background-isolate handling for supplement notification actions (Done, Snooze).
@visibleForTesting
Future<bool> handleSupplementBackgroundTap(
  NotificationResponse details,
  SharedPreferences prefs,
) async {
  final supplementId = supplementIdFromPayload(details.payload);
  if (supplementId == null) return false;

  final actionId = details.actionId;
  if (actionId == SupplementNotificationActionIds.done) {
    await SupplementRepository.markTakenInPrefs(prefs, supplementId, true);
    await PendingSupplementActionQueue.enqueue(prefs, supplementId);
    try {
      tz.initializeTimeZones();
      final repo = SupplementRepository(prefs);
      final supplements = repo.loadSupplements();
      final taken = repo.loadTakenToday();
      final scheduler = SupplementNotificationScheduler(
        FlutterLocalNotificationsPlugin(),
      );
      await scheduler.reschedule(supplements, takenTodayIds: taken);
    } catch (_) {}
    return true;
  }

  if (actionId == SupplementNotificationActionIds.snooze30 ||
      actionId == SupplementNotificationActionIds.snooze60) {
    final minutes = actionId == SupplementNotificationActionIds.snooze30
        ? 30
        : 60;
    try {
      tz.initializeTimeZones();
      final repo = SupplementRepository(prefs);
      final supplements = repo.loadSupplements();
      final scheduler = SupplementNotificationScheduler(
        FlutterLocalNotificationsPlugin(),
      );
      await scheduler.snoozeById(
        supplementId,
        supplements,
        duration: Duration(minutes: minutes),
      );
    } catch (_) {}
    return true;
  }

  return false;
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

  /// Foreground tap on a fasting-schedule notification. Whether this starts
  /// the fast immediately or just opens the Fasting page for review is the
  /// receiving side's call (`FastingScheduleData.autoStart`) — this service
  /// only routes the tap, it has no fasting-domain knowledge beyond the id.
  static Future<void> Function(int scheduleId)? onFastingScheduleTap;

  /// Foreground tap on the Sunday weekly-report notification. Navigation only;
  /// the report is generated by the view's controller, never here (RPT-03).
  static Future<void> Function()? onWeeklyReportTap;

  /// Foreground action on a supplement notification (Done, Snooze).
  static Future<void> Function(String supplementId, String actionId)?
  onSupplementAction;

  /// Foreground tap on a supplement notification (opens tracker).
  static Future<void> Function(String supplementId)? onSupplementTap;

  /// Routes a weekly-report payload to [onWeeklyReportTap]. Returns true when
  /// the payload was the weekly marker, even if no callback is registered.
  @visibleForTesting
  static Future<bool> dispatchWeeklyReportPayload(String? payload) async {
    if (!isWeeklyReportPayload(payload)) return false;
    await onWeeklyReportTap?.call();
    return true;
  }

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

  Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    final iOS = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: [
        DarwinNotificationCategory(
          SupplementNotificationScheduler.categoryIdentifier,
          actions: [
            DarwinNotificationAction.plain(
              SupplementNotificationActionIds.done,
              'Done',
            ),
            DarwinNotificationAction.plain(
              SupplementNotificationActionIds.snooze30,
              '+30 min',
            ),
            DarwinNotificationAction.plain(
              SupplementNotificationActionIds.snooze60,
              '+1 hour',
            ),
          ],
        ),
      ],
    );
    await _guard(() async {
      await _plugin.initialize(
        InitializationSettings(android: android, iOS: iOS),
        onDidReceiveNotificationResponse: (details) async {
          // Payload-only taps: check before the actionId guard below.
          if (await dispatchWeeklyReportPayload(details.payload)) return;

          final scheduleId = fastingScheduleIdFromPayload(details.payload);
          if (scheduleId != null) {
            await onFastingScheduleTap?.call(scheduleId);
            return;
          }

          // Supplement notifications (action buttons or tap)
          final supplementId = supplementIdFromPayload(details.payload);
          if (supplementId != null) {
            final actionId = details.actionId;
            if (actionId != null && actionId.isNotEmpty) {
              await onSupplementAction?.call(supplementId, actionId);
              return;
            }
            await onSupplementTap?.call(supplementId);
            return;
          }

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

  int? _activeSessionId;
  DateTime? _activeStartedAt;
  String? _activeExerciseName;
  String? _activeWorkoutName;
  int? _activeCurrentSet;
  int? _activeTotalSets;
  String? _activeWeightLabel;
  String? _activeLoadStepLabel;
  List<OngoingWorkoutSurfaceAction>? _activeActions;
  int? _activeTargetSetId;
  int? _activeReps;
  String? _activeSetLabel;

  /// Start ticking a live notification that updates the elapsed time every
  /// 5 seconds. Safe to call multiple times - restarts the ticker if already running.
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
    String? setLabel,
  }) async {
    _ticker?.cancel();
    _activeSetLabel = setLabel;
    _activeSessionId = sessionId;
    _activeStartedAt = startedAt;
    _activeExerciseName = exerciseName;
    _activeWorkoutName = workoutName;
    _activeCurrentSet = currentSet;
    _activeTotalSets = totalSets;
    _activeWeightLabel = weightLabel;
    _activeLoadStepLabel = loadStepLabel;
    _activeActions = actions;
    _activeTargetSetId = targetSetId;
    _activeReps = reps;

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
      setLabel: setLabel,
    );

    // Elapsed time is drawn by the notification chronometer (`when` +
    // `usesChronometer`), so reposting at 1 Hz bought nothing and Android
    // rate-limits it anyway.
    _ticker = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (_activeStartedAt == null || _activeSessionId == null) return;
      await _post(
        startedAt: _activeStartedAt!,
        sessionId: _activeSessionId!,
        exerciseName: _activeExerciseName ?? '',
        workoutName: _activeWorkoutName,
        currentSet: _activeCurrentSet,
        totalSets: _activeTotalSets,
        weightLabel: _activeWeightLabel,
        loadStepLabel: _activeLoadStepLabel,
        actions: _activeActions,
        targetSetId: _activeTargetSetId,
        reps: _activeReps,
        setLabel: _activeSetLabel,
      );
    });
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
    String? setLabel,
  }) async {
    final title = exerciseName.isNotEmpty ? exerciseName : 'Workout';

    // Written into the body explicitly rather than relying solely on
    // Android's native chronometer widget: `usesChronometer` is Android-only
    // (iOS has no equivalent, so its notification showed no duration at
    // all) and its small system-drawn digit is easy to miss or misread as a
    // wall-clock time rather than an elapsed duration. Computed fresh on
    // every `_post` call — the 5s ticker keeps it current to within 5s,
    // matching `live_workout_banner.dart`'s `_formatElapsed`.
    final StringBuffer bodyBuf = StringBuffer(_formatElapsed(startedAt));
    if (setLabel != null && setLabel.isNotEmpty) {
      // Already worded by the snapshot ("Set 2/4", "Warmup W1").
      bodyBuf.write(' - ');
      bodyBuf.write(setLabel);
    } else if (currentSet != null) {
      bodyBuf.write(' - ');
      bodyBuf.write('Set $currentSet');
      if (totalSets != null && totalSets > 0) {
        bodyBuf.write('/$totalSets');
      }
    }
    if (weightLabel != null && reps != null) {
      if (bodyBuf.isNotEmpty) bodyBuf.write(' - ');
      bodyBuf.write('$weightLabel x $reps reps');
    } else if (reps != null) {
      if (bodyBuf.isNotEmpty) bodyBuf.write(' - ');
      bodyBuf.write('$reps reps');
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
      // No `when`/`usesChronometer`: the body text above is the single
      // source of truth for elapsed time. The system chronometer digit was
      // dropped because it's Android-only (iOS showed nothing) and, once
      // `showWhen` is on without it, Android instead renders `when` as a
      // static wall-clock timestamp that looks like a broken duration.
      showWhen: false,
      icon: '@mipmap/ic_launcher',
      largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
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

  /// "H:MM:SS" once the workout crosses an hour, else "MM:SS" — mirrors
  /// `live_workout_banner.dart`'s in-app timer so the two never disagree.
  String _formatElapsed(DateTime startedAt) {
    final d = DateTime.now().difference(startedAt);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
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

  Future<void> scheduleRestTimer(
    int seconds,
    String exerciseName, {
    bool enabled = true,
  }) async {
    if (!enabled) {
      await cancelRestTimer();
      return;
    }
    final scheduledDate = tz.TZDateTime.now(
      tz.local,
    ).add(Duration(seconds: seconds));
    await _guard(() async {
      try {
        await _plugin.zonedSchedule(
          _restNotifId,
          "IT'S GO TIME",
          exerciseName,
          scheduledDate,
          const NotificationDetails(
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
        );
      } catch (_) {
        await _plugin.zonedSchedule(
          _restNotifId,
          "IT'S GO TIME",
          exerciseName,
          scheduledDate,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              _restChannelId,
              'Rest Timer',
              channelDescription: 'Alerts when a rest period finishes',
              importance: Importance.high,
              priority: Priority.high,
            ),
            iOS: DarwinNotificationDetails(),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
    });
  }

  /// Stop the ticker and dismiss the notification.
  Future<void> cancel() async {
    _ticker?.cancel();
    _ticker = null;
    _activeSessionId = null;
    _activeStartedAt = null;
    _activeExerciseName = null;
    _activeWorkoutName = null;
    _activeCurrentSet = null;
    _activeTotalSets = null;
    _activeWeightLabel = null;
    _activeLoadStepLabel = null;
    _activeActions = null;
    _activeTargetSetId = null;
    _activeReps = null;
    _activeSetLabel = null;
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
