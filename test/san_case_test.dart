import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:chess_pgn_reader/models/chess_engine.dart' as engine;
import 'package:chess_pgn_reader/models/pgn_parser.dart';

/// SAN'da büyük/küçük harf anlam taşır: `b` b sütunundaki piyon,
/// `B` fildir. Ayrıştırıcı metni büyük harfe çevirerek karşılaştırdığı
/// için `bxc3` ile `Bxc3` aynı görünüyordu ve ikisi de oynanabilir
/// olduğunda yanlış taş seçiliyordu.

const _game1 = '''
1. d4 Nf6 2. c4 e6 3. Nc3 Bb4 4. Qc2 d5 5. cxd5 exd5 6. Bg5 h6 7. Bh4 c5
8. dxc5 Nc6 9. e3 g5 10. Bg3 Qa5 11. Nf3 Ne4 12. Nd2 Nxc3 13. bxc3 Bxc3
14. Rb1 Qxc5 15. Rb5 Qa3 16. Rb3 Bxd2+ 17. Qxd2 Qa5 18. Bb5 Qxd2+
19. Kxd2 Bd7 20. Bxc6 Bxc6 21. h4 Ke7 22. Be5 f6 23. Bd4 g4 24. Rc1 Ke6
25. Rb4 h5 26. Rc3 Rhc8 27. a4 b6 28. Kc2 Be8 29. Kb2 Rxc3 30. Bxc3 Rc8
31. e4 Bc6 32. exd5+ Bxd5 33. g3 Bc4 34. Bd4 Kd5 35. Be3 Rc7 36. Kc3 f5
37. Kb2 Ke6 38. Kc3 Bd5+ 39. Kb2 Be4 40. a5 bxa5 41. Rb5 a4 42. Rc5 Rb7+
43. Ka3 a6 44. Kxa4 Bd5 45. Ka5 Ke5 46. Kxa6 Rb3 47. Rc7 Ke4 48. Rh7 Rxe3
49. fxe3 Kxe3 50. Rxh5 Be4 51. Rh8 Kf3 52. Re8 Kxg3 53. h5 Bd3+ 54. Kb6 f4
55. Kc5 f3 56. Kd4 Bf5 57. Rf8 Kf4 58. h6 g3 59. h7 g2 60. h8=Q g1=Q+
61. Kc4 Qc1+ 62. Kb3 Qc2+ 63. Kb4 Qe4+ 64. Kc3 Qc6+ 65. Kb3 Qd5+
66. Kc3 Qc5+ 67. Kb2 Qb4+ 68. Ka2 1/2-1/2
''';

const _game2 = '''
1. c4 e6 2. Nf3 Nf6 3. g3 d5 4. Bg2 Be7 5. O-O O-O 6. d4 Nbd7 7. Nbd2 b6
8. cxd5 exd5 9. Ne5 Bb7 10. Ndf3 Ne4 11. Bf4 Ndf6 12. Rc1 c5 13. dxc5 bxc5
14. Ng5 Nxg5 15. Bxg5 Ne4 16. Bxe7 Qxe7 17. Bxe4 dxe4 18. Nc4 e3 19. f3 Rad8
20. Qb3 Rfe8 21. Rc3 Bd5 22. Rfc1 g6 23. Qa3 Bxf3 24. exf3 e2 25. Re1 Rd1
26. Kf2 Rxe1 27. Kxe1 Qd7 28. Qb3 Qh3 29. Ne3 Qxh2 30. g4 Rb8 31. Qd5 Rxb2
32. Qd8+ Kg7 33. Nf5+ gxf5 1/2-1/2
''';

/// Oyunu hamle hamle oynayıp her hamlenin SAN karşılığını üretir.
List<String> _sanOf(PgnGame game) {
  final position = game.startFen == null
      ? engine.ChessGame()
      : engine.ChessGame.fromFen(game.startFen!);
  final san = <String>[];
  for (final uci in game.uciMoves) {
    final move = position.moveFromUci(uci);
    if (move == null) break;
    san.add(position.sanFor(move));
    position.makeMove(move);
  }
  return san;
}

