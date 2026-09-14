import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/models/chess_engine.dart' as engine;
import 'package:chess_pgn_reader/services/board_image_service.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/widgets/board_background.dart';
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

  testWidgets('ahşap dokusu tahtayı gerçekten değiştirir', (tester) async {
    // Damar bir görselden gelmiyor, çizimden doğuyor; anahtar açılınca
    // aynı renklerle farklı bir görüntü çıkması gerekiyor.
    Future<List<int>> capture({required bool wood}) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 128,
                height: 128,
                child: BoardBackground(
                  light: 0xFFF0D9B5,
                  dark: 0xFFB58863,
                  wood: wood,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      List<int> bytes = const [];
      await tester.runAsync(() async {
        bytes = (await BoardImageService.capture(key, pixelRatio: 1))!;
      });
      return bytes;
    }

    final plain = await capture(wood: false);
    final grained = await capture(wood: true);
    expect(plain, isNot(equals(grained)), reason: 'damar çizilmemiş');

    // Damar taşların okunmasını zorlaştırmayacak kadar hafif olmalı:
    // sıkıştırılmış boyut düz tahtanınkinden çok büyük olmamalı.
    expect(
      grained.length,
      lessThan(plain.length * 60),
      reason: 'damar fazla belirgin',
    );
  });

  testWidgets('işaret rengi seçilen tahtaya göre değişir', (tester) async {
    // İşaret rengi koyu kare renginden türetiliyor; tahta değişince
    // işaretin de değişmesi gerekiyor, yoksa yeşil tahtada yeşil işaret
    // kaybolurdu.
    await _pumpBoard(tester);
    SettingsService.instance.boardDark = 0xFF769656; // yeşil
    final onGreen = BoardAssets.markColor(SettingsService.instance.boardDark);
    SettingsService.instance.boardDark = 0xFFE2571E; // turuncu
    final onOrange = BoardAssets.markColor(SettingsService.instance.boardDark);
    expect(onGreen, isNot(onOrange));
  });
}
