import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/models/chess_engine.dart' as engine;
import 'package:chess_pgn_reader/models/opening.dart';
import 'package:chess_pgn_reader/models/pgn_parser.dart';
import 'package:chess_pgn_reader/screens/game_screen.dart';
import 'package:chess_pgn_reader/screens/openings/opening_study_screen.dart';
import 'package:chess_pgn_reader/services/engine/engine_service.dart';
import 'package:chess_pgn_reader/services/engine/stockfish_uci.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/widgets/chess_board_widget.dart';

/// 9.0.9'da kapatılan maddeler.

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

engine.Color? _movableSide(WidgetTester tester) => tester
    .widget<ChessBoardWidget>(find.byType(ChessBoardWidget))
    .movableSide;

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
    _silencePlugins();
  });

  testWidgets('motor düşünürken gezinip dönünce tahta kilitlenmiyor',
      (tester) async {
    // Gezinmek konumu değiştirdiği için arama geçersiz oluyor; canlı
    // konuma dönüldüğünde kimse motoru yeniden çağırmıyordu. Sıra
    // motorda kalıyor, tahta oyuncunun rengine kilitli duruyordu.
    StockfishUci.cachedBinaryPath =
        '${Directory.systemTemp.path}/chesslib-yok-sf-5';
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

    // Motor düşünürken başa dön ve **orada kal**: arama bittiğinde konum
    // başka olduğu için sonuç düşüyor.
    await tester.tap(find.byIcon(Icons.chevron_left_rounded));
    await tester.pump();

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    // Şimdi canlı konuma dön: motoru yeniden çağıran kimse yoktu.
    await tester.tap(find.byIcon(Icons.last_page_rounded));
    await tester.pump();

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(_movableSide(tester), isNull,
        reason: 'canlı konuma dönünce motor yeniden çağrılmalı; '
            'cevap veremiyorsa tahta iki tarafa açılmalı');
  });

  testWidgets('açılışta "Göster" rakip hamlesiyle devam ediyor',
      (tester) async {
    // "Göster" yalnızca bir yarım hamle ilerletiyordu: senin hamlen
    // oynanıyor, tahta rakibi bekler hâlde kalıyordu.
    final position = engine.ChessGame();
    final uci = <String>[];
    final san = <String>[];
    for (final move in ['e2e4', 'e7e5', 'g1f3', 'b8c6']) {
      final parsed = position.moveFromUci(move)!;
      san.add(position.sanFor(parsed));
      position.makeMove(parsed);
      uci.add(move);
    }
    final opening = Opening(
      id: 'deneme',
      eco: 'C40',
      family: 'Deneme',
      variation: 'Kısa',
      uciMoves: uci,
      sanMoves: san,
    );

    await tester.pumpWidget(
      MaterialApp(home: OpeningStudyScreen(opening: opening)),
    );
    await tester.pumpAndSettle();

    // Alıştırma kipine geç.
    await tester.tap(find.text(t('openings.practice')));
    await tester.pumpAndSettle();

    await tester.tap(find.text(t('openings.show')));
    await tester.pump();
    expect(find.text('e4'), findsWidgets, reason: 'ilk hamle oynanmalı');

    // Rakibin cevabı 700 ms sonra gelir.
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();

    expect(find.text('e5'), findsWidgets,
        reason: '"Göster" sonrası rakip de oynamalı');
  });

  test('bozuk başlangıç konumu PGN üretimini düşürmüyor', () {
    // "PGN kopyala" ve dışa aktarma yolunda `fromFen` yakalanmıyordu.
    final pgn = PgnParser.buildPgn(
      uciMoves: const ['e2e4', 'e7e5'],
      startFen: 'bu bir fen degil',
    );

    expect(pgn, contains('1. e4 e5'));
    expect(pgn.contains('[FEN'), isFalse,
        reason: 'okunamayan konum başlığa yazılmamalı');
  });
}
