package com.github.homehoster.meine_notizen

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.net.Uri
import android.os.Bundle

class WidgetActionActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        AlertDialog.Builder(this)
            .setTitle("Meine Notizen")
            .setItems(arrayOf("Meine Notizen öffnen", "Neue Notiz")) { _, which ->
                val uri = when (which) {
                    0 -> "notizapp://home"
                    else -> "notizapp://new-note"
                }
                startActivity(
                    Intent(this, MainActivity::class.java).apply {
                        action = Intent.ACTION_VIEW
                        data = Uri.parse(uri)
                        flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                    }
                )
                finish()
            }
            .setOnCancelListener { finish() }
            .show()
    }
}
