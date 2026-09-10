import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:chess_pgn_reader/models/playlist.dart';
import 'package:chess_pgn_reader/services/pgn_import_service.dart';

/// Gerçekten oynanabilir 40 yarım hamlelik bir oyun (İspanyol açılışı).
const List<String> _realMoves = [
  'e2e4',
  'e7e5',
  'g1f3',
  'b8c6',
  'f1b5',
  'a7a6',
  'b5a4',
  'g8f6',
  'e1g1',
  'f8e7',
  'f1e1',
  'b7b5',
  'a4b3',
  'd7d6',
  'c2c3',
  'e8g8',
  'h2h3',
  'c6b8',
  'd2d4',
  'b8d7',
  'b1d2',
  'c8b7',
  'b3c2',
  'f8e8',
  'd2f1',
  'e7f8',
  'f1g3',
  'g7g6',
  'c1g5',
  'h7h6',
  'g5d2',
  'f8g7',
  'a2a4',
  'c7c5',
  'd4d5',
  'c5c4',
  'b2b4',
  'c4b3',
  'c2b3',
  'd8c7',
];

/// 44 hamlelik bir oyunun UCI listesi kadar veri.
List<String> _moves() =>
    List<String>.generate(87, (i) => 'e2e4'.substring(0, 4));

SavedGame _game(int i) => SavedGame(
      name: 'Beyaz $i - Siyah $i',
      uciMoves: _moves(),
      createdAt: DateTime(2026, 1, 1),
      result: '1-0',
      white: 'Beyaz $i',
      black: 'Siyah $i',
    );

void main() {
  test('1000 oyunluk liste JSON boyutu', () {
    final playlist = Playlist(name: 'Büyük liste');
    for (int i = 0; i < 1000; i++) {
      playlist.games.add(_game(i));
    }

    final json = jsonEncode([playlist.toJson()]);
    final kb = json.length / 1024;
    // ignore: avoid_print
    print('1000 oyun · ${kb.toStringAsFixed(0)} KB JSON');

    expect(playlist.games.length, 1000);
    // Tek seferde yazılabilecek boyutta kalmalı.
    expect(kb, lessThan(2048));
  });

  test('oyun başına yazma ile tek yazmanın maliyeti', () {
    final playlist = Playlist(name: 'Ölçüm');

    // Her eklemede tüm listeyi yeniden kodlamak (eski davranış).
    final perGame = Stopwatch()..start();
    for (int i = 0; i < 300; i++) {
      playlist.games.add(_game(i));
      jsonEncode([playlist.toJson()]);
    }
    perGame.stop();

    final single = Playlist(name: 'Ölçüm');
    final bulk = Stopwatch()..start();
    for (int i = 0; i < 300; i++) {
      single.games.add(_game(i));
    }
    jsonEncode([single.toJson()]);
    bulk.stop();

    // ignore: avoid_print
    print('300 oyun · oyun başına kodlama ${perGame.elapsedMilliseconds} ms · '
        'tek kodlama ${bulk.elapsedMilliseconds} ms');

    // Toplu yazma en az bir kat daha hızlı olmalı.
    expect(bulk.elapsedMilliseconds * 5, lessThan(perGame.elapsedMilliseconds));
  });

  test('liste PGN cikarma olcegi', () {
    for (final count in [50, 200]) {
      final playlist = Playlist(name: 'Cikti');
      for (int i = 0; i < count; i++) {
        playlist.games.add(SavedGame(
          name: 'Oyun $i',
          uciMoves: List<String>.from(_realMoves),
          createdAt: DateTime(2026, 1, 1),
          result: '1-0',
        ));
      }

      final watch = Stopwatch()..start();
      final pgn = buildListPgn(playlist);
      watch.stop();

      expect('[Event'.allMatches(pgn).length, count);
      // ignore: avoid_print
      print('$count oyun -> PGN · ${(pgn.length / 1024).round()} KB · '
          '${watch.elapsedMilliseconds} ms · '
          '${(watch.elapsedMilliseconds / count).toStringAsFixed(1)} ms/oyun');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
