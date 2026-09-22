import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

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

  /// Ayarların bir kısmı yalnızca masaüstünde anlamlı.
  ///
  /// Telefonda ve tablette tahta boyutu sorulmuyor: pencere yeniden
  /// boyutlandırılamadığı için "sığanın tamamı"ndan başka doğru cevap
  /// yok. Çalışmayan bir ayar, olmayan ayardan kötüdür.
  static bool get isDesktop =>
      debugDesktopOverride ??
      (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS));

  /// Testlerde cihaz sınıfını zorlamak için.
  @visibleForTesting
  static bool? debugDesktopOverride;

  /// Masaüstünde yazıların büyütülme oranı.
  ///
  /// Uygulamadaki punto değerleri telefona göre seçilmişti (101 yerin
  /// 73'ü 13 punto ve altı). Aynı değerler bir bilgisayar ekranında,
  /// göze uzak mesafede küçük kalıyor. Tek tek büyütmek yerine tek
  /// ölçek: Android'e hiç dokunulmuyor, masaüstünde her yazı aynı
  /// oranda büyüyor.
  ///
  /// Oran bilerek ölçülü (%15): daha fazlası sabit yükseklikli
  /// şeritleri (motor satırı, hamle şeridi, geri bildirim kartı)
  /// taşırırdı.
  static const double desktopTextScale = 1.15;

  /// Yan yerleşimde grubun pencere kenarlarına bırakacağı pay
  /// (üstte ve altta ayrı ayrı).
  ///
  /// Olmadan grup pencereyi tam dolduruyordu: en büyük tahtada alttaki
  /// oyuncu adı ekranın en dibine yapışıyor, bulmaca ve açılış
  /// ekranlarında tahtanın altında hiç boşluk kalmıyordu.
  static const double wideOuterMargin = 16;

  /// Tahta ile yan panel arasındaki boşluk.
  ///
  /// Tahtanın oranı: küçük tahtada küçük, büyük tahtada büyük kalsın.
  /// Eskiden 8 pikseldi ve panel tahtaya yapışık duruyordu.
  ///
  /// Tahtanın kendi 8 piksellik dolgusu da araya ekleniyor; toplam,
  /// örnek alınan düzendeki oranla (tahta genişliğinin ~%5,8'i) aynı
  /// yere geliyor.
  static double panelGap(double boardSide) =>
      (boardSide * 0.045).clamp(14.0, 38.0);

  /// Tahtanın boyuna göre motor satırının punto değeri.
  ///
  /// Alt sınır bugünkü değerin üstünde: yazı zaten küçüktü. Üst sınır
  /// da var, çünkü şerit sabit yükseklikli ve telefonda tahta ekranı
  /// doldurduğu için ölçek yukarı kaçabilirdi.
  static double engineFontSize(double? boardSide) =>
      boardSide == null ? 14.0 : (boardSide / 640 * 14.0).clamp(13.0, 17.0);

  /// Dar yerleşimde tahtanın üst sınırı.
  ///
  /// Masaüstünde dar pencere bir **tercih**, telefonun ve küçük
  /// tabletin ölçüsü ise **veri**: orada tahta sığdığının tamamı kadar
  /// olmalı. Telefon için seçilmiş 520'lik tavan, 7" bir tablette
  /// (600 piksel genişlik) ekranın sekizde birini boşa harcıyordu.
  static double get narrowBoardCap =>
      isDesktop ? maxBoardSide : maxWideBoardSide;

  /// Bu ekran, yan yana yerleşimi taşıyabilecek bir tablet mi?
  ///
  /// Ölçüt iki parçalı: kısa kenar en az 600 (Material'ın tablet tanımı)
  /// **ve** uzun kenar en az [twoColumnBreakpoint]. İkincisi şart, çünkü
  /// yatay çevirmenin tek sebebi yan paneli açabilmek. Sığmayacaksa
  /// çevirmek tahtayı küçültmekten başka işe yaramaz: 7" bir tablette
  /// (600x960) dikeyde ~600 piksel olan tahta, yatayda alt şeride
  /// düşerek ~310'a inerdi.
  static bool isTabletScreen(Size logical) {
    final shortest = math.min(logical.width, logical.height);
    final longest = math.max(logical.width, logical.height);
    return shortest >= 600 && longest >= twoColumnBreakpoint;
  }

  /// İki sütunlu yerleşim için gereken en küçük genişlik.
  ///
  /// Makul bir tahta (~610) + hamle sütunu (340) + boşluklar. Bunun
  /// altında boyut ayarı da gösterilmiyor: çalışmayan bir ayar, olmayan
  /// ayardan kötüdür.
  ///
  /// 1100'den 1000'e indi. Sebebi 4:3 tabletler: 9.7" bir cihazın
  /// (768x1024) yatay genişliği 1024 ve eski eşiğin altında kalıyordu,
  /// yani cihaz "telefon" sayılıp dikey kilitleniyordu. Orada tahta
  /// genişliğin %93'ünü kaplıyor, altına her şey sıkışıyordu. Yatayda
  /// tahta 634 oluyor ve yanına panel geliyor — yüksekliğin ~%83'ü,
  /// yani diğer tabletlerle aynı oran.
  ///
  /// 1000 eşiği 7" tabletleri (uzun kenar 960) dışarıda bırakmaya
  /// devam ediyor; orada yatay tahtayı 584'ten 530'a düşürürdü.
  static const double twoColumnBreakpoint = 1000;

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
