package com.github.homehoster.meine_notizen

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val widgetChannelName = "com.github.homehoster.meine_notizen/widget"
    private var widgetUriChannel: MethodChannel? = null
    private var widgetChannelReady = false
    private var pendingWidgetUri: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        widgetUriChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            widgetChannelName
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "ready") {
                    widgetChannelReady = true
                    result.success(null)
                    pendingWidgetUri?.let { uri ->
                        pendingWidgetUri = null
                        channel.invokeMethod("openWidgetUri", uri)
                    }
                } else {
                    result.notImplemented()
                }
            }
        }
        dispatchWidgetUri(intent?.data)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        dispatchWidgetUri(intent.data)
    }

    private fun dispatchWidgetUri(uri: Uri?) {
        if (uri == null ||
            uri.scheme != "notizapp" ||
            uri.host !in setOf("note", "actions", "new-note", "home")
        ) {
            return
        }
        val value = uri.toString()
        if (widgetChannelReady) {
            widgetUriChannel?.invokeMethod("openWidgetUri", value)
        } else {
            pendingWidgetUri = value
        }
    }
}
