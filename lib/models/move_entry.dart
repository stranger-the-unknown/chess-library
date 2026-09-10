import 'chess_engine.dart' as engine;

/// Bir hamle ve onun görüntülenebilir bilgileri.
///
/// SAN gösterimi hamle oynanmadan **önce** hesaplanmalıdır; bu sınıf
/// hesaplanmış hâli taşıyarak listelerin her karede yeniden SAN üretmesini
/// önler (uzun oyunlarda gözle görülür bir fark yaratır).
class MoveEntry {
  final engine.ChessMove move;
  final String san;

  /// Hamleden sonraki pozisyonun FEN'i (analiz ve tekrar tespiti için).
  final String fenAfter;

  const MoveEntry({
    required this.move,
    required this.san,
    required this.fenAfter,
  });

  String get uci => move.uci;

  /// Verilen pozisyonda hamleyi oynayarak bir kayıt üretir.
  /// [position] hamle oynanmış hâlde geri döner.
  static MoveEntry play(engine.ChessGame position, engine.ChessMove move) {
    final san = position.sanFor(move);
    position.makeMove(move);
    return MoveEntry(move: move, san: san, fenAfter: position.fen);
  }

  /// UCI listesini baştan oynayarak kayıt listesi üretir.
  /// Geçersiz bir hamlede durur.
  static List<MoveEntry> fromUciList(
    List<String> uciMoves, {
    String? startFen,
  }) {
    final position = startFen != null
        ? engine.ChessGame.fromFen(startFen)
        : engine.ChessGame();
    final entries = <MoveEntry>[];
    for (final uci in uciMoves) {
      final move = position.moveFromUci(uci);
      if (move == null) break;
      entries.add(play(position, move));
    }
    return entries;
  }
}
