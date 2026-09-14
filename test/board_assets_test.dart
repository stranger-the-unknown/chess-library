import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/services/board_image_service.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/widgets/board_background.dart';

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

    test('kare adı her tahtada okunur kalır', () {
      // Yazı, üzerinde durduğu karenin karşıt rengini alır. Taş, mermer
      // ve zeytin gibi tahtalarda iki kare rengi birbirine çok yakın
      // olduğu için bu yetmiyor; oralarda siyah ya da beyaza düşülüyor.
      // Ölçüt her tahtada aynı: yazı zeminden yeterince ayrışmalı.
      for (final board in BoardAssets.boards) {
        final (light, dark) = BoardAssets.squareColors(board);
        for (final onLight in [true, false]) {
          final background = onLight ? light : dark;
          final text = BoardAssets.coordinateColor(
            board,
            onLightSquare: onLight,
          );
          expect(
            BoardAssets.contrastRatio(text, background),
            greaterThanOrEqualTo(2.0),
            reason: '$board üzerinde kare adı zemine karışıyor',
          );
        }
      }
    });

    test('alışılmış tahtalarda karşıt kare rengi kullanılmayı sürdürür', () {
      // Kahve ve yeşil tahtaların görünümü değişmemeli: siyah/beyaza
      // düşme yalnızca gerçekten okunmaz duruma düşenler için.
      for (final board in ['brown', 'green', 'blue', 'walnut']) {
        final (light, dark) = BoardAssets.squareColors(board);
        expect(
          BoardAssets.coordinateColor(board, onLightSquare: true),
          dark,
          reason: '$board açık karede karşıt renk kullanmıyor',
        );
        expect(
          BoardAssets.coordinateColor(board, onLightSquare: false),
          light,
          reason: '$board koyu karede karşıt renk kullanmıyor',
        );
      }
    });

    test('otuz iki tahta var ve hiçbiri yinelenmiyor', () {
      expect(BoardAssets.boards, hasLength(32));
      expect(BoardAssets.boards.toSet(), hasLength(32));
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

  group('Seçicideki önizleme', () {
    // Ayarlardaki tahta seçici, ızgara hücresinde `BoardBackground`
    // kullanıyor. Hücre kare değil ve görselli tahtalar bir dosyadan
    // geliyor; daha önce bu yol sessizce boş kutu çizmişti. Burada her
    // tahta o hücre ölçüsünde çizilip boş çıkmadığı denetleniyor.
    testWidgets('her tahta önizleme kutusunda görünür', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.instance.load();

      Future<List<int>> capture(String board) async {
        // Görsel önce çözümlenir: test ortamında `Image.asset`
        // eşzamansız yüklenir ve `pumpAndSettle` onu beklemez.
        if (!BoardAssets.isFlat(board)) {
          await tester.runAsync(() async {
            final provider = AssetImage(BoardAssets.boardPath(board));
            final stream = provider.resolve(ImageConfiguration.empty);
            final done = Completer<void>();
            late ImageStreamListener listener;
            listener = ImageStreamListener(
              (image, _) {
                if (!done.isCompleted) done.complete();
                stream.removeListener(listener);
              },
              onError: (error, stack) {
                if (!done.isCompleted) done.completeError(error);
                stream.removeListener(listener);
              },
            );
            stream.addListener(listener);
            await done.future;
          });
        }

        final key = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: RepaintBoundary(
                key: key,
                child: SizedBox(
                  // Seçici ızgarasındaki oranın aynısı: kare değil.
                  width: 120,
                  height: 98,
                  child: BoardBackground(board: board, fit: BoxFit.cover),
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

      final seen = <String, List<int>>{};
      for (final board in BoardAssets.boards) {
        final bytes = await capture(board);
        expect(bytes, isNotEmpty, reason: '$board önizlemesi çizilemedi');
        // Tek renk bir kutu çok küçük sıkışır; desen varsa büyür.
        expect(
          bytes.length,
          greaterThan(200),
          reason: '$board önizlemesi boş görünüyor',
        );
        seen[board] = bytes;
      }

      // İki tahta birebir aynı görünmemeli; aynıysa biri yüklenmemiştir.
      final distinct = seen.values.map((b) => b.length).toSet();
      expect(
        distinct.length,
        greaterThan(BoardAssets.boards.length ~/ 2),
        reason: 'önizlemelerin çoğu aynı çıktı',
      );
    });
  });
}
