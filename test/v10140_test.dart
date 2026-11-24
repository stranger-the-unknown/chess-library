import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/models/chess_engine.dart' as engine;
import 'package:chess_pgn_reader/models/opening.dart';
import 'package:chess_pgn_reader/models/game_filter.dart';
import 'package:chess_pgn_reader/models/pgn_parser.dart';
import 'package:chess_pgn_reader/models/playlist.dart';
import 'package:chess_pgn_reader/models/puzzle.dart';
import 'package:chess_pgn_reader/screens/game_screen.dart';
import 'package:chess_pgn_reader/screens/home_shell.dart';
import 'package:chess_pgn_reader/screens/openings/opening_study_screen.dart';
import 'package:chess_pgn_reader/screens/playlist_detail_screen.dart';
import 'package:chess_pgn_reader/screens/puzzles/puzzle_list_screen.dart';
import 'package:chess_pgn_reader/screens/puzzles/puzzle_solve_screen.dart';
import 'package:chess_pgn_reader/services/engine/search_result.dart';
import 'package:chess_pgn_reader/services/app_store.dart';
import 'package:chess_pgn_reader/services/opening_service.dart';
import 'package:chess_pgn_reader/services/prefs_write.dart';
import 'package:chess_pgn_reader/services/puzzle_service.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/services/storage_service.dart';
import 'package:chess_pgn_reader/theme/app_look.dart';
import 'package:chess_pgn_reader/theme/app_theme.dart';
import 'package:chess_pgn_reader/widgets/app_dialogs.dart';
import 'package:chess_pgn_reader/widgets/chess_board_widget.dart';

/// 10.14.0: 10.13.0 incelemesinden kalan hatalar ve öneriler. Her test,
/// düzeltmeden önceki kodda düşüyordu.

Future<void> _wait(WidgetTester tester, [int ms = 1000]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Üç oyunluk liste ("Beyaz 1" … "Beyaz 3") ve onun ekranı.
Future<Playlist> _openList(WidgetTester tester, {Set<int> read = const {}}) async {
  final storage = StorageService.instance;
  storage.resetCache();
  final list = await storage.createPlaylistWithGames('Okuma', [
    for (var i = 1; i <= 3; i++)
      SavedGame(
        name: 'Oyun $i',
        uciMoves: const ['e2e4', 'e7e5'],
        createdAt: DateTime(2026, 11, i),
        white: 'Beyaz $i',
        black: 'Siyah $i',
        read: read.contains(i),
      ),
  ]);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(480, 1000);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
      MaterialApp(home: PlaylistDetailScreen(playlistId: list.id)));
  await tester.pumpAndSettle();
  return list;
}

/// Tahtadaki bir kareye dokunur (beyaz aşağıda).
Future<void> _tapSquare(WidgetTester tester, String square) async {
  final board = tester.getRect(find.byType(ChessBoardWidget));
  final size = board.width / 8;
  final file = square.codeUnitAt(0) - 'a'.codeUnitAt(0);
  final rank = int.parse(square[1]);
  await tester.tapAt(Offset(
    board.left + (file + 0.5) * size,
    board.top + (8 - rank + 0.5) * size,
  ));
  await tester.pump();
}

Future<void> _pumpGame(WidgetTester tester, Widget screen,
    {Size size = const Size(360, 640)}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: screen));
  await _wait(tester, 400);
}

Opening _line(String id, String variation, List<String> uci,
        List<String> san) =>
    Opening(
      id: id,
      eco: 'B90',
      family: 'Sicilya Savunması',
      variation: variation,
      uciMoves: uci,
      sanMoves: san,
      custom: true,
    );

final _najdorf = _line('n', 'Najdorf Varyantı', const ['e2e4', 'c7c5'],
    const ['e4', 'c5']);
final _dragon = _line('d', 'Ejderha Varyantı', const ['e2e4', 'c7c5', 'g1f3'],
    const ['e4', 'c5', 'Nf3']);

