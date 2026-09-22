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
    // `makeMove` yasadışı hamlede `false` dönüyor ve bu sessizce
    // yutuluyordu: tahta oynamıyor ama kayıt listesine ekleniyor, geçmiş
    // ile tahta ayrışıyordu. Çağıranların hepsi yasal hamle veriyor;
    // burada yakalanan bir hata varsa o çağıran bozuktur.
    final played = position.makeMove(move);
    // `assert` yetmiyordu: sürüm derlemesinde kalkıyor ve kayıt tahtaya
    // uymadığı hâlde listeye giriyordu. Tahta bu durumda değişmemiş
    // oluyor; hata atıp kaydı hiç üretmemek ikisini tutarlı bırakıyor.
    if (!played) {
      throw StateError('yasadışı hamle oynatılmaya çalışıldı: ${move.uci}');
    }
    return MoveEntry(move: move, san: san, fenAfter: position.fen);
  }

  /// UCI listesini baştan oynayarak kayıt listesi üretir.
  /// Geçersiz bir hamlede durur.
  ///
  /// Bozuk bir başlangıç konumu (elle düzenlenmiş kayıt) `fromFen` ile
  /// hata fırlatıyordu; okunamayan konum yok sayılıp standart dizilişten
  /// başlanıyor.
  static List<MoveEntry> fromUciList(
    List<String> uciMoves, {
    String? startFen,
  }) {
    final position =
        startFen != null && engine.ChessGame.validateFen(startFen) == null
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
