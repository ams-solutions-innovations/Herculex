import 'package:shared_preferences/shared_preferences.dart';

/// Persists fasting-schedule notification taps that arrived while the app
/// wasn't running to react to them — the background notification-response
/// isolate (`workoutNotificationTapBackground` in
/// `workout_notification_service.dart`) has no Flutter engine to read
/// providers or write to Drift, so it can only queue the schedule id here.
/// Drained on the next app launch, mirroring
/// `PendingWorkoutNotificationActionQueue`.
class PendingFastingScheduleActionQueue {
  static const prefsKey = 'pending_fasting_schedule_actions';

  const PendingFastingScheduleActionQueue._();

  static List<int> read(SharedPreferences prefs) {
    final values = prefs.getStringList(prefsKey) ?? const <String>[];
    return values.map(int.tryParse).whereType<int>().toList();
  }

  static Future<void> enqueue(SharedPreferences prefs, int scheduleId) async {
    final ids = {...read(prefs), scheduleId}.toList();
    await _write(prefs, ids);
  }

  static Future<void> replace(SharedPreferences prefs, List<int> ids) =>
      _write(prefs, ids);

  static Future<void> _write(SharedPreferences prefs, List<int> ids) async {
    if (ids.isEmpty) {
      await prefs.remove(prefsKey);
      return;
    }
    await prefs.setStringList(prefsKey, [for (final id in ids) '$id']);
  }
}
