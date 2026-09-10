import 'package:flutter/material.dart';

import '../services/settings_service.dart';

/// Bir tahtanın zeminini çizer.
///
/// Düz renkli tahtaların görsel dosyası yoktur; kareler doğrudan tuvale
/// çizilir. Böylece her ölçüde kusursuz keskin çıkarlar (ölçekleme
/// bulanıklığı ya da sıkıştırma izi olmaz) ve hiç yer kaplamazlar.
/// Ahşap görünümlü tahtalar ise bir görselden gelir.
///
/// Hem oyun tahtası hem ayarlardaki önizleme bunu kullanır; ikisinin
/// ayrışıp birinin boş kalması böylece mümkün olmaz.
class BoardBackground extends StatelessWidget {
  final String board;

  /// Görselden gelen tahtalarda kullanılacak kutu doldurma biçimi.
  final BoxFit fit;

  const BoardBackground({
    super.key,
    required this.board,
    this.fit = BoxFit.fill,
  });

  @override
  Widget build(BuildContext context) {
    final (light, dark) = BoardAssets.squareColors(board);
    final painter = CheckerPainter(Color(light), Color(dark));

    if (BoardAssets.isFlat(board)) {
      return CustomPaint(painter: painter, size: Size.infinite);
    }
    return Image.asset(
      BoardAssets.boardPath(board),
      fit: fit,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stack) =>
          CustomPaint(painter: painter, size: Size.infinite),
    );
  }
}

/// İki renkli 8x8 kare deseni.
class CheckerPainter extends CustomPainter {
  final Color light;
  final Color dark;

  const CheckerPainter(this.light, this.dark);

  @override
  void paint(Canvas canvas, Size size) {
    // Genişlik ve yükseklik ayrı hesaplanır: tahtanın kendisi karedir ama
    // ayarlardaki önizleme kutusu kare olmayabilir; tek bir kenardan
    // hesaplanırsa altta boyanmamış bir şerit kalıyordu.
    final cellW = size.width / 8;
    final cellH = size.height / 8;
    final paint = Paint();
    for (int row = 0; row < 8; row++) {
      for (int col = 0; col < 8; col++) {
        paint.color = (row + col) % 2 == 0 ? light : dark;
        canvas.drawRect(
          // Bitişik kareler arasında saç teli boşluk kalmasın diye
          // kenarlar bir sonraki hücrenin başlangıcına kadar uzatılır.
          Rect.fromLTRB(
            col * cellW,
            row * cellH,
            (col + 1) * cellW,
            (row + 1) * cellH,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CheckerPainter oldDelegate) =>
      oldDelegate.light != light || oldDelegate.dark != dark;
}
