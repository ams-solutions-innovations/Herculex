package com.ams.herculex.workout

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.Text
import com.ams.herculex.ui.HxIcons
import kotlinx.coroutines.delay

// Active-workout redesign (Claude Design handoff "Herculex Watch Workout").
// Shared pieces for SetLoggerScreen: bezel ring, domain glow, set-type
// badge, chips, the timed-set body and the myo/forced screens.

internal val HxBlue = Color(0xFF42A5F5)
internal val HxTeal = Color(0xFF26A69A)
internal val HxCyan = Color(0xFF26C6DA)
internal val HxAmber = Color(0xFFFFA726)
internal val HxGreen = Color(0xFF30D158)
internal val HxMuted = Color(0xFF8B93A5)
private val HxSub = Color(0xFFB0BEC5)

/** Letter + colour of a set type; shared by the logger, the Set Type list and badges. */
internal data class SetTypeStyle(val letter: String, val color: Color)

internal fun setTypeStyle(id: String): SetTypeStyle = when (id) {
    "warmup" -> SetTypeStyle("W", Color(0xFFFFA726))
    "drop" -> SetTypeStyle("D", Color(0xFFBF5AF2))
    "forced" -> SetTypeStyle("F", Color(0xFFFF453A))
    "cheat" -> SetTypeStyle("CR", Color(0xFFFF7043))
    "rest_pause" -> SetTypeStyle("RP", Color(0xFF26C6DA))
    "myo_reps" -> SetTypeStyle("MY", Color(0xFF81C784))
    "partials" -> SetTypeStyle("PT", Color(0xFF26A69A))
    "negatives" -> SetTypeStyle("NG", Color(0xFF42A5F5))
    "pause" -> SetTypeStyle("PS", Color(0xFFFFD60A))
    else -> SetTypeStyle("", HxMuted)
}

/** Subtle domain gradient: [bottom] glows up from the bottom edge, [top] down from the top. */
internal fun Modifier.domainGlow(bottom: Color, top: Color): Modifier = drawBehind {
    drawRect(
        Brush.radialGradient(
            colors = listOf(bottom, Color.Transparent),
            center = Offset(size.width / 2f, size.height * 1.08f),
            radius = size.width * 0.8f,
        ),
    )
    drawRect(
        Brush.radialGradient(
            colors = listOf(top, Color.Transparent),
            center = Offset(size.width / 2f, -size.height * 0.12f),
            radius = size.width * 0.65f,
        ),
    )
}

/** Set-by-set bezel: warm-ups amber, working sets [accent]; the open set pulses. */
@Composable
internal fun SetBezel(
    warmupTotal: Int,
    workingTotal: Int,
    completed: Int,
    accent: Color,
    modifier: Modifier = Modifier,
) {
    val pulse by rememberInfiniteTransition(label = "bezel").animateFloat(
        initialValue = 0.25f,
        targetValue = 0.75f,
        animationSpec = infiniteRepeatable(tween(760, easing = LinearEasing), RepeatMode.Reverse),
        label = "bezelPulse",
    )
    val all = (warmupTotal + workingTotal).coerceAtLeast(1)
    Canvas(modifier.fillMaxSize()) {
        val stroke = size.minDimension * 10f / 330f
        val inset = size.minDimension * 9f / 330f + stroke / 2f
        val arcSize = Size(size.width - 2 * inset, size.height - 2 * inset)
        val topLeft = Offset(inset, inset)
        val slot = 360f / all
        val gap = (15f / (2f * Math.PI.toFloat() * 156f)) * 360f
        for (i in 0 until all) {
            val warm = i < warmupTotal
            val track = if (warm) Color(0xFF3A2A12) else if (accent == HxTeal) Color(0xFF0F2E2B) else Color(0xFF14263D)
            val start = -90f + i * slot + gap / 2f
            val sweep = (slot - gap).coerceAtLeast(1f)
            drawArc(track, start, sweep, false, topLeft, arcSize, style = Stroke(stroke, cap = StrokeCap.Round))
            val color = if (warm) HxAmber else accent
            if (i < completed) {
                drawArc(color, start, sweep, false, topLeft, arcSize, style = Stroke(stroke, cap = StrokeCap.Round))
            } else if (i == completed) {
                drawArc(color.copy(alpha = pulse), start, sweep, false, topLeft, arcSize, style = Stroke(stroke, cap = StrokeCap.Round))
            }
        }
    }
}

