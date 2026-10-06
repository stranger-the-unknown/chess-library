import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/models/chess_engine.dart' as engine;
import 'dart:math' as math;

import 'package:chess_pgn_reader/screens/game_screen.dart';
import 'package:chess_pgn_reader/screens/home_screen.dart';
import 'package:chess_pgn_reader/screens/openings/opening_study_screen.dart';
import 'package:chess_pgn_reader/screens/settings_screen.dart';
import 'package:chess_pgn_reader/models/opening.dart';
import 'package:chess_pgn_reader/services/engine/engine_service.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/widgets/chess_board_widget.dart';
import 'package:chess_pgn_reader/widgets/move_list.dart';

/// 10.9.0: bekleyen işler — ekranlar.
///
/// Yalnızca tercih deposuyla koşuyor: sahte saatli ekran testlerinde
/// dosya deposunun gerçek disk işlemleri bitmiyor.

final _settings = SettingsService.instance;

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

Future<void> _pump(
  WidgetTester tester,
  Widget screen, {
  Size size = const Size(412, 915),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pumpAndSettle();
}

ChessBoardWidget _board(WidgetTester tester) =>
    tester.widget<ChessBoardWidget>(find.byType(ChessBoardWidget));

int _cursor(WidgetTester tester) =>
    tester.widget<MoveList>(find.byType(MoveList)).currentIndex;

/// Ekranı kapatıp bekleyen zamanlayıcıları boşaltır. Motora karşı
/// oyunda Maia'nın zaman aşımı 20 sn ([MaiaPlayer.timeout]); sahte saatle
/// geçiyor.
Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 25));
}

const _italian = ['e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1c4', 'f8c5'];

/// Sırası bilinen "rastgele" kaynak.
class _Sequence implements math.Random {
  _Sequence(this.values);
  final List<bool> values;
  var _i = 0;
  @override
  bool nextBool() => values[_i++ % values.length];
  @override
  int nextInt(int max) => nextBool() ? 0 : max - 1;
  @override
  double nextDouble() => nextBool() ? 0.25 : 0.75;
}

/// Motora karşı oyun penceresini açar, [color] rengini seçer ve başlatır;
/// oyunun rengini döner ve ekrandan çıkar.
Future<engine.Color> _startGame(WidgetTester tester, String color) async {
  await tester.tap(find.text(t('home.playEngine')).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(color));
  await tester.pumpAndSettle();
  await tester.tap(find.text(t('common.start')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  final played = tester.widget<GameScreen>(find.byType(GameScreen)).playerColor;
  tester.state<NavigatorState>(find.byType(Navigator).first).pop();
  await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)));
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
  return played;
}

/// Pencerede seçili renk (0 beyaz, 1 siyah, 2 rastgele).
Future<int> _selectedColor(WidgetTester tester) async {
  await tester.tap(find.text(t('home.playEngine')).first);
  await tester.pumpAndSettle();
  final selected = tester
      .widget<SegmentedButton<int>>(find.byType(SegmentedButton<int>))
      .selected
      .single;
  tester.state<NavigatorState>(find.byType(Navigator).first).pop();
  await tester.pumpAndSettle();
  return selected;
}

SearchResult _result(String pv) => SearchResult(
      bestMoveUci: pv.split(' ').first,
      scoreCp: 25,
      depth: 12,
      nodes: 1,
      pvUci: pv.split(' '),
    );

