package io.github.strangertheunknown.chesslibrary

import android.annotation.SuppressLint
import android.content.ContentValues
import android.content.Context
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.AudioFormat
import android.media.AudioPlaybackCaptureConfiguration
import android.media.AudioRecord
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.media.projection.MediaProjection
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.os.Process
import android.provider.MediaStore
import android.util.Log

/**
 * Ekranı ve uygulamanın kendi seslerini MP4'e yazar (Android 10+).
 *
 * Görüntü: sanal ekran → H.264 kodlayıcının giriş yüzeyi. Ekran
 * değişmediğinde de kare üretiliyor ([MediaFormat.KEY_REPEAT_PREVIOUS_FRAME_AFTER]):
 * yoksa başta ve sonda bekletilen durgun tahta videoya hiç girmezdi.
 *
 * Ses: yalnızca bu uygulamanın çaldığı sesler (AudioPlaybackCapture,
 * kendi kullanıcı kimliğiyle sınırlı) → AAC. Müzik ya da bildirim sesi
 * girmiyor.
 *
 * Dosya: Filmler/Chess Library (MediaStore); yazılırken "beklemede",
 * bitince galeride görünüyor.
 */
class Mp4Writer(
    private val context: Context,
    private val projection: MediaProjection,
    displayWidth: Int,
    displayHeight: Int,
    private val dpi: Int,
    private val name: String,
) {
    private val width: Int
    private val height: Int
    private val video = MediaCodec.createEncoderByType(VIDEO_MIME)
    private val audio = MediaCodec.createEncoderByType(AUDIO_MIME)
    private var record: AudioRecord? = null
    private var display: VirtualDisplay? = null

    private var uri: Uri? = null
    private var file: ParcelFileDescriptor? = null
    private var muxer: MediaMuxer? = null
    private val lock = Object()
    private var videoTrack = -1
    private var audioTrack = -1
    private var muxerStarted = false
    private var wroteVideo = false

    @Volatile private var capturing = false
    private var videoThread: Thread? = null
    private var audioThread: Thread? = null

    init {
        // Kodlayıcının desteklediği en büyük boyut: ekran boyutu, gerekirse
        // orantılı küçültülmüş; kenarlar çift sayı.
        val caps = video.codecInfo.getCapabilitiesForType(VIDEO_MIME).videoCapabilities
        var scale = 1.0
        var w: Int
        var h: Int
        while (true) {
            w = ((displayWidth * scale).toInt() / 2) * 2
            h = ((displayHeight * scale).toInt() / 2) * 2
            if (caps.isSizeSupported(w, h) || scale < 0.3) break
            scale -= 0.1
        }
        width = w
        height = h
    }

    /** Kaydı başlatır; olmazsa hatayı fırlatır. */
    @SuppressLint("MissingPermission") // İzin MainActivity'de alınıyor.
    fun start() {
        val values = ContentValues().apply {
            put(MediaStore.Video.Media.DISPLAY_NAME, "$name.mp4")
            put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
            put(MediaStore.Video.Media.RELATIVE_PATH, RELATIVE_DIR)
            put(MediaStore.Video.Media.IS_PENDING, 1)
        }
        val resolver = context.contentResolver
        val target = resolver.insert(
            MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY),
            values,
        ) ?: throw IllegalStateException("MediaStore kaydı açılamadı")
        uri = target
        val fd = resolver.openFileDescriptor(target, "rw")
            ?: throw IllegalStateException("dosya açılamadı")
        file = fd
        muxer = MediaMuxer(fd.fileDescriptor, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)

        val videoFormat = MediaFormat.createVideoFormat(VIDEO_MIME, width, height).apply {
            setInteger(
                MediaFormat.KEY_COLOR_FORMAT,
                MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface,
            )
            setInteger(MediaFormat.KEY_BIT_RATE, (width * height * FPS * 0.15).toInt())
            setInteger(MediaFormat.KEY_FRAME_RATE, FPS)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
            setLong(MediaFormat.KEY_REPEAT_PREVIOUS_FRAME_AFTER, 1_000_000L / FPS)
        }
        video.configure(videoFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        val surface = video.createInputSurface()

        val audioFormat = MediaFormat.createAudioFormat(AUDIO_MIME, SAMPLE_RATE, 1).apply {
            setInteger(
                MediaFormat.KEY_AAC_PROFILE,
                MediaCodecInfo.CodecProfileLevel.AACObjectLC,
            )
            setInteger(MediaFormat.KEY_BIT_RATE, 128_000)
            setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16_384)
        }
        audio.configure(audioFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)

        val capture = AudioPlaybackCaptureConfiguration.Builder(projection)
            .addMatchingUid(Process.myUid())
            .build()
        val pcm = AudioFormat.Builder()
            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
            .setSampleRate(SAMPLE_RATE)
            .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
            .build()
        val minBuffer = AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        record = AudioRecord.Builder()
            .setAudioFormat(pcm)
            .setBufferSizeInBytes(maxOf(minBuffer * 2, 8_192))
            .setAudioPlaybackCaptureConfig(capture)
            .build()

        capturing = true
        video.start()
        audio.start()
        record!!.startRecording()
        display = projection.createVirtualDisplay(
            "ChessLibraryRecord",
            width,
            height,
            dpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            surface,
            null,
            null,
        )
        videoThread = Thread({ drainVideo() }, "record-video").apply { start() }
        audioThread = Thread({ pumpAudio() }, "record-audio").apply { start() }
        Log.i(TAG, "kayıt başladı: ${width}x$height, $name")
    }

    /**
     * Kaydı bitirir ve dosyayı galeriye açar. Kaydedilen yolu döner
     * ("Movies/Chess Library/….mp4"); hiç kare yazılmadıysa dosyayı
     * siler ve null döner.
     */
    fun stop(): String? {
        if (!capturing) return null
        capturing = false
        try {
            audioThread?.join(3_000)
            video.signalEndOfInputStream()
            videoThread?.join(5_000)
        } catch (e: Exception) {
            Log.w(TAG, "durdururken", e)
        }
        display?.release()
        runCatching { record?.stop() }
        runCatching { record?.release() }
        runCatching { video.stop() }
        runCatching { video.release() }
        runCatching { audio.stop() }
        runCatching { audio.release() }
        val ok = synchronized(lock) {
            val started = muxerStarted
            runCatching { if (started) muxer?.stop() }
            runCatching { muxer?.release() }
            started && wroteVideo
        }
        runCatching { file?.close() }
        val target = uri ?: return null
        val resolver = context.contentResolver
        if (!ok) {
            runCatching { resolver.delete(target, null, null) }
            Log.w(TAG, "kare yazılmadı; dosya silindi")
            return null
        }
        resolver.update(
            target,
            ContentValues().apply { put(MediaStore.Video.Media.IS_PENDING, 0) },
            null,
            null,
        )
        Log.i(TAG, "kayıt bitti: $RELATIVE_DIR/$name.mp4")
        return "$RELATIVE_DIR/$name.mp4"
    }

    private fun drainVideo() {
        val info = MediaCodec.BufferInfo()
        while (true) {
            val index = video.dequeueOutputBuffer(info, 10_000)
            if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                synchronized(lock) {
                    videoTrack = muxer!!.addTrack(video.outputFormat)
                    startMuxerIfReady()
                }
            } else if (index >= 0) {
                writeSample(video, index, info, isVideo = true)
                if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return
            }
        }
    }

    private fun pumpAudio() {
        val rec = record ?: return
        var startUs = System.nanoTime() / 1_000
        var samples = 0L
        val info = MediaCodec.BufferInfo()
        var inputDone = false
        while (true) {
            if (!inputDone) {
                val inIndex = audio.dequeueInputBuffer(10_000)
                if (inIndex >= 0) {
                    val buffer = audio.getInputBuffer(inIndex)!!
                    buffer.clear()
                    if (!capturing) {
                        val pts = startUs + samples * 1_000_000L / SAMPLE_RATE
                        audio.queueInputBuffer(inIndex, 0, 0, pts, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        inputDone = true
                    } else {
                        val read = rec.read(buffer, buffer.capacity())
                        val size = maxOf(read, 0)
                        // Zaman damgası örnek sayısından; ses gerçek zamanın
                        // gerisine düşerse (yakalama bir süre veri vermezse)
                        // saate yeniden hizalanıyor. Yoksa ses görüntünün
                        // gerisinde kalıyordu (öykünücüde 9 sn'de ~1 sn).
                        var pts = startUs + samples * 1_000_000L / SAMPLE_RATE
                        val bufferUs = (size / 2) * 1_000_000L / SAMPLE_RATE
                        val realStart = System.nanoTime() / 1_000 - bufferUs
                        if (realStart - pts > RESYNC_US) {
                            startUs += realStart - pts
                            pts = realStart
                        }
                        samples += size / 2
                        audio.queueInputBuffer(inIndex, 0, size, pts, 0)
                    }
                }
            }
            val outIndex = audio.dequeueOutputBuffer(info, 0)
            if (outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                synchronized(lock) {
                    audioTrack = muxer!!.addTrack(audio.outputFormat)
                    startMuxerIfReady()
                }
            } else if (outIndex >= 0) {
                writeSample(audio, outIndex, info, isVideo = false)
                if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return
            }
        }
    }

    private fun startMuxerIfReady() {
        if (!muxerStarted && videoTrack >= 0 && audioTrack >= 0) {
            muxer!!.start()
            muxerStarted = true
            lock.notifyAll()
        }
    }

    /**
     * Kodlanmış örneği yazar. Kas (muxer) iki iz de hazır olunca başlıyor;
     * o ana kadar gelen ilk örnek bekletiliyor (ilk görüntü karesi anahtar
     * kare, atılırsa video bozuk başlar).
     */
    private fun writeSample(codec: MediaCodec, index: Int, info: MediaCodec.BufferInfo, isVideo: Boolean) {
        if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0 || info.size == 0) {
            codec.releaseOutputBuffer(index, false)
            return
        }
        synchronized(lock) {
            var waited = 0
            while (!muxerStarted && waited < 3_000) {
                lock.wait(50)
                waited += 50
            }
            if (muxerStarted) {
                val buffer = codec.getOutputBuffer(index)!!
                buffer.position(info.offset)
                buffer.limit(info.offset + info.size)
                muxer!!.writeSampleData(if (isVideo) videoTrack else audioTrack, buffer, info)
                if (isVideo) wroteVideo = true
            }
        }
        codec.releaseOutputBuffer(index, false)
    }

    companion object {
        private const val TAG = "ChessLibraryRecord"
        private const val VIDEO_MIME = MediaFormat.MIMETYPE_VIDEO_AVC
        private const val AUDIO_MIME = MediaFormat.MIMETYPE_AUDIO_AAC
        private const val FPS = 30
        private const val SAMPLE_RATE = 44_100

        /** Sesin saatten bu kadar geride kalması yeniden hizalatıyor. */
        private const val RESYNC_US = 60_000L
        const val RELATIVE_DIR = "Movies/Chess Library"
    }
}
