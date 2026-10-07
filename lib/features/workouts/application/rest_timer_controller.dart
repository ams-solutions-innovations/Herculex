import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:herculex/app/providers.dart';
import 'package:herculex/features/notifications/application/notification_settings_provider.dart';
import 'package:herculex/services/platform/workout_notification_service.dart';

/// Whether the rest timer should auto-start after a completed set.
/// Persisted in SharedPreferences; toggled from [WorkoutSettingsSheet].
class RestTimerEnabledNotifier extends Notifier<bool> {
  static const prefsKey = 'rest_timer_enabled';

  @override
  bool build() =>
      ref.watch(sharedPreferencesProvider).getBool(prefsKey) ?? true;

  Future<void> set(bool enabled) async {
    await ref.read(sharedPreferencesProvider).setBool(prefsKey, enabled);
    state = enabled;
  }
}

final restTimerEnabledProvider =
    NotifierProvider<RestTimerEnabledNotifier, bool>(
      RestTimerEnabledNotifier.new,
    );

class RestTimerState {
  final DateTime? endsAt;
  final int targetSeconds;
  final String? exerciseName;

  const RestTimerState({
    this.endsAt,
    this.targetSeconds = 0,
    this.exerciseName,
  });

  bool get isRunning => endsAt != null;

  int remainingSecondsFrom(DateTime now) {
    if (endsAt == null) return 0;
    final diff = endsAt!.difference(now).inSeconds;
    return diff > 0 ? diff : 0;
  }

  double progressFrom(DateTime now) {
    if (endsAt == null || targetSeconds == 0) return 0;
    final remaining = remainingSecondsFrom(now);
    return 1 - (remaining / targetSeconds);
  }

  static const idle = RestTimerState();
}

class RestTimerController extends Notifier<RestTimerState> {
  Timer? _ticker;

  @override
  RestTimerState build() {
    ref.onDispose(() {
      _ticker?.cancel();
      WorkoutNotificationService.instance.cancelRestTimer();
    });
    return RestTimerState.idle;
  }

  /// Starts (or restarts) the rest countdown.
  ///
  /// [seconds] is what is left to rest. [totalSeconds] is the full period it
  /// belongs to, when the rest began earlier than now — a set completed on
  /// the watch reaches the phone a moment late, and the progress bar should
  /// reflect the whole rest rather than restart from empty.
  void start({required int seconds, String? exerciseName, int? totalSeconds}) {
    if (!ref.read(restTimerEnabledProvider)) return;
    _ticker?.cancel();
    final clock = ref.read(clockProvider);
    state = RestTimerState(
      endsAt: clock.now().add(Duration(seconds: seconds)),
      targetSeconds: totalSeconds != null && totalSeconds > seconds
          ? totalSeconds
          : seconds,
      exerciseName: exerciseName,
    );

    if (seconds > 0) {
      final notifEnabled = ref
          .read(notificationSettingsProvider)
          .restTimerAlertsEnabled;
      WorkoutNotificationService.instance.scheduleRestTimer(
        seconds,
        exerciseName ?? 'Time for your next set!',
        enabled: notifEnabled,
      );
    }

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final remaining = state.remainingSecondsFrom(clock.now());
      if (remaining <= 0) {
        _expire();
      } else {
        // Trigger rebuild by nudging state (cheaply).
        state = RestTimerState(
          endsAt: state.endsAt,
          targetSeconds: state.targetSeconds,
          exerciseName: state.exerciseName,
        );
      }
    });
  }

  void addSeconds(int delta) {
    if (!state.isRunning) return;
    state = RestTimerState(
      endsAt: state.endsAt!.add(Duration(seconds: delta)),
      targetSeconds: state.targetSeconds + delta,
      exerciseName: state.exerciseName,
    );

    // Reschedule the notification with the new remaining time.
    final clock = ref.read(clockProvider);
    final remaining = state.remainingSecondsFrom(clock.now());
    if (remaining > 0) {
      final notifEnabled = ref
          .read(notificationSettingsProvider)
          .restTimerAlertsEnabled;
      WorkoutNotificationService.instance.scheduleRestTimer(
        remaining,
        state.exerciseName ?? 'Time for your next set!',
        enabled: notifEnabled,
      );
    }
  }

  /// The user skipped the rest: stop counting and withdraw the scheduled
  /// "rest finished" alert, which would otherwise still fire.
  void cancel() {
    _ticker?.cancel();
    _ticker = null;
    state = RestTimerState.idle;
    WorkoutNotificationService.instance.cancelRestTimer();
  }

  /// The rest ran out on its own. Unlike [cancel] this leaves the scheduled
  /// alert alone — the ticker and the alarm fire within the same second, and
  /// cancelling here used to swallow the very notification that was due.
  void _expire() {
    _ticker?.cancel();
    _ticker = null;
    state = RestTimerState.idle;
  }
}

final restTimerProvider = NotifierProvider<RestTimerController, RestTimerState>(
  RestTimerController.new,
);
