import 'package:flutter/material.dart';

import '../theme/app_look.dart';

/// Uygulamanın logosu: görünümün zemin geçişi üstünde at (♞).
///
/// Ana menüdeki logo ve görünüm seçme penceresindeki örnekler bunu
/// kullanıyor; uygulama simgeleri de aynı düzenle üretiliyor
/// (`tools/make_look_icons.py`). Ölçüler 54 piksellik logodan oranlanıyor.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, required this.look, this.size = 54});

  final AppLook look;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scale = size / 54;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16 * scale),
        gradient: look.iconGradient,
      ),
      alignment: Alignment.center,
      // Yazı tipi açıkça veriliyor: sistem yazı tipine bırakılınca at
      // Android'de ve Windows'ta farklı çiziliyordu. Noto'nun ♞ glifi satır
      // kutusunda yukarıda duruyor; kareye tam ortalamak için ölçülen kadar
      // (54 pikselde 5) aşağı alınıyor.
      child: Transform.translate(
        offset: Offset(0, 5 * scale),
        child: Text(
          '♞',
          // Logo bir resim: sistemin yazı büyütmesi atı büyütmesin.
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontFamily: 'NotoSansSymbols2',
            fontSize: 30 * scale,
            color: look.knight,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}
