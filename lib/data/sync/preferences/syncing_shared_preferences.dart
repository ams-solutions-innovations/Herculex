import 'package:shared_preferences/shared_preferences.dart';

/// Called after a successful local write; [value] is null for a removal.
typedef PreferenceWriteListener = void Function(String key, Object? value);

/// The app's [SharedPreferences], with a hook on every write.
///
/// The profile, meal slots, goals and similar settings live in
/// SharedPreferences, which never left the device — so a second device (the
/// web app above all) started from onboarding with none of them. Installed
/// once in `main()`, this wrapper lets the synced-preferences bridge mirror
/// the keys it cares about into the synced `user_preferences` table without
/// touching any of the ~40 places that read and write preferences.
///
/// [clear] stays local on purpose: it is how sign-out and "clear all data"
/// wipe a device, and must never delete the account's settings in the cloud.
class SyncingSharedPreferences implements SharedPreferences {
  SyncingSharedPreferences(this._inner);

  final SharedPreferences _inner;

  /// Set by the bridge once sync is wired up; null until then.
  PreferenceWriteListener? onLocalWrite;

  Future<bool> _write(
    String key,
    Object? value,
    Future<bool> Function() write,
  ) async {
    final ok = await write();
    if (ok) onLocalWrite?.call(key, value);
    return ok;
  }

  /// Writes a value that came *from* the cloud straight to the store, without
  /// notifying [onLocalWrite] — otherwise every pulled setting would be
  /// echoed straight back up. Null removes the key.
  Future<void> applyRemote(String key, Object? value) async {
    switch (value) {
      case null:
        await _inner.remove(key);
      case bool():
        await _inner.setBool(key, value);
      case int():
        await _inner.setInt(key, value);
      case double():
        await _inner.setDouble(key, value);
      case String():
        await _inner.setString(key, value);
      case List<String>():
        await _inner.setStringList(key, value);
    }
  }

  @override
  Future<bool> setBool(String key, bool value) =>
      _write(key, value, () => _inner.setBool(key, value));

  @override
  Future<bool> setInt(String key, int value) =>
      _write(key, value, () => _inner.setInt(key, value));

  @override
  Future<bool> setDouble(String key, double value) =>
      _write(key, value, () => _inner.setDouble(key, value));

  @override
  Future<bool> setString(String key, String value) =>
      _write(key, value, () => _inner.setString(key, value));

  @override
  Future<bool> setStringList(String key, List<String> value) =>
      _write(key, value, () => _inner.setStringList(key, value));

  @override
  Future<bool> remove(String key) =>
      _write(key, null, () => _inner.remove(key));

  @override
  Future<bool> clear() => _inner.clear();

  @override
  Set<String> getKeys() => _inner.getKeys();

  @override
  Object? get(String key) => _inner.get(key);

  @override
  bool? getBool(String key) => _inner.getBool(key);

  @override
  int? getInt(String key) => _inner.getInt(key);

  @override
  double? getDouble(String key) => _inner.getDouble(key);

  @override
  String? getString(String key) => _inner.getString(key);

  @override
  List<String>? getStringList(String key) => _inner.getStringList(key);

  @override
  bool containsKey(String key) => _inner.containsKey(key);

  @override
  // ignore: deprecated_member_use
  Future<bool> commit() => _inner.commit();

  @override
  Future<void> reload() => _inner.reload();
}
