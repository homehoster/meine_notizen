package com.github.homehoster.meine_notizen

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class NoteWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        val rows = intArrayOf(R.id.n0, R.id.n1, R.id.n2, R.id.n3, R.id.n4)
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.note_widget).apply {
                for (i in 0..4) {
                    val label = widgetData.getString("label_$i", "") ?: ""
                    val noteId = widgetData.getString("id_$i", "") ?: ""
                    setTextViewText(rows[i], label)
                    setViewVisibility(rows[i], if (label.isEmpty()) View.GONE else View.VISIBLE)
                    if (noteId.isNotEmpty()) {
                        setOnClickPendingIntent(
                            rows[i],
                            HomeWidgetLaunchIntent.getActivity(
                                context, MainActivity::class.java,
                                Uri.parse("notizapp://note/$noteId")
                            )
                        )
                    }
                }
                setOnClickPendingIntent(
                    R.id.widget_title,
                    HomeWidgetLaunchIntent.getActivity(
                        context, MainActivity::class.java, Uri.parse("notizapp://home")
                    )
                )
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
