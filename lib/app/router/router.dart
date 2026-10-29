import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/core/error/app_error_view.dart';
import 'package:herculex/core/error/error_log_view.dart';
import 'package:herculex/core/platform/platform_capabilities.dart';
import 'package:herculex/design_system/components/hx_rail_frame.dart';
import 'package:herculex/features/admin/presentation/admin_dashboard_view.dart';
import 'package:herculex/features/admin/presentation/admin_insert_recipe_view.dart';
import 'package:herculex/features/admin/presentation/admin_insert_workout_view.dart';
import 'package:herculex/features/analytics/presentation/views/cns_view.dart';
import 'package:herculex/features/analytics/presentation/views/insights_view.dart';
import 'package:herculex/features/analytics/presentation/views/muscle_volume_detail_view.dart';
import 'package:herculex/features/analytics/presentation/views/muscle_volume_overview_view.dart';
import 'package:herculex/features/analytics/presentation/views/personal_records_view.dart';
import 'package:herculex/features/auth/domain/auth_session.dart';
import 'package:herculex/features/auth/presentation/reset_password_view.dart';
import 'package:herculex/features/auth/presentation/sign_in_view.dart';
import 'package:herculex/features/buddy/presentation/buddy_join_scanner_view.dart';
import 'package:herculex/features/buddy/presentation/gym_buddy_hub_view.dart';
import 'package:herculex/features/fasting/presentation/fasting_history_view.dart';
import 'package:herculex/features/fasting/presentation/fasting_schedule_view.dart';
import 'package:herculex/features/fasting/presentation/fasting_view.dart';
import 'package:herculex/features/gamification/presentation/level_system_view.dart';
import 'package:herculex/features/gamification/presentation/training_level_view.dart';
import 'package:herculex/features/gyms/presentation/gyms_view.dart';
import 'package:herculex/features/health/presentation/cycle_tracking_view.dart';
import 'package:herculex/features/health/presentation/health_integrations_view.dart';
import 'package:herculex/features/health/presentation/health_platform_detail_view.dart';
import 'package:herculex/features/hercul/presentation/views/hercul_insights_report_view.dart';
import 'package:herculex/features/labs/presentation/labs_view.dart';
import 'package:herculex/features/measurements/presentation/measurements_view.dart';
import 'package:herculex/features/measurements/presentation/metric_detail_view.dart';
import 'package:herculex/features/notifications/presentation/notification_settings_view.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/nutrition/presentation/views/activity_calibration_view.dart';
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
import 'package:herculex/features/physique/presentation/views/physique_roadmap_view.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:herculex/features/profile/presentation/custom_foods_view.dart';
import 'package:herculex/features/profile/presentation/custom_recipes_view.dart';
import 'package:herculex/features/profile/presentation/dream_physique_history_view.dart';
import 'package:herculex/features/profile/presentation/dream_physique_priorities_view.dart';
import 'package:herculex/features/profile/presentation/dream_physique_view.dart';
import 'package:herculex/features/profile/presentation/profile_view.dart';
import 'package:herculex/features/programs/presentation/views/rotation_pools_view.dart';
import 'package:herculex/features/recovery/presentation/recovery_view.dart';
import 'package:herculex/features/settings/presentation/account_settings_view.dart';
import 'package:herculex/features/settings/presentation/appearance_settings_view.dart';
import 'package:herculex/features/settings/presentation/data_library_settings_view.dart';
import 'package:herculex/features/settings/presentation/permissions_settings_view.dart';
import 'package:herculex/features/settings/presentation/preferences_settings_view.dart';
import 'package:herculex/features/settings/presentation/settings_view.dart';
import 'package:herculex/features/shell/main_scaffold.dart';
import 'package:herculex/features/shell/not_on_web_view.dart';
import 'package:herculex/features/shell/restoring_view.dart';
import 'package:herculex/features/shell/splash_view.dart';
import 'package:herculex/features/sleep/presentation/views/sleep_tracking_view.dart';
import 'package:herculex/features/steps/presentation/views/steps_tracking_view.dart';
import 'package:herculex/features/supplements/presentation/supplements_view.dart';
import 'package:herculex/features/weekly_report/domain/iso_week.dart';
import 'package:herculex/features/weekly_report/presentation/views/weekly_report_view.dart';
import 'package:herculex/features/weekly_report/presentation/views/weekly_reports_history_view.dart';
import 'package:herculex/features/workouts/presentation/views/exercise_details_view.dart';
import 'package:herculex/features/workouts/presentation/views/exercise_library_view.dart';
import 'package:herculex/features/workouts/presentation/views/micro_workouts_view.dart';
import 'package:herculex/features/workouts/presentation/views/planned_workout_preview_view.dart';
import 'package:herculex/features/workouts/presentation/views/set_types_guide_view.dart';
import 'package:herculex/features/workouts/presentation/views/workout_history_view.dart';

