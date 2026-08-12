import 'dart:async';

import '../domain/auth_provider_service.dart';
import '../domain/auth_session.dart';
import 'local_auth_repository.dart';

/// Facade over the credential provider ([AuthProviderService]) and the local
/// session cache ([LocalAuthRepository]).
///
/// Every public method signature here is unchanged from the Firebase era, so
/// no screen above this class was touched by the Supabase cutover.
class AuthRepository {
  AuthRepository({
    required LocalAuthRepository localRepository,
    required AuthProviderService authService,
  }) : _localRepository = localRepository,
       _authService = authService {
    // Replaces the old one-shot `hydrateFromNative()` pull. Subscribing means
    // token refresh, session expiry and sign-outs triggered elsewhere all keep
    // the local cache honest — none of which the imperative version noticed.
    _sub = _authService.authStateChanges().listen((session) async {
      if (session == null) {
        await _localRepository.clear();
      } else {
        await _localRepository.save(session);
      }
    });
  }

  final LocalAuthRepository _localRepository;
  final AuthProviderService _authService;
  StreamSubscription<AuthSession?>? _sub;

  AuthSession? get currentSession => _localRepository.currentSession;

  Stream<AuthSession?> watch() => _localRepository.watch();

  /// The current access token, read straight from the auth client.
  ///
  /// Previously this read a separately-stored copy of the Firebase ID token,
  /// which `MainActivity.toAuthSessionMap()` always mapped to null — so it
  /// returned null unconditionally. Sourcing it from the live session removes
  /// both the duplicate storage and the bug.
  Future<String?> getIdToken() async =>
      (await _authService.getCurrentUser())?.idToken;

  /// Initial synchronous reconciliation at startup, so the router does not
  /// flash the onboarding screen before [authStateChanges] delivers.
  Future<void> hydrate() async {
    final session = await _authService.getCurrentUser();
    if (session == null) {
      await _localRepository.clear();
    } else {
      await _localRepository.save(session);
    }
  }

  Future<AuthSession> registerWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final session = await _authService.registerWithEmail(
      email: email,
      password: password,
      displayName: displayName,
    );
    await _localRepository.save(session);
    return session;
  }

  Future<AuthSession> loginWithEmail({
    required String email,
    required String password,
  }) async {
    final session = await _authService.loginWithEmail(
      email: email,
      password: password,
    );
    await _localRepository.save(session);
    return session;
  }

  Future<AuthSession> signInWithGoogle() async {
    final session = await _authService.signInWithGoogle();
    await _localRepository.save(session);
    return session;
  }

  Future<AuthSession> signInWithApple() async {
    final session = await _authService.signInWithApple();
    await _localRepository.save(session);
    return session;
  }

  Future<void> sendPasswordReset(String email) {
    return _authService.sendPasswordReset(email);
  }

  Future<void> signOut() async {
    await _authService.signOut();
    await _localRepository.clear();
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
