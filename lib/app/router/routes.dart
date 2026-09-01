/// Every route path in the app, in one place.
///
/// Navigation used to spell paths as string literals at each of ~74 call
/// sites, which is how two of them silently drifted out of sync with the
/// route table and started landing users on `AppErrorScreen`:
/// `main_scaffold` pushed `/profile/dream-physique` against a route
/// registered as `/dream-physique`, and `rep_auto_count_tile` pushed
/// `/rep-tracking-consent`, which was never registered at all.
///
/// Both `GoRoute(path: ...)` and every `context.go`/`context.push` now read
/// from here, so a typo is a compile error rather than a runtime error
/// screen. Parameterised routes get a builder function instead of a bare
/// constant — that is what stops a caller from hand-assembling
/// `'/exercise/$id'` and getting the separator wrong.
library;

/// Route paths as registered with GoRouter.
///
/// Nested paths are spelled in full here (GoRouter is configured with a flat
/// route list, so the registered path and the navigable path are the same
/// string).
abstract final class AppRoutes {
  // Shell
  static const splash = '/splash';
  static const onboarding = '/onboarding';
  static const app = '/app';

  // Workouts
  static const workoutHistory = '/workout-history/:id';
  static const exercise = '/exercise/:id';
  static const exercises = '/exercises';
  static const microWorkouts = '/micro-workouts';
  static const gyms = '/gyms';

  // Body / measurements
  static const measurements = '/measurements';
  static const measurementDetail = '/measurements/:metric';

  // Fasting
  static const fasting = '/fasting';
  static const fastingSchedule = '/fasting/schedule';

  // Analytics
  static const insights = '/insights';
  static const cns = '/cns';
  static const recovery = '/recovery';
  static const muscleVolume = '/muscle-volume';
  static const muscleVolumeDetail = '/muscle-volume/:muscle';

  // Health
  static const health = '/health';
  static const cycle = '/cycle';
  static const healthSamsung = '/health/samsung';
  static const healthApple = '/health/apple';
  static const healthGoogle = '/health/google';

  // Profile
  static const profile = '/profile';
  static const notifications = '/notifications';
  static const dreamPhysique = '/dream-physique';

  // Nutrition
  static const customFoods = '/custom-foods';
  static const customRecipes = '/custom-recipes';
  static const nutritionTargets = '/nutrition-targets';
  static const nutritionMealSlots = '/nutrition-meal-slots';
  static const nutritionNutrients = '/nutrition-nutrients';
  static const nutrientOverview = '/nutrient-overview';
  static const nutritionWeeklyStats = '/nutrition/weekly-stats';
  static const macroTrends = '/macro-trends/:macro';
  static const goals = '/goals';
  static const calorieMacroGoals = '/calorie-macro-goals';
  static const calorieMealGoals = '/calorie-meal-goals';

  // Programs
  static const rotationPools = '/rotation-pools';

  // Buddy
  static const buddyJoin = '/buddy/join';

  // Assisted rep tracking
  //
  // rep_auto_count_tile.dart has been pushing this path with no matching
  // GoRoute, so tapping the tile landed on AppErrorScreen. Registered here;
  // the call site itself is deliberately left spelling the literal, because
  // lib/features/reps/ belongs to the in-flight GSD Phase 10 and should not
  // pick up merge conflicts from this refactor.
  static const repTrackingConsent = '/rep-tracking-consent';

  // Admin / diagnostics
  static const admin = '/admin';
  static const adminRecipe = '/admin/recipe';
  static const adminWorkout = '/admin/workout';
  static const adminFixtureRecording = '/admin/fixture-recording';
  static const diagnosticsErrors = '/diagnostics/errors';
}

/// Concrete paths for the parameterised routes.
///
/// Kept apart from [AppRoutes] because those constants carry GoRouter's
/// `:param` placeholders and are only ever correct in a `GoRoute(path:)`.
/// Passing one to `context.push` would navigate to the literal `:id`.
abstract final class AppPaths {
  static String workoutHistory(int id) => '/workout-history/$id';
  static String exercise(int id) => '/exercise/$id';
  static String measurementDetail(String metric) => '/measurements/$metric';
  static String muscleVolumeDetail(String muscle) => '/muscle-volume/$muscle';
  static String macroTrends(String macro) => '/macro-trends/$macro';
}
