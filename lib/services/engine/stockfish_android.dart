import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import 'stockfish_uci.dart';

/// Android APK içindeki Stockfish varlığını uygulama destek dizinine çıkarır.
///
/// İkili dosyalar git'e girmez; derlemeden önce
/// `android/stockfish/README.md` adımlarıyla `assets/stockfish/` altına
/// kopyalanır. Yoksa `null` döner.
///
/// Not: `dart:io` [File] üzerinde `setExecutable` yok (Dart 3.13); yürütme
/// biti `chmod` ile uygulanır. Mevcut dosyada da her açılışta yeniden +x.
Future<String?> ensureAndroidStockfishBinary() async {
  if (kIsWeb || !Platform.isAndroid) return null;

  try {
    final support = await getApplicationSupportDirectory();
    final dest = File('${support.path}/stockfish');
    if (await dest.exists()) {
      final len = await dest.length();
      if (len > 1024 * 1024) {
        // Yeniden kullanırken bile +x uygula (SELinux / çıkarım sonrası kayıp).
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

/// Yürütme bitini uygular (çıkarım sonrası ve mevcut dosyada tekrar).
///
/// `File.setExecutable` dart:io'da yok; chmod birincil yol. Birden fazla
/// yol denenir (toybox / system / sh).
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
