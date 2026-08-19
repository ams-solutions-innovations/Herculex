import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/local/database.dart';
import '../../../data/local/local_data_wipe.dart';
import 'auth_repository.dart';

/// "Delete my account", start to finish.
///
/// Three stores hold the user, and all three have to go: the Supabase project
/// (the account row and, by cascade, every synced table), the local Drift
/// database, and `SharedPreferences` — which is where the profile, unit
/// preferences, dashboard layout, meal slots and supplement checklist live,
/// none of which ever syncs.
///
/// The order is not cosmetic. The remote delete goes first because it is the
/// only step that can fail in a way the user must hear about; if it does, the
/// device is left untouched and they can retry. Everything after it is local
/// cleanup that cannot fail meaningfully, so once the account is gone the
/// operation always completes.
class AccountDeletionService {
  AccountDeletionService({
    required AuthRepository authRepository,
    required AppDatabase database,
    required SharedPreferences preferences,
  }) : _authRepository = authRepository,
       _database = database,
       _preferences = preferences;

  final AuthRepository _authRepository;
  final AppDatabase _database;
  final SharedPreferences _preferences;

  /// Throws if the backend refuses the deletion, leaving local data intact.
  Future<void> deleteAccountAndWipeDevice() async {
    // Point of no return. Also signs out, which stops `SyncService` — so
    // nothing tries to push the deletes made below into an account that no
    // longer exists.
    await _authRepository.deleteAccount();

    await wipeAllLocalUserData(_database);

    // `clear()` rather than a key list on purpose: an allowlist would silently
    // miss whatever preference the next feature adds, and everything in here
    // is either the user's own data or a setting that should not outlive them.
    // Clearing the onboarding flags is intended — the app is a fresh install
    // as far as this device is concerned.
    await _preferences.clear();
  }
}
