import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/core/utils/units.dart';
import 'package:herculex/data/sync/preferences/synced_preferences_bridge.dart';
import 'package:herculex/data/sync/preferences/syncing_shared_preferences.dart';
import 'package:herculex/design_system/theme/theme_provider.dart';
import 'package:herculex/features/nutrition/application/goals_providers.dart';
import 'package:herculex/features/nutrition/application/meal_slots_provider.dart';
import 'package:herculex/features/nutrition/application/nutrient_settings_provider.dart';
import 'package:herculex/features/profile/data/local_profile_repository.dart';
import 'package:herculex/features/supplements/application/supplement_providers.dart';
import 'package:herculex/features/workouts/application/performance_hint_mode_provider.dart';
import 'package:herculex/features/workouts/application/rest_timer_controller.dart';
import 'package:herculex/features/workouts/data/workout_quick_action_settings.dart';
import 'package:herculex/features/workouts/presentation/sheets/workout_settings_sheet.dart';

/// Which SharedPreferences keys follow the account to every device (web
/// track W3). Everything else stays on the device that set it.
///
/// Deliberately *not* synced: `theme_mode` (light/dark is per screen), the
/// dashboard layout, notification and widget settings, per-device consents,
/// the XP ledger (to become a synced table in Phase 24), Labs data (device
/// only by design), and `assistance_*` keys — those embed a local exercise id
/// that means a different exercise on another device.
abstract final class SyncedPreferenceKeys {
  static const exact = <String>{
    LocalProfileRepository.prefsKey,
    'nutrition_meal_slots_v1',
    'nutrition_visible_nutrients_v1',
    'nutrition_micronutrients_visible_v1',
    UnitsNotifier.prefsKey,
    'app_color_theme',
    RestTimerEnabledNotifier.prefsKey,
    DefaultRestTimerNotifier.prefsKey,
    PerformanceHintModeNotifier.prefsKey,
    QuickLoadStepNotifier.prefsKey,
    'supplements_config_v1',
  };

  static const prefixes = <String>[
    'goals_',
    'diet_',
    'min_targets_',
    'meal_',
    'supplements_taken_',
  ];

  static bool isSynced(String key) =>
      exact.contains(key) || prefixes.any(key.startsWith);
}

/// Providers that read synced keys when they are built. When the cloud
/// changes a key they are rebuilt so the screen shows the new value.
final List<ProviderOrFamily> _preferenceReaders = [
  mealSlotsProvider,
  activeDietPlanProvider,
  startingWeightProvider,
  goalWeightProvider,
  weeklyGoalProvider,
  fitnessGoalsProvider,
  showNetCarbsByMealProvider,
  mealGoalsProvider,
  minimumTargetsProvider,
  visibleNutrientIdsProvider,
  micronutrientsVisibleProvider,
  unitsProvider,
  appColorThemeProvider,
  restTimerEnabledProvider,
  defaultRestTimerProvider,
  performanceHintModeProvider,
  quickLoadStepProvider,
  supplementRepositoryProvider,
];

/// Wires [SyncedPreferencesBridge] to the session: mirrors while signed in,
/// seeds missing keys after the account's first full pull, and refreshes the
/// affected providers when a pull changes a key. Null where preferences
/// aren't wrapped (widget tests use plain SharedPreferences). Something has
/// to watch this once for it to run — `HerculexApp.build()` does.
final syncedPreferencesBridgeProvider = Provider<SyncedPreferencesBridge?>((
  ref,
) {
  final prefs = ref.watch(sharedPreferencesProvider);
  if (prefs is! SyncingSharedPreferences) return null;

  final bridge = SyncedPreferencesBridge(
    db: ref.watch(appDatabaseProvider),
    prefs: prefs,
    isSynced: SyncedPreferenceKeys.isSynced,
    onRemoteChange: (keys) {
      if (keys.contains(LocalProfileRepository.prefsKey)) {
        ref.read(localProfileRepositoryProvider).reloadFromStorage();
      }
      for (final reader in _preferenceReaders) {
        ref.invalidate(reader);
      }
    },
  );
  ref.onDispose(bridge.dispose);

  ref.listen(authSessionProvider, (_, next) {
    final uid = next.valueOrNull?.uid;
    if (uid == null) {
      bridge.detach();
    } else {
      bridge.attach(uid);
    }
  }, fireImmediately: true);

  final seedSub = ref.watch(syncServiceProvider).initialPullDoneStream.listen((
    done,
  ) {
    if (done) bridge.seedMissing();
  });
  ref.onDispose(seedSub.cancel);

  return bridge;
});
