import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

/// Linux'ta hamle sesleri.
///
/// `just_audio`'nun Linux gerçekleştirmesi yok. Sesleri sistemin kendi
/// komutu çalıyor: PulseAudio ya da PipeWire'da `paplay`, yalnız
/// PipeWire'da `pw-play`, yalnız ALSA'da `aplay`. Bu komutlar MP3'ü her
/// dağıtımda açamadığı için aynı sesler WAV olarak da paketleniyor
/// (`assets/sounds/wav/`). WAV'lar ilk kullanımda geçici klasöre bir kez
/// yazılıyor.
///
/// Hiçbiri yoksa ses çalınamıyor; bu **sessizce** geçmiyor: ayarlarda ses
/// seçeneğinin altında hangi komutların arandığı yazıyor ([unavailable]).
class LinuxSound {
  static final LinuxSound instance = LinuxSound._();
  LinuxSound._();

  /// Aranma sırasıyla oynatıcı komutları.
  static const List<String> players = ['paplay', 'pw-play', 'aplay'];

  /// Bir komut sistemde var mı? Testler değiştirir.
  @visibleForTesting
  static Future<bool> Function(String command) commandExists = (command) async {
    try {
      final result =
          await Process.run('sh', ['-c', 'command -v $command']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  };

  /// Sesi çalan süreç. Testler değiştirir.
  @visibleForTesting
  static Future<void> Function(String command, List<String> arguments) start =
      (command, arguments) async {
    await Process.start(command, arguments, mode: ProcessStartMode.detached);
  };

  /// WAV'ların yazılacağı klasör. Testler değiştirir.
  @visibleForTesting
  static Future<Directory> Function() directory = () async {
    final temp = await getTemporaryDirectory();
    return Directory('${temp.path}${Platform.pathSeparator}chess-library-sounds');
  };

  Future<void>? _ready;
  String? _player;
  final Map<String, String> _files = {};

  /// Bulunan oynatıcı komutu (`null`: henüz aranmadı ya da yok).
  String? get player => _player;

  /// Oynatıcı arandı ve hiçbiri bulunamadı.
  bool get unavailable => _checked && _player == null;
  bool _checked = false;

  /// Oynatıcıyı arar ve sesleri hazırlar; ikinci çağrı ilkini bekler.
  Future<void> init(List<String> names) => _ready ??= _prepare(names);

  Future<void> _prepare(List<String> names) async {
    for (final candidate in players) {
      if (await commandExists(candidate)) {
        _player = candidate;
        break;
      }
    }
    _checked = true;
    if (_player == null) return;
    try {
      final dir = await directory();
      await dir.create(recursive: true);
      for (final name in names) {
        final data = await rootBundle.load('assets/sounds/wav/$name.wav');
        final bytes =
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        final file = File('${dir.path}${Platform.pathSeparator}$name.wav');
        if (!await file.exists() || await file.length() != bytes.length) {
          await file.writeAsBytes(bytes, flush: true);
        }
        _files[name] = file.path;
      }
    } catch (_) {
      // Yazılamayan ses çalmıyor; diğerleri çalıyor.
    }
  }

  /// [name] sesini çalar; hazırlık bitmediyse bekler.
  Future<void> play(String name, List<String> names) async {
    await init(names);
    final player = _player;
    final path = _files[name];
    if (player == null || path == null) return;
    try {
      await start(player, [if (player == 'aplay') '-q', path]);
    } catch (_) {
      // Oynatma hatası oyun akışını bölmemeli.
    }
  }

  @visibleForTesting
  void reset() {
    _ready = null;
    _player = null;
    _checked = false;
    _files.clear();
  }
}
