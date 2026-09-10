import 'package:flutter_test/flutter_test.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/models/playlist.dart';
import 'package:chess_pgn_reader/models/puzzle.dart';
import 'package:chess_pgn_reader/models/puzzle_search.dart';
import 'package:chess_pgn_reader/services/pgn_import_service.dart';

void main() {
  setUp(() => Strings.language = AppLanguage.turkish);

  group('Bulmaca araması', () {
    final endgame = Puzzle.fromAssetLine(
      '8/8/3k4/8/8/8/6Q1/7K w - - 0 1|oyunsonu,ustunluk,az-tas',
      'endgames#0',
    )!;
    final enPassant = Puzzle.fromAssetLine(
      '7k/8/7p/5Pp1/6P1/8/8/7K w - g6 0 1|oyunsonu,gecerken-alma,az-tas',
      'endgames#1',
    )!;
    final mate = Puzzle.fromAssetLine(
      '3q1rk1/5pbp/5Qp1/8/8/2B5/5PPP/6K1 w - - 0 1|mat-1|f6g7',
      'mates#0',
    )!;

    test('boş arama her şeyi geçirir', () {
      expect(puzzleMatches(endgame, ''), isTrue);
      expect(puzzleMatches(endgame, '   '), isTrue);
    });

    test('okunabilir etiketle bulunur', () {
      expect(puzzleMatches(endgame, 'oyun sonu'), isTrue);
      expect(puzzleMatches(endgame, 'az taş'), isTrue);
      expect(puzzleMatches(mate, '1 hamlede mat'), isTrue);
    });

    test('Türkçe harfler ve büyük/küçük harf ayrımı sorun çıkarmaz', () {
      expect(puzzleMatches(enPassant, 'geçerken'), isTrue);
      expect(puzzleMatches(enPassant, 'gecerken'), isTrue);
      expect(puzzleMatches(enPassant, 'GEÇERKEN ALMA'), isTrue);
      expect(puzzleMatches(endgame, 'ÜSTÜNLÜK'), isTrue);
    });

    test('ham etiket adıyla da bulunur', () {
      expect(puzzleMatches(enPassant, 'gecerken-alma'), isTrue);
      expect(puzzleMatches(mate, 'mat-1'), isTrue);
    });

    test('sıra numarasıyla bulunur', () {
      expect(puzzleMatches(endgame, '12', number: 12), isTrue);
      expect(puzzleMatches(endgame, '#12', number: 12), isTrue);
      expect(puzzleMatches(endgame, '1', number: 12), isTrue);
      expect(puzzleMatches(endgame, '13', number: 12), isFalse);
    });

    test('hamle sırasıyla bulunur', () {
      expect(puzzleMatches(endgame, 'beyaz'), isTrue);
      expect(puzzleMatches(endgame, 'siyah'), isFalse);
    });

    test('ad ve nota bakar', () {
      final named = endgame.copyWith(title: 'Vezir matı', note: 'kolay');
      expect(puzzleMatches(named, 'vezir'), isTrue);
      expect(puzzleMatches(named, 'KOLAY'), isTrue);
    });

    test('FEN parçasıyla bulunur', () {
      expect(puzzleMatches(endgame, '6Q1'), isTrue);
    });

    test('alakasız arama eşleşmez', () {
      expect(puzzleMatches(endgame, 'zzzz'), isFalse);
    });
  });

  group('Liste PGN dışa aktarımı', () {
    test('her oyun için ayrı PGN bloğu üretilir', () {
      final playlist = Playlist(name: 'Denemeler', games: [
        SavedGame(
          name: 'Birinci',
          uciMoves: const ['e2e4', 'e7e5', 'g1f3'],
          createdAt: DateTime(2026, 1, 2),
          result: '1-0',
          white: 'Ali',
          black: 'Veli',
        ),
        SavedGame(
          name: 'İkinci',
          uciMoves: const ['d2d4', 'd7d5'],
          createdAt: DateTime(2026, 3, 4),
        ),
      ]);

      final pgn = buildListPgn(playlist);
      expect('[Event'.allMatches(pgn).length, 2);
      expect(pgn, contains('[White "Ali"]'));
      expect(pgn, contains('[Black "Veli"]'));
      expect(pgn, contains('[Date "2026.01.02"]'));
      expect(pgn, contains('1. e4 e5 2. Nf3 1-0'));
      expect(pgn, contains('1. d4 d5 *'));
      // Adı olmayan oyuncularda oyun adı kullanılır.
      expect(pgn, contains('[White "İkinci"]'));
    });

    test('boş liste boş metin verir', () {
      expect(buildListPgn(Playlist(name: 'Boş')).trim(), isEmpty);
    });
  });
}
