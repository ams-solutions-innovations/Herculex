package com.ams.herculex

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.navigation.SwipeDismissableNavHost
import androidx.wear.compose.navigation.composable
import androidx.wear.compose.navigation.rememberSwipeDismissableNavController
import com.ams.herculex.home.HomeScreen
import com.ams.herculex.nutrition.AddCaloriesScreen
import com.ams.herculex.nutrition.AddWaterScreen
import com.ams.herculex.nutrition.FastingScreen
import com.ams.herculex.nutrition.LogFoodAmountScreen
import com.ams.herculex.nutrition.LogFoodMealPickerScreen
import com.ams.herculex.nutrition.LogFoodScreen
import com.ams.herculex.nutrition.NutritionScreen
import com.ams.herculex.nutrition.NutritionViewModel
import com.ams.herculex.nutrition.NutrientsScreen
import com.ams.herculex.nutrition.NutrientTrendScreen
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import com.ams.herculex.workout.ActiveWorkoutScreen
import com.ams.herculex.workout.ExerciseOptionsScreen
import com.ams.herculex.workout.ManageExerciseScreen
import com.ams.herculex.workout.PrCelebrationOverlay
import com.ams.herculex.workout.SelectExerciseScreen
import com.ams.herculex.workout.SetLoggerScreen
import com.ams.herculex.workout.WeeklyVolumeScreen
import com.ams.herculex.workout.WorkoutDetailScreen
import com.ams.herculex.workout.WorkoutListScreen
import com.ams.herculex.workout.WorkoutSummaryScreen
import com.ams.herculex.workout.WorkoutViewModel
import androidx.compose.ui.Modifier
import kotlinx.coroutines.flow.MutableStateFlow

