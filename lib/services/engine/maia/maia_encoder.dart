import 'dart:typed_data';

import '../../../models/chess_engine.dart' as engine;

/// Konumları Maia-3'ün girdisine, hamleleri onun hamle numaralarına
/// çevirir (`maia3/dataset.py`, `maia3/utils.py`).
///
/// Kurallar orijinal koddan:
/// * Kare numarası a1 = 0, h8 = 63 (bizim motorda satır 0 = 8. sıra).
/// * Sırası siyahtaysa tahta aynalanır: sıralar ters çevrilir, renkler
///   değişir. Model hep "beyaz oynuyor" gibi görür. Geçmişteki her konum
///   **kendi** sırası gelen tarafa göre aynalanır.
/// * Bir karenin 12 kanalı: piyon, at, fil, kale, vezir, şah (beyaz), sonra
///   aynıları siyah için.
/// * Geçmiş eskiden yeniye dizilir; eksikse en eski konum başa tekrarlanır.
/// * Hamle numarası: kaynak × 64 + hedef (aynalanmış karelerle). Terfiler
///   ayrı: 4096 + (kaynak dosya × 8 + hedef dosya) × 4 + (v, k, f, a).
class MaiaEncoder {
  MaiaEncoder._();

  /// [boards]: eskiden yeniye konumlar; sonuncusu hamle sırası olan konum.
  static Float32List encode(List<engine.ChessGame> boards, int history) {
    if (boards.isEmpty) throw ArgumentError('maia: konum yok');
    final recent = boards.length > history
        ? boards.sublist(boards.length - history)
        : boards;
    final padded = [
      for (var i = 0; i < history - recent.length; i++) recent.first,
      ...recent,
    ];
    final width = history * 12;
    final out = Float32List(64 * width);
    for (var slot = 0; slot < history; slot++) {
      final game = padded[slot];
      final black = game.sideToMove == engine.Color.black;
      for (var row = 0; row < 8; row++) {
        for (var col = 0; col < 8; col++) {
          final piece = game.board[row * 8 + col];
          if (piece == null) continue;
          var square = (7 - row) * 8 + col;
          var isBlack = piece.color == engine.Color.black;
          if (black) {
            square ^= 56;
            isBlack = !isBlack;
          }
          final channel = piece.type.index + (isBlack ? 6 : 0);
          out[square * width + slot * 12 + channel] = 1;
        }
      }
    }
    return out;
  }

  /// Hamlenin Maia numarası; [sideToMove] hamleyi yapan taraf.
  static int moveIndex(engine.ChessMove move, engine.Color sideToMove) {
    final black = sideToMove == engine.Color.black;
    var from = (7 - move.from.row) * 8 + move.from.col;
    var to = (7 - move.to.row) * 8 + move.to.col;
    if (black) {
      from ^= 56;
      to ^= 56;
    }
    final promotion = move.promotion;
    if (promotion == null) return from * 64 + to;
    final piece = switch (promotion) {
      engine.PieceType.queen => 0,
      engine.PieceType.rook => 1,
      engine.PieceType.bishop => 2,
      engine.PieceType.knight => 3,
      _ => throw ArgumentError('maia: geçersiz terfi'),
    };
    return 4096 + ((from % 8) * 8 + (to % 8)) * 4 + piece;
  }
}