/// [moves] oynandıktan sonraki konumun FEN'i.
String _after(List<String> moves) {
  final game = engine.ChessGame();
  for (final uci in moves) {
    game.makeMove(game.moveFromUci(uci)!);
  }
  return game.fen;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    _silencePlugins();
    SharedPreferences.setMockInitialValues({
      'flutter.soundEnabled': false,
      'flutter.animateMoves': true,
      'flutter.soundDefaultsRestored': true,
    });
    await _settings.load();
    Strings.language = AppLanguage.turkish;
  });

  tearDown(() {
    Strings.language = AppLanguage.system;
    GameScreen.debugAnalyze = null;
    OpeningStudyScreen.debugAnalyze = null;
    HomeScreen.random = math.Random.secure();
  });

  testWidgets('denemeden sonra devam: önce oyunun kendi konumu, sonra '
      'sıradaki hamle', (tester) async {
    _settings.gameWatchSpeed = WatchSpeed.veryFast;
    await _pump(tester, const GameScreen(uciMoves: _italian, title: 'x'));
    await tester.tap(find.byTooltip(t('common.play')));
    await tester.pump(const Duration(milliseconds: 510));
    await tester.tap(find.byTooltip(t('common.pause')));
    await tester.pumpAndSettle();
    expect(_cursor(tester), 0);

    // Durdurup tahtada bir hamle dene.
    final game = _board(tester).game;
    _board(tester).onMove!(game.moveFromUci('d7d5')!);
    await tester.pumpAndSettle();
    expect(_board(tester).game.fen, _after(['e2e4', 'd7d5']));

    await tester.tap(find.byTooltip(t('common.play')));
    await tester.pump();
    expect(_board(tester).game.fen, _after(['e2e4']),
        reason: 'eskiden deneme konumu kalıyor, ardından doğrudan sonraki '
            'hamleye geçiliyordu');
    expect(_cursor(tester), 0);
    await tester.pump(const Duration(milliseconds: 510));
    expect(_cursor(tester), 1);
    expect(_board(tester).game.fen, _after(['e2e4', 'e7e5']));
    await _dispose(tester);
  });

  group('Motora karşı oyunda renk', () {
    testWidgets('"Rastgele" kaynağın sonucuna göre iki renk de geliyor',
        (tester) async {
      HomeScreen.random = _Sequence([true, false, false, true]);
      await _pump(tester, const HomeScreen());
      final colors = [
        for (var i = 0; i < 4; i++)
          await _startGame(tester, t('common.random')),
      ];
      expect(colors, [
        engine.Color.white,
        engine.Color.black,
        engine.Color.black,
        engine.Color.white,
      ]);
      await _dispose(tester);
    });

    testWidgets('gerçek kaynakla 2000 seviyesinde iki renk de geliyor',
        (tester) async {
      await _pump(tester, const HomeScreen());
      await tester.tap(find.text(t('home.playEngine')).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('2000'));
      await tester.pumpAndSettle();
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      final colors = {
        for (var i = 0; i < 24; i++)
          await _startGame(tester, t('common.random')),
      };
      // 24 oyunun hepsinin aynı renk gelme olasılığı 2^-23.
      expect(colors, {engine.Color.white, engine.Color.black});
      await _dispose(tester);
    });

    testWidgets('seçilen renk zorluk gibi hatırlanıyor', (tester) async {
      await _pump(tester, const HomeScreen());
      expect(await _selectedColor(tester), 0, reason: 'ilk açılışta beyaz');

      HomeScreen.random = _Sequence([false]);
      expect(await _startGame(tester, t('common.random')), engine.Color.black);
      expect(await _selectedColor(tester), 2,
          reason: 'Rastgele seçili kalıyor');

      await _startGame(tester, t('common.black'));
      await _settings.load();
      // `load` dili de diskten okuyor (testte sistem dili); ekran Türkçe.
      Strings.language = AppLanguage.turkish;
      expect(_settings.engineColor, 1, reason: 'diske yazıldı');
      expect(await _selectedColor(tester), 1);
      await _dispose(tester);
    });
  });

  group('Motor ayarları', () {
    final asked = <String>[];
    setUp(asked.clear);

    Future<SearchResult> analyze(String fen) async {
      asked.add(fen);
      return _result('e2e4');
    }

    test('ikisi de varsayılan açık', () {
      expect(_settings.resumeEngineAfterWatch, isTrue);
      expect(_settings.exploreStartsEngine, isTrue);
    });

    testWidgets('"izleme bitince motoru geri aç" kapalıysa motor kapalı '
        'kalıyor (oyun)', (tester) async {
      _settings.resumeEngineAfterWatch = false;
      _settings.gameWatchSpeed = WatchSpeed.veryFast;
      GameScreen.debugAnalyze = analyze;
      await _pump(tester, const GameScreen(uciMoves: _italian, title: 'x'));
      await tester.tap(find.byTooltip(t('game.analysisOn')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(t('common.play')));
      await tester.pump(const Duration(milliseconds: 510));
      await tester.tap(find.byTooltip(t('common.pause')));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byTooltip(t('game.analysisOn')), findsOneWidget,
          reason: 'motor kapalı kaldı');
      expect(asked, hasLength(1));
      await _dispose(tester);
    });

    testWidgets('"izleme bitince motoru geri aç" kapalıysa motor kapalı '
        'kalıyor (açılış)', (tester) async {
      _settings.resumeEngineAfterWatch = false;
      _settings.openingWatchSpeed = WatchSpeed.veryFast;
      OpeningStudyScreen.debugAnalyze = analyze;
      final line = Opening(
        id: 'o',
        eco: 'C50',
        family: 'İtalyan',
        variation: 'Giuoco Piano',
        uciMoves: _italian,
        sanMoves: const ['e4', 'e5', 'Nf3', 'Nc6', 'Bc4', 'Bc5'],
        custom: true,
      );
      await _pump(tester, OpeningStudyScreen(opening: line));
      await tester.tap(find.byTooltip(t('game.analysisOn')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(t('common.play')));
      for (var i = 0; i < 7; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      await tester.pumpAndSettle();
      expect(find.byTooltip(t('game.analysisOn')), findsOneWidget,
          reason: 'izleme kendiliğinden bitti, motor kapalı kaldı');
      expect(asked, hasLength(1));
      await _dispose(tester);
    });

    testWidgets('"deneme hamlesinde motoru aç" kapalıysa motor açılmıyor',
        (tester) async {
      GameScreen.debugAnalyze = analyze;
      await _pump(tester, const GameScreen(uciMoves: _italian, title: 'x'));
      _board(tester).onMove!(_board(tester).game.moveFromUci('d2d4')!);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byTooltip(t('game.analysisOff')), findsOneWidget,
          reason: 'varsayılan: deneme motoru açıyor');
      await _dispose(tester);

      _settings.exploreStartsEngine = false;
      asked.clear();
      await _pump(tester, const GameScreen(
          key: ValueKey('ikinci'), uciMoves: _italian, title: 'x'));
      _board(tester).onMove!(_board(tester).game.moveFromUci('d2d4')!);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byTooltip(t('game.analysisOn')), findsOneWidget);
      expect(asked, isEmpty);
      await _dispose(tester);
    });

    testWidgets('ayarlarda iki anahtar', (tester) async {
      await _pump(tester, const SettingsScreen(), size: const Size(360, 800));
      for (final key in ['resumeEngineAfterWatch', 'exploreStartsEngine']) {
        final tile = find.byKey(Key(key));
        await tester.scrollUntilVisible(tile, 200,
            scrollable: find.byType(Scrollable).first);
        await tester.pumpAndSettle();
        await tester.tap(tile);
        await tester.pumpAndSettle();
      }
      expect(_settings.resumeEngineAfterWatch, isFalse);
      expect(_settings.exploreStartsEngine, isFalse);
      await _settings.load();
      expect(_settings.resumeEngineAfterWatch, isFalse, reason: 'diske yazıldı');
      expect(_settings.exploreStartsEngine, isFalse);
      expect(tester.takeException(), isNull);
    });
  });
}
