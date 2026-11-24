import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/models/chess_engine.dart' as engine;
import 'package:chess_pgn_reader/models/opening.dart';
import 'package:chess_pgn_reader/models/pgn_parser.dart';
import 'package:chess_pgn_reader/models/playlist.dart';
import 'package:chess_pgn_reader/models/puzzle.dart';
import 'package:chess_pgn_reader/screens/game_screen.dart';
import 'package:chess_pgn_reader/screens/openings/opening_list_screen.dart';
import 'package:chess_pgn_reader/screens/openings/opening_study_screen.dart';
import 'package:chess_pgn_reader/screens/playlist_detail_screen.dart';
import 'package:chess_pgn_reader/screens/puzzles/puzzle_solve_screen.dart';
import 'package:chess_pgn_reader/services/engine/search_result.dart';
import 'package:chess_pgn_reader/services/opening_service.dart';
import 'package:chess_pgn_reader/services/pgn_import_service.dart';
import 'package:chess_pgn_reader/services/puzzle_service.dart';
import 'package:chess_pgn_reader/services/screen_awake.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/services/storage_service.dart';
import 'package:chess_pgn_reader/theme/app_look.dart';
import 'package:chess_pgn_reader/theme/app_theme.dart';
import 'package:chess_pgn_reader/widgets/chess_board_widget.dart';
import 'package:chess_pgn_reader/widgets/move_list.dart';

/// 10.13.0: kullanıcının notu ve uygulamanın baştan sona gözden
/// geçirilmesinde (24 Kasım 2026) bulunan hatalar. Her test, düzeltmeden
/// önceki kodda düşüyordu.

const _blackToMove = '6k1/5ppp/8/8/8/8/5PPP/R5K1 b - - 0 1';
const _whiteToMove = '6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1';

Future<SearchResult> _noEngine(String fen,
        {required int depth, required int movetimeMs}) async =>
    SearchResult.empty;

Future<void> _wait(WidgetTester tester, [int ms = 1000]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _openPuzzle(WidgetTester tester, String fen) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(480, 1000);
  addTearDown(tester.view.reset);
  final puzzle = Puzzle(id: 'c1#1', fen: fen);
  final collection =
      PuzzleCollection(id: 'c1', name: 'Deneme', puzzles: [puzzle]);
  await tester.pumpWidget(MaterialApp(
    home: PuzzleSolveScreen(
      collection: collection,
      puzzles: [puzzle],
      initialIndex: 0,
    ),
  ));
  await _wait(tester, 300);
}

