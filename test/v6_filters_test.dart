import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/models/game_filter.dart';
import 'package:chess_pgn_reader/models/move_count.dart';
import 'package:chess_pgn_reader/models/pgn_parser.dart';
import 'package:chess_pgn_reader/models/playlist.dart';
import 'package:chess_pgn_reader/screens/playlist_detail_screen.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/services/storage_service.dart';
import 'package:chess_pgn_reader/widgets/game_filter_dialog.dart';

/// Sürüm 6 / 6.1: oyun filtresi, hamle sayısı, yıl ve renk-bağımsız ad.

SavedGame _game(
  String white,
  String black,
  String result, {
  String? date,
}) =>
    SavedGame(
      name: '$white - $black',
      uciMoves: const ['e2e4', 'e7e5'],
      createdAt: DateTime.now(),
      white: white,
      black: black,
      result: result,
      tags: {
        if (date != null) 'Date': date,
      },
    );

final _carlsenNepo = _game('Magnus Carlsen', 'Ian Nepomniachtchi', '1-0');
final _aronianCarlsen = _game('Levon Aronian', 'Magnus Carlsen', '0-1');
final _carlsenCaruana = _game('Magnus Carlsen', 'Fabiano Caruana', '1/2-1/2');

List<SavedGame> _filtered(GameFilter filter) => [
      _carlsenNepo,
      _aronianCarlsen,
      _carlsenCaruana,
    ].where(filter.matches).toList();

