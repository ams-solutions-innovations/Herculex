package com.ams.herculex.tile

import android.content.Context

/**
 * Tiny prefs-backed state for the two timer tiles. A tile cannot hold state,
 * so Start / Stop / ± arrive as LoadAction clicks and mutate this, then the
 * next tileRequest renders from it.
 */
class SetTimerStore(context: Context, name: String) {
    private val p = context.applicationContext.getSharedPreferences("hx_timer_$name", Context.MODE_PRIVATE)

    enum class Mode { IDLE, RUN, DONE }

    var mode: Mode
        get() = Mode.valueOf(p.getString("mode", Mode.IDLE.name)!!)
        private set(v) { p.edit().putString("mode", v.name).apply() }
    var startedAtMs: Long
        get() = p.getLong("started", 0L)
        private set(v) { p.edit().putLong("started", v).apply() }
    var elapsedMs: Long // frozen value once DONE
        get() = p.getLong("elapsed", 0L)
        private set(v) { p.edit().putLong("elapsed", v).apply() }
    var distanceM: Int
        get() = p.getInt("dist", 0)
        private set(v) { p.edit().putInt("dist", v).apply() }

    fun start(now: Long = System.currentTimeMillis()) { startedAtMs = now; elapsedMs = 0; distanceM = 0; mode = Mode.RUN }
    fun stop(now: Long = System.currentTimeMillis()) { if (mode == Mode.RUN) { elapsedMs = now - startedAtMs; mode = Mode.DONE } }
    fun reset() { elapsedMs = 0; distanceM = 0; mode = Mode.IDLE }
    fun nudgeDistance(delta: Int) { if (mode != Mode.IDLE) distanceM = (distanceM + delta).coerceAtLeast(0) }
    fun elapsedNow(now: Long = System.currentTimeMillis()): Long = if (mode == Mode.RUN) now - startedAtMs else elapsedMs
}