class MainActivity : ComponentActivity() {
    // Notification-tap "open the active workout" signal, tracked as a
    // MutableStateFlow Compose actually observes (ENG-15) — the bare
    // `intent` field `onNewIntent` used to update via `setIntent()` isn't
    // observable state, so `LaunchedEffect(intent)`/`LaunchedEffect
    // (activeSession != null)` never re-ran on a second tap while the
    // Activity was already alive (`FLAG_ACTIVITY_SINGLE_TOP` reuses the same
    // instance, no recomposition was otherwise triggered). Incremented, not
    // boolean, so a tap while already viewing the active workout screen
    // still forces the effect below to rerun instead of being suppressed by
    // an unchanged key.
    private val openActiveWorkoutRequests = MutableStateFlow(0L)
    private val pendingRoute = MutableStateFlow<String?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            if (checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 101)
            }
        }

        consumeIntentExtras(intent)

        setContent {
            MaterialTheme {
                val navController      = rememberSwipeDismissableNavController()
                val nutritionViewModel: NutritionViewModel = viewModel()
                val workoutViewModel:   WorkoutViewModel   = viewModel()
                val activeSession by workoutViewModel.session.collectAsState()
                val prCelebration by workoutViewModel.prCelebration.collectAsState()
                val openWorkoutRequest by openActiveWorkoutRequests.collectAsState()
                val targetRoute by pendingRoute.collectAsState()

                LaunchedEffect(targetRoute) {
                    targetRoute?.let { route ->
                        if (route == "quick_workout") {
                            workoutViewModel.startEmptyWorkout()
                            navController.navigate("active_workout")
                        } else {
                            navController.navigate(route)
                        }
                        pendingRoute.value = null
                    }
                }

                var lastNavigatedSessionId by remember { mutableStateOf<String?>(null) }
                var lastHandledOpenRequest by remember { mutableStateOf(0L) }

                LaunchedEffect(activeSession?.template?.id, openWorkoutRequest) {
                    val currentSession = activeSession
                    if (currentSession != null) {
                        try {
                            val intent = android.content.Intent(applicationContext, com.ams.herculex.workout.WorkoutOngoingService::class.java).apply {
                                putExtra(com.ams.herculex.workout.WorkoutOngoingService.EXTRA_START_EPOCH_MS, com.ams.herculex.workout.WorkoutStore.getActiveSessionStartEpoch(applicationContext) ?: System.currentTimeMillis())
                                putExtra(com.ams.herculex.workout.WorkoutOngoingService.EXTRA_WORKOUT_TITLE, currentSession.template.name)
                                val curEx = currentSession.exercises.getOrNull(currentSession.currentExerciseIndex)
                                if (curEx != null) {
                                    putExtra(com.ams.herculex.workout.WorkoutOngoingService.EXTRA_EXERCISE_NAME, curEx.template.name)
                                }
                            }
                            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                                applicationContext.startForegroundService(intent)
                            } else {
                                applicationContext.startService(intent)
                            }
                        } catch (e: Exception) {
                            android.util.Log.e("MainActivity", "Failed to start ongoing service", e)
                        }

                        val isNewSession = currentSession.template.id != lastNavigatedSessionId
                        val isExplicitRequest = openWorkoutRequest > lastHandledOpenRequest

                        if (isNewSession || isExplicitRequest) {
                            lastNavigatedSessionId = currentSession.template.id
                            lastHandledOpenRequest = openWorkoutRequest
                            navController.navigate("active_workout") {
                                launchSingleTop = true
                            }
                        }
                    } else {
                        lastNavigatedSessionId = null
                    }
                }

                Box(modifier = Modifier.fillMaxSize()) {
                    SwipeDismissableNavHost(
                        navController    = navController,
                        startDestination = "home",
                    ) {
                        // ── Home hub ──────────────────────────────────────────────
                        composable("home") {
                            HomeScreen(navController, nutritionViewModel, workoutViewModel)
                        }

                        // ── Nutrition ─────────────────────────────────────────────
                        composable("nutrition") {
                            NutritionScreen(navController)
                        }
                        composable("nutrients") {
                            NutrientsScreen(navController, nutritionViewModel)
                        }
                        composable("nutrient_trend/{nutrient}") { backStack ->
                            val nutrient = backStack.arguments?.getString("nutrient").orEmpty()
                            NutrientTrendScreen(navController, nutritionViewModel, nutrient)
                        }
                        composable("rambler_voice") {
                            com.ams.herculex.nutrition.RamblerScreen(navController, nutritionViewModel, autoStartSpeech = true)
                        }
                        composable("rambler_voice/{mealKey}") { backStack ->
                            val meal = backStack.arguments?.getString("mealKey")
                            com.ams.herculex.nutrition.RamblerScreen(navController, nutritionViewModel, initialMealKey = meal, autoStartSpeech = true)
                        }
                        composable("log_food") {
                            LogFoodScreen(navController, nutritionViewModel)
                        }
                        composable("log_food_amount") {
                            LogFoodAmountScreen(navController, nutritionViewModel)
                        }
                        composable("log_food_meal") {
                            LogFoodMealPickerScreen(navController, nutritionViewModel)
                        }
                        composable("add_calories") {
                            AddCaloriesScreen(navController, nutritionViewModel)
                        }
                        composable("add_water") {
                            AddWaterScreen(navController, nutritionViewModel)
                        }
                        composable("fasting") {
                            FastingScreen(navController, nutritionViewModel)
                        }

                        // ── Workouts ──────────────────────────────────────────────
                        composable("workout_list") {
                            WorkoutListScreen(navController, workoutViewModel)
                        }
                        composable("workout_detail/{workoutId}") { backStack ->
                            val id = backStack.arguments?.getString("workoutId").orEmpty()
                            WorkoutDetailScreen(navController, workoutViewModel, id)
                        }
                        composable("active_workout") {
                            ActiveWorkoutScreen(navController, workoutViewModel)
                        }
                        composable("set_logger/{exerciseIndex}") { backStack ->
                            val idx = backStack.arguments?.getString("exerciseIndex")?.toIntOrNull() ?: 0
                            SetLoggerScreen(navController, workoutViewModel, idx)
                        }
                        composable("exercise_options") {
                            ExerciseOptionsScreen(navController, workoutViewModel)
                        }
                        composable("select_exercise/{mode}/{targetIndex}") { backStack ->
                            val mode = backStack.arguments?.getString("mode").orEmpty()
                            val targetIdx = backStack.arguments?.getString("targetIndex")?.toIntOrNull() ?: -1
                            SelectExerciseScreen(navController, workoutViewModel, mode, targetIdx)
                        }
                        composable("manage_exercise/{action}") { backStack ->
                            val action = backStack.arguments?.getString("action").orEmpty()
                            ManageExerciseScreen(navController, workoutViewModel, action)
                        }
                        composable("weekly_volume") {
                            WeeklyVolumeScreen(navController, nutritionViewModel)
                        }
                        composable("workout_summary") {
                            WorkoutSummaryScreen(navController, workoutViewModel)
                        }
                    }

                    // Global full-screen PR Trophy celebration overlay
                    prCelebration?.let { prEvent ->
                        PrCelebrationOverlay(
                            event = prEvent,
                            onDismiss = { workoutViewModel.dismissPrCelebration() },
                        )
                    }
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        consumeIntentExtras(intent)
    }

    /// Reads and clears `open_active_workout` and `route` extras
    private fun consumeIntentExtras(intent: Intent?) {
        if (intent?.getBooleanExtra("open_active_workout", false) == true) {
            intent.removeExtra("open_active_workout")
            openActiveWorkoutRequests.value += 1
        }
        intent?.getStringExtra("route")?.let { route ->
            intent.removeExtra("route")
            pendingRoute.value = route
        }
    }
}
