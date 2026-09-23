import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/models/chess_engine.dart' as engine;
import 'package:chess_pgn_reader/models/puzzle.dart';
import 'package:chess_pgn_reader/screens/puzzles/puzzle_solve_screen.dart';
import 'package:chess_pgn_reader/services/engine/search_result.dart';
import 'package:chess_pgn_reader/services/puzzle_service.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/widgets/chess_board_widget.dart';
import 'package:chess_pgn_reader/widgets/move_list.dart';

/// 10.3.0: bulmaca ekranındaki düğmeler.

const _start = '6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1';

String _after(List<String> ucis) {
  final game = engine.ChessGame.fromFen(_start);
  for (final uci in ucis) {
    game.makeMove(game.moveFromUci(uci)!);
  }
  return game.fen;
}

SearchResult _r(String best, int cp, [List<String>? pv]) => SearchResult(
      bestMoveUci: best,
      scoreCp: cp,
      depth: 14,
      nodes: 1000,
      pvUci: pv ?? [best],
    );

/// Konuma göre sonuç veren sahte motor. Bir konum için birden çok sonuç
/// verilirse sırayla kullanılır, sonuncusu tekrar eder.
class _FakeEngine {
  final Map<String, List<SearchResult>> byFen;
  final List<String> asked = [];
  _FakeEngine(this.byFen);

  Future<SearchResult> call(String fen,
      {required int depth, required int movetimeMs}) async {
    asked.add(fen);
    final queue = byFen[fen];
    if (queue == null || queue.isEmpty) return SearchResult.empty;
    return queue.length > 1 ? queue.removeAt(0) : queue.first;
  }
}

/// Motorla yargılanan (çözümü kayıtlı olmayan) bulmacanın motoru:
/// en iyi hat a1a7 g8h8 a7b7 h8g8.
_FakeEngine _standardEngine() => _FakeEngine({
      _start: [_r('a1a7', 300, ['a1a7', 'g8h8', 'a7b7', 'h8g8'])],
      _after(['a1a7']): [_r('g8h8', -300)],
      _after(['a1a7', 'g8h8']): [_r('a7b7', 300, ['a7b7', 'h8g8'])],
      _after(['a1a7', 'g8h8', 'a7b7']): [_r('h8g8', -300)],
    });

Puzzle _enginePuzzle() => Puzzle(id: 'c1#e', fen: _start);
Puzzle _scriptedPuzzle() => Puzzle(
      id: 'c1#s',
      fen: _start,
      solution: const ['a1a7', 'g8h8', 'a7b7'],
    );

ChessBoardWidget _board(WidgetTester tester) =>
    tester.widget<ChessBoardWidget>(find.byType(ChessBoardWidget));

List<String> _arrows(WidgetTester tester) => [
      for (final a in _board(tester).arrows)
        '${a.from.algebraic}${a.to.algebraic}',
    ];

int _moveCount(WidgetTester tester) {
  final list = find.byType(MoveList);
  if (list.evaluate().isEmpty) return 0;
  return tester.widget<MoveList>(list).moves.length;
}

VoidCallback? _button(WidgetTester tester, String label) => tester
    .widget<TextButton>(find.ancestor(
      of: find.text(label),
      matching: find.byType(TextButton),
    ))
    .onPressed;

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

