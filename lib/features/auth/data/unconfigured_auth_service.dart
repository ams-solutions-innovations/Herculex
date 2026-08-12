import '../domain/auth_provider_service.dart';
import '../domain/auth_session.dart';

/// Stands in for [SupabaseAuthService] when the app was built without
/// `SUPABASE_URL` / `SUPABASE_ANON_KEY`.
///
/// Herculex is local-first: training, nutrition and recovery all work with no
/// backend at all, so a credential-less build must stay fully usable rather
/// than crash on `Supabase.instance`. This reports "nobody is signed in" and
/// fails loudly only if someone actually attempts to authenticate.
///
/// Also what the widget tests run against.
class UnconfiguredAuthService implements AuthProviderService {
  const UnconfiguredAuthService();

  static const _message =
      'This build has no backend configured. Rebuild with '
      '--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...';

  @override
  Future<AuthSession?> getCurrentUser() async => null;

  @override
  Stream<AuthSession?> authStateChanges() => const Stream<AuthSession?>.empty();

  @override
  Future<AuthSession> registerWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async => throw UnsupportedError(_message);

  @override
  Future<AuthSession> loginWithEmail({
    required String email,
    required String password,
  }) async => throw UnsupportedError(_message);

  @override
  Future<AuthSession> signInWithGoogle() async =>
      throw UnsupportedError(_message);

  @override
  Future<AuthSession> signInWithApple() async =>
      throw UnsupportedError(_message);

  @override
  Future<void> sendPasswordReset(String email) async =>
      throw UnsupportedError(_message);

  /// Signing out of nothing is a no-op, not an error — `signOut()` runs on
  /// paths that must not throw (e.g. clearing local state).
  @override
  Future<void> signOut() async {}
}
