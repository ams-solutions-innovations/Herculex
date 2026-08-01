package com.ams.herculex.workout

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.Text

private val equipmentVariants = listOf(
    "Barbell",
    "Dumbbell",
    "Smith Machine",
    "Cable",
    "Machine (Plate-Loaded)",
    "Machine (Selectorized)",
    "Kettlebell",
    "Band",
    "Bodyweight",
    "Other",
)

private fun requiresEquipmentPrompt(name: String): Boolean {
    val lower = name.lowercase()
    return !lower.contains("db") &&
           !lower.contains("dumbbell") &&
           !lower.contains("barbell") &&
           !lower.contains("cable") &&
           !lower.contains("smith") &&
           !lower.contains("machine") &&
           !lower.contains("pull-up") &&
           !lower.contains("pull up") &&
           !lower.contains("push-up") &&
           !lower.contains("dips") &&
           !lower.contains("kettlebell") &&
           !lower.contains("good morning")
}

@Composable
fun SelectExerciseScreen(
    navController: NavController,
    viewModel: WorkoutViewModel,
    mode: String, // "add" or "substitute"
    targetIndex: Int,
) {
    val context = LocalContext.current
    var searchQuery by remember { mutableStateOf("") }
    var selectedExerciseTemplate by remember { mutableStateOf<ExerciseTemplate?>(null) }

    val allExercises = remember(searchQuery) { ExerciseCatalog.getAll(context) }
    val filteredExercises = remember(searchQuery, allExercises) {
        if (searchQuery.isBlank()) allExercises
        else allExercises.filter { it.name.contains(searchQuery, ignoreCase = true) }
    }

    val listState = rememberScalingLazyListState()

    if (selectedExerciseTemplate == null) {
        // Step 1: Pick Exercise Name from Catalog with Search
        ScalingLazyColumn(
            state = listState,
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black)
                .attachRotaryScroll(listState),
            autoCentering = null,
            contentPadding = PaddingValues(top = 10.dp, bottom = 20.dp, start = 10.dp, end = 10.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            item {
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Text(
                        text = if (mode == "substitute") "Substitute Exercise" else "Select Exercise",
                        color = Color.White,
                        fontWeight = FontWeight.Bold,
                        fontSize = 14.sp,
                        modifier = Modifier.padding(bottom = 2.dp),
                    )
                }
            }

            // Search Bar Input
            item {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(Color(0xFF1C1C1E), shape = CircleShape)
                        .padding(horizontal = 14.dp, vertical = 8.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.Center,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text("🔍 ", fontSize = 12.sp)
                        BasicTextField(
                            value = searchQuery,
                            onValueChange = { searchQuery = it },
                            singleLine = true,
                            textStyle = TextStyle(color = Color.White, fontSize = 13.sp),
                            cursorBrush = SolidColor(Color(0xFF42A5F5)),
                            decorationBox = { innerTextField ->
                                if (searchQuery.isEmpty()) {
                                    Text("Search...", color = Color(0xFF757575), fontSize = 13.sp)
                                }
                                innerTextField()
                            }
                        )
                    }
                }
            }

            items(filteredExercises) { exTemplate ->
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(Color(0xFF1C1C1E), shape = CircleShape)
                        .clickable {
                            if (requiresEquipmentPrompt(exTemplate.name)) {
                                selectedExerciseTemplate = exTemplate
                            } else {
                                if (mode == "substitute" && targetIndex >= 0) {
                                    viewModel.substituteExerciseInSession(targetIndex, exTemplate)
                                } else {
                                    viewModel.addExerciseToSession(exTemplate)
                                }
                                navController.popBackStack()
                            }
                        }
                        .padding(horizontal = 14.dp, vertical = 10.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        exTemplate.name,
                        color = Color.White,
                        fontWeight = FontWeight.Medium,
                        fontSize = 13.sp,
                    )
                }
            }
        }
    } else {
        // Step 2: Equipment Variant Selection ("Which equipment?")
        val baseTemplate = selectedExerciseTemplate!!

        ScalingLazyColumn(
            state = listState,
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black)
                .attachRotaryScroll(listState),
            autoCentering = null,
            contentPadding = PaddingValues(top = 10.dp, bottom = 20.dp, start = 10.dp, end = 10.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            item {
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Text(
                        text = baseTemplate.name,
                        color = Color.White,
                        fontWeight = FontWeight.Bold,
                        fontSize = 14.sp,
                    )
                    Spacer(Modifier.height(2.dp))
                    Text(
                        text = "Which equipment?",
                        color = Color(0xFF9E9E9E),
                        fontSize = 11.sp,
                        modifier = Modifier.padding(bottom = 2.dp),
                    )
                }
            }

            items(equipmentVariants) { eqLabel ->
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(Color(0xFF1C1C1E), shape = CircleShape)
                        .clickable {
                            val finalName = "${baseTemplate.name} ($eqLabel)"
                            val finalTemplate = baseTemplate.copy(name = finalName)
                            if (mode == "substitute" && targetIndex >= 0) {
                                viewModel.substituteExerciseInSession(targetIndex, finalTemplate)
                            } else {
                                viewModel.addExerciseToSession(finalTemplate)
                            }
                            navController.popBackStack()
                        }
                        .padding(horizontal = 14.dp, vertical = 10.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        eqLabel,
                        color = Color.White,
                        fontWeight = FontWeight.Medium,
                        fontSize = 13.sp,
                    )
                }
            }
        }
    }
}
