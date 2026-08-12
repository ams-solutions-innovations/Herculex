import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/auth_session.dart';

/// Offline cache of the signed-in user's profile.
///
/// This is *not* an auth provider and holds no credentials. The bearer tokens
/// live in `SecureAuthStorage`, owned by the Supabase client — keeping a second
/// copy here would mean two sources of truth for the same secret. What this
/// stores is the non-sensitive session shape (`uid`, display name, avatar) so a
/// cold start with no network can render the signed-in shell immediately,
/// before Supabase finishes refreshing.
class LocalAuthRepository {
  static const _kAuthKey = 'herculex.auth_session';

  /// Orphaned Firebase ID token from before the Supabase cutover. Deleted once
  /// on first run; remove this constant and [_purgeLegacyToken] after a
  /// release or two.
  static const _kLegacyIdTokenKey = 'herculex.auth_id_token';

  LocalAuthRepository(this._prefs, {FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage() {
    _controller.onListen = () {
      scheduleMicrotask(() {
        if (!_controller.isClosed) {
          _controller.add(currentSession);
        }
      });
    };
    unawaited(_purgeLegacyToken());
  }

  Future<void> _purgeLegacyToken() async {
    try {
      await _secureStorage.delete(key: _kLegacyIdTokenKey);
    } catch (_) {
      // Secure storage unavailable (e.g. tests, or a device with a broken
      // keystore). The stale token is inert either way.
    }
  }

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secureStorage;
  final _controller = StreamController<AuthSession?>.broadcast();

  AuthSession? get currentSession {
    final raw = _prefs.getString(_kAuthKey);
    if (raw == null) return null;
    try {
      return AuthSession.decode(raw);
    } catch (_) {
      return null;
    }
  }

  Stream<AuthSession?> watch() => _controller.stream;

  /// Persists the session shape only. [AuthSession.toJson] deliberately omits
  /// `idToken`, so no credential reaches SharedPreferences.
  Future<void> save(AuthSession session) async {
    await _prefs.setString(_kAuthKey, session.encode());
    _controller.add(session);
  }

  Future<void> clear() async {
    await _prefs.remove(_kAuthKey);
    _controller.add(null);
  }

  void dispose() => _controller.close();
}