/// Rakip cevabı 700 ms, çözüm adımları 900 ms: zamanı elle ilerlet.
Future<void> _wait(WidgetTester tester, [int ms = 1000]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _open(WidgetTester tester, Puzzle puzzle) async {
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

  group('Çözüm', () {
    testWidgets('bir hamleden sonra kaldığı yerden devam ediyor (motorlu)',
        (tester) async {
      PuzzleSolveScreen.debugAnalyze = _standardEngine().call;
      await _open(tester, _enginePuzzle());

      await _play(tester, 'a1a7');
      await _wait(tester);
      expect(_moveCount(tester), 2, reason: 'hamle ve rakip cevabı');

      await tester.tap(find.text(t('puzzles.solution')));
      await tester.pump();
      // İki hamle yerinde, sıradaki hemen oynanıyor. Eskiden liste
      // silinip baştan başlıyordu (0 ya da 1).
      expect(_moveCount(tester), 3, reason: 'baştan değil, kaldığı yerden');
      await _wait(tester, 2000);

      // Eskiden sonraki konumun hattı başlangıç konumunda oynanmaya
      // çalışılıyor, hiçbir hamle oynanmadan ekran kilitleniyordu.
      expect(_moveCount(tester), 4);
      expect(_board(tester).game.fen,
          _after(['a1a7', 'g8h8', 'a7b7', 'h8g8']));
    });

    testWidgets('bir hamleden sonra kaldığı yerden devam ediyor (kayıtlı)',
        (tester) async {
      await _open(tester, _scriptedPuzzle());
      await _play(tester, 'a1a7');
      await _wait(tester);

      await tester.tap(find.text(t('puzzles.solution')));
      await tester.pump();
      // İki hamle yerinde, sıradaki hemen oynanıyor. Eskiden liste
      // silinip baştan başlıyordu (0 ya da 1).
      expect(_moveCount(tester), 3, reason: 'baştan değil, kaldığı yerden');
      await _wait(tester, 1200);
      expect(_moveCount(tester), 3);
    });

    testWidgets('gösterildikten sonra yeniden basılınca baştan gösteriyor',
        (tester) async {
      PuzzleSolveScreen.debugAnalyze = _standardEngine().call;
      await _open(tester, _enginePuzzle());
      await _play(tester, 'a1a7');
      await _wait(tester);
      await tester.tap(find.text(t('puzzles.solution')));
      await _wait(tester, 2000);
      expect(_moveCount(tester), 4);

      expect(_button(tester, t('puzzles.solution')), isNotNull,
          reason: 'çözüm düğmesi yeniden basılabilmeli');
      await tester.tap(find.text(t('puzzles.solution')));
      await tester.pump();
      expect(_moveCount(tester), 1,
          reason: 'baştan gösterim: ilk hamle hemen oynanır');
      await _wait(tester, 4000);
      expect(_moveCount(tester), 4);
      expect(_board(tester).game.fen,
          _after(['a1a7', 'g8h8', 'a7b7', 'h8g8']));
    });
  });

  group('Baştan', () {
    testWidgets('ipucu ve çözüm başlangıç konumuna göre çalışıyor',
        (tester) async {
      PuzzleSolveScreen.debugAnalyze = _standardEngine().call;
      await _open(tester, _enginePuzzle());
      await _play(tester, 'a1a7');
      await _wait(tester);

      await tester.tap(find.text(t('common.restart')));
      await tester.pump();
      expect(_moveCount(tester), 0);

      // Eskiden ölçüt sonraki konumda kalıyordu: ipucu oku çıkmıyor,
      // hamleler yanlış ölçüte göre yargılanıyordu.
      await tester.tap(find.text(t('common.hint')));
      await tester.pump();
      expect(_arrows(tester), ['a1a7']);

      await tester.tap(find.text(t('puzzles.solution')));
      await _wait(tester, 4000);
      expect(_moveCount(tester), 4);
    });
  });

  group('İpucu', () {
    testWidgets('motor okları kapalıyken de gösteriliyor', (tester) async {
      SettingsService.instance.showEngineArrows = false;
      await _open(tester, _scriptedPuzzle());

      await tester.tap(find.text(t('common.hint')));
      await tester.pump();
      expect(_arrows(tester), ['a1a7'],
          reason: 'ipucu motor oklarından bağımsız bir istek');
    });

    testWidgets('ikinci hamlede de gösteriliyor (motorlu)', (tester) async {
      PuzzleSolveScreen.debugAnalyze = _standardEngine().call;
      await _open(tester, _enginePuzzle());
      await _play(tester, 'a1a7');
      await _wait(tester);

      await tester.tap(find.text(t('common.hint')));
      await tester.pump();
      expect(_arrows(tester), ['a7b7']);
    });
  });

  group('Hamle listesi', () {
    testWidgets('eski hamleye dokununca o konum gösteriliyor', (tester) async {
      await _open(tester, _scriptedPuzzle());
      await _play(tester, 'a1a7');
      await _wait(tester);
      expect(_moveCount(tester), 2);

      await tester.tap(find.text('Ra7'));
      await tester.pump();
      expect(_board(tester).game.fen, _after(['a1a7']));
      expect(_board(tester).interactive, isFalse,
          reason: 'geçmiş konumda hamle yapılamaz');

      // Son hamleye dokunmak canlı konuma döndürüyor.
      await tester.tap(find.text('Kh8'));
      await tester.pump();
      expect(_board(tester).game.fen, _after(['a1a7', 'g8h8']));
      expect(_board(tester).interactive, isTrue);
    });
  });

  group('Motorla yargılama', () {
    testWidgets('motor cevap veremezse hamle doğru sayılmıyor',
        (tester) async {
      // Başlangıç ölçütü eşitlik; kullanıcının hamlesinden sonraki konum
      // için motor sonuç vermiyor. Eskiden skor 0 sayılıp hamle
      // "doğru" kabul ediliyordu.
      PuzzleSolveScreen.debugAnalyze = _FakeEngine({
        _start: [_r('a1a7', 0)],
      }).call;
      await _open(tester, _enginePuzzle());

      await _play(tester, 'a1b1');
      await _wait(tester);
      expect(_moveCount(tester), 0, reason: 'yargılanamayan hamle oynanmaz');
      expect(find.text(t('puzzles.engineUnavailable')), findsOneWidget);
    });

    testWidgets('ölçüt iptal olursa sonraki hamle eski ölçütle yargılanmıyor',
        (tester) async {
      final current = _after(['a1a7', 'g8h8']);
      final fake = _FakeEngine({
        // Başlangıç konumu kötü görünüyor (-500): eski ölçüt bu kalırsa
        // sonraki zayıf hamle de tolerans içinde sayılır.
        _start: [_r('a1a7', -500, ['a1a7', 'g8h8'])],
        _after(['a1a7']): [_r('g8h8', 500)],
        // Rakip cevabından sonraki analiz iki kez iptal oluyor, sonra
        // gerçek sonuç: kazanç (+300).
        current: [
          SearchResult.superseded,
          SearchResult.superseded,
          _r('a7b7', 300),
        ],
        // Kullanıcının zayıf hamlesi: kazanç gidiyor (rakip için 0).
        _after(['a1a7', 'g8h8', 'a7c7']): [_r('h8g8', 0)],
      });
      PuzzleSolveScreen.debugAnalyze = fake.call;
      await _open(tester, _enginePuzzle());
      await _play(tester, 'a1a7');
      await _wait(tester);

      await _play(tester, 'a7c7');
      await _wait(tester);
      expect(_moveCount(tester), 2, reason: 'kazancı kaçıran hamle yanlış');
      expect(find.textContaining('Rc7'), findsOneWidget,
          reason: 'yanlış hamle geri bildirimi');
    });
  });
}
