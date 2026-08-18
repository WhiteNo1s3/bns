package com.whiteno1se.bns

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.provider.AlarmClock
import android.speech.RecognitionListener
import android.speech.RecognitionService
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.annotation.RequiresApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

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
                    // The person's own words, ALL of them (mad-vent law:
                    // cursing fully allowed; owner, 2026-08-18: "אין קללות
                    // או מילים לא מוכרות"). Google masks curses with
                    // asterisks unless told not to — Android 13+ listens
                    // to this extra, older phones ignore it harmlessly.
                    putExtra(RecognizerIntent.EXTRA_MASK_OFFENSIVE_WORDS, false)
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
        // THE FILE EAR (owner, 2026-08-18: "רציתי שמהתחלה יהיה גם הקלטה
        // וגם יצירת טקסט מהדיבור... לגרום לגוגל להוציא מילים מההקלטה גם
        // מגניב"). Android 13 opened the door this app waited a year for:
        // RecognizerIntent.EXTRA_AUDIO_SOURCE hands the recognizer a FILE
        // DESCRIPTOR instead of the microphone. The one mic records, and
        // the SAME audio is then read by the popup's own engine — voice
        // and words from one speaking, nobody says anything twice.
        //
        // Phones differ on which recognizer honors the extra, so the Dart
        // side probes once with a bundled spoken sentence: variant 0 = the
        // on-device recognizer, 1 = Google's service called by name,
        // 2 = the system default.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bns/file_stt")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isSupported" ->
                        result.success(Build.VERSION.SDK_INT >= 33)
                    "transcribeFile" -> {
                        if (Build.VERSION.SDK_INT < 33) {
                            result.error("old_android",
                                "the file ear needs Android 13", null)
                        } else if (earBusy) {
                            result.error("busy",
                                "the file ear is already listening", null)
                        } else {
                            earBusy = true
                            transcribeFile(
                                call.argument<String>("path") ?: "",
                                call.argument<String>("locale") ?: "he-IL",
                                call.argument<Int>("variant") ?: 2,
                                (call.argument<Int>("timeoutMs") ?: 120_000).toLong(),
                                result,
                            )
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // ---- The file ear (Android 13+) ----

    private var earBusy = false
    private val mainHandler by lazy { Handler(Looper.getMainLooper()) }

    /// Decode off the UI thread, then listen on it (SpeechRecognizer is a
    /// main-thread citizen). The Result is answered exactly once, on main.
    /// [timeoutMs] caps a stuck session — the probe passes a short leash
    /// so a phone with three dead doors costs seconds, never minutes.
    private fun transcribeFile(
        path: String, locale: String, variant: Int, timeoutMs: Long,
        result: MethodChannel.Result
    ) {
        Thread {
            val file = File(path)
            val decoded = if (file.exists()) {
                // WAVs are parsed by hand — the probe asset must never
                // depend on codec moods. m4a and friends go to MediaCodec.
                (if (path.lowercase().endsWith(".wav"))
                    parseWavPcm16(file.readBytes()) else null)
                    ?: decodeCompressed(path)
            } else null
            if (decoded == null) {
                mainHandler.post {
                    earBusy = false
                    result.error("no_audio", "could not read $path", null)
                }
                return@Thread
            }
            if (Build.VERSION.SDK_INT >= 33) {
                mainHandler.post {
                    listenToPcm(decoded.first, decoded.second, locale, variant,
                        timeoutMs, result)
                }
            } else {
                // Unreachable (the channel guards first) — but a Result
                // must never be left waiting forever.
                mainHandler.post {
                    earBusy = false
                    result.error("old_android", null, null)
                }
            }
        }.apply { name = "bns-file-ear-decode" }.start()
    }

    /// PCM16 out of a WAV without asking any codec: RIFF → fmt (must be
    /// plain PCM16) → data. Returns mono PCM + sample rate, or null.
    private fun parseWavPcm16(bytes: ByteArray): Pair<ByteArray, Int>? {
        if (bytes.size < 44) return null
        val bb = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        if (bb.getInt(0) != 0x46464952 || bb.getInt(8) != 0x45564157) {
            return null // not RIFF/WAVE
        }
        var pos = 12
        var rate = 0
        var channels = 0
        var data: ByteArray? = null
        while (pos + 8 <= bytes.size) {
            val id = bb.getInt(pos)
            val size = bb.getInt(pos + 4)
            val body = pos + 8
            if (size < 0 || body > bytes.size) break
            when (id) {
                0x20746d66 -> { // "fmt "
                    if (body + 16 > bytes.size) return null
                    if (bb.getShort(body).toInt() != 1) return null // PCM only
                    channels = bb.getShort(body + 2).toInt()
                    rate = bb.getInt(body + 4)
                    if (bb.getShort(body + 14).toInt() != 16) return null
                }
                0x61746164 -> { // "data"
                    data = bytes.copyOfRange(body, minOf(body + size, bytes.size))
                }
            }
            pos = body + size + (size and 1)
        }
        val pcm = data ?: return null
        if (rate <= 0 || channels < 1) return null
        return Pair(if (channels == 1) pcm else downmix(pcm, channels), rate)
    }

    /// Everything that is not a WAV: MediaExtractor + MediaCodec down to
    /// PCM16, then mono. Null when the file cannot be read as audio.
    private fun decodeCompressed(path: String): Pair<ByteArray, Int>? {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(path)
            var format: MediaFormat? = null
            for (i in 0 until extractor.trackCount) {
                val f = extractor.getTrackFormat(i)
                if (f.getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true) {
                    extractor.selectTrack(i)
                    format = f
                    break
                }
            }
            val fmt = format ?: return null
            val mime = fmt.getString(MediaFormat.KEY_MIME) ?: return null
            var rate = fmt.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var channels = fmt.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            val out = ByteArrayOutputStream()
            if (mime == MediaFormat.MIMETYPE_AUDIO_RAW) {
                val buf = ByteBuffer.allocate(1 shl 16)
                while (true) {
                    val n = extractor.readSampleData(buf, 0)
                    if (n < 0) break
                    val chunk = ByteArray(n)
                    buf.get(chunk)
                    buf.clear()
                    out.write(chunk)
                    extractor.advance()
                }
            } else {
                val codec = MediaCodec.createDecoderByType(mime)
                codec.configure(fmt, null, null, 0)
                codec.start()
                val info = MediaCodec.BufferInfo()
                var inputDone = false
                var outputDone = false
                var idleSpins = 0
                while (!outputDone && idleSpins < 500) { // ~5s of silence = a stuck codec
                    var progressed = false
                    if (!inputDone) {
                        val inIx = codec.dequeueInputBuffer(10_000)
                        if (inIx >= 0) {
                            progressed = true
                            val inBuf = codec.getInputBuffer(inIx)!!
                            val n = extractor.readSampleData(inBuf, 0)
                            if (n < 0) {
                                codec.queueInputBuffer(inIx, 0, 0, 0,
                                    MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                                inputDone = true
                            } else {
                                codec.queueInputBuffer(inIx, 0, n,
                                    extractor.sampleTime, 0)
                                extractor.advance()
                            }
                        }
                    }
                    val outIx = codec.dequeueOutputBuffer(info, 10_000)
                    if (outIx >= 0) {
                        progressed = true
                        val outBuf = codec.getOutputBuffer(outIx)!!
                        val chunk = ByteArray(info.size)
                        outBuf.position(info.offset)
                        outBuf.get(chunk)
                        out.write(chunk)
                        codec.releaseOutputBuffer(outIx, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                            outputDone = true
                        }
                    } else if (outIx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                        progressed = true
                        rate = codec.outputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                        channels = codec.outputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    }
                    idleSpins = if (progressed) 0 else idleSpins + 1
                }
                codec.stop()
                codec.release()
                if (!outputDone) return null
            }
            val pcm = out.toByteArray()
            if (pcm.isEmpty() || rate <= 0) return null
            return Pair(if (channels == 1) pcm else downmix(pcm, channels), rate)
        } catch (e: Exception) {
            return null
        } finally {
            extractor.release()
        }
    }

    private fun downmix(pcm: ByteArray, channels: Int): ByteArray {
        val frame = channels * 2
        val frames = pcm.size / frame
        val out = ByteArray(frames * 2)
        val src = ByteBuffer.wrap(pcm).order(ByteOrder.LITTLE_ENDIAN)
        val dst = ByteBuffer.wrap(out).order(ByteOrder.LITTLE_ENDIAN)
        for (f in 0 until frames) {
            var sum = 0
            for (c in 0 until channels) {
                sum += src.getShort(f * frame + c * 2).toInt()
            }
            dst.putShort(f * 2, (sum / channels).toShort())
        }
        return out
    }

    /// One recognition over a pipe: the recognizer reads our PCM from the
    /// read end while a feed thread writes the file into the write end.
    /// Closing the write end is the end of speech. One session per file —
    /// a very long vent may come back with its tail missing; the voice
    /// itself is whole either way (segmented sessions are the next rung).
    @RequiresApi(Build.VERSION_CODES.TIRAMISU)
    private fun listenToPcm(
        pcm: ByteArray, rate: Int, locale: String, variant: Int,
        timeoutMs: Long, result: MethodChannel.Result
    ) {
        val recognizer: SpeechRecognizer = when (variant) {
            0 -> {
                if (!SpeechRecognizer.isOnDeviceRecognitionAvailable(this)) {
                    earBusy = false
                    result.error("no_ondevice", "no on-device recognizer", null)
                    return
                }
                SpeechRecognizer.createOnDeviceSpeechRecognizer(this)
            }
            1 -> {
                val component = googleRecognitionService()
                if (component == null) {
                    earBusy = false
                    result.error("no_google", "no Google recognition service", null)
                    return
                }
                SpeechRecognizer.createSpeechRecognizer(this, component)
            }
            else -> {
                if (!SpeechRecognizer.isRecognitionAvailable(this)) {
                    earBusy = false
                    result.error("no_service", "no recognition service", null)
                    return
                }
                SpeechRecognizer.createSpeechRecognizer(this)
            }
        }
        val pipe = ParcelFileDescriptor.createPipe()
        var finished = false
        lateinit var timeout: Runnable
        // Every road out passes here exactly once: destroy, close, answer.
        fun finish(words: String?, errCode: String?) {
            if (finished) return
            finished = true
            mainHandler.removeCallbacks(timeout)
            try { recognizer.destroy() } catch (_: Exception) {}
            try { pipe[0].close() } catch (_: Exception) {}
            try { pipe[1].close() } catch (_: Exception) {}
            earBusy = false
            if (errCode != null) {
                result.error(errCode, null, null)
            } else {
                result.success(words ?: "")
            }
        }
        timeout = Runnable { finish(null, "ear_timeout") }
        mainHandler.postDelayed(timeout, timeoutMs)
        recognizer.setRecognitionListener(object : RecognitionListener {
            override fun onResults(results: Bundle?) {
                val texts = results
                    ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                finish(texts?.firstOrNull() ?: "", null)
            }

            override fun onError(error: Int) {
                // Silence is an answer, not a failure: the ear worked and
                // heard nothing. Anything else names a broken variant.
                if (error == SpeechRecognizer.ERROR_NO_MATCH ||
                    error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT
                ) {
                    finish("", null)
                } else {
                    finish(null, "ear_$error")
                }
            }

            override fun onReadyForSpeech(params: Bundle?) {}
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) {}
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() {}
            override fun onPartialResults(partialResults: Bundle?) {}
            override fun onEvent(eventType: Int, params: Bundle?) {}
        })
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, locale)
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE, pipe[0])
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_ENCODING,
                AudioFormat.ENCODING_PCM_16BIT)
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_CHANNEL_COUNT, 1)
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_SAMPLING_RATE, rate)
            // No asterisks over the person's own words (mad-vent law).
            putExtra(RecognizerIntent.EXTRA_MASK_OFFENSIVE_WORDS, false)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        }
        try {
            recognizer.startListening(intent)
        } catch (e: Exception) {
            finish(null, "ear_start")
            return
        }
        Thread {
            try {
                ParcelFileDescriptor.AutoCloseOutputStream(pipe[1]).use { sink ->
                    var off = 0
                    while (off < pcm.size) {
                        val n = minOf(32 * 1024, pcm.size - off)
                        sink.write(pcm, off, n)
                        off += n
                    }
                }
            } catch (_: Exception) {
                // Reader closed early (recognizer finished or died) — fine.
            }
        }.apply { name = "bns-file-ear-feed" }.start()
    }

    /// Google's recognition service, found by name — on Samsung phones the
    /// DEFAULT recognizer is Samsung's and refuses Hebrew (field truth,
    /// 2026-07-26), while Google's, asked directly, is the popup's engine.
    private fun googleRecognitionService(): ComponentName? {
        return try {
            packageManager.queryIntentServices(
                Intent(RecognitionService.SERVICE_INTERFACE), 0)
                .firstOrNull {
                    it.serviceInfo?.packageName?.contains("google") == true
                }
                ?.serviceInfo
                ?.let { ComponentName(it.packageName, it.name) }
        } catch (_: Exception) {
            null
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
