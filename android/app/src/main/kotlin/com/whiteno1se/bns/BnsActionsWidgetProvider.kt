package com.whiteno1se.bns

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * "Quick actions" — three big buttons, one tap each:
 *   + Task   → routines screen with the new-routine form already open
 *   + Memory → capture screen ready to type
 *   🎤 Voice → capture screen ALREADY recording
 * (Distinct URIs make distinct PendingIntents even with one request code.)
 */
class BnsActionsWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_actions).apply {
                setOnClickPendingIntent(
                    R.id.btn_task,
                    HomeWidgetLaunchIntent.getActivity(
                        context, MainActivity::class.java, Uri.parse("bns://add-task")),
                )
                setOnClickPendingIntent(
                    R.id.btn_memory,
                    HomeWidgetLaunchIntent.getActivity(
                        context, MainActivity::class.java, Uri.parse("bns://add-memory")),
                )
                setOnClickPendingIntent(
                    R.id.btn_voice,
                    HomeWidgetLaunchIntent.getActivity(
                        context, MainActivity::class.java, Uri.parse("bns://record")),
                )
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