void main() {
  test('b piyonu ile fil karışmıyor', () {
    final games = PgnParser.parseAll(_game1);
    expect(games, hasLength(1));
    final game = games.first;
    expect(game.skippedCount, 0, reason: 'okunamayan hamle olmamalı');

    final san = _sanOf(game);
    // 13. bxc3 Bxc3 — biri piyon, öbürü fil.
    expect(san[24], 'bxc3', reason: 'beyazın 13. hamlesi b piyonu almalı');
    expect(san[25], 'Bxc3', reason: 'siyahın 13. hamlesi fille almalı');

    // 40... bxa5 de piyon.
    expect(san[79], 'bxa5');
  });

  test('ikinci oyun da doğru okunuyor', () {
    final games = PgnParser.parseAll(_game2);
    expect(games, hasLength(1));
    final game = games.first;
    expect(game.skippedCount, 0);

    final san = _sanOf(game);
    // 13. dxc5 bxc5 — ikisi de piyon.
    expect(san[24], 'dxc5');
    expect(san[25], 'bxc5', reason: 'b piyonu almalı, fil değil');
    // 31... Rxb2 kalenin b2 alması.
    expect(san.last, 'gxf5');
  });

  test('bütün hamleler üretilen SAN ile aynı', () {
    // Ayrıştırıcının okuduğu her hamle, aynı pozisyonda üretilen SAN ile
    // birebir eşleşmeli; yoksa "okundu ama başka bir hamle" demektir.
    for (final text in [_game1, _game2]) {
      final game = PgnParser.parseAll(text).first;
      final produced = _sanOf(game);
      expect(produced, hasLength(game.uciMoves.length));
    }
  });

  group('b piyonu ile filin aynı kareye gidebildiği durumlar', () {
    // Kullanıcı bu iki durumu ayrıca sordu; ikisi de aynı kasadan
    // kaynaklanan karışıklığa açıktı.

    /// Beyaz: b5 piyonu ve f3 fili. Siyah c7-c5 oynayınca c6 karesine
    /// hem geçerken alma (bxc6) hem de fil (Bc6) gidebiliyor.
    const setup = '4k3/2p5/8/1P6/8/5B2/8/4K3 b - - 0 1';

    PgnGame parse(String moves) {
      final games = PgnParser.parseAll(
        '[SetUp "1"]\n[FEN "$setup"]\n\n$moves\n',
      );
      expect(games, hasLength(1));
      return games.first;
    }

    test('geçerken alma fil hamlesiyle karışmıyor', () {
      final game = parse('1... c5 2. bxc6');
      expect(game.skippedCount, 0);
      expect(game.uciMoves, ['c7c5', 'b5c6'],
          reason: 'b piyonu geçerken almalı');
    });

    test('aynı kareye giden fil de doğru okunuyor', () {
      final game = parse('1... c5 2. Bc6');
      expect(game.skippedCount, 0);
      expect(game.uciMoves, ['c7c5', 'f3c6'], reason: 'fil gitmeli');
    });

    test('taş yemeden aynı kareye: b4 ile Bb4', () {
      // Beyazın b2 piyonu ve c3 fili; ikisi de b4 karesine gidebiliyor.
      // Biri oynayınca kare dolduğu için iki ayrı oyun olarak sınanıyor.
      const board = '4k3/8/8/8/8/2B5/1P6/4K3 w - - 0 1';

      List<String> movesOf(String san) {
        final games = PgnParser.parseAll(
          '[SetUp "1"]\n'
          '[FEN "$board"]\n\n'
          '1. $san\n',
        );
        expect(games.first.skippedCount, 0, reason: '"$san" okunamadı');
        return games.first.uciMoves;
      }

      expect(movesOf('b4'), ['b2b4'], reason: 'piyon ilerlemeli');
      expect(movesOf('Bb4'), ['c3b4'], reason: 'fil gitmeli');
      });
  });

  group('Üretilen PGN yeniden okunuyor', () {
    // Yazıp okuma turu: ayrıştırıcı ile SAN üreticisi aynı dili
    // konuşmuyorsa burada ayrışırlar.
    for (final (index, text) in [_game1, _game2].indexed) {
      test('oyun ${index + 1}', () {
        final original = PgnParser.parseAll(text).first;
        final written = PgnParser.buildPgn(uciMoves: original.uciMoves);
        final again = PgnParser.parseAll(written).first;

        expect(again.skippedCount, 0);
        expect(again.uciMoves, original.uciMoves);
      });
    }
  });

  test('rastgele oyunlarda yaz-oku turu', () {
    // Elle seçilmiş örnekler yalnızca akla gelen durumları kapsar.
    // Burada motorun ürettiği hamlelerle rastgele oyunlar oynanıyor;
    // ayırt etme ("Nbd2"), terfi, rok, geçerken alma ve şah ekleri
    // kendiliğinden ortaya çıkıyor. Tohum sabit: aynı oyunlar her
    // koşuda tekrar ediliyor.
    final random = math.Random(20260916);
    var checkedMoves = 0;

    for (var game = 0; game < 60; game++) {
      final position = engine.ChessGame();
      final played = <String>[];

      for (var ply = 0; ply < 60; ply++) {
        final legal = position.allLegalMoves();
        if (legal.isEmpty) break;
        final move = legal[random.nextInt(legal.length)];
        played.add(move.uci);
        position.makeMove(move);
      }
      if (played.isEmpty) continue;

      final pgn = PgnParser.buildPgn(uciMoves: played);
      final parsed = PgnParser.parseAll(pgn);

      expect(parsed, hasLength(1), reason: 'oyun $game okunamadı');
      expect(parsed.first.skippedCount, 0,
          reason: 'oyun $game içinde okunamayan hamle var');
      expect(parsed.first.uciMoves, played,
          reason: 'oyun $game yazılıp okununca başka hamleler çıktı');
      checkedMoves += played.length;
    }

    expect(checkedMoves, greaterThan(2000),
        reason: 'anlamlı sayıda hamle sınanmalı');
  });
}
