import 'dart:async';

import 'package:herculex/features/auth/domain/auth_provider_service.dart';
import 'package:herculex/features/auth/domain/auth_session.dart';

/// In-memory stand-in for [SupabaseAuthService]. The whole point of extracting
/// [AuthProviderService] was to make this possible without a live
/// `SupabaseClient`.
class FakeAuthProviderService implements AuthProviderService {
  FakeAuthProviderService({this.throwOnSignIn});

  final Object? throwOnSignIn;
  final _controller = StreamController<AuthSession?>.broadcast();
  AuthSession? current;
  int signOutCalls = 0;
  int deleteAccountCalls = 0;
  String? passwordResetEmail;

  /// Set to make [deleteAccount] fail the way a refused or unreachable
  /// backend would — the case that must leave local data alone.
  Object? throwOnDeleteAccount;

  @override
  Future<AuthSession?> getCurrentUser() async => current;

  @override
  Stream<AuthSession?> authStateChanges() => _controller.stream;

  /// Simulates Supabase pushing a state change we did not initiate:
  /// token refresh, expiry, or a sign-out from another surface.
  void emit(AuthSession? session) {
    current = session;
    _controller.add(session);
  }

  AuthSession _make(String uid, AuthProvider provider) => AuthSession(
    uid: uid,
    email: '$uid@herculex.app',
    displayName: 'Athlete',
    provider: provider,
    idToken: 'token-$uid',
    isEmailVerified: true,
  );

  @override
  Future<AuthSession> registerWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async => current = _make('reg', AuthProvider.emailPassword);

  @override
  Future<AuthSession> loginWithEmail({
    required String email,
    required String password,
  }) async {
    if (throwOnSignIn != null) throw throwOnSignIn!;
    return current = _make('login', AuthProvider.emailPassword);
  }

  @override
  Future<AuthSession> signInWithGoogle() async {
    if (throwOnSignIn != null) throw throwOnSignIn!;
    return current = _make('google', AuthProvider.google);
  }

  @override
  Future<AuthSession> signInWithApple() async =>
      current = _make('apple', AuthProvider.apple);

  @override
  Future<void> sendPasswordReset(String email) async =>
      passwordResetEmail = email;

  @override
  Future<void> signOut() async {
    signOutCalls++;
    current = null;
  }

  @override
  Future<void> deleteAccount() async {
    if (throwOnDeleteAccount != null) throw throwOnDeleteAccount!;
    deleteAccountCalls++;
    current = null;
  }

  Future<void> dispose() => _controller.close();
}
