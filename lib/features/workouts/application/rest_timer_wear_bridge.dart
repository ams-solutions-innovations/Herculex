import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:herculex/app/providers.dart';
import 'package:herculex/features/notifications/application/notification_settings_provider.dart';
import 'package:herculex/features/nutrition/application/nutrition_providers.dart';
import 'package:herculex/features/nutrition/data/wear_sync_contract.dart';
import 'package:herculex/features/nutrition/data/wear_sync_service.dart';
import 'package:herculex/features/workouts/application/rest_timer_controller.dart';
import 'package:herculex/features/workouts/application/workouts_providers.dart';
import 'package:herculex/features/workouts/domain/rest_timer_ack.dart';
import 'package:herculex/services/platform/workout_notification_service.dart';

/// Mirrors the phone's rest timer onto the watch and decides which device
/// announces the end of the rest.
///
/// The watch shows the countdown under the set number. When the user wants a
/// "rest over" alert and a watch that is following this workout has *armed* it
/// — confirmed by an ack, not merely by the message having been sent — the
/// watch buzzes "IT'S GO TIME" and the phone withdraws its own notification:
/// one short tap on the wrist instead of two devices going off.
///
/// Until that ack arrives, and whenever it never does (no watch in reach, an
/// old watch build, no exact-alarm access, notifications off on the watch),
/// the phone's notification stays. The old rule withdrew it as soon as the
/// message was handed to the radio, so any silent failure on the watch left
/// the lifter with no alert on either device.
///
/// Watched once from the app root.
final restTimerWearBridgeProvider = Provider<void>((ref) {
  int? lastSentEndsAtMs;
  int? lastSentRev;
  var lastAlert = false;
  var lastWatchFollows = false;
  final revisions = WearRevisionAllocator(
    ref.watch(sharedPreferencesProvider),
    'rest_timer',
  );

  WearSyncService.onWatchRestTimerAck = (json) {
    final ack = RestTimerAck.tryParse(json);
    if (ack == null) return;
    final withdraw = shouldWithdrawPhoneRestAlert(
      ack: ack,
      sentRev: lastSentRev,
      sentEndsAtMs: lastSentEndsAtMs,
      alertEnabled: lastAlert,
      watchFollowsWorkout: lastWatchFollows,
      now: ref.read(clockProvider).now(),
    );
    if (withdraw) {
      WorkoutNotificationService.instance.cancelRestTimer();
    }
  };
  ref.onDispose(() => WearSyncService.onWatchRestTimerAck = null);

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
    final watchFollowsWorkout = ref
        .read(wearWorkoutSyncServiceProvider)
        .hasActiveSyncedSession;
    final rev = revisions.next();
    // Remember what was sent *before* sending: the ack can beat the await.
    lastSentRev = rev;
    lastAlert = alert;
    lastWatchFollows = watchFollowsWorkout;

    final payload = jsonEncode({
      'endsAtEpochMs': endsAtMs ?? 0,
      'totalSeconds': next.targetSeconds,
      'label': next.exerciseName ?? '',
      'showOnWatch': true,
      'alert': alert,
      // Orders the messages: a late start must not undo a later skip, and the
      // ack names the revision it answers.
      'rev': rev,
    });

    unawaited(ref.read(wearSyncServiceProvider).syncRestTimer(payload));
  });
});
