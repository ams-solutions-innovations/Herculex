import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';

import '../../../services/workout_notification_service.dart';

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

final restTimerEnabledProvider = NotifierProvider<RestTimerEnabledNotifier, bool>(
  RestTimerEnabledNotifier.new,
);

class RestTimerState {
  final DateTime? endsAt;
  final int targetSeconds;
  final String? exerciseName;

  const RestTimerState({this.endsAt, this.targetSeconds = 0, this.exerciseName});

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

  void start({required int seconds, String? exerciseName}) {
    if (!ref.read(restTimerEnabledProvider)) return;
    _ticker?.cancel();
    final clock = ref.read(clockProvider);
    state = RestTimerState(
      endsAt: clock.now().add(Duration(seconds: seconds)),
      targetSeconds: seconds,
      exerciseName: exerciseName,
    );
    
    if (seconds > 0) {
      WorkoutNotificationService.instance.scheduleRestTimer(
        seconds, 
        exerciseName ?? 'Time for your next set!',
      );
    }

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final remaining = state.remainingSecondsFrom(clock.now());
      if (remaining <= 0) {
        cancel();
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
      WorkoutNotificationService.instance.scheduleRestTimer(
        remaining, 
        state.exerciseName ?? 'Time for your next set!',
      );
    }
  }

  void cancel() {
    _ticker?.cancel();
    _ticker = null;
    state = RestTimerState.idle;
    WorkoutNotificationService.instance.cancelRestTimer();
  }
}

final restTimerProvider =
    NotifierProvider<RestTimerController, RestTimerState>(RestTimerController.new);
