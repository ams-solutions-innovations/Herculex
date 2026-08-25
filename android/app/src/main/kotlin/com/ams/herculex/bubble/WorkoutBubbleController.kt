package com.ams.herculex.bubble

import android.animation.ValueAnimator
import android.app.AlertDialog
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Point
import android.os.Build
import android.os.SystemClock
import android.provider.Settings
import android.text.InputType
import android.util.Log
import android.util.TypedValue
import android.view.ContextThemeWrapper
import android.view.Gravity
import android.view.KeyEvent
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.VelocityTracker
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.view.ViewOutlineProvider
import android.view.WindowInsets
import android.view.WindowManager
import android.view.animation.DecelerateInterpolator
import android.view.animation.OvershootInterpolator
import android.view.animation.PathInterpolator
import android.widget.Chronometer
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.TextView
import androidx.core.content.ContextCompat
import com.ams.herculex.MainActivity
import com.ams.herculex.R

/**
 * The Workout Bubble — a Facebook-Messenger-style chat head shown over other
 * apps while a workout is running, which expands into a live workout card.
 *
 * Application-scoped on purpose: the overlay outlives `MainActivity`, which is
 * exactly the point (it exists *because* the user left the app).
 *
 * This class renders and reports taps; it never derives workout state. Content
 * arrives from Dart as a [BubbleSnapshot] — built from the same
 * `OngoingWorkoutSurfaceSnapshot` that drives the ongoing notification — and
 * control taps go straight back out through [onAction] as shared action IDs.
 */
object WorkoutBubbleController {

    private const val TAG = "WorkoutBubble"

    private const val EDGE_MARGIN_DP = 8
    private const val DISMISS_BOTTOM_MARGIN_DP = 88
    private const val DISMISS_CAPTURE_RADIUS_DP = 80
    private const val DISMISS_SIZE_DP = 56
    private const val POPUP_GAP_DP = 8
    private const val INITIAL_Y_FRACTION = 0.35f
    private const val SNAP_DURATION_MS = 280L

    // Open/close relocation. Values and easing lifted from design mock.
    private const val OPEN_TOP_MARGIN_DP = 44
    private const val OPEN_BOTTOM_MARGIN_DP = 44
    private const val RELOCATE_DURATION_MS = 300L
    private const val POPUP_TRANSFORM_DURATION_MS = 240L
    private const val POPUP_ENTER_SCALE = 0.94f
    private const val POPUP_TRANSLATE_DP = 12

    private val MOTION_INTERPOLATOR = PathInterpolator(0.2f, 0.8f, 0.2f, 1f)
    private val BOUNCY_INTERPOLATOR = OvershootInterpolator(1.2f)

    /** One control in the popup, already labelled by Dart. */
    data class BubbleAction(val id: String, val label: String, val primary: Boolean)

    /** Everything the popup displays. Purely presentational. */
    data class BubbleSnapshot(
        val sessionId: Long,
        val startedAtEpochMs: Long,
        val exerciseName: String,
        val subtitle: String,
        val setNumber: String,
        val weight: String,
        val reps: String,
        val rpe: String,
        val totalSetsText: String,
        val tonnageText: String,
        val lastSetText: String?,
        val targetSetId: Long?,
        val actions: List<BubbleAction>,
    )

    /**
     * Reports a control tap or value edit back to Dart as
     * `(actionId, sessionId, setId, value)`.
     */
    var onAction: ((String, Long, Long?, String?) -> Unit)? = null

    private var bubbleView: View? = null
    private var bubbleParams: WindowManager.LayoutParams? = null
    private var popupContainer: ViewGroup? = null
    private var popupView: View? = null
    private var dismissView: View? = null
    private var snapAnimator: ValueAnimator? = null
    private var relocateAnimator: ValueAnimator? = null
    private var snapshot: BubbleSnapshot? = null
    private var isPopupAtBottom = false

    /** Where the bubble was docked before it relocated to open — restored on close. */
    private var restoreX = 0
    private var restoreY = 0