/// Bulmacanın ⋮ menüsünden "Analiz tahtasında aç"; açılan tahta.
Future<ChessBoardWidget> _openAnalysis(WidgetTester tester) async {
  await tester.tap(find.descendant(
    of: find.byType(AppBar),
    matching: find.byType(PopupMenuButton<String>),
  ));
  await _wait(tester, 500);
  await tester.tap(find.text(t('common.openInAnalysis')));
  await _wait(tester, 800);
  return tester.widget<ChessBoardWidget>(find.descendant(
    of: find.byType(GameScreen),
    matching: find.byType(ChessBoardWidget),
  ));
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'flutter.soundEnabled': false,
      'flutter.hapticsEnabled': false,
      'flutter.animateMoves': false,
      'flutter.soundDefaultsRestored': true,
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dev.fluttercommunity.plus/wakelock'),
            (c) async => null);
    Strings.language = AppLanguage.turkish;
    await SettingsService.instance.load();
    PuzzleService.instance.resetCache();
    PuzzleSolveScreen.debugAnalyze = _noEngine;
  });

  tearDown(() {
    PuzzleSolveScreen.debugAnalyze = null;
    Strings.language = AppLanguage.system;
  });

  group('Bulmacadan analiz tahtası', () {
    testWidgets('siyah çözüyorsa tahta siyahın gözünden açılıyor',
        (tester) async {
      await _openPuzzle(tester, _blackToMove);
      final board = await _openAnalysis(tester);
      expect(board.flipped, isTrue);
    });

    testWidgets('beyaz çözüyorsa beyazın gözünden', (tester) async {
      await _openPuzzle(tester, _whiteToMove);
      final board = await _openAnalysis(tester);
      expect(board.flipped, isFalse);
    });

    testWidgets('tahta elle çevrildiyse o yönde', (tester) async {
      await _openPuzzle(tester, _whiteToMove);
      await tester.tap(find.byTooltip(t('common.flipBoard')));
      await _wait(tester, 200);
      final board = await _openAnalysis(tester);
      expect(board.flipped, isTrue, reason: 'bulmacada görünen yön');
    });
  });

  // -----------------------------------------------------------------------
  // Ekranı açık tutma
  // -----------------------------------------------------------------------

  test('ekran kilidi: iki ekran üst üste binince son bırakana kadar açık',
      () {
    final calls = <bool>[];
    ScreenAwake.debugPlatform = calls.add;
    addTearDown(() => ScreenAwake.debugPlatform = null);
    final first = ScreenAwake();
    final second = ScreenAwake();
    first.keep();
    second.keep(); // listede sonraki oyun: yeni ekran kuruldu
    first.release(); // eski ekran aynı karenin sonunda kapandı
    expect(calls, [true], reason: 'kilit yeni ekranın elinden alınmadı');
    second.release();
    expect(calls, [true, false]);
    first.release();
    expect(calls, [true, false], reason: 'çift bırakma zararsız');
  });

  // -----------------------------------------------------------------------
  // PGN
  // -----------------------------------------------------------------------

  group('PGN okuma', () {
    test('fazladan ayrıştırılmış hamle oyunu bozmuyor (Nge7)', () {
      // 4... Nge7: c6'daki at açmazda, yalın yazımı "Ne7". Eskiden hamle
      // atlanıyor, oyunun geri kalanı yanlış konumdan okunuyordu.
      final parser = PgnParser();
      expect(
        parser.parse('1. e4 e5 2. Nf3 Nc6 3. Bb5 d6 4. d4 Nge7 5. O-O a6 *'),
        isTrue,
      );
      expect(parser.skippedTokens, isEmpty);
      expect(parser.moves, [
        'e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1b5',
        'd7d6', 'd2d4', 'g8e7', 'e1g1', 'a7a6',
      ]);
    });

    test('uzun yazım okunuyor; belirsiz hamle yine okunmuyor', () {
      final long = PgnParser()..parse('1. e2-e4 e7e5 2. Ng1f3 Nb8-c6 *');
      expect(long.skippedTokens, isEmpty);
      expect(long.moves, ['e2e4', 'e7e5', 'g1f3', 'b8c6']);

      // İki at da d2'ye gidebiliyor: "Nd2" hangisi olduğunu söylemiyor.
      final vague = PgnParser()..parse('1. Nf3 d5 2. d3 d4 3. Nd2 *');
      expect(vague.skippedTokens, ['Nd2']);
    });

    test('değerinde köşeli ayraç olan başlık hamlelere karışmıyor', () {
      final games = PgnParser.parseAll(
        '[Event "Titled Tuesday [Early] 2024"]\n[White "A"]\n[Black "B"]\n'
        '[Result "1-0"]\n\n1. e4 e5 2. Nf3 1-0\n',
      );
      expect(games, hasLength(1));
      expect(games.single.skippedCount, 0);
      expect(games.single.uciMoves, ['e2e4', 'e7e5', 'g1f3']);

      // Artıkta açık parantez kalınca oyunun tamamı yutuluyordu.
      final open = PgnParser.parseAll(
        '[Event "Open [A] (U18"]\n[White "A"]\n[Black "B"]\n\n1. e4 e5 *\n',
      );
      expect(open, hasLength(1));
      expect(open.single.uciMoves, ['e2e4', 'e7e5']);

      // Yorumdaki tek "[" sonraki "[%clk]"e kadar hamleleri silmiyor.
      final clock = PgnParser()
        ..parse('1. e4 {[ not} e5 {[%clk 0:01:00]} 2. Nf3 *');
      expect(clock.skippedTokens, isEmpty);
      expect(clock.moves, ['e2e4', 'e7e5', 'g1f3']);
    });

    test('hamle olmayan işaretler "okunamayan hamle" sayılmıyor', () {
      for (final text in [
        '1. e4 e5 2. Nf3 ! Nc6 *',
        '1. e4 d5 2. e5 f5 3. exf6 e.p. Nxf6 *',
        '1. d4 Nf6 2. c4 +- e6 *',
        '1. e4 e5 1/2 - 1/2',
      ]) {
        final parser = PgnParser()..parse(text);
        expect(parser.skippedTokens, isEmpty, reason: text);
      }
      final spaced = PgnParser()..parse('1. e4 e5 1/2 - 1/2');
      expect(spaced.gameResult, '1/2-1/2');

      // Numaraya yapışık noktalar hamleyi düşürmüyor.
      const black =
          '[FEN "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1"]\n\n';
      for (final body in ['1. ...e5 2. Nf3 *', '1. ... e5 2. Nf3 *']) {
        final parser = PgnParser()..parse('$black$body');
        expect(parser.skippedTokens, isEmpty, reason: body);
        expect(parser.moves, ['e7e5', 'g1f3'], reason: body);
      }
    });

    test('reddedilmiş FEN başlığı dışa aktarılmıyor', () {
      final pgn = PgnParser.buildPgn(
        uciMoves: const ['e2e4'],
        tags: const {'FEN': 'okunamayan konum', 'SetUp': '1'},
      );
      expect(pgn, isNot(contains('[FEN')));
      expect(pgn, isNot(contains('[SetUp')));
    });

    test('liste dışa aktarımı: eski "A - B" adlı oyunda oyuncular ayrılıyor',
        () {
      final playlist = Playlist(name: 'Liste', games: [
        SavedGame(
          name: 'Ali - Veli',
          uciMoves: const ['e2e4'],
          createdAt: DateTime(2026, 1, 2),
        ),
      ]);
      final pgn = buildListPgn(playlist);
      expect(pgn, contains('[White "Ali"]'));
      expect(pgn, contains('[Black "Veli"]'));
      expect(pgn, isNot(contains('[White "Ali - Veli"]')));
    });
  });

  // -----------------------------------------------------------------------
  // Bulmaca ve açılış verisi
  // -----------------------------------------------------------------------

  group('Veri', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      PuzzleService.instance.resetCache();
      OpeningService.instance.resetCache();
    });

    test('silinen bulmaca notu geri gelmiyor', () async {
      final service = PuzzleService.instance;
      final list = await service.createCollection('Liste');
      await service.addPuzzle(list, fen: _whiteToMove);
      var puzzle = (await service.puzzlesOf(list)).single;
      await service.updatePuzzle(list, puzzle,
          fen: puzzle.fen, title: puzzle.title, note: 'abc');
      // Çözme ekranı elindeki nesneyi de güncelliyor; o nesne temel kayıt.
      puzzle.note = 'abc';
      puzzle = (await service.puzzlesOf(list)).single;
      expect(puzzle.note, 'abc');

      await service.updatePuzzle(list, puzzle,
          fen: puzzle.fen, title: puzzle.title, note: null);
      expect((await service.puzzlesOf(list)).single.note, isNull,
          reason: 'liste yeniden okununca not geri gelmemeli');
    });

    test('ilerlemeyi sıfırlamak favorileri silmiyor', () async {
      final service = PuzzleService.instance;
      final list = await service.createCollection('Liste');
      final first = await service.addPuzzle(list, fen: _whiteToMove);
      await _tick();
      final second = await service.addPuzzle(list, fen: _blackToMove);
      expect(first.id, isNot(second.id));
      await service.toggleFavorite(first.id);
      await service.markSolved(first.id);
      await service.markSolved(second.id);

      await service.resetProgress(list.id);
      final progress = await service.progressMap();
      expect(progress[first.id]?.favorite, isTrue, reason: 'yıldız duruyor');
      expect(progress[first.id]?.solved, isFalse);
      expect(progress[second.id]?.solved ?? false, isFalse);
    });

    test('kayıt yokken bulmaca listelerini okumak depoya yazmıyor', () async {
      await PuzzleService.instance.collections();
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getKeys().where((key) => key.contains('puzzle_collections')),
        isEmpty,
        reason: 'boş liste yazılırsa masaüstünde gerçek dosyanın üstüne '
            'yazılabiliyor',
      );
    });

    test('silinen açılış notu yeniden açılışta geri gelmiyor', () async {
      final service = OpeningService.instance;
      final line = (await service.addFromSan(
          family: 'Açık', variation: 'a1', moveText: '1. e4 e5'))!;
      await service.setNote(line.id, 'abc');
      await service.all(); // notu bellekteki kayda kopyalar
      await _tick();
      // Liste kaydedilir: not varyantın kendi kaydına da yazılır.
      await service.addFromSan(
          family: 'Açık', variation: 'a2', moveText: '1. e4 e5 2. Nf3');

      await service.setNote(line.id, '');
      service.resetCache(); // uygulama yeniden açıldı
      final again =
          (await service.all()).firstWhere((o) => o.id == line.id);
      expect(again.note, isNull);
    });
  });

  // -----------------------------------------------------------------------
  // Ekranlar
  // -----------------------------------------------------------------------

  testWidgets('mat bulmacası: bir hamle geç mat eden hamle "Doğru" değil',
      (tester) async {
    // 1 hamlede mat (Ra8#). Ra7 mat etmiyor; motor "rakip 1 hamlede mat
    // oluyor" diyor, yani toplam 2 hamle. Eskiden kabul ediliyordu.
    PuzzleSolveScreen.debugAnalyze = (fen,
            {required int depth, required int movetimeMs}) async =>
        const SearchResult(
          bestMoveUci: 'g8h8',
          scoreCp: -99999,
          mateIn: -1,
          depth: 12,
          nodes: 1,
          pvUci: ['g8h8'],
        );
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(480, 1000);
    addTearDown(tester.view.reset);
    final puzzle =
        Puzzle(id: 'c1#m', fen: _whiteToMove, solution: const ['a1a8']);
    await tester.pumpWidget(MaterialApp(
      home: PuzzleSolveScreen(
        collection:
            PuzzleCollection(id: 'c1', name: 'Deneme', puzzles: [puzzle]),
        puzzles: [puzzle],
        initialIndex: 0,
      ),
    ));
    await _wait(tester, 300);
    await _tapSquare(tester, 'a1');
    await _tapSquare(tester, 'a7');
    await _wait(tester, 600);
    expect(find.text(t('puzzles.wrong', {'move': 'Ra7'})), findsOneWidget);
    expect(find.text(t('puzzles.correct', {'move': 'Ra7'})), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await _wait(tester, 4000);
  });

  testWidgets('açılış alıştırması: cevap beklenirken "Göster" sırayı kaydırmıyor',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(480, 1000);
    addTearDown(tester.view.reset);
    final position = engine.ChessGame();
    final san = <String>[];
    const uci = ['e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1c4', 'f8c5'];
    for (final move in uci) {
      final parsed = position.moveFromUci(move)!;
      san.add(position.sanFor(parsed));
      position.makeMove(parsed);
    }
    await tester.pumpWidget(MaterialApp(
      home: OpeningStudyScreen(
        opening: Opening(
          id: 'o',
          eco: 'C50',
          family: 'İtalyan',
          variation: 'Giuoco Piano',
          uciMoves: uci,
          sanMoves: san,
          custom: true,
        ),
      ),
    ));
    await _wait(tester, 300);
    await tester.tap(find.text(t('openings.practice')));
    await _wait(tester, 300);

    await tester.tap(find.text(t('openings.show'))); // e4, cevap 700 ms sonra
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text(t('openings.show'))); // cevabı öne alır
    await _wait(tester, 2000);

    final board =
        tester.widget<ChessBoardWidget>(find.byType(ChessBoardWidget));
    expect(tester.widget<MoveList>(find.byType(MoveList)).currentIndex, 1,
        reason: 'e4 ve cevabı e5; kullanıcının hamlesi oynanmadı');
    expect(board.game.sideToMove, engine.Color.white, reason: 'sıra bende');
    await tester.pumpWidget(const SizedBox());
    await _wait(tester, 2000);
  });

  testWidgets('kayıtlı oyunda FEN yapıştırınca tahta serbest kalıyor',
      (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => call.method == 'Clipboard.getData'
          ? <String, dynamic>{'text': engine.ChessGame().fen}
          : null,
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(480, 1000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
      home: GameScreen(
        uciMoves: ['d2d4', 'd7d5', 'c2c4'],
        title: 'A - B',
        whiteName: 'A',
        blackName: 'B',
      ),
    ));
    await _wait(tester, 300);
    await tester.tap(find.descendant(
      of: find.byType(AppBar),
      matching: find.byType(PopupMenuButton<String>),
    ));
    await _wait(tester, 500);
    await tester.tap(find.text(t('common.pasteFen')));
    await _wait(tester, 500);

    await _tapSquare(tester, 'e2');
    await _tapSquare(tester, 'e4');
    await _wait(tester, 300);
    await _tapSquare(tester, 'e7');
    await _tapSquare(tester, 'e5');
    await _wait(tester, 300);
    // Eskiden ikinci hamle "deneme hamlesi" oluyordu: listede tek hamle.
    expect(tester.widget<MoveList>(find.byType(MoveList)).moves, hasLength(2));
    await tester.pumpWidget(const SizedBox());
    await _wait(tester, 2000);
  });

  testWidgets('"PGN kopyala" oyuncuları ve oyunun tarihini yazıyor',
      (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(480, 1000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
      home: GameScreen(
        uciMoves: ['e2e4', 'e7e5'],
        title: 'Fischer - Spassky',
        whiteName: 'Fischer',
        blackName: 'Spassky',
        pgnTags: {'Event': 'Dünya Şampiyonası', 'Date': '1972.07.11'},
      ),
    ));
    await _wait(tester, 300);
    await tester.tap(find.descendant(
      of: find.byType(AppBar),
      matching: find.byType(PopupMenuButton<String>),
    ));
    await _wait(tester, 500);
    await tester.tap(find.text(t('game.copyPgn')));
    await _wait(tester, 500);
    expect(copied, contains('[White "Fischer"]'));
    expect(copied, contains('[Black "Spassky"]'));
    expect(copied, contains('[Date "1972.07.11"]'));
    expect(copied, contains('[Event "Dünya Şampiyonası"]'));
    await tester.pumpWidget(const SizedBox());
    await _wait(tester, 4000);
  });

  testWidgets('açılış araması Türkçe harfleri katlıyor', (tester) async {
    SharedPreferences.setMockInitialValues({});
    OpeningService.instance.resetCache();
    await OpeningService.instance.addFromSan(
        family: 'Şah Hint', variation: 'Klasik', moveText: '1. d4');
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(700, 1100);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: OpeningListScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Şah Hint'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'sah hint');
    await tester.pumpAndSettle();
    expect(find.text('Şah Hint'), findsOneWidget,
        reason: '"sah hint" yazınca "Şah Hint" bulunmalı');
  });

  testWidgets('"Tümünü okunmadı işaretle" önce soruyor', (tester) async {
    // Menüde "Tümünü okundu" ile "Tümünü okunmadı" alt alta; yanlışına
    // dokununca yüzlerce oyunun işareti geri alınamadan gidiyordu.
    final storage = StorageService.instance;
    storage.resetCache();
    final list = await storage.createPlaylistWithGames('Okunanlar', [
      for (var i = 1; i <= 3; i++)
        SavedGame(
          name: 'Oyun $i',
          uciMoves: const ['e2e4', 'e7e5'],
          createdAt: DateTime(2026, 11, i),
          white: 'Beyaz $i',
          black: 'Siyah $i',
        ),
    ]);
    await storage.setAllRead(list.id, true);
    Future<int> readCount() async => (await storage.loadPlaylists())
        .firstWhere((p) => p.id == list.id)
        .games
        .where((g) => g.read)
        .length;
    expect(await readCount(), 3);

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(700, 1100);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        MaterialApp(home: PlaylistDetailScreen(playlistId: list.id)));
    await tester.pumpAndSettle();

    Future<void> choose() async {
      await tester.tap(find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(PopupMenuButton<String>),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('lists.markAllUnread')));
      await tester.pumpAndSettle();
    }

    await choose();
    expect(find.text(t('lists.markAllUnreadMessage', {'count': 3})),
        findsOneWidget);
    expect(await readCount(), 3, reason: 'sormadan silmemeli');
    await tester.tap(find.text(t('common.giveUp')));
    await tester.pumpAndSettle();
    expect(await readCount(), 3, reason: 'vazgeçince işaretler duruyor');

    await choose();
    await tester.tap(find.text(t('openings.mark')));
    await tester.pumpAndSettle();
    expect(await readCount(), 0);
  });

  testWidgets('listeden açılan oyunda okundu ve favori işaretlenebiliyor',
      (tester) async {
    // Oyunu bitirince işaretlemek için listeye dönmek gerekiyordu.
    final storage = StorageService.instance;
    storage.resetCache();
    final list = await storage.createPlaylistWithGames('Okuma', [
      for (var i = 1; i <= 2; i++)
        SavedGame(
          name: 'Oyun $i',
          uciMoves: const ['e2e4', 'e7e5'],
          createdAt: DateTime(2026, 11, i),
          white: 'Beyaz $i',
          black: 'Siyah $i',
        ),
    ]);
    Future<SavedGame> stored(int i) async => (await storage.loadPlaylists())
        .firstWhere((p) => p.id == list.id)
        .games[i];

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(480, 1000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        MaterialApp(home: PlaylistDetailScreen(playlistId: list.id)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beyaz 1'));
    await _wait(tester, 800);
    final screen = find.byType(GameScreen);
    expect(screen, findsOneWidget);
    Finder button(String key) => find.descendant(
        of: screen, matching: find.byTooltip(t(key)));

    await tester.tap(button('lists.markRead'));
    await _wait(tester, 300);
    expect((await stored(0)).read, isTrue);
    expect(button('lists.markUnread'), findsOneWidget,
        reason: 'düğme yeni durumu göstermeli');
    await tester.tap(button('common.favoriteAdd'));
    await _wait(tester, 300);
    expect((await stored(0)).favorite, isTrue);
    expect(button('common.favoriteRemove'), findsOneWidget);

    // Sonraki oyun kendi işaretleriyle açılıyor.
    await tester.tap(button('lists.nextGame'));
    await _wait(tester, 800);
    expect(button('lists.markRead'), findsOneWidget);
    expect(button('common.favoriteAdd'), findsOneWidget);
    expect((await stored(1)).read, isFalse);

    // Geri alınabiliyor.
    await tester.tap(button('lists.previousGame'));
    await _wait(tester, 800);
    await tester.tap(button('lists.markUnread'));
    await _wait(tester, 300);
    expect((await stored(0)).read, isFalse);
    expect((await stored(0)).favorite, isTrue);
  });

  test('açık temada doğru / yanlış / uyarı renkleri zeminde okunuyor', () {
    // Tek renk iki temada kullanılıyordu: açık zeminde "Doğru!" yazısı
    // 2,1:1, favori yıldızı 2:1 karşıtlıkla neredeyse görünmüyordu.
    for (final look in AppLook.values) {
      final scheme = AppTheme.lightFor(look).colorScheme;
      for (final entry in {
        'doğru': scheme.correct,
        'yanlış': scheme.wrong,
        'uyarı': scheme.warning,
      }.entries) {
        expect(AppTheme.contrast(entry.value, scheme.surface),
            greaterThanOrEqualTo(4.5),
            reason: '${look.id}: ${entry.key} rengi açık zeminde');
      }
    }
  });

  test('Türkçe büyük harf: i → İ, ı → I', () {
    Strings.language = AppLanguage.turkish;
    expect(Strings.upper('Veri'), 'VERİ');
    expect(Strings.upper('Ses ve titreşim'), 'SES VE TİTREŞİM');
    expect(Strings.upper('Açılış'), 'AÇILIŞ');
    Strings.language = AppLanguage.english;
    expect(Strings.upper('Engine'), 'ENGINE');
  });
}

/// Saatin bir adım ilerlemesini bekler: kimlikler saatten geliyor ve kaba
/// saatli sistemlerde (Windows) art arda eklenen iki kayıt çakışabiliyor.
Future<void> _tick() async {
  final before = DateTime.now().microsecondsSinceEpoch;
  while (DateTime.now().microsecondsSinceEpoch == before) {}
}

Future<void> _tapSquare(WidgetTester tester, String square) async {
  final rect = tester.getRect(find.byType(ChessBoardWidget));
  final s = rect.width / 8;
  await tester.tapAt(Offset(
    rect.left + ('abcdefgh'.indexOf(square[0]) + 0.5) * s,
    rect.top + (8 - int.parse(square[1]) + 0.5) * s,
  ));
  await tester.pump();
}
