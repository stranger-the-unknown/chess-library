package io.github.strangertheunknown.chesslibrary

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "chess_library/native"

    /** Hamle sesleri (bkz. [GameSounds]); Dart'taki `AndroidSound`. */
    private val soundChannelName = "chess_library/sound"
    private var sounds: GameSounds? = null

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
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        sounds?.release()
        sounds = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