    /**
     * The session the user flung onto the X. Dismissal is scoped to one
     * workout, not to the setting.
     */
    private var dismissedSessionId: Long? = null

    // Drag state.
    private var pressStartX = 0
    private var pressStartY = 0
    private var pressRawX = 0f
    private var pressRawY = 0f
    private var dragging = false
    private var velocityTracker: VelocityTracker? = null

    val isShowing: Boolean
        get() = bubbleView != null

    fun canDrawOverlays(context: Context): Boolean =
        Settings.canDrawOverlays(context.applicationContext)

    /**
     * Clears any dismissal lock so that next time the user leaves the app,
     * the bubble reappears.
     */
    fun clearDismissed() {
        dismissedSessionId = null
    }

    /** Shows the bubble for [newSnapshot], or refreshes it if already up. */
    @Suppress("ClickableViewAccessibility")
    fun show(context: Context, newSnapshot: BubbleSnapshot) {
        val appContext = context.applicationContext
        if (!canDrawOverlays(appContext)) return
        if (dismissedSessionId == newSnapshot.sessionId) return

        snapshot = newSnapshot

        if (bubbleView != null) {
            popupView?.let {
                try {
                    bindPopup(appContext, it, newSnapshot)
                } catch (e: Exception) {
                    Log.w(TAG, "Could not refresh the workout bubble popup", e)
                }
            }
            return
        }

        val windowManager = windowManager(appContext) ?: return

        val view = try {
            LayoutInflater.from(appContext).inflate(R.layout.workout_bubble, null)
        } catch (e: Exception) {
            Log.w(TAG, "Could not inflate the workout bubble", e)
            return
        }
        view.outlineProvider = ViewOutlineProvider.BACKGROUND
        view.clipToOutline = true

        val (screenWidth, screenHeight) = screenSize(windowManager)
        val bubbleSize = appContext.resources.getDimensionPixelSize(R.dimen.workout_bubble_size)

        val params = WindowManager.LayoutParams(
            bubbleSize,
            bubbleSize,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = screenWidth
            y = (screenHeight * INITIAL_Y_FRACTION).toInt()
        }

        view.setOnTouchListener { touched, event -> onBubbleTouch(appContext, touched, event) }

        try {
            windowManager.addView(view, params)
        } catch (e: Exception) {
            Log.w(TAG, "Could not add the workout bubble", e)
            return
        }

        bubbleView = view
        bubbleParams = params
        view.post {
            if (relocateAnimator?.isRunning == true) return@post
            val current = bubbleParams ?: return@post
            val (topInset, bottomInset) = verticalInsets(windowManager)
            val (targetX, targetY) = BubbleDragMath.snapTarget(
                currentX = current.x,
                currentY = current.y,
                velocityX = 0f,
                velocityY = 0f,
                bubbleWidth = view.width,
                bubbleHeight = view.height,
                screenWidth = screenWidth,
                screenHeight = screenHeight,
                margin = dp(appContext, EDGE_MARGIN_DP),
                topInset = topInset,
                bottomInset = bottomInset,
            )
            current.x = targetX
            current.y = targetY
            safeUpdate(appContext, view, current)
        }
    }

    /** Removes the bubble and its popup. Safe to call anytime. */
    fun hide(context: Context) {
        val appContext = context.applicationContext
        snapAnimator?.cancel()
        snapAnimator = null
        relocateAnimator?.cancel()
        relocateAnimator = null
        velocityTracker?.recycle()
        velocityTracker = null
        dragging = false

        hidePopup(appContext, relocate = false)

        val bubble = bubbleView
        bubbleView = null
        bubbleParams = null
        if (bubble != null) {
            try {
                windowManager(appContext)?.removeView(bubble)
            } catch (e: Exception) {
                Log.w(TAG, "Could not remove the workout bubble", e)
            }
        }
        hideDismissTarget(appContext)
    }

    // ── Touch and drag ────────────────────────────────────────────────────────

