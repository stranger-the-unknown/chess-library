import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/models/pgn_parser.dart';
import 'package:chess_pgn_reader/models/playlist.dart';
import 'package:chess_pgn_reader/models/puzzle.dart';
import 'package:chess_pgn_reader/models/puzzle_search.dart';
import 'package:chess_pgn_reader/screens/playlist_detail_screen.dart';
import 'package:chess_pgn_reader/services/pgn_import_service.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/services/storage_service.dart';

/// Oyun listesi kartı, sıralaması, tarihi ve araması.

String _pgn({
  required String white,
  required String black,
  String date = '2019.07.14',
  String event = 'Turnuva',
}) =>
    '''
[Event "$event"]
[Site "İstanbul"]
[Date "$date"]
[Round "3"]
[White "$white"]
[Black "$black"]
[Result "1-0"]
[ECO "B90"]

1. e4 c5 1-0
''';

Future<Playlist> _seed(String pgn) async {
  SharedPreferences.setMockInitialValues({});
  StorageService.instance.resetCache();
  await SettingsService.instance.load();
  Strings.language = AppLanguage.turkish;
  final playlist = await StorageService.instance.createPlaylist('Deneme');
  await PgnImportService.addToList(playlist.id, PgnParser.parseAll(pgn));
  return playlist;
}

Future<void> _pump(WidgetTester tester, String id) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(420, 900);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(MaterialApp(home: PlaylistDetailScreen(playlistId: id)));
  await tester.pumpAndSettle();
}

