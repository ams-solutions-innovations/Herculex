import 'dart:async';

import 'package:herculex/features/notifications/domain/notification_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationSettingsRepository {
  static const _prefsKey = 'app_notification_settings_v1';
  final SharedPreferences _prefs;
  final _controller = StreamController<NotificationSettings>.broadcast();

  NotificationSettingsRepository(this._prefs);

  void dispose() {
    _controller.close();
  }

  NotificationSettings load() {
    final raw = _prefs.getString(_prefsKey);
    return NotificationSettings.fromRawJson(raw);
  }

  Stream<NotificationSettings> watch() {
    Future.microtask(() => _controller.add(load()));
    return _controller.stream;
  }

  Future<void> save(NotificationSettings settings) async {
    await _prefs.setString(_prefsKey, settings.toRawJson());
    _controller.add(settings);
  }
}
