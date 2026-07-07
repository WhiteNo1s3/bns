package com.whiteno1se.bns

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/** "Coming up" — next days' plans + one recent memory. Tap → calendar. */
class BnsUpcomingWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_upcoming).apply {
                setTextViewText(
                    R.id.upcoming_text,
                    widgetData.getString("upcoming", "Nothing planned ahead. That's allowed.")
                        ?: "",
                )
                setTextViewText(
                    R.id.recent_memory,
                    widgetData.getString("recent_memory", "You've done great things before.")
                        ?: "",
                )
                setOnClickPendingIntent(
                    R.id.upcoming_root,
                    HomeWidgetLaunchIntent.getActivity(
                        context, MainActivity::class.java, Uri.parse("bns://calendar")),
                )
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