    private fun onBubbleTouch(context: Context, view: View, event: MotionEvent): Boolean {
        val params = bubbleParams ?: return false
        val windowManager = windowManager(context) ?: return false
        val (screenWidth, screenHeight) = screenSize(windowManager)
        val (topInset, bottomInset) = verticalInsets(windowManager)

        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                snapAnimator?.cancel()
                relocateAnimator?.cancel()
                velocityTracker?.recycle()
                velocityTracker = VelocityTracker.obtain().apply {
                    addMovement(event)
                }
                pressStartX = params.x
                pressStartY = params.y
                pressRawX = event.rawX
                pressRawY = event.rawY
                dragging = false

                view.animate()
                    .scaleX(0.92f)
                    .scaleY(0.92f)
                    .setDuration(120)
                    .setInterpolator(DecelerateInterpolator())
                    .start()

                return true
            }

            MotionEvent.ACTION_MOVE -> {
                velocityTracker?.addMovement(event)
                val dx = event.rawX - pressRawX
                val dy = event.rawY - pressRawY
                if (!dragging) {
                    if (popupView != null) return true
                    if (!BubbleDragMath.isTap(dx, dy, ViewConfiguration.get(context).scaledTouchSlop)) {
                        dragging = true
                        showDismissTarget(context)
                        view.animate()
                            .scaleX(1.06f)
                            .scaleY(1.06f)
                            .setDuration(150)
                            .setInterpolator(BOUNCY_INTERPOLATOR)
                            .start()
                    }
                }
                if (!dragging) return true

                params.x = (pressStartX + dx.toInt())
                params.y = BubbleDragMath.clampY(
                    y = pressStartY + dy.toInt(),
                    bubbleHeight = view.height,
                    screenHeight = screenHeight,
                    topInset = topInset,
                    bottomInset = bottomInset,
                )
                safeUpdate(context, view, params)
                return true
            }

            MotionEvent.ACTION_UP -> {
                velocityTracker?.addMovement(event)
                velocityTracker?.computeCurrentVelocity(1000)
                val vx = velocityTracker?.xVelocity ?: 0f
                val vy = velocityTracker?.yVelocity ?: 0f
                velocityTracker?.recycle()
                velocityTracker = null

                view.animate()
                    .scaleX(1f)
                    .scaleY(1f)
                    .setDuration(220)
                    .setInterpolator(BOUNCY_INTERPOLATOR)
                    .start()

                if (!dragging) {
                    view.performClick()
                    togglePopup(context)
                    return true
                }
                dragging = false
                val overDismiss = isOverDismissTarget(context, view, params, screenWidth, screenHeight)
                hideDismissTarget(context)
                if (overDismiss) {
                    snapshot?.let { dismissedSessionId = it.sessionId }
                    hide(context)
                } else {
                    animateSnap(context, view, params, vx, vy, screenWidth, screenHeight, topInset, bottomInset)
                }
                return true
            }

