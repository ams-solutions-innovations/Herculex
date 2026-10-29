import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/core/platform/platform_capabilities.dart';
import 'package:herculex/core/utils/env.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/data/sync/supabase_sync_backend_service.dart';
import 'package:herculex/data/sync/sync_backend_service.dart';
import 'package:herculex/data/sync/sync_service.dart';
import 'package:herculex/features/auth/data/account_deletion_service.dart';
import 'package:herculex/features/auth/data/auth_repository.dart';
import 'package:herculex/features/auth/data/local_auth_repository.dart';
import 'package:herculex/features/auth/data/supabase_auth_service.dart';
import 'package:herculex/features/auth/data/unconfigured_auth_service.dart';
import 'package:herculex/features/auth/domain/auth_provider_service.dart';
import 'package:herculex/features/auth/domain/auth_session.dart';
import 'package:herculex/features/gyms/data/gyms_repository.dart';
import 'package:herculex/features/measurements/data/measurements_repository.dart';
import 'package:herculex/features/nutrition/data/food_catalogue_source.dart';
import 'package:herculex/features/nutrition/data/remote_food_catalogue_source.dart';
import 'package:herculex/features/physique/data/physique_summary_bridge.dart';
import 'package:herculex/features/profile/data/local_profile_repository.dart';
import 'package:herculex/features/profile/data/dream_physique_summary_repository.dart';
import 'package:herculex/features/profile/data/dream_physique_nutrition_preference_repository.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:herculex/features/workouts/data/accessories_repository.dart';
import 'package:herculex/features/workouts/data/exercise_progressions_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

export 'package:herculex/core/utils/clock.dart' show clockProvider;

/// Overridden in main() once SharedPreferences has been initialised.
final sharedPreferencesProvider = Provider<SharedPreferences>((_) {
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main()',
  );
});

/// Resolves to the real Supabase-backed sync backend when the build carries
/// credentials, and to a safe no-op otherwise — same idiom as
/// [authServiceProvider].
final syncBackendServiceProvider = Provider<SyncBackendService>((ref) {
  if (!Env.hasSupabase) return const NoopSyncBackendService();
  return SupabaseSyncBackendService(Supabase.instance.client);
});

/// Starts/stops itself off [authSessionProvider] — sign-in begins draining
/// the outbox and pulling remote deltas, sign-out stops both. Something must
/// `ref.watch(syncServiceProvider)` once at app startup for this to run at
/// all (see `HerculexApp.build()`), since Riverpod providers are lazy.
/// Where catalogue foods come from: the bundled import on phones, the shared
/// `food_catalogue` table (fetched on demand, cached locally) on the web.
final foodCatalogueSourceProvider = Provider<FoodCatalogueSource>((ref) {
  if (ref.watch(platformCapabilitiesProvider).hasBundledFoodCatalogue ||
      !Env.hasSupabase) {
    return const BundledFoodCatalogueSource();
  }
  return RemoteFoodCatalogueSource(
    ref.watch(appDatabaseProvider),
    SupabaseFoodCatalogueRemote(Supabase.instance.client),
  );
});

final syncServiceProvider = Provider<SyncService>((ref) {
  final caps = ref.watch(platformCapabilitiesProvider);
  final service = SyncService(
    db: ref.watch(appDatabaseProvider),
    backend: ref.watch(syncBackendServiceProvider),
    // Without the bundled catalogue, a pulled food entry has to bring its
    // catalogue food along or it would resolve to no food at all.
    cataloguePrefetcher: caps.hasBundledFoodCatalogue
        ? null
        : ref.watch(foodCatalogueSourceProvider),
  );
  ref.onDispose(service.dispose);

  ref.listen<AsyncValue<AuthSession?>>(authSessionProvider, (previous, next) {
    final session = next.value;
    if (session != null) {
      service.start(session.uid);
    } else {
      service.stop();
    }
  }, fireImmediately: true);

  return service;
});

/// What the sync layer is actually doing — derived from real push/pull
/// results, unlike the `SyncEngine` this replaced, which inferred "synced"
/// from an empty outbox table without ever contacting a backend (RB-02).
final syncStateProvider = StreamProvider<SyncState>((ref) {
  return ref.watch(syncServiceProvider).stateStream;
});

