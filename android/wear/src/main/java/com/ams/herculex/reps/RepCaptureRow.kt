package com.ams.herculex.reps

import android.content.Context
import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.Text
import com.ams.herculex.workout.WorkoutOngoingService

/**
 * The on-wrist rep-capture control, and the live provisional count.
 *
 * ## Why this file exists
 *
 * `WorkoutOngoingService` has handled `ACTION_START_REP_CAPTURE` since the
 * capture controller was written, and `provisionalRepCount` has been exposed
 * as a `StateFlow` for just as long — but **nothing on the watch ever sent
 * that intent or read that flow**. The entire wrist capture path was
 * unreachable, so the phone's default `wrist` source produced a tracker panel
 * that waited forever for a capture that could not begin. This is the missing
 * sender.
 *
 * ## What it deliberately does not do
 *
 * It does not arm itself. The tap here is what starts sensing, which keeps
 * "the tracker never starts itself" true from the user's side as well as the
 * code's. What the tap arms is the low-rate motion *gate*, not a single
 * capture — so one tap covers every set of the exercise, and the per-set tap
 * that made a twenty-set workout worse than typing the numbers is gone.
 *
 * While armed and resting the watch runs one sensor at ~12.5 Hz with a
 * five-second hardware FIFO, so the processor sleeps between bursts. It
 * escalates to three sensors at 50 Hz only once motion starts.
 *
 * It also does not decide whether the exercise is *trackable*. That question
 * is answered by the per-exercise capability profile, which lives on the phone
 * — the watch would need its own copy of the profiles asset to filter here,
 * and a second copy is a second thing to keep in sync. The cost of asking is
 * one capture's worth of sensor time on an exercise the phone will then report
 * as unmeasurable; the cost of a stale watch-side copy is silently refusing to
 * track an exercise that works. The gate belongs on the watch eventually, fed
 * by the same catalogue push that already carries slugs.
 *
 * The count shown here is **provisional** and labelled as such. The
 * authoritative count comes from the phone's detector, which runs a
 * multi-channel pipeline over the full sample stream; this one is an
 * adaptive-threshold peak counter with no calibration, present so the wrist
 * gives immediate feedback rather than a five-minute silence.
 */
@Composable
fun RepCaptureRow(
    exerciseSlug: String?,
    modifier: Modifier = Modifier,
) {
    if (exerciseSlug.isNullOrBlank()) return

    val context = androidx.compose.ui.platform.LocalContext.current
    val provisionalCount by WorkoutOngoingService.provisionalRepCount.collectAsState()
    // "armed" is the gate, not a capture. One tap covers every set of this
    // exercise; the sets themselves open and close on their own.
    var armed by remember(exerciseSlug) { mutableStateOf(false) }

    // Leaving the screen, or moving to another exercise, ends the capture.
    // Without this a user who swipes away mid-set leaves the accelerometer
    // registered until the service is destroyed — the controller's teardown
    // paths are balanced, but only if something calls one of them.
    DisposableEffect(exerciseSlug) {
        onDispose {
            if (armed) {
                context.sendRepCapture(WorkoutOngoingService.ACTION_STOP_REP_WATCH, exerciseSlug)
            }
        }
    }

    Row(
        modifier = modifier
            .clip(RoundedCornerShape(12.dp))
            .background(if (armed) Color(0xFF0D3B66) else Color(0xFF2C2C2E))
            .clickable {
                armed = if (armed) {
                    context.sendRepCapture(
                        WorkoutOngoingService.ACTION_STOP_REP_WATCH,
                        exerciseSlug,
                    )
                    false
                } else {
                    context.sendRepCapture(
                        WorkoutOngoingService.ACTION_START_REP_WATCH,
                        exerciseSlug,
                    )
                    true
                }
            }
            .padding(horizontal = 10.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (armed) {
            Text(
                "$provisionalCount",
                color = Color(0xFF42A5F5),
                fontSize = 14.sp,
                fontWeight = FontWeight.Bold,
            )
            Spacer(Modifier.width(6.dp))
            // "approx" is not decoration. The phone may propose a different
            // number, and a user who was shown an unqualified count on the
            // wrist would read that as the app contradicting itself.
            Text("approx · auto", color = Color(0xFF9E9E9E), fontSize = 9.sp)
        } else {
            Text("◉ Auto-count reps", color = Color(0xFFBDBDBD), fontSize = 10.sp)
        }
    }
}

/**
 * Sends one capture command to the hosting foreground service.
 *
 * `startService` rather than `startForegroundService`: the service is already
 * in the foreground for the duration of the workout, and these commands are
 * only ever sent from a visible set logger. Promoting it here would be a
 * second, redundant foreground start.
 */
private fun Context.sendRepCapture(action: String, exerciseSlug: String) {
    val intent = Intent(this, WorkoutOngoingService::class.java).apply {
        this.action = action
        putExtra(WorkoutOngoingService.EXTRA_REP_EXERCISE_SLUG, exerciseSlug)
    }
    runCatching { startService(intent) }
}
