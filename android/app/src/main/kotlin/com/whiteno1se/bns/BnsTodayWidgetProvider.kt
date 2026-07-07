package com.whiteno1se.bns

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/** "Today" — the mission list + gentle progress. Tap anywhere → open BNS. */
class BnsTodayWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_today).apply {
                setTextViewText(
                    R.id.today_progress,
                    widgetData.getString("today_progress", "") ?: "",
                )
                setTextViewText(
                    R.id.today_mission,
                    widgetData.getString("today_mission", "Open BNS to plan a gentle day")
                        ?: "",
                )
                setTextViewText(
                    R.id.today_summary,
                    widgetData.getString("summary", "You showed up. That counts.") ?: "",
                )
                setOnClickPendingIntent(
                    R.id.today_root,
                    HomeWidgetLaunchIntent.getActivity(
                        context, MainActivity::class.java, Uri.parse("bns://today")),
                )
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
