import '../domain/auth_session.dart';
import 'local_auth_repository.dart';
import 'native_auth_service.dart';

class AuthRepository {
  AuthRepository({
    required LocalAuthRepository localRepository,
    required NativeAuthService nativeService,
  }) : _localRepository = localRepository,
       _nativeService = nativeService;

  final LocalAuthRepository _localRepository;
  final NativeAuthService _nativeService;

  AuthSession? get currentSession => _localRepository.currentSession;

  Stream<AuthSession?> watch() => _localRepository.watch();

  Future<void> hydrateFromNative() async {
    final session = await _nativeService.getCurrentUser();
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
    final session = await _nativeService.registerWithEmail(
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
    final session = await _nativeService.loginWithEmail(
      email: email,
      password: password,
    );
    await _localRepository.save(session);
    return session;
  }

  Future<AuthSession> signInWithGoogle() async {
    final session = await _nativeService.signInWithGoogle();
    await _localRepository.save(session);
    return session;
  }

  Future<AuthSession> signInWithApple() async {
    final session = await _nativeService.signInWithApple();
    await _localRepository.save(session);
    return session;
  }

  Future<void> sendPasswordReset(String email) {
    return _nativeService.sendPasswordReset(email);
  }

  Future<void> signOut() async {
    await _nativeService.signOut();
    await _localRepository.clear();
  }
}
