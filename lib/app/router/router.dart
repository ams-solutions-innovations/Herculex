import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/core/error/app_error_view.dart';
import 'package:herculex/core/error/error_log_view.dart';
import 'package:herculex/features/admin/presentation/admin_dashboard_view.dart';
import 'package:herculex/features/admin/presentation/admin_insert_recipe_view.dart';
import 'package:herculex/features/admin/presentation/admin_insert_workout_view.dart';
import 'package:herculex/features/analytics/presentation/views/cns_view.dart';
import 'package:herculex/features/analytics/presentation/views/insights_view.dart';
import 'package:herculex/features/analytics/presentation/views/muscle_volume_detail_view.dart';
import 'package:herculex/features/analytics/presentation/views/muscle_volume_overview_view.dart';
import 'package:herculex/features/analytics/presentation/views/personal_records_view.dart';
import 'package:herculex/features/buddy/presentation/buddy_join_scanner_view.dart';
import 'package:herculex/features/fasting/presentation/fasting_schedule_view.dart';
import 'package:herculex/features/fasting/presentation/fasting_view.dart';
import 'package:herculex/features/gamification/presentation/training_level_view.dart';
import 'package:herculex/features/gyms/presentation/gyms_view.dart';
import 'package:herculex/features/health/presentation/cycle_tracking_view.dart';
import 'package:herculex/features/health/presentation/health_integrations_view.dart';
import 'package:herculex/features/health/presentation/health_platform_detail_view.dart';
import 'package:herculex/features/measurements/presentation/measurements_view.dart';
import 'package:herculex/features/measurements/presentation/metric_detail_view.dart';
import 'package:herculex/features/notifications/presentation/notification_settings_view.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/nutrition/presentation/views/calorie_macro_goals_view.dart';
import 'package:herculex/features/nutrition/presentation/views/calorie_meal_goals_view.dart';
import 'package:herculex/features/nutrition/presentation/views/goals_view.dart';
import 'package:herculex/features/nutrition/presentation/views/meal_slots_view.dart';
import 'package:herculex/features/nutrition/presentation/views/nutrient_overview_view.dart';
import 'package:herculex/features/nutrition/presentation/views/nutrient_settings_view.dart';
import 'package:herculex/features/nutrition/presentation/views/nutrition_targets_view.dart';
import 'package:herculex/features/nutrition/presentation/views/weekly_calories_view.dart';
import 'package:herculex/features/onboarding/presentation/onboarding_view.dart';
import 'package:herculex/features/physique/presentation/views/physique_progress_view.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:herculex/features/profile/presentation/custom_foods_view.dart';
import 'package:herculex/features/profile/presentation/custom_recipes_view.dart';
import 'package:herculex/features/profile/presentation/dream_physique_history_view.dart';
import 'package:herculex/features/profile/presentation/dream_physique_priorities_view.dart';
import 'package:herculex/features/profile/presentation/dream_physique_view.dart';
import 'package:herculex/features/profile/presentation/profile_view.dart';
import 'package:herculex/features/programs/presentation/views/rotation_pools_view.dart';
import 'package:herculex/features/recovery/presentation/recovery_view.dart';
import 'package:herculex/features/shell/main_scaffold.dart';
import 'package:herculex/features/shell/splash_view.dart';
import 'package:herculex/features/supplements/presentation/supplements_view.dart';
import 'package:herculex/features/weekly_report/domain/iso_week.dart';
import 'package:herculex/features/weekly_report/presentation/views/weekly_report_view.dart';
import 'package:herculex/features/weekly_report/presentation/views/weekly_reports_history_view.dart';
import 'package:herculex/features/workouts/presentation/views/exercise_details_view.dart';
import 'package:herculex/features/workouts/presentation/views/exercise_library_view.dart';
import 'package:herculex/features/workouts/presentation/views/micro_workouts_view.dart';
import 'package:herculex/features/workouts/presentation/views/planned_workout_preview_view.dart';
import 'package:herculex/features/workouts/presentation/views/workout_history_view.dart';

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
      onGoHome: () => context.go(AppRoutes.app),
    );

