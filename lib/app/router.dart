import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/error/app_error_view.dart';
import '../core/error/error_log_view.dart';
import '../features/admin/presentation/admin_dashboard_view.dart';
import '../features/admin/presentation/admin_insert_recipe_view.dart';
import '../features/admin/presentation/admin_insert_workout_view.dart';
import '../features/analytics/presentation/cns_view.dart';
import '../features/analytics/presentation/insights_view.dart';
import '../features/analytics/presentation/muscle_volume_detail_view.dart';
import '../features/analytics/presentation/muscle_volume_overview_view.dart';
import '../features/recovery/presentation/recovery_view.dart';
import '../features/fasting/presentation/fasting_schedule_view.dart';
import '../features/fasting/presentation/fasting_view.dart';
import '../features/gyms/presentation/gyms_view.dart';
import '../features/health/presentation/cycle_tracking_view.dart';
import '../features/health/presentation/health_integrations_view.dart';
import '../features/health/presentation/health_platform_detail_view.dart';
import '../features/measurements/presentation/measurements_view.dart';
import '../features/measurements/presentation/metric_detail_view.dart';
import '../features/notifications/presentation/notification_settings_view.dart';
import '../features/nutrition/presentation/calorie_macro_goals_view.dart';
import '../features/nutrition/presentation/calorie_meal_goals_view.dart';
import '../features/nutrition/presentation/goals_view.dart';
import '../features/nutrition/presentation/nutrition_targets_view.dart';
import '../features/nutrition/presentation/meal_slots_view.dart';
import '../features/nutrition/presentation/nutrient_overview_view.dart';
import '../features/reps/presentation/fixture_recording_view.dart';
import '../features/nutrition/presentation/nutrient_settings_view.dart';
import '../features/nutrition/presentation/weekly_calories_view.dart';
import '../features/onboarding/presentation/onboarding_view.dart';
import '../features/programs/presentation/rotation_pools_view.dart';
import '../features/profile/domain/profile.dart';
import '../features/profile/presentation/custom_foods_view.dart';
import '../features/profile/presentation/custom_recipes_view.dart';
import '../features/profile/presentation/dream_physique_view.dart';
import '../features/profile/presentation/profile_view.dart';
import '../features/shell/main_scaffold.dart';
import '../features/shell/splash_view.dart';
import '../features/workouts/presentation/micro_workouts_view.dart';
import '../features/workouts/presentation/exercise_details_view.dart';
import '../features/workouts/presentation/exercise_library_view.dart';
import '../features/workouts/presentation/workout_history_view.dart';
import '../features/buddy/presentation/buddy_join_scanner_view.dart';
import 'providers.dart';

/// Bridges the Riverpod profile stream into a [Listenable] so
/// [GoRouter.refreshListenable] re-evaluates the redirect every time the local
/// profile changes (e.g. onboarding completes, or data is cleared).
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen<AsyncValue<Profile?>>(
      profileProvider,
      (_, _) => notifyListeners(),
    );
  }
}

/// `int.parse` on a path parameter throws *inside a route builder*, which is a
/// build-phase throw — it used to take the whole screen down. Deep links,
/// notification payloads and restored routes are all untrusted input here.
int? _intParam(GoRouterState state, String name) =>
    int.tryParse(state.pathParameters[name] ?? '');

