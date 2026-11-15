package com.github.homehoster.meine_notizen

import android.content.ContentUris
import android.content.ContentValues
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "com.github.homehoster.meine_notizen/logs"
    private val fileName = "notizen.log"
    private var logFileUri: Uri? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "appendLog" -> {
                            appendLog(call.argument<String>("line") ?: "")
                            result.success(null)
                        }
                        "readLogFiles" -> result.success(readLogFiles())
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("LOG_ERROR", e.message, null)
                }
            }
    }

    // Android 9 und älter: app-eigener Ordner (Downloads bräuchte dort eine Berechtigung)
    private fun legacyFile(): File {
        val dir = File(getExternalFilesDir(null) ?: filesDir, "logs")
        dir.mkdirs()
        return File(dir, fileName)
    }

    private fun findLogUri(): Uri? {
        logFileUri?.let { return it }
        val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
        contentResolver.query(
            collection,
            arrayOf(MediaStore.Downloads._ID, MediaStore.Downloads.RELATIVE_PATH),
            "${MediaStore.Downloads.DISPLAY_NAME}=?",
            arrayOf(fileName),
            null
        )?.use { c ->
            val idColumn = c.getColumnIndexOrThrow(MediaStore.Downloads._ID)
            val pathColumn = c.getColumnIndexOrThrow(MediaStore.Downloads.RELATIVE_PATH)
            while (c.moveToNext()) {
                if (c.getString(pathColumn)?.trimEnd('/') ==
                    Environment.DIRECTORY_DOWNLOADS.trimEnd('/')
                ) {
                    return ContentUris.withAppendedId(collection, c.getLong(idColumn))
                        .also { logFileUri = it }
                }
            }
        }
        return null
    }

    private fun appendLog(line: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            legacyFile().appendText(line)
            return
        }
        val uri = findLogUri() ?: run {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                put(MediaStore.Downloads.MIME_TYPE, "text/plain")
                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            }
            contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
        } ?: throw IllegalStateException("Logdatei konnte nicht angelegt werden")
        logFileUri = uri
        val output = contentResolver.openOutputStream(uri, "wa")
            ?: throw IllegalStateException("Logdatei konnte nicht geöffnet werden")
        output.use {
            it.write(line.toByteArray(Charsets.UTF_8))
        }
    }

    private fun readLogFiles(): List<String> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            val f = legacyFile()
            return if (f.exists() && f.length() > 0) listOf(f.path) else emptyList()
        }
        val uri = findLogUri() ?: return emptyList()
        val out = File(cacheDir, fileName)
        contentResolver.openInputStream(uri)?.use { input ->
            out.outputStream().use { input.copyTo(it) }
        }
        return if (out.exists() && out.length() > 0) listOf(out.path) else emptyList()
    }
}
