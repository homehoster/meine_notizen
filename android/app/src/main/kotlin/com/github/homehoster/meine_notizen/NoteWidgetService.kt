package com.github.homehoster.meine_notizen

import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteException
import android.database.sqlite.SQLiteDatabase
import android.graphics.BitmapFactory
import android.net.Uri
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import android.view.View
import android.util.Log

class NoteWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        NoteWidgetFactory(applicationContext)
}

private data class WidgetNote(
    val id: String,
    val title: String,
    val preview: String,
    val imagePath: String
)

private enum class WidgetListType { TASK, BULLET, NUMBERED }

private data class WidgetTask(
    val text: String,
    val done: Boolean,
    val children: MutableList<WidgetTask> = mutableListOf()
)

private class NoteWidgetFactory(private val context: Context) : RemoteViewsService.RemoteViewsFactory {
    private var notes = emptyList<WidgetNote>()

    override fun onCreate() = Unit

    override fun onDataSetChanged() {
        val databaseFile = java.io.File(
            context.getDir("flutter", Context.MODE_PRIVATE),
            "notiz_app.sqlite"
        )
        if (!databaseFile.isFile) {
            notes = emptyList()
            return
        }

        var database: SQLiteDatabase? = null
        try {
            val readDatabase = SQLiteDatabase.openDatabase(
                databaseFile.absolutePath,
                null,
                SQLiteDatabase.OPEN_READONLY
            )
            database = readDatabase
            val cursor = readDatabase.rawQuery(
                """
                SELECT n.id, n.content
                FROM notes n
                WHERE n.deleted = 0 AND n.state = 'normal'
                  AND (
                    NOT EXISTS (
                      SELECT 1 FROM widget_ids wi
                      JOIN notes selected ON selected.id = wi.note_id
                      WHERE selected.deleted = 0 AND selected.state = 'normal'
                    )
                    OR EXISTS (
                      SELECT 1 FROM widget_ids wi WHERE wi.note_id = n.id
                    )
                  )
                ORDER BY n.pinned DESC, n.updated_at DESC
                """.trimIndent(),
                null
            )
            cursor.use {
                val imagePreferences = context.getSharedPreferences(
                    "HomeWidgetPreferences",
                    Context.MODE_PRIVATE
                )
                val loadedNotes = mutableListOf<WidgetNote>()
                while (it.moveToNext()) {
                    val id = it.getString(0)
                    val content = it.getString(1)
                    val safeId = id.replace(Regex("[^A-Za-z0-9._-]"), "_")
                    loadedNotes.add(
                        WidgetNote(
                            id = id,
                            title = widgetTitle(content),
                            preview = widgetPreview(content),
                            imagePath = imagePreferences.getString("note_${safeId}_image", "") ?: ""
                        )
                    )
                }
                notes = loadedNotes
            }
        } catch (e: SQLiteException) {
            Log.e("NoteWidgetService", "Widget-Notizen konnten nicht gelesen werden", e)
            notes = emptyList()
        } finally {
            database?.close()
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

    override fun getItemId(position: Int): Long = notes[position].id.hashCode().toLong()

    override fun hasStableIds(): Boolean = true
}

private val widgetTaskPattern = Regex("""^(\s*)[-*] \[([ xX])\] ?(.*)$""")
private val widgetBulletPattern = Regex("""^(\s*)[-*] +(.*)$""")
private val widgetNumberedPattern = Regex("""^(\s*)\d+\. +(.*)$""")

private fun widgetTitle(content: String): String {
    val marker = Regex("""^\s*(#+\s*|[-*]\s*(\[[ xX]\]\s*)?)""")
    return content.lineSequence()
        .map { marker.replaceFirst(it, "").trim() }
        .firstOrNull { it.isNotEmpty() } ?: "Leere Notiz"
}

private fun widgetPlainText(line: String): String = line
    .replace(Regex("""^\s{0,3}#{1,6}\s+"""), "")
    .replace(Regex("""^\s{0,3}>\s?"""), "")
    .replace(Regex("""!\[([^\]]*)\]\([^)]+\)""")) { it.groupValues[1] }
    .replace(Regex("""\[([^\]]+)\]\([^)]+\)""")) { it.groupValues[1] }
    .replace(Regex("""(\*\*|__|~~|`|\*|_)"""), "")
    .trim()

private fun widgetPreview(content: String): String {
    val lines = content.split('\n')
    val first = lines.indexOfFirst { it.isNotBlank() }
    if (first < 0) return ""

    val preview = mutableListOf<String>()
    var index = first + 1
    while (index < lines.size && preview.size < 5) {
        val line = lines[index]
        val taskMatch = widgetTaskPattern.matchEntire(line)
        val bulletMatch = if (taskMatch == null) widgetBulletPattern.matchEntire(line) else null
        val numberedMatch =
            if (taskMatch == null && bulletMatch == null) widgetNumberedPattern.matchEntire(line)
            else null
        if (taskMatch == null && bulletMatch == null && numberedMatch == null) {
            val textLines = mutableListOf<String>()
            while (index < lines.size) {
                val current = lines[index]
                if (widgetTaskPattern.matches(current) ||
                    widgetBulletPattern.matches(current) ||
                    widgetNumberedPattern.matches(current)
                ) break
                val text = widgetPlainText(current)
                if (text.isNotEmpty()) textLines.add(text)
                index++
            }
            preview.addAll(textLines.take(5 - preview.size))
            continue
        }

        val type = when {
            taskMatch != null -> WidgetListType.TASK
            bulletMatch != null -> WidgetListType.BULLET
            else -> WidgetListType.NUMBERED
        }
        val roots = mutableListOf<WidgetTask>()
        val stack = mutableListOf<Pair<Int, WidgetTask>>()
        while (index < lines.size) {
            val current = lines[index]
            val task = widgetTaskPattern.matchEntire(current)
            val bullet = if (task == null) widgetBulletPattern.matchEntire(current) else null
            val numbered =
                if (task == null && bullet == null) widgetNumberedPattern.matchEntire(current)
                else null
            val currentType = when {
                task != null -> WidgetListType.TASK
                bullet != null -> WidgetListType.BULLET
                numbered != null -> WidgetListType.NUMBERED
                else -> null
            }
            if (currentType != type) break

            val match = task ?: bullet ?: numbered!!
            val indent = match.groupValues[1].replace("\t", "  ").length / 2
            val value = if (task != null) match.groupValues[3] else match.groupValues[2]
            val item = WidgetTask(value, task != null && task.groupValues[2] != " ")
            while (stack.isNotEmpty() && stack.last().first >= indent) stack.removeAt(stack.lastIndex)
            if (stack.isEmpty()) roots.add(item) else stack.last().second.children.add(item)
            stack.add(indent to item)
            index++
        }

        fun appendTasks(tasks: List<WidgetTask>, depth: Int) {
            tasks.forEachIndexed { taskIndex, item ->
                if (type != WidgetListType.TASK || !item.done) {
                    val text = widgetPlainText(item.text)
                    if (text.isNotEmpty() && preview.size < 5) {
                        val marker = when (type) {
                            WidgetListType.TASK -> "☐"
                            WidgetListType.BULLET -> "•"
                            WidgetListType.NUMBERED -> "${taskIndex + 1}."
                        }
                        preview.add("${"  ".repeat(depth)}$marker $text")
                    }
                }
                if (preview.size < 5) appendTasks(item.children, depth + 1)
            }
        }
        appendTasks(roots, 0)
    }
    return preview.take(5).joinToString("\n")
}
