import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show MethodChannel, rootBundle;
import 'package:path_provider/path_provider.dart';

import 'stockfish_uci.dart';

const _nativeChannel = MethodChannel('chess_library/native');

/// Android'de Stockfish ikili yolunu hazırlar.
///
/// **Kök neden:** Asset'ten uygulama veri dizinine çıkarılan ikili Android 10+
/// W^X / SELinux yüzünden `Process.start` ile çalışmaz. Ayrıca AGP varsayılanı
/// `extractNativeLibs=false` iken jniLibs APK içinde kalır ve dosya olarak
/// görünmez. `Platform.resolvedExecutable` ebeveyni de güvenilir nativeLibraryDir
/// değildir.
///
/// **Sağlam yol:** `jniLibs` + `extractNativeLibs=true` +
/// `applicationInfo.nativeLibraryDir/libstockfish.so` (MethodChannel).
Future<String?> ensureAndroidStockfishBinary() async {
  if (kIsWeb || !Platform.isAndroid) return null;

  try {
    final native = await _nativeLibraryStockfish();
    if (native != null) {
      StockfishUci.cachedBinaryPath = native;
      return native;
    }

    // Yedek: eski extract yolu (çoğu cihazda W^X ile başarısız olur).
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
      } catch (_) {}
    }
  } catch (_) {}

  return StockfishUci.resolveBinaryPath();
}

Future<String?> _nativeLibraryStockfish() async {
  try {
    final fromChannel =
        await _nativeChannel.invokeMethod<String>('stockfishPath');
    if (fromChannel != null && fromChannel.isNotEmpty) {
      final f = File(fromChannel);
      if (await f.exists() && await f.length() > 1024 * 1024) {
        return f.path;
      }
    }
  } catch (_) {}

  try {
    final dir =
        await _nativeChannel.invokeMethod<String>('nativeLibraryDir');
    if (dir != null && dir.isNotEmpty) {
      final candidate = File('$dir${Platform.pathSeparator}libstockfish.so');
      if (await candidate.exists() && await candidate.length() > 1024 * 1024) {
        return candidate.path;
      }
    }
  } catch (_) {}

  // Son çare: resolvedExecutable ebeveyni (Flutter sürümüne göre kırılgan).
  try {
    final dir = File(Platform.resolvedExecutable).parent.path;
    final candidate = File('$dir${Platform.pathSeparator}libstockfish.so');
    if (await candidate.exists() && await candidate.length() > 1024 * 1024) {
      return candidate.path;
    }
  } catch (_) {}

  return null;
}

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
    } catch (_) {}
  }
}