import 'package:flutter/services.dart';

import '../domain/auth_session.dart';

class NativeAuthService {
  static const _channel = MethodChannel('com.ams.herculex/auth');
  static const firebaseWebClientId = String.fromEnvironment(
    'FIREBASE_WEB_CLIENT_ID',
    defaultValue: '',
  );

  Future<AuthSession?> getCurrentUser() async {
    final result = await _channel.invokeMethod<Object?>('getCurrentUser');
    if (result == null) return null;
    return AuthSession.fromMap(Map<Object?, Object?>.from(result as Map));
  }

  Future<AuthSession> registerWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final result = await _channel.invokeMethod<Object?>('registerWithEmail', {
      'email': email,
      'password': password,
      'displayName': displayName,
    });
    return AuthSession.fromMap(Map<Object?, Object?>.from(result as Map));
  }

  Future<AuthSession> loginWithEmail({
    required String email,
    required String password,
  }) async {
    final result = await _channel.invokeMethod<Object?>('loginWithEmail', {
      'email': email,
      'password': password,
    });
    return AuthSession.fromMap(Map<Object?, Object?>.from(result as Map));
  }

  Future<AuthSession> signInWithGoogle() async {
    if (firebaseWebClientId.isEmpty) {
      throw PlatformException(
        code: 'MISSING_GOOGLE_CLIENT_ID',
        message:
            'FIREBASE_WEB_CLIENT_ID is missing. Start the app with --dart-define=FIREBASE_WEB_CLIENT_ID=...',
      );
    }
    final result = await _channel.invokeMethod<Object?>('signInWithGoogle', {
      'serverClientId': firebaseWebClientId,
    });
    return AuthSession.fromMap(Map<Object?, Object?>.from(result as Map));
  }

  Future<AuthSession> signInWithApple() async {
    final result = await _channel.invokeMethod<Object?>('signInWithApple');
    return AuthSession.fromMap(Map<Object?, Object?>.from(result as Map));
  }

  Future<void> sendPasswordReset(String email) {
    return _channel.invokeMethod<void>('sendPasswordReset', {'email': email});
  }

  Future<void> signOut() {
    return _channel.invokeMethod<void>('signOut', {
      'serverClientId': firebaseWebClientId.isEmpty ? null : firebaseWebClientId,
    });
  }
}