Widget _badParam(BuildContext context, GoRouterState state, String name) =>
    AppErrorScreen(
      message: "'${state.pathParameters[name]}' isn't a valid $name.",
      onGoHome: () => context.go('/app'),
    );

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    // Unmatched paths and malformed deep links used to fall through to
    // go_router's bare default screen; a throw inside a route builder had no
    // boundary at all.
    errorBuilder: (context, state) => AppErrorScreen(
      message: state.error?.toString() ?? 'No screen matches ${state.uri}.',
      onGoHome: () => context.go('/app'),
    ),
    redirect: (context, state) {
      // On-device only: the only gate is whether onboarding has produced a
      // local profile. No accounts, no sign-in.
      final profileAsync = ref.read(profileProvider);
      final loc = state.matchedLocation;

      // While the profile is still loading from disk, sit on /splash.
      if (profileAsync.isLoading) {
        return loc == '/splash' ? null : '/splash';
      }

      final profile = profileAsync.asData?.value;

      // No profile yet → onboarding is the only valid destination.
      if (profile == null) {
        return loc == '/onboarding' ? null : '/onboarding';
      }

      // Onboarded: bounce out of splash/onboarding into the app.
      if (loc == '/splash' || loc == '/onboarding') return '/app';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashView()),
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingView()),
      GoRoute(path: '/app', builder: (_, _) => const MainScaffold()),
      GoRoute(
        path: '/workout-history/:id',
        builder: (context, state) {
          final id = _intParam(state, 'id');
          if (id == null) return _badParam(context, state, 'id');
          return WorkoutHistoryView(sessionId: id);
        },
      ),
      GoRoute(
        path: '/exercise/:id',
        builder: (context, state) {
          final id = _intParam(state, 'id');
          if (id == null) return _badParam(context, state, 'id');
          return ExerciseDetailsView(exerciseId: id);
        },
      ),
      GoRoute(
        path: '/measurements',
        builder: (_, _) => const MeasurementsView(),
      ),
      GoRoute(
        path: '/measurements/:metric',
        builder: (_, state) =>
            MetricDetailView(metric: state.pathParameters['metric']!),
      ),
      GoRoute(path: '/fasting', builder: (_, _) => const FastingView()),
      GoRoute(
        path: '/fasting/schedule',
        builder: (_, _) => const FastingScheduleView(),
      ),
      GoRoute(path: '/gyms', builder: (_, _) => const GymsView()),
      GoRoute(
        path: '/micro-workouts',
        builder: (_, _) => const MicroWorkoutsView(),
      ),
      GoRoute(
        path: '/exercises',
        builder: (_, _) => const ExerciseLibraryView(),
      ),
      GoRoute(path: '/insights', builder: (_, _) => const InsightsView()),
      GoRoute(path: '/cns', builder: (_, _) => const CnsView()),
      GoRoute(path: '/recovery', builder: (_, _) => const RecoveryView()),
      GoRoute(
        path: '/muscle-volume',
        builder: (_, _) => const MuscleVolumeOverviewView(),
      ),
      GoRoute(
        path: '/muscle-volume/:muscle',
        builder: (_, state) =>
            MuscleVolumeDetailView(muscle: state.pathParameters['muscle']!),
      ),
      GoRoute(
        path: '/health',
        builder: (_, _) => const HealthIntegrationsView(),
      ),
      GoRoute(path: '/cycle', builder: (_, _) => const CycleTrackingView()),
      GoRoute(
        path: '/health/samsung',
        builder: (_, _) =>
            const HealthPlatformDetailView(platform: HealthPlatform.samsung),
      ),
      GoRoute(
        path: '/health/apple',
        builder: (_, _) =>
            const HealthPlatformDetailView(platform: HealthPlatform.apple),
      ),
      GoRoute(
        path: '/health/google',
        builder: (_, _) =>
            const HealthPlatformDetailView(platform: HealthPlatform.google),
      ),
      GoRoute(path: '/profile', builder: (_, _) => const ProfileView()),
      GoRoute(
        path: '/notifications',
        builder: (_, _) => const NotificationSettingsView(),
      ),
      GoRoute(
        path: '/dream-physique',
        builder: (_, _) => const DreamPhysiqueView(),
      ),
      GoRoute(
        path: '/custom-foods',
        builder: (_, _) => const CustomFoodsView(),
      ),
      GoRoute(
        path: '/custom-recipes',
        builder: (_, _) => const CustomRecipesView(),
      ),
      GoRoute(
        path: '/nutrition-targets',
        builder: (_, _) => const NutritionTargetsView(),
      ),
      GoRoute(
        path: '/nutrition-meal-slots',
        builder: (_, _) => const MealSlotsView(),
      ),
      GoRoute(
        path: '/nutrition-nutrients',
        builder: (_, _) => const NutrientSettingsView(),
      ),
      GoRoute(
        path: '/nutrient-overview',
        builder: (_, _) => const NutrientOverviewView(),
      ),
      GoRoute(
        path: '/nutrition/weekly-stats',
        builder: (_, _) => const WeeklyCaloriesView(),
      ),
      GoRoute(
        path: '/macro-trends/:macro',
        builder: (_, state) =>
            MacroTrendView(macro: state.pathParameters['macro'] ?? 'kcal'),
      ),
      GoRoute(path: '/goals', builder: (_, _) => const GoalsView()),
      GoRoute(
        path: '/calorie-macro-goals',
        builder: (_, _) => const CalorieMacroGoalsView(),
      ),
      GoRoute(
        path: '/calorie-meal-goals',
        builder: (_, _) => const CalorieMealGoalsView(),
      ),
      GoRoute(
        path: '/rotation-pools',
        builder: (_, _) => const RotationPoolsView(),
      ),
      GoRoute(
        path: '/buddy/join',
        builder: (_, _) => const BuddyJoinScannerView(),
      ),
      // Deliberately *not* behind kDebugMode: release is where an error is
      // otherwise invisible (blank ErrorWidget, no reporter), so this has to
      // be reachable there. Read-only, and holds nothing the user didn't
      // already generate on their own device.
      GoRoute(
        path: '/diagnostics/errors',
        builder: (_, _) => const ErrorLogView(),
      ),
      // Developer-only content tools. Excluded from release builds entirely.
      if (kDebugMode) ...[
        GoRoute(path: '/admin', builder: (_, _) => const AdminDashboardView()),
        GoRoute(
          path: '/admin/workout',
          builder: (_, _) => const AdminInsertWorkoutView(),
        ),
        GoRoute(
          path: '/admin/recipe',
          builder: (_, _) => const AdminInsertRecipeView(),
        ),
        GoRoute(
          path: '/admin/fixture-recording',
          builder: (_, _) => const FixtureRecordingView(),
        ),
      ],
    ],
  );
});
