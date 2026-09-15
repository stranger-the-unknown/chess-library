import 'package:flutter_test/flutter_test.dart';

import 'package:chess_pgn_reader/models/chess_engine.dart' as engine;
import 'package:chess_pgn_reader/models/move_entry.dart';
import 'package:chess_pgn_reader/models/stored_review.dart';
import 'package:chess_pgn_reader/services/analysis_queue.dart';
import 'package:chess_pgn_reader/services/game_review.dart';

/// Kaydedilmiş analizin geri kurulması.
///
/// Amaç, listeden bir kaydı açınca motorun yeniden çalışmaması. Kayıt
/// oyunla uyuşmazsa geri kurma reddedilmeli, yoksa ekranda yanlış
/// değerlendirmeler gösterilir.

List<MoveEntry> _history(List<String> uciMoves) {
  final position = engine.ChessGame();
  final history = <MoveEntry>[];
  for (final uci in uciMoves) {
    final move = position.moveFromUci(uci)!;
    final san = position.sanFor(move);
    position.makeMove(move);
    history.add(MoveEntry(move: move, san: san, fenAfter: position.fen));
  }
  return history;
}

StoredReview _stored(int moveCount) => StoredReview(
      deep: true,
      at: DateTime.now(),
      whiteAccuracy: 88,
      blackAccuracy: 64,
      moves: List.generate(
        moveCount,
        (i) => StoredReviewMove(
          bestScoreCp: 40 - i,
          playedScoreCp: 10 - i,
          bestMoveUci: 'e2e4',
          quality: MoveQuality.inaccuracy.index,
          accuracy: 70,
        ),
      ),
    );

void main() {
  test('kayıt geri kuruluyor', () {
    final history = _history(['e2e4', 'e7e5', 'g1f3']);
    final review = fromStoredReview(_stored(3), history);

    expect(review, isNotNull);
    expect(review!.moves, hasLength(3));
    expect(review.whiteAccuracy, 88);
    expect(review.blackAccuracy, 64);
    expect(review.moves.first.bestScoreCp, 40);
    expect(review.moves.first.quality, MoveQuality.inaccuracy);
  });

  test('oynayan taraf doğru atanıyor', () {
    final history = _history(['e2e4', 'e7e5', 'g1f3']);
    final review = fromStoredReview(_stored(3), history)!;

    expect(review.moves[0].mover, engine.Color.white);
    expect(review.moves[1].mover, engine.Color.black);
    expect(review.moves[2].mover, engine.Color.white);
  });

  test('önerilen hamlenin SAN karşılığı yeniden üretiliyor', () {
    // SAN kaydedilmiyor; aynı bilgiyi iki kez saklamamak için
    // pozisyondan hesaplanıyor.
    final history = _history(['d2d4']);
    final review = fromStoredReview(_stored(1), history)!;
    expect(review.moves.first.bestMoveSan, 'e4');
  });

  test('hamle sayısı uyuşmazsa geri kurma reddediliyor', () {
    final history = _history(['e2e4', 'e7e5']);
    expect(fromStoredReview(_stored(5), history), isNull);
    expect(fromStoredReview(_stored(1), history), isNull);
  });

  test('gidiş dönüş: kaydedilip geri okunduğunda aynı', () {
    final original = _stored(3);
    final decoded = StoredReview.fromJson(original.toJson());

    expect(decoded.deep, original.deep);
    expect(decoded.whiteAccuracy, original.whiteAccuracy);
    expect(decoded.moves, hasLength(3));
    expect(decoded.moves.first.bestMoveUci, 'e2e4');
    expect(decoded.moves.first.quality, MoveQuality.inaccuracy.index);
  });
}
