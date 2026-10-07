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
    val maxVolume: Int = 15,
    val volumePercent: Int = 50,
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
        // The phone's quick post-command updates carry no artwork (they must
        // stay small to be fast). Keep the cover we already have for the same
        // track instead of flashing to the placeholder.
        val current = _mediaFlow.value
        _mediaFlow.value = if (parsed.artwork == null && current?.artwork != null && current.title == parsed.title) {
            parsed.copy(artwork = current.artwork)
        } else {
            parsed
        }

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

    // Every state message used to re-decode the same cover from base64.
    private var cachedArtworkKey: Int = 0
    private var cachedArtwork: Bitmap? = null

    private fun decodeArtwork(encoded: String): Bitmap? {
        val key = encoded.hashCode()
        if (key == cachedArtworkKey && cachedArtwork != null) return cachedArtwork
        val bitmap = runCatching {
            val bytes = Base64.decode(encoded, Base64.DEFAULT)
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
        }.getOrNull()
        cachedArtworkKey = key
        cachedArtwork = bitmap
        return bitmap
    }

    private fun parse(json: String): SyncedMediaInfo? {
        return try {
            val obj = JSONObject(json)
            val app = obj.optString("appName", "")
            val pkg = obj.optString("packageName", "")
            val explicitSpotify = obj.optBoolean("isSpotify", false)
            val isSpotify = explicitSpotify || app.contains("spotify", ignoreCase = true) || pkg.contains("spotify", ignoreCase = true)
            val vol = obj.optInt("volume", 0)
            val maxVol = obj.optInt("maxVolume", 15)
            val explicitPercent = obj.optInt("volumePercent", -1)
            val volumePercent = if (explicitPercent >= 0) explicitPercent else if (maxVol > 0) vol * 100 / maxVol else 50
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
                volume = vol,
                maxVolume = maxVol,
                volumePercent = volumePercent,
                updatedAtEpochMs = obj.optLong("updatedAtEpochMs", System.currentTimeMillis()),
                artwork = obj.optString("artworkBase64", "").takeIf { it.isNotBlank() }?.let(::decodeArtwork),
            )
        } catch (_: Exception) {
            null
        }
    }
}
