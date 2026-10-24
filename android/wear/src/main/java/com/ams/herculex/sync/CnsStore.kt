package com.ams.herculex.sync

import android.content.Context
import android.content.SharedPreferences

object CnsStore {
    private const val PREFS = "herculex_cns"
    private const val KEY_READINESS_PCT = "readiness_pct"
    private const val KEY_STATUS = "status"
    private const val KEY_UPDATED_AT = "updated_at"

    fun save(context: Context, readinessPct: Int, status: String) {
        prefs(context).edit()
            .putInt(KEY_READINESS_PCT, readinessPct.coerceIn(0, 100))
            .putString(KEY_STATUS, status)
            .putLong(KEY_UPDATED_AT, System.currentTimeMillis())
            .apply()
    }

    fun readinessPct(context: Context): Int =
        prefs(context).getInt(KEY_READINESS_PCT, 100)

    fun status(context: Context): String =
        prefs(context).getString(KEY_STATUS, "FRESH") ?: "FRESH"

    fun updatedAt(context: Context): Long =
        prefs(context).getLong(KEY_UPDATED_AT, 0L)

    private fun prefs(context: Context): SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
