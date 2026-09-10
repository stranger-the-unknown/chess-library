import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/models/chess_engine.dart' as engine;
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/services/sound_service.dart';
import 'package:chess_pgn_reader/widgets/chess_board_widget.dart';

/// Kural dışı hamle sesinin ne zaman çaldığı.
///
/// Kural: ses yalnızca hamle sırası olan taraf şah altındayken çalar
/// ("bu hamle şahı kurtarmıyor"). Şah yokken geçersiz bir kareye
/// tıklamak sessiz olmalı, yoksa tahtada dolaşmak gürültülü olur.

const double _boardSide = 480;
const double _square = _boardSide / 8;

/// Kareyi ekran koordinatına çevirir (tahta çevrilmemiş varsayılır).
Offset _at(String square) {
  final file = square.codeUnitAt(0) - 97;
  final rank = int.parse(square[1]);
  return Offset(
    file * _square + _square / 2,
    (8 - rank) * _square + _square / 2,
  );
}

Future<List<String>> _tapSequence(
  WidgetTester tester,
  String fen,
  List<String> squares, {
  engine.ChessGame? into,
}) async {
  final played = <String>[];
  SoundService.instance.debugOnPlay = played.add;
  addTearDown(() => SoundService.instance.debugOnPlay = null);

  final game = into ?? engine.ChessGame.fromFen(fen);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: _boardSide,
            height: _boardSide,
            // onMove verilmezse tahta etkileşime kapalıdır ve
            // dokunuşlar hiç işlenmez; testler boş yere geçerdi.
            child: ChessBoardWidget(game: game, onMove: game.makeMove),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  for (final square in squares) {
    await tester.tapAt(
      tester.getTopLeft(find.byType(ChessBoardWidget)) + _at(square),
    );
    await tester.pumpAndSettle();
  }
  return played;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.load();
  });

  testWidgets('şah yokken kural dışı deneme sessizdir', (tester) async {
    // Normal başlangıç dizilişi: şah yok. e2 piyonu seçilip e5'e
    // (ulaşamayacağı bir kare) tıklanıyor.
    final played = await _tapSequence(
      tester,
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
      ['e2', 'e5'],
    );
    expect(played, isEmpty, reason: 'şah yokken ses çalmamalı');
  });

  testWidgets('şah altındayken kural dışı deneme ses çıkarır', (tester) async {
    // Siyah vezir e-hattında; beyaz şah e1'de şah altında.
    // a2 piyonunu a3'e oynamak şahı kurtarmaz: kural dışı.
    const fen = '4k3/8/8/8/8/8/PPPP1PPP/RNB1KBNR w KQ - 0 1';
    final game = engine.ChessGame.fromFen(fen);
    expect(game.isCheck, isFalse, reason: 'önce şahsız hâli doğrula');

    const checkFen = '4k3/8/8/8/8/8/PPPPqPPP/RNB1KBNR w KQ - 0 1';
    expect(
      engine.ChessGame.fromFen(checkFen).isCheck,
      isTrue,
      reason: 'bu dizilişte beyaz şah altında olmalı',
    );

    final played = await _tapSequence(tester, checkFen, ['a2', 'a3']);
    expect(
      played,
      contains(SoundService.illegal),
      reason: 'şah altında kural dışı deneme uyarı sesi vermeli',
    );
  });

  testWidgets('şah altında geçerli hamle kural dışı sesi vermez', (
    tester,
  ) async {
    // Aynı pozisyonda şahı kurtaran hamle: Şe1xe2 (vezir alınır).
    const checkFen = '4k3/8/8/8/8/8/PPPPqPPP/RNB1KBNR w KQ - 0 1';
    final game = engine.ChessGame.fromFen(checkFen);
    final played = await _tapSequence(
      tester,
      checkFen,
      ['e1', 'e2'],
      into: game,
    );

    // Dokunuşun gerçekten tahtaya ulaştığını doğrula: yoksa "ses
    // çalmadı" beklentisi boş yere geçerdi.
    expect(
      game.pieceAt(engine.Position.fromAlgebraic('e2'))?.type,
      engine.PieceType.king,
      reason: 'Şxe2 oynanmış olmalı',
    );
    expect(
      played,
      isNot(contains(SoundService.illegal)),
      reason: 'geçerli hamlede kural dışı sesi çalmamalı',
    );
  });

  testWidgets('kendi taşına geçiş sessizdir', (tester) async {
    // Bir taş seçip başka bir kendi taşına tıklamak seçimi değiştirir;
    // kural dışı bir deneme değildir.
    final played = await _tapSequence(
      tester,
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
      ['e2', 'd2'],
    );
    expect(played, isEmpty);
  });
}
