import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/models/chess_engine.dart' as engine;
import 'package:chess_pgn_reader/services/board_image_service.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/widgets/board_background.dart';
import 'package:chess_pgn_reader/widgets/mini_board.dart';
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

        // 64x64 = 4096 piksel. Çoğu takımda en ince taş bile bunun
        // yüzde on beşini kaplıyor; harflerden kurulu 'letter' takımı
        // ise yüzde sekizde kalıyor. Eşik onun altında tutuldu: amaç
        // ince çizimi elemek değil, hiç çizilmemiş olanı yakalamak.
        expect(whiteCount, greaterThan(200), reason: '$set beyaz $type boş');
        expect(blackCount, greaterThan(200), reason: '$set siyah $type boş');
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
                const Positioned.fill(child: BoardBackground()),
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
                  const Positioned.fill(child: BoardBackground()),
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

  group('Bulmaca önizlemesi', () {
    // Listelerdeki küçük tahtalar ayrı bir çizim yolundan geçiyor;
    // seçilen tahta ya da taş takımı değiştiğinde önizlemenin de
    // değişmesi gerekiyor, yoksa liste oyun tahtasından başka görünür.
    const fen = 'r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 0 1';

    Future<List<int>> capture(WidgetTester tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        _wrap(
          RepaintBoundary(
            key: key,
            child: const MiniBoard(fen: fen, size: 96),
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

    testWidgets('tahta değişince önizleme de değişir', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.instance.load();

      SettingsService.instance.boardLight = 0xFFF0D9B5;
      SettingsService.instance.boardDark = 0xFFB58863;
      final brown = await capture(tester);
      SettingsService.instance.boardLight = 0xFFAEB7C4;
      SettingsService.instance.boardDark = 0xFF4B5A72;
      final midnight = await capture(tester);

      expect(
        brown,
        isNot(equals(midnight)),
        reason: 'küçük tahta seçili tahtayı kullanmıyor',
      );
    });

    testWidgets('taş takımı değişince önizleme de değişir', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.instance.load();

      SettingsService.instance.pieceSet = 'chessnut';
      final chessnut = await capture(tester);
      SettingsService.instance.pieceSet = 'papercut';
      final papercut = await capture(tester);

      expect(
        chessnut,
        isNot(equals(papercut)),
        reason: 'küçük tahta seçili taş takımını kullanmıyor',
      );
    });
  });
}
