import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class PendingWorkoutNotificationActionQueue {
  static const prefsKey = 'pending_workout_notification_actions';

  const PendingWorkoutNotificationActionQueue._();

  static List<PendingWorkoutNotificationAction> read(SharedPreferences prefs) {
    final values = prefs.getStringList(prefsKey) ?? const <String>[];
    return values
        .map(PendingWorkoutNotificationAction.fromStorage)
        .whereType<PendingWorkoutNotificationAction>()
        .toList();
  }

  static Future<void> enqueue(
    SharedPreferences prefs,
    String actionId, {
    int? sessionId,
    int? setId,
  }) async {
    final actions = [
      ...read(prefs),
      PendingWorkoutNotificationAction(
        actionId: actionId,
        sessionId: sessionId,
        setId: setId,
      ),
    ];
    await _write(prefs, actions);
  }

  static PendingWorkoutNotificationActionDrain drainForSession(
    SharedPreferences prefs,
    int? sessionId,
  ) {
    final pending = read(prefs);
    final accepted = <PendingWorkoutNotificationAction>[];
    final remaining = <PendingWorkoutNotificationAction>[];
    var dropped = 0;

    for (final action in pending) {
      if (sessionId == null) {
        remaining.add(action);
      } else if (action.sessionId == sessionId) {
        accepted.add(action);
      } else if (action.sessionId == null) {
        dropped += 1;
      } else {
        dropped += 1;
      }
    }

    return PendingWorkoutNotificationActionDrain(
      actions: accepted,
      remaining: remaining,
      dropped: dropped,
    );
  }

  static Future<void> replace(
    SharedPreferences prefs,
    List<PendingWorkoutNotificationAction> actions,
  ) async {
    await _write(prefs, actions);
  }

  static Future<void> _write(
    SharedPreferences prefs,
    List<PendingWorkoutNotificationAction> actions,
  ) async {
    if (actions.isEmpty) {
      await prefs.remove(prefsKey);
      return;
    }
    await prefs.setStringList(prefsKey, [
      for (final action in actions) action.toStorage(),
    ]);
  }
}

class PendingWorkoutNotificationAction {
  final String actionId;
  final int? sessionId;
  final int? setId;

  const PendingWorkoutNotificationAction({
    required this.actionId,
    required this.sessionId,
    this.setId,
  });

  String toStorage() {
    return jsonEncode(<String, Object?>{
      'actionId': actionId,
      'sessionId': sessionId,
      'setId': setId,
    });
  }

  static PendingWorkoutNotificationAction? fromStorage(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, Object?>) {
        final actionId = decoded['actionId'] as String?;
        if (actionId == null || actionId.isEmpty) return null;
        return PendingWorkoutNotificationAction(
          actionId: actionId,
          sessionId: decoded['sessionId'] as int?,
          setId: decoded['setId'] as int?,
        );
      }
    } catch (_) {
      if (value.isEmpty) return null;
      return PendingWorkoutNotificationAction(actionId: value, sessionId: null);
    }
    return null;
  }
}

class PendingWorkoutNotificationActionDrain {
  final List<PendingWorkoutNotificationAction> actions;
  final List<PendingWorkoutNotificationAction> remaining;
  final int dropped;

  const PendingWorkoutNotificationActionDrain({
    required this.actions,
    required this.remaining,
    required this.dropped,
  });
}
