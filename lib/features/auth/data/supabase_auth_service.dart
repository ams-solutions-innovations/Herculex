import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
// `AuthProvider` below always means the app's own domain enum; Supabase names
// its equivalent `OAuthProvider`, so there is no collision.
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/env.dart';
import '../domain/auth_provider_service.dart';
import '../domain/auth_session.dart';

/// Supabase-backed credential provider. Replaces the native Kotlin
/// `FirebaseAuthRepository` reached over the `com.ams.herculex/auth`
/// `MethodChannel`.
///
/// Being pure Dart, this works on iOS — the Firebase bridge never did (there
/// was no `GoogleService-Info.plist`, no Podfile, and no native implementation,
/// so every call threw `MissingPluginException`).
class SupabaseAuthService implements AuthProviderService {
  SupabaseAuthService(this._client, {GoogleSignIn? googleSignIn})
    : _googleSignIn =
          googleSignIn ??
          GoogleSignIn(
            // Supabase verifies the ID token against the *web* client id even
            // on Android, so it goes in `serverClientId`, not `clientId`.
            serverClientId: Env.googleWebClientId.isEmpty
                ? null
                : Env.googleWebClientId,
            clientId: Env.googleIosClientId.isEmpty
                ? null
                : Env.googleIosClientId,
          );

  final SupabaseClient _client;
  final GoogleSignIn _googleSignIn;

  @override
  Future<AuthSession?> getCurrentUser() async {
    final session = _client.auth.currentSession;
    return session == null ? null : mapSession(session);
  }

  @override
  Stream<AuthSession?> authStateChanges() => _client.auth.onAuthStateChange.map(
    (event) => event.session == null ? null : mapSession(event.session!),
  );

  @override
  Future<AuthSession> registerWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final res = await _client.auth.signUp(
      email: email,
      password: password,
      data: displayName == null || displayName.trim().isEmpty
          ? null
          : {'full_name': displayName.trim()},
      emailRedirectTo: Env.authCallbackUrl,
    );
    return _require(res.session, res.user, 'registerWithEmail');
  }

  @override
  Future<AuthSession> loginWithEmail({
    required String email,
    required String password,
  }) async {
    final res = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    return _require(res.session, res.user, 'loginWithEmail');
  }

  @override
  Future<AuthSession> signInWithGoogle() async {
    if (!Env.hasGoogleSignIn) {
      throw const AuthException(
        'Google sign-in is not configured. Build with '
        '--dart-define=GOOGLE_WEB_CLIENT_ID=...',
      );
    }

    // Native flow (account picker sheet) rather than a browser redirect — it
    // is the flow users expect on mobile and it avoids the deep-link round trip.
    final account = await _googleSignIn.signIn();
    if (account == null) {
      throw const AuthException('Google sign-in was cancelled.');
    }
    final auth = await account.authentication;
    final idToken = auth.idToken;
    if (idToken == null) {
      throw const AuthException(
        'Google sign-in returned no ID token. Check that the Android OAuth '
        'client is registered with this build\'s SHA-1 fingerprint.',
      );
    }

    final res = await _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: auth.accessToken,
    );
    return _require(res.session, res.user, 'signInWithGoogle');
  }

  @override
  Future<AuthSession> signInWithApple() async {
    // Native Sign in with Apple is only available on Apple platforms. On
    // Android it requires the web flow via a Service ID; until that is
    // configured we fail loudly rather than opening a broken redirect.
    if (!kIsWeb && !Platform.isIOS && !Platform.isMacOS) {
      throw const AuthException(
        'Sign in with Apple is only available on iOS and macOS in this build.',
      );
    }

    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
    );
    final idToken = credential.identityToken;
    if (idToken == null) {
      throw const AuthException('Apple sign-in returned no identity token.');
    }

    final res = await _client.auth.signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: idToken,
    );

    // Apple only ever sends the display name on the *first* authorization, so
    // capture it now or it is lost forever.
    final given = credential.givenName;
    final family = credential.familyName;
    final full = [given, family].whereType<String>().join(' ').trim();
    if (full.isNotEmpty &&
        (res.user?.userMetadata?['full_name'] as String?) == null) {
      await _client.auth.updateUser(UserAttributes(data: {'full_name': full}));
    }

    return _require(res.session, res.user, 'signInWithApple');
  }

  @override
  Future<void> sendPasswordReset(String email) =>
      _client.auth.resetPasswordForEmail(email, redirectTo: Env.authCallbackUrl);

  @override
  Future<void> signOut() async {
    // Clear the Google account too, otherwise the next sign-in silently reuses
    // the cached account and the picker never appears.
    try {
      await _googleSignIn.signOut();
    } catch (_) {
      // Not signed in with Google, or Play Services unavailable — irrelevant
      // to signing out of Supabase.
    }
    await _client.auth.signOut();
  }

  AuthSession _require(Session? session, User? user, String op) {
    if (session == null) {
      // Happens when email confirmation is required: the user exists but has
      // no session until they click the link.
      if (user != null) {
        throw const AuthException(
          'Check your email to confirm your account, then sign in.',
        );
      }
      throw AuthException('$op returned no session.');
    }
    return mapSession(session);
  }

  /// Supabase [Session] -> the app's existing provider-agnostic [AuthSession].
  ///
  /// Visible for testing: this mapping is the whole compatibility surface
  /// between Supabase and every screen above `AuthRepository`.
  @visibleForTesting
  static AuthSession mapSession(Session session) {
    final user = session.user;
    final meta = user.userMetadata ?? const <String, dynamic>{};
    return AuthSession(
      // NOTE: a Supabase UUID, not a Firebase uid. Existing installs are
      // forced to sign in again once; nothing in Drift stores a user id, so
      // no local data is orphaned by the change.
      uid: user.id,
      email: user.email,
      displayName:
          (meta['full_name'] ?? meta['name'] ?? meta['display_name'])
              as String?,
      photoUrl: (meta['avatar_url'] ?? meta['picture']) as String?,
      provider: switch (user.appMetadata['provider'] as String?) {
        'google' => AuthProvider.google,
        'apple' => AuthProvider.apple,
        _ => AuthProvider.emailPassword,
      },
      idToken: session.accessToken,
      isEmailVerified: user.emailConfirmedAt != null,
    );
  }
}
