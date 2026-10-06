package io.github.strangertheunknown.chesslibrary

import android.content.Context
import android.media.AudioAttributes
import android.media.SoundPool
import android.util.Log
import io.flutter.FlutterInjector

/**
 * Hamle sesleri: Android'in kısa sesler için olan SoundPool'u.
 *
 * 10.9.0'a kadar her ses ayrı bir just_audio (ExoPlayer) oynatıcısıyla,
 * her çalışta başa sarılıp yeniden başlatılarak çalıyordu. Ekran kaydı
 * alınırken (işlemci görüntü kodlamakla meşgulken) bu başlangıçlar bazı
 * hamlelerde aksıyor ve kayıtta cızırtı oluyordu; aynı kayıtla YouTube'un
 * sesi temizdi. SoundPool sesleri açılışta bir kez çözüp bellekte tutuyor
 * ve her çalışta yalnızca hazır örneği karıştırıyor.
 *
 * Ses türü bilerek "oyun" (USAGE_GAME): Android'in ekran kaydı
 * (AudioPlaybackCapture) yalnızca medya, oyun ve bilinmeyen türleri
 * yakalıyor. "Arayüz sesi" (ASSISTANCE_SONIFICATION) seçilseydi hamle
 * sesleri kayda hiç girmezdi. Oyun sesi medya ses düzeyini izliyor
 * (just_audio'daki gibi) ve ses odağı istemiyor: çalan müzik durmuyor.
 */
class GameSounds(private val context: Context) {
    private val pool: SoundPool = SoundPool.Builder()
        // Hamle + alma, şah gibi üst üste gelen sesler için pay.
        .setMaxStreams(4)
        .setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_GAME)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
        )
        .build()

    /** Ses adı → SoundPool örnek kimliği. */
    private val samples = HashMap<String, Int>()

    /** Çözülüp çalınmaya hazır örnekler. */
    private val ready = HashSet<Int>()

    /** Çözülemeyen sesler (ad → durum kodu). */
    private val failed = HashMap<String, Int>()

    /**
     * Hazır olmadan çalınması istenen örnek: hazır olunca çalınıyor.
     * Uygulama açılır açılmaz yapılan ilk hamlenin sesi yutulmasın.
     */
    private var pending: Int? = null

    init {
        pool.setOnLoadCompleteListener { _, sampleId, status ->
            if (status == 0) {
                ready.add(sampleId)
                if (pending == sampleId) {
                    pending = null
                    start(sampleId)
                }
            } else {
                val name = samples.entries.firstOrNull { it.value == sampleId }?.key
                failed[name ?: "#$sampleId"] = status
                Log.w(TAG, "çözülemedi: $name (durum $status)")
            }
        }
    }

    /**
     * Sesleri yükler: [sounds] ad → Flutter varlık yolu
     * ("assets/sounds/wav/move-self.wav"). Açılamayanların adlarını döner;
     * çözme sonucu sonradan gelir ([failures]).
     */
    fun load(sounds: Map<String, String>): List<String> {
        val loader = FlutterInjector.instance().flutterLoader()
        val missing = ArrayList<String>()
        for ((name, asset) in sounds) {
            if (samples.containsKey(name)) continue
            try {
                context.assets.openFd(loader.getLookupKeyForAsset(asset)).use { fd ->
                    samples[name] = pool.load(fd, 1)
                }
            } catch (e: Exception) {
                Log.w(TAG, "açılamadı: $asset", e)
                missing.add(name)
            }
        }
        Log.i(TAG, "yüklendi: ${samples.size}, açılamayan: ${missing.size}")
        return missing
    }

    /** Sesi çalar. Ses yoksa ya da çözülemediyse false. */
    fun play(name: String): Boolean {
        val sample = samples[name] ?: return false
        if (failed.containsKey(name)) return false
        if (sample !in ready) {
            pending = sample
            return true
        }
        return start(sample)
    }

    /** Çözülemeyen sesler; ayarlar ekranı söylüyor. */
    fun failures(): List<String> = failed.keys.sorted()

    private fun start(sample: Int): Boolean {
        val stream = pool.play(sample, 1f, 1f, 1, 0, 1f)
        if (stream == 0) Log.w(TAG, "çalınamadı: örnek $sample")
        return stream != 0
    }

    fun release() = pool.release()

    companion object {
        private const val TAG = "ChessLibrarySound"
    }
}