/// Whether this build gates the app behind a signed-in account: the web,
/// when it has a backend to sign in to. A web build without Supabase
/// credentials (local development) runs local-only like a phone instead of
/// stopping at a sign-in screen nobody can get past.
final accountRequiredProvider = Provider<bool>(
  (ref) =>
      ref.watch(platformCapabilitiesProvider).requiresAccount &&
      Env.hasSupabase,
);

/// Whether the local database holds the signed-in account yet.
///
/// Always true where the device owns its data (phones work offline-first and
/// keep it across sessions). On the web a fresh browser starts empty, so this
/// stays false until the first full cloud pull — the router parks on
/// `/restoring`, and startup code that writes defaults waits for it.
final initialSyncReadyProvider = StreamProvider<bool>((ref) {
  if (!ref.watch(platformCapabilitiesProvider).requiresInitialSync ||
      !ref.watch(accountRequiredProvider)) {
    return Stream.value(true);
  }
  return ref.watch(syncServiceProvider).initialPullDoneStream;
});

final localProfileRepositoryProvider = Provider<LocalProfileRepository>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final repo = LocalProfileRepository(prefs);
  ref.onDispose(repo.dispose);
  return repo;
});

final dreamPhysiqueSummaryRepositoryProvider =
    Provider<DreamPhysiqueSummaryRepository>((ref) {
      final repository = DreamPhysiqueSummaryRepository(
        ref.watch(sharedPreferencesProvider),
      );
      ref.onDispose(repository.dispose);
      return repository;
    });

/// Database-backed since Phase 23: same names and model as before so Phase 27
/// and the existing Dream Physique consumers keep working. The preferences
/// repository above is now only the legacy migration source.
final physiqueSummaryBridgeProvider = Provider<PhysiqueSummaryBridge>(
  (ref) => PhysiqueSummaryBridge(ref.watch(appDatabaseProvider)),
);

final dreamPhysiqueSummaryProvider =
    StreamProvider<DreamPhysiqueAnalysisSummary?>((ref) {
      return ref.watch(physiqueSummaryBridgeProvider).watchCurrent();
    });

final dreamPhysiqueSummaryHistoryProvider =
    StreamProvider<List<DreamPhysiqueAnalysisSummary>>((ref) {
      return ref.watch(physiqueSummaryBridgeProvider).watchHistory();
    });

final dreamPhysiqueNutritionPreferenceRepositoryProvider =
    Provider<DreamPhysiqueNutritionPreferenceRepository>((ref) {
      final repository = DreamPhysiqueNutritionPreferenceRepository(
        ref.watch(sharedPreferencesProvider),
      );
      ref.onDispose(repository.dispose);
      return repository;
    });

final dreamPhysiqueNutritionPreferenceProvider =
    StreamProvider<DreamPhysiqueNutritionPreference?>((ref) {
      return ref
          .watch(dreamPhysiqueNutritionPreferenceRepositoryProvider)
          .watch();
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

/// Owns the whole "delete my account" flow — remote account, local database
/// and preferences. Kept separate from [authRepositoryProvider] so the auth
/// layer stays free of Drift and `SharedPreferences` dependencies.
final accountDeletionServiceProvider = Provider<AccountDeletionService>((ref) {
  return AccountDeletionService(
    authRepository: ref.watch(authRepositoryProvider),
    database: ref.watch(appDatabaseProvider),
    preferences: ref.watch(sharedPreferencesProvider),
    localProfileRepository: ref.watch(localProfileRepositoryProvider),
  );
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
  final db = ref.watch(appDatabaseProvider);
  final profileRepo = ref.watch(localProfileRepositoryProvider);
  final repo = MeasurementsRepository(db, profileRepo);
  profileRepo.setMeasurementsRepository(repo);
  if (ref.read(platformCapabilitiesProvider).requiresInitialSync) {
    // Seeding a bodyweight row from the profile into an empty browser
    // database would duplicate the one the first pull is about to deliver.
    ref.listen<AsyncValue<bool>>(initialSyncReadyProvider, (_, next) {
      if (next.valueOrNull ?? false) repo.syncOnStartup();
    }, fireImmediately: true);
  } else {
    repo.syncOnStartup();
  }
  return repo;
});

final exerciseProgressionsRepositoryProvider =
    Provider<ExerciseProgressionsRepository>((ref) {
      return ExerciseProgressionsRepository(ref.watch(appDatabaseProvider));
    });
