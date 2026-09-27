package com.ams.herculex.media

import android.content.Context
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Base64
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONObject

data class SyncedMediaInfo(
    val title: String = "",
    val artist: String = "",
    val album: String = "",
    val isPlaying: Boolean = false,
    val appName: String = "",
    val packageName: String = "",
    val isSpotify: Boolean = false,
    val hasPermission: Boolean = false,
    val positionMs: Long = 0L,
    val durationMs: Long = 0L,
    val volume: Int = 0,
    val updatedAtEpochMs: Long = 0L,
    val artwork: Bitmap? = null,
) {
    val hasContent: Boolean get() = title.isNotBlank() && title != "No track playing"
}

object WearMediaStore {
    private const val PREFS_NAME = "wear_media_store"
    private const val KEY_MEDIA_JSON = "media_json"

    private val _mediaFlow = MutableStateFlow<SyncedMediaInfo?>(null)
    val mediaFlow: StateFlow<SyncedMediaInfo?> = _mediaFlow.asStateFlow()

    private var initialized = false

    fun init(context: Context) {
        if (initialized) return
        initialized = true
        val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val raw = prefs.getString(KEY_MEDIA_JSON, null)
        if (!raw.isNullOrBlank()) {
            _mediaFlow.value = parse(raw)
        }
    }

    fun save(context: Context, json: String) {
        if (json.isBlank()) return
        val parsed = parse(json) ?: return
        _mediaFlow.value = parsed

        context.applicationContext
            .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_MEDIA_JSON, json)
            .apply()
    }

    fun current(): SyncedMediaInfo? = _mediaFlow.value

    fun updateOptimisticPlaying(isPlaying: Boolean) {
        val cur = _mediaFlow.value ?: return
        _mediaFlow.value = cur.copy(isPlaying = isPlaying)
    }

    private fun parse(json: String): SyncedMediaInfo? {
        return try {
            val obj = JSONObject(json)
            val app = obj.optString("appName", "")
            val pkg = obj.optString("packageName", "")
            val explicitSpotify = obj.optBoolean("isSpotify", false)
            val isSpotify = explicitSpotify || app.contains("spotify", ignoreCase = true) || pkg.contains("spotify", ignoreCase = true)
            SyncedMediaInfo(
                title = obj.optString("title", ""),
                artist = obj.optString("artist", ""),
                album = obj.optString("album", ""),
                isPlaying = obj.optBoolean("isPlaying", false),
                appName = if (app.isNotBlank()) app else (if (isSpotify) "Spotify" else "Music"),
                packageName = pkg,
                isSpotify = isSpotify,
                hasPermission = obj.optBoolean("hasPermission", false),
                positionMs = obj.optLong("positionMs", 0L),
                durationMs = obj.optLong("durationMs", 0L),
                volume = obj.optInt("volume", 0),
                updatedAtEpochMs = obj.optLong("updatedAtEpochMs", System.currentTimeMillis()),
                artwork = obj.optString("artworkBase64", "").takeIf { it.isNotBlank() }?.let { encoded ->
                    runCatching {
                        val bytes = Base64.decode(encoded, Base64.DEFAULT)
                        BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                    }.getOrNull()
                },
            )
        } catch (_: Exception) {
            null
        }
    }
}
