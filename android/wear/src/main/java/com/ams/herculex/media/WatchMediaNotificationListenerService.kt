package com.ams.herculex.media

import android.service.notification.NotificationListenerService

/**
 * The system grants this service notification-listener access when the user
 * enables Media controls in Wear OS settings.  That access is what permits
 * MediaSessionManager to expose local watch players to this app.
 */
class WatchMediaNotificationListenerService : NotificationListenerService()
