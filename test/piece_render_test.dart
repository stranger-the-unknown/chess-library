import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chess_pgn_reader/models/chess_engine.dart' as engine;
import 'package:chess_pgn_reader/services/board_image_service.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/widgets/board_background.dart';
import 'package:chess_pgn_reader/widgets/piece_widget.dart';

/// Taşların gerçekten çizildiğini ve PNG'ye yakalandığını denetler.
///
/// Taşlar SVG'ye taşındığında bu yol sessizce bozulabilirdi: dosya
/// bulunamazsa ya da çözümleme bitmeden yakalama yapılırsa ekranda ve
/// dışa aktarılan görüntüde boş kare kalırdı.

const List<int> _pngSignature = [137, 80, 78, 71, 13, 10, 26, 10];

Widget _wrap(Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: child),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('her takımda on iki taşın hepsi çizilir', (tester) async {
    for (final set in BoardAssets.pieceSets) {
      for (final color in [engine.Color.white, engine.Color.black]) {
        for (final type in engine.PieceType.values) {
          final piece = engine.Piece(type, color);
          await tester.pumpWidget(
            _wrap(PieceWidget(piece: piece, size: 64, pieceSet: set)),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '$set / ${PieceWidget.codeFor(piece)} çizilemedi',
          );
        }
      }
    }
  });

  testWidgets('her taş gerçekten boyanır ve renkler ayırt edilir', (
    tester,
  ) async {
    // Bir SVG dosyası çözümlenemezse flutter_svg sessizce boş bir resim
    // döner: hata da yoktur, taş da yoktur. Bunu ancak piksel sayarak
    // yakalayabiliyoruz. Aynı geçişte beyazın siyahtan ayırt edilip
    // edilmediğine de bakılır.
    Future<(int, List<int>)> render(engine.Piece piece, String set) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        _wrap(
          RepaintBoundary(
            key: key,
            child: SizedBox(
              width: 64,
              height: 64,
              child: PieceWidget(piece: piece, size: 64, pieceSet: set),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      int opaque = 0;
      List<int> pixels = const [];
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        pixels = data!.buffer.asUint8List().toList(growable: false);
        for (int i = 3; i < pixels.length; i += 4) {
          if (pixels[i] > 16) opaque++;
        }
      });
      return (opaque, pixels);
    }

    for (final set in BoardAssets.pieceSets) {
      for (final type in engine.PieceType.values) {
        final (whiteCount, whitePixels) =
            await render(engine.Piece(type, engine.Color.white), set);
        final (blackCount, blackPixels) =
            await render(engine.Piece(type, engine.Color.black), set);

        // 64x64 = 4096 piksel; en ince taş (piyon) bile bunun yüzde
        // onunu kaplıyor. Eşiği düşük tutup yalnızca "boş" durumu
        // yakalıyoruz.
        expect(whiteCount, greaterThan(400), reason: '$set beyaz $type boş');
        expect(blackCount, greaterThan(400), reason: '$set siyah $type boş');
        expect(
          whitePixels,
          isNot(equals(blackPixels)),
          reason: '$set için beyaz ve siyah $type birebir aynı görünüyor',
        );
      }
    }
  });

  testWidgets('taşlı tahta PNG olarak yakalanır ve boş çıkmaz', (
    tester,
  ) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      _wrap(
        RepaintBoundary(
          key: key,
          child: SizedBox(
            width: 128,
            height: 128,
            child: Stack(
              children: [
                const Positioned.fill(child: BoardBackground(board: 'brown')),
                Positioned(
                  left: 0,
                  top: 0,
                  child: PieceWidget(
                    piece: const engine.Piece(
                      engine.PieceType.queen,
                      engine.Color.black,
                    ),
                    size: 64,
                    pieceSet: 'chessnut',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final bytes = await tester.runAsync(
      () => BoardImageService.capture(key, pixelRatio: 2),
    );

    expect(bytes, isNotNull);
    expect(bytes!.sublist(0, 8), _pngSignature);
    // Yalnızca zemin çizilseydi görüntü çok daha küçük sıkışırdı; taşın
    // da bulunduğunu boyuttan anlamak yeterli değil, bu yüzden pikselleri
    // ayrıca karşılaştırıyoruz.
    expect(bytes.length, greaterThan(200));
  });

  testWidgets('taşsız tahta ile taşlı tahta farklı görüntü verir', (
    tester,
  ) async {
    Future<List<int>?> capture({required bool withPiece}) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        _wrap(
          RepaintBoundary(
            key: key,
            child: SizedBox(
              width: 128,
              height: 128,
              child: Stack(
                children: [
                  const Positioned.fill(child: BoardBackground(board: 'brown')),
                  if (withPiece)
                    Positioned(
                      left: 0,
                      top: 0,
                      child: PieceWidget(
                        piece: const engine.Piece(
                          engine.PieceType.queen,
                          engine.Color.black,
                        ),
                        size: 64,
                        pieceSet: 'chessnut',
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final bytes = await tester.runAsync(
        () => BoardImageService.capture(key, pixelRatio: 1),
      );
      return bytes;
    }

    final empty = await capture(withPiece: false);
    final withPiece = await capture(withPiece: true);

    expect(empty, isNotNull);
    expect(withPiece, isNotNull);
    expect(
      withPiece,
      isNot(equals(empty)),
      reason: 'taş çizilmemiş: iki görüntü birebir aynı',
    );
  });
}