/** Single full-circle progress ring (timed sets, rest). */
@Composable
internal fun ProgressRing(
    fraction: Float,
    track: Color,
    color: Color,
    modifier: Modifier = Modifier,
) {
    Canvas(modifier.fillMaxSize()) {
        val stroke = size.minDimension * 10f / 330f
        val inset = size.minDimension * 9f / 330f + stroke / 2f
        val arcSize = Size(size.width - 2 * inset, size.height - 2 * inset)
        val topLeft = Offset(inset, inset)
        drawArc(track, -90f, 360f, false, topLeft, arcSize, style = Stroke(stroke, cap = StrokeCap.Round))
        val f = fraction.coerceIn(0f, 1f)
        if (f > 0f) {
            drawArc(color, -90f, (360f * f).coerceAtLeast(2f), false, topLeft, arcSize, style = Stroke(stroke, cap = StrokeCap.Round))
        }
    }
}

/** Coloured circle with the set-type letter (W, D, F, MY…); a weight icon for Normal. */
@Composable
internal fun SetTypeBadge(typeId: String, selected: Boolean = false, size: Int = 52) {
    val st = setTypeStyle(typeId)
    Box(
        modifier = Modifier
            .size(size.dp)
            .background(st.color.copy(alpha = 0.18f), CircleShape)
            .border(1.5.dp, st.color.copy(alpha = 0.6f), CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        if (st.letter.isEmpty()) {
            Icon(HxIcons.Dumbbell, null, tint = Color.White, modifier = Modifier.size((size * 0.5f).dp))
        } else {
            Text(
                st.letter,
                color = st.color,
                fontWeight = FontWeight.ExtraBold,
                fontSize = (if (st.letter.length > 1) size * 0.36f else size * 0.46f).sp,
            )
        }
    }
}

@Composable
internal fun HxChip(text: String, color: Color) {
    Text(
        text = text,
        color = color,
        fontSize = 8.sp,
        fontWeight = FontWeight.Bold,
        letterSpacing = 0.4.sp,
        maxLines = 1,
        modifier = Modifier
            .background(color.copy(alpha = 0.12f), CircleShape)
            .border(1.dp, color.copy(alpha = 0.33f), CircleShape)
            .padding(horizontal = 6.dp, vertical = 1.dp),
    )
}

internal fun formatClock(seconds: Int): String {
    val s = seconds.coerceAtLeast(0)
    return "%d:%02d".format(s / 60, s % 60)
}

/**
 * Plank / rowing body: big running time in the centre, ring toward the goal,
 * Start → Stop → Log pill. Goal is set before start with − / +; rowing also
 * has metres (− / + 100 m) and a live /500 m pace.
 */
@Composable
internal fun TimedSetBody(
    name: String,
    setLabel: String,
    dotsTotal: Int,
    dotsDone: Int,
    isBodyweight: Boolean,
    isRow: Boolean,
    targetSeconds: Int,
    elapsedSeconds: Int,
    running: Boolean,
    targetMeters: Int,
    rowedMeters: Int,
    hint: String?,
    hasNext: Boolean,
    onTargetStep: (Int) -> Unit,
    onMetersStep: (Int) -> Unit,
    onPrimary: () -> Unit,
    onPrev: () -> Unit,
    onNext: () -> Unit,
) {
    val idle = !running && elapsedSeconds == 0
    val stopped = !running && elapsedSeconds > 0
    val over = !isRow && !idle && elapsedSeconds >= targetSeconds
    val accent = if (isRow) HxBlue else HxTeal
    val frac = when {
        idle -> 0f
        isRow -> rowedMeters.toFloat() / targetMeters.coerceAtLeast(1)
        else -> elapsedSeconds.toFloat() / targetSeconds.coerceAtLeast(1)
    }
    val pace = if (isRow && rowedMeters > 0 && elapsedSeconds > 0) (elapsedSeconds / (rowedMeters / 500f)).toInt() else 0
    val caption = when {
        idle -> "target ${formatClock(targetSeconds)}"
        isRow -> if (pace > 0) "${formatClock(pace)} /500 m" else "target ${formatClock(targetSeconds)}"
        over -> "Goal reached · +${formatClock(elapsedSeconds - targetSeconds)}"
        else -> formatClock(targetSeconds - elapsedSeconds) + if (stopped) " short" else " left"
    }
    val chipBg = if (isRow) Color(0xFF142B66) else Color(0xFF0F2E2B)
    val chipFg = if (isRow) Color(0xFF80C4FA) else Color(0xFF80CBC4)

    Box(
        Modifier
            .fillMaxSize()
            .domainGlow(accent.copy(alpha = 0.26f), (if (isRow) HxTeal else HxBlue).copy(alpha = 0.14f)),
    ) {
        ProgressRing(frac, if (isRow) Color(0xFF14263D) else Color(0xFF0F2E2B), if (over) Color(0xFF80CBC4) else accent)
        Column(
            Modifier
                .fillMaxSize()
                .padding(top = 22.dp, bottom = 14.dp, start = 18.dp, end = 18.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(name, color = Color.White, fontWeight = FontWeight.Bold, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                Text("SET $setLabel", color = Color.White, fontSize = 8.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.5.sp)
                Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                    for (i in 0 until dotsTotal) {
                        Box(
                            Modifier
                                .size(4.dp)
                                .background(
                                    when {
                                        i < dotsDone -> accent
                                        i == dotsDone -> Color.White
                                        else -> Color(0xFF2A2F3E)
                                    },
                                    CircleShape,
                                ),
                        )
                    }
                }
                if (isBodyweight) Text("BW", color = HxBlue, fontSize = 8.sp, fontWeight = FontWeight.Bold)
                RestCountdownInline()
            }
            Spacer(Modifier.weight(1f))
            Text(
                formatClock(elapsedSeconds),
                color = if (over) Color(0xFF80CBC4) else Color.White,
                fontSize = if (isRow) 34.sp else 38.sp,
                fontWeight = FontWeight.Bold,
                letterSpacing = (-1).sp,
            )
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                if (idle) StepChip("−", chipBg, chipFg) { onTargetStep(-1) } else Spacer(Modifier.size(20.dp))
                Text(
                    caption,
                    color = if (over || pace > 0) Color(0xFF80CBC4) else Color(0xFFA0AABF),
                    fontSize = 10.sp,
                    fontWeight = if (over || pace > 0) FontWeight.SemiBold else FontWeight.Normal,
                    textAlign = TextAlign.Center,
                    maxLines = 1,
                    modifier = Modifier.width(72.dp),
                )
                if (idle) StepChip("+", chipBg, chipFg) { onTargetStep(1) } else Spacer(Modifier.size(20.dp))
            }
            if (isRow) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    StepChip("−", Color(0xFF142B66), Color(0xFF80C4FA)) { onMetersStep(-1) }
                    Row(Modifier.width(78.dp), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.Bottom) {
                        Text(
                            "%,d".format(if (idle) targetMeters else rowedMeters),
                            color = HxBlue,
                            fontSize = 18.sp,
                            fontWeight = FontWeight.Bold,
                        )
                        Spacer(Modifier.width(3.dp))
                        Text(if (idle) "m target" else "m", color = Color(0xFFA0AABF), fontSize = 8.sp, modifier = Modifier.padding(bottom = 3.dp))
                    }
                    StepChip("+", Color(0xFF142B66), Color(0xFF80C4FA)) { onMetersStep(1) }
                }
            }
            Spacer(Modifier.weight(1f))
            if (hint != null) Text(hint, color = HxMuted, fontSize = 8.sp, maxLines = 1)
            Spacer(Modifier.height(2.dp))
            Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Box(Modifier.padding(bottom = 5.dp)) { NavCircleButton("‹", Color(0xFF2C2C2E), 24, onClick = onPrev) }
                val (label, bg, badge, icon) = when {
                    idle -> PrimaryStyle("Start", Color(0xFF0E4B46), Color(0xFF082F2C), HxIcons.Play)
                    running -> PrimaryStyle("Stop", Color(0xFF7A2434), Color(0xFF4F1520), HxIcons.Stop)
                    else -> PrimaryStyle("Log", Color(0xFF1E44AA), Color(0xFF132E78), HxIcons.Check)
                }
                Row(
                    Modifier
                        .width(70.dp)
                        .height(30.dp)
                        .background(bg, CircleShape)
                        .clickable(onClick = onPrimary)
                        .padding(start = 3.dp, end = 5.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Box(Modifier.size(24.dp).background(badge, CircleShape), contentAlignment = Alignment.Center) {
                        Icon(icon, null, tint = Color.White, modifier = Modifier.size(14.dp))
                    }
                    Text(label, color = Color.White, fontWeight = FontWeight.Bold, fontSize = 11.sp)
                }
                Box(Modifier.padding(bottom = 5.dp)) { NavCircleButton("›", Color(0xFF2C2C2E), 24, enabled = hasNext, onClick = onNext) }
            }
        }
    }
}

