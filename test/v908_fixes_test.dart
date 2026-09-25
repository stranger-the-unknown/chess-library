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
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/widgets/captured_pieces.dart';
import 'package:chess_pgn_reader/widgets/chess_board_widget.dart';
import 'package:chess_pgn_reader/widgets/piece_widget.dart';

/// 9.0.8'de kapatılan maddeler.

/// Siyahın oynayacağı sade bir konum.
const _pastedFen = '4k3/8/8/8/8/8/4P3/4K3 b - - 0 1';

void _silencePlugins({String? clipboard}) {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final channel in const [
    MethodChannel('com.ryanheise.just_audio.methods'),
    MethodChannel('dev.fluttercommunity.plus/wakelock'),
  ]) {
    messenger.setMockMethodCallHandler(channel, (call) async => null);
  }
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.getData' && clipboard != null) {
      return <String, dynamic>{'text': clipboard};
    }
    return null;
  });
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

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(AppBar),
      matching: find.byType(PopupMenuButton<String>),
    ),
  );
  await tester.pumpAndSettle();
}

bool _boardOpen(WidgetTester tester) => tester
    .widget<ChessBoardWidget>(find.byType(ChessBoardWidget))
    .interactive;

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

  testWidgets('pes ettikten sonra FEN yapıştırınca tahta açılıyor',
      (tester) async {
    // `_pasteFen` ve `_editPosition` geçmişi siliyor ama "pes edildi"
    // bayrağını bırakıyordu: 9.0.6'da geri alma için kapatılan kilit
    // buradan geri geliyordu.
    _silencePlugins(clipboard: _pastedFen);
    StockfishUci.cachedBinaryPath =
        '${Directory.systemTemp.path}/chesslib-yok-sf-3';
    // Bu test Stockfish'i sınıyor; varsayılan seviye artık Maia.
    SettingsService.instance.engineLevel = 9; // Uzman
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

    await _openMenu(tester);
    await tester.tap(find.text(t('game.resign')).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(t('game.resign')).last);
    await tester.pumpAndSettle();
    expect(_boardOpen(tester), isFalse);

    await _openMenu(tester);
    await tester.tap(find.text(t('common.pasteFen')).last);
    await tester.pumpAndSettle();

    expect(_boardOpen(tester), isTrue,
        reason: 'yeni konum kurulunca pes bayrağı kalkmalı');

    // Yeni konumda sıra motorda: başlatma denemesini ve bekleme
    // süresini boşalt, yoksa test zamanlayıcı asılı kalıyor.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });

  testWidgets('kayıtlı oyunda "Yeniden başlat" hamleleri silmiyor',
      (tester) async {
    // Menüdeki düğme geçmişi boşaltıyor ve incelenen partiyi geri
    // alınamayacak şekilde siliyordu; onay düğmesi de "Sil" yazıyordu.
    _silencePlugins();
    await tester.pumpWidget(const MaterialApp(
      home: GameScreen(
        uciMoves: ['e2e4', 'e7e5', 'g1f3', 'b8c6'],
        title: 'Kayıtlı oyun',
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Nf3'), findsOneWidget);

    await _openMenu(tester);
    await tester.tap(find.text(t('game.restart')).last);
    await tester.pumpAndSettle();

    // Onay penceresindeki düğme "Sil" değil "Yeniden başlat".
    expect(find.text(t('common.delete')), findsNothing);
    await tester.tap(find.text(t('game.restart')).last);
    await tester.pumpAndSettle();

    expect(find.text('Nf3'), findsOneWidget,
        reason: 'kayıtlı oyunun hamleleri durmalı');
  });

  testWidgets('motor düşünürken geri al kapalı', (tester) async {
    _silencePlugins();
    StockfishUci.cachedBinaryPath =
        '${Directory.systemTemp.path}/chesslib-yok-sf-4';
    // Bu test Stockfish'i sınıyor; varsayılan seviye artık Maia.
    SettingsService.instance.engineLevel = 9; // Uzman
    addTearDown(() async {
      StockfishUci.cachedBinaryPath = null;
      await EngineService.instance.dispose();
    });

    await tester.pumpWidget(const MaterialApp(
      home: GameScreen(mode: GameMode.versusEngine),
    ));
    await tester.pumpAndSettle();

    await _play(tester, 'e2', 'e4');
    await tester.pump();

    final undo = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.undo_rounded),
        matching: find.byType(IconButton),
      ),
    );
    expect(undo.onPressed, isNull,
        reason: 'motor düşünürken geri almak iki aramayı çakıştırıyordu');

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });

  testWidgets('terfi eden piyon alınmış sayılmıyor', (tester) async {
    // Siyah bir piyonu vezire çevirdi: yedi piyonu, iki veziri var.
    // Beyazın şeridinde hiçbir taş görünmemeli.
    _silencePlugins();
    // Siyah: yedi piyon (biri terfi etti) ve iki vezir.
    final game = engine.ChessGame.fromFen(
      'rnbqkbnr/ppppppp1/7q/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 300,
          child: CapturedPieces(
            side: engine.Color.white,
            game: game,
            size: 16,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(PieceWidget), findsNothing,
        reason: 'terfi eden piyon şeride "alınmış" diye yazılıyordu');
  });

  test('bozuk kayıt karantinaya alınınca asıl anahtar kalkıyor', () async {
    // Anahtar durduğu sürece her açılışta yeniden çözümlenip aynı uyarıyı
    // veriyordu.
    const broken = '[{"id":"a","name":"Yar';
    SharedPreferences.setMockInitialValues({'openings_custom_v1': broken});
    OpeningService.instance.resetCache();

    expect(await OpeningService.instance.all(), isEmpty);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('openings_custom_v1_bozuk'), broken,
        reason: 'veri kaybolmamalı');
    expect(prefs.getString('openings_custom_v1'), isNull,
        reason: 'asıl anahtar kaldırılmalı');
  });

  test('makeUciMove da dört ya da beş karakter istiyor', () {
    // Not: bu yol zaten güvenliydi (tanınmayan terfi harfi `false`
    // döndürüyordu); denetim yalnızca üç API'yi aynı kurala bağlıyor.
    final game = engine.ChessGame();
    expect(game.makeUciMove('e2e4abc'), isFalse);
    expect(engine.ChessGame().makeUciMove('e2e4'), isTrue);
  });
}
