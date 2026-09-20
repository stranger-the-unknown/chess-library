import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import 'stockfish_uci.dart';

/// Android APK içindeki Stockfish varlığını uygulama destek dizinine çıkarır.
///
/// İkili dosyalar git'e girmez; derlemeden önce
/// `android/stockfish/README.md` adımlarıyla `assets/stockfish/` altına
/// kopyalanır. Yoksa `null` döner ve motor Dart'a düşer.
Future<String?> ensureAndroidStockfishBinary() async {
  if (kIsWeb || !Platform.isAndroid) return null;

  try {
    final support = await getApplicationSupportDirectory();
    final dest = File('${support.path}/stockfish');
    if (await dest.exists()) {
      final len = await dest.length();
      if (len > 1024 * 1024) {
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
        // Yürütülebilir yap.
        try {
          await Process.run('chmod', ['755', dest.path]);
        } catch (_) {
          // Bazı cihazlarda chmod yok; FileMode ile dene.
          try {
            final result = await Process.run('/system/bin/chmod', ['755', dest.path]);
            if (result.exitCode != 0) {
              // ignore
            }
          } catch (_) {}
        }
        StockfishUci.cachedBinaryPath = dest.path;
        return dest.path;
      } catch (_) {
        // Bu ABI asset'te yok; sonrakini dene.
      }
    }
  } catch (_) {}

  return StockfishUci.resolveBinaryPath();
}
