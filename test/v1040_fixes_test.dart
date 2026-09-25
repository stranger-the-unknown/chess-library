import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/models/chess_engine.dart' as engine;
import 'package:chess_pgn_reader/models/puzzle.dart';
import 'package:chess_pgn_reader/screens/game_screen.dart';
import 'package:chess_pgn_reader/screens/openings/opening_list_screen.dart';
import 'package:chess_pgn_reader/screens/puzzles/puzzle_list_screen.dart';
import 'package:chess_pgn_reader/services/engine/engine_service.dart';
import 'package:chess_pgn_reader/services/engine/stockfish_uci.dart';
import 'package:chess_pgn_reader/services/opening_service.dart';
import 'package:chess_pgn_reader/services/puzzle_service.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/services/storage_service.dart';
import 'package:chess_pgn_reader/widgets/chess_board_widget.dart';

/// 10.4.0 öncesi bildirilen hatalar.

void _silencePlugins() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final channel in const [
    MethodChannel('com.ryanheise.just_audio.methods'),
    MethodChannel('dev.fluttercommunity.plus/wakelock'),
  ]) {
    messenger.setMockMethodCallHandler(channel, (call) async => null);
  }
}

Offset _squareCenter(WidgetTester tester, String square) {
  final board = tester.getRect(find.byType(ChessBoardWidget));
  final size = board.width / 8;
  final file = 'abcdefgh'.indexOf(square[0]);
  final rank = int.parse(square[1]);
  return Offset(
    board.left + (file + 0.5) * size,
    board.top + (8 - rank + 0.5) * size,
  );
}

