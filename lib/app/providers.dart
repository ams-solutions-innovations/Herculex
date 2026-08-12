import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../core/env.dart';
import '../data/local/database.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/auth/data/local_auth_repository.dart';
import '../features/auth/data/supabase_auth_service.dart';
import '../features/auth/data/unconfigured_auth_service.dart';
import '../features/auth/domain/auth_provider_service.dart';
import '../features/auth/domain/auth_session.dart';
import '../features/profile/data/local_profile_repository.dart';
import '../features/profile/domain/profile.dart';

import '../features/gyms/data/gyms_repository.dart';
import '../features/measurements/data/measurements_repository.dart';
import '../features/workouts/data/accessories_repository.dart';
import '../features/workouts/data/exercise_progressions_repository.dart';
import '../data/sync/sync_engine.dart';

export '../core/clock.dart' show clockProvider;

/// Overridden in main() once SharedPreferences has been initialised.
final sharedPreferencesProvider = Provider<SharedPreferences>((_) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden in main()');
});

final syncEngineProvider = Provider<SyncEngine>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final engine = SyncEngine(db);
  ref.onDispose(engine.dispose);
  return engine;
});

final syncStatusProvider = StreamProvider<SyncStatus>((ref) {
  return ref.watch(syncEngineProvider).statusStream;
});

final localProfileRepositoryProvider = Provider<LocalProfileRepository>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final repo = LocalProfileRepository(prefs);
  ref.onDispose(repo.dispose);
  return repo;
});

final localAuthRepositoryProvider = Provider<LocalAuthRepository>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final repo = LocalAuthRepository(prefs);
  ref.onDispose(repo.dispose);
  return repo;
});

/// Resolves to Supabase when the build carries backend credentials, and to a
/// local-only stub otherwise. Reading `Supabase.instance` unconditionally would
/// assert in tests and in any credential-less dev build.
final authServiceProvider = Provider<AuthProviderService>((ref) {
  if (!Env.hasSupabase) return const UnconfiguredAuthService();
  return SupabaseAuthService(Supabase.instance.client);
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final repo = AuthRepository(
    localRepository: ref.watch(localAuthRepositoryProvider),
    authService: ref.watch(authServiceProvider),
  );
  ref.onDispose(repo.dispose);
  return repo;
});

final authSessionProvider = StreamProvider<AuthSession?>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  return repo.watch();
});

final profileProvider = StreamProvider<Profile?>((ref) {
  final repo = ref.watch(localProfileRepositoryProvider);
  return repo.watch();
});

/// Single AppDatabase instance for the lifetime of the app.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final gymsRepositoryProvider = Provider<GymsRepository>((ref) {
  return GymsRepository(ref.watch(appDatabaseProvider));
});

final accessoriesRepositoryProvider = Provider<AccessoriesRepository>((ref) {
  return AccessoriesRepository(ref.watch(appDatabaseProvider));
});

final measurementsRepositoryProvider = Provider<MeasurementsRepository>((ref) {
  return MeasurementsRepository(ref.watch(appDatabaseProvider));
});

final exerciseProgressionsRepositoryProvider =
    Provider<ExerciseProgressionsRepository>((ref) {
  return ExerciseProgressionsRepository(ref.watch(appDatabaseProvider));
});
