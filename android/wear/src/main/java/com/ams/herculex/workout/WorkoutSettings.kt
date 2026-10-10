package com.ams.herculex.workout

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/// Watch-local workout preferences (not synced with the phone).
object WorkoutSettings {

    private const val PREFS = "herculex_workout_settings"
    private const val KEY_KEEP_AWAKE = "keep_awake"

    private val _keepAwake = MutableStateFlow(false)

    /// Keep the screen on while a workout is running. Off by default: a lit
    /// OLED all session is a real battery cost, so it is an explicit choice.
    val keepAwake: StateFlow<Boolean> = _keepAwake.asStateFlow()

    /// Loads the persisted value; call once before the UI reads [keepAwake].
    fun init(context: Context) {
        _keepAwake.value = prefs(context).getBoolean(KEY_KEEP_AWAKE, false)
    }

    fun setKeepAwake(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_KEEP_AWAKE, enabled).apply()
        _keepAwake.value = enabled
    }

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
