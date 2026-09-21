import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/models/chess_engine.dart' as engine;
import 'package:chess_pgn_reader/models/move_entry.dart';
import 'package:chess_pgn_reader/models/pgn_parser.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/widgets/chess_board_widget.dart';
import 'package:chess_pgn_reader/widgets/move_list.dart';

/// 9.0.7'de kapatılan maddeler.

const _boardSize = 400.0;

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

void main() {
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

  testWidgets('parmak kayarak dokununca hamle kaybolmuyor', (tester) async {
    // Seçili taş varken hedef kareye azıcık kayarak dokunmak `onPan`
    // tanıyıcısını kazandırıyor ve `onTapUp` hiç gelmiyordu: hamle
    // sessizce düşüyordu. Telefonda ve izleme yüzeyinde sık.
    engine.ChessMove? played;
    final game = engine.ChessGame();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: _boardSize,
            height: _boardSize,
            child: ChessBoardWidget(
              game: game,
              interactive: true,
              onMove: (move) => played = move,
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Taşı seç.
    await tester.tapAt(_squareCenter(tester, 'e2'));
    await tester.pump();

    // Hedef kareye dokun, ama parmağı kare içinde 20 piksel kaydır
    // (dokunma eşiği 18 piksel; tanıyıcı sürükleme sayıyor).
    final gesture = await tester.startGesture(_squareCenter(tester, 'e4'));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveBy(const Offset(0, -20));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(played, isNotNull, reason: 'kayan dokunuş hamleyi düşürmemeli');
    expect(played!.uci, 'e2e4');
  });

  testWidgets('siyah başlayan listede ilk satır "1..." oluyor',
      (tester) async {
    final game = engine.ChessGame.fromFen(
      'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1',
    );
    final moves = <MoveEntry>[
      MoveEntry.play(game, game.moveFromUci('e7e5')!),
      MoveEntry.play(game, game.moveFromUci('g1f3')!),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 60,
          child: MoveList(
            moves: moves,
            currentIndex: 1,
            onMoveTap: (_) {},
            blackFirst: true,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Beyazın boş yarısı ve siyahın hamlesi aynı satırda.
    expect(find.text('...'), findsOneWidget);
    expect(find.text('e5'), findsOneWidget);
    expect(find.text('1.'), findsOneWidget);
    expect(find.text('2.'), findsOneWidget,
        reason: 'ikinci hamle yeni satıra geçmeli');
  });

  group('PGN kenarları', () {
    test('eşitliksiz terfi okunuyor', () {
      // "e8Q" biçimi PGN standardı değil ama eski dosyalarda yaygın.
      const pgn = '[White "A"]\n[Black "B"]\n\n'
          '1. a4 h5 2. a5 h4 3. a6 h3 4. axb7 hxg2 5. bxa8Q gxh1N *';
      final parser = PgnParser();

      expect(parser.parse(pgn), isTrue);
      expect(parser.skippedTokens, isEmpty,
          reason: 'terfiler atlanmamalı: ${parser.skippedTokens}');
      expect(parser.moves, contains('b7a8q'));
      expect(parser.moves, contains('g2h1n'));
    });

    test('Unicode üç nokta ve ½-½ okunuyor', () {
      const pgn = '[White "A"]\n[Black "B"]\n\n'
          '1. e4 e5 2. Nf3 Nc6 ½-½';
      final parser = PgnParser();

      expect(parser.parse(pgn), isTrue);
      expect(parser.gameResult, '1/2-1/2');
      expect(parser.skippedTokens, isEmpty);

      final black = PgnParser();
      expect(black.parse('[FEN "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/'
          'RNBQKBNR b KQkq - 0 1"]\n\n1… e5 2. Nf3 *'), isTrue);
      expect(black.skippedTokens, isEmpty,
          reason: 'üç nokta hamle sayılmamalı: ${black.skippedTokens}');
      expect(black.moves, ['e7e5', 'g1f3']);
    });
  });

  test('UCI metni dört ya da beş karakter olmalı', () {
    final game = engine.ChessGame();
    expect(game.isLegalUci('e2e4'), isTrue);
    expect(game.moveFromUci('e2e4'), isNotNull);

    // Kuyruklu metin eskiden geçerli sayılıyordu.
    expect(game.isLegalUci('e2e4abc'), isFalse);
    expect(game.moveFromUci('e2e4abc'), isNull);
    expect(game.isLegalUci('e2e'), isFalse);
  });
}
