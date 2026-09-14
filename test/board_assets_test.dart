import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';

/// Tahta ve taş takımı listeleri elle tutuluyor; yeni bir takım eklenip
/// renk çifti ya da etiketi unutulursa uygulama sessizce yedek renklere
/// düşer ve kare adları okunmaz hâle gelir. Bunlar burada yakalanır.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => Strings.language = AppLanguage.system);

  group('Tahtalar', () {
    test('her tahtanın kendi renk çifti var', () {
      final fallback = BoardAssets.squareColors('__tanimsiz__');
      for (final board in BoardAssets.boards) {
        expect(
          BoardAssets.squareColors(board),
          isNot(equals(fallback)),
          reason: '$board için renk çifti tanımlanmamış',
        );
      }
    });

    test('açık ve koyu kare birbirinden farklı', () {
      for (final board in BoardAssets.boards) {
        final (light, dark) = BoardAssets.squareColors(board);
        expect(light, isNot(dark), reason: '$board tek renk görünür');
      }
    });

    test('kare adı rengi bulunduğu karenin rengi olamaz', () {
      // Yazı, üzerinde durduğu karenin karşıt rengini alır; aynı olsaydı
      // koordinatlar zeminde kaybolurdu.
      for (final board in BoardAssets.boards) {
        final (light, dark) = BoardAssets.squareColors(board);
        expect(
          BoardAssets.coordinateColor(board, onLightSquare: true),
          allOf(isNot(light), equals(dark)),
          reason: '$board açık karede okunmaz',
        );
        expect(
          BoardAssets.coordinateColor(board, onLightSquare: false),
          allOf(isNot(dark), equals(light)),
          reason: '$board koyu karede okunmaz',
        );
      }
    });

    test('görselli tahtaların dosyası pakette var', () async {
      for (final board in BoardAssets.boards) {
        if (BoardAssets.isFlat(board)) continue;
        final data = await rootBundle.load(BoardAssets.boardPath(board));
        expect(
          data.lengthInBytes,
          greaterThan(0),
          reason: '${BoardAssets.boardPath(board)} boş',
        );
      }
    });

    test('her tahtanın iki dilde de adı var', () {
      for (final code in [AppLanguage.turkish, AppLanguage.english]) {
        Strings.language = code;
        for (final board in BoardAssets.boards) {
          final label = BoardAssets.label(board);
          expect(label, isNotEmpty);
          expect(
            label,
            isNot(contains('_')),
            reason: '$board için $code etiketi eksik, ham ad görünüyor',
          );
        }
      }
    });
  });

  group('Taş takımları', () {
    test('her takımın on iki dosyası pakette var', () async {
      const codes = [
        'wp', 'wn', 'wb', 'wr', 'wq', 'wk', //
        'bp', 'bn', 'bb', 'br', 'bq', 'bk',
      ];
      for (final set in BoardAssets.pieceSets) {
        for (final code in codes) {
          final path = BoardAssets.piecePath(set, code);
          final data = await rootBundle.load(path);
          expect(data.lengthInBytes, greaterThan(0), reason: '$path boş');
        }
      }
    });

    test('takım adları çevrilmez', () {
      for (final set in BoardAssets.pieceSets) {
        Strings.language = AppLanguage.turkish;
        final tr = BoardAssets.label(set);
        Strings.language = AppLanguage.english;
        expect(
          BoardAssets.label(set),
          tr,
          reason: '$set adı dile göre değişiyor; özel isimler sabit kalmalı',
        );
        expect(tr, isNot(contains('-')), reason: '$set için etiket eksik');
      }
    });
  });
}
