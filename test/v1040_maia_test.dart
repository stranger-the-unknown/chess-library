import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/models/chess_engine.dart' as engine;
import 'package:chess_pgn_reader/screens/game_screen.dart';
import 'package:chess_pgn_reader/screens/home_screen.dart';
import 'package:chess_pgn_reader/services/engine/engine_service.dart';
import 'package:chess_pgn_reader/services/engine/maia/maia_player.dart';
import 'package:chess_pgn_reader/services/engine/stockfish_uci.dart';
import 'package:chess_pgn_reader/services/opening_service.dart';
import 'package:chess_pgn_reader/services/puzzle_service.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/services/storage_service.dart';
import 'package:chess_pgn_reader/widgets/chess_board_widget.dart';

/// 10.4.0: insan gibi rakip (Maia).
///
/// Stockfish'in alt kademeleri en iyi hamleyi arayıp arada rastgele büyük
/// hatalar yapıyordu; düşük seviyede oynayan biri için insan gibi
/// değildi. Artık 800–2400 arası dokuz Maia seviyesi var, üstte iki
/// Stockfish seviyesi (Uzman, Usta) kalıyor.
const _weights = 'assets/maia/maia3-5m.bin';
const _start = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

Set<String> _legal(String fen) =>
    engine.ChessGame.fromFen(fen).allLegalMoves().map((m) => m.uci).toSet();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final weightsAvailable = File(_weights).existsSync();
  // Uygulamanın kendi yükleyicisi (varlık paketinden); testler değiştiriyor.
  final bundleLoader = MaiaPlayer.loadBytes;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.load();
    // Ayar yüklenince dil sistemin diline dönüyor; ondan sonra.
    Strings.language = AppLanguage.turkish;
  });

  tearDown(() {
    Strings.language = AppLanguage.system;
  });

  group('Seviye listesi', () {
    test('dokuz Maia seviyesi, üstte Uzman ve Usta', () {
      final all = EngineLevel.all;
      expect(all, hasLength(11));
      for (var i = 0; i < all.length; i++) {
        expect(all[i].index, i, reason: 'ayarda saklanan numara sırayla aynı');
      }
      expect(
        [for (final l in all) l.maiaElo],
        [800, 1000, 1200, 1400, 1600, 1800, 2000, 2200, 2400, null, null],
      );
      expect(all[9].isFullStrength, isFalse);
      expect(all[10].isFullStrength, isTrue);
      expect(EngineLevel.all[EngineLevel.defaultIndex].maiaElo, 1200);
    });

    test('her seviyenin adı ve açıklaması iki dilde de var', () {
      for (final language in [AppLanguage.turkish, AppLanguage.english]) {
        Strings.language = language;
        for (final level in EngineLevel.all) {
          for (final text in [
            level.name,
            level.description,
            level.opponentLabel,
          ]) {
            expect(text, isNot(startsWith('level.')), reason: '$language');
            expect(text, isNot(startsWith('game.')), reason: '$language');
            expect(text, isNot(contains('{')), reason: '$language');
          }
        }
      }
    });

    test('oyun ekranında rakibin adı', () {
      expect(EngineLevel.all[3].opponentLabel, 'Maia · 1400');
      expect(EngineLevel.all[9].opponentLabel, 'Motor · Uzman');
      Strings.language = AppLanguage.english;
      expect(EngineLevel.all[10].opponentLabel, 'Engine · Master');
    });
  });

  group('Eski ayarın taşınması', () {
    test('ayar yoksa Maia 1200', () {
      expect(SettingsService.instance.engineLevel, EngineLevel.defaultIndex);
    });

    test('eski altı kademe en yakın yeni seviyeye taşınıyor', () async {
      // Acemi, Çırak, Kulüp, İleri, Uzman, Usta.
      const expected = [0, 2, 3, 5, 9, 10];
      for (var old = 0; old < 6; old++) {
        SharedPreferences.setMockInitialValues({'flutter.engineLevel': old});
        await SettingsService.instance.load();
        expect(
          SettingsService.instance.engineLevel,
          expected[old],
          reason: 'eski $old',
        );
      }
    });

    test('yeni ayar varsa eskisine bakılmıyor', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.engineLevel': 5,
        'flutter.opponentLevel': 4,
      });
      await SettingsService.instance.load();
      expect(SettingsService.instance.engineLevel, 4);
    });

    test('bozuk değer listenin içine çekiliyor', () async {
      SharedPreferences.setMockInitialValues({'flutter.opponentLevel': 99});
      await SettingsService.instance.load();
      expect(SettingsService.instance.engineLevel, EngineLevel.all.length - 1);
    });

    test('seçim yeni anahtara yazılıyor, eski anahtara dokunulmuyor',
        () async {
      SharedPreferences.setMockInitialValues({'flutter.engineLevel': 1});
      await SettingsService.instance.load();
      SettingsService.instance.engineLevel = 7;
      await Future<void>.delayed(Duration.zero);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('opponentLevel'), 7);
      // Eski sürüme dönülürse eski seçimi bulsun.
      expect(prefs.getInt('engineLevel'), 1);
    });
  });

  group('Oyun hamlesi', () {
    tearDown(() async {
      MaiaPlayer.instance.reset();
      StockfishUci.cachedBinaryPath = null;
      await EngineService.instance.dispose();
    });

    test('Maia seviyesi yasal bir hamle oynuyor', () async {
      MaiaPlayer.loadBytes = () async => File(_weights).readAsBytesSync();
      // Stockfish'e hiç gidilmediğini göstermek için ikiliyi yok say.
      StockfishUci.cachedBinaryPath =
          '${Directory.systemTemp.path}/chesslib-no-stockfish-for-maia';
      const afterE4 =
          'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1';
      final result = await EngineService.instance.bestMoveForLevel(
        afterE4,
        EngineLevel.all[2],
        history: const [_start, afterE4],
      );
      expect(_legal(afterE4), contains(result.bestMoveUci));
    }, skip: weightsAvailable ? false : 'ağırlık dosyası yok');

    test('geçmiş konumla uyuşmuyorsa yalnızca konum kullanılıyor', () async {
      MaiaPlayer.loadBytes = () async => File(_weights).readAsBytesSync();
      StockfishUci.cachedBinaryPath =
          '${Directory.systemTemp.path}/chesslib-no-stockfish-for-maia';
      const other = '8/8/8/8/8/4k3/4P3/4K3 w - - 0 1';
      final result = await EngineService.instance.bestMoveForLevel(
        other,
        EngineLevel.all[4],
        history: const [_start],
      );
      expect(_legal(other), contains(result.bestMoveUci));
    }, skip: weightsAvailable ? false : 'ağırlık dosyası yok');

    test('ağırlık dosyası yoksa Stockfish gizlice oynamıyor', () async {
      // Stockfish hazır olsa bile Maia seviyesinde ona düşülmemeli: öyle
      // bir hata fark edilmeden kalırdı. Sonuç boş, sebep kayıtlı.
      MaiaPlayer.loadBytes = () async => throw const FileSystemException('yok');
      StockfishUci.cachedBinaryPath = null;
      final path = await StockfishUci.resolveBinaryPath();
      if (path == null) {
        markTestSkipped('Stockfish ikilisi yok');
        return;
      }
      StockfishUci.cachedBinaryPath = path;
      final result = await EngineService.instance
          .bestMoveForLevel(_start, EngineLevel.all[0], history: const [_start]);
      expect(result.bestMoveUci, isEmpty);
      expect(MaiaPlayer.instance.unavailable, isTrue);
      expect(MaiaPlayer.instance.failure, contains('yok'));
    });

    test('ne Maia ne Stockfish varsa boş sonuç, çökme yok', () async {
      MaiaPlayer.loadBytes = () async => throw const FileSystemException('yok');
      StockfishUci.cachedBinaryPath =
          '${Directory.systemTemp.path}/chesslib-no-stockfish-at-all';
      final result = await EngineService.instance
          .bestMoveForLevel(_start, EngineLevel.all[5]);
      expect(result.bestMoveUci, isEmpty);
    });
  });

  group('Zorluk seçimi', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      StorageService.instance.resetCache();
      PuzzleService.instance.resetCache();
      OpeningService.instance.resetCache();
    });

    Future<void> openSheet(WidgetTester tester) async {
      await SettingsService.instance.load();
      Strings.language = AppLanguage.turkish;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(420, 900);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('home.playEngine')));
      await tester.pumpAndSettle();
    }

    testWidgets('Maia puanları yan yana, Stockfish ayrı bölümde',
        (tester) async {
      await openSheet(tester);
      expect(find.byType(ChoiceChip), findsNWidgets(9));
      expect(find.text(t('home.maiaTitle')), findsOneWidget);
      expect(find.text(t('home.stockfishTitle')), findsOneWidget);
      expect(find.text(t('level.expert.name')), findsOneWidget);
      expect(find.text(t('level.master.name')), findsOneWidget);
      // Varsayılan Maia 1200: açıklaması görünüyor.
      expect(find.text(t('level.maia.1200')), findsOneWidget);
    });

    testWidgets('puana dokununca seçiliyor ve açıklaması değişiyor',
        (tester) async {
      await openSheet(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, '1600'));
      await tester.pumpAndSettle();
      expect(SettingsService.instance.engineLevel, 4);
      expect(find.text(t('level.maia.1600')), findsOneWidget);
      expect(find.text(t('level.maia.1200')), findsNothing);
    });

    testWidgets('Stockfish seçilince Maia açıklaması kalkıyor',
        (tester) async {
      await openSheet(tester);
      await tester.ensureVisible(find.text(t('level.master.name')));
      await tester.tap(find.text(t('level.master.name')));
      await tester.pumpAndSettle();
      expect(SettingsService.instance.engineLevel, 10);
      expect(find.text(t('level.maia.1200')), findsNothing);
      final chips = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip));
      expect(chips.where((c) => c.selected), isEmpty);
    });
  });

  group('Oyun ekranı', () {
    setUp(() async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      for (final channel in const [
        MethodChannel('com.ryanheise.just_audio.methods'),
        MethodChannel('dev.fluttercommunity.plus/wakelock'),
      ]) {
        messenger.setMockMethodCallHandler(channel, (call) async => null);
      }
      SharedPreferences.setMockInitialValues({
        'flutter.soundEnabled': false,
        'flutter.hapticsEnabled': false,
        'flutter.animateMoves': false,
        'flutter.soundDefaultsRestored': true,
      });
      await SettingsService.instance.load();
      Strings.language = AppLanguage.turkish;
      MaiaPlayer.instance.reset();
      MaiaPlayer.loadBytes = bundleLoader;
      // Stockfish'e gidilirse hamle gelmesin: oynayan Maia olmalı.
      StockfishUci.cachedBinaryPath =
          '${Directory.systemTemp.path}/chesslib-no-stockfish-in-game';
    });

    tearDown(() async {
      MaiaPlayer.instance.reset();
      StockfishUci.cachedBinaryPath = null;
      await EngineService.instance.dispose();
    });

    testWidgets('Maia beyazla ilk hamleyi oynuyor, rakibin adı görünüyor',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: GameScreen(
          mode: GameMode.versusEngine,
          playerColor: engine.Color.black,
          engineLevelIndex: 2,
        ),
      ));
      await tester.pump();
      expect(find.text('Maia · 1200'), findsWidgets);

      ChessBoardWidget board() =>
          tester.widget<ChessBoardWidget>(find.byType(ChessBoardWidget));
      // Ağırlıklar varlık paketinden gerçek zamanda okunuyor, ağ arka
      // planda hesaplıyor; sahte saat bunları beklemiyor.
      for (var i = 0; i < 40 && board().lastMove == null; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 250)),
        );
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pumpAndSettle();

      expect(board().lastMove, isNotNull, reason: 'Maia hamle oynamadı');
      expect(board().game.sideToMove, engine.Color.black);
      expect(board().movableSide, engine.Color.black);
      expect(find.text(t('game.engineStalled')), findsNothing);
      expect(MaiaPlayer.instance.unavailable, isFalse,
          reason: 'ağırlıklar varlık paketinde olmalı (pubspec)');
    }, skip: !weightsAvailable); // ağırlık dosyası yoksa

    testWidgets('Maia açılamazsa oyun bunu sebebiyle söylüyor',
        (tester) async {
      MaiaPlayer.loadBytes =
          () async => throw const FileSystemException('model dosyası yok');
      await tester.pumpWidget(const MaterialApp(
        home: GameScreen(
          mode: GameMode.versusEngine,
          playerColor: engine.Color.black,
          engineLevelIndex: 2,
        ),
      ));
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pumpAndSettle();

      final board =
          tester.widget<ChessBoardWidget>(find.byType(ChessBoardWidget));
      expect(board.lastMove, isNull, reason: 'Stockfish gizlice oynamamalı');
      expect(board.movableSide, isNull, reason: 'tahta iki tarafa açık');
      expect(find.textContaining('Maia'), findsWidgets);
      expect(find.textContaining('model dosyası yok'), findsOneWidget,
          reason: 'sebep yazılmalı');
      expect(find.text(t('game.engineStalled')), findsNothing);
    });
  });
}
