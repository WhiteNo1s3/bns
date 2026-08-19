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
import android.speech.RecognitionSupport
import android.speech.RecognitionSupportCallback
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
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
                    // The doors THIS phone offers, by honest inventory:
                    // the on-device recognizer, every Google-published
                    // RecognitionService, and the system default. Never a
                    // third-party service — the voice goes only to the OS
                    // and to Google's own engines (privacy law).
                    "ears" -> {
                        if (Build.VERSION.SDK_INT < 33) {
                            result.success(listOf<String>())
                        } else {
                            val doors = mutableListOf<String>()
                            if (SpeechRecognizer.isOnDeviceRecognitionAvailable(this)) {
                                doors.add("ondevice")
                            }
                            for (c in googleRecognitionServices()) {
                                doors.add("${c.packageName}/${c.className}")
                            }
                            if (SpeechRecognizer.isRecognitionAvailable(this)) {
                                doors.add("default")
                            }
                            Log.i("BNSear", "doors: $doors")
                            result.success(doors)
                        }
                    }
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
                                call.argument<String>("door") ?: "default",
                                (call.argument<Int>("timeoutMs") ?: 120_000).toLong(),
                                result,
                            )
                        }
                    }
                    // Ask the on-device engine to FETCH the language pack
                    // (API 33: checkRecognitionSupport + triggerModelDownload).
                    // Fire-and-forget: if Hebrew lands, the next run's probe
                    // finds a working on-device door — fully offline words.
                    "suggestDownload" -> {
                        if (Build.VERSION.SDK_INT < 33) {
                            result.success(false)
                        } else {
                            result.success(suggestOnDeviceDownload(
                                call.argument<String>("locale") ?: "he-IL"))
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
        path: String, locale: String, door: String, timeoutMs: Long,
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
                Log.i("BNSear", "decode failed: $path")
                mainHandler.post {
                    earBusy = false
                    result.error("no_audio", "could not read $path", null)
                }
                return@Thread
            }
            Log.i("BNSear", "decoded ${decoded.first.size}B @${decoded.second}Hz " +
                "door=$door locale=$locale ${File(path).name}")
            // The online fd pipeline is picky about rates: the 16 kHz probe
            // sails through while a 44.1 kHz take is cut off with
            // SERVER_DISCONNECTED in 250ms (S23 field truth, 2026-08-19).
            // Every take goes down to 16 kHz mono — the rate speech
            // engines eat natively.
            val pcm16 = resampleTo16k(decoded.first, decoded.second)
            if (pcm16.size != decoded.first.size) {
                Log.i("BNSear", "resampled to ${pcm16.size}B @16000Hz")
            }
            if (Build.VERSION.SDK_INT >= 33) {
                mainHandler.post {
                    listenToPcm(pcm16, 16000, locale, door,
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

    /// Plain linear resampling to 16 kHz mono PCM16 — plenty for speech.
    private fun resampleTo16k(pcm: ByteArray, rate: Int): ByteArray {
        if (rate == 16000 || rate <= 0) return pcm
        val nIn = pcm.size / 2
        if (nIn < 2) return pcm
        val src = ByteBuffer.wrap(pcm).order(ByteOrder.LITTLE_ENDIAN)
        val nOut = ((nIn.toLong() * 16000) / rate).toInt().coerceAtLeast(1)
        val out = ByteArray(nOut * 2)
        val dst = ByteBuffer.wrap(out).order(ByteOrder.LITTLE_ENDIAN)
        for (i in 0 until nOut) {
            val pos = i.toDouble() * rate / 16000.0
            val i0 = pos.toInt().coerceAtMost(nIn - 1)
            val i1 = (i0 + 1).coerceAtMost(nIn - 1)
            val frac = pos - i0
            val s = src.getShort(i0 * 2) * (1 - frac) +
                src.getShort(i1 * 2) * frac
            dst.putShort(i * 2, s.toInt().toShort())
        }
        return out
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
        pcm: ByteArray, rate: Int, locale: String, door: String,
        timeoutMs: Long, result: MethodChannel.Result
    ) {
        val recognizer: SpeechRecognizer = when (door) {
            "ondevice" -> {
                if (!SpeechRecognizer.isOnDeviceRecognitionAvailable(this)) {
                    Log.i("BNSear", "door=ondevice: unavailable")
                    earBusy = false
                    result.error("no_ondevice", "no on-device recognizer", null)
                    return
                }
                Log.i("BNSear", "door=ondevice")
                SpeechRecognizer.createOnDeviceSpeechRecognizer(this)
            }
            "default" -> {
                if (!SpeechRecognizer.isRecognitionAvailable(this)) {
                    Log.i("BNSear", "door=default: unavailable")
                    earBusy = false
                    result.error("no_service", "no recognition service", null)
                    return
                }
                Log.i("BNSear", "door=default")
                SpeechRecognizer.createSpeechRecognizer(this)
            }
            else -> {
                val parts = door.split('/')
                if (parts.size != 2) {
                    earBusy = false
                    result.error("bad_door", door, null)
                    return
                }
                Log.i("BNSear", "door=$door")
                SpeechRecognizer.createSpeechRecognizer(
                    this, ComponentName(parts[0], parts[1]))
            }
        }
        val pipe = ParcelFileDescriptor.createPipe()
        var finished = false
        lateinit var timeout: Runnable
        var wrapUp: Runnable? = null
        // Every road out passes here exactly once: destroy, close, answer.
        fun finish(words: String?, errCode: String?) {
            if (finished) return
            finished = true
            mainHandler.removeCallbacks(timeout)
            wrapUp?.let { mainHandler.removeCallbacks(it) }
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
        timeout = Runnable {
            Log.i("BNSear", "door=$door hard timeout")
            finish(null, "ear_timeout")
        }
        mainHandler.postDelayed(timeout, timeoutMs)
        // An fd session is a SEGMENTED session (the API-33 recipe this
        // door was missing): words arrive per segment, and the session
        // ends when the source ends. Plain onResults stays handled for
        // services that answer the classic way.
        val segments = StringBuilder()
        fun joined(tail: String?): String {
            val t = (tail ?: "").trim()
            if (t.isNotEmpty()) {
                if (segments.isNotEmpty()) segments.append('\n')
                segments.append(t)
            }
            return segments.toString().trim()
        }
        recognizer.setRecognitionListener(object : RecognitionListener {
            override fun onResults(results: Bundle?) {
                val texts = results
                    ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                Log.i("BNSear",
                    "door=$door results len=${texts?.firstOrNull()?.length ?: -1}")
                finish(joined(texts?.firstOrNull()), null)
            }

            override fun onSegmentResults(segmentResults: Bundle) {
                val texts = segmentResults
                    .getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                Log.i("BNSear",
                    "door=$door segment len=${texts?.firstOrNull()?.length ?: -1}")
                joined(texts?.firstOrNull())
            }

            override fun onEndOfSegmentedSession() {
                Log.i("BNSear", "door=$door segmented session ended")
                finish(segments.toString().trim(), null)
            }

            override fun onError(error: Int) {
                Log.i("BNSear", "door=$door onError=$error")
                // Silence is an answer, not a failure: the ear worked and
                // heard nothing. Anything else names a broken door — but
                // words already gathered from segments are never dropped.
                if (error == SpeechRecognizer.ERROR_NO_MATCH ||
                    error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT ||
                    segments.isNotEmpty()
                ) {
                    finish(segments.toString().trim(), null)
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
            // Reading from a file descriptor IS a segmented session — the
            // documented pairing. Without it Google's service closed the
            // session in half a second with an empty result (S23 field
            // truth, 2026-08-19).
            putExtra(RecognizerIntent.EXTRA_SEGMENTED_SESSION,
                RecognizerIntent.EXTRA_AUDIO_SOURCE)
            // No asterisks over the person's own words (mad-vent law).
            putExtra(RecognizerIntent.EXTRA_MASK_OFFENSIVE_WORDS, false)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        }
        // A silence-only take never triggers any callback in a segmented
        // session (S23 field truth, 2026-08-19: «כותבים את המילים…» hung
        // the full timeout on a quiet room). So: once the whole file has
        // been fed and consumed, a short grace — then we close with
        // whatever was heard, empty included. The door stays trusted.
        wrapUp = Runnable {
            Log.i("BNSear", "door=$door wrap-up after EOF")
            finish(segments.toString().trim(), null)
        }
        try {
            recognizer.startListening(intent)
        } catch (e: Exception) {
            // The fd-in-intent path is the fragile joint (some glue layers
            // refuse file descriptors) — name the refusal in the log.
            Log.e("BNSear", "door=$door startListening threw", e)
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
                        // ~4× realtime, one second of audio per quarter
                        // second: the service streams to its server as it
                        // reads, and blasting a 16-second take at 100×
                        // folded the network layer (S23 field truth,
                        // 2026-08-19: ERROR_NETWORK 40ms after the feed).
                        if (off < pcm.size) Thread.sleep(250)
                    }
                }
                // The pipe is small, so writes complete only as the service
                // reads: reaching here means the audio was consumed whole.
                Log.i("BNSear", "door=$door audio fed (${pcm.size}B)")
                wrapUp?.let { mainHandler.postDelayed(it, 20_000) }
            } catch (_: Exception) {
                // Reader closed early (recognizer finished or died) — fine.
            }
        }.apply { name = "bns-file-ear-feed" }.start()
    }

    /// Every RecognitionService Google publishes on this phone, ranked:
    /// the Google app (the Waze popup's own home) first, then Speech
    /// Services (com.google.android.tts), then the rest. The S23 carries
    /// no quicksearchbox service (field truth, 2026-08-19) — its cast is
    /// AiAi (on-device host), Speech Services, and third parties we never
    /// touch (the voice goes only to the OS and Google's own engines).
    private fun googleRecognitionServices(): List<ComponentName> {
        return try {
            val all = packageManager.queryIntentServices(
                Intent(RecognitionService.SERVICE_INTERFACE), 0)
                .mapNotNull { it.serviceInfo }
            Log.i("BNSear", "recognition services: " +
                all.joinToString { "${it.packageName}/${it.name}" })
            all.filter { it.packageName.startsWith("com.google.") }
                .sortedBy {
                    when (it.packageName) {
                        "com.google.android.googlequicksearchbox" -> 0
                        "com.google.android.tts" -> 1
                        else -> 2
                    }
                }
                .map { ComponentName(it.packageName, it.name) }
        } catch (e: Exception) {
            Log.e("BNSear", "service query failed", e)
            emptyList()
        }
    }

    /// Ask the on-device engine for the Hebrew pack (API 33). Honest
    /// telemetry in the log either way; true = a download was triggered.
    /// If the pack lands, the next run's probe finds a working ondevice
    /// door — words with no network at all.
    @RequiresApi(Build.VERSION_CODES.TIRAMISU)
    private fun suggestOnDeviceDownload(locale: String): Boolean {
        if (!SpeechRecognizer.isOnDeviceRecognitionAvailable(this)) {
            Log.i("BNSear", "download: no on-device recognizer to teach")
            return false
        }
        return try {
            val recognizer = SpeechRecognizer.createOnDeviceSpeechRecognizer(this)
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
            }
            recognizer.checkRecognitionSupport(intent, mainExecutor,
                object : RecognitionSupportCallback {
                    override fun onSupportResult(support: RecognitionSupport) {
                        Log.i("BNSear", "ondevice support: " +
                            "installed=${support.installedOnDeviceLanguages} " +
                            "supported=${support.supportedOnDeviceLanguages} " +
                            "pending=${support.pendingOnDeviceLanguages}")
                        val canLearn = support.supportedOnDeviceLanguages.any {
                            it.startsWith("he") || it.startsWith("iw")
                        }
                        if (canLearn) {
                            Log.i("BNSear", "download: triggering $locale pack")
                            recognizer.triggerModelDownload(intent)
                        }
                        // Give the trigger a breath before letting go.
                        mainHandler.postDelayed({
                            try { recognizer.destroy() } catch (_: Exception) {}
                        }, 3_000)
                    }

                    override fun onError(error: Int) {
                        Log.i("BNSear", "download: support check error=$error")
                        try { recognizer.destroy() } catch (_: Exception) {}
                    }
                })
            true
        } catch (e: Exception) {
            Log.e("BNSear", "download suggestion failed", e)
            false
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
