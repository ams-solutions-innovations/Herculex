package com.ams.herculex

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.navigation.SwipeDismissableNavHost
import androidx.wear.compose.navigation.composable
import androidx.wear.compose.navigation.rememberSwipeDismissableNavController
import com.ams.herculex.home.HomeScreen
import com.ams.herculex.nutrition.AddCaloriesScreen
import com.ams.herculex.nutrition.AddWaterScreen
import com.ams.herculex.nutrition.FastingScreen
import com.ams.herculex.nutrition.LogFoodMealPickerScreen
import com.ams.herculex.nutrition.LogFoodScreen
import com.ams.herculex.nutrition.NutritionScreen
import com.ams.herculex.nutrition.NutritionViewModel
import com.ams.herculex.nutrition.NutrientsScreen
import com.ams.herculex.workout.ActiveWorkoutScreen
import com.ams.herculex.workout.ExerciseOptionsScreen
import com.ams.herculex.workout.ManageExerciseScreen
import com.ams.herculex.workout.SelectExerciseScreen
import com.ams.herculex.workout.SetLoggerScreen
import com.ams.herculex.workout.WeeklyVolumeScreen
import com.ams.herculex.workout.WorkoutDetailScreen
import com.ams.herculex.workout.WorkoutListScreen
import com.ams.herculex.workout.WorkoutViewModel

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            if (checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 101)
            }
        }

        setContent {
            MaterialTheme {
                val navController      = rememberSwipeDismissableNavController()
                val nutritionViewModel: NutritionViewModel = viewModel()
                val workoutViewModel:   WorkoutViewModel   = viewModel()
                val activeSession by workoutViewModel.session.collectAsState()

                LaunchedEffect(intent) {
                    intent?.getStringExtra("route")?.let { route ->
                        navController.navigate(route)
                        intent.removeExtra("route")
                    }
                }

                LaunchedEffect(activeSession != null) {
                    if (activeSession != null) {
                        try {
                            val intent = android.content.Intent(applicationContext, com.ams.herculex.workout.WorkoutOngoingService::class.java).apply {
                                val s = activeSession!!
                                putExtra(com.ams.herculex.workout.WorkoutOngoingService.EXTRA_START_EPOCH_MS, com.ams.herculex.workout.WorkoutStore.getActiveSessionStartEpoch(applicationContext) ?: System.currentTimeMillis())
                                putExtra(com.ams.herculex.workout.WorkoutOngoingService.EXTRA_WORKOUT_TITLE, s.template.name)
                                val curEx = s.exercises.getOrNull(s.currentExerciseIndex)
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

                        navController.navigate("active_workout") {
                            launchSingleTop = true
                        }
                    }
                }

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
                        NutrientsScreen(nutritionViewModel)
                    }
                    composable("log_food") {
                        LogFoodScreen(navController, nutritionViewModel)
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
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }
}