Finder _inGame(Finder finder) =>
    find.descendant(of: find.byType(GameScreen), matching: finder);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'flutter.soundEnabled': false,
      'flutter.soundDefaultsRestored': true,
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dev.fluttercommunity.plus/wakelock'),
            (call) async => null);
    // Sıra önemli: `load` dili ayardan (sistem) yeniden kuruyor.
    await SettingsService.instance.load();
    Strings.language = AppLanguage.turkish;
    PuzzleService.instance.resetCache();
    OpeningService.instance.resetCache();
  });

  tearDown(() {
    AppStore.instance = PrefsStore();
    Strings.language = AppLanguage.system;
  });

  group('Masaüstünde deponun açılması', () {
    late Directory support;
    setUp(() async {
      support = await Directory.systemTemp.createTemp('cl_store_');
    });
    tearDown(() async {
      if (await support.exists()) await support.delete(recursive: true);
    });

    test('ilk deneme olmazsa bir kez daha deneniyor', () async {
      var calls = 0;
      final opened = await openDesktopStore(
        support,
        retryDelay: Duration.zero,
        open: (dir) async {
          if (++calls == 1) throw const FileSystemException('kilitli');
          return FileStore.open(dir);
        },
      );
      expect(calls, 2);
      expect(opened.readOnly, isFalse);
      expect(opened.store, isA<FileStore>());
    });

    test('veri klasörü var ama açılamıyorsa hiçbir şey diske yazılmıyor',
        () async {
      // Veri dosyalarda; açılamayınca eskiden tercih deposuna düşülüyordu:
      // o oturumda yazılanlar sonraki açılışta gerçek dosyaların yerine
      // geçiyordu.
      final real = await FileStore.open(support);
      await real.setString('playlists_v2', '[GERCEK]');
      SharedPreferences.setMockInitialValues({});

      final opened = await openDesktopStore(
        support,
        retryDelay: Duration.zero,
        open: (dir) async => throw const FileSystemException('okunamadı'),
      );
      expect(opened.readOnly, isTrue, reason: 'kullanıcıya söylenmeli');
      expect(opened.store, isA<MemoryStore>());

      await opened.store.setString('playlists_v2', '[BU OTURUM]');
      expect(await opened.store.getString('playlists_v2'), '[BU OTURUM]');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().where(AppStore.isDataKey), isEmpty,
          reason: 'tercih dosyasına veri yazılmamalı');

      // Sonraki açılış: gerçek veri yerinde.
      final reopened = await FileStore.open(support);
      expect(await reopened.getString('playlists_v2'), '[GERCEK]');
    });

    test('klasör hiç oluşmadıysa veri tercih dosyasından okunuyor', () async {
      SharedPreferences.setMockInitialValues({'playlists_v2': '[ESKI]'});
      final notADir = File('${support.path}${Platform.pathSeparator}dosya');
      await notADir.writeAsString('x');
      final opened = await openDesktopStore(Directory(notADir.path),
          retryDelay: Duration.zero);
      expect(opened.readOnly, isFalse);
      expect(opened.store, isA<PrefsStore>());
      expect(await opened.store.getString('playlists_v2'), '[ESKI]');
    });
  });

  testWidgets('"Kaydedilemedi" uyarısını başarı mesajı örtmüyor',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (c) {
        context = c;
        return const SizedBox();
      })),
    ));
    // Olağan durumda mesaj çıkıyor.
    AppDialogs.snack(context, 'ilk');
    await tester.pump();
    expect(find.text('ilk'), findsOneWidget);

    // Yazma başarısız: uygulama kökü uyarıyı gösteriyor, servis olağan
    // dönüyor, ekran "eklendi" demeye çalışıyor.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(t('lists.saveFailed'))));
    reportWriteFailure();
    AppDialogs.snack(context, '3 işaretlendi');
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text(t('lists.saveFailed')), findsOneWidget);
    expect(find.text('3 işaretlendi'), findsNothing);

    // Yalnızca o bir mesaj yutuluyor.
    AppDialogs.snack(context, 'sonraki');
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('sonraki'), findsOneWidget);
  });

  test('yanlış türde yazılmış ayar açılışı durdurmuyor', () async {
    // Elle düzenlenmiş bir yedek: sayı olması gereken yerde metin.
    SharedPreferences.setMockInitialValues({
      'flutter.themeMode': '2',
      'flutter.showCoordinates': 'evet',
      'flutter.pieceSet': 7,
      'flutter.boardSize': true,
      'flutter.soundDefaultsRestored': 'x',
    });
    await SettingsService.instance.load();
    expect(SettingsService.instance.themeMode, ThemeMode.system);
    expect(SettingsService.instance.showCoordinates, isTrue);
  });

  group('İçe aktarma', () {
    test('açılış dosyası: kesilen ve okunamayan satırlar sayılıyor', () async {
      final result = await OpeningService.instance.importText([
        'Sicilya|Ana|1. e4 c5 2. Nf3 d6',
        // Yan varyantlı satır: "(2." geçersiz, üç hamle olarak ekleniyor.
        'Sicilya|Alapin|1. e4 c5 2. Nf3 (2. c3) d6',
        'yalnızca bir alan',
        'İtalyan|Bozuk|1. Zz9 e5',
        '# açıklama',
        '',
      ].join('\n'));
      expect(result.added, 2);
      expect(result.truncated, 1);
      expect(result.invalid, 2);
    });

    test('bulmaca dosyası: okunamayan satırların numarası dönüyor', () async {
      final service = PuzzleService.instance;
      final collection = await service.createCollection('Kitap');
      final invalid = <int>[];
      final added = await service.importFens(
        collection,
        [
          '6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1',
          'bu bir fen değil',
          '6k1/5ppp/8/8/8/8/5PPP/R5K1 b - - 0 1',
        ].join('\n'),
        invalidLines: invalid,
      );
      expect(added, 2);
      expect(invalid, [2]);
    });
  });

  group('Bulmaca', () {
    test('motorun yargıladığı matta kısa matlar en hızlı yoldan', () {
      // Tahtada 1 hamlede mat: mat etmeyen hamle (geriye 1 ya da 2 kalır)
      // kabul edilmiyordu olmalı; eskiden ikisi de "Doğru"ydu.
      expect(PuzzleSolveScreen.mateFastEnough(1, 1), isFalse);
      expect(PuzzleSolveScreen.mateFastEnough(1, 2), isFalse);
      // 2 hamlede mat: en iyi hamleden sonra 1 kalır.
      expect(PuzzleSolveScreen.mateFastEnough(2, 1), isTrue);
      expect(PuzzleSolveScreen.mateFastEnough(2, 2), isFalse);
      // Uzun matta bir hamle pay (sığ aramanın oynaklığı), iki değil.
      expect(PuzzleSolveScreen.mateFastEnough(5, 4), isTrue);
      expect(PuzzleSolveScreen.mateFastEnough(5, 5), isTrue);
      expect(PuzzleSolveScreen.mateFastEnough(5, 6), isFalse);
    });

    test('FEN\'de çift boşluk ya da büyük B: sıra yine siyahta', () {
      expect(Puzzle(id: 'a', fen: '6k1/8/8/8/8/8/8/6K1  b - - 0 1').sideToMove,
          engine.Color.black);
      expect(Puzzle(id: 'b', fen: '6k1/8/8/8/8/8/8/6K1 B - - 0 1').sideToMove,
          engine.Color.black);
      expect(Puzzle(id: 'c', fen: '6k1/8/8/8/8/8/8/6K1 w - - 0 1').sideToMove,
          engine.Color.white);
    });
  });

  group('PGN', () {
    test('yorumun içindeki { oyunun kalanını yutmuyor', () {
      final game = PgnParser.parseAll('1. e4 { a { b } e5 2. Nf3 Nc6 *').single;
      expect(game.uciMoves, ['e2e4', 'e7e5', 'g1f3', 'b8c6']);
    });

    test('başlıksız, boş satırla ayrılmış oyunlar ayrı oyun', () {
      final games = PgnParser.splitGames('1. e4 e5 2. Nf3 1-0\n\n'
          '1. d4 d5\n2. c4 *\n\n'
          '1. c4 e5 1/2-1/2\n');
      expect(games, hasLength(3));
      // Sonuçsuz biten hamle satırından sonraki boş satır oyunu bölmüyor.
      expect(
          PgnParser.splitGames('[Event "x"]\n\n1. e4 e5\n\n2. Nf3 Nc6 *\n'),
          hasLength(1));
    });
  });

  group('Oyun listesi', () {
    testWidgets('"Devam et" ilk okunmamış oyunu açıyor', (tester) async {
      await _openList(tester, read: {1});
      await tester.tap(find.text(t('puzzles.continue')));
      await _wait(tester, 800);
      expect(_inGame(find.text('Beyaz 2')), findsOneWidget);
      expect(
          _inGame(find.text(t('lists.gamePosition', {'n': 2, 'total': 3}))),
          findsOneWidget);
    });

    testWidgets('hepsi okunmuşsa "Devam et" ilk oyunu açıyor', (tester) async {
      await _openList(tester, read: {1, 2, 3});
      await tester.tap(find.text(t('puzzles.continue')));
      await _wait(tester, 800);
      expect(_inGame(find.text('Beyaz 1')), findsOneWidget);
    });

    testWidgets('oyun ekranı süzgeç açıkken de listedeki numarayı yazıyor',
        (tester) async {
      // "Okunmamış" süzgecinde ilk görünen oyun listenin 2. oyunu; eskiden
      // "Oyun 1 / 2" yazıyordu.
      await _openList(tester, read: {1});
      await tester.tap(find.text(t('lists.filterUnread')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Beyaz 2'));
      await _wait(tester, 800);
      expect(
          _inGame(find.text(t('lists.gamePosition', {'n': 2, 'total': 3}))),
          findsOneWidget);
      // Oklar süzülmüş sırada geziyor: sonraki, listenin 3. oyunu.
      await tester.tap(_inGame(find.byTooltip(t('lists.nextGame'))));
      await _wait(tester, 800);
      expect(_inGame(find.text('Beyaz 3')), findsOneWidget);
      expect(
          _inGame(find.text(t('lists.gamePosition', {'n': 3, 'total': 3}))),
          findsOneWidget);
    });
  });

  group('Oyun ekranı', () {
    for (final result in const ['1-0', null]) {
      testWidgets(
          'deneme hamlesi tahtayı kaydırmıyor '
          '(${result == null ? 'sonuçsuz oyun' : 'sonuçlu oyun'})',
          (tester) async {
        // Kısa telefon: eskiden deneme kartı belirince adlar ve tahta
        // kayıyor ya da tahta küçülüyordu.
        await _pumpGame(
          tester,
          GameScreen(
            uciMoves: const ['e2e4', 'e7e5'],
            initialResult: result,
            whiteName: 'Ali',
            blackName: 'Banu',
            showTitle: false,
          ),
        );
        // Son konuma git (sonuç kartı son hamlede görünüyor).
        await tester.tap(find.byTooltip(t('game.toEnd')));
        await _wait(tester, 300);
        final before = tester.getRect(find.byType(ChessBoardWidget));

        await _tapSquare(tester, 'g1');
        await _tapSquare(tester, 'f3');
        await _wait(tester, 300);
        expect(find.text('Nf3'), findsOneWidget, reason: 'deneme kartı');
        expect(find.byTooltip(t('game.backToGame')), findsOneWidget);
        expect(tester.getRect(find.byType(ChessBoardWidget)), before);
        expect(tester.takeException(), isNull);

        await tester.tap(find.byTooltip(t('game.backToGame')));
        await _wait(tester, 300);
        expect(tester.getRect(find.byType(ChessBoardWidget)), before);
      });
    }

    testWidgets('kayıtlı oyunun menüsü: kayıt en üstte, yeniden başlat yok',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await _pumpGame(
        tester,
        const GameScreen(
          uciMoves: ['e2e4', 'e7e5'],
          whiteName: 'Ali',
          blackName: 'Banu',
          showTitle: false,
        ),
        size: const Size(480, 1000),
      );
      await tester.tap(find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(PopupMenuButton<String>),
      ));
      await _wait(tester, 500);
      final items = tester
          .widgetList<PopupMenuItem<String>>(
              find.byType(PopupMenuItem<String>))
          .map((item) => item.value)
          .toList();
      expect(items, isNot(contains('restart')));
      expect(items, contains('play'),
          reason: '"Bu konumdan motora karşı oyna"');
      if (items.contains('record')) expect(items.first, 'record');
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('serbest tahtada "yeniden başlat" duruyor', (tester) async {
      await _pumpGame(tester, const GameScreen(title: 'Serbest tahta'),
          size: const Size(480, 1000));
      await tester.tap(find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(PopupMenuButton<String>),
      ));
      await _wait(tester, 500);
      expect(find.text(t('game.restart')), findsOneWidget);
    });

    testWidgets('listede son hamlede "sona git" yerine sonraki oyun',
        (tester) async {
      await _openList(tester);
      await tester.tap(find.text('Beyaz 1'));
      await _wait(tester, 800);
      expect(_inGame(find.byKey(const ValueKey('nextGameAtEnd'))),
          findsNothing, reason: 'oyunun başında değil');
      await tester.tap(_inGame(find.byTooltip(t('game.toEnd'))));
      await _wait(tester, 300);
      final next = _inGame(find.byKey(const ValueKey('nextGameAtEnd')));
      expect(next, findsOneWidget);
      await tester.tap(next);
      await _wait(tester, 800);
      expect(_inGame(find.text('Beyaz 2')), findsOneWidget);
      // Son oyunda sonraki yok: düğme eski hâlinde.
      await tester.tap(_inGame(find.byTooltip(t('lists.nextGame'))).first);
      await _wait(tester, 800);
      expect(_inGame(find.text('Beyaz 3')), findsOneWidget);
      await tester.tap(_inGame(find.byTooltip(t('game.toEnd'))));
      await _wait(tester, 300);
      expect(_inGame(find.byKey(const ValueKey('nextGameAtEnd'))),
          findsNothing);
    });
    testWidgets('motora karşı oyun bitince kartta "Yeni oyun" ve "Listeye kaydet"',
        (tester) async {
      // Eskiden ikisi de ⋮ menüsündeydi. Beyaz bir hamlede mat ediyor;
      // motora sıra gelmiyor.
      await _pumpGame(
        tester,
        const GameScreen(
          mode: GameMode.versusEngine,
          startFen: '6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1',
        ),
        size: const Size(480, 1000),
      );
      expect(find.text(t('game.newGame')), findsNothing);
      await _tapSquare(tester, 'a1');
      await _tapSquare(tester, 'a8');
      await _wait(tester, 600);
      expect(find.text(t('game.newGame')), findsOneWidget);
      expect(find.text(t('game.saveToList')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await _wait(tester, 1000);
    });

    testWidgets('serbest tahtada mat olunca o düğmeler yok', (tester) async {
      await _pumpGame(
        tester,
        const GameScreen(startFen: '6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1'),
        size: const Size(480, 1000),
      );
      await _tapSquare(tester, 'a1');
      await _tapSquare(tester, 'a8');
      await _wait(tester, 600);
      expect(find.text(t('game.newGame')), findsNothing);
    });
  });

  group('Açılış çalışma ekranı', () {
    testWidgets('varyantın adı üst çubukta değil, altındaki satırda tam',
        (tester) async {
      // 360 dp'de üst çubukta 80 piksel kalıyordu; "Najdorf Varyantı" 144.
      await _pumpGame(tester, OpeningStudyScreen(opening: _najdorf));
      expect(
          find.descendant(
              of: find.byType(AppBar),
              matching: find.text('Najdorf Varyantı')),
          findsNothing);
      final name = find.text('Najdorf Varyantı');
      expect(name, findsOneWidget);
      final paragraph = tester.renderObject<RenderParagraph>(name);
      expect(paragraph.didExceedMaxLines, isFalse, reason: 'ad kesilmemeli');
      expect(find.text('Sicilya Savunması'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await _wait(tester, 500);
    });

    testWidgets('varyantın sonunda "sona git" yerine sonraki varyant',
        (tester) async {
      await _pumpGame(
        tester,
        OpeningStudyScreen(opening: _najdorf, sequence: [_najdorf, _dragon]),
        size: const Size(480, 1000),
      );
      const key = ValueKey('nextVariationAtEnd');
      expect(find.byKey(key), findsNothing, reason: 'başta değil');
      await tester.tap(find.byIcon(Icons.last_page_rounded));
      await _wait(tester, 400);
      expect(find.byKey(key), findsOneWidget);
      await tester.tap(find.byKey(key));
      await _wait(tester, 800);
      expect(find.text('Ejderha Varyantı'), findsOneWidget);
      // Son varyantta sonraki yok.
      await tester.tap(find.byIcon(Icons.last_page_rounded));
      await _wait(tester, 400);
      expect(find.byKey(key), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await _wait(tester, 500);
    });

    testWidgets('son kullanılan kip hatırlanıyor', (tester) async {
      await _pumpGame(tester, OpeningStudyScreen(opening: _najdorf),
          size: const Size(480, 1000));
      StudyMode mode() => tester
          .widget<SegmentedButton<StudyMode>>(
              find.byType(SegmentedButton<StudyMode>))
          .selected
          .single;
      expect(mode(), StudyMode.watch);
      await tester.tap(find.text(t('openings.practice')));
      await _wait(tester, 400);
      expect(SettingsService.instance.openingPractice, isTrue);
      await tester.pumpWidget(const SizedBox());
      await _wait(tester, 500);

      // Başka bir varyant: eskiden yine "İzle"de açılıyordu.
      await _pumpGame(
          tester, OpeningStudyScreen(key: const ValueKey('2'), opening: _dragon),
          size: const Size(480, 1000));
      expect(mode(), StudyMode.practice);
      // Uygulama yeniden açılınca da.
      await SettingsService.instance.load();
      expect(SettingsService.instance.openingPractice, isTrue);
      await tester.pumpWidget(const SizedBox());
      await _wait(tester, 500);
    });
  });

  group('Hatırlanan seçimler', () {
    testWidgets('"Listeye kaydet" son kaydedilen listeyle açılıyor; '
        'serbest tahtanın adı tarihten', (tester) async {
      final storage = StorageService.instance;
      storage.resetCache();
      await storage.createPlaylist('Birinci');
      await _tickClock();
      final second = await storage.createPlaylist('İkinci');
      SettingsService.instance.lastSaveList = second.id;

      await _pumpGame(tester, const GameScreen(title: 'Serbest tahta'),
          size: const Size(480, 1000));
      await _tapSquare(tester, 'e2');
      await _tapSquare(tester, 'e4');
      await _wait(tester, 300);
      await tester.tap(find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(PopupMenuButton<String>),
      ));
      await _wait(tester, 500);
      await tester.tap(find.text(t('game.saveToList')));
      await _wait(tester, 600);
      expect(find.text('İkinci'), findsOneWidget,
          reason: 'son kaydedilen liste seçili gelmeli');
      final name =
          tester.widget<TextField>(find.byType(TextField)).controller!.text;
      expect(name, isNot('Serbest tahta'));
      expect(name, startsWith(t('game.defaultGameName', {'date': ''}).trim()));
    });

    testWidgets('uygulama son açık sekmede açılıyor (Ayarlar hariç)',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(480, 1000);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: HomeShell()));
      await _wait(tester, 400);
      await tester.tap(find.text(t('nav.lists')));
      await _wait(tester, 400);
      expect(SettingsService.instance.lastTab, 3);
      await tester.tap(find.text(t('nav.settings')));
      await _wait(tester, 400);
      expect(SettingsService.instance.lastTab, 3,
          reason: 'uygulama Ayarlar\'da açılmasın');
      await SettingsService.instance.load();
      expect(SettingsService.instance.lastTab, 3, reason: 'diske yazıldı');
      await tester.pumpWidget(const SizedBox());
      await _wait(tester, 500);
    });
  });

  group('Sözler ve boş durumlar', () {
    testWidgets('not varken menüde "Notu düzenle"', (tester) async {
      final withNote = _line('x', 'Notlu', const ['e2e4'], const ['e4'])
        ..note = 'bir not';
      await _pumpGame(tester, OpeningStudyScreen(opening: withNote),
          size: const Size(480, 1000));
      await tester.tap(find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(PopupMenuButton<String>),
      ));
      await _wait(tester, 500);
      expect(find.text(t('common.editNote')), findsOneWidget);
      expect(find.text(t('common.addNote')), findsNothing);
    });

    testWidgets('boş oyun listesinde PGN ekleme düğmesi', (tester) async {
      final storage = StorageService.instance;
      storage.resetCache();
      final list = await storage.createPlaylist('Boş');
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(480, 1000);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
          MaterialApp(home: PlaylistDetailScreen(playlistId: list.id)));
      await tester.pumpAndSettle();
      expect(
          find.widgetWithText(OutlinedButton, t('pgn.importIntoList')),
          findsOneWidget);
      expect(find.text(t('puzzles.continue')), findsNothing,
          reason: 'boş listede "Devam et" yok');
    });

    testWidgets('boş bulmaca listesinde üç ekleme yolu; süzgeç boşsa '
        '"Tümünü göster"', (tester) async {
      final service = PuzzleService.instance;
      final collection = await service.createCollection('Kitap');
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(480, 1000);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
          MaterialApp(home: PuzzleListScreen(collection: collection)));
      await tester.pumpAndSettle();
      for (final key in const [
        'puzzles.addPuzzle',
        'puzzles.pasteFenList',
        'puzzles.importFile',
      ]) {
        expect(find.widgetWithText(OutlinedButton, t(key)), findsOneWidget,
            reason: key);
      }

      await service.importFens(
          collection, '6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1');
      await tester.pumpWidget(MaterialApp(
          home: PuzzleListScreen(
              key: const ValueKey('dolu'), collection: collection)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('puzzles.filterSolved')));
      await tester.pumpAndSettle();
      expect(find.text(t('puzzles.emptyFilter')), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, t('puzzles.addPuzzle')),
          findsNothing, reason: 'istenen bulmaca eklemek değil');
      await tester.tap(find.widgetWithText(OutlinedButton, t('common.showAll')));
      await tester.pumpAndSettle();
      expect(find.text(t('puzzles.emptyFilter')), findsNothing);
    });

    testWidgets('aralık penceresinde kısa adlar', (tester) async {
      await _openList(tester);
      await tester.tap(find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(PopupMenuButton<String>),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('lists.markRange')));
      await tester.pumpAndSettle();
      expect(find.text(t('lists.rangeUnread')), findsOneWidget);
      expect(find.text(t('lists.markUnread')), findsNothing,
          reason: 'uzun ad dar telefonda iki satıra bölünüyordu');
    });
  });

  group('Görünüm', () {
    test('açık temada ikinci vurgu kendi açık zemininde okunuyor', () {
      // "Mat! Bulmaca tamam." gibi yazılar: renk, kendi %14 tonunun
      // üstünde. Eskiden 3,3:1.
      for (final look in AppLook.values) {
        final scheme = AppTheme.lightFor(look).colorScheme;
        final tint = Color.alphaBlend(
            scheme.secondary.withValues(alpha: 0.14), scheme.surface);
        expect(AppTheme.contrast(scheme.secondary, tint),
            greaterThanOrEqualTo(4.5),
            reason: look.id);
      }
    });

    testWidgets('açık temada liste kartındaki sonuç etiketi okunuyor',
        (tester) async {
      final storage = StorageService.instance;
      storage.resetCache();
      final list = await storage.createPlaylistWithGames('Sonuçlar', [
        for (final result in const ['1-0', '0-1', '1/2-1/2'])
          SavedGame(
            name: 'Oyun $result',
            uciMoves: const ['e2e4'],
            createdAt: DateTime(2026, 11, 24),
            white: 'A',
            black: 'B',
            result: result,
          ),
      ]);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(480, 1000);
      addTearDown(tester.view.reset);
      final theme = AppTheme.lightFor(AppLook.yesil);
      await tester.pumpWidget(MaterialApp(
          theme: theme, home: PlaylistDetailScreen(playlistId: list.id)));
      await tester.pumpAndSettle();
      for (final label in const ['1-0', '0-1', '½-½']) {
        final text = tester.widget<Text>(find.text(label));
        final chip = tester.widget<Container>(find
            .ancestor(of: find.text(label), matching: find.byType(Container))
            .first);
        final background = Color.alphaBlend(
            (chip.decoration! as BoxDecoration).color!,
            theme.colorScheme.surfaceContainer);
        expect(AppTheme.contrast(text.style!.color!, background),
            greaterThanOrEqualTo(4.5),
            reason: label);
      }
    });

    testWidgets('açılışta motor şeridi yeni konumu beklerken son skoru tutuyor',
        (tester) async {
      // Eskiden her hamlede gri "Motor düşünüyor…" yazısına dönüyordu.
      OpeningStudyScreen.debugAnalyze = (fen) async => const SearchResult(
            bestMoveUci: 'e2e4',
            scoreCp: 35,
            depth: 10,
            nodes: 1,
            pvUci: ['e2e4'],
          );
      addTearDown(() => OpeningStudyScreen.debugAnalyze = null);
      await _pumpGame(tester, OpeningStudyScreen(opening: _dragon),
          size: const Size(480, 1000));
      await tester.tap(find.byTooltip(t('game.analysisOn')));
      await _wait(tester, 300);
      expect(find.textContaining('+0.35'), findsOneWidget);
      // Sonraki hamle: yeni ölçüm 400 ms sonra isteniyor.
      await tester.tap(find.byTooltip(t('game.forward')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text(t('openings.engineThinking')), findsNothing);
      expect(find.textContaining('0.35'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await _wait(tester, 1000);
    });

    testWidgets('açılışta üst çubuk sırası oyun ekranıyla aynı: çevir, motor',
        (tester) async {
      await _pumpGame(tester, OpeningStudyScreen(opening: _dragon),
          size: const Size(480, 1000));
      final flip = tester.getCenter(find.byTooltip(t('common.flipBoard')));
      final engineButton =
          tester.getCenter(find.byTooltip(t('game.analysisOn')));
      expect(flip.dx, lessThan(engineButton.dx));
      await tester.pumpWidget(const SizedBox());
      await _wait(tester, 500);
    });
  });

  test('oyuncu süzgeci kartta görünen adı buluyor', () {
    // Eski kayıt: oyuncu alanları boş, ad "A - B" biçiminde.
    final game = SavedGame(
      name: 'Kasparov - Karpov',
      uciMoves: const ['e2e4'],
      createdAt: DateTime(2026, 11, 24),
    );
    expect(game.resolvedWhite, 'Kasparov');
    expect(const GameFilter(white: 'kasparov').matches(game), isTrue);
    expect(const GameFilter(black: 'karpov').matches(game), isTrue);
    expect(const GameFilter(white: 'karpov').matches(game), isFalse);
  });
}

/// Saatin bir adım ilerlemesini bekler: kimlikler saatten geliyor ve kaba
/// saatli sistemlerde (Windows) art arda eklenen iki kayıt çakışabiliyor.
Future<void> _tickClock() async {
  final before = DateTime.now().microsecondsSinceEpoch;
  while (DateTime.now().microsecondsSinceEpoch == before) {}
}
