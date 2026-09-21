import 'dart:async';

import 'package:wakelock_plus/wakelock_plus.dart';

/// Ekranın kendiliğinden kapanmasını geçici olarak engeller.
///
/// Bulmaca çözerken ya da tahta başında düşünürken ekrana dokunulmadığı
/// için telefon ekranı sönüyordu; on dakikadan uzun düşünmek olağan.
///
/// Sınır neden var: "hep açık" bırakmak, uygulamayı açık unutan
/// kullanıcının pilini bitirir. Sayaç **her hamlede sıfırlanıyor**, yani
/// süre "hareketsiz geçen zaman". Oynamaya devam ettiğin sürece ekran
/// açık kalır; masada unutulursa yarım saat sonra normale döner.
///
/// Eklentiyi çağırmak testlerde mümkün olmadığı için ([setter] ile)
/// dışarıdan verilebiliyor.
class ScreenAwake {
  ScreenAwake({
    this.limit = const Duration(minutes: 30),
    void Function(bool keepOn)? setter,
  }) : _setter = setter ?? _platform;

  final Duration limit;
  final void Function(bool keepOn) _setter;

  Timer? _timer;
  bool _on = false;

  /// Şu an ekran açık tutuluyor mu?
  bool get isOn => _on;

  /// Ekranı açık tut ve süreyi baştan başlat.
  void keep() {
    _timer?.cancel();
    _timer = Timer(limit, release);
    if (_on) return;
    _on = true;
    _setter(true);
  }

  /// Bırak: ekran normal davranışına döner. Çift çağrı zararsız.
  void release() {
    _timer?.cancel();
    _timer = null;
    if (!_on) return;
    _on = false;
    _setter(false);
  }

  static void _platform(bool keepOn) {
    // Eklenti olmayan ortamda (test, desteklenmeyen platform) sessizce geç.
    final work = keepOn ? WakelockPlus.enable() : WakelockPlus.disable();
    work.catchError((Object _) {});
  }
}
