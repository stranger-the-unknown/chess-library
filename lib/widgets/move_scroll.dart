import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Yatay hamle şeridini seçili hamlede tutar.
///
/// Uygulamada iki ayrı hamle şeridi var — tahtanın altındaki [MoveList] ve
/// açılış çalışma ekranındaki şerit — ve ikisi de aynı iki hatayı
/// taşıyordu:
///
/// * **Sona git.** `ListView.builder` yalnızca görünen aralığı kurar.
///   Uzaktaki hamlenin `GlobalKey`'i boş olduğu için
///   `Scrollable.ensureVisible` çağıracak bir bağlam bulamıyor ve şerit
///   yerinde kalıyordu. Çözüm: önce oransal bir tahminle oraya atlamak,
///   sonraki karede hedef kurulmuş oluyor ve ortalama tam yapılıyor.
/// * **Başa dön.** İmleç -1 oluyor, yani gösterilecek bir hamle yok; şerit
///   de oyunun ortasında asılı kalıyordu. Artık başa dönüyor.
///
/// Kural tek yerde dursun diye ayrı bir sınıf: şeritlerden birinde
/// düzeltip diğerini unutmak, hatanın ilk hâlinin tekrarı olurdu.
class MoveScroller {
  final ScrollController controller = ScrollController();
  final Map<int, GlobalKey> _keys = {};

  /// En son takip edilen hamle; aynı hamle için iş tekrarlanmasın diye.
  ///
  /// Şerit her çizimde takip isteyebilir; bu olmadan kullanıcının elle
  /// yaptığı kaydırma her karede geri alınırdı.
  int? _followed;

  static const Duration _duration = Duration(milliseconds: 220);
  static const int _maxTries = 16;
  static const Curve _curve = Curves.easeOut;

  /// Hamlenin çizildiği kutuya verilecek anahtar.
  GlobalKey keyFor(int index) => _keys.putIfAbsent(index, GlobalKey.new);

  /// Şerit ekrandan kalktı mı?
  ///
  /// Kare sonu işleri bir kare sonra çalışıyor; o arada şerit
  /// atılabiliyor (pencere dar↔geniş yerleşim arasında geçince olur).
  /// Atılmış bir denetleyiciye dokunmak hata veriyordu.
  bool _disposed = false;

  void dispose() {
    _disposed = true;
    controller.dispose();
  }

  /// [index] numaralı hamleyi görünür kılar.
  ///
  /// [rowCount] şeritteki satır (hamle çifti) sayısı, [rowOf] bir hamlenin
  /// hangi satıra düştüğü. Konum tahmini bunlardan çıkıyor.
  void follow({
    required int index,
    required int rowCount,
    int Function(int index)? rowOf,
  }) {
    if (_followed == index) return;
    _followed = index;
    _step(index, rowCount, rowOf ?? (i) => i ~/ 2, 0);
  }

  /// Hedefe yaklaşma denemesi; her deneme bir kare sürüyor.
  ///
  /// `ListView.builder` görmediği satırların genişliğini gördüklerinin
  /// ortalamasından tahmin eder. Açılışta satırlar kısa ("e4"), sonunda
  /// uzun ("Raxf7+") olduğu için baştan sona atlarken tahmin edilen son,
  /// gerçek sondan kısa kalıyor: tek atlayış şeridi ortalarda bırakıyordu.
  /// Her atlayış yeni satırlar kurduruyor, tahmin de düzeliyor; hedef
  /// kurulana kadar tekrarlanıyor.
  void _step(int index, int rowCount, int Function(int index) rowOf, int tries) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || !controller.hasClients) return;
      // Bu arada başka bir hamle istendiyse eski hedefin peşine düşme.
      if (_followed != index) return;
      final position = controller.position;

      if (index < 0) {
        // Uzaktan animasyonla dönmek aradaki her satırı kurdurur; uzun
        // oyunlarda şerit takılıyor, hatta yerinden kıpırdamıyor gibi
        // görünüyordu. Yakınsa kayarak, uzaksa atlayarak dönüyor.
        final distance = position.pixels - position.minScrollExtent;
        if (distance > position.viewportDimension * 3) {
          controller.jumpTo(position.minScrollExtent);
        } else {
          controller.animateTo(
            position.minScrollExtent,
            duration: _duration,
            curve: _curve,
          );
        }
        return;
      }

      if (_ensureVisible(index)) return;
      if (tries >= _maxTries) return;

      final target = _estimate(position, index, rowCount, rowOf);
      // Tahmin olduğu yeri gösteriyorsa ilerleme yok; döngüyü kes.
      if ((target - position.pixels).abs() < 0.5) return;
      controller.jumpTo(target);
      _step(index, rowCount, rowOf, tries + 1);
    });
  }

  /// Şerit yeniden kurulduğunda takibi sıfırlar.
  void reset() => _followed = null;

  bool _ensureVisible(int index) {
    final target = _keys[index]?.currentContext;
    if (target == null) return false;
    Scrollable.ensureVisible(
      target,
      alignment: 0.5,
      duration: _duration,
      curve: _curve,
    );
    return true;
  }

  /// Hamle sırasına göre oransal konum.
  ///
  /// Satır genişlikleri hamle metnine göre değiştiği için bu bir tahmin;
  /// amacı hedefi kurdurmak, ortalamayı sonraki kare yapıyor. Sona
  /// gitmekte tahmin zaten kesin: son satır en sonda.
  double _estimate(
    ScrollPosition position,
    int index,
    int rowCount,
    int Function(int index) rowOf,
  ) {
    final last = math.max(1, rowCount - 1);
    final ratio = (rowOf(index) / last).clamp(0.0, 1.0);
    return position.minScrollExtent +
        (position.maxScrollExtent - position.minScrollExtent) * ratio;
  }
}
