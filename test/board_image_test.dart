import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chess_pgn_reader/models/puzzle.dart';
import 'package:chess_pgn_reader/services/board_image_service.dart';

/// PNG dosyalarının ilk sekiz baytı sabittir.
const List<int> pngSignature = [137, 80, 78, 71, 13, 10, 26, 10];

void main() {
  group('Tahta görüntüsü', () {
    testWidgets('çizim sınırı PNG baytlarına çevrilir', (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: RepaintBoundary(
            key: key,
            child: const SizedBox(
              width: 160,
              height: 160,
              child: ColoredBox(color: Color(0xFFB58863)),
            ),
          ),
        ),
      );

      final bytes = await tester.runAsync(
        () => BoardImageService.capture(key, pixelRatio: 2),
      );

      expect(bytes, isNotNull);
      expect(bytes!.sublist(0, 8), pngSignature);
      expect(bytes.length, greaterThan(100));
    });

    testWidgets('çizim sınırı yoksa null döner', (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(const SizedBox.shrink());
      final bytes = await tester.runAsync(
        () => BoardImageService.capture(key),
      );
      expect(bytes, isNull);
    });
  });

  group('Bulmaca numarası', () {
    test('varlık satırındaki kaynak numarası okunur', () {
      final puzzle = Puzzle.fromAssetLine(
        '3q1rk1/5pbp/5Qp1/8/8/2B5/5PPP/6K1 w - - 0 1|mat-1|f6g7|771',
        'mates#770',
      )!;
      expect(puzzle.number, 771);
      expect(puzzle.solution, ['f6g7']);
    });

    test('numarasız satırda null kalır', () {
      final puzzle = Puzzle.fromAssetLine(
        '8/8/3k4/8/8/8/6Q1/7K w - - 0 1|oyunsonu',
        'endgames#0',
      )!;
      expect(puzzle.number, isNull);
    });

    test('düzenlenen bulmaca numarasını korur', () {
      final puzzle = Puzzle.fromAssetLine(
        '3q1rk1/5pbp/5Qp1/8/8/2B5/5PPP/6K1 w - - 0 1|mat-1|f6g7|771',
        'mates#770',
      )!;
      expect(puzzle.copyWith(title: 'Deneme').number, 771);
    });
  });
}
