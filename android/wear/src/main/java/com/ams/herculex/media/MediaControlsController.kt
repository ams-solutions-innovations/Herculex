package com.ams.herculex.media

import android.content.ComponentName
import android.content.Context
import android.graphics.Bitmap
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.provider.MediaStore
import android.provider.Settings
import android.view.KeyEvent
import com.ams.herculex.sync.WearDataLayerSyncManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class MediaControlsState(
    val title: String = "No active media",
    val artist: String = "Play on phone or watch",
    val isPlaying: Boolean = false,
    val hasSession: Boolean = false,
    val source: String = "none",
    val volume: Int = 0,
    val maxVolume: Int = 15,
    val artwork: Bitmap? = null,
    val positionMs: Long = 0L,
    val durationMs: Long = 0L,
    val isSpotify: Boolean = false,
    val appName: String = "Spotify",
    val updatedAtEpochMs: Long = 0L,
) {
    /**
     * Calculates the estimated current playback position in milliseconds.
     */
    fun estimatedPositionMs(): Long {
        if (!isPlaying || durationMs <= 0L || updatedAtEpochMs <= 0L) return positionMs
        val elapsed = System.currentTimeMillis() - updatedAtEpochMs
        return (positionMs + elapsed).coerceIn(0L, durationMs)
    }

    /**
     * Progress between 0f and 1f.
     */
    val progress: Float
        get() {
            if (durationMs <= 0L) return 0f
            return (estimatedPositionMs().toFloat() / durationMs.toFloat()).coerceIn(0f, 1f)
        }
}

/**
 * Unified media controller combining:
 * 1. Synced Phone Media State (via [WearMediaStore])
 * 2. Local Watch Media Sessions (via [MediaSessionManager])
 * 3. Local Audio & Media Key fallback (via [AudioManager])
 * 4. Realtime command dispatch to connected phone (via [WearDataLayerSyncManager])
 *
 * Never blocks the UI behind a permission gate — always keeps transport controls ready.
 */
class MediaControlsController(private val context: Context) {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val syncManager = WearDataLayerSyncManager(context)
    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val sessionManager = context.getSystemService(MediaSessionManager::class.java)
    private val listenerComponent = ComponentName(context, MediaNotificationListenerService::class.java)

    private val _stateFlow = MutableStateFlow(snapshot())
    val stateFlow: StateFlow<MediaControlsState> = _stateFlow.asStateFlow()

    private var activeLocalController: MediaController? = null
    private var optimisticIsPlaying: Boolean? = null
    private var syncedMediaJob: Job? = null

    private val controllerCallback = object : MediaController.Callback() {
        override fun onPlaybackStateChanged(state: PlaybackState?) {
            _stateFlow.value = snapshot()
        }

        override fun onMetadataChanged(metadata: MediaMetadata?) {
            _stateFlow.value = snapshot()
        }

        override fun onSessionDestroyed() {
            attachToActiveLocalSession()
        }
    }

    private val activeSessionsListener = MediaSessionManager.OnActiveSessionsChangedListener {
        attachToActiveLocalSession()
    }

    init {
        WearMediaStore.init(context)
    }

    fun start() {
        runCatching {
            sessionManager.addOnActiveSessionsChangedListener(activeSessionsListener, listenerComponent)
        }
        attachToActiveLocalSession()

        // Listen for phone-synced media state updates
        syncedMediaJob?.cancel()
        syncedMediaJob = scope.launch {
            WearMediaStore.mediaFlow.collect {
                _stateFlow.value = snapshot()
            }
        }
    }

    fun stop() {
        activeLocalController?.unregisterCallback(controllerCallback)
        activeLocalController = null
        syncedMediaJob?.cancel()
        syncedMediaJob = null
        runCatching { sessionManager.removeOnActiveSessionsChangedListener(activeSessionsListener) }
    }

    fun refresh() {
        attachToActiveLocalSession()
    }

    fun playPause() {
        val currentPlaying = _stateFlow.value.isPlaying
        val targetPlaying = !currentPlaying
        optimisticIsPlaying = targetPlaying
        WearMediaStore.updateOptimisticPlaying(targetPlaying)
        _stateFlow.value = snapshot()

        // 1. If local active session exists, toggle local transport
        val local = activeLocalController
        if (local != null) {
            if (local.playbackState?.state == PlaybackState.STATE_PLAYING) {
                local.transportControls.pause()
            } else {
                local.transportControls.play()
            }
        }

        // 2. Dispatch local media key event
        sendMediaKey(KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE)

        // 3. Send remote command to phone companion
        scope.launch {
            syncManager.sendMediaCommand("play_pause")
        }
    }

    fun next() {
        val local = activeLocalController
        if (local != null) {
            local.transportControls.skipToNext()
        }
        sendMediaKey(KeyEvent.KEYCODE_MEDIA_NEXT)
        scope.launch {
            syncManager.sendMediaCommand("next")
        }
    }

    fun previous() {
        val local = activeLocalController
        if (local != null) {
            local.transportControls.skipToPrevious()
        }
        sendMediaKey(KeyEvent.KEYCODE_MEDIA_PREVIOUS)
        scope.launch {
            syncManager.sendMediaCommand("previous")
        }
    }

    fun setVolume(volume: Int) {
        val maxVol = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        val clamped = volume.coerceIn(0, maxVol)
        try {
            audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, clamped, 0)
        } catch (_: Exception) {}

