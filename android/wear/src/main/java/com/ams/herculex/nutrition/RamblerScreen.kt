package com.ams.herculex.nutrition

import android.app.Activity
import android.content.Intent
import android.speech.RecognizerIntent
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.CircularProgressIndicator
import androidx.wear.compose.material.Text
import com.ams.herculex.ui.OneUiPill
import com.ams.herculex.ui.OneUiPillStyle
import com.ams.herculex.workout.attachRotaryScroll
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.Calendar

@Composable
fun RamblerScreen(
    navController: NavController,
    viewModel: NutritionViewModel,
    initialMealKey: String? = null,
    autoStartSpeech: Boolean = false,
) {
    val context = LocalContext.current
    val coroutineScope = rememberCoroutineScope()
    val listState = rememberScalingLazyListState()

    // Determine initial meal key based on current time
    val defaultMeal = remember {
        if (!initialMealKey.isNullOrBlank()) {
            initialMealKey
        } else {
            val hour = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)
            when (hour) {
                in 4..10 -> "breakfast"
                in 11..15 -> "lunch"
                in 16..21 -> "dinner"
                else -> "snack"
            }
        }
    }

    var selectedMeal by remember { mutableStateOf(defaultMeal) }
    var spokenText by remember { mutableStateOf("") }
    var isSending by remember { mutableStateOf(false) }
    var isSent by remember { mutableStateOf(false) }

    val speechLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK) {
            val matches = result.data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
            val text = matches?.firstOrNull()?.trim()
            if (!text.isNullOrBlank()) {
                spokenText = text
            }
        }
    }

    fun startListening() {
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
            )
            putExtra(RecognizerIntent.EXTRA_PROMPT, "Describe what you ate...")
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        }
        try {
            speechLauncher.launch(intent)
        } catch (e: Exception) {
            Toast.makeText(context, "Voice input unavailable on this device", Toast.LENGTH_SHORT).show()
        }
    }

    LaunchedEffect(Unit) {
        if (autoStartSpeech) {
            delay(300)
            startListening()
        }
    }

    ScalingLazyColumn(
        state = listState,
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .attachRotaryScroll(listState),
        autoCentering = null,
        contentPadding = PaddingValues(top = 36.dp, bottom = 48.dp, start = 12.dp, end = 12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        // ── Title Header ─────────────────────────────────────────────────────
        item {
            Column(
                modifier = Modifier.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(
                    text = "Rambler AI",
                    color = Color(0xFF42A5F5),
                    fontWeight = FontWeight.Bold,
                    fontSize = 15.sp,
                )
                Text(
                    text = "Voice Food Logger",
                    color = Color(0xFF9E9E9E),
                    fontSize = 11.sp,
                    modifier = Modifier.padding(bottom = 4.dp),
                )
            }
        }

        // ── Success State ────────────────────────────────────────────────────
        if (isSent) {
            item {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 12.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text("✓ Logged to Diary!", color = Color(0xFFA5D6A7), fontWeight = FontWeight.Bold, fontSize = 14.sp)
                    Spacer(Modifier.height(4.dp))
                    Text("AI is analyzing & syncing macros...", color = Color(0xFFB0B8C8), fontSize = 11.sp, textAlign = TextAlign.Center)
                }
            }
        } else if (isSending) {
            // ── Sending / Analyzing State ─────────────────────────────────────
            item {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 16.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(32.dp),
                        strokeWidth = 3.dp,
                        indicatorColor = Color(0xFF42A5F5),
                    )
                    Spacer(Modifier.height(8.dp))
                    Text("Sending to AI...", color = Color.White, fontSize = 12.sp)
                }
            }
        } else {
            // ── Meal Slot Chips ──────────────────────────────────────────────
            item {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceEvenly,
                ) {
                    MealSlotChip(label = "B", fullName = "Breakfast", key = "breakfast", selected = selectedMeal == "breakfast") { selectedMeal = "breakfast" }
                    MealSlotChip(label = "L", fullName = "Lunch", key = "lunch", selected = selectedMeal == "lunch") { selectedMeal = "lunch" }
                    MealSlotChip(label = "D", fullName = "Dinner", key = "dinner", selected = selectedMeal == "dinner") { selectedMeal = "dinner" }
                    MealSlotChip(label = "S", fullName = "Snack", key = "snack", selected = selectedMeal == "snack") { selectedMeal = "snack" }
                }
            }

            // ── Voice Input Trigger / Transcript Box ─────────────────────────
            if (spokenText.isBlank()) {
                item {
                    OneUiPill(
                        title = "Tap to Speak",
                        subtitle = "Describe your meal",
                        icon = "🎙️",
                        style = OneUiPillStyle.RoyalBlue,
                        onClick = { startListening() },
                    )
                }
            } else {
                item {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(14.dp))
                            .background(Color(0xFF202636))
                            .padding(12.dp),
                    ) {
                        Column {
                            Text(
                                text = "“$spokenText”",
                                color = Color.White,
                                fontSize = 12.sp,
                                fontWeight = FontWeight.Medium,
                            )
                            Spacer(Modifier.height(4.dp))
                            Text(
                                text = "Meal: ${selectedMeal.replaceFirstChar { it.uppercase() }}",
                                color = Color(0xFF42A5F5),
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Bold,
                            )
                        }
                    }
                }

                // ── Action: Analyze & Log ────────────────────────────────────
                item {
                    OneUiPill(
                        title = "Log with AI",
                        subtitle = "Analyze & save macros",
                        icon = "⚡",
                        style = OneUiPillStyle.EmeraldGreen,
                        onClick = {
                            if (spokenText.isNotBlank()) {
                                isSending = true
                                viewModel.logRamblerVoice(spokenText, selectedMeal)
                                coroutineScope.launch {
                                    delay(1200)
                                    isSending = false
                                    isSent = true
                                    delay(1200)
                                    navController.popBackStack("nutrition", inclusive = false)
                                }
                            }
                        },
                    )
                }

                // ── Action: Speak Again ──────────────────────────────────────
                item {
                    OneUiPill(
                        title = "Speak Again",
                        icon = "🔄",
                        style = OneUiPillStyle.SlateNavy,
                        onClick = { startListening() },
                    )
                }
            }
        }
    }
}

@Composable
private fun MealSlotChip(
    label: String,
    fullName: String,
    key: String,
    selected: Boolean,
    onClick: () -> Unit,
) {
    val bgColor = if (selected) Color(0xFF1E44AA) else Color(0xFF202636)
    val textColor = if (selected) Color.White else Color(0xFFB0B8C8)

    Box(
        modifier = Modifier
            .size(32.dp)
            .clip(CircleShape)
            .background(bgColor)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = label,
            color = textColor,
            fontSize = 12.sp,
            fontWeight = if (selected) FontWeight.Bold else FontWeight.Normal,
        )
    }
}