Future<Playlist> _seed() async {
  SharedPreferences.setMockInitialValues({});
  StorageService.instance.resetCache();
  await SettingsService.instance.load();
  Strings.language = AppLanguage.turkish;
  final playlist = await StorageService.instance.createPlaylist('Turnuva');
  await StorageService.instance.addGames(
    playlist.id,
    [_carlsenNepo, _aronianCarlsen, _carlsenCaruana],
  );
  return playlist;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => Strings.language = AppLanguage.system);

  group('Oyuncu süzgeci', () {
    test('boş süzgeç hiçbir oyunu elemiyor', () {
      expect(GameFilter.none.isActive, isFalse);
      expect(_filtered(GameFilter.none), hasLength(3));
    });

    test('yalnızca beyaz oyuncu yazılabiliyor', () {
      final games = _filtered(const GameFilter(white: 'Carlsen'));
      expect(games, hasLength(2));
      expect(games.every((g) => g.white == 'Magnus Carlsen'), isTrue);
    });

    test('yalnızca siyah oyuncu yazılabiliyor', () {
      final games = _filtered(const GameFilter(black: 'Carlsen'));
      expect(games, hasLength(1));
      expect(games.single.white, 'Levon Aronian');
    });

    test('ikisi birden yazılınca ikisi de tutmalı', () {
      expect(
        _filtered(const GameFilter(white: 'Carlsen', black: 'Caruana')),
        hasLength(1),
      );
      expect(
        _filtered(const GameFilter(white: 'Caruana', black: 'Carlsen')),
        isEmpty,
      );
    });

    test('büyük küçük harf ayrımı yok', () {
      for (final yazim in ['CARLSEN', 'carlsen', 'CaRlSeN']) {
        expect(_filtered(GameFilter(white: yazim)), hasLength(2),
            reason: yazim);
      }
    });

    test('adın bir parçası yetiyor', () {
      // Soyadı, adı ya da yalnızca birkaç harf.
      expect(_filtered(const GameFilter(black: 'nepo')), hasLength(1));
      expect(_filtered(const GameFilter(white: 'magnus')), hasLength(2));
      expect(_filtered(const GameFilter(white: 'carl')), hasLength(2));
    });

    test('ad sırası önemli değil', () {
      // PGN dosyalarında "Carlsen, Magnus" da geçiyor.
      final game = _game('Carlsen, Magnus', 'Nepomniachtchi, Ian', '1-0');
      expect(const GameFilter(white: 'magnus carlsen').matches(game), isTrue);
    });

    test('Türkçe harfler sadeleşiyor', () {
      final game = _game('İbrahim Çetin', 'Şule Işık', '1-0');
      expect(const GameFilter(white: 'ibrahim cetin').matches(game), isTrue);
      expect(const GameFilter(black: 'sule isik').matches(game), isTrue);
    });
  });

  group('Sonuç süzgeci', () {
    test('beyaz kazanır', () {
      final games = _filtered(const GameFilter(result: ResultFilter.whiteWins));
      expect(games, hasLength(1));
      expect(games.single.black, 'Ian Nepomniachtchi');
    });

    test('siyah kazanır', () {
      final games = _filtered(const GameFilter(result: ResultFilter.blackWins));
      expect(games.single.white, 'Levon Aronian');
    });

    test('beraberlik', () {
      final games = _filtered(const GameFilter(result: ResultFilter.draw));
      expect(games.single.black, 'Fabiano Caruana');
    });

    test('yarım işaretiyle yazan dosyalar da beraberlik sayılıyor', () {
      final game = _game('Bir', 'İki', '½-½');
      expect(const GameFilter(result: ResultFilter.draw).matches(game), isTrue);
    });

    test('şu oyuncu kazanır: iki renkte de', () {
      final games = _filtered(
        const GameFilter(result: ResultFilter.playerWins, winner: 'carlsen'),
      );
      expect(games, hasLength(2), reason: 'biri beyazla biri siyahla kazandı');
      expect(games.any((g) => g.result == '1-0'), isTrue);
      expect(games.any((g) => g.result == '0-1'), isTrue);
    });

    test('kazanan adı boşken süzgeç sayılmıyor', () {
      const filter = GameFilter(result: ResultFilter.playerWins);
      expect(filter.isActive, isFalse);
      expect(_filtered(filter), hasLength(3));
    });

    test('sonucu bilinmeyen oyun sonuç süzgecine takılıyor', () {
      final game = _game('Bir', 'İki', '*');
      expect(
        const GameFilter(result: ResultFilter.whiteWins).matches(game),
        isFalse,
      );
    });

    test('oyuncu ve sonuç birlikte çalışıyor', () {
      expect(
        _filtered(
          const GameFilter(white: 'Carlsen', result: ResultFilter.draw),
        ),
        hasLength(1),
      );
      expect(
        _filtered(
          const GameFilter(white: 'Aronian', result: ResultFilter.whiteWins),
        ),
        isEmpty,
      );
    });
  });

  group('Renk fark etmesin', () {
    test('kapalıyken eski kural duruyor', () {
      expect(
        const GameFilter(white: 'Carlsen', ignoreColor: false).isActive,
        isTrue,
      );
      expect(_filtered(const GameFilter(white: 'Carlsen')), hasLength(2));
      expect(_filtered(const GameFilter(black: 'Carlsen')), hasLength(1));
    });

    test('yalnız işaretliyse filtre sayılmıyor', () {
      const filter = GameFilter(ignoreColor: true);
      expect(filter.isActive, isFalse);
      expect(_filtered(filter), hasLength(3));
    });

    test('tek ad, iki renkte de', () {
      final games = _filtered(
        const GameFilter(white: 'Carlsen', ignoreColor: true),
      );
      expect(games, hasLength(3));
    });

    test('tek ad alt alana yazılınca da aynı', () {
      expect(
        _filtered(const GameFilter(black: 'Carlsen', ignoreColor: true)),
        hasLength(3),
      );
    });

    test('iki ad, renk sırası fark etmez', () {
      expect(
        _filtered(const GameFilter(
          white: 'Carlsen',
          black: 'Aronian',
          ignoreColor: true,
        )),
        hasLength(1),
      );
      expect(
        _filtered(const GameFilter(
          white: 'Aronian',
          black: 'Carlsen',
          ignoreColor: true,
        )),
        hasLength(1),
      );
      expect(
        _filtered(const GameFilter(
          white: 'Carlsen',
          black: 'Caruana',
          ignoreColor: true,
        )),
        hasLength(1),
      );
    });

    test('iki ad kapalıyken ters renk boş kalır', () {
      expect(
        _filtered(const GameFilter(white: 'Carlsen', black: 'Aronian')),
        isEmpty,
      );
    });

    test('renk-bağımsız ad ve sonuç birlikte', () {
      expect(
        _filtered(const GameFilter(
          white: 'Carlsen',
          ignoreColor: true,
          result: ResultFilter.draw,
        )),
        hasLength(1),
      );
      expect(
        _filtered(const GameFilter(
          white: 'Carlsen',
          black: 'Aronian',
          ignoreColor: true,
          result: ResultFilter.whiteWins,
        )),
        isEmpty,
        reason: 'Aronian-Carlsen 0-1 bitti, beyaz kazanmadı',
      );
      expect(
        _filtered(const GameFilter(
          white: 'Carlsen',
          black: 'Aronian',
          ignoreColor: true,
          result: ResultFilter.blackWins,
        )),
        hasLength(1),
      );
    });
  });

  group('Yıl filtresi', () {
    final dated = [
      _game('Magnus Carlsen', 'Ian Nepomniachtchi', '1-0', date: '2021.11.26'),
      _game('Levon Aronian', 'Magnus Carlsen', '0-1', date: '2018.07.14'),
      _game('Magnus Carlsen', 'Fabiano Caruana', '1/2-1/2', date: '2021.??.??'),
      _game('Ali', 'Veli', '1-0'),
    ];

    test('yıl PGN Date ve UTCDate üzerinden okunur', () {
      expect(dated[0].year, 2021);
      expect(dated[1].year, 2018);
      expect(dated[2].year, 2021);
      expect(dated[3].year, isNull);
      expect(
        SavedGame(
          name: 'x',
          uciMoves: const [],
          createdAt: DateTime(2020),
          tags: const {'UTCDate': '2019.01.02'},
        ).year,
        2019,
      );
    });

    test('yıla göre eler', () {
      expect(dated.where(const GameFilter(year: 2021).matches), hasLength(2));
      expect(dated.where(const GameFilter(year: 2018).matches), hasLength(1));
      expect(dated.where(const GameFilter(year: 1999).matches), isEmpty);
    });

    test('tarihi olmayan oyun yıl filtresine takılır', () {
      expect(const GameFilter(year: 2021).matches(dated[3]), isFalse);
    });

    test('yıl ve oyuncu birlikte', () {
      expect(
        dated.where(const GameFilter(white: 'Carlsen', year: 2021).matches),
        hasLength(2),
      );
      expect(
        dated.where(const GameFilter(
          white: 'Carlsen',
          ignoreColor: true,
          year: 2018,
        ).matches),
        hasLength(1),
      );
    });

    test('yıl, renk-bağımsız ad ve sonuç üçü birden', () {
      final filter = const GameFilter(
        white: 'Carlsen',
        ignoreColor: true,
        year: 2021,
        result: ResultFilter.draw,
      );
      final games = dated.where(filter.matches).toList();
      expect(games, hasLength(1));
      expect(games.single.black, 'Fabiano Caruana');
    });
  });

  group('Hamle sayısı', () {
    test('beyazın hamlesi yazılıyor, ikisinin toplamı değil', () {
      // 1. e4 e5 2. Nf3 -> beyaz iki hamle yaptı.
      final game = SavedGame(
        name: 'Kısa',
        uciMoves: const ['e2e4', 'e7e5', 'g1f3'],
        createdAt: DateTime.now(),
      );
      expect(game.moveCount, 2);
    });

    test('yarım hamle sayısından beyazın sayısına', () {
      expect(countWhiteMoves(2, null), 1);
      expect(countWhiteMoves(80, null), 40);
      expect(countWhiteMoves(81, null), 41);
      expect(countWhiteMoves(0, null), 0);
    });

    test('siyahın oynayacağı konumdan başlayan oyun', () {
      const fen = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1';
      expect(countWhiteMoves(1, fen), 0, reason: 'ilk hamle siyahın');
      expect(countWhiteMoves(2, fen), 1);
      expect(countWhiteMoves(3, fen), 1);
    });

    test('PGN listesinde de aynı sayı', () {
      final games = PgnParser.parseAll(
        '[White "Bir"]\n[Black "Iki"]\n[Result "1-0"]\n\n'
        '1. e4 e5 2. Nf3 Nc6 3. Bb5 1-0\n',
      );
      expect(games, hasLength(1));
      expect(games.single.uciMoves, hasLength(5));
      expect(games.single.moveCount, 3);
    });
  });

  group('Süzgeç penceresi', () {
    testWidgets('menüden açılıyor, listeyi süzüyor ve şerit görünüyor',
        (tester) async {
      final playlist = await _seed();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(600, 1200);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: KeyedSubtree(
            key: UniqueKey(),
            child: PlaylistDetailScreen(playlistId: playlist.id),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Aronian'), findsOneWidget);

      // Oyun kartlarının da menüsü var; aranan başlıktaki.
      await tester.tap(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byType(PopupMenuButton<String>),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Oyun filtrele').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.ancestor(
          of: find.text('Beyaz oyuncu'),
          matching: find.byType(TextField),
        ),
        'carl',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Filtrele'));
      await tester.pumpAndSettle();

      expect(find.text('Aronian'), findsNothing,
          reason: 'filtreye takılan oyun listede kalmamalı');
      expect(find.text('Nepomniachtchi'), findsOneWidget);
      expect(find.text('Caruana'), findsOneWidget);
      expect(find.textContaining('Beyaz oyuncu: carl'), findsOneWidget,
          reason: 'şerit hangi filtrenin açık olduğunu yazmalı');
      expect(find.textContaining('2 oyun'), findsOneWidget,
          reason: 'kaç oyun kaldığı yazmalı');

      // Şeritteki çarpı filtreyi kaldırıyor.
      await tester.tap(find.byTooltip('Filtreyi temizle'));
      await tester.pumpAndSettle();
      expect(find.text('Aronian'), findsOneWidget);
    });

    testWidgets('dar telefonda taşmıyor', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.instance.load();
      Strings.language = AppLanguage.turkish;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 640);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GameFilterDialog(
              filter: GameFilter(
                result: ResultFilter.playerWins,
                winner: 'Carlsen',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Beş seçenek ve ad alanı birlikte görünürken bile taşma yok:
      // taşma olsaydı test kendiliğinden düşerdi.
      expect(find.text('Şu oyuncu kazanır'), findsOneWidget);
      expect(find.text('Kazanan oyuncu'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Filtrele'), findsOneWidget);
      expect(find.text('Renk fark etmesin'), findsOneWidget);
      expect(find.text('Yıl'), findsOneWidget);
    });

    testWidgets('renk fark etmesin tek adla iki rengi de getiriyor',
        (tester) async {
      final playlist = await _seed();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(600, 1200);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: KeyedSubtree(
            key: UniqueKey(),
            child: PlaylistDetailScreen(playlistId: playlist.id),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byType(PopupMenuButton<String>),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Oyun filtrele').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.ancestor(
          of: find.text('Oyuncu'),
          matching: find.byType(TextField),
        ),
        'aronian',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Filtrele'));
      await tester.pumpAndSettle();

      expect(find.text('Aronian'), findsOneWidget);
      expect(find.text('Carlsen'), findsOneWidget);
      expect(find.text('Nepomniachtchi'), findsNothing);
      expect(find.textContaining('1 oyun'), findsOneWidget);
    });
  });
}