/// Bridges the Riverpod profile stream into a [Listenable] so
/// [GoRouter.refreshListenable] re-evaluates the redirect every time the local
/// profile changes (e.g. onboarding completes, or data is cleared).
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref, {required bool accountGated}) {
    ref.listen<AsyncValue<Profile?>>(
      profileProvider,
      (_, _) => notifyListeners(),
    );
    if (accountGated) {
      ref.listen<AsyncValue<AuthSession?>>(
        authSessionProvider,
        (_, _) => notifyListeners(),
      );
      ref.listen<AsyncValue<bool>>(
        initialSyncReadyProvider,
        (_, _) => notifyListeners(),
      );
    }
  }
}

/// A `from` query parameter is untrusted input (it arrives in a URL): only an
/// in-app absolute path is honoured — never `//host` or `https://…`.
@visibleForTesting
String? safeRedirectTarget(String? from) {
  if (from == null || !from.startsWith('/') || from.startsWith('//')) {
    return null;
  }
  return from;
}

String? _safeFrom(GoRouterState state) =>
    safeRedirectTarget(state.uri.queryParameters['from']);

String _withFrom(String path, String? from) => from == null
    ? path
    : Uri(path: path, queryParameters: {'from': from}).toString();

/// Outcome of the web gates: [_WebGate.pass] hands the request on to the
/// profile gate; otherwise the redirect is final — `to == null` means "stay
/// here". The distinction matters: the profile gate bounces /sign-in and
/// /restoring to the app, which would loop straight back here.
typedef _WebGate = ({bool decided, String? to});

const _WebGate _pass = (decided: false, to: null);
_WebGate _stay() => (decided: true, to: null);
_WebGate _go(String to) => (decided: true, to: to);

/// The web build's gates, ahead of the profile gate every build has: a
/// session, then a completed first pull.
_WebGate _webAccountGate(Ref ref, GoRouterState state) {
  final loc = state.matchedLocation;
  final auth = ref.read(authSessionProvider);
  if (auth.isLoading && !auth.hasValue) {
    return loc == AppRoutes.splash ? _stay() : _go(AppRoutes.splash);
  }

  if (auth.valueOrNull == null) {
    if (loc == AppRoutes.signIn) return _stay();
    // Remember a deep link (a bookmarked /insights, a shared report) so
    // signing in lands there instead of on the dashboard.
    final from =
        const {
          AppRoutes.root,
          AppRoutes.splash,
          AppRoutes.app,
          AppRoutes.onboarding,
          AppRoutes.restoring,
          AppRoutes.resetPassword,
        }.contains(loc)
        ? null
        : state.uri.toString();
    return _go(_withFrom(AppRoutes.signIn, from));
  }

  // The password-reset link signs the user in with a recovery session; they
  // choose the new password before anything else happens.
  if (loc == AppRoutes.resetPassword) return _stay();

  final ready = ref.read(initialSyncReadyProvider).valueOrNull ?? false;
  if (!ready) {
    if (loc == AppRoutes.restoring) return _stay();
    final from = loc == AppRoutes.signIn ? _safeFrom(state) : null;
    return _go(_withFrom(AppRoutes.restoring, from));
  }
  return _pass;
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

/// Root navigator key used for imperative navigation, modal sheets, and dialogs
/// triggered from external intents (widgets, shortcuts, notifications).
final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'rootNavigator');

/// Screens that only work on a phone (a health store, notifications, the
/// camera-driven Gym Buddy join). The web build
/// redirects them to [NotOnWebView] instead of letting them fail against a
/// missing plugin.
@visibleForTesting
const nativeOnlyRoutes = <String>{
  AppRoutes.health,
  AppRoutes.healthSamsung,
  AppRoutes.healthApple,
  AppRoutes.healthGoogle,
  AppRoutes.steps,
  AppRoutes.sleep,
  AppRoutes.notifications,
  AppRoutes.settingsPermissions,
  AppRoutes.gymBuddy,
  AppRoutes.buddyJoin,
};

