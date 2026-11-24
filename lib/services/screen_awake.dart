import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
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

  /// Ekranı şu an açık tutan örnek sayısı.
  ///
  /// Kilit telefonda tek ve ortak; eklenti saymıyor. İki ekran üst üste
  /// bindiğinde (listede sonraki oyuna geçiş: yeni ekran kurulur, eskisi
  /// aynı karenin sonunda kapanır; bulmacadan açılan analiz tahtasından
  /// geri dönüş) kapanan ekranın bırakması kilidi ötekinin elinden de
  /// alıyordu: ikinci oyundan itibaren telefon izlerken uyuyordu, öteki
  /// ekran ise kilidi hâlâ tuttuğunu sanıp yeniden istemiyordu. Kilit artık
  /// son tutan bırakınca kapanıyor.
  static int _holders = 0;

  /// Testler için: eklentinin yerine geçer.
  @visibleForTesting
  static void Function(bool keepOn)? debugPlatform;

  static void _platform(bool keepOn) {
    if (keepOn) {
      _holders++;
      if (_holders > 1) return;
    } else {
      if (_holders > 0) _holders--;
      if (_holders > 0) return;
    }
    final override = debugPlatform;
    if (override != null) {
      override(keepOn);
      return;
    }
    // Eklenti olmayan ortamda (test, desteklenmeyen platform) sessizce geç.
    final work = keepOn ? WakelockPlus.enable() : WakelockPlus.disable();
    work.catchError((Object _) {});
  }
}
