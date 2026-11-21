package com.github.homehoster.meine_notizen

import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import android.view.View
import android.util.Log
import org.json.JSONException
import org.json.JSONArray

class NoteWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        NoteWidgetFactory(applicationContext)

    companion object {
        const val PREFERENCES_NAME = "note_widget_data"
        const val NOTE_DATA_KEY = "widget_notes"
    }
}

private data class WidgetNote(
    val id: String,
    val title: String,
    val preview: String,
    val imagePath: String
)

private class NoteWidgetFactory(private val context: Context) : RemoteViewsService.RemoteViewsFactory {
    private var notes = emptyList<WidgetNote>()

    override fun onCreate() = Unit

    override fun onDataSetChanged() {
        val data = context.getSharedPreferences(
            NoteWidgetService.PREFERENCES_NAME,
            Context.MODE_PRIVATE
        ).getString(NoteWidgetService.NOTE_DATA_KEY, "[]") ?: "[]"
        try {
            val array = JSONArray(data)
            notes = List(array.length()) { index ->
                val item = array.getJSONObject(index)
                WidgetNote(
                    id = item.getString("id"),
                    title = item.getString("title"),
                    preview = item.getString("preview"),
                    imagePath = item.optString("imagePath", "")
                )
            }
        } catch (e: JSONException) {
            Log.e("NoteWidgetService", "Widget-Notizen konnten nicht gelesen werden", e)
            notes = emptyList()
        }
    }

    override fun onDestroy() {
        notes = emptyList()
    }

    override fun getCount(): Int = notes.size

    override fun getViewAt(position: Int): RemoteViews? {
        val note = notes.getOrNull(position) ?: return null
        return RemoteViews(context.packageName, R.layout.note_widget_row).apply {
            setTextViewText(R.id.widget_note_title, note.title)
            setTextViewText(R.id.widget_note_preview, note.preview)
            val bitmap = if (note.imagePath.isEmpty()) {
                null
            } else {
                BitmapFactory.decodeFile(note.imagePath)
            }
            if (bitmap == null) {
                setViewVisibility(R.id.widget_note_image, View.GONE)
            } else {
                setImageViewBitmap(R.id.widget_note_image, bitmap)
                setViewVisibility(R.id.widget_note_image, View.VISIBLE)
            }
            setOnClickFillInIntent(
                R.id.widget_note_row,
                Intent().setData(Uri.parse("notizapp://note/${Uri.encode(note.id)}"))
            )
        }
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long =
        notes.getOrNull(position)?.id?.hashCode()?.toLong() ?: position.toLong()

    override fun hasStableIds(): Boolean = true
}