final routerProvider = Provider<GoRouter>((ref) {
  final caps = ref.read(platformCapabilitiesProvider);
  final accountGated = ref.read(accountRequiredProvider);
  final refresh = _RouterRefresh(ref, accountGated: accountGated);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
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
      // The web requires an account and a restored database first. Phones
      // are on-device: the only gate is whether onboarding has produced a
      // local profile. No accounts, no sign-in.
      if (accountGated) {
        final gate = _webAccountGate(ref, state);
        if (gate.decided) return gate.to;
      }

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

      // Onboarded: bounce out of splash/onboarding (and, on the web, the
      // sign-in and restoring screens) into the app — or back to the deep
      // link that sent the user to sign in.
      if (loc == AppRoutes.splash ||
          loc == AppRoutes.onboarding ||
          loc == AppRoutes.signIn ||
          loc == AppRoutes.restoring) {
        return _safeFrom(state) ?? AppRoutes.app;
      }
      if (caps.isWeb && nativeOnlyRoutes.contains(loc)) {
        return AppPaths.notOnWeb(loc);
      }
      return null;
    },
    routes: [
      // The web starts from whatever path the browser opened; a bare domain
      // is `/`, which nothing else matches.
      GoRoute(path: AppRoutes.root, redirect: (_, _) => AppRoutes.app),
      GoRoute(path: AppRoutes.splash, builder: (_, _) => const SplashView()),
      GoRoute(
        path: AppRoutes.notOnWeb,
        builder: (_, state) =>
            NotOnWebView(from: state.uri.queryParameters['from']),
      ),
      GoRoute(path: AppRoutes.signIn, builder: (_, _) => const SignInView()),
      GoRoute(
        path: AppRoutes.resetPassword,
        builder: (_, _) => const ResetPasswordView(),
      ),
      GoRoute(
        path: AppRoutes.restoring,
        builder: (_, _) => const RestoringView(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (_, _) => const OnboardingView(),
      ),
      GoRoute(
        path: AppRoutes.app,
        pageBuilder: (context, state) =>
            NoTransitionPage(key: state.pageKey, child: const MainScaffold()),
      ),
      GoRoute(
        path: AppRoutes.labs,
        pageBuilder: (context, state) =>
            NoTransitionPage(key: state.pageKey, child: const LabsView()),
      ),
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
        pageBuilder: (context, state) => NoTransitionPage(
          key: state.pageKey,
          child: const MeasurementsView(),
        ),
      ),
      GoRoute(
        path: AppRoutes.measurementDetail,
        builder: (_, state) =>
            MetricDetailView(metric: state.pathParameters['metric']!),
      ),
      GoRoute(
        path: AppRoutes.fasting,
        pageBuilder: (context, state) =>
            NoTransitionPage(key: state.pageKey, child: const FastingView()),
      ),
      GoRoute(
        path: AppRoutes.fastingSchedule,
        builder: (_, _) => const FastingScheduleView(),
      ),
      GoRoute(
        path: AppRoutes.fastingHistory,
        builder: (_, _) => const FastingHistoryView(),
      ),
      GoRoute(path: AppRoutes.gyms, builder: (_, _) => const GymsView()),
      GoRoute(
        path: AppRoutes.microWorkouts,
        builder: (_, _) => const MicroWorkoutsView(),
      ),
      GoRoute(
        path: AppRoutes.exercises,
        pageBuilder: (context, state) => NoTransitionPage(
          key: state.pageKey,
          child: const ExerciseLibraryView(),
        ),
      ),
      GoRoute(
        path: AppRoutes.setTypesGuide,
        builder: (_, state) =>
            SetTypesGuideView(highlight: state.uri.queryParameters['type']),
      ),
      GoRoute(
        path: AppRoutes.insights,
        pageBuilder: (context, state) =>
            NoTransitionPage(key: state.pageKey, child: const InsightsView()),
      ),
      GoRoute(
        path: AppRoutes.herculInsights,
        builder: (_, _) => const HxRailFrame(child: HerculInsightsReportView()),
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
        pageBuilder: (context, state) => NoTransitionPage(
          key: state.pageKey,
          child: const SupplementsView(),
        ),
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
        path: AppRoutes.steps,
        builder: (_, _) => const StepsTrackingView(),
      ),
      GoRoute(
        path: AppRoutes.sleep,
        builder: (_, _) => const SleepTrackingView(),
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
        path: AppRoutes.levelSystem,
        builder: (_, _) => const LevelSystemView(),
      ),
      GoRoute(
        path: AppRoutes.notifications,
        builder: (_, _) => const NotificationSettingsView(),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (_, _) => const SettingsView(),
      ),
      GoRoute(
        path: AppRoutes.settingsAppearance,
        builder: (_, _) => const AppearanceSettingsView(),
      ),
      GoRoute(
        path: AppRoutes.settingsPermissions,
        builder: (_, _) => const PermissionsSettingsView(),
      ),
      GoRoute(
        path: AppRoutes.settingsPreferences,
        builder: (_, _) => const PreferencesSettingsView(),
      ),
      GoRoute(
        path: AppRoutes.settingsData,
        builder: (_, _) => const DataLibrarySettingsView(),
      ),
      GoRoute(
        path: AppRoutes.settingsAccount,
        builder: (_, _) => const AccountSettingsView(),
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
        path: AppRoutes.dreamPhysiqueRoadmap,
        builder: (_, state) => PhysiqueRoadmapView(
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
        path: AppRoutes.activityCalibration,
        builder: (_, _) => const ActivityCalibrationView(),
      ),
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
        path: AppRoutes.gymBuddy,
        builder: (_, _) => const GymBuddyHubView(),
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
