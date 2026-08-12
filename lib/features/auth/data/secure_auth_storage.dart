import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Persists the Supabase session (which contains the refresh token — a bearer
/// credential) in platform secure storage: Keychain on iOS, Keystore-backed
/// EncryptedSharedPreferences on Android.
///
/// supabase_flutter's default [LocalStorage] writes to plain SharedPreferences.
/// That is the same mistake the 2026-08-10 audit flagged for the old Firebase
/// ID token, so we do not repeat it.
class SecureAuthStorage extends LocalStorage {
  SecureAuthStorage({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  static const _key = 'herculex.supabase_session';

  final FlutterSecureStorage _storage;

  @override
  Future<void> initialize() async {}

  @override
  Future<String?> accessToken() => _storage.read(key: _key);

  @override
  Future<bool> hasAccessToken() async =>
      await _storage.read(key: _key) != null;

  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(key: _key, value: persistSessionString);

  @override
  Future<void> removePersistedSession() => _storage.delete(key: _key);
}
