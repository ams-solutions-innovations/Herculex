import 'package:shared_preferences/shared_preferences.dart';

/// Persists a weekly-report notification tap that arrived while the app
/// wasn't running. The background notification-response isolate
/// (`workoutNotificationTapBackground`) has no Flutter engine, so it can only
/// set this flag; the app drains it at start and on resume and then opens the
/// report. The target week is deliberately not stored: it is resolved at drain
/// time by `IsoWeek.forNotificationTap`.
class PendingWeeklyReportOpenQueue {
  static const prefsKey = 'pending_weekly_report_open';

  const PendingWeeklyReportOpenQueue._();

  static bool isPending(SharedPreferences prefs) =>
      prefs.getBool(prefsKey) ?? false;

  static Future<void> enqueue(SharedPreferences prefs) =>
      prefs.setBool(prefsKey, true);

  /// Clears the flag and returns whether it was set.
  static Future<bool> take(SharedPreferences prefs) async {
    if (!isPending(prefs)) return false;
    await prefs.remove(prefsKey);
    return true;
  }
}
