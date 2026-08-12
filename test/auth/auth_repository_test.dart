import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/auth/data/auth_repository.dart';
import 'package:herculex/features/auth/data/local_auth_repository.dart';
import 'package:herculex/features/auth/domain/auth_provider_service.dart';
import 'package:herculex/features/auth/domain/auth_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory stand-in for [SupabaseAuthService]. The whole point of extracting
/// [AuthProviderService] was to make this possible without a live
/// `SupabaseClient`.
class FakeAuthProviderService implements AuthProviderService {
  FakeAuthProviderService({this.throwOnSignIn});

  final Object? throwOnSignIn;
  final _controller = StreamController<AuthSession?>.broadcast();
  AuthSession? current;
  int signOutCalls = 0;
  String? passwordResetEmail;

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

  Future<void> dispose() => _controller.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalAuthRepository local;
  late FakeAuthProviderService service;
  late AuthRepository repo;

  Future<void> build({Object? throwOnSignIn}) async {
    SharedPreferences.setMockInitialValues({});
    local = LocalAuthRepository(await SharedPreferences.getInstance());
    service = FakeAuthProviderService(throwOnSignIn: throwOnSignIn);
    repo = AuthRepository(localRepository: local, authService: service);
  }

  tearDown(() async {
    repo.dispose();
    local.dispose();
    await service.dispose();
  });

  test('sign-in persists the session to the local cache', () async {
    await build();
    final session = await repo.loginWithEmail(
      email: 'a@b.c',
      password: 'pw',
    );

    expect(session.uid, 'login');
    expect(local.currentSession?.uid, 'login');
  });

  test('sign-out clears the local cache', () async {
    await build();
    await repo.loginWithEmail(email: 'a@b.c', password: 'pw');
    expect(local.currentSession, isNotNull);

    await repo.signOut();

    expect(service.signOutCalls, 1);
    expect(local.currentSession, isNull);
  });

  test('the cached session never contains a bearer token', () async {
    await build();
    await repo.loginWithEmail(email: 'a@b.c', password: 'pw');

    // AuthSession.toJson deliberately omits idToken, so a session round-tripped
    // through SharedPreferences must come back without one.
    expect(local.currentSession!.idToken, isNull);
    // ...while the live token is still reachable from the auth client.
    expect(await repo.getIdToken(), 'token-login');
  });

  test(
    'an auth-state change from the provider updates the cache unprompted',
    () async {
      await build();
      final pushed = AuthSession(
        uid: 'refreshed',
        provider: AuthProvider.google,
        isEmailVerified: true,
      );

      service.emit(pushed);
      await pumpEventQueue();

      // The old one-shot hydrateFromNative() could not observe this at all.
      expect(local.currentSession?.uid, 'refreshed');

      service.emit(null);
      await pumpEventQueue();
      expect(local.currentSession, isNull);
    },
  );

  test('hydrate() reconciles the cache at startup', () async {
    await build();
    service.current = AuthSession(
      uid: 'restored',
      provider: AuthProvider.emailPassword,
      isEmailVerified: false,
    );

    await repo.hydrate();

    expect(local.currentSession?.uid, 'restored');
  });

  test('hydrate() clears a stale cache when the provider has no user', () async {
    await build();
    await repo.loginWithEmail(email: 'a@b.c', password: 'pw');
    service.current = null;

    await repo.hydrate();

    expect(local.currentSession, isNull);
  });

  test('provider errors propagate unchanged for the onboarding error UI', () async {
    await build(throwOnSignIn: StateError('invalid credentials'));

    await expectLater(
      repo.loginWithEmail(email: 'a@b.c', password: 'wrong'),
      throwsA(isA<StateError>()),
    );
    expect(local.currentSession, isNull);
  });

  test('dispose cancels the auth-state subscription', () async {
    await build();
    repo.dispose();

    service.emit(
      AuthSession(
        uid: 'after-dispose',
        provider: AuthProvider.google,
        isEmailVerified: true,
      ),
    );
    await pumpEventQueue();

    expect(local.currentSession, isNull);
  });
}
