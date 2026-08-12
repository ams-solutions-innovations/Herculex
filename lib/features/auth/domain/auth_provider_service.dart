import 'auth_session.dart';

/// The credential provider behind [AuthRepository].
///
/// Extracted when Firebase (a native Kotlin `MethodChannel` impl) was replaced
/// by Supabase so that:
///   * `AuthRepository` depends on a contract rather than a concrete backend,
///   * tests can supply a fake without a live `SupabaseClient`.
///
/// The method set is deliberately identical to what `AuthRepository` already
/// called on the old `NativeAuthService`, so no caller above the repository
/// changed. The one addition is [authStateChanges], which replaces the old
/// one-shot `hydrateFromNative()` pull — the previous design could not observe
/// token refresh, session expiry, or a sign-out triggered elsewhere.
abstract interface class AuthProviderService {
  /// The session restored from persistent storage at startup, if any.
  Future<AuthSession?> getCurrentUser();

  /// Emits on sign-in, sign-out, token refresh and session expiry.
  /// Null means "no authenticated user".
  Stream<AuthSession?> authStateChanges();

  Future<AuthSession> registerWithEmail({
    required String email,
    required String password,
    String? displayName,
  });

  Future<AuthSession> loginWithEmail({
    required String email,
    required String password,
  });

  Future<AuthSession> signInWithGoogle();

  Future<AuthSession> signInWithApple();

  Future<void> sendPasswordReset(String email);

  Future<void> signOut();
}
