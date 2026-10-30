import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/models/puzzle.dart';
import 'package:chess_pgn_reader/screens/game_screen.dart';
import 'package:chess_pgn_reader/screens/puzzles/puzzle_solve_screen.dart';
import 'package:chess_pgn_reader/services/engine/search_result.dart';
import 'package:chess_pgn_reader/services/puzzle_service.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/widgets/chess_board_widget.dart';

/// 10.11.0: deneme hamlesini geri almada animasyon yok; bulmacada
/// doğru/yanlış kartı bir süre sonra soluyor, "bitti" kartı kalıyor.

ChessBoardWidget _board(WidgetTester tester) =>
    tester.widget<ChessBoardWidget>(find.byType(ChessBoardWidget));

Future<void> _tapSquare(WidgetTester tester, String square) async {
  final rect = tester.getRect(find.byType(ChessBoardWidget));
  final s = rect.width / 8;
  await tester.tapAt(Offset(
    rect.left + ('abcdefgh'.indexOf(square[0]) + 0.5) * s,
    rect.top + (8 - int.parse(square[1]) + 0.5) * s,
  ));
  await tester.pump();
}

Future<void> _play(WidgetTester tester, String uci) async {
  await _tapSquare(tester, uci.substring(0, 2));
  await _tapSquare(tester, uci.substring(2, 4));
}

Future<void> _wait(WidgetTester tester, int ms) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

// -------------------------------------------------------------------------
// Bulmaca
// -------------------------------------------------------------------------

/// Arka sırası açık şah: a1a8 mat.
const _start = '6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1';

/// Kayıtlı çözüm: a1a7 g8h8 a7b7. Kayıtlı olmayan hamlede motor sonuç
/// vermiyor, yani "aynı hızda mat" sayılmıyor ve hamle yanlış oluyor.
Puzzle _scriptedPuzzle() => Puzzle(
      id: 'c1#s',
      fen: _start,
      solution: const ['a1a7', 'g8h8', 'a7b7'],
    );

Future<SearchResult> _noEngine(String fen,
        {required int depth, required int movetimeMs}) async =>
    SearchResult.empty;

Future<void> _openPuzzle(WidgetTester tester, Puzzle puzzle) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(480, 1000);
  addTearDown(tester.view.reset);
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

/// Kartın görünürlüğü: yazının üstündeki solma katmanının hedefi.
double _cardOpacity(WidgetTester tester, String text) => tester
    .widget<AnimatedOpacity>(find.ancestor(
      of: find.text(text),
      matching: find.byType(AnimatedOpacity),
    ))
    .opacity;

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
  });

  tearDown(() => PuzzleSolveScreen.debugAnalyze = null);

  group('Deneme hamlesi', () {
    testWidgets('geri alınca ve kapatınca canlandırılmıyor', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: GameScreen(
          uciMoves: ['e2e4', 'e7e5', 'g1f3', 'b8c6'],
          title: 'Kayıtlı oyun',
        ),
      ));
      await tester.pump();

      await _play(tester, 'd2d4');
      await _play(tester, 'd7d5');
      expect(_board(tester).animateLastMove, isTrue,
          reason: 'deneme hamlesi ileri gidiştir');

      // Eskiden bayrak ileri gidişteki gibi açık kalıyordu: geri alınan
      // denemeden önceki hamle tahtada yeniden oynanıyormuş gibi kayıyordu.
      await tester.tap(find.byTooltip(t('game.undoExplore')));
      await tester.pump();
      expect(_board(tester).animateLastMove, isFalse);

      await _play(tester, 'd7d5');
      expect(_board(tester).animateLastMove, isTrue);
      await tester.tap(find.byTooltip(t('game.backToGame')));
      await tester.pump();
      expect(_board(tester).animateLastMove, isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('Bulmaca kartı', () {
    testWidgets('yanlış kartı bir süre sonra soluyor', (tester) async {
      PuzzleSolveScreen.debugAnalyze = _noEngine;
      await _openPuzzle(tester, _scriptedPuzzle());
      final wrong = t('puzzles.wrong', {'move': 'Rb1'});

      await _play(tester, 'a1b1');
      await _wait(tester, 300);
      expect(find.text(wrong), findsOneWidget);
      expect(_cardOpacity(tester, wrong), 1);

      await _wait(tester, 3000);
      expect(_cardOpacity(tester, wrong), 0);
    });

    testWidgets('aynı yanlış hamle yeniden oynanınca kart yeniden çıkıyor',
        (tester) async {
      PuzzleSolveScreen.debugAnalyze = _noEngine;
      await _openPuzzle(tester, _scriptedPuzzle());
      final wrong = t('puzzles.wrong', {'move': 'Rb1'});

      await _play(tester, 'a1b1');
      await _wait(tester, 3500);
      expect(_cardOpacity(tester, wrong), 0);

      // Yazı aynı; kart yine de yeni bir geri bildirimdir.
      await _play(tester, 'a1b1');
      await _wait(tester, 300);
      expect(_cardOpacity(tester, wrong), 1);
    });

    testWidgets('rakibin cevabından sonra doğru kartı da soluyor',
        (tester) async {
      PuzzleSolveScreen.debugAnalyze = _noEngine;
      await _openPuzzle(tester, _scriptedPuzzle());
      final reply = t('puzzles.opponentPlayed', {'move': 'Kh8'});

      await _play(tester, 'a1a7');
      await _wait(tester, 1000);
      expect(find.text(reply), findsOneWidget);
      expect(_cardOpacity(tester, reply), 1);

      await _wait(tester, 3000);
      expect(_cardOpacity(tester, reply), 0);
    });

    testWidgets('bulmaca bitince bayraklı kart kalıyor', (tester) async {
      PuzzleSolveScreen.debugAnalyze = _noEngine;
      await _openPuzzle(
        tester,
        Puzzle(id: 'c1#m', fen: _start, solution: const ['a1a8']),
      );

      await _play(tester, 'a1a8');
      await _wait(tester, 500);
      expect(find.text(t('puzzles.mateDone')), findsOneWidget);

      await _wait(tester, 5000);
      expect(find.text(t('puzzles.mateDone')), findsOneWidget);
      expect(_cardOpacity(tester, t('puzzles.mateDone')), 1);
    });
  });
}