/// Builder of [AppRoutes.weeklyReport]. Both path parameters are untrusted
/// (deep links, restored routes): a non-number or an impossible ISO week (week
/// 0, week 99, week 53 in a 52-week year) shows the bad-parameter screen and
/// never reaches the report view.
@visibleForTesting
Widget buildWeeklyReportRoute(BuildContext context, GoRouterState state) {
  final year = _intParam(state, 'isoYear');
  final week = _intParam(state, 'isoWeek');
  if (year == null) return _badParam(context, state, 'isoYear');
  if (week == null) return _badParam(context, state, 'isoWeek');
  final isoWeek = IsoWeek.tryCreate(year, week);
  if (isoWeek == null) return _badParam(context, state, 'isoWeek');
  return WeeklyReportView(week: isoWeek);
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: refresh,
    // Unmatched paths and malformed deep links used to fall through to
    // go_router's bare default screen; a throw inside a route builder had no
    // boundary at all.
    errorBuilder: (context, state) => AppErrorScreen(
      message: state.error?.toString() ?? 'No screen matches ${state.uri}.',
      onGoHome: () => context.go(AppRoutes.app),
    ),
    redirect: (context, state) {
      // On-device only: the only gate is whether onboarding has produced a
      // local profile. No accounts, no sign-in.
      final profileAsync = ref.read(profileProvider);
      final loc = state.matchedLocation;

      // While the profile is still loading from disk, sit on /splash.
      if (profileAsync.isLoading) {
        return loc == AppRoutes.splash ? null : AppRoutes.splash;
      }

      final profile = profileAsync.asData?.value;

      // No profile yet → onboarding is the only valid destination.
      if (profile == null) {
        return loc == AppRoutes.onboarding ? null : AppRoutes.onboarding;
      }

      // Onboarded: bounce out of splash/onboarding into the app.
      if (loc == AppRoutes.splash || loc == AppRoutes.onboarding) {
        return AppRoutes.app;
      }
      return null;
    },
    routes: [
      GoRoute(path: AppRoutes.splash, builder: (_, _) => const SplashView()),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (_, _) => const OnboardingView(),
      ),
      GoRoute(path: AppRoutes.app, builder: (_, _) => const MainScaffold()),
      GoRoute(
        path: AppRoutes.workoutHistory,
        builder: (context, state) {
          final id = _intParam(state, 'id');
          if (id == null) return _badParam(context, state, 'id');
          return WorkoutHistoryView(sessionId: id);
        },
      ),
      GoRoute(
        path: AppRoutes.plannedWorkoutPreview,
        builder: (context, state) {
          final id = _intParam(state, 'id');
          if (id == null) return _badParam(context, state, 'id');
          return PlannedWorkoutPreviewView(scheduleId: id);
        },
      ),
      GoRoute(
        path: AppRoutes.exercise,
        builder: (context, state) {
          final id = _intParam(state, 'id');
          if (id == null) return _badParam(context, state, 'id');
          return ExerciseDetailsView(exerciseId: id);
        },
      ),
      GoRoute(
        path: AppRoutes.measurements,
        builder: (_, _) => const MeasurementsView(),
      ),
      GoRoute(
        path: AppRoutes.measurementDetail,
        builder: (_, state) =>
            MetricDetailView(metric: state.pathParameters['metric']!),
      ),
      GoRoute(path: AppRoutes.fasting, builder: (_, _) => const FastingView()),
      GoRoute(
        path: AppRoutes.fastingSchedule,
        builder: (_, _) => const FastingScheduleView(),
      ),
      GoRoute(path: AppRoutes.gyms, builder: (_, _) => const GymsView()),
      GoRoute(
        path: AppRoutes.microWorkouts,
        builder: (_, _) => const MicroWorkoutsView(),
      ),
      GoRoute(
        path: AppRoutes.exercises,
        builder: (_, _) => const ExerciseLibraryView(),
      ),
      GoRoute(
        path: AppRoutes.insights,
        builder: (_, _) => const InsightsView(),
      ),
      GoRoute(path: AppRoutes.cns, builder: (_, _) => const CnsView()),
      GoRoute(
        path: AppRoutes.weeklyReports,
        builder: (_, _) => const WeeklyReportsHistoryView(),
      ),
      GoRoute(path: AppRoutes.weeklyReport, builder: buildWeeklyReportRoute),
      GoRoute(
        path: AppRoutes.recovery,
        builder: (_, _) => const RecoveryView(),
      ),
      GoRoute(
        path: AppRoutes.personalRecords,
        builder: (_, _) => const PersonalRecordsView(),
      ),
      GoRoute(
        path: AppRoutes.supplements,
        builder: (_, _) => const SupplementsView(),
      ),
      GoRoute(
        path: AppRoutes.muscleVolume,
        builder: (_, _) => const MuscleVolumeOverviewView(),
      ),
      GoRoute(
        path: AppRoutes.muscleVolumeDetail,
        builder: (_, state) =>
            MuscleVolumeDetailView(muscle: state.pathParameters['muscle']!),
      ),
      GoRoute(
        path: AppRoutes.health,
        builder: (_, _) => const HealthIntegrationsView(),
      ),
      GoRoute(
        path: AppRoutes.cycle,
        builder: (_, _) => const CycleTrackingView(),
      ),
      GoRoute(
        path: AppRoutes.healthSamsung,
        builder: (_, _) =>
            const HealthPlatformDetailView(platform: HealthPlatform.samsung),
      ),
      GoRoute(
        path: AppRoutes.healthApple,
        builder: (_, _) =>
            const HealthPlatformDetailView(platform: HealthPlatform.apple),
      ),
      GoRoute(
        path: AppRoutes.healthGoogle,
        builder: (_, _) =>
            const HealthPlatformDetailView(platform: HealthPlatform.google),
      ),
      GoRoute(path: AppRoutes.profile, builder: (_, _) => const ProfileView()),
      GoRoute(
        path: AppRoutes.trainingLevel,
        builder: (_, _) => const TrainingLevelView(),
      ),
      GoRoute(
        path: AppRoutes.notifications,
        builder: (_, _) => const NotificationSettingsView(),
      ),
      GoRoute(
        path: AppRoutes.dreamPhysique,
        builder: (_, _) => const DreamPhysiqueView(),
      ),
      GoRoute(
        path: AppRoutes.dreamPhysiquePriorities,
        builder: (_, _) => const DreamPhysiquePrioritiesView(),
      ),
      GoRoute(
        path: AppRoutes.dreamPhysiqueHistory,
        builder: (_, _) => const DreamPhysiqueHistoryView(),
      ),
      GoRoute(
        path: AppRoutes.dreamPhysiqueProgress,
        builder: (_, state) => PhysiqueProgressView(
          goalId: int.tryParse(state.uri.queryParameters['goalId'] ?? ''),
        ),
      ),
      GoRoute(
        path: AppRoutes.customFoods,
        builder: (_, _) => const CustomFoodsView(),
      ),
      GoRoute(
        path: AppRoutes.customRecipes,
        builder: (_, _) => const CustomRecipesView(),
      ),
      GoRoute(
        path: AppRoutes.nutritionTargets,
        builder: (_, state) =>
            NutritionTargetsView(initialPhase: state.extra as DietPhase?),
      ),
      GoRoute(
        path: AppRoutes.nutritionMealSlots,
        builder: (_, _) => const MealSlotsView(),
      ),
      GoRoute(
        path: AppRoutes.nutritionNutrients,
        builder: (_, _) => const NutrientSettingsView(),
      ),
      GoRoute(
        path: AppRoutes.nutrientOverview,
        builder: (_, _) => const NutrientOverviewView(),
      ),
      GoRoute(
        path: AppRoutes.nutritionWeeklyStats,
        builder: (_, _) => const WeeklyCaloriesView(),
      ),
      GoRoute(
        path: AppRoutes.macroTrends,
        builder: (_, state) =>
            MacroTrendView(macro: state.pathParameters['macro'] ?? 'kcal'),
      ),
      GoRoute(path: AppRoutes.goals, builder: (_, _) => const GoalsView()),
      GoRoute(
        path: AppRoutes.calorieMacroGoals,
        builder: (_, _) => const CalorieMacroGoalsView(),
      ),
      GoRoute(
        path: AppRoutes.calorieMealGoals,
        builder: (_, _) => const CalorieMealGoalsView(),
      ),
      GoRoute(
        path: AppRoutes.rotationPools,
        builder: (_, _) => const RotationPoolsView(),
      ),
      GoRoute(
        path: AppRoutes.buddyJoin,
        builder: (_, _) => const BuddyJoinScannerView(),
      ),
      // Deliberately *not* behind kDebugMode: release is where an error is
      // otherwise invisible (blank ErrorWidget, no reporter), so this has to
      // be reachable there. Read-only, and holds nothing the user didn't
      // already generate on their own device.
      GoRoute(
        path: AppRoutes.diagnosticsErrors,
        builder: (_, _) => const ErrorLogView(),
      ),
      // Developer-only content tools. Excluded from release builds entirely.
      if (kDebugMode) ...[
        GoRoute(
          path: AppRoutes.admin,
          builder: (_, _) => const AdminDashboardView(),
        ),
        GoRoute(
          path: AppRoutes.adminWorkout,
          builder: (_, _) => const AdminInsertWorkoutView(),
        ),
        GoRoute(
          path: AppRoutes.adminRecipe,
          builder: (_, _) => const AdminInsertRecipeView(),
        ),
      ],
    ],
  );
});
