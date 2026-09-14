import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';

/// Tahta artık hazır bir listeden değil, kullanıcının seçtiği iki
/// renkten doğuyor. Bu, kare adlarının okunurluğunu kullanıcının eline
/// bırakıyor: iki rengi birbirine yakın seçerse koordinatlar kaybolabilir.
/// Aşağıdaki denetimler bunun olamayacağını gösteriyor.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => Strings.language = AppLanguage.system);

  group('Renk paleti', () {
    test('yüz renk var ve hiçbiri yinelenmiyor', () {
      expect(BoardAssets.palette, hasLength(100));
      expect(BoardAssets.palette.toSet(), hasLength(100));
    });

    test('hepsi tam donuk', () {
      for (final color in BoardAssets.palette) {
        expect(
          color >> 24 & 0xFF,
          0xFF,
          reason: '${color.toRadixString(16)} saydam',
        );
      }
    });

    test('başlangıç renkleri palette bulunur', () {
      // Aksi hâlde ayarlar ilk açıldığında hiçbir kare seçili görünmezdi.
      expect(BoardAssets.palette, contains(BoardAssets.defaultLight));
      expect(BoardAssets.palette, contains(BoardAssets.defaultDark));
    });

    test('açıktan koyuya sıralı', () {
      // Izgaranın üst satırları açık kare, alt satırları koyu kare için.
      double lightness(int argb) => HSLColor.fromColor(Color(argb)).lightness;
      for (int i = 1; i < BoardAssets.palette.length; i++) {
        expect(
          lightness(BoardAssets.palette[i]),
          lessThanOrEqualTo(lightness(BoardAssets.palette[i - 1]) + 0.001),
          reason: '$i. renk sırayı bozuyor',
        );
      }
    });

    test('eski hazır tahtaların renkleri kaybolmadı', () {
      // 3.0'dan önce seçilebilen on beş tahtanın kare renkleri palette
      // duruyor; kullanıcı eski görünümünü yeniden kurabilir.
      const legacy = [
        0xFFF0D9B5, 0xFFB58863, // kahve
        0xFFEEEED2, 0xFF769656, // yeşil
        0xFFE8E9CC, 0xFF5E8A4E, // turnuva
        0xFFDEE3E6, 0xFF8CA2AD, // mavi
        0xFFDCDCDC, 0xFF8F8F8F, // gri
        0xFFC6CDD6, 0xFF69788A, // arduvaz
        0xFFEDDCBE, 0xFFC0A47B, // kum
        0xFFE6E0EC, 0xFF9B8BB4, // mor
        0xFFF2EDE3, 0xFFC3B7A4, // fildişi
        0xFFF3DFE2, 0xFFBE8A96, // gül
        0xFFD8E8E6, 0xFF74A09B, // deniz yeşili
        0xFFAEB7C4, 0xFF4B5A72, // gece mavisi
        0xFFB79062, 0xFF53331F, // koyu ahşap
        0xFFC2A076, 0xFF654328, // ceviz
        0xFFDCBF92, 0xFF986D45, // meşe
      ];
      for (final color in legacy) {
        expect(
          BoardAssets.palette,
          contains(color),
          reason: '${color.toRadixString(16)} palette yok',
        );
      }
    });
  });

  group('Kare adlarının rengi', () {
    test('paletteki her renk ikilisinde okunur kalır', () {
      // 100 x 100 = 10.000 olası tahta. Hiçbirinde kare adı zemine
      // karışmamalı; karışacaksa siyah ya da beyaza düşülür.
      double worst = double.infinity;
      int worstLight = 0;
      int worstDark = 0;

      for (final light in BoardAssets.palette) {
        for (final dark in BoardAssets.palette) {
          for (final onLight in [true, false]) {
            final background = onLight ? light : dark;
            final text = BoardAssets.coordinateColor(
              light: light,
              dark: dark,
              onLightSquare: onLight,
            );
            final ratio = BoardAssets.contrastRatio(text, background);
            if (ratio < worst) {
              worst = ratio;
              worstLight = light;
              worstDark = dark;
            }
          }
        }
      }

      expect(
        worst,
        greaterThanOrEqualTo(2.0),
        reason: 'en kötü ikili: '
            '${worstLight.toRadixString(16)} / ${worstDark.toRadixString(16)}',
      );
    });

    test('iki renk aynı seçilse bile yazı görünür', () {
      for (final color in BoardAssets.palette) {
        for (final onLight in [true, false]) {
          final text = BoardAssets.coordinateColor(
            light: color,
            dark: color,
            onLightSquare: onLight,
          );
          expect(
            BoardAssets.contrastRatio(text, color),
            greaterThan(4.0),
            reason: '${color.toRadixString(16)} üzerinde kare adı okunmuyor',
          );
        }
      }
    });

    test('alışılmış tahtada karşıt kare rengi kullanılmayı sürdürür', () {
      // Klasik kahve tahtada yazı siyah/beyaza düşmemeli; eski görünüm
      // aynen korunmalı.
      expect(
        BoardAssets.coordinateColor(
          light: BoardAssets.defaultLight,
          dark: BoardAssets.defaultDark,
          onLightSquare: true,
        ),
        BoardAssets.defaultDark,
      );
      expect(
        BoardAssets.coordinateColor(
          light: BoardAssets.defaultLight,
          dark: BoardAssets.defaultDark,
          onLightSquare: false,
        ),
        BoardAssets.defaultLight,
      );
    });

    test('karşıtlık oranı bilinen değerleri veriyor', () {
      expect(
        BoardAssets.contrastRatio(0xFF000000, 0xFFFFFFFF),
        closeTo(21, 0.1),
      );
      expect(
        BoardAssets.contrastRatio(0xFF123456, 0xFF123456),
        closeTo(1, 0.001),
      );
    });
  });

  group('İşaret rengi', () {
    test('her koyu kare rengi için tanımlı ve donuk', () {
      for (final color in BoardAssets.palette) {
        expect(BoardAssets.markColor(color) >> 24 & 0xFF, 0xFF);
      }
    });

    test('tahtanın kendi renginden yeterince uzak', () {
      for (final color in BoardAssets.palette) {
        final boardHue = HSVColor.fromColor(Color(color)).hue;
        final markHue =
            HSVColor.fromColor(Color(BoardAssets.markColor(color))).hue;
        final raw = (markHue - boardHue).abs();
        final distance = raw > 180 ? 360 - raw : raw;
        expect(
          distance,
          greaterThan(40),
          reason: '${color.toRadixString(16)} üzerinde işaret rengi çok yakın',
        );
      }
    });
  });

  group('Eski ayardan geçiş', () {
    test('tahta adı renk çiftine çevriliyor', () async {
      SharedPreferences.setMockInitialValues({'boardTheme': 'walnut'});
      await SettingsService.instance.load();
      expect(SettingsService.instance.boardLight, 0xFFC2A076);
      expect(SettingsService.instance.boardDark, 0xFF654328);

      // Çevrildikten sonra eski anahtar kalmamalı, yenisi yazılmalı.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('boardTheme'), isNull);
      expect(prefs.getInt('boardLight'), 0xFFC2A076);
    });

    test('tanınmayan ad varsayılana düşer', () async {
      SharedPreferences.setMockInitialValues({'boardTheme': 'boyle-bir-tahta'});
      await SettingsService.instance.load();
      expect(SettingsService.instance.boardLight, BoardAssets.defaultLight);
      expect(SettingsService.instance.boardDark, BoardAssets.defaultDark);
    });

    test('yeni ayar varsa eski ada bakılmaz', () async {
      SharedPreferences.setMockInitialValues({
        'boardTheme': 'walnut',
        'boardLight': 0xFFEEEED2,
        'boardDark': 0xFF769656,
      });
      await SettingsService.instance.load();
      expect(SettingsService.instance.boardLight, 0xFFEEEED2);
      expect(SettingsService.instance.boardDark, 0xFF769656);
    });
  });

  group('Taş takımları', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.instance.load();
    });

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
      }
    });
  });
}
