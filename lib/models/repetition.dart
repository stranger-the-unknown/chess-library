import 'chess_engine.dart' as engine;

/// Konum tekrarı sayımı.
///
/// Anahtar olarak FEN'in ilk dört alanı kullanılıyor: taş dizilimi, sıra,
/// rok hakları ve geçerken alma karesi. Son iki alan (yarım hamle sayacı
/// ve hamle numarası) her hamlede değiştiği için tekrarı bozar; sayıma
/// girmemeleri gerekir.
///
/// Geçerken alma karesi yalnızca alma **gerçekten mümkünse** anahtara
/// giriyor (FIDE 9.2: konumlar, olası hamleler aynıysa aynıdır). Motor bu
/// kareyi her çift kare piyon sürüşünden sonra yazıyor; eskiden anahtara
/// da hep giriyordu ve sürüşten hemen sonraki konum, aynı konumun sonraki
/// tekrarlarından ayrı sayılıyordu. `1.e4 e5 2.Nf3 Nf6 3.Ng1 Ng8 4.Nf3 Nf6
/// 5.Ng1 Ng8` sonrasında FIDE'ye göre üç tekrar var; sayım iki buluyordu.
///
/// Ekrandan ayrı bir yerde duruyor ki kuralı tahtayı çizmeden
/// sınayabilelim.
String positionKey(String fen) {
  final parts = fen.split(' ');
  if (parts.length < 4) return fen;
  final ep = parts[3] != '-' && _enPassantPossible(fen) ? parts[3] : '-';
  return '${parts[0]} ${parts[1]} ${parts[2]} $ep';
}

/// Sırası gelen taraf geçerken almayı yasal olarak yapabiliyor mu?
///
/// Yalnızca hedef karenin iki yanındaki piyonlara bakılıyor: bu hesap her
/// çizimde bütün geçmiş için yapıldığından ucuz kalmalı. Açmazdaki piyonun
/// alması yasal hamle üretiminde zaten eleniyor.
bool _enPassantPossible(String fen) {
  final engine.ChessGame game;
  try {
    game = engine.ChessGame.fromFen(fen);
  } catch (_) {
    return true; // Okunamayan FEN'de eski davranış: kare korunur.
  }
  final target = game.enPassantTarget;
  if (target == null) return false;
  final to = engine.Position.fromIndex(target);
  final pawnRow =
      game.sideToMove == engine.Color.white ? to.row + 1 : to.row - 1;
  for (final col in [to.col - 1, to.col + 1]) {
    if (col < 0 || col > 7) continue;
    final from = engine.Position(pawnRow, col);
    final piece = game.pieceAt(from);
    if (piece == null ||
        piece.type != engine.PieceType.pawn ||
        piece.color != game.sideToMove) {
      continue;
    }
    if (game.legalMovesFrom(from).any((m) => m.to.index == target)) {
      return true;
    }
  }
  return false;
}

/// [current] konumu, [fens] içinde (kendisi dahil) kaç kez geçiyor?
int repetitionCount(Iterable<String> fens, String current) {
  final key = positionKey(current);
  var count = 0;
  for (final fen in fens) {
    if (positionKey(fen) == key) count++;
  }
  return count;
}

/// Üç tekrar oldu mu?
bool isThreefold(Iterable<String> fens, String current) =>
    repetitionCount(fens, current) >= 3;
