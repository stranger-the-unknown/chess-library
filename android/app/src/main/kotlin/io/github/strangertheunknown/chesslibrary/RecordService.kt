package io.github.strangertheunknown.chesslibrary

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log

/**
 * Ekran kaydının ön plan hizmeti ("ekran yansıtma" türü).
 *
 * Android 10'dan beri ekran yansıtma yalnızca böyle bir hizmet açıkken
 * yapılabiliyor; Android 14'ten beri hizmet kullanıcının onayından
 * **sonra** başlatılmalı ve izin belgesi (token) ancak ondan sonra
 * kullanılabiliyor. Akış: MainActivity onay penceresini açar → onay
 * gelince bu hizmeti başlatır → hizmet yansıtmayı alır ve [Capture]'a
 * verir → Dart "begin" der → kayıt başlar.
 *
 * Bildirimdeki "Durdur" ya da sistemin kendi durdurma düğmesi (Android
 * 14+ durum çubuğu) kaydı bitirir ve o ana kadarki kısım kaydedilir.
 */
class RecordService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            Capture.finish(fromOutside = true)
            return START_NOT_STICKY
        }
        startInForeground()
        val code = intent?.getIntExtra(EXTRA_CODE, 0) ?: 0
        val data: Intent? = if (Build.VERSION.SDK_INT >= 33) {
            intent?.getParcelableExtra(EXTRA_DATA, Intent::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent?.getParcelableExtra(EXTRA_DATA)
        }
        val manager = getSystemService(MediaProjectionManager::class.java)
        val projection = if (data != null) manager.getMediaProjection(code, data) else null
        if (projection == null) {
            Capture.prepared(null, "izin belgesi yok")
            stopSelf()
            return START_NOT_STICKY
        }
        // Android 14+: yansıtma geri çağrısı sanal ekrandan önce kaydedilmeli.
        projection.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() {
                Capture.finish(fromOutside = true)
            }
        }, Handler(Looper.getMainLooper()))
        Capture.prepared(projection, null)
        return START_NOT_STICKY
    }

    private fun startInForeground() {
        val manager = getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL) == null) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, "Ekran kaydı", NotificationManager.IMPORTANCE_LOW)
            )
        }
        val stop = PendingIntent.getService(
            this,
            0,
            Intent(this, RecordService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = Notification.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.presence_video_online)
            .setContentTitle("Chess Library ekranı kaydediyor")
            .setOngoing(true)
            .addAction(Notification.Action.Builder(null, "Durdur", stop).build())
            .build()
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    companion object {
        const val EXTRA_CODE = "code"
        const val EXTRA_DATA = "data"
        const val ACTION_STOP = "io.github.strangertheunknown.chesslibrary.STOP_RECORDING"
        private const val CHANNEL = "screen_recording"
        private const val NOTIFICATION_ID = 7
    }
}

/**
 * Kaydın durumu: MainActivity (kanal), [RecordService] ve [Mp4Writer]
 * arasında. Hepsi ana iş parçacığında çağrılıyor; dosyanın kapatılması
 * ayrı bir iş parçacığında.
 */
object Capture {
    private const val TAG = "ChessLibraryRecord"
    private val main = Handler(Looper.getMainLooper())

    private var projection: MediaProjection? = null
    private var writer: Mp4Writer? = null

    /** Hizmeti durdurmak için; MainActivity veriyor. */
    var appContext: Context? = null

    /** Onay ve hizmet hazır olunca çağrılır (hata metni ya da null). */
    var onPrepared: ((String?) -> Unit)? = null

    /** Kayıt dışarıdan bittiğinde (bildirim, sistem): kaydedilen yol. */
    var onStoppedOutside: ((String?) -> Unit)? = null

    fun prepared(value: MediaProjection?, error: String?) {
        projection = value
        val callback = onPrepared
        onPrepared = null
        callback?.invoke(if (value == null) (error ?: "bilinmeyen hata") else null)
    }

    /** Kaydı başlatır; hata metni ya da null. */
    fun begin(context: Context, name: String, sounds: GameSounds): String? {
        val current = projection ?: return "ekran yansıtma hazır değil"
        return try {
            val metrics = context.resources.displayMetrics
            val bounds = if (Build.VERSION.SDK_INT >= 30) {
                context.getSystemService(android.view.WindowManager::class.java)
                    .maximumWindowMetrics.bounds
            } else {
                null
            }
            val w = bounds?.width() ?: metrics.widthPixels
            val h = bounds?.height() ?: metrics.heightPixels
            writer = Mp4Writer(context.applicationContext, current, w, h, metrics.densityDpi, name, sounds)
                .also { it.start() }
            null
        } catch (e: Exception) {
            Log.w(TAG, "başlatılamadı", e)
            writer = null
            release()
            e.message ?: e.toString()
        }
    }

    /**
     * Kaydı bitirir; sonuç (kaydedilen yol ya da null) ana iş parçacığında
     * [done]'a gelir. [fromOutside]: bildirimden ya da sistemden durduruldu.
     */
    fun finish(fromOutside: Boolean = false, done: ((String?) -> Unit)? = null) {
        val current = writer
        writer = null
        if (current == null) {
            release()
            done?.invoke(null)
            return
        }
        Thread {
            val saved = runCatching { current.stop() }.getOrNull()
            main.post {
                release()
                done?.invoke(saved)
                if (fromOutside) onStoppedOutside?.invoke(saved)
            }
        }.start()
    }

    private fun release() {
        val current = projection
        projection = null
        runCatching { current?.stop() }
        appContext?.let { context ->
            runCatching { context.stopService(Intent(context, RecordService::class.java)) }
        }
    }
}