            MotionEvent.ACTION_CANCEL -> {
                velocityTracker?.recycle()
                velocityTracker = null
                dragging = false
                view.animate()
                    .scaleX(1f)
                    .scaleY(1f)
                    .setDuration(220)
                    .setInterpolator(BOUNCY_INTERPOLATOR)
                    .start()
                hideDismissTarget(context)
                animateSnap(context, view, params, 0f, 0f, screenWidth, screenHeight, topInset, bottomInset)
                return true
            }
        }
        return false
    }

    private fun animateSnap(
        context: Context,
        view: View,
        params: WindowManager.LayoutParams,
        velocityX: Float,
        velocityY: Float,
        screenWidth: Int,
        screenHeight: Int,
        topInset: Int,
        bottomInset: Int,
    ) {
        val (targetX, targetY) = BubbleDragMath.snapTarget(
            currentX = params.x,
            currentY = params.y,
            velocityX = velocityX,
            velocityY = velocityY,
            bubbleWidth = view.width,
            bubbleHeight = view.height,
            screenWidth = screenWidth,
            screenHeight = screenHeight,
            margin = dp(context, EDGE_MARGIN_DP),
            topInset = topInset,
            bottomInset = bottomInset,
        )
        val startX = params.x
        val startY = params.y
        snapAnimator?.cancel()
        snapAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = SNAP_DURATION_MS
            interpolator = BOUNCY_INTERPOLATOR
            addUpdateListener { animation ->
                val live = bubbleParams ?: return@addUpdateListener
                val fraction = animation.animatedValue as Float
                live.x = BubbleDragMath.lerp(startX, targetX, fraction)
                live.y = BubbleDragMath.lerp(startY, targetY, fraction)
                safeUpdate(context, view, live)
            }
            start()
        }
    }

    // ── Live popup ───────────────────────────────────────────────────────────

    private fun togglePopup(context: Context) {
        if (popupView != null) hidePopup(context) else showPopup(context)
    }

    @Suppress("ClickableViewAccessibility")
    private fun showPopup(context: Context) {
        if (popupView != null) return
        val current = snapshot ?: return
        val bubble = bubbleView ?: return
        val bubbleLayout = bubbleParams ?: return
        val windowManager = windowManager(context) ?: return

        restoreX = bubbleLayout.x
        restoreY = bubbleLayout.y

        val (screenWidth, screenHeight) = screenSize(windowManager)
        val (topInset, bottomInset) = verticalInsets(windowManager)

        val isBottom = BubbleDragMath.isBottomHalf(bubbleLayout.y, bubble.height, screenHeight)
        isPopupAtBottom = isBottom

        val targetX = BubbleDragMath.centeredX(bubble.width, screenWidth)
        val targetY = if (isBottom) {
            BubbleDragMath.restingBottomY(bottomInset, dp(context, OPEN_BOTTOM_MARGIN_DP), bubble.height, screenHeight)
        } else {
            BubbleDragMath.restingTopY(topInset, dp(context, OPEN_TOP_MARGIN_DP))
        }

        val view: View
        try {
            view = LayoutInflater.from(context).inflate(R.layout.workout_bubble_popup, null)
            bindPopup(context, view, current)
        } catch (e: Exception) {
            Log.w(TAG, "Could not build the workout bubble popup", e)
            return
        }

        val width = context.resources.getDimensionPixelSize(R.dimen.workout_bubble_popup_width)
        view.measure(
            View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED),
        )
        val height = view.measuredHeight
        val margin = dp(context, EDGE_MARGIN_DP)
        val gap = dp(context, POPUP_GAP_DP)

        val popupX = BubbleDragMath.centeredX(width, screenWidth).coerceAtLeast(margin)
        val popupY = if (isBottom) {
            (targetY - height - gap).coerceAtLeast(topInset + margin)
        } else {
            (targetY + bubble.height + gap)
                .coerceAtMost((screenHeight - height - margin).coerceAtLeast(margin))
        }

        val container = object : FrameLayout(context) {
            override fun dispatchKeyEvent(event: KeyEvent): Boolean {
                if (event.keyCode == KeyEvent.KEYCODE_BACK && event.action == KeyEvent.ACTION_UP) {
                    hidePopup(context)
                    return true
                }
                return super.dispatchKeyEvent(event)
            }
        }.apply {
            setBackgroundColor(Color.TRANSPARENT)
            isClickable = true
            isFocusable = true
            isFocusableInTouchMode = true
            setOnTouchListener { _, event ->
                if (event.actionMasked == MotionEvent.ACTION_DOWN) {
                    hidePopup(context)
                }
                true
            }
        }

        val cardParams = FrameLayout.LayoutParams(width, FrameLayout.LayoutParams.WRAP_CONTENT).apply {
            leftMargin = popupX
            topMargin = popupY
        }
        view.isClickable = true
        view.setOnClickListener {
            openActiveWorkout(context)
            hide(context)
        }
        container.addView(view, cardParams)

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        )

        view.pivotX = width / 2f
        view.pivotY = if (isBottom) height.toFloat() else 0f
        view.alpha = 0f
        view.scaleX = POPUP_ENTER_SCALE
        view.scaleY = POPUP_ENTER_SCALE
        view.translationY = if (isBottom) dp(context, POPUP_TRANSLATE_DP).toFloat() else -dp(context, POPUP_TRANSLATE_DP).toFloat()

        try {
            windowManager.addView(container, params)
            container.requestFocus()
            popupContainer = container
            popupView = view
        } catch (e: Exception) {
            Log.w(TAG, "Could not open the workout bubble popup", e)
            return
        }

        view.animate()
            .alpha(1f)
            .scaleX(1f)
            .scaleY(1f)
            .translationY(0f)
            .setDuration(POPUP_TRANSFORM_DURATION_MS)
            .setInterpolator(BOUNCY_INTERPOLATOR)
            .start()

        animateRelocate(context, bubble, bubbleLayout, targetX, targetY)
    }

    private fun hidePopup(context: Context, relocate: Boolean = true) {
        val container = popupContainer
        val view = popupView
        popupContainer = null
        popupView = null
        if (view == null && container == null) return
        view?.findViewById<Chronometer>(R.id.bubble_popup_elapsed)?.stop()

        if (!relocate || view == null || container == null) {
            view?.animate()?.cancel()
            if (container != null) {
                removePopupView(context, container)
            }
            return
        }

        val exitTranslationY = if (isPopupAtBottom) {
            dp(context, POPUP_TRANSLATE_DP).toFloat()
        } else {
            -dp(context, POPUP_TRANSLATE_DP).toFloat()
        }

        view.animate()
            .alpha(0f)
            .scaleX(POPUP_ENTER_SCALE)
            .scaleY(POPUP_ENTER_SCALE)
            .translationY(exitTranslationY)
            .setDuration(POPUP_TRANSFORM_DURATION_MS)
            .setInterpolator(MOTION_INTERPOLATOR)
            .withEndAction { removePopupView(context, container) }
            .start()

        val bubble = bubbleView
        val bubbleLayout = bubbleParams
        if (bubble != null && bubbleLayout != null) {
            animateRelocate(context, bubble, bubbleLayout, restoreX, restoreY)
        }
    }

    private fun removePopupView(context: Context, container: View) {
        try {
            windowManager(context)?.removeView(container)
        } catch (e: Exception) {
            Log.w(TAG, "Could not close the workout bubble popup", e)
        }
    }

    private fun animateRelocate(
        context: Context,
        view: View,
        params: WindowManager.LayoutParams,
        targetX: Int,
        targetY: Int,
    ) {
        val startX = params.x
        val startY = params.y
        relocateAnimator?.cancel()
        relocateAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = RELOCATE_DURATION_MS
            interpolator = BOUNCY_INTERPOLATOR
            addUpdateListener { animation ->
                val live = bubbleParams ?: return@addUpdateListener
                val fraction = animation.animatedValue as Float
                live.x = BubbleDragMath.lerp(startX, targetX, fraction)
                live.y = BubbleDragMath.lerp(startY, targetY, fraction)
                safeUpdate(context, view, live)
            }
            start()
        }
    }

    private fun bindPopup(context: Context, root: View, current: BubbleSnapshot) {
        root.setOnClickListener {
            openActiveWorkout(context)
            hide(context)
        }
        root.findViewById<TextView>(R.id.bubble_popup_exercise).text = current.exerciseName
        root.findViewById<TextView>(R.id.bubble_popup_subtitle).text = current.subtitle
        root.findViewById<TextView>(R.id.bubble_popup_set_num).text = current.setNumber
        root.findViewById<TextView>(R.id.bubble_popup_weight).text = current.weight
        root.findViewById<TextView>(R.id.bubble_popup_reps).text = current.reps
        root.findViewById<TextView>(R.id.bubble_popup_rpe).text = current.rpe
        root.findViewById<TextView>(R.id.bubble_popup_stats_sets).text = current.totalSetsText
        root.findViewById<TextView>(R.id.bubble_popup_stats_volume).text = current.tonnageText

        val lastSetView = root.findViewById<TextView>(R.id.bubble_popup_last_perf)
        if (current.lastSetText.isNullOrBlank()) {
            lastSetView.visibility = View.GONE
        } else {
            lastSetView.text = current.lastSetText
            lastSetView.visibility = View.VISIBLE
        }

        val chronometer = root.findViewById<Chronometer>(R.id.bubble_popup_elapsed)
        chronometer.base =
            SystemClock.elapsedRealtime() - (System.currentTimeMillis() - current.startedAtEpochMs)
        chronometer.start()

        // Editable KG pill
        root.findViewById<View>(R.id.bubble_popup_weight).setOnClickListener {
            showNumberInputDialog(
                context = context,
                title = "Weight (kg)",
                initialValue = current.weight,
                isDecimal = true,
            ) { newVal ->
                dispatchAction(context, "edit_weight", newVal)
            }
        }

        // Editable REPS pill
        root.findViewById<View>(R.id.bubble_popup_reps).setOnClickListener {
            showNumberInputDialog(
                context = context,
                title = "Reps",
                initialValue = current.reps,
                isDecimal = false,
            ) { newVal ->
                dispatchAction(context, "edit_reps", newVal)
            }
        }

        // Editable RPE pill
        root.findViewById<View>(R.id.bubble_popup_rpe).setOnClickListener {
            showRpePickerDialog(context, current.rpe) { newVal ->
                dispatchAction(context, "edit_rpe", newVal)
            }
        }

        // Complete set checkmark
        root.findViewById<View>(R.id.bubble_popup_done_btn).setOnClickListener {
            dispatchAction(context, "complete_set")
        }

        // + Exercise button
        root.findViewById<View>(R.id.bubble_popup_btn_exercise).setOnClickListener {
            openActiveWorkout(context, "add_exercise")
            hidePopup(context)
        }

        // ✓ Finish button
        root.findViewById<View>(R.id.bubble_popup_btn_finish).setOnClickListener {
            openActiveWorkout(context, "finish_workout")
            hidePopup(context)
        }
    }

    private fun showNumberInputDialog(
        context: Context,
        title: String,
        initialValue: String,
        isDecimal: Boolean,
        onConfirmed: (String) -> Unit,
    ) {
        val themedContext = ContextThemeWrapper(context, android.R.style.Theme_DeviceDefault_Dialog_Alert)
        val editText = EditText(themedContext).apply {
            inputType = if (isDecimal) {
                InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_FLAG_DECIMAL
            } else {
                InputType.TYPE_CLASS_NUMBER
            }
            if (initialValue != "-") {
                setText(initialValue)
                setSelection(initialValue.length)
            }
            setPadding(dp(context, 20), dp(context, 16), dp(context, 20), dp(context, 16))
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
        }

        val dialog = AlertDialog.Builder(themedContext)
            .setTitle(title)
            .setView(editText)
            .setPositiveButton("Save") { _, _ ->
                val text = editText.text.toString().trim()
                if (text.isNotEmpty()) {
                    onConfirmed(text)
                }
            }
            .setNegativeButton("Cancel", null)
            .create()

        dialog.window?.let { win ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                win.setType(WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY)
            } else {
                @Suppress("DEPRECATION")
                win.setType(WindowManager.LayoutParams.TYPE_SYSTEM_ALERT)
            }
            win.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_VISIBLE)
        }

        try {
            dialog.show()
            editText.requestFocus()
        } catch (e: Exception) {
            Log.w(TAG, "Could not show input dialog overlay", e)
        }
    }

    private fun showRpePickerDialog(
        context: Context,
        currentRpe: String,
        onConfirmed: (String) -> Unit,
    ) {
        val themedContext = ContextThemeWrapper(context, android.R.style.Theme_DeviceDefault_Dialog_Alert)
        val rpeOptions = arrayOf("6.0", "6.5", "7.0", "7.5", "8.0", "8.5", "9.0", "9.5", "10.0")
        val dialog = AlertDialog.Builder(themedContext)
            .setTitle("Select RPE")
            .setItems(rpeOptions) { _, which ->
                onConfirmed(rpeOptions[which])
            }
            .setNegativeButton("Cancel", null)
            .create()

        dialog.window?.let { win ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                win.setType(WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY)
            } else {
                @Suppress("DEPRECATION")
                win.setType(WindowManager.LayoutParams.TYPE_SYSTEM_ALERT)
            }
        }

        try {
            dialog.show()
        } catch (e: Exception) {
            Log.w(TAG, "Could not show RPE dialog overlay", e)
        }
    }

    private fun dispatchAction(context: Context, actionId: String, value: String? = null) {
        val current = snapshot ?: return
        val sink = onAction
        if (sink == null) {
            openActiveWorkout(context)
            hide(context)
            return
        }
        sink(actionId, current.sessionId, current.targetSetId, value)
    }

    /**
     * Opens active workout screen and optionally dispatches an action.
     */
    private fun openActiveWorkout(context: Context, action: String? = null) {
        val intent = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            putExtra("open_active_workout", true)
            if (action != null) {
                putExtra("workout_action", action)
            }
        }
        try {
            context.startActivity(intent)
        } catch (e: Exception) {
            Log.w(TAG, "Could not open the active workout from the bubble", e)
        }
    }

    // ── Drop-to-dismiss target ───────────────────────────────────────────────

    private fun showDismissTarget(context: Context) {
        if (dismissView != null) return
        val windowManager = windowManager(context) ?: return
        val view = LayoutInflater.from(context).inflate(R.layout.workout_bubble_dismiss, null)
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            y = dp(context, DISMISS_BOTTOM_MARGIN_DP)
        }
        try {
            windowManager.addView(view, params)
            dismissView = view
        } catch (e: Exception) {
            Log.w(TAG, "Could not add the bubble dismiss target", e)
        }
    }

    private fun hideDismissTarget(context: Context) {
        val view = dismissView ?: return
        dismissView = null
        try {
            windowManager(context)?.removeView(view)
        } catch (e: Exception) {
            Log.w(TAG, "Could not remove the bubble dismiss target", e)
        }
    }

    private fun isOverDismissTarget(
        context: Context,
        view: View,
        params: WindowManager.LayoutParams,
        screenWidth: Int,
        screenHeight: Int,
    ): Boolean {
        val dismissHeight = dismissView?.height?.takeIf { it > 0 }
            ?: dp(context, DISMISS_SIZE_DP)
        return BubbleDragMath.isOverDismissTarget(
            bubbleX = params.x,
            bubbleY = params.y,
            bubbleWidth = view.width,
            bubbleHeight = view.height,
            dismissCentreX = screenWidth / 2,
            dismissCentreY = screenHeight - dp(context, DISMISS_BOTTOM_MARGIN_DP) - dismissHeight / 2,
            captureRadius = dp(context, DISMISS_CAPTURE_RADIUS_DP),
        )
    }

    // ── Platform helpers ─────────────────────────────────────────────────────

    private fun windowManager(context: Context): WindowManager? =
        context.applicationContext.getSystemService(Context.WINDOW_SERVICE) as? WindowManager

    private fun safeUpdate(context: Context, view: View, params: WindowManager.LayoutParams) {
        try {
            windowManager(context)?.updateViewLayout(view, params)
        } catch (e: Exception) {
            Log.w(TAG, "Could not move the workout bubble", e)
        }
    }

    private fun dp(context: Context, value: Int): Int =
        (value * context.resources.displayMetrics.density).toInt()

    private fun screenSize(windowManager: WindowManager): Pair<Int, Int> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bounds = windowManager.currentWindowMetrics.bounds
            return bounds.width() to bounds.height()
        }
        @Suppress("DEPRECATION")
        val size = Point().also { windowManager.defaultDisplay.getSize(it) }
        return size.x to size.y
    }

    private fun verticalInsets(windowManager: WindowManager): Pair<Int, Int> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val insets = windowManager.currentWindowMetrics.windowInsets.getInsetsIgnoringVisibility(
                WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout(),
            )
            return insets.top to insets.bottom
        }
        return 0 to 0
    }
}
