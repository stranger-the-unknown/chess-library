import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/models/chess_engine.dart' as engine;
import 'package:chess_pgn_reader/screens/game_screen.dart';
import 'package:chess_pgn_reader/services/engine/engine_service.dart';
import 'package:chess_pgn_reader/services/engine/stockfish_uci.dart';
import 'package:chess_pgn_reader/services/opening_service.dart';
import 'package:chess_pgn_reader/services/puzzle_service.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/services/storage_service.dart';
import 'package:chess_pgn_reader/widgets/chess_board_widget.dart';

/// 10.5.0 öncesi bildirilen hatalar.

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

Offset _squareCenter(WidgetTester tester, String square, {bool flipped = false}) {
  final board = tester.getRect(find.byType(ChessBoardWidget));
  final size = board.width / 8;
  var file = 'abcdefgh'.indexOf(square[0]);
  var rank = int.parse(square[1]);
  if (flipped) {
    file = 7 - file;
    rank = 9 - rank;
  }
  return Offset(
    board.left + (file + 0.5) * size,
    board.top + (8 - rank + 0.5) * size,
  );
}

Future<void> _play(WidgetTester tester, String from, String to,
    {bool flipped = false}) async {
  await tester.tapAt(_squareCenter(tester, from, flipped: flipped));
  await tester.pump();
  await tester.tapAt(_squareCenter(tester, to, flipped: flipped));
  await tester.pump();
}

/// Motorun cevap verememesini bekler (ikili yok; gerçek zamanda denenir).
Future<void> _letEngineStall(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 300)),
  );
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
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

  tearDown(() async {
    Strings.language = AppLanguage.system;
    GameScreen.debugAnalyze = null;
    StockfishUci.cachedBinaryPath = null;
    await EngineService.instance.dispose();
  });

  group('Motora karşı oyunda eski hamlede motor', () {
    testWidgets('sıranın motorda olduğu eski konumda analiz çalışıyor',
        (tester) async {
      // Eskiden eski bir hamleye gidip motoru açınca, o konumda sıra
      // motordaysa analiz hiç başlamıyordu ("bazen çalışmıyor").
      final asked = <String>[];
      GameScreen.debugAnalyze = (fen) async {
        asked.add(fen);
        return const SearchResult(
          bestMoveUci: 'e2e4',
          scoreCp: 25,
          depth: 12,
          nodes: 1,
          pvUci: ['e2e4'],
        );
      };
      StockfishUci.cachedBinaryPath =
          '${Directory.systemTemp.path}/chesslib-yok-sf-1050';
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(480, 1000);
      addTearDown(tester.view.reset);

      // Kullanıcı siyah; motor (Uzman, Stockfish) beyaz ve oynayamıyor:
      // tahta iki tarafa açılıyor, hamleleri kullanıcı yapıyor.
      await tester.pumpWidget(const MaterialApp(
        home: GameScreen(
          mode: GameMode.versusEngine,
          playerColor: engine.Color.black,
          engineLevelIndex: 9,
        ),
      ));
      await tester.pump();
      await _letEngineStall(tester);
      await _play(tester, 'e2', 'e4', flipped: true);
      await tester.pumpAndSettle();
      await _play(tester, 'e7', 'e5', flipped: true);
      await _letEngineStall(tester);

      // Başa dön: sıra beyazda, yani motorda. Canlı konum değil.
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byIcon(Icons.chevron_left_rounded));
        await tester.pumpAndSettle();
      }
      asked.clear();

      await tester.tap(find.byTooltip(t('game.analysisOn')));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(asked, contains(engine.ChessGame().fen),
          reason: 'başlangıç konumu motora sorulmalı');
      expect(find.textContaining('+0.25'), findsOneWidget);
    });
  });
}
