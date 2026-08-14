import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/admin/presentation/admin_dashboard_view.dart';
import '../features/admin/presentation/admin_insert_recipe_view.dart';
import '../features/admin/presentation/admin_insert_workout_view.dart';
import '../features/analytics/presentation/insights_view.dart';
import '../features/gyms/presentation/gyms_view.dart';
import '../features/health/presentation/cycle_tracking_view.dart';
import '../features/health/presentation/health_integrations_view.dart';
import '../features/health/presentation/health_platform_detail_view.dart';
import '../features/measurements/presentation/measurements_view.dart';
import '../features/measurements/presentation/metric_detail_view.dart';
import '../features/nutrition/presentation/calorie_macro_goals_view.dart';
import '../features/nutrition/presentation/calorie_meal_goals_view.dart';
import '../features/nutrition/presentation/goals_view.dart';
import '../features/nutrition/presentation/nutrition_targets_view.dart';
import '../features/nutrition/presentation/meal_slots_view.dart';
import '../features/nutrition/presentation/nutrient_overview_view.dart';
import '../features/reps/presentation/fixture_recording_view.dart';
import '../features/nutrition/presentation/nutrient_settings_view.dart';
import '../features/onboarding/presentation/onboarding_view.dart';
import '../features/programs/presentation/rotation_pools_view.dart';
import '../features/profile/domain/profile.dart';
import '../features/profile/presentation/custom_foods_view.dart';
import '../features/profile/presentation/custom_recipes_view.dart';
import '../features/profile/presentation/profile_view.dart';
import '../features/reps/presentation/rep_tracking_consent_view.dart';
import '../features/shell/main_scaffold.dart';
import '../features/shell/splash_view.dart';
import '../features/workouts/presentation/micro_workouts_view.dart';
import '../features/workouts/presentation/workout_history_view.dart';
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

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
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
        builder: (_, state) => WorkoutHistoryView(
          sessionId: int.parse(state.pathParameters['id']!),
        ),
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
      GoRoute(path: '/gyms', builder: (_, _) => const GymsView()),
      GoRoute(
        path: '/micro-workouts',
        builder: (_, _) => const MicroWorkoutsView(),
      ),
      GoRoute(path: '/insights', builder: (_, _) => const InsightsView()),
      GoRoute(path: '/health', builder: (_, _) => const HealthIntegrationsView()),
      GoRoute(
        path: '/rep-tracking-consent',
        builder: (_, _) => const RepTrackingConsentView(),
      ),
      GoRoute(path: '/cycle', builder: (_, _) => const CycleTrackingView()),
      GoRoute(
        path: '/health/samsung',
        builder: (_, _) => const HealthPlatformDetailView(platform: HealthPlatform.samsung),
      ),
      GoRoute(
        path: '/health/apple',
        builder: (_, _) => const HealthPlatformDetailView(platform: HealthPlatform.apple),
      ),
      GoRoute(
        path: '/health/google',
        builder: (_, _) => const HealthPlatformDetailView(platform: HealthPlatform.google),
      ),
      GoRoute(path: '/profile', builder: (_, _) => const ProfileView()),
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
