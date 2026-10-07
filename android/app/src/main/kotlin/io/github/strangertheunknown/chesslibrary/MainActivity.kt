package io.github.strangertheunknown.chesslibrary

import android.content.Intent
import android.media.projection.MediaProjectionConfig
import android.media.projection.MediaProjectionManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "chess_library/native"

    /** Hamle sesleri (bkz. [GameSounds]); Dart'taki `AndroidSound`. */
    private val soundChannelName = "chess_library/sound"
    private var sounds: GameSounds? = null

    /** Ekran kaydı (bkz. [RecordService], [Capture]); Dart'ta `ScreenRecording`. */
    private val recordChannelName = "chess_library/record"
    private var recordChannel: MethodChannel? = null

    /** "prepare" isteğinin bekleyen cevabı (izin ve onay pencereleri). */
    private var pendingPrepare: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "nativeLibraryDir" -> {
                        result.success(applicationInfo.nativeLibraryDir)
                    }
                    "stockfishPath" -> {
                        val dir = applicationInfo.nativeLibraryDir ?: ""
                        val f = File(dir, "libstockfish.so")
                        result.success(if (f.exists()) f.absolutePath else null)
                    }
                    else -> result.notImplemented()
                }
            }

        val gameSounds = GameSounds(applicationContext)
        sounds = gameSounds
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, soundChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "load" -> {
                        val map = call.argument<Map<String, String>>("sounds") ?: emptyMap()
                        result.success(gameSounds.load(map))
                    }
                    "play" -> {
                        val name = call.argument<String>("name") ?: ""
                        result.success(gameSounds.play(name))
                    }
                    "failures" -> result.success(gameSounds.failures())
                    else -> result.notImplemented()
                }
            }

        Capture.appContext = applicationContext
        val record = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, recordChannelName)
        recordChannel = record
        Capture.onStoppedOutside = { saved -> record.invokeMethod("stopped", saved) }
        record.setMethodCallHandler { call, result ->
            when (call.method) {
                // Uygulamanın kendi sesini yakalamak Android 10 ister.
                "supported" -> result.success(Build.VERSION.SDK_INT >= 29)
                "prepare" -> prepare(result)
                "begin" -> {
                    val name = call.argument<String>("name") ?: "Chess Library"
                    result.success(Capture.begin(this, name, gameSounds))
                }
                "stop" -> Capture.finish { saved -> result.success(saved) }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Android'in "ekranı kaydetsin mi?" penceresi. Cevap: "ok",
     * "cancelled" ya da hata metni. (Ses kaydı izni 10.10.1'den beri
     * gerekmiyor: videonun sesi uygulamanın kendi seslerinden üretiliyor.)
     */
    private fun prepare(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 29) {
            result.success("unsupported")
            return
        }
        pendingPrepare?.success("cancelled")
        pendingPrepare = result
        askToCapture()
    }

    /**
     * Android'in "ekranı kaydetsin mi?" penceresi.
     *
     * Android 14+ pencerede "tek bir uygulama" da sunuyor; uygulama kendi
     * kendini seçince kayıt hemen kesiliyordu ("failing to set
     * ContentRecordingSession": uygulama zaten açık olduğu için seçimin
     * bağlandığı görev bulunamıyor; öykünücüde Android 15'te görüldü).
     * Bu yüzden pencere doğrudan tüm ekran kaydıyla açılıyor — telefonun
     * kendi kaydedicisindeki gibi.
     */
    private fun askToCapture() {
        val manager = getSystemService(MediaProjectionManager::class.java)
        val intent = if (Build.VERSION.SDK_INT >= 34) {
            manager.createScreenCaptureIntent(MediaProjectionConfig.createConfigForDefaultDisplay())
        } else {
            manager.createScreenCaptureIntent()
        }
        @Suppress("DEPRECATION")
        startActivityForResult(intent, REQUEST_CAPTURE)
    }

    @Deprecated("FlutterActivity bir ComponentActivity değil")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_CAPTURE) return
        val result = pendingPrepare ?: return
        pendingPrepare = null
        if (resultCode != RESULT_OK || data == null) {
            result.success("cancelled")
            return
        }
        Capture.onPrepared = { error -> result.success(error ?: "ok") }
        val service = Intent(this, RecordService::class.java)
            .putExtra(RecordService.EXTRA_CODE, resultCode)
            .putExtra(RecordService.EXTRA_DATA, data)
        startForegroundService(service)
    }

    companion object {
        private const val REQUEST_CAPTURE = 4102
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        sounds?.release()
        sounds = null
        Capture.onStoppedOutside = null
        Capture.finish()
        recordChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
