import 'package:shared_preferences/shared_preferences.dart';

import '../domain/dashboard_config.dart';

/// Persists the editable dashboard layout (V2 §18) in SharedPreferences as a
/// single compact string under [_key].
class DashboardConfigRepository {
  static const _key = 'dashboard_config_v1';
  static const _shapeKey = 'dashboard_card_shape_v1';
  final SharedPreferences _prefs;

  DashboardConfigRepository(this._prefs);

  DashboardConfig load() => DashboardConfig.decode(_prefs.getString(_key));

  Future<void> save(DashboardConfig config) async {
    await _prefs.setString(_key, config.encode());
  }

  DashboardCardShape loadShape() =>
      DashboardCardShape.fromId(_prefs.getString(_shapeKey));

  Future<void> saveShape(DashboardCardShape shape) async {
    await _prefs.setString(_shapeKey, shape.id);
  }
}
