import 'package:flutter/material.dart';

import '../models/chess_engine.dart' as engine;
import 'piece_widget.dart';

/// Bulmaca listelerinde kullanılan küçük, etkileşimsiz tahta önizlemesi.
///
/// Liste binlerce satır olabildiği için burada tahta görseli yerine iki
/// renkli kareler çizilir; bu, kaydırmayı belirgin biçimde hızlandırır.
class MiniBoard extends StatelessWidget {
  final String fen;
  final double size;
  final bool flipped;

  const MiniBoard({
    super.key,
    required this.fen,
    this.size = 64,
    this.flipped = false,
  });

  static const Color _light = Color(0xFFEBD3AE);
  static const Color _dark = Color(0xFFB07E58);

  @override
  Widget build(BuildContext context) {
    engine.ChessGame? game;
    try {
      game = engine.ChessGame.fromFen(fen);
    } catch (_) {
      game = null;
    }

    final square = size / 8;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          children: [
            CustomPaint(size: Size(size, size), painter: _MiniSquaresPainter()),
            if (game != null)
              for (int i = 0; i < 64; i++)
                if (game.board[i] != null)
                  Positioned(
                    left: (flipped ? 7 - i % 8 : i % 8) * square,
                    top: (flipped ? 7 - i ~/ 8 : i ~/ 8) * square,
                    width: square,
                    height: square,
                    child: PieceWidget(piece: game.board[i]!, size: square),
                  ),
          ],
        ),
      ),
    );
  }
}

class _MiniSquaresPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final square = size.width / 8;
    final paint = Paint();
    for (int row = 0; row < 8; row++) {
      for (int col = 0; col < 8; col++) {
        paint.color = (row + col) % 2 == 0 ? MiniBoard._light : MiniBoard._dark;
        canvas.drawRect(
          Rect.fromLTWH(col * square, row * square, square, square),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