        _stateFlow.value = _stateFlow.value.copy(volume = clamped)
        scope.launch {
            syncManager.sendMediaCommand("set_volume", clamped)
        }
    }

    fun getVolume(): Int = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
    fun getMaxVolume(): Int = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)

    fun openSystemPlayer() {
        val intent = android.content.Intent(MediaStore.INTENT_ACTION_MUSIC_PLAYER)
            .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching { context.startActivity(intent) }
            .recover {
                runCatching {
                    context.startActivity(
                        android.content.Intent(Settings.ACTION_SOUND_SETTINGS)
                            .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
                }
            }
    }

    private fun attachToActiveLocalSession() {
        activeLocalController?.unregisterCallback(controllerCallback)
        val next = findActiveLocalController()
        activeLocalController = next
        next?.registerCallback(controllerCallback)
        _stateFlow.value = snapshot()
    }

    private fun findActiveLocalController(): MediaController? {
        return try {
            val sessions = sessionManager.getActiveSessions(listenerComponent)
            sessions.firstOrNull { it.playbackState?.state == PlaybackState.STATE_PLAYING }
                ?: sessions.firstOrNull()
        } catch (_: Exception) {
            null
        }
    }

    private fun snapshot(): MediaControlsState {
        val local = activeLocalController
        val synced = WearMediaStore.current()

        val vol = try { audioManager.getStreamVolume(AudioManager.STREAM_MUSIC) } catch (_: Exception) { 8 }
        val maxVol = try { audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC) } catch (_: Exception) { 15 }

        val localArtwork = local?.metadata?.let { metadata ->
            metadata.getBitmap(MediaMetadata.METADATA_KEY_ART)
                ?: metadata.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART)
                ?: metadata.getBitmap(MediaMetadata.METADATA_KEY_DISPLAY_ICON)
        }

        // Local watch playback has precedence if actively playing
        if (local != null && local.playbackState?.state == PlaybackState.STATE_PLAYING) {
            val metadata = local.metadata
            val title = metadata?.getString(MediaMetadata.METADATA_KEY_TITLE)
                ?: metadata?.getString(MediaMetadata.METADATA_KEY_DISPLAY_TITLE)
                ?: "Playing on Watch"
            val artist = metadata?.getString(MediaMetadata.METADATA_KEY_ARTIST)
                ?: metadata?.getString(MediaMetadata.METADATA_KEY_DISPLAY_SUBTITLE)
                ?: "Local Player"
            val duration = metadata?.getLong(MediaMetadata.METADATA_KEY_DURATION) ?: 0L
            val position = local.playbackState?.position ?: 0L
            val isSpotify = local.packageName.contains("spotify", ignoreCase = true)
            return MediaControlsState(
                title = title,
                artist = artist,
                isPlaying = true,
                hasSession = true,
                source = "watch",
                volume = vol,
                maxVolume = maxVol,
                artwork = localArtwork,
                positionMs = position,
                durationMs = duration,
                isSpotify = isSpotify,
                appName = if (isSpotify) "Spotify" else "Watch Player",
                updatedAtEpochMs = System.currentTimeMillis(),
            )
        }

        // Check synced phone media state
        if (synced != null && synced.hasContent) {
            val isPlaying = optimisticIsPlaying ?: synced.isPlaying
            return MediaControlsState(
                title = synced.title,
                artist = if (synced.artist.isNotBlank()) synced.artist else "Spotify",
                isPlaying = isPlaying,
                hasSession = true,
                source = "phone",
                volume = vol,
                maxVolume = maxVol,
                artwork = localArtwork,
                positionMs = synced.positionMs,
                durationMs = synced.durationMs,
                isSpotify = synced.isSpotify,
                appName = synced.appName.ifBlank { if (synced.isSpotify) "Spotify" else "Music" },
                updatedAtEpochMs = synced.updatedAtEpochMs,
            )
        }

        // Fallback to local session metadata if available
        if (local != null) {
            val metadata = local.metadata
            val title = metadata?.getString(MediaMetadata.METADATA_KEY_TITLE)
                ?: metadata?.getString(MediaMetadata.METADATA_KEY_DISPLAY_TITLE)
                ?: "Music Controls"
            val artist = metadata?.getString(MediaMetadata.METADATA_KEY_ARTIST)
                ?: metadata?.getString(MediaMetadata.METADATA_KEY_DISPLAY_SUBTITLE)
                ?: "Ready to play"
            val isPlaying = optimisticIsPlaying ?: (local.playbackState?.state == PlaybackState.STATE_PLAYING)
            val duration = metadata?.getLong(MediaMetadata.METADATA_KEY_DURATION) ?: 0L
            val position = local.playbackState?.position ?: 0L
            val isSpotify = local.packageName.contains("spotify", ignoreCase = true)
            return MediaControlsState(
                title = title,
                artist = artist,
                isPlaying = isPlaying,
                hasSession = true,
                source = "watch",
                volume = vol,
                maxVolume = maxVol,
                artwork = localArtwork,
                positionMs = position,
                durationMs = duration,
                isSpotify = isSpotify,
                appName = if (isSpotify) "Spotify" else "Watch Player",
                updatedAtEpochMs = System.currentTimeMillis(),
            )
        }

        // Default standby state
        val isPlaying = optimisticIsPlaying ?: false
        return MediaControlsState(
            title = if (isPlaying) "Playing on Phone" else "No Active Media",
            artist = "Start Spotify on phone or watch",
            isPlaying = isPlaying,
            hasSession = false,
            source = "none",
            volume = vol,
            maxVolume = maxVol,
            artwork = null,
            isSpotify = true,
            appName = "Spotify",
            updatedAtEpochMs = System.currentTimeMillis(),
        )
    }

    private fun sendMediaKey(keyCode: Int) {
        try {
            val down = KeyEvent(KeyEvent.ACTION_DOWN, keyCode)
            val up = KeyEvent(KeyEvent.ACTION_UP, keyCode)
            audioManager.dispatchMediaKeyEvent(down)
            audioManager.dispatchMediaKeyEvent(up)
        } catch (_: Exception) {}
    }
}
