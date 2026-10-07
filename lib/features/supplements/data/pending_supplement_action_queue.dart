import 'package:shared_preferences/shared_preferences.dart';

/// Persists supplement notification actions (like "Done") that were triggered
/// while the app was in the background or terminated, so that when the app
/// launches or resumes, Riverpod providers and stream controllers can be
/// refreshed immediately.
class PendingSupplementActionQueue {
  static const prefsKey = 'pending_supplement_notification_actions';

  const PendingSupplementActionQueue._();

  static List<String> read(SharedPreferences prefs) {
    return prefs.getStringList(prefsKey) ?? const <String>[];
  }

  static Future<void> enqueue(
    SharedPreferences prefs,
    String supplementId,
  ) async {
    final ids = {...read(prefs), supplementId}.toList();
    await _write(prefs, ids);
  }

  static Future<void> replace(SharedPreferences prefs, List<String> ids) =>
      _write(prefs, ids);

  static Future<void> _write(SharedPreferences prefs, List<String> ids) async {
    if (ids.isEmpty) {
      await prefs.remove(prefsKey);
      return;
    }
    await prefs.setStringList(prefsKey, ids);
  }
}
