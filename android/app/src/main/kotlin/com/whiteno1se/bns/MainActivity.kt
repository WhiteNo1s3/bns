package com.whiteno1se.bns

import android.app.Activity
import android.content.Intent
import android.speech.RecognizerIntent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// The Waze door (owner, 2026-07-26): the system speech POPUP reaches
/// Google's full recognizer — Hebrew included — even when the embedded
/// engine only carries its downloaded on-device packs. Same door the
/// navigation apps use; that's why their mic "just works".
class MainActivity : FlutterActivity() {
    private var pendingResult: MethodChannel.Result? = null
    private val popupRequestCode = 7326

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bns/speech_popup")
            .setMethodCallHandler { call, result ->
                if (call.method != "recognize") {
                    result.notImplemented(); return@setMethodCallHandler
                }
                if (pendingResult != null) {
                    result.error("busy", "recognition already running", null)
                    return@setMethodCallHandler
                }
                val locale = call.argument<String>("locale")
                val prompt = call.argument<String>("prompt")
                val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                    putExtra(
                        RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                        RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
                    )
                    if (!locale.isNullOrEmpty()) {
                        putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
                        putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, locale)
                    }
                    if (!prompt.isNullOrEmpty()) {
                        putExtra(RecognizerIntent.EXTRA_PROMPT, prompt)
                    }
                    putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
                }
                try {
                    pendingResult = result
                    startActivityForResult(intent, popupRequestCode)
                } catch (e: Exception) {
                    // No activity to handle it — the Dart side falls back.
                    pendingResult = null
                    result.error("unavailable", e.message, null)
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == popupRequestCode) {
            val res = pendingResult
            pendingResult = null
            if (res != null) {
                if (resultCode == Activity.RESULT_OK) {
                    val texts =
                        data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
                    res.success(texts?.firstOrNull() ?: "")
                } else {
                    // Cancelled or nothing heard — empty words, never an error.
                    res.success("")
                }
            }
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }
}
