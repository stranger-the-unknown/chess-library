import 'package:flutter_test/flutter_test.dart';

import 'package:chess_pgn_reader/models/chess_engine.dart' as game;
import 'package:chess_pgn_reader/models/pgn_parser.dart';
import 'package:chess_pgn_reader/models/puzzle.dart';
import 'package:chess_pgn_reader/services/engine/engine_service.dart';

/// `models/chess_engine.dart` (arayüz motoru) için perft.
int gamePerft(game.ChessGame position, int depth) {
  if (depth == 0) return 1;
  int total = 0;
  for (final move in position.allLegalMoves()) {
    final next = position.copy();
    if (!next.makeMove(move)) continue;
    total += gamePerft(next, depth - 1);
  }
  return total;
}

const kiwipete =
    'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1';
const position3 = '8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1';
const position4 =
    'r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1';
const position5 = 'rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8';
const startpos = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

void main() {

  group('Arayüz motoru perft', () {
    test('başlangıç', () {
      expect(gamePerft(game.ChessGame(), 3), 8902);
    });
    test('kiwipete', () {
      expect(gamePerft(game.ChessGame.fromFen(kiwipete), 3), 97862);
    });
    test('pozisyon 3 (en passant tuzakları)', () {
      expect(gamePerft(game.ChessGame.fromFen(position3), 4), 43238);
    });
    test('pozisyon 4 (terfiler)', () {
      expect(gamePerft(game.ChessGame.fromFen(position4), 3), 9467);
    });
  });

  group('FEN', () {
    test('gidiş dönüş', () {
      for (final fen in [startpos, kiwipete, position3, position4, position5]) {
        expect(game.ChessGame.fromFen(fen).fen, fen);
      }
    });

    test('geçersiz FEN reddedilir', () {
      expect(game.ChessGame.validateFen('bozuk'), isNotNull);
      expect(
          game.ChessGame.validateFen('8/8/8/8/8/8/8/8 w - - 0 1'), isNotNull);
      expect(
        game.ChessGame.validateFen('4k3/8/8/8/8/8/4P3/4K3 w - - 0 1'),
        isNull,
      );
      // Sırası olmayan taraf şahta olamaz.
      expect(
        game.ChessGame.validateFen('4k3/8/8/8/8/8/8/4KQ2 b - - 0 1'),
        isNull,
      );
      expect(
        game.ChessGame.validateFen('4k3/8/8/8/8/8/8/4K1Q1 w - - 0 1'),
        isNull,
      );
    });

    test('olmayan kale için rok hakkı temizlenir', () {
      final position =
          game.ChessGame.fromFen('4k3/8/8/8/8/8/8/4K3 w KQkq - 0 1');
      expect(position.fen.split(' ')[2], '-');
    });
  });

  group('SAN', () {
    test('temel gösterimler', () {
      final position = game.ChessGame();
      expect(position.sanFor(position.moveFromUci('e2e4')!), 'e4');
      expect(position.sanFor(position.moveFromUci('g1f3')!), 'Nf3');
    });

    test('rok, alma, terfi ve mat', () {
      final castle =
          game.ChessGame.fromFen('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1');
      expect(castle.sanFor(castle.moveFromUci('e1g1')!), 'O-O');
      expect(castle.sanFor(castle.moveFromUci('e1c1')!), 'O-O-O');

      final promotion =
          game.ChessGame.fromFen('8/4P3/8/8/8/8/8/k1K5 w - - 0 1');
      expect(promotion.sanFor(promotion.moveFromUci('e7e8n')!), 'e8=N');

      final mate =
          game.ChessGame.fromFen('6k1/5ppp/8/8/8/8/8/R3K2R w KQ - 0 1');
      expect(mate.sanFor(mate.moveFromUci('a1a8')!), 'Ra8#');
    });

    test('aynı kareye giden taşlar ayırt edilir', () {
      final position =
          game.ChessGame.fromFen('4k3/8/8/8/8/4K3/8/R6R w - - 0 1');
      expect(position.sanFor(position.moveFromUci('a1d1')!), 'Rad1');

      // Aynı dosyadaki iki kale sıra numarasıyla ayrılır.
      final files = game.ChessGame.fromFen('4k3/8/8/R7/8/4K3/8/R7 w - - 0 1');
      expect(files.sanFor(files.moveFromUci('a1a3')!), 'R1a3');
    });
  });

  group('PGN', () {
    test('SAN hamleleri ve sonuç okunur', () {
      final parser = PgnParser();
      expect(
        parser.parse('1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 1-0'),
        isTrue,
      );
      expect(parser.moves, ['e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1b5', 'a7a6']);
      expect(parser.gameResult, '1-0');
    });

    test('yorumlar, varyasyonlar ve NAG işaretleri atlanır', () {
      final parser = PgnParser();
      parser.parse(
        '[Event "Test"]\n\n1. d4 {iyi hamle} d5 \$1 (1... Nf6 2. c4) 2. c4 *',
      );
      expect(parser.moves, ['d2d4', 'd7d5', 'c2c4']);
    });

    test('FEN başlığı olan PGN doğru pozisyondan başlar', () {
      final parser = PgnParser();
      parser.parse(
        '[SetUp "1"]\n[FEN "4k3/8/8/8/8/8/4P3/4K3 w - - 0 1"]\n\n1. e4 Kd7 *',
      );
      expect(parser.startFen, '4k3/8/8/8/8/8/4P3/4K3 w - - 0 1');
      expect(parser.moves, ['e2e4', 'e8d7']);
    });
  });


  group('Çok oyunlu PGN', () {
    const twoGames = '[Event "Test A"]\n'
        '[White "Ali"]\n'
        '[Black "Veli"]\n'
        '[Result "1-0"]\n'
        '\n'
        '1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 1-0\n'
        '\n'
        '[Event "Test B"]\n'
        '[White "Ayse"]\n'
        '[Black "Fatma"]\n'
        '[Result "0-1"]\n'
        '\n'
        '1. d4 d5 2. c4 e6 0-1\n';

    test('oyunlar ayrılır', () {
      expect(PgnParser.splitGames(twoGames).length, 2);
    });

    test('tüm oyunlar çözümlenir', () {
      final games = PgnParser.parseAll(twoGames);
      expect(games.length, 2);
      expect(games[0].white, 'Ali');
      expect(games[0].black, 'Veli');
      expect(games[0].result, '1-0');
      expect(games[0].uciMoves.length, 6);
      expect(games[1].title, 'Ayse - Fatma');
      expect(games[1].uciMoves, ['d2d4', 'd7d5', 'c2c4', 'e7e6']);
    });

    test('başlıksız tek oyun da okunur', () {
      final games = PgnParser.parseAll('1. e4 e5 2. Nf3 *');
      expect(games.length, 1);
      expect(games.first.uciMoves, ['e2e4', 'e7e5', 'g1f3']);
    });
  });

  group('Bulmaca varlık satırı', () {
    test('çözümlü satır okunur', () {
      final puzzle = Puzzle.fromAssetLine(
        '3q1rk1/5pbp/5Qp1/8/8/2B5/5PPP/6K1 w - - 0 1|mat-1|f6g7',
        'mates#0',
      )!;
      expect(puzzle.tags, ['mat-1']);
      expect(puzzle.solution, ['f6g7']);
      expect(puzzle.hasSolution, isTrue);
      expect(puzzle.mateInMoves, 1);
    });

    test('çözümsüz satır da okunur', () {
      final puzzle = Puzzle.fromAssetLine(
        '8/8/3k4/8/8/8/6Q1/7K w - - 0 1|oyunsonu,az-tas',
        'endgames#0',
      )!;
      expect(puzzle.hasSolution, isFalse);
      expect(puzzle.tags.length, 2);
    });

    test('pozisyon değişince çözüm düşer', () {
      final puzzle = Puzzle.fromAssetLine(
        '3q1rk1/5pbp/5Qp1/8/8/2B5/5PPP/6K1 w - - 0 1|mat-1|f6g7',
        'mates#0',
      )!;
      final edited = puzzle.copyWith(fen: '4k3/8/8/8/8/8/4P3/4K3 w - - 0 1');
      expect(edited.solution, isEmpty);
      expect(puzzle.copyWith(title: 'ad').solution, ['f6g7']);
    });

    test('kayıtlı mat çözümü gerçekten mat ediyor', () {
      final puzzle = Puzzle.fromAssetLine(
        '1Q6/8/8/8/8/k2K4/8/8 w - - 0 1|mat-2|d3c3 a3a2 b8b2',
        'mates#1',
      )!;
      final position = game.ChessGame.fromFen(puzzle.fen);
      for (final uci in puzzle.solution) {
        final move = position.moveFromUci(uci);
        expect(move, isNotNull, reason: uci);
        position.makeMove(move!);
      }
      expect(position.isCheckmate, isTrue);
    });
  });
  group('EngineLevel → Stockfish eşlemesi', () {
    test('skill değerleri ve Usta tam güç', () {
      final stockfish = EngineLevel.all.where((e) => !e.isMaia).toList();
      expect(stockfish.map((e) => e.skill), [17, 20]);
      expect(EngineLevel.all.last.isFullStrength, isTrue);
      expect(EngineLevel.all.first.isFullStrength, isFalse);
    });
  });

}
