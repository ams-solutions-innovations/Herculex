package com.ams.herculex.media

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.provider.MediaStore
import android.provider.Settings
import android.view.KeyEvent

data class MediaControlsState(
    val title: String = "No active media",
    val artist: String = "Start music, then come back",
    val hasSession: Boolean = false,
    val hasNotificationAccess: Boolean = false,
    val isPlaying: Boolean = false,
)

class MediaControlsController(private val context: Context) {

    fun state(): MediaControlsState {
        val hasAccess = hasNotificationAccess()
        val controller = activeController()
        val metadata = controller?.metadata
        val title = metadata?.getString(MediaMetadata.METADATA_KEY_TITLE)
            ?: metadata?.getString(MediaMetadata.METADATA_KEY_DISPLAY_TITLE)
            ?: if (hasAccess) "No active media" else "Enable media access"
        val artist = metadata?.getString(MediaMetadata.METADATA_KEY_ARTIST)
            ?: metadata?.getString(MediaMetadata.METADATA_KEY_DISPLAY_SUBTITLE)
            ?: if (hasAccess) "Controls still send media keys" else "Tap access below"
        val isPlaying = controller?.playbackState?.state == android.media.session.PlaybackState.STATE_PLAYING

        return MediaControlsState(
            title = title,
            artist = artist,
            hasSession = controller != null,
            hasNotificationAccess = hasAccess,
            isPlaying = isPlaying,
        )
    }

    fun playPause() {
        val controller = activeController()
        if (controller == null) {
            sendMediaKey(KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE)
            return
        }
        if (controller.playbackState?.state == android.media.session.PlaybackState.STATE_PLAYING) {
            controller.transportControls.pause()
        } else {
            controller.transportControls.play()
        }
    }

    fun next() {
        activeController()?.transportControls?.skipToNext()
            ?: sendMediaKey(KeyEvent.KEYCODE_MEDIA_NEXT)
    }

    fun previous() {
        activeController()?.transportControls?.skipToPrevious()
            ?: sendMediaKey(KeyEvent.KEYCODE_MEDIA_PREVIOUS)
    }

    fun openAccessSettings() {
        context.startActivity(
            Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }

    fun openSystemPlayer() {
        val intent = Intent(MediaStore.INTENT_ACTION_MUSIC_PLAYER)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching { context.startActivity(intent) }
            .recover {
                context.startActivity(
                    Intent(Settings.ACTION_SOUND_SETTINGS)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
            }
    }

    private fun activeController(): MediaController? {
        return try {
            val manager = context.getSystemService(MediaSessionManager::class.java)
            val listener = ComponentName(context, MediaNotificationListenerService::class.java)
            manager.getActiveSessions(listener).firstOrNull {
                it.playbackState?.state == android.media.session.PlaybackState.STATE_PLAYING
            } ?: manager.getActiveSessions(listener).firstOrNull()
        } catch (_: SecurityException) {
            null
        }
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
