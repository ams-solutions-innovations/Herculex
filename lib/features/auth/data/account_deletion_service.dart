import 'package:herculex/data/local/database.dart';
import 'package:herculex/data/local/local_data_wipe.dart';
import 'package:herculex/features/auth/data/auth_repository.dart';
import 'package:herculex/features/profile/data/local_profile_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "Delete my account" and "Clear All Data", start to finish.
///
/// Three stores hold the user: the Supabase project (the account row and, by
/// cascade, every synced table), the local Drift database (+ photo files), and
/// `SharedPreferences` — which is where the profile, unit preferences,
/// dashboard layout, meal slots and supplement checklist live.
///
/// For account deletion, the remote delete goes first because it is the only
/// step that can fail in a way the user must hear about; if it does, the
/// device is left untouched and they can retry.
class AccountDeletionService {
  AccountDeletionService({
    required AuthRepository authRepository,
    required AppDatabase database,
    required SharedPreferences preferences,
    LocalProfileRepository? localProfileRepository,
  }) : _authRepository = authRepository,
       _database = database,
       _preferences = preferences,
       _localProfileRepository = localProfileRepository;

  final AuthRepository _authRepository;
  final AppDatabase _database;
  final SharedPreferences _preferences;
  final LocalProfileRepository? _localProfileRepository;

  /// Throws if the backend refuses the deletion, leaving local data intact.
  Future<void> deleteAccountAndWipeDevice() async {
    // Point of no return. Also signs out, which stops `SyncService` — so
    // nothing tries to push the deletes made below into an account that no
    // longer exists.
    await _authRepository.deleteAccount();
    await _wipeLocalStores();
  }

  /// Wipes every local user store (SQLite tables, photos, home-screen widgets,
  /// and `SharedPreferences`) while leaving any cloud account untouched.
  ///
  /// If a cloud session is currently active, signs out locally first so
  /// `SyncService` stops before the local tables are cleared (preventing both
  /// race pushes and background pulls repopulating the wiped device).
  Future<void> clearAllLocalDataOnly() async {
    if (_authRepository.currentSession != null) {
      await _authRepository.signOut();
    }
    await _wipeLocalStores();
  }

  Future<void> _wipeLocalStores() async {
    await wipeAllLocalUserData(_database);

    // `clear()` rather than a key list on purpose: an allowlist would silently
    // miss whatever preference the next feature adds, and everything in here
    // is either the user's own data or a setting that should not outlive them.
    await _preferences.clear();

    // Notify in-memory profile stream listeners so GoRouter immediately
    // redirects back to onboarding.
    await _localProfileRepository?.clear();
  }
}
