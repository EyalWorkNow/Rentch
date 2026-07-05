package com.rentch.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createDefaultNotificationChannel()
    }

    /**
     * Creates the default FCM channel `rently_default` (IMPORTANCE_HIGH) so pushes
     * route to a reliable, heads-up channel instead of FCM's silent fallback.
     * Paired with the manifest meta-data
     * `com.google.firebase.messaging.default_notification_channel_id=rently_default`.
     * Creating an existing channel is a no-op, so this is safe to call every launch.
     */
    private fun createDefaultNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        // A channel's importance is FROZEN at creation — the old `rently_default`
        // shipped as low-importance on early builds, so on updated devices it's
        // stuck silent (no heads-up banner). Android ignores importance changes to
        // an existing channel, so we move to a NEW id that's high everywhere and
        // delete the stale one.
        manager.deleteNotificationChannel("rently_default")
        val channel = NotificationChannel(
            "rently_alerts",
            "Rently",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "התראות Rently"
            enableVibration(true)
            enableLights(true)
        }
        manager.createNotificationChannel(channel)
    }
}
