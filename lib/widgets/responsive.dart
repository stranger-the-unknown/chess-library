import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Ekran genişliğine göre yerleşim kararları.
///
/// Uygulama hem telefonda hem masaüstünde çalışır. Telefonda her şey ekranı
/// doldurur; geniş bir pencerede ise tahtanın ve metin sütunlarının
/// sınırsız büyümesi hem çirkin hem kullanışsızdır. Bu sınırlar tek yerden
/// yönetilsin diye burada toplanmıştır.
class Layout {
  Layout._();

  /// Bu genişlikten itibaren masaüstü yerleşimi (yan gezinme çubuğu).
  static const double wideBreakpoint = 900;

  /// Tahtanın alabileceği en büyük kenar uzunluğu (dar yerleşim).
  static const double maxBoardSide = 520;

  /// Tahtanın ulaşabileceği en büyük kenar.
  ///
  /// Çok geniş/yüksek pencerede tahta sonsuza kadar büyümesin diye tavan.
  static const double maxWideBoardSide = 760;

  /// Tahta boyutu seçenekleri: Küçük / Orta / Büyük.
  ///
  /// **Mutlak piksel değil, sığabilecek en büyük tahtanın oranı.**
  ///
  /// Önce 520/640/760 yazılmıştı ve yanlıştı: tahtayı sınırlayan şey
  /// genişlik değil **yükseklik**. 1920x1080 panelde %125 ölçekle gövde
  /// 816 mantıksal piksel kalıyor, tahtaya kalan ise 690. Yani "Büyük"
  /// hiçbir zaman 760'a ulaşmıyor, Orta ile arası 50 pikselde (%8)
  /// kalıyor ve seçim gözle ayırt edilmiyordu.
  ///
  /// Oranlar eşit aralıklı: hangi ekranda olursa olsun üç kademe
  /// birbirinden görünür şekilde ayrılıyor. "Büyük" her zaman sığanın
  /// tamamı.
  static const List<double> boardScales = [0.75, 0.875, 1.0];

  /// İki sütunlu oyun yerleşimi için gereken en küçük genişlik.
  ///
  /// Tahta (en çok 640) + hamle sütunu (340) + boşluklar. Bunun altında
  /// yerleşim seçeneği gösterilmiyor: çalışmayan bir ayar, olmayan
  /// ayardan kötüdür.
  static const double twoColumnBreakpoint = 1100;

  /// Yan sütunun genişliği (hamle listesi, motor satırı, düğmeler).
  static const double sidePanelWidth = 340;

  /// Liste ve form içeriğinin en fazla genişliği.
  static const double maxContentWidth = 760;

  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= wideBreakpoint;

  /// Pencere iki sütunlu oyun yerleşimini taşıyabiliyor mu?
  static bool isTwoColumn(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= twoColumnBreakpoint;

  /// Verilen alana sığan, üst sınırı aşmayan tahta kenarı.
  ///
  /// [cap] verilmezse dar yerleşimin sınırı ([maxBoardSide]) kullanılır.
  static double boardSide(double available, [double? secondAxis, double? cap]) {
    var side = available;
    if (secondAxis != null) side = math.min(side, secondAxis);
    return math.max(0, math.min(side, cap ?? maxBoardSide));
  }
}

/// İçeriği geniş pencerelerde ortalar ve genişliğini sınırlar.
///
/// Kaydırılabilir gövdelerde de güvenle kullanılabilir: kaydırma davranışı
/// değişmez, yalnızca içerik ortalanır.
class ContentWidth extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const ContentWidth({
    super.key,
    required this.child,
    this.maxWidth = Layout.maxContentWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      // heightFactor olmadan Align dikeyde eldeki tüm alanı kaplar. Bu,
      // gövdede sorun çıkarmaz ama `bottomNavigationBar` gibi yüksekliği
      // içeriğinden gelen yerlerde çubuğun ekranı doldurmasına yol açar.
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// Kaydırma alanını daraltmadan içeriği ortalayan liste dolgusu.
///
/// [ContentWidth] kaydırılabilir gövdelerde yanlış araçtır: listeyi
/// daraltınca kaydırma alanı da daralıyor, listenin yanında kalan boşluk
/// da kaydırmaya cevap vermiyor. Masaüstünde imleç pencerenin kenarına
/// yakınken fare tekerleği hiçbir şey yapmıyordu — sayfa kıpırdamıyordu.
///
/// Burada liste tüm genişliği kaplıyor; ortalama, listenin **kendi**
/// dolgusuyla yapılıyor. Görüntü aynı, kaydırma alanı ise pencere kadar
/// geniş.
///
/// Genişlik [MediaQuery] yerine [LayoutBuilder] ile ölçülüyor: geniş
/// pencerede solda bir gezinme çubuğu var ve pencere genişliği listeye
/// kalan genişlikten fazla.
class ContentInset extends StatelessWidget {
  /// Listenin dar pencerede kullanacağı dolgu.
  final EdgeInsets padding;

  final double maxWidth;

  /// Hesaplanmış dolguyla listeyi kurar.
  final Widget Function(BuildContext context, EdgeInsets padding) builder;

  const ContentInset({
    super.key,
    required this.padding,
    required this.builder,
    this.maxWidth = Layout.maxContentWidth,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final extra = math.max(0.0, (constraints.maxWidth - maxWidth) / 2);
        return builder(
          context,
          padding.copyWith(
            left: padding.left + extra,
            right: padding.right + extra,
          ),
        );
      },
    );
  }
}

/// Tahtayı ortalayıp en fazla [Layout.maxBoardSide] kadar büyütür.
///
/// [builder] kenar uzunluğunu alır; tahta widget'ını o ölçüde kurar.
class BoardArea extends StatelessWidget {
  final Widget Function(BuildContext context, double side) builder;

  /// Tahtanın yanında yer kaplayan öğeler (ör. değerlendirme çubuğu).
  final double reservedWidth;

  final EdgeInsets padding;

  const BoardArea({
    super.key,
    required this.builder,
    this.reservedWidth = 0,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: padding,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side = Layout.boardSide(
              constraints.maxWidth - reservedWidth,
              constraints.maxHeight,
            );
            return builder(context, side);
          },
        ),
      ),
    );
  }
}