private data class PrimaryStyle(val label: String, val bg: Color, val badge: Color, val icon: ImageVector)

@Composable
private fun StepChip(label: String, bg: Color, fg: Color, onClick: () -> Unit) {
    Box(
        Modifier
            .size(20.dp)
            .background(bg, CircleShape)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(label, color = fg, fontSize = 12.sp, fontWeight = FontWeight.Bold)
    }
}

/** Rest left, amber, inline with the set label (phone-driven timer). */
@Composable
private fun RestCountdownInline() {
    val timer by RestTimerStore.timer.collectAsState()
    val active = timer?.takeIf { it.showOnWatch } ?: return
    var now by remember(active.endsAtEpochMs) { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(active.endsAtEpochMs) {
        while (now < active.endsAtEpochMs) {
            delay(1000L - (System.currentTimeMillis() % 1000L))
            now = System.currentTimeMillis()
        }
    }
    val remaining = active.remainingSeconds(now)
    if (remaining <= 0) return
    Text(formatClock(remaining), color = HxAmber, fontSize = 8.sp, fontWeight = FontWeight.SemiBold)
}

/**
 * Myo / forced / cheat reps: clean set, big running total, stepper and
 * "+ N type" / Finish. Background gradient carries the type; after adding,
 * [ExtraRestScreen] takes over until the rest is over.
 */
@Composable
internal fun ExtraRepsScreen(
    exercise: ActiveExercise,
    exerciseIndex: Int,
    setIndex: Int,
    loggedSet: LoggedSet,
    viewModel: WorkoutViewModel,
    onEditActivation: () -> Unit,
    onFinishSet: () -> Unit,
) {
    val haptic = LocalHapticFeedback.current
    val isMyo = loggedSet.setType == "myo_reps"
    val isForced = loggedSet.setType == "forced"
    val kind = when {
        isMyo -> "myo"
        isForced -> "forced"
        else -> "cheat"
    }
    val color = when {
        isMyo -> Color(0xFF81C784)
        isForced -> Color(0xFFFF453A)
        else -> Color(0xFFFF7043)
    }
    val restLen = if (isMyo) 15 else 45
    val extraList = remember(loggedSet.setTypeMetaJson) {
        if (isMyo) loggedSet.getMiniSets() else loggedSet.getExtraReps()
    }
    var repCount by remember { mutableIntStateOf(extraList.lastOrNull() ?: if (isMyo) 3 else 2) }
    var restEndMs by remember { mutableLongStateOf(0L) }
    var restNext by remember { mutableIntStateOf(0) }

    if (restEndMs > 0L) {
        ExtraRestScreen(
            endMs = restEndMs,
            lengthSeconds = restLen,
            nextReps = restNext,
            kind = kind,
            onDone = { restEndMs = 0L },
            onSkip = { restEndMs = System.currentTimeMillis() },
        )
        return
    }

    val rawName = exercise.template.name
    val mainName = if (rawName.contains("(")) rawName.substringBefore("(").trim() else rawName
    val subName = (if (rawName.contains("(")) rawName.substringAfter("(").substringBefore(")").trim() else "")
        .ifEmpty { exercise.template.equipmentVariant?.let { ExerciseCatalog.equipmentLabel(it) } ?: "" }
    val total = loggedSet.reps + extraList.sum()
    val parts = loggedSet.reps.toString() + extraList.joinToString("") { " + $it" }

    Box(
        Modifier
            .fillMaxSize()
            .background(Color.Black)
            .domainGlow(color.copy(alpha = 0.42f), color.copy(alpha = 0.14f)),
    ) {
        Column(
            Modifier
                .fillMaxSize()
                .padding(top = 24.dp, bottom = 20.dp, start = 18.dp, end = 18.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(mainName, color = Color.White, fontWeight = FontWeight.Bold, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (subName.isNotEmpty()) Text(subName, color = HxSub, fontSize = 9.sp, maxLines = 1)
            Spacer(Modifier.height(4.dp))
            Row(
                Modifier
                    .height(20.dp)
                    .background(Color(0xD9202636), CircleShape)
                    .border(1.dp, Color(0xFF323B52), CircleShape)
                    .clickable(onClick = onEditActivation)
                    .padding(horizontal = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Icon(HxIcons.Dumbbell, null, tint = Color.White, modifier = Modifier.size(10.dp))
                Text("Clean · %.1f kg × %d".format(loggedSet.weight, loggedSet.reps), color = Color.White, fontSize = 9.sp, fontWeight = FontWeight.SemiBold)
            }
            Spacer(Modifier.height(4.dp))
            Text("$total", color = color, fontSize = 34.sp, fontWeight = FontWeight.Bold, letterSpacing = (-1).sp)
            Text("reps total", color = HxSub, fontSize = 9.sp)
            Text(parts, color = color.copy(alpha = 0.9f), fontSize = 9.sp, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.weight(1f))
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                NavCircleButton("-", Color(0xFF2C2C2E), 24) { if (repCount > 1) repCount -= 1 }
                Column(Modifier.width(38.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("$repCount", color = Color.White, fontSize = 19.sp, fontWeight = FontWeight.Bold)
                    Text(kind, color = HxSub, fontSize = 8.sp)
                }
                NavCircleButton("+", Color(0xFF2C2C2E), 24) { if (repCount < 20) repCount += 1 }
            }
            Spacer(Modifier.height(4.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Box(
                    Modifier
                        .width(62.dp)
                        .height(28.dp)
                        .background(Color(0xFF1565C0), CircleShape)
                        .clickable {
                            haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                            if (isMyo) viewModel.addMiniSet(exerciseIndex, setIndex, repCount)
                            else viewModel.addExtraReps(exerciseIndex, setIndex, repCount)
                            restNext = repCount
                            restEndMs = System.currentTimeMillis() + restLen * 1000L
                        },
                    contentAlignment = Alignment.Center,
                ) {
                    Text("+ $repCount $kind", color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Bold, maxLines = 1)
                }
                Row(
                    Modifier
                        .width(52.dp)
                        .height(28.dp)
                        .background(Color(0xFF1B4D3E), CircleShape)
                        .clickable(onClick = onFinishSet),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.Center,
                ) {
                    Icon(HxIcons.Check, null, tint = Color.White, modifier = Modifier.size(12.dp))
                    Text("Finish", color = Color.White, fontSize = 9.sp, fontWeight = FontWeight.Bold, maxLines = 1)
                }
            }
        }
    }
}

/** Rest between myo / forced bursts; ends with a "TIME TO GO AGAIN" pop. */
@Composable
internal fun ExtraRestScreen(
    endMs: Long,
    lengthSeconds: Int,
    nextReps: Int,
    kind: String,
    onDone: () -> Unit,
    onSkip: () -> Unit,
) {
    val haptic = LocalHapticFeedback.current
    var now by remember(endMs) { mutableLongStateOf(System.currentTimeMillis()) }
    val finished = now >= endMs
    LaunchedEffect(endMs) {
        while (System.currentTimeMillis() < endMs) {
            now = System.currentTimeMillis()
            delay(50)
        }
        now = System.currentTimeMillis()
        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
        delay(1700)
        onDone()
    }
    val pop = remember(endMs) { Animatable(0.7f) }
    LaunchedEffect(finished) {
        if (finished) {
            pop.animateTo(1.2f, tween(250))
            pop.animateTo(1f, tween(200))
        }
    }
    val leftSec = ((endMs - now).coerceAtLeast(0L) / 1000f)
    val ringColor = if (finished) HxGreen else HxAmber
    Box(
        Modifier
            .fillMaxSize()
            .background(Color.Black)
            .domainGlow(
                if (finished) HxGreen.copy(alpha = 0.42f) else HxAmber.copy(alpha = 0.3f),
                if (finished) HxGreen.copy(alpha = 0.14f) else Color(0xFFFF7043).copy(alpha = 0.1f),
            ),
    ) {
        ProgressRing(if (finished) 1f else leftSec / lengthSeconds.coerceAtLeast(1), Color(0xFF1C1F26), ringColor)
        Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
            if (finished) {
                Text(
                    "TIME TO\nGO AGAIN",
                    color = HxGreen,
                    fontSize = 22.sp,
                    fontWeight = FontWeight.ExtraBold,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.scale(pop.value),
                )
                Text("$nextReps $kind reps", color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(top = 4.dp))
            } else {
                Text("REST", color = HxAmber, fontSize = 9.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.sp)
                Text(formatClock(kotlin.math.ceil(leftSec).toInt()), color = Color.White, fontSize = 50.sp, fontWeight = FontWeight.Bold, letterSpacing = (-2).sp)
                Text("Next · $nextReps $kind reps", color = Color(0xFFA0AABF), fontSize = 10.sp, fontWeight = FontWeight.SemiBold)
                Spacer(Modifier.height(8.dp))
                Box(
                    Modifier
                        .height(24.dp)
                        .background(Color(0xFF202636), CircleShape)
                        .border(1.dp, Color(0xFF323B52), CircleShape)
                        .clickable(onClick = onSkip)
                        .padding(horizontal = 14.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text("Skip", color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                }
            }
        }
    }
}
