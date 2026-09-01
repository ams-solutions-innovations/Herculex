import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:herculex/app/providers.dart';

/// Whether the Workout Bubble — the floating chat head shown over other apps
/// during a workout — is enabled.
///
/// Persisted in SharedPreferences; toggled from the Profile settings screen.
/// Defaults to **off**, unlike the other workout toggles: it needs the
/// sensitive "Display over other apps" permission, so it has to be opt-in.
///
/// This is only the user's preference. Whether a bubble is actually on screen
/// also depends on the permission and on there being a live session — see
/// `shouldShowWorkoutBubble` in
/// `lib/services/active_workout_surface_sync_policy.dart`.
class WorkoutBubbleEnabledNotifier extends Notifier<bool> {
  static const prefsKey = 'workout_bubble_enabled';

  @override
  bool build() =>
      ref.watch(sharedPreferencesProvider).getBool(prefsKey) ?? false;

  Future<void> set(bool enabled) async {
    await ref.read(sharedPreferencesProvider).setBool(prefsKey, enabled);
    state = enabled;
  }
}

final workoutBubbleEnabledProvider =
    NotifierProvider<WorkoutBubbleEnabledNotifier, bool>(
      WorkoutBubbleEnabledNotifier.new,
    );
