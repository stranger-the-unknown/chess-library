package io.github.strangertheunknown.chesslibrary

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "chess_library/native"

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
    }
}