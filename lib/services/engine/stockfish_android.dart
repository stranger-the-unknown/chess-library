import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import 'stockfish_uci.dart';

/// Android'de Stockfish ikili yolunu hazırlar.
///
/// **Kök neden (8.0.1 ve öncesi):** Asset'ten `getApplicationSupportDirectory`
/// altına çıkarılan ikili `chmod 755` ile +x alsa bile Android 10+ W^X /
/// SELinux, yazılabilir uygulama veri dizininden `Process.start` ile
/// yürütmeyi engeller. Windows'ta sorun yoktu.
///
/// **Sağlam yol:** `jniLibs/<abi>/libstockfish.so` → paket yöneticisi
/// `nativeLibraryDir`'e çıkarır (yürütülebilir). Asset extract yedek kalır.
///
/// Her motor başlatmadan önce [EngineService] bunu çağırır.
Future<String?> ensureAndroidStockfishBinary() async {
  if (kIsWeb || !Platform.isAndroid) return null;

  try {
    final native = await _nativeLibraryStockfish();
    if (native != null) {
      StockfishUci.cachedBinaryPath = native;
      return native;
    }

    final support = await getApplicationSupportDirectory();
    final dest = File('${support.path}/stockfish');
    if (await dest.exists()) {
      final len = await dest.length();
      if (len > 1024 * 1024) {
        await _makeExecutable(dest);
        StockfishUci.cachedBinaryPath = dest.path;
        return dest.path;
      }
    }

    for (final abi in const ['arm64-v8a', 'armeabi-v7a']) {
      try {
        final data = await rootBundle.load('assets/stockfish/$abi');
        await dest.parent.create(recursive: true);
        final bytes =
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        await dest.writeAsBytes(bytes, flush: true);
        await _makeExecutable(dest);
        StockfishUci.cachedBinaryPath = dest.path;
        return dest.path;
      } catch (_) {
        // Bu ABI asset'te yok; sonrakini dene.
      }
    }
  } catch (_) {}

  return StockfishUci.resolveBinaryPath();
}

/// Flutter APK'da `Platform.resolvedExecutable` genelde
/// `…/lib/<abi>/libapp.so` (veya benzeri); ebeveyn dizin = nativeLibraryDir.
Future<String?> _nativeLibraryStockfish() async {
  try {
    final dir = File(Platform.resolvedExecutable).parent.path;
    final candidate = File('$dir${Platform.pathSeparator}libstockfish.so');
    if (!await candidate.exists()) return null;
    final len = await candidate.length();
    if (len <= 1024 * 1024) return null;
    return candidate.path;
  } catch (_) {
    return null;
  }
}

/// Yürütme bitini uygular (yalnızca asset-extract yedek yolu).
Future<void> _makeExecutable(File dest) async {
  final path = dest.path;
  final attempts = <List<String>>[
    ['chmod', '755', path],
    ['/system/bin/chmod', '755', path],
    ['/system/xbin/chmod', '755', path],
    ['sh', '-c', 'chmod 755 "$path"'],
  ];
  for (final args in attempts) {
    try {
      final result = await Process.run(args.first, args.sublist(1));
      if (result.exitCode == 0) return;
    } catch (_) {
      // Sonraki yolu dene.
    }
  }
}
