import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/models/puzzle.dart';
import 'package:chess_pgn_reader/screens/game_screen.dart';
import 'package:chess_pgn_reader/screens/puzzles/puzzle_solve_screen.dart';
import 'package:chess_pgn_reader/services/engine/engine_service.dart';
import 'package:chess_pgn_reader/services/engine/stockfish_uci.dart';
import 'package:chess_pgn_reader/services/puzzle_service.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/widgets/chess_board_widget.dart';

/// 10.0.2'de kapatılan maddeler.

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
    SharedPreferences.setMockInitialValues({
      'flutter.soundEnabled': false,
      'flutter.hapticsEnabled': false,
      'flutter.animateMoves': false,
      'flutter.soundDefaultsRestored': true,
    });
    Strings.language = AppLanguage.turkish;
    await SettingsService.instance.load();
    PuzzleService.instance.resetCache();
    _silencePlugins();
  });

  testWidgets('serbest tahtada geçmişten başka hamle oynanabiliyor',
      (tester) async {
    // Analiz tahtasında geri gidince tahta kapanıyordu: varyant denemek
    // imkânsızdı. `_onBoardMove` içindeki "sonrasını sil" kodu bu yüzden
    // hiç çalışmıyordu.
    await tester.pumpWidget(const MaterialApp(home: GameScreen()));
    await tester.pumpAndSettle();

    await _play(tester, 'e2', 'e4');
    await tester.pumpAndSettle();
    await _play(tester, 'e7', 'e5');
    await tester.pumpAndSettle();
    expect(find.text('e5'), findsOneWidget);

    // Bir hamle geri git ve siyah için başka bir hamle oyna.
    await tester.tap(find.byIcon(Icons.chevron_left_rounded));
    await tester.pumpAndSettle();
    await _play(tester, 'c7', 'c5');
    await tester.pumpAndSettle();

    expect(find.text('c5'), findsOneWidget,
        reason: 'geçmişten devam edilebilmeli');
    expect(find.text('e5'), findsNothing,
        reason: 'yeni hamle sonrasını silmeli');
  });

  testWidgets('boş bulmaca listesi ekranı düşürmüyor', (tester) async {
    // Arayüz bunu açmıyor ama kapı açık kalmasındı: önce `clamp(0, -1)`
    // hata veriyordu, sonra tahta atanmadığı için `late` alan patlıyordu.
    StockfishUci.cachedBinaryPath =
        '${Directory.systemTemp.path}/chesslib-yok-sf-bos';
    addTearDown(() async {
      StockfishUci.cachedBinaryPath = null;
      await EngineService.instance.dispose();
    });
    final collection = PuzzleCollection(id: 'bos', name: 'Boş');

    await tester.pumpWidget(MaterialApp(
      home: PuzzleSolveScreen(
        collection: collection,
        puzzles: const [],
        initialIndex: 0,
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);

    // Boş bulmacada motor değerlendirmesi de başlıyor; onu da boşalt.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  test('konum düzenlenince kayıtlı çözüm siliniyor', () async {
    // Yeni konumda eski hamle dizisi bekleniyordu: doğru hamleler
    // "yanlış" sayılıyordu.
    final collection = await PuzzleService.instance.createCollection('Deneme');
    final puzzle = await PuzzleService.instance.addPuzzle(
      collection,
      fen: '6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1',
      title: 'Mat',
    );
    puzzle.solution = ['a1a8'];
    await PuzzleService.instance.updatePuzzle(
      collection,
      puzzle,
      fen: puzzle.fen,
      title: puzzle.title,
      tags: puzzle.tags,
    );
    expect(puzzle.solution, isNotEmpty, reason: 'konum aynıyken korunmalı');

    await PuzzleService.instance.updatePuzzle(
      collection,
      puzzle,
      fen: '7k/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1',
      title: puzzle.title,
      tags: puzzle.tags,
    );

    expect(puzzle.solution, isEmpty,
        reason: 'konum değişince eski çözüm kalmamalı');
  });
}
