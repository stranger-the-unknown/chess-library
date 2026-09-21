import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/models/chess_engine.dart' as engine;
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/widgets/chess_board_widget.dart';

/// Sağ tık işaretleri hamle tanıyıcılarıyla aynı tahtayı paylaşıyor;
/// birinin diğerini yutması kolay. Burada işaretlemenin çalıştığı ve
/// hamle akışını bozmadığı denetlenir.

/// İşaret katmanı ekranda mı?
bool _hasMarkLayer(WidgetTester tester) {
  return tester.widgetList<CustomPaint>(find.byType(CustomPaint)).any(
        (paint) => paint.painter.runtimeType.toString() == '_MarkPainter',
      );
}

Future<void> _pumpBoard(
  WidgetTester tester, {
  void Function(engine.ChessMove move)? onMove,
}) async {
  SharedPreferences.setMockInitialValues({});
  await SettingsService.instance.load();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            height: 400,
            child: ChessBoardWidget(
              game: engine.ChessGame(),
              onMove: onMove,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Tahtanın sol üstünden sayarak bir karenin orta noktası.
Offset _squareCenter(WidgetTester tester, int col, int row) {
  final board = tester.getRect(find.byType(ChessBoardWidget));
  final square = board.width / 8;
  return board.topLeft + Offset((col + 0.5) * square, (row + 0.5) * square);
}

Future<void> _rightClick(WidgetTester tester, Offset at) async {
  final gesture = await tester.startGesture(
    at,
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryButton,
  );
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sağ tık kareyi işaretler, ikincisi kaldırır', (tester) async {
    await _pumpBoard(tester);
    expect(_hasMarkLayer(tester), isFalse);

    await _rightClick(tester, _squareCenter(tester, 4, 4));
    expect(_hasMarkLayer(tester), isTrue, reason: 'işaret konmadı');

    await _rightClick(tester, _squareCenter(tester, 4, 4));
    expect(_hasMarkLayer(tester), isFalse, reason: 'işaret kalkmadı');
  });

  testWidgets('sağ sürükleme ok çizer', (tester) async {
    await _pumpBoard(tester);

    final gesture = await tester.startGesture(
      _squareCenter(tester, 4, 6),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await gesture.moveTo(_squareCenter(tester, 4, 4));
    await tester.pump();
    // Sürükleme sürerken ok önizlemesi görünür.
    expect(_hasMarkLayer(tester), isTrue, reason: 'önizleme yok');

    await gesture.up();
    await tester.pumpAndSettle();
    expect(_hasMarkLayer(tester), isTrue, reason: 'ok kalmadı');
  });

  testWidgets('sol tık işaretleri temizler', (tester) async {
    await _pumpBoard(tester);
    await _rightClick(tester, _squareCenter(tester, 2, 2));
    expect(_hasMarkLayer(tester), isTrue);

    // Boş bir kareye sol tık.
    await tester.tapAt(_squareCenter(tester, 6, 3));
    await tester.pumpAndSettle();
    expect(_hasMarkLayer(tester), isFalse);
  });

  testWidgets('işaretleme hamle yapmayı engellemez', (tester) async {
    engine.ChessMove? played;
    await _pumpBoard(tester, onMove: (move) => played = move);

    await _rightClick(tester, _squareCenter(tester, 3, 3));

    // e2 -> e4: alttan ikinci sıra (row 6), beşinci sütun (col 4).
    await tester.tapAt(_squareCenter(tester, 4, 6));
    await tester.pumpAndSettle();
    await tester.tapAt(_squareCenter(tester, 4, 4));
    await tester.pumpAndSettle();

    expect(played, isNotNull, reason: 'hamle tanınmadı');
    expect(played!.uci, 'e2e4');
  });

  group('İşaret rengi', () {
    test('her tahtada tanımlı ve saydam değil', () {
      for (final board in BoardAssets.boards) {
        final color = BoardAssets.markColor(board);
        expect(color >> 24 & 0xFF, 0xFF, reason: '$board için saydam renk');
      }
    });

    test('varsayılan renk paletin ilk rengi', () {
      // Eskiden renk tahtanın renginden türetiliyordu (tondan en uzak
      // aday seçiliyordu). Artık kullanıcı her tahta için paletten
      // seçiyor; seçmediyse paletin ilk rengi geçerli.
      for (final board in BoardAssets.boards) {
        expect(
          BoardAssets.markColor(board),
          BoardAssets.accentPalette.first,
          reason: '$board için varsayılan renk paletin ilki değil',
        );
      }
    });
  });
}
