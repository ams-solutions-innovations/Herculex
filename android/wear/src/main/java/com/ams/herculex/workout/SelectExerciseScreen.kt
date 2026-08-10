package com.ams.herculex.workout

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.runtime.Composable
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
import com.ams.herculex.ui.OneUiPill
import com.ams.herculex.ui.OneUiPillStyle

/// Equipment the phone says this exercise can actually be performed with.
///
/// Replaces a hardcoded ten-item list gated by a name-substring heuristic,
/// which offered a Barbell option on a selectorized leg curl and prompted or
/// skipped based on whether the word "machine" happened to appear in the
/// name. A single option means there is nothing to ask about.
private fun equipmentPromptOptions(template: ExerciseTemplate): List<String> =
    template.equipmentOptions.takeIf { it.size > 1 } ?: emptyList()

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
            contentPadding = PaddingValues(top = 40.dp, bottom = 48.dp, start = 14.dp, end = 14.dp),
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

            // Search Bar One UI Stadium Input
            item {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(min = 48.dp)
                        .background(Color(0xFF202636), shape = CircleShape)
                        .border(1.dp, Color(0xFF323B52), CircleShape)
                        .padding(horizontal = 12.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(
                        modifier = Modifier
                            .size(32.dp)
                            .background(Color(0xFF141926), shape = CircleShape),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text("🔍", fontSize = 13.sp)
                    }
                    Spacer(Modifier.width(8.dp))
                    BasicTextField(
                        value = searchQuery,
                        onValueChange = { searchQuery = it },
                        singleLine = true,
                        textStyle = TextStyle(color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.Medium),
                        cursorBrush = SolidColor(Color(0xFF42A5F5)),
                        decorationBox = { innerTextField ->
                            if (searchQuery.isEmpty()) {
                                Text("Search...", color = Color(0xFFA0AABF), fontSize = 13.sp)
                            }
                            innerTextField()
                        }
                    )
                }
            }

            items(filteredExercises) { exTemplate ->
                OneUiPill(
                    title = exTemplate.name,
                    icon = "🏋️",
                    style = OneUiPillStyle.SlateNavy,
                    onClick = {
                        if (equipmentPromptOptions(exTemplate).isNotEmpty()) {
                            selectedExerciseTemplate = exTemplate
                        } else {
                            if (mode == "substitute" && targetIndex >= 0) {
                                viewModel.substituteExerciseInSession(targetIndex, exTemplate)
                            } else {
                                viewModel.addExerciseToSession(exTemplate)
                            }
                            navController.popBackStack()
                        }
                    },
                )
            }
        }
    } else {
        // Step 2: Equipment Variant Selection ("Which equipment?")
        val baseTemplate = selectedExerciseTemplate!!
        val options = equipmentPromptOptions(baseTemplate)

        ScalingLazyColumn(
            state = listState,
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black)
                .attachRotaryScroll(listState),
            autoCentering = null,
            contentPadding = PaddingValues(top = 40.dp, bottom = 48.dp, start = 14.dp, end = 14.dp),
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

            items(options) { variant ->
                OneUiPill(
                    title = ExerciseCatalog.equipmentLabel(variant),
                    icon = "⚙️",
                    style = OneUiPillStyle.SlateNavy,
                    onClick = {
                        // The choice rides along as a variant, not as a
                        // rewritten name: "Squat (Barbell)" matched no
                        // phone catalog row and minted a custom exercise
                        // on every sync.
                        val finalTemplate = baseTemplate.copy(equipmentVariant = variant)
                        if (mode == "substitute" && targetIndex >= 0) {
                            viewModel.substituteExerciseInSession(targetIndex, finalTemplate)
                        } else {
                            viewModel.addExerciseToSession(finalTemplate)
                        }
                        navController.popBackStack()
                    },
                )
            }
        }
    }
}
