import 'package:flutter/material.dart';

import '../models/chess_engine.dart' as engine;
import '../services/settings_service.dart';
import 'piece_widget.dart';

/// Bulmaca ve oyun listelerinde kullanılan küçük, etkileşimsiz tahta.
///
/// Kareler görsel yerine doğrudan çizilir: liste binlerce satır olabilir
/// ve her satırda bir görsel çözmek kaydırmayı belirgin biçimde yavaşlatır.
///
/// Renkler **seçili tahtadan**, taşlar **seçili takımdan** gelir; böylece
/// önizleme oyun tahtasıyla aynı görünür. Ahşap tahtalarda dokunun yerine
/// o tahtanın temsilî iki rengi kullanılır.
class MiniBoard extends StatelessWidget {
  final String fen;
  final double size;
  final bool flipped;

  /// Belirtilmezse ayarlardaki kare renkleri kullanılır.
  final int? light;
  final int? dark;

  const MiniBoard({
    super.key,
    required this.fen,
    this.size = 64,
    this.flipped = false,
    this.light,
    this.dark,
  });

  @override
  Widget build(BuildContext context) {
    engine.ChessGame? game;
    try {
      game = engine.ChessGame.fromFen(fen);
    } catch (_) {
      game = null;
    }

    final settings = SettingsService.instance;
    final squareLight = light ?? settings.boardLight;
    final squareDark = dark ?? settings.boardDark;

    final square = size / 8;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          children: [
            CustomPaint(
              size: Size(size, size),
              painter: _MiniSquaresPainter(
                Color(squareLight),
                Color(squareDark),
              ),
            ),
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
  final Color light;
  final Color dark;

  const _MiniSquaresPainter(this.light, this.dark);

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / 8;
    final cellH = size.height / 8;
    final paint = Paint();
    for (int row = 0; row < 8; row++) {
      for (int col = 0; col < 8; col++) {
        paint.color = (row + col) % 2 == 0 ? light : dark;
        canvas.drawRect(
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
  bool shouldRepaint(covariant _MiniSquaresPainter oldDelegate) =>
      oldDelegate.light != light || oldDelegate.dark != dark;
}
