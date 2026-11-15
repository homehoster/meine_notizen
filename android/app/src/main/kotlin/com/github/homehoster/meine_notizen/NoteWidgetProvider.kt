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
        val rows = intArrayOf(R.id.r0, R.id.r1, R.id.r2, R.id.r3, R.id.r4)
        val titles = intArrayOf(R.id.n0, R.id.n1, R.id.n2, R.id.n3, R.id.n4)
        val previews = intArrayOf(R.id.p0, R.id.p1, R.id.p2, R.id.p3, R.id.p4)
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.note_widget).apply {
                for (i in 0..4) {
                    val title = widgetData.getString("title_$i", "") ?: ""
                    val preview = widgetData.getString("preview_$i", "") ?: ""
                    val noteId = widgetData.getString("id_$i", "") ?: ""
                    setTextViewText(titles[i], title)
                    setTextViewText(previews[i], preview)
                    setViewVisibility(rows[i], if (title.isEmpty()) View.GONE else View.VISIBLE)
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
                    R.id.widget_add,
                    HomeWidgetLaunchIntent.getActivity(
                        context, MainActivity::class.java, Uri.parse("notizapp://actions")
                    )
                )
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
