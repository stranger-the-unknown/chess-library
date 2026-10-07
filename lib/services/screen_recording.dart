import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/services.dart';

/// "Ekran kaydı al"ın hazırlığının sonucu.
enum RecordStart {
  /// Hazır: [ScreenRecording.begin] kaydı başlatır.
  ok,

  /// Kullanıcı Android'in onay penceresinde vazgeçti; söylenecek bir şey
  /// yok.
  cancelled,

  /// Bu sistemde yapılamıyor; sebep [ScreenRecording.lastError] içinde.
  unsupported,

  /// Başka bir hata; metni [ScreenRecording.lastError] içinde.
  failed,
}

/// Uygulamanın kendi aldığı ekran kaydı (10.10.0).
///
/// Instagram'a ekran kaydıyla paylaşılan oyunlarda başta kaydı başlatıp
/// oynatmaya basmak, sonda kaydı zamanında durdurmak ve fazlasını kırpmak
/// gerekiyordu. Bunu uygulama yapıyor; akış [RecordingSession] içinde.
///
/// * Android (10+): ekran yansıtma; ses izi kayıt sürerken çalınan hamle
///   seslerinden üretiliyor (10.10.1), MP4, Filmler/Chess Library
///   (`Mp4Writer.kt`, `RecordService.kt`).
/// * Linux (X11): uygulamanın penceresi + bilgisayarın ses çıkışı,
///   GStreamer ile MP4, Videolar/Chess Library ([LinuxScreenRecorder]).
class ScreenRecording {
  ScreenRecording._();
  static ScreenRecording instance = ScreenRecording._();

  /// Bu platformda menüde gösterilsin mi? (Gerekenler eksikse seçenek
  /// yine görünür ve basınca neyin eksik olduğunu söyler.)
  static bool get platformSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isLinux);

  static const MethodChannel channel = MethodChannel('chess_library/record');

  /// Testler değiştirebilir.
  @visibleForTesting
  static LinuxScreenRecorder linux = LinuxScreenRecorder();

  /// Son hatanın metni ([RecordStart.unsupported], [RecordStart.failed]).
  String? lastError;

  /// Kayıt dışarıdan bittiğinde (Android'de bildirim ya da sistemin durdurma
  /// düğmesi, Linux'ta GStreamer'ın kapanması): kaydedilen yol ya da null.
  void Function(String? saved)? onStoppedOutside;

  bool _channelReady = false;

  void _listen() {
    if (_channelReady) return;
    _channelReady = true;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'stopped') {
        onStoppedOutside?.call(call.arguments as String?);
      }
      return null;
    });
  }

  /// İzinler ve (Android'de) onay penceresi.
  Future<RecordStart> prepare() async {
    lastError = null;
    if (!kIsWeb && Platform.isLinux) {
      final error = await linux.prepare();
      if (error == null) return RecordStart.ok;
      lastError = error;
      return RecordStart.unsupported;
    }
    _listen();
    try {
      final result = await channel.invokeMethod<String>('prepare');
      switch (result) {
        case 'ok':
          return RecordStart.ok;
        case 'cancelled':
          return RecordStart.cancelled;
        case 'unsupported':
          return RecordStart.unsupported;
        default:
          lastError = result;
          return RecordStart.failed;
      }
    } catch (error) {
      lastError = '$error';
      return RecordStart.failed;
    }
  }

  /// Kaydı başlatır; hata metni ya da null.
  Future<String?> begin(String name) async {
    if (!kIsWeb && Platform.isLinux) {
      return linux.begin(name, onExit: (saved) => onStoppedOutside?.call(saved));
    }
    try {
      return await channel.invokeMethod<String>('begin', {'name': name});
    } catch (error) {
      return '$error';
    }
  }

  /// Kaydı bitirir; kaydedilen yol (gösterilecek biçimde) ya da null.
  /// Hazırlanıp başlatılmamış bir kaydı da kapatır.
  Future<String?> stop() async {
    if (!kIsWeb && Platform.isLinux) return linux.stop();
    try {
      return await channel.invokeMethod<String>('stop');
    } catch (_) {
      return null;
    }
  }
}

/// Linux'ta ekran kaydı: GStreamer (`gst-launch-1.0`) uygulamanın
/// penceresini (`ximagesrc`) ve bilgisayarın ses çıkışını (`pulsesrc`,
/// varsayılan çıkışın "monitor"u) MP4'e yazıyor.
///
/// Ses, bilgisayarın **genel** çıkışından alınıyor: kayıt sırasında başka
/// bir yerde çalan ses de videoya girer. Gerekenler eksikse kayıt
/// başlamıyor ve neyin eksik olduğu söyleniyor (sessizce geçilmiyor).
class LinuxScreenRecorder {
  /// Gereken GStreamer parçaları; AAC için ikisinden biri yeter.
  static const List<String> elements = [
    'ximagesrc',
    'pulsesrc',
    'videoconvert',
    'videoscale',
    'x264enc',
    'h264parse',
    'aacparse',
    'mp4mux',
  ];
  static const List<String> aacEncoders = ['avenc_aac', 'voaacenc'];

  /// Komut çalıştırır (çıktı, çıkış kodu). Testler değiştirir.
  Future<ProcessResult> Function(String command, List<String> arguments) run =
      (command, arguments) => Process.run(command, arguments);

  /// Kaydı yapan süreci başlatır. Testler değiştirir.
  Future<Process> Function(String command, List<String> arguments) start =
      // İletiler dilden bağımsız olsun ("PLAYING" beklenen sözcük).
      (command, arguments) =>
          Process.start(command, arguments, environment: {'LC_ALL': 'C'});

  /// Uygulama penceresinin X11 kimliği ve piksel boyutu; X11 değilse null.
  Future<Map<String, int>?> Function() captureTarget = () async {
    final value = await const MethodChannel('chess_library/window')
        .invokeMapMethod<String, int>('captureTarget');
    return value;
  };

  Map<String, int>? _target;
  String? _sink;
  String? _aac;
  Process? _process;
  String? _path;
  String? _shown;
  bool _stopping = false;

  /// Hazırlık; olmazsa sebebin metni.
  Future<String?> prepare() async {
    final missing = <String>[];
    for (final element in elements) {
      if (!await _has(element)) missing.add(element);
    }
    _aac = null;
    for (final encoder in aacEncoders) {
      if (await _has(encoder)) {
        _aac = encoder;
        break;
      }
    }
    if (_aac == null) missing.add(aacEncoders.join(' / '));
    if (missing.isNotEmpty) {
      return 'GStreamer: ${missing.join(', ')}';
    }
    try {
      _target = await captureTarget();
    } catch (error) {
      return '$error';
    }
    if (_target == null) return 'x11';
    try {
      final sink = await run('pactl', ['get-default-sink']);
      _sink = (sink.stdout as String).trim();
    } catch (_) {
      _sink = null;
    }
    if (_sink == null || _sink!.isEmpty) return 'pactl';
    return null;
  }

  Future<bool> _has(String element) async {
    try {
      final result = await run('gst-inspect-1.0', [element]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Videoların klasörü: `xdg-user-dir VIDEOS` (Türkçe sistemde
  /// "Videolar"), içinde "Chess Library".
  Future<Directory> _folder() async {
    var base = '';
    try {
      final result = await run('xdg-user-dir', ['VIDEOS']);
      base = (result.stdout as String).trim();
    } catch (_) {}
    final home = Platform.environment['HOME'] ?? '';
    if (base.isEmpty || base == home) base = '$home/Videos';
    final folder = Directory('$base/Chess Library');
    await folder.create(recursive: true);
    return folder;
  }

  /// Kaydı başlatır; hata metni ya da null. [onExit]: süreç kendiliğinden
  /// kapanırsa (ör. pencere boyutu değişti) kaydedilen yol.
  Future<String?> begin(String name, {void Function(String?)? onExit}) async {
    final target = _target;
    final sink = _sink;
    final aac = _aac;
    if (target == null || sink == null || aac == null) return 'hazır değil';
    final folder = await _folder();
    final path = '${folder.path}/$name.mp4';
    _path = path;
    final home = Platform.environment['HOME'] ?? '';
    _shown = home.isNotEmpty && path.startsWith('$home/')
        ? path.substring(home.length + 1)
        : path;
    // x264 çift kenar istiyor.
    final width = (target['width']! ~/ 2) * 2;
    final height = (target['height']! ~/ 2) * 2;
    final arguments = <String>[
      '-e',
      'ximagesrc', 'xid=${target['xid']}', 'use-damage=false',
      'show-pointer=false',
      '!', 'video/x-raw,framerate=30/1',
      '!', 'videoconvert', '!', 'videoscale',
      '!', 'video/x-raw,format=I420,width=$width,height=$height',
      '!', 'x264enc', 'speed-preset=veryfast', 'tune=zerolatency',
      'bitrate=6000', 'key-int-max=60',
      '!', 'h264parse', '!', 'queue', '!', 'mp4mux', 'name=mux',
      '!', 'filesink', 'location=$path',
      'pulsesrc', 'device=$sink.monitor',
      '!', 'audioconvert', '!', 'audioresample',
      '!', 'audio/x-raw,rate=44100,channels=2',
      '!', aac, '!', 'aacparse', '!', 'queue', '!', 'mux.',
    ];
    final Process process;
    try {
      process = await start('gst-launch-1.0', arguments);
    } catch (error) {
      return '$error';
    }
    _process = process;
    _stopping = false;
    // Boru hattı çalışmaya başlayınca "PLAYING" yazıyor; hata olursa
    // süreç hemen kapanıyor.
    final playing = Completer<String?>();
    final errors = StringBuffer();
    process.stdout.transform(utf8.decoder).listen((text) {
      if (text.contains('PLAYING') && !playing.isCompleted) {
        playing.complete(null);
      }
    });
    process.stderr.transform(utf8.decoder).listen(errors.write);
    unawaited(process.exitCode.then((code) {
      if (!playing.isCompleted) {
        playing.complete(errors.isEmpty ? 'gst-launch-1.0: $code' : '$errors');
        return;
      }
      if (!_stopping) {
        _process = null;
        onExit?.call(_finished());
      }
    }));
    final error = await playing.future
        .timeout(const Duration(seconds: 10), onTimeout: () => 'zaman aşımı');
    if (error != null) {
      _process?.kill();
      _process = null;
      return error;
    }
    return null;
  }

  /// Kaydı bitirir (GStreamer'a kesme sinyali: `-e` sayesinde dosya
  /// düzgün kapanıyor); kaydedilen yol ya da null.
  Future<String?> stop() async {
    final process = _process;
    _process = null;
    if (process == null) return null;
    _stopping = true;
    process.kill(ProcessSignal.sigint);
    try {
      await process.exitCode.timeout(const Duration(seconds: 15));
    } on TimeoutException {
      process.kill();
      return null;
    }
    return _finished();
  }

  String? _finished() {
    final path = _path;
    if (path == null) return null;
    final file = File(path);
    if (!file.existsSync() || file.lengthSync() == 0) return null;
    return _shown;
  }
}