Future<void> _play(WidgetTester tester, String from, String to) async {
  await tester.tapAt(_squareCenter(tester, from));
  await tester.pump();
  await tester.tapAt(_squareCenter(tester, to));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    _silencePlugins();
    SharedPreferences.setMockInitialValues({
      'flutter.soundEnabled': false,
      'flutter.hapticsEnabled': false,
      'flutter.animateMoves': false,
      'flutter.soundDefaultsRestored': true,
    });
    StorageService.instance.resetCache();
    PuzzleService.instance.resetCache();
    OpeningService.instance.resetCache();
    await SettingsService.instance.load();
    Strings.language = AppLanguage.turkish;
  });

  tearDown(() {
    Strings.language = AppLanguage.system;
    GameScreen.debugAnalyze = null;
  });

  group('Mat skoru', () {
    // Beyaz iki hamlede mat ediyordu; şerit sırasıyla "Beyaz mat ediyor
    // (2)", "(1)" ve mat olunca "Siyah mat ediyor (0)" yazıyordu.
    test('mat olmuş konumda mat edeni doğru yazıyor', () {
      expect(GameScreen.mateText(0, engine.Color.black), 'Beyaz mat etti');
      expect(GameScreen.mateText(0, engine.Color.white), 'Siyah mat etti');
    });

    test('mat yolundaki sayılar değişmedi', () {
      expect(GameScreen.mateText(2, engine.Color.white), 'Beyaz mat ediyor (2)');
      expect(GameScreen.mateText(-1, engine.Color.black), 'Beyaz mat ediyor (1)');
      expect(GameScreen.mateText(3, engine.Color.black), 'Siyah mat ediyor (3)');
      expect(GameScreen.mateText(-2, engine.Color.white), 'Siyah mat ediyor (2)');
    });

    test('"mate 0" sıradaki taraf için en kötü skor', () {
      // Eskiden +100000'di: beyaz mat edince skor çubuğu siyahı
      // kazanıyor gösteriyordu.
      final mated = StockfishUci.parseInfo('info depth 0 score mate 0')!;
      expect(mated.mateIn, 0);
      expect(mated.scoreCp, lessThan(-99000));

      final mating = StockfishUci.parseInfo(
        'info depth 12 score mate 2 pv h5f7',
      )!;
      expect(mating.scoreCp, greaterThan(99000));
      final beingMated = StockfishUci.parseInfo(
        'info depth 12 score mate -1 pv e8e7',
      )!;
      expect(beingMated.scoreCp, lessThan(-99000));
      expect(mated.scoreCp, lessThan(beingMated.scoreCp),
          reason: 'mat olmuş, mat olacak olandan kötü');
    });

    test('gerçek motor: mat olmuş konum', () async {
      StockfishUci.cachedBinaryPath = null;
      final path = await StockfishUci.resolveBinaryPath();
      if (path == null) {
        markTestSkipped('Stockfish ikilisi yok');
        return;
      }
      StockfishUci.cachedBinaryPath = path;
      addTearDown(() async {
        StockfishUci.cachedBinaryPath = null;
        await EngineService.instance.dispose();
      });
      // Aptal matı: 1.f3 e5 2.g4 Vh4#. Sıra beyazda, beyaz mat.
      const fen =
          'rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3';
      final result =
          await EngineService.instance.analyze(fen, depth: 10, movetimeMs: 300);
      expect(result.mateIn, 0);
      expect(result.scoreCp, lessThan(0));
      expect(GameScreen.mateText(result.mateIn!, engine.Color.white),
          'Siyah mat etti');
    });
  });

  group('Analiz tahtası', () {
    testWidgets('yeniden başlatınca analiz başlangıç konumunda sürüyor',
        (tester) async {
      // Eskiden motor duruyor ama analiz düğmesi basılı kalıyordu.
      final asked = <String>[];
      GameScreen.debugAnalyze = (fen) async {
        asked.add(fen);
        return const SearchResult(
          bestMoveUci: 'e2e4',
          scoreCp: 20,
          depth: 10,
          nodes: 1,
          pvUci: ['e2e4'],
        );
      };
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(480, 1000);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(
        home: GameScreen(title: 'Serbest'),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip(t('game.analysisOn')));
      await tester.pumpAndSettle();
      await _play(tester, 'e2', 'e4');
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      final start = engine.ChessGame().fen;
      asked.clear();

      await tester.tap(find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(PopupMenuButton<String>),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('game.restart')).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('game.restart')).last);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.byTooltip(t('game.analysisOff')), findsOneWidget,
          reason: 'düğme açık kalıyor');
      expect(asked, contains(start),
          reason: 'başlangıç konumu motora sorulmalı');
      expect(find.textContaining('+0.20'), findsOneWidget,
          reason: 'şeritte sonuç görünmeli');
    });
  });

  group('Açılış ekleme: alt alta varyantlar', () {
    test('1. hamleden başlayan her satır ayrı varyant', () {
      final drafts = OpeningService.splitVariations(
        '1. e4 e5 2. Nf3 Nc6\n1. d4 d5 2. c4\n1.c4 e5',
      );
      expect(drafts, hasLength(3));
    });

    test('satırlara bölünmüş PGN tek oyun kalıyor', () {
      final drafts = OpeningService.splitVariations(
        '[Event "Deneme"]\n[White "A"]\n\n'
        '1. e4 e5 2. Nf3 Nc6 3. Bb5 a6\n4. Ba4 Nf6 5. O-O Be7\n6. Re1 b5',
      );
      expect(drafts, hasLength(1));
      expect(drafts.single.moves, contains('Re1'));
    });

    test('numarasız satırlar: devam edemeyen satır yeni varyant', () {
      final drafts = OpeningService.splitVariations('e4 e5 Nf3\ne4 c5');
      expect(drafts, hasLength(2));
    });

    test('boş satır ve "ad |" yeni varyant başlatıyor', () {
      final drafts = OpeningService.splitVariations(
        'e4 e5\n\nNf3 d5\nNajdorf | e4 c5 Nf3 d6',
      );
      expect(drafts, hasLength(3));
      expect(drafts[2].name, 'Najdorf');
    });

    test('adlar: satırın adı, formdaki ad + sıra, geçersiz satır sayılıyor',
        () async {
      final result = await OpeningService.instance.addManyFromSan(
        family: 'Deneme',
        variation: 'Ana hat',
        moveText: '1. e4 e5\nÖzel | 1. d4 d5\n1. c4 c5\n1. Zz9',
      );
      expect(result.added.map((o) => o.variation),
          ['Ana hat 1', 'Özel', 'Ana hat 2']);
      expect(result.skipped, 1);
      expect(result.truncated, 0);
      expect(result.added.every((o) => o.family == 'Deneme'), isTrue);
      expect(await OpeningService.instance.all(), hasLength(3));
    });

    test('tek satır eskisi gibi: formdaki ad olduğu gibi', () async {
      final result = await OpeningService.instance.addManyFromSan(
        family: 'İspanyol',
        variation: 'Breyer',
        moveText: '1. e4 e5 2. Nf3 Nc6 3. Bb5 a6',
      );
      expect(result.added.single.variation, 'Breyer');
      expect(result.added.single.sanMoves, hasLength(6));
    });

    test('geçersiz hamlede kesilen varyant sayılıyor', () async {
      final result = await OpeningService.instance.addManyFromSan(
        family: '',
        variation: '',
        moveText: '1. e4 e5 2. Nf3 Nc6 3. Bz9 a6\n1. d4 d5',
      );
      expect(result.added, hasLength(2));
      expect(result.added.first.sanMoves, hasLength(4));
      expect(result.truncated, 1);
    });

    testWidgets('formda iki satır iki varyant ekliyor', (tester) async {
      // Eskiden ikinci satır sessizce atılıyor, "10 hamlelik varyant
      // eklendi" deniyordu.
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(480, 1000);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: OpeningListScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text(t('openings.addOwn')).first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, t('openings.family')),
        'Deneme',
      );
      await tester.enterText(
        find.widgetWithText(TextField, t('openings.moves')),
        '1. e4 e5 2. Nf3 Nc6\n1. d4 d5 2. c4 e6',
      );
      await tester.tap(find.text(t('common.add')));
      await tester.pumpAndSettle();

      final all = await OpeningService.instance.all();
      expect(all, hasLength(2));
      expect(find.text(t('openings.imported', {'count': 2})), findsOneWidget);
    });
  });

  group('Oyun sonu süzgeçleri', () {
    Future<void> pumpList(WidgetTester tester) async {
      final puzzles = [
        Puzzle(id: 'e#1', fen: '8/8/8/8/8/4k3/4P3/4K3 w - - 0 1',
            title: 'Bir', tags: ['beyaz-kazanir']),
        Puzzle(id: 'e#2', fen: '8/8/8/8/8/4k3/4P3/4K3 w - - 0 1',
            title: 'İki', tags: ['beyaz-kazanir']),
        Puzzle(id: 'e#3', fen: '8/8/8/8/8/4k3/4P3/4K3 w - - 0 1',
            title: 'Üç', tags: ['beraberlik']),
        Puzzle(id: 'e#4', fen: '8/8/8/8/8/4k3/4P3/4K3 w - - 0 1',
            title: 'Dört', tags: ['siyah-kazanir']),
      ];
      final collection = PuzzleCollection(
        id: 'e',
        name: 'Oyun sonları',
        isEndgame: true,
        puzzles: puzzles,
      );
      await PuzzleService.instance.markSolved('e#1');
      tester.view.devicePixelRatio = 1;
      // Geniş pencere: yedi süzgeç çipinin hepsi ekranda.
      tester.view.physicalSize = const Size(1300, 1000);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(home: PuzzleListScreen(collection: collection)),
      );
      await tester.pumpAndSettle();
    }

    bool shown(String title) => find.textContaining(title).evaluate().isNotEmpty;

    testWidgets('durum ve sonuç birlikte seçilebiliyor', (tester) async {
      await pumpList(tester);
      await tester.tap(find.text(t('puzzles.filterUnsolved')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('puzzles.filterWhiteWin')));
      await tester.pumpAndSettle();

      // Çözülmemiş VE beyaz kazanır: yalnızca "İki".
      expect(shown('İki'), isTrue);
      expect(shown('Bir'), isFalse, reason: 'çözülmüş');
      expect(shown('Üç'), isFalse, reason: 'beraberlik');
      expect(shown('Dört'), isFalse, reason: 'siyah kazanır');
    });

    testWidgets('seçili sonuca yeniden dokununca kalkıyor, durum kalıyor',
        (tester) async {
      await pumpList(tester);
      await tester.tap(find.text(t('puzzles.filterUnsolved')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('puzzles.filterDraw')));
      await tester.pumpAndSettle();
      expect(shown('Üç'), isTrue);
      expect(shown('İki'), isFalse);

      await tester.tap(find.text(t('puzzles.filterDraw')));
      await tester.pumpAndSettle();
      // Sonuç kalktı; "çözülmemiş" sürüyor.
      expect(shown('İki'), isTrue);
      expect(shown('Üç'), isTrue);
      expect(shown('Dört'), isTrue);
      expect(shown('Bir'), isFalse, reason: 'çözülmemiş süzgeci sürmeli');
    });

    testWidgets('sonuç seçiliyken "Tümü" sonucu bırakıyor', (tester) async {
      await pumpList(tester);
      await tester.tap(find.text(t('puzzles.filterBlackWin')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('puzzles.filterSolved')));
      await tester.pumpAndSettle();
      expect(shown('Dört'), isFalse, reason: 'çözülmüş değil');
      await tester.tap(find.text(t('puzzles.filterAll')));
      await tester.pumpAndSettle();
      expect(shown('Dört'), isTrue);
      expect(shown('Bir'), isFalse, reason: 'siyah kazanır süzgeci sürmeli');
    });
  });
}
