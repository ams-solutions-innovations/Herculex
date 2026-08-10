package com.ams.herculex.media

import android.content.ComponentName
import android.content.Context
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.provider.MediaStore
import android.provider.Settings
import android.view.KeyEvent
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

data class MediaControlsState(
    val title: String = "No active media",
    val artist: String = "Start music, then come back",
    val hasSession: Boolean = false,
    val hasNotificationAccess: Boolean = false,
    val isPlaying: Boolean = false,
)

/**
 * Drives [MediaControlsState] from the platform's active [MediaController], pushing updates
 * the moment the underlying session reports a change instead of polling on a timer. Polling
 * was reading a controller's [MediaController.getPlaybackState] immediately after issuing a
 * transport command, which raced the (often Bluetooth-relayed) session actually applying the
 * command — the read almost always won the race and showed stale state, so the on-screen
 * icon/title never appeared to change even though the command reached the player.
 */
class MediaControlsController(private val context: Context) {

    private val _stateFlow = MutableStateFlow(snapshot())
    val stateFlow: StateFlow<MediaControlsState> = _stateFlow.asStateFlow()

    private val sessionManager = context.getSystemService(MediaSessionManager::class.java)
    private val listenerComponent = ComponentName(context, MediaNotificationListenerService::class.java)

    private var activeController: MediaController? = null
    private var optimisticIsPlaying = false

    private val controllerCallback = object : MediaController.Callback() {
        override fun onPlaybackStateChanged(state: PlaybackState?) {
            _stateFlow.value = snapshot()
        }

        override fun onMetadataChanged(metadata: MediaMetadata?) {
            _stateFlow.value = snapshot()
        }

        override fun onSessionDestroyed() {
            attachToActiveSession()
        }
    }

    private val activeSessionsListener = MediaSessionManager.OnActiveSessionsChangedListener {
        attachToActiveSession()
    }

    /** Call from a DisposableEffect (or equivalent) when the media controls UI becomes visible. */
    fun start() {
        runCatching {
            sessionManager.addOnActiveSessionsChangedListener(activeSessionsListener, listenerComponent)
        }
        attachToActiveSession()
    }

    /** Call from a DisposableEffect's onDispose to avoid leaking the controller/listener. */
    fun stop() {
        activeController?.unregisterCallback(controllerCallback)
        activeController = null
        runCatching { sessionManager.removeOnActiveSessionsChangedListener(activeSessionsListener) }
    }

    fun state(): MediaControlsState = _stateFlow.value

    /**
     * Re-checks notification access and re-discovers the active session. There is no platform
     * callback for "notification access was just granted", so callers poll this at a slow,
     * safe cadence (it never runs right after a transport command, so it can't race one).
     */
    fun refresh() {
        attachToActiveSession()
    }

    fun playPause() {
        val controller = activeController
        if (controller == null) {
            optimisticIsPlaying = !optimisticIsPlaying
            sendMediaKey(KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE)
            _stateFlow.value = snapshot()
            return
        }
        if (controller.playbackState?.state == PlaybackState.STATE_PLAYING) {
            controller.transportControls.pause()
        } else {
            controller.transportControls.play()
        }
    }

    fun next() {
        val controller = activeController
        if (controller == null) {
            sendMediaKey(KeyEvent.KEYCODE_MEDIA_NEXT)
        } else {
            controller.transportControls.skipToNext()
        }
    }

    fun previous() {
        val controller = activeController
        if (controller == null) {
            sendMediaKey(KeyEvent.KEYCODE_MEDIA_PREVIOUS)
        } else {
            controller.transportControls.skipToPrevious()
        }
    }

    fun openAccessSettings() {
        runCatching {
            context.startActivity(
                android.content.Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                    .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        }.recover {
            runCatching {
                val intent = android.content.Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = android.net.Uri.fromParts("package", context.packageName, null)
                    addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
            }
        }
    }

    fun openSystemPlayer() {
        val intent = android.content.Intent(MediaStore.INTENT_ACTION_MUSIC_PLAYER)
            .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching { context.startActivity(intent) }
            .recover {
                context.startActivity(
                    android.content.Intent(Settings.ACTION_SOUND_SETTINGS)
                        .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                )
            }
    }

    private fun attachToActiveSession() {
        activeController?.unregisterCallback(controllerCallback)
        val next = findActiveController()
        activeController = next
        next?.registerCallback(controllerCallback)
        _stateFlow.value = snapshot()
    }

    private fun findActiveController(): MediaController? {
        return try {
            val sessions = sessionManager.getActiveSessions(listenerComponent)
            sessions.firstOrNull { it.playbackState?.state == PlaybackState.STATE_PLAYING }
                ?: sessions.firstOrNull()
        } catch (_: SecurityException) {
            null
        }
    }

    private fun snapshot(): MediaControlsState {
        val hasAccess = hasNotificationAccess()
        val controller = activeController
        val metadata = controller?.metadata
        val title = metadata?.getString(MediaMetadata.METADATA_KEY_TITLE)
            ?: metadata?.getString(MediaMetadata.METADATA_KEY_DISPLAY_TITLE)
            ?: "Media Controls"
        val artist = metadata?.getString(MediaMetadata.METADATA_KEY_ARTIST)
            ?: metadata?.getString(MediaMetadata.METADATA_KEY_DISPLAY_SUBTITLE)
            ?: "Tap buttons to control music"
        val isPlaying = if (controller != null) {
            controller.playbackState?.state == PlaybackState.STATE_PLAYING
        } else {
            optimisticIsPlaying
        }

        return MediaControlsState(
            title = title,
            artist = artist,
            hasSession = controller != null,
            hasNotificationAccess = hasAccess,
            isPlaying = isPlaying,
        )
    }

    private fun hasNotificationAccess(): Boolean {
        val enabled = Settings.Secure.getString(
            context.contentResolver,
            "enabled_notification_listeners",
        ) ?: return false
        val packageName = context.packageName
        return enabled.split(':').any { it.contains(packageName, ignoreCase = true) }
    }

    private fun sendMediaKey(keyCode: Int) {
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val down = KeyEvent(KeyEvent.ACTION_DOWN, keyCode)
        val up = KeyEvent(KeyEvent.ACTION_UP, keyCode)
        audioManager.dispatchMediaKeyEvent(down)
        audioManager.dispatchMediaKeyEvent(up)
    }
}
