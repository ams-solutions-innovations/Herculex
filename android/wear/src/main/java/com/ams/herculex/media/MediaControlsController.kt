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
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.concurrent.atomic.AtomicInteger

data class MediaControlsState(
    val title: String = "No active media",
    val artist: String = "Play on phone or watch",
    val isPlaying: Boolean = false,
    val hasSession: Boolean = false,
    val source: String = "none",
    val volume: Int = 0,
    val maxVolume: Int = 15,
    val volumePercent: Int = 50,
    val artwork: Bitmap? = null,
    val positionMs: Long = 0L,
    val durationMs: Long = 0L,
    val isSpotify: Boolean = false,
    val appName: String = "Spotify",
    val packageName: String = "",
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

    private companion object {
        const val OPTIMISTIC_PLAY_GRACE_MS = 2500L
        const val VOLUME_ECHO_GRACE_MS = 1500L
        const val VOLUME_SEND_INTERVAL_MS = 120L
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val syncManager = WearDataLayerSyncManager(context)
    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val sessionManager = context.getSystemService(MediaSessionManager::class.java)

    private val _stateFlow = MutableStateFlow(snapshot())
    val stateFlow: StateFlow<MediaControlsState> = _stateFlow.asStateFlow()

    private var activeLocalController: MediaController? = null
    private var syncedMediaJob: Job? = null

    // ── Optimistic UI ────────────────────────────────────────────────────
    // A tap or a bezel detent updates the screen at once; the phone's
    // confirmation arrives 0.3–1.5 s later. State that lands in between is
    // usually *older* than the tap (a periodic poll, or the phone echoing a
    // volume change with a stale play state), and applying it made the play
    // button and the volume jump back and forth. Hold the optimistic value
    // until the phone agrees or the grace period runs out.
    @Volatile private var optimisticIsPlaying: Boolean? = null
    @Volatile private var optimisticPlayingAtMs = 0L
    @Volatile private var lastVolumeInputAtMs = 0L

    // Bezel detents arrive far faster than Bluetooth round-trips. Only the
    // latest target is sent, at most every [VOLUME_SEND_INTERVAL_MS].
    private val pendingVolumePercent = AtomicInteger(-1)
    private var volumeSendJob: Job? = null

    private val controllerCallback = object : MediaController.Callback() {
        override fun onPlaybackStateChanged(state: PlaybackState?) {
            publish()
        }

        override fun onMetadataChanged(metadata: MediaMetadata?) {
            publish()
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
            sessionManager.addOnActiveSessionsChangedListener(activeSessionsListener, null)
        }
        attachToActiveLocalSession()

        // Listen for phone-synced media state updates
        syncedMediaJob?.cancel()
        syncedMediaJob = scope.launch {
            WearMediaStore.mediaFlow.collect { publish() }
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
        optimisticPlayingAtMs = System.currentTimeMillis()
        _stateFlow.value = _stateFlow.value.copy(isPlaying = targetPlaying)

        val local = activeLocalController
        val pkg = _stateFlow.value.packageName.ifBlank { WearMediaStore.current()?.packageName.orEmpty() }

        // A phone session is mirrored over the data layer OR no active local player on watch:
        if (WearMediaStore.current()?.hasContent == true || (local == null && _stateFlow.value.source != "watch")) {
            scope.launch { syncManager.sendMediaCommand("play_pause", packageName = pkg) }
            return
        }
        if (local != null) {
            if (local.playbackState?.state == PlaybackState.STATE_PLAYING) {
                local.transportControls.pause()
            } else {
                local.transportControls.play()
            }
        } else {
            sendMediaKey(KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE)
        }
    }

    fun next() {
        val local = activeLocalController
        val pkg = _stateFlow.value.packageName.ifBlank { WearMediaStore.current()?.packageName.orEmpty() }
        if (WearMediaStore.current()?.hasContent == true || (local == null && _stateFlow.value.source != "watch")) {
            scope.launch { syncManager.sendMediaCommand("next", packageName = pkg) }
        } else if (local != null) {
            local.transportControls.skipToNext()
        } else {
            sendMediaKey(KeyEvent.KEYCODE_MEDIA_NEXT)
        }
    }

    fun previous() {
        val local = activeLocalController
        val pkg = _stateFlow.value.packageName.ifBlank { WearMediaStore.current()?.packageName.orEmpty() }
        if (WearMediaStore.current()?.hasContent == true || (local == null && _stateFlow.value.source != "watch")) {
            scope.launch { syncManager.sendMediaCommand("previous", packageName = pkg) }
        } else if (local != null) {
            local.transportControls.skipToPrevious()
        } else {
            sendMediaKey(KeyEvent.KEYCODE_MEDIA_PREVIOUS)
        }
    }

    /**
     * One volume step up (+1) or down (-1), driven by the rotating bezel.
     * Follows the transport rule: when a phone session is mirrored the phone's
     * music volume changes, otherwise the watch's own stream does.
     *
     * For the phone, one detent is exactly one of the phone's own volume
     * steps, so what the ring shows is what the phone lands on — the old
     * fixed 100/15 % step drifted from it and then snapped back.
     */
    fun adjustVolume(direction: Int) {
        if (direction == 0) return
        val current = _stateFlow.value
        lastVolumeInputAtMs = System.currentTimeMillis()

        val synced = WearMediaStore.current()
        if (synced?.hasContent == true || current.source == "phone") {
            val phoneMax = synced?.maxVolume?.takeIf { it > 0 } ?: 15
            val step = 100f / phoneMax
            val newPercent = Math.round(current.volumePercent + direction * step).coerceIn(0, 100)
            _stateFlow.value = current.copy(volumePercent = newPercent)
            sendVolumePercent(newPercent, current.packageName.ifBlank { synced?.packageName.orEmpty() })
            return
        }
        try {
            audioManager.adjustStreamVolume(
                AudioManager.STREAM_MUSIC,
                if (direction > 0) AudioManager.ADJUST_RAISE else AudioManager.ADJUST_LOWER,
                0,
            )
            val vol = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
            val max = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
            _stateFlow.value = current.copy(volume = vol, maxVolume = max, volumePercent = vol * 100 / max)
        } catch (_: Exception) {}
    }

    private fun sendVolumePercent(percent: Int, packageName: String) {
        pendingVolumePercent.set(percent)
        if (volumeSendJob?.isActive == true) return
        volumeSendJob = scope.launch {
            while (true) {
                val next = pendingVolumePercent.getAndSet(-1)
                if (next < 0) break
                syncManager.sendMediaCommand(
                    action = "set_volume_percent",
                    value = next,
                    packageName = packageName,
                )
                delay(VOLUME_SEND_INTERVAL_MS)
            }
        }
    }

    fun setVolume(volume: Int) {
        lastVolumeInputAtMs = System.currentTimeMillis()
        val current = _stateFlow.value
        val maxVol = if (current.maxVolume > 0) current.maxVolume else audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        val clamped = volume.coerceIn(0, maxVol)
        val percent = if (maxVol > 0) clamped * 100 / maxVol else 0
        _stateFlow.value = current.copy(volume = clamped, volumePercent = percent)

        val pkg = current.packageName.ifBlank { WearMediaStore.current()?.packageName.orEmpty() }

        if (WearMediaStore.current()?.hasContent == true || current.source == "phone") {
            scope.launch {
                syncManager.sendMediaCommand(
                    action = "set_volume_percent",
                    value = percent,
                    packageName = pkg,
                )
            }
            return
        }
        try {
            audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, clamped, 0)
        } catch (_: Exception) {}
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

    fun hasMediaAccess(): Boolean {
        val enabled = Settings.Secure.getString(
            context.contentResolver,
            "enabled_notification_listeners",
        ).orEmpty()
        return enabled.contains(WatchMediaNotificationListenerService::class.java.name)
    }

    fun openMediaAccessSettings() {
        context.startActivity(
            android.content.Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS")
                .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK),
        )
    }

    private fun attachToActiveLocalSession() {
        activeLocalController?.unregisterCallback(controllerCallback)
        val next = findActiveLocalController()
        activeLocalController = next
        next?.registerCallback(controllerCallback)
        publish()
    }

    /** Recomputes the state, keeping optimistic values the phone has not confirmed yet. */
    private fun publish() {
        val base = snapshot()
        val now = System.currentTimeMillis()
        var result = base
        val optimistic = optimisticIsPlaying
        if (optimistic != null) {
            if (base.isPlaying == optimistic || now - optimisticPlayingAtMs > OPTIMISTIC_PLAY_GRACE_MS) {
                optimisticIsPlaying = null
            } else {
                result = result.copy(isPlaying = optimistic)
            }
        }
        if (now - lastVolumeInputAtMs < VOLUME_ECHO_GRACE_MS) {
            val shown = _stateFlow.value
            result = result.copy(volumePercent = shown.volumePercent, volume = shown.volume)
        }
        _stateFlow.value = result
    }

    private fun findActiveLocalController(): MediaController? {
        return try {
            val listener = ComponentName(context, WatchMediaNotificationListenerService::class.java)
            val sessions = sessionManager.getActiveSessions(listener)
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
                volumePercent = if (maxVol > 0) vol * 100 / maxVol else 0,
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
            val isPlaying = synced.isPlaying
            return MediaControlsState(
                title = synced.title,
                artist = if (synced.artist.isNotBlank()) synced.artist else "Spotify",
                isPlaying = isPlaying,
                hasSession = true,
                source = "phone",
                volume = vol,
                maxVolume = maxVol,
                volumePercent = synced.volumePercent,
                packageName = synced.packageName,
                artwork = synced.artwork ?: localArtwork,
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
            val isPlaying = local.playbackState?.state == PlaybackState.STATE_PLAYING
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
                volumePercent = if (maxVol > 0) vol * 100 / maxVol else 0,
                artwork = localArtwork,
                positionMs = position,
                durationMs = duration,
                isSpotify = isSpotify,
                appName = if (isSpotify) "Spotify" else "Watch Player",
                updatedAtEpochMs = System.currentTimeMillis(),
            )
        }

        // Default standby state
        val isPlaying = false
        val hasPermission = synced?.hasPermission ?: false
        val titleMsg = if (!hasPermission) "Allow Phone Permission" else if (isPlaying) "Playing on Phone" else "No Active Media"
        val artistMsg = if (!hasPermission) "Open phone app to allow" else "Start Spotify on phone or watch"
        return MediaControlsState(
            title = titleMsg,
            artist = artistMsg,
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
