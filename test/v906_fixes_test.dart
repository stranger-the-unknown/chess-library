import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/models/pgn_parser.dart';
import 'package:chess_pgn_reader/models/puzzle.dart';
import 'package:chess_pgn_reader/screens/game_screen.dart';
import 'package:chess_pgn_reader/screens/puzzles/puzzle_solve_screen.dart';
import 'package:chess_pgn_reader/services/engine/engine_service.dart';
import 'package:chess_pgn_reader/services/engine/stockfish_uci.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/widgets/chess_board_widget.dart';

/// 9.0.6'da kapatılan kilitler ve sessiz kalan uyarılar.

/// Tahtadaki bir karenin ekran koordinatı (beyaz aşağıda).
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

bool _boardOpen(WidgetTester tester) => tester
    .widget<ChessBoardWidget>(find.byType(ChessBoardWidget))
    .interactive;

/// Ekran geri tuşuna kapalı mı? (`PopScope` turlenmis oldugu icin tip
/// yerine bicime bakiliyor.)
bool _canPop(WidgetTester tester) => tester
    .widgetList(find.byWidgetPredicate((w) => w is PopScope))
    .cast<PopScope>()
    .first
    .canPop;

/// Gerçek eklentiler testte yok (bkz. engine_stall_test).
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
  });

  testWidgets('pes ettikten sonra geri alınca tahta açılıyor', (tester) async {
    // `_takeBack` sonucu siliyor ama "pes edildi" bayrağını
    // bırakıyordu: tahta kapalı kalıyor, motor da oynamıyordu. Tek
    // çıkış oyunu baştan başlatmaktı (yani bütün hamleler gidiyordu).
    //
    // Geri alma düğmesi yalnızca motora karşı oyunda var; motorun
    // cevabını beklememek için ikili dosya yok sayılıyor.
    _silencePlugins();
    StockfishUci.cachedBinaryPath =
        '${Directory.systemTemp.path}/chesslib-yok-sf-2';
    addTearDown(() async {
      StockfishUci.cachedBinaryPath = null;
      await EngineService.instance.dispose();
    });

    await tester.pumpWidget(const MaterialApp(
      home: GameScreen(mode: GameMode.versusEngine),
    ));
    await tester.pumpAndSettle();

    await _play(tester, 'e2', 'e4');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(_boardOpen(tester), isTrue);

    await tester.tap(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(t('game.resign')).last);
    await tester.pumpAndSettle();
    // Onay penceresindeki "Pes et".
    await tester.tap(find.text(t('game.resign')).last);
    await tester.pumpAndSettle();

    expect(_boardOpen(tester), isFalse, reason: 'pes edilince tahta kapanır');

    await tester.tap(find.byIcon(Icons.undo_rounded));
    await tester.pumpAndSettle();

    expect(_boardOpen(tester), isTrue,
        reason: 'geri alınca oyun sürüyor, tahta kilitli kalmamalı');
  });

  testWidgets('kaydedilmemiş oyunda çıkış onayı isteniyor', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GameScreen()));
    await tester.pumpAndSettle();

    // Hamle yokken kaybolacak bir şey de yok.
    expect(_canPop(tester), isTrue);

    await _play(tester, 'e2', 'e4');
    await tester.pumpAndSettle();

    expect(
      _canPop(tester),
      isFalse,
      reason: 'kaydedilmemiş hamleler geri tuşuyla sessizce silinmemeli',
    );
  });

  testWidgets('bulmacada "Baştan" bekleyen cevabı iptal ediyor',
      (tester) async {
    // Rakip cevabı beklenirken başa sarınca bekleyen iş konumun
    // değiştiğini görüp `_busy`yi indirmeden çıkıyordu: tahta ve
    // ileri/geri düğmeleri kilitli kalıyor, ekrandan çıkmadan
    // kurtulunamıyordu.
    final puzzle = Puzzle(
      id: 'p1',
      fen: '6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1',
      solution: const ['a1a7', 'g8h8', 'a7b7'],
    );
    final collection = PuzzleCollection(
      id: 'c1',
      name: 'Deneme',
      puzzles: [puzzle],
    );

    await tester.pumpWidget(MaterialApp(
      home: PuzzleSolveScreen(
        collection: collection,
        puzzles: [puzzle],
        initialIndex: 0,
      ),
    ));
    await tester.pumpAndSettle();

    // Doğru hamle: rakip cevabı sıraya giriyor (en erken 0,5 sn).
    await _play(tester, 'a1', 'a7');
    await tester.pump();
    expect(_boardOpen(tester), isFalse);

    await tester.tap(find.text(t('common.restart')));
    await tester.pump();

    // Bekleyen cevap bu sırada dönüyor.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(_boardOpen(tester), isTrue,
        reason: 'başa sarınca tahta yeniden oynanabilir olmalı');
  });

  test('bozuk [FEN] başlığı sessiz kalmıyor', () {
    // Başlıktaki konum okunamayınca hamleler standart açılıştan
    // oynanıyor: ortaya bambaşka bir parti çıkabilir.
    const pgn = '[White "A"]\n[Black "B"]\n[FEN "bu bir fen degil"]\n\n'
        '1. e4 e5 2. Nf3 *';
    final parser = PgnParser();

    expect(parser.parse(pgn), isTrue);
    expect(parser.startFenRejected, isTrue);
    expect(parser.startFen, isNull);
    expect(parser.moves, hasLength(3));

    final games = PgnParser.parseAll(pgn);
    expect(games, hasLength(1));
    expect(games.first.fenRejected, isTrue);
    expect(games.first.isClean, isFalse,
        reason: 'içe aktarma ekranı bunu kendiliğinden seçmemeli');
  });
}
