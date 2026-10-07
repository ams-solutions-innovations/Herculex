import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:herculex/app/providers.dart';
import 'package:herculex/features/notifications/application/notification_settings_provider.dart';
import 'package:herculex/features/nutrition/application/nutrition_providers.dart';
import 'package:herculex/features/workouts/application/rest_timer_controller.dart';
import 'package:herculex/features/workouts/application/workouts_providers.dart';
import 'package:herculex/services/platform/workout_notification_service.dart';

/// Mirrors the phone's rest timer onto the watch and decides which device
/// announces the end of the rest.
///
/// The watch shows the countdown under the set number. When the user wants a
/// "rest over" alert and a watch that is following this workout received the
/// timer, the watch buzzes "IT'S GO TIME" and the phone withdraws its own
/// notification — one short tap on the wrist instead of two devices going
/// off. With no watch in reach the phone notification stays as it was.
///
/// Watched once from the app root.
final restTimerWearBridgeProvider = Provider<void>((ref) {
  int? lastSentEndsAtMs;
  ref.listen<RestTimerState>(restTimerProvider, (previous, next) {
    final endsAtMs = next.endsAt?.millisecondsSinceEpoch;
    if (endsAtMs == lastSentEndsAtMs) return; // the 1 Hz repaint nudge

    final now = ref.read(clockProvider).now();
    final ranOut =
        endsAtMs == null &&
        previous?.endsAt != null &&
        !previous!.endsAt!.isAfter(now.add(const Duration(seconds: 1)));
    lastSentEndsAtMs = endsAtMs;
    // A rest that simply ran out needs no message: the watch is already at
    // zero and buzzing. Sending "cancel" here would race that buzz.
    if (ranOut) return;

    final alert = ref.read(notificationSettingsProvider).restTimerAlertsEnabled;
    final wear = ref.read(wearSyncServiceProvider);
    final watchFollowsWorkout = ref
        .read(wearWorkoutSyncServiceProvider)
        .hasActiveSyncedSession;
    final payload = jsonEncode({
      'endsAtEpochMs': endsAtMs ?? 0,
      'totalSeconds': next.targetSeconds,
      'label': next.exerciseName ?? '',
      'showOnWatch': true,
      'alert': alert,
    });

    wear.syncRestTimer(payload).then((delivered) {
      if (delivered && watchFollowsWorkout && alert && endsAtMs != null) {
        WorkoutNotificationService.instance.cancelRestTimer();
      }
    });
  });
});
