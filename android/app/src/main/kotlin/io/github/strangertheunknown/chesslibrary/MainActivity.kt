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
                    "stockfishSmoke" -> {
                        // Process.start can run extracted jni lib; returns first lines or error.
                        try {
                            val dir = applicationInfo.nativeLibraryDir ?: ""
                            val bin = File(dir, "libstockfish.so")
                            if (!bin.exists()) {
                                result.error("missing", "libstockfish.so not in $dir", null)
                                return@setMethodCallHandler
                            }
                            val pb = ProcessBuilder(bin.absolutePath)
                                .redirectErrorStream(true)
                            val p = pb.start()
                            p.outputStream.write("uci\n".toByteArray())
                            p.outputStream.flush()
                            val reader = p.inputStream.bufferedReader()
                            val lines = mutableListOf<String>()
                            val deadline = System.currentTimeMillis() + 4000
                            while (System.currentTimeMillis() < deadline && lines.size < 40) {
                                if (reader.ready()) {
                                    val line = reader.readLine() ?: break
                                    lines.add(line)
                                    if (line == "uciok") break
                                } else {
                                    Thread.sleep(20)
                                }
                            }
                            try { p.destroy() } catch (_: Exception) {}
                            result.success(
                                mapOf(
                                    "path" to bin.absolutePath,
                                    "exists" to true,
                                    "length" to bin.length(),
                                    "canExecute" to bin.canExecute(),
                                    "lines" to lines,
                                    "uciok" to lines.contains("uciok"),
                                ),
                            )
                        } catch (e: Exception) {
                            result.error("exec", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}