import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

/// Android'de hamle sesleri: Android'in SoundPool'u (`GameSounds.kt`).
///
/// 10.9.0'a kadar her ses ayrı bir just_audio oynatıcısıyla, her çalışta
/// başa sarılıp yeniden başlatılarak çalıyordu; ekran kaydı alınırken bazı
/// hamlelerde kayıtta cızırtı oluyordu (aynı kayıtla YouTube'un sesi
/// temizdi). SoundPool sesleri açılışta bir kez çözüp bellekte tutuyor.
///
/// Sesler WAV kopyalarından yükleniyor (`assets/sounds/wav/`, Linux da
/// onları kullanıyor): MP3 çözme işi de kalkıyor.
///
/// Yüklenemeyen ses **sessizce** geçmiyor: ayarlarda ses seçeneğinin
/// altında hangi seslerin yüklenemediği yazıyor ([failure]).
class AndroidSound {
  static final AndroidSound instance = AndroidSound._();
  AndroidSound._();

  static const MethodChannel channel = MethodChannel('chess_library/sound');

  Future<void>? _ready;

  /// Yüklenemeyen seslerin listesi ya da kanalın hatası; yoksa null.
  String? failure;

  bool get unavailable => failure != null;

  /// Testler için: yüklemeyi ve hatayı unutur.
  @visibleForTesting
  void reset() {
    _ready = null;
    failure = null;
  }

  /// Sesleri bir kez yükler; ikinci çağrı ilkini bekler.
  Future<void> init(List<String> names) => _ready ??= _load(names);

  Future<void> _load(List<String> names) async {
    try {
      final missing = await channel.invokeListMethod<String>('load', {
        'sounds': {for (final name in names) name: 'assets/sounds/wav/$name.wav'},
      });
      if (missing != null && missing.isNotEmpty) failure = missing.join(', ');
    } catch (error) {
      failure = '$error';
    }
  }

  Future<void> play(String name, List<String> names) async {
    await init(names);
    try {
      final played = await channel.invokeMethod<bool>('play', {'name': name});
      // Çözülemeyen ses yükleme bittikten sonra anlaşılıyor; ayarlarda
      // görünsün diye listeyi tazele.
      if (played == false) await _refreshFailures();
    } catch (error) {
      failure = '$error';
    }
  }

  Future<void> _refreshFailures() async {
    final failed = await channel.invokeListMethod<String>('failures');
    if (failed != null && failed.isNotEmpty) failure = failed.join(', ');
  }
}
