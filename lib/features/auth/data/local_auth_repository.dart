import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/auth_session.dart';

class LocalAuthRepository {
  static const _kAuthKey = 'herculex.auth_session';

  LocalAuthRepository(this._prefs) {
    _controller.onListen = () {
      scheduleMicrotask(() {
        if (!_controller.isClosed) {
          _controller.add(currentSession);
        }
      });
    };
  }

  final SharedPreferences _prefs;
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