List<String> _numbersOnScreen(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data ?? '')
    .where((s) => RegExp(r'^\d+\.$').hasMatch(s))
    .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => Strings.language = AppLanguage.system);

  group('Tarih', () {
    test('tam tarih gün.ay.yıl olarak yazılır', () {
      final game = SavedGame(
        name: 'x',
        uciMoves: const [],
        createdAt: DateTime(2020),
        tags: const {'Date': '2019.07.14'},
      );
      expect(game.displayDate, '14.07.2019');
    });

    test('eksik tarihte yalnızca yıl yazılır', () {
      for (final raw in ['1997.??.??', '1997.12.??', '1997']) {
        final game = SavedGame(
          name: 'x',
          uciMoves: const [],
          createdAt: DateTime(2020),
          tags: {'Date': raw},
        );
        expect(game.displayDate, '1997', reason: raw);
      }
    });

    test('yıl bilinmiyorsa hiç yazılmaz', () {
      for (final raw in ['????.??.??', '', 'bilinmiyor']) {
        final game = SavedGame(
          name: 'x',
          uciMoves: const [],
          createdAt: DateTime(2020),
          tags: {'Date': raw},
        );
        expect(game.displayDate, isNull, reason: raw);
      }
    });

    test('tarih etiketi hiç yoksa null', () {
      final game = SavedGame(
        name: 'x',
        uciMoves: const [],
        createdAt: DateTime(2020),
      );
      expect(game.displayDate, isNull);
    });
  });

  group('Kart adı', () {
    test('First Last ve Last, First aynı soyadı verir', () {
      expect(playerLastName('Magnus Carlsen'), 'Carlsen');
      expect(playerLastName('Carlsen, Magnus'), 'Carlsen');
      expect(playerLastName('GM Magnus Carlsen'), 'Carlsen');
    });

    test('tek parça kullanıcı adı olduğu gibi kalır', () {
      expect(playerLastName('Hikaru'), 'Hikaru');
      expect(playerLastName('DrNykterstein'), 'DrNykterstein');
      expect(playerLastName('?'), '');
      expect(playerLastName(''), '');
    });
  });

  group('PGN dışa aktarma', () {
    test('çevrimiçi oyunun adı ve tarihi korunur', () {
      final game = SavedGame(
        name: 'Hikaru - Faker',
        uciMoves: const ['e2e4', 'e7e5'],
        createdAt: DateTime(2020, 1, 1),
        white: 'Hikaru',
        black: 'Faker',
        result: '1-0',
        tags: const {
          'Event': 'Live Chess',
          'Site': 'Chess.com',
          'Date': '2024.03.15',
          'WhiteElo': '2800',
        },
      );
      final pgn = buildListPgn(Playlist(name: 'Online', games: [game]));
      expect(pgn, contains('[White "Hikaru"]'));
      expect(pgn, contains('[Black "Faker"]'));
      expect(pgn, contains('[Date "2024.03.15"]'));
      expect(pgn, contains('[WhiteElo "2800"]'));
      expect(pgn, isNot(contains('[Date "2020.01.01"]')));
    });

    test('saat yorumlu çevrimiçi PGN okunur', () {
      const pgn = '''
[Event "Live Chess"]
[Site "Chess.com"]
[Date "2024.03.15"]
[White "Hikaru"]
[Black "Faker"]
[Result "1-0"]

1. e4 {[%clk 0:09:59]} e5 {[%clk 0:09:58]} 2. Nf3 {[%clk 0:09:50]} 1-0
''';
      final games = PgnParser.parseAll(pgn);
      expect(games, hasLength(1));
      expect(games.single.white, 'Hikaru');
      expect(games.single.black, 'Faker');
      expect(games.single.uciMoves.length, 3);
    });

    test('küçük harfli white başlığı oyuncu adına yazılır', () {
      const pgn = '''
[event "x"]
[white "alice"]
[black "bob"]
[result "1-0"]

1. e4 e5 1-0
''';
      final games = PgnParser.parseAll(pgn);
      expect(games.single.white, 'alice');
      expect(games.single.black, 'bob');
    });
  });

  group('Kart', () {
    testWidgets('kartta soyad görünür, tam ad durur', (tester) async {
      const white = 'Çok Uzun Bir Beyaz Oyuncu Adı';
      const black = 'Çok Uzun Bir Siyah Oyuncu Adı';
      final playlist = await _seed(_pgn(white: white, black: black));
      await _pump(tester, playlist.id);

      expect(find.text('Adı'), findsNWidgets(2));
      expect(find.text(white), findsNothing);
      expect(find.text(black), findsNothing);
    });

    testWidgets('kullanıcı adı soyad gibi kesilmez', (tester) async {
      final playlist = await _seed(_pgn(white: 'Hikaru', black: 'DrNykterstein'));
      await _pump(tester, playlist.id);
      expect(find.text('Hikaru'), findsOneWidget);
      expect(find.text('DrNykterstein'), findsOneWidget);
    });

    testWidgets('arama hâlâ ilk ada bakıyor', (tester) async {
      final playlist = await _seed(_pgn(white: 'Magnus Carlsen', black: 'Ian Nepomniachtchi'));
      await _pump(tester, playlist.id);
      await tester.enterText(find.byType(TextField), 'magnus');
      await tester.pumpAndSettle();
      expect(find.text('Carlsen'), findsOneWidget);
      expect(find.text('Nepomniachtchi'), findsOneWidget);
    });

    testWidgets('tarih kartta görünüyor', (tester) async {
      final playlist = await _seed(_pgn(white: 'Ali', black: 'Veli'));
      await _pump(tester, playlist.id);
      expect(find.text('14.07.2019'), findsOneWidget);
    });

    testWidgets('PGN bilgileri menüden açılıyor', (tester) async {
      final playlist = await _seed(_pgn(white: 'Ali', black: 'Veli'));
      await _pump(tester, playlist.id);

      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Oyun bilgileri'));
      await tester.pumpAndSettle();

      expect(find.text('Turnuva'), findsOneWidget);
      expect(find.text('İstanbul'), findsOneWidget);
      expect(find.text('B90'), findsOneWidget);
      // Bilinmeyen alanlar listelenmemeli.
      expect(find.text('?'), findsNothing);
    });
  });

  group('Sıralama', () {
    testWidgets('ok listeyi tersine çeviriyor', (tester) async {
      final pgn = List.generate(
        4,
        (i) => _pgn(white: 'Beyaz ${i + 1}', black: 'Siyah ${i + 1}'),
      ).join();
      final playlist = await _seed(pgn);
      await _pump(tester, playlist.id);

      expect(_numbersOnScreen(tester), ['1.', '2.', '3.', '4.']);

      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();
      expect(_numbersOnScreen(tester), ['4.', '3.', '2.', '1.']);
    });

    testWidgets('süzgeç değişince sıralama varsayılana dönüyor',
        (tester) async {
      final pgn = List.generate(
        4,
        (i) => _pgn(white: 'Beyaz ${i + 1}', black: 'Siyah ${i + 1}'),
      ).join();
      final playlist = await _seed(pgn);
      await _pump(tester, playlist.id);

      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();
      expect(_numbersOnScreen(tester), ['4.', '3.', '2.', '1.']);

      await tester.tap(find.text('Okunmamış'));
      await tester.pumpAndSettle();
      expect(_numbersOnScreen(tester), ['1.', '2.', '3.', '4.']);
    });
  });

  group('Sayıyla arama', () {
    test('bulmacada yalnızca numaraya bakılır', () {
      // FEN'inde 1 geçen ama numarası 2 olan bulmaca, "1" aramasında
      // çıkmamalı.
      final puzzle = Puzzle(
        id: 'p',
        fen: '8/8/8/4k3/8/4K3/4P3/8 w - - 0 1',
        tags: const ['az-tas'],
      );
      expect(puzzleMatches(puzzle, '1', number: 1), isTrue);
      expect(puzzleMatches(puzzle, '1', number: 12), isTrue);
      expect(puzzleMatches(puzzle, '1', number: 2), isFalse);
      expect(puzzleMatches(puzzle, '#2', number: 2), isTrue);
    });

    test('harf içeren arama metne bakmayı sürdürür', () {
      final puzzle = Puzzle(
        id: 'p',
        fen: '8/8/8/4k3/8/4K3/4P3/8 w - - 0 1',
        tags: const ['az-tas'],
      );
      expect(puzzleMatches(puzzle, 'az-tas', number: 5), isTrue);
    });

    testWidgets('oyun listesinde de yalnızca numaraya bakılır',
        (tester) async {
      // 1 numaralı oyunun adında 2 geçiyor; "2" araması onu getirmemeli.
      final playlist = await _seed(
        _pgn(white: 'Beyaz 2', black: 'Siyah 2') +
            _pgn(white: 'Ali', black: 'Veli'),
      );
      await _pump(tester, playlist.id);

      await tester.enterText(find.byType(TextField).first, '2');
      await tester.pumpAndSettle();

      expect(_numbersOnScreen(tester), ['2.']);
      expect(find.text('Ali'), findsOneWidget);
      expect(find.text('Beyaz 2'), findsNothing);
    });
  });
}
