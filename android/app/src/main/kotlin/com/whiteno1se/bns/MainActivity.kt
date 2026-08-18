package com.whiteno1se.bns

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.wifi.WifiManager
import android.os.Bundle
import android.provider.AlarmClock
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

    /// THE PHONE'S EARS FOR THE LAN (owner's test, 2026-07-27: the phone's
    /// hello reached the PC, but the PC's never reached the phone). Android
    /// filters broadcast/multicast frames in the Wi-Fi driver to save
    /// battery; a held MulticastLock is the only way an app hears them.
    /// Held while the app is in front — exactly when discovery matters.
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            val wifi = applicationContext
                .getSystemService(Context.WIFI_SERVICE) as WifiManager
            multicastLock = wifi.createMulticastLock("bns-lan-discovery").apply {
                setReferenceCounted(true)
                acquire()
            }
        } catch (_: Exception) {
            // No Wi-Fi service (emulator, odd ROM) — discovery degrades,
            // the app itself never suffers for it.
        }
    }

    override fun onDestroy() {
        try {
            multicastLock?.let { if (it.isHeld) it.release() }
        } catch (_: Exception) {
        }
        multicastLock = null
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // THE CLOCK DOOR (owner, 2026-08-18: "make sure it passes from my
        // app into the clock itself with configurations and notes"). Hands
        // the wake to the phone's own clock app, pre-filled — time and the
        // reason as the label. The clock's UI opens so the person SEES it
        // land and can pick their song right there; its alarms survive
        // anything, BNS included.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bns/wake_clock")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "plant" -> {
                            val intent = Intent(AlarmClock.ACTION_SET_ALARM).apply {
                                putExtra(AlarmClock.EXTRA_HOUR,
                                    call.argument<Int>("hour") ?: 8)
                                putExtra(AlarmClock.EXTRA_MINUTES,
                                    call.argument<Int>("minutes") ?: 0)
                                call.argument<String>("message")?.let {
                                    putExtra(AlarmClock.EXTRA_MESSAGE, it)
                                }
                                // Repeat: java.util.Calendar day numbers
                                // (1=Sunday .. 7=Saturday). Absent/empty =
                                // a one-time ring at the next occurrence.
                                call.argument<List<Int>>("days")?.let {
                                    if (it.isNotEmpty()) {
                                        putIntegerArrayListExtra(
                                            AlarmClock.EXTRA_DAYS, ArrayList(it))
                                    }
                                }
                                putExtra(AlarmClock.EXTRA_SKIP_UI, false)
                            }
                            startActivity(intent)
                            result.success(true)
                        }
                        "openAlarms" -> {
                            startActivity(Intent(AlarmClock.ACTION_SHOW_ALARMS))
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    // No clock app to answer — the Dart side says so kindly.
                    result.success(false)
                }
            }
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
