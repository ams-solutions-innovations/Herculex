import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

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

  static const _channelId = 'workout_live';
  static const _notifId = 1;
  static const _restNotifId = 2;
  static const _supplementNotifId = 3;
  static const _supplementChannelId = 'supplement_reminders';

  final _plugin = FlutterLocalNotificationsPlugin();
  Timer? _ticker;

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
        onDidReceiveNotificationResponse: (details) {
          onNotificationTap?.call();
        },
      );

      // Request permission on Android 13+.
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
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
        debugPrint('WorkoutNotificationService: notification call skipped ($e)');
      }
    }
  }

  /// Start ticking a live notification that updates the elapsed time every
  /// second. Safe to call multiple times — restarts the ticker if already running.
  void showOrUpdate({
    required DateTime startedAt,
    required String exerciseName,
    String? workoutName,
    int? currentSet,
    int? totalSets,
    double? weightKg,
    int? reps,
  }) {
    _ticker?.cancel();
    _post(
      startedAt: startedAt,
      exerciseName: exerciseName,
      workoutName: workoutName,
      currentSet: currentSet,
      totalSets: totalSets,
      weightKg: weightKg,
      reps: reps,
    );
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      _post(
        startedAt: startedAt,
        exerciseName: exerciseName,
        workoutName: workoutName,
        currentSet: currentSet,
        totalSets: totalSets,
        weightKg: weightKg,
        reps: reps,
      );
    });
  }

  Future<void> _post({
    required DateTime startedAt,
    required String exerciseName,
    String? workoutName,
    int? currentSet,
    int? totalSets,
    double? weightKg,
    int? reps,
  }) async {
    final elapsed = _fmt(DateTime.now().difference(startedAt));
    final title = (workoutName != null && workoutName.isNotEmpty)
        ? '$workoutName • $elapsed'
        : 'Workout  $elapsed';

    final StringBuffer bodyBuf = StringBuffer(exerciseName);
    if (currentSet != null) {
      bodyBuf.write(' • Serija $currentSet');
      if (totalSets != null && totalSets > 0) {
        bodyBuf.write('/$totalSets');
      }
    }
    if (weightKg != null && reps != null) {
      final weightStr = weightKg.truncateToDouble() == weightKg
          ? weightKg.toStringAsFixed(0)
          : weightKg.toStringAsFixed(1);
      bodyBuf.write(' ($weightStr kg × $reps)');
    } else if (reps != null) {
      bodyBuf.write(' ($reps reps)');
    }

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      'Live Workout',
      channelDescription: 'Shows elapsed time during an active workout',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,           // cannot be dismissed by swipe
      onlyAlertOnce: true,     // no sound/vibration on updates
      showWhen: false,
      icon: '@mipmap/ic_launcher',
    );
    const iOSDetails = DarwinNotificationDetails(
      presentAlert: false,
      presentBadge: false,
      presentSound: false,
    );
    await _guard(() => _plugin.show(
          _notifId,
          title,
          bodyBuf.toString(),
          const NotificationDetails(android: androidDetails, iOS: iOSDetails),
        ));
  }

  Future<void> scheduleRestTimer(int seconds, String exerciseName) async {
    final scheduledDate = tz.TZDateTime.now(tz.local).add(Duration(seconds: seconds));
    await _guard(() => _plugin.zonedSchedule(
      _restNotifId,
      'Rest finished',
      exerciseName,
      scheduledDate,
      const NotificationDetails(
        android: AndroidNotificationDetails(_channelId, 'Rest Timer', importance: Importance.max, priority: Priority.max),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    ));
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
    await _guard(() => _plugin.show(
          _supplementNotifId,
          '💊 Post-workout supplements',
          body,
          const NotificationDetails(
            android: androidDetails,
            iOS: iOSDetails,
          ),
        ));
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
