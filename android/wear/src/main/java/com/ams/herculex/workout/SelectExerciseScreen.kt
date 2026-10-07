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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
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
    val session by viewModel.session.collectAsState()

    // If session was discarded/finished, pop back to home (when not starting fresh)
    LaunchedEffect(session) {
        if (session == null && mode != "start") navController.popBackStack("home", inclusive = false)
    }

    var searchQuery by remember { mutableStateOf("") }
    var selectedExerciseTemplate by remember { mutableStateOf<ExerciseTemplate?>(null) }

    val allExercises = remember { ExerciseCatalog.getAll(context) }
    val savedWorkouts = remember { WorkoutStore.getWorkouts(context) }

    // Calculate occurrences in user's workout routines / templates
    val templateOccurrences = remember(savedWorkouts) {
        val map = mutableMapOf<String, Int>()
        for (w in savedWorkouts) {
            for (ex in w.exercises) {
                val key = ExerciseUsageTracker.exerciseKey(ex)
                map[key] = (map[key] ?: 0) + 1
            }
        }
        map
    }

    // 1. Frequent exercises (routines + logged history score)
    val frequentExercises = remember(allExercises, templateOccurrences) {
        allExercises
            .map { ex -> ex to ExerciseUsageTracker.calculateScore(context, ex, templateOccurrences) }
            .filter { it.second > 0 }
            .sortedByDescending { it.second }
            .map { it.first }
    }
    val frequentKeys = remember(frequentExercises) {
        frequentExercises.map { ExerciseUsageTracker.exerciseKey(it) }.toSet()
    }

    // 2. Recent exercises (not already in frequent list)
    val recentExercises = remember(allExercises, frequentKeys) {
        val recentKeys = ExerciseUsageTracker.getRecentKeys(context)
        recentKeys.mapNotNull { rk ->
            allExercises.firstOrNull { ExerciseUsageTracker.exerciseKey(it) == rk }
        }.filter { !frequentKeys.contains(ExerciseUsageTracker.exerciseKey(it)) }
    }
    val frequentAndRecentKeys = remember(frequentKeys, recentExercises) {
        frequentKeys + recentExercises.map { ExerciseUsageTracker.exerciseKey(it) }.toSet()
    }

    // 3. Remaining catalog exercises
    val remainingExercises = remember(allExercises, frequentAndRecentKeys) {
        allExercises
            .filter { !frequentAndRecentKeys.contains(ExerciseUsageTracker.exerciseKey(it)) }
            .sortedBy { it.name }
    }

    // Filtered lists when searching
    val filteredFrequent = remember(searchQuery, frequentExercises) {
        if (searchQuery.isBlank()) frequentExercises
        else frequentExercises.filter { it.name.contains(searchQuery, ignoreCase = true) }
    }
    val filteredRecent = remember(searchQuery, recentExercises) {
        if (searchQuery.isBlank()) recentExercises
        else recentExercises.filter { it.name.contains(searchQuery, ignoreCase = true) }
    }
    val filteredRemaining = remember(searchQuery, remainingExercises) {
        if (searchQuery.isBlank()) remainingExercises
        else remainingExercises.filter { it.name.contains(searchQuery, ignoreCase = true) }
    }

    val listState = rememberScalingLazyListState()

    fun onExerciseSelected(exTemplate: ExerciseTemplate) {
        ExerciseUsageTracker.recordUsed(context, exTemplate)
        if (mode == "substitute" && targetIndex >= 0) {
            viewModel.substituteExerciseInSession(targetIndex, exTemplate)
        } else {
            viewModel.addExerciseToSession(exTemplate)
        }
        navController.popBackStack()
    }

    if (selectedExerciseTemplate == null) {
        // Step 1: Pick Exercise Name from Prioritized Catalog with Search
        ScalingLazyColumn(
            state = listState,
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black)
                .attachRotaryScroll(listState),
            autoCentering = null,
            contentPadding = PaddingValues(top = 36.dp, bottom = 48.dp, start = 14.dp, end = 14.dp),
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
                        .heightIn(min = 44.dp)
                        .background(Color(0xFF202636), shape = CircleShape)
                        .border(1.dp, Color(0xFF323B52), CircleShape)
                        .padding(horizontal = 12.dp, vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(
                        modifier = Modifier
                            .size(28.dp)
                            .background(Color(0xFF141926), shape = CircleShape),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text("🔍", fontSize = 12.sp)
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

            // ── Section 1: Most Frequent Exercises ────────────────────────
            if (filteredFrequent.isNotEmpty()) {
                item {
                    SectionHeader(title = if (searchQuery.isBlank()) "⭐ MOST FREQUENT" else "⭐ FREQUENT MATCHES")
                }
                items(filteredFrequent) { exTemplate ->
                    OneUiPill(
                        title = exTemplate.name,
                        subtitle = "Frequent / Routine",
                        iconComposable = {
                            ExerciseArtwork(
                                name = exTemplate.name,
                                slug = exTemplate.slug,
                                size = 38.dp,
                            )
                        },
                        style = OneUiPillStyle.RoyalBlue,
                        onClick = {
                            if (equipmentPromptOptions(exTemplate).isNotEmpty()) {
                                selectedExerciseTemplate = exTemplate
                            } else {
                                onExerciseSelected(exTemplate)
                            }
                        },
                    )
                }
            }

            // ── Section 2: Recent Exercises ──────────────────────────────
            if (filteredRecent.isNotEmpty()) {
                item {
                    SectionHeader(title = if (searchQuery.isBlank()) "🕒 RECENT" else "🕒 RECENT MATCHES")
                }
                items(filteredRecent) { exTemplate ->
                    OneUiPill(
                        title = exTemplate.name,
                        subtitle = "Recent",
                        iconComposable = {
                            ExerciseArtwork(
                                name = exTemplate.name,
                                slug = exTemplate.slug,
                                size = 38.dp,
                            )
                        },
                        style = OneUiPillStyle.SlateNavy,
                        onClick = {
                            if (equipmentPromptOptions(exTemplate).isNotEmpty()) {
                                selectedExerciseTemplate = exTemplate
                            } else {
                                onExerciseSelected(exTemplate)
                            }
                        },
                    )
                }
            }

            // ── Section 3: All Other Catalog Exercises ───────────────────
            if (filteredRemaining.isNotEmpty()) {
                item {
                    SectionHeader(title = if (searchQuery.isBlank()) "📚 ALL EXERCISES (${remainingExercises.size})" else "📚 ALL MATCHES")
                }
                items(filteredRemaining) { exTemplate ->
                    OneUiPill(
                        title = exTemplate.name,
                        iconComposable = {
                            ExerciseArtwork(
                                name = exTemplate.name,
                                slug = exTemplate.slug,
                                size = 38.dp,
                            )
                        },
                        style = OneUiPillStyle.SlateNavy,
                        onClick = {
                            if (equipmentPromptOptions(exTemplate).isNotEmpty()) {
                                selectedExerciseTemplate = exTemplate
                            } else {
                                onExerciseSelected(exTemplate)
                            }
                        },
                    )
                }
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
                        val finalTemplate = baseTemplate.copy(equipmentVariant = variant)
                        onExerciseSelected(finalTemplate)
                    },
                )
            }
        }
    }
}

@Composable
private fun SectionHeader(title: String) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(start = 6.dp, top = 6.dp, bottom = 2.dp)
    ) {
        Text(
            text = title,
            color = Color(0xFFA0AABF),
            fontWeight = FontWeight.Bold,
            fontSize = 10.sp,
            letterSpacing = 0.5.sp
        )
    }
}
