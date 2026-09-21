import 'package:flutter_test/flutter_test.dart';

import 'package:chess_pgn_reader/models/chess_engine.dart' as engine;
import 'package:chess_pgn_reader/models/move_entry.dart';
import 'package:chess_pgn_reader/models/repetition.dart';

/// Beraberlik kuralları.
///
/// Elli hamle ve yetersiz materyal motorda zaten hesaplanıyordu ama oyun
/// yalnızca mat ve patta bitiyordu; üç tekrar ise hiç yoktu. Şah ve şah
/// kalan bir oyun sonsuza kadar sürüyordu.

/// Atları ileri geri oynatarak konumu tekrarlar.
List<String> _shuffle(int plies) {
  final position = engine.ChessGame();
  const cycle = ['g1f3', 'g8f6', 'f3g1', 'f6g8'];
  final fens = <String>[position.fen];
  for (var i = 0; i < plies; i++) {
    final move = position.moveFromUci(cycle[i % cycle.length])!;
    MoveEntry.play(position, move);
    fens.add(position.fen);
  }
  return fens;
}

void main() {
  group('Üç tekrar', () {
    test('yarım hamle sayacı ve hamle numarası tekrarı bozmuyor', () {
      const a = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
      const b = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 8 5';
      expect(positionKey(a), positionKey(b));
      expect(repetitionCount([a, b], a), 2);
    });

    test('rok hakkı değişince aynı konum sayılmıyor', () {
      const withRights =
          'r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1';
      const without = 'r3k2r/8/8/8/8/8/8/R3K2R w - - 0 1';
      expect(positionKey(withRights) == positionKey(without), isFalse);
    });

    test('atlar iki tur gidip gelince üç tekrar oluyor', () {
      // Başlangıç + iki tam tur: başlangıç konumu üç kez görülür.
      final fens = _shuffle(8);
      expect(isThreefold(fens, fens.last), isTrue);

      // Bir tur yetmez.
      final short = _shuffle(4);
      expect(isThreefold(short, short.last), isFalse);
      expect(repetitionCount(short, short.last), 2);
    });

    test('farklı konumlar tekrar saymıyor', () {
      final position = engine.ChessGame();
      final fens = <String>[position.fen];
      for (final uci in ['e2e4', 'e7e5', 'g1f3', 'b8c6']) {
        MoveEntry.play(position, position.moveFromUci(uci)!);
        fens.add(position.fen);
      }
      expect(isThreefold(fens, fens.last), isFalse);
      expect(repetitionCount(fens, fens.last), 1);
    });
  });

  group('Motorun bildiği beraberlikler', () {
    test('yetersiz materyal: şah ve şah', () {
      final position = engine.ChessGame.fromFen('8/8/4k3/8/8/4K3/8/8 w - - 0 1');
      expect(position.insufficientMaterial, isTrue);
      expect(position.isCheckmate, isFalse);
      expect(position.isStalemate, isFalse);
    });

    test('elli hamle kuralı sayaçtan okunuyor', () {
      final position =
          engine.ChessGame.fromFen('8/8/4k3/8/8/4K3/7R/8 w - - 100 80');
      expect(position.fiftyMoveRule, isTrue);
    });
  });
}
