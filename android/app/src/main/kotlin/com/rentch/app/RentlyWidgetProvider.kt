package com.rentch.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.widget.RemoteViews

/**
 * Home-screen widget showing the user's Rently activity summary:
 * "ההתאמות שלך" / "הודעות שלא נקראו" / "לייקים".
 *
 * Data source: the Flutter side writes these via
 * `HomeWidget.saveWidgetData("w_matches" | "w_unread" | "w_likes" | "w_updated", ...)`.
 * The `home_widget` plugin persists them in the SharedPreferences file
 * "HomeWidgetPreferences" (its `HomeWidgetPlugin.getData(context)` returns exactly
 * that file). We read it directly here so the widget compiles even before the
 * Flutter plugin's native artifact is on the classpath, and so a host-side widget
 * refresh never needs the engine running.
 *
 * Tap opens MainActivity via a plain launch PendingIntent.
 */
class RentlyWidgetProvider : AppWidgetProvider() {

    companion object {
        // Must match es.antonborri.home_widget.HomeWidgetPlugin#PREFERENCES.
        private const val PREFS_NAME = "HomeWidgetPreferences"

        private const val KEY_MATCHES = "w_matches"
        private const val KEY_UNREAD = "w_unread"
        private const val KEY_LIKES = "w_likes"

        /** Reads a counter that Flutter may have stored as a String or an int. */
        private fun readCount(prefs: SharedPreferences, key: String): String {
            val all = prefs.all
            return when (val v = all[key]) {
                null -> "0"
                is String -> if (v.isBlank()) "0" else v
                is Int -> v.toString()
                is Long -> v.toString()
                is Float -> v.toLong().toString()
                is Double -> v.toLong().toString()
                else -> v.toString()
            }
        }

        fun updateWidget(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

            val views = RemoteViews(context.packageName, R.layout.rently_widget)
            views.setTextViewText(R.id.widget_matches_count, readCount(prefs, KEY_MATCHES))
            views.setTextViewText(R.id.widget_unread_count, readCount(prefs, KEY_UNREAD))
            views.setTextViewText(R.id.widget_likes_count, readCount(prefs, KEY_LIKES))

            // Tap anywhere -> open the app.
            val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?: Intent(context, MainActivity::class.java)
            launch.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            val pending = PendingIntent.getActivity(
                context,
                0,
                launch,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_root, pending)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (id in appWidgetIds) {
            updateWidget(context, appWidgetManager, id)
        }
    }

    /**
     * The `home_widget` plugin's `HomeWidget.updateWidget(...)` broadcasts
     * AppWidgetManager.ACTION_APPWIDGET_UPDATE to this provider, which lands here;
     * super.onReceive dispatches it to onUpdate so fresh data renders immediately.
     */
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (AppWidgetManager.ACTION_APPWIDGET_UPDATE == intent.action) {
            val mgr = AppWidgetManager.getInstance(context)
            val ids = mgr.getAppWidgetIds(ComponentName(context, RentlyWidgetProvider::class.java))
            if (ids != null && ids.isNotEmpty()) {
                onUpdate(context, mgr, ids)
            }
        }
    }
}
