import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/services/opening_service.dart';

/// Açılış listesini yönetme: tekrar denetimi, toptan silme, gizleme.
///
/// Üçü de binlerce varyantlı bir listeyi elde edilebilir kılmak için var;
/// tek tek düzenlemek o ölçekte iş görmüyor.

const _text = '''
B90|Sicilian: Najdorf|Main Line|e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6
B33|Sicilian: Sveshnikov|Main Line|e4 c5 Nf3 Nc6 d4 cxd4 Nxd4 Nf6 Nc3 e5
C00|French|Ana Hat|e4 e6
D00|Queen's Pawn|Ana Hat|d4 d5
''';

Future<OpeningService> _seed() async {
  SharedPreferences.setMockInitialValues({});
  Strings.language = AppLanguage.turkish;
  OpeningService.instance.resetCache();
  final service = OpeningService.instance;
  await service.importText(_text);
  return service;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => Strings.language = AppLanguage.system);

  group('Almada tekrar denetimi', () {
    test('aynı dosya ikinci kez alınınca hiçbiri katlanmaz', () async {
      // Kullanıcının derdi buydu: bir açılışı silip geri getirmek için
      // dosyayı yeniden alınca geri kalan her şey ikiye katlanıyordu.
      final service = await _seed();
      expect((await service.all()), hasLength(4));

      final again = await service.importText(_text);
      expect(again.added, 0);
      expect(again.skipped, 4);
      expect((await service.all()), hasLength(4));
    });

    test('silinen varyant yeniden alımda geri gelir', () async {
      final service = await _seed();
      final french = (await service.all())
          .firstWhere((o) => o.family == 'French');
      await service.deleteCustom(french.id);
      expect((await service.all()), hasLength(3));

      final again = await service.importText(_text);
      expect(again.added, 1, reason: 'yalnızca silinen geri gelmeli');
      expect(again.skipped, 3);
      expect((await service.all()), hasLength(4));
    });

    test('aynı dosyanın içindeki tekrarlar da bir kez eklenir', () async {
      SharedPreferences.setMockInitialValues({});
      OpeningService.instance.resetCache();
      final result = await OpeningService.instance.importText('$_text$_text');
      expect(result.added, 4);
      expect(result.skipped, 4);
    });

    test('aynı pozisyona farklı sırayla varanlar ayrı varyant', () async {
      // Transpozisyon serbest: iki hat aynı pozisyonda bitse de farklı
      // hamle dizileri, ikisi de çalışmaya değer.
      SharedPreferences.setMockInitialValues({});
      OpeningService.instance.resetCache();
      final result = await OpeningService.instance.importText(
        'A|Bir|d4 Nf6 c4 e6 Nc3\n'
        'A|İki|c4 Nf6 d4 e6 Nc3\n',
      );
      expect(result.added, 2);
      expect(result.skipped, 0);
    });
  });

  group('Toptan silme', () {
    test('açılışlarla ilgili her şey gider', () async {
      final service = await _seed();
      final openings = await service.all();
      for (final opening in openings) {
        await service.markLearned(opening.id);
        await service.setNote(opening.id, 'not');
      }
      await service.setFamilyHidden('French', true);

      expect(await service.deleteAll(), 4);

      expect(await service.all(), isEmpty);
      expect(await service.progressMap(), isEmpty);
      expect(await service.hiddenFamilies(), isEmpty);

      // Soğuk başlangıçta da boş kalmalı; sadece bellekteki kopya
      // temizlenmiş olmasın.
      service.resetCache();
      expect(await service.all(), isEmpty);
      expect(await service.progressMap(), isEmpty);
    });

    test('boş listede sıfır döner', () async {
      SharedPreferences.setMockInitialValues({});
      OpeningService.instance.resetCache();
      expect(await OpeningService.instance.deleteAll(), 0);
    });
  });

  group('Gizleme', () {
    test('tek başlık gizlenip geri getirilebilir', () async {
      final service = await _seed();
      await service.setFamilyHidden('French', true);
      expect(await service.hiddenFamilies(), {'French'});

      await service.setFamilyHidden('French', false);
      expect(await service.hiddenFamilies(), isEmpty);
    });

    test('gizlilik kalıcı; soğuk başlangıçta duruyor', () async {
      final service = await _seed();
      await service.setFamilyHidden('French', true);
      service.resetCache();
      expect(await service.hiddenFamilies(), {'French'});
    });

    test('gizlilik aile adına bağlı, kimliğe değil', () async {
      // Kimlikler her almada yeniden üretiliyor; gizliliği kimliğe
      // bağlasaydık dosya yeniden alındığında hepsi dağılırdı.
      final service = await _seed();
      await service.setFamilyHidden('French', true);

      await service.deleteAll();
      await service.setFamilyHidden('French', true);
      await service.importText(_text);

      expect(await service.hiddenFamilies(), {'French'},
          reason: 'yeniden almadan sonra gizlilik durmalı');
    });

    group('Toplu işlemler', () {
      test('hepsini gizle', () async {
        final service = await _seed();
        await service.hideAllExcept(<String>{});
        expect(await service.hiddenFamilies(), hasLength(4));
      });

      test('seçilenler hariç hepsini gizle', () async {
        final service = await _seed();
        await service.hideAllExcept({'French', 'Sicilian: Najdorf'});
        expect(await service.hiddenFamilies(),
            {"Queen's Pawn", 'Sicilian: Sveshnikov'});
      });

      test('hepsini göster', () async {
        final service = await _seed();
        await service.hideAllExcept(<String>{});
        await service.showAllExcept(<String>{});
        expect(await service.hiddenFamilies(), isEmpty);
      });

      test('seçilenler hariç hepsini göster', () async {
        final service = await _seed();
        await service.hideAllExcept(<String>{});
        await service.showAllExcept({'French'});
        expect(await service.hiddenFamilies(), {'French'},
            reason: 'seçili olan gizli kalmalı, diğerleri açılmalı');
      });

      test('seçilen zaten görünürse gizli sayılmaz', () async {
        final service = await _seed();
        await service.setFamilyHidden('French', true);
        await service.showAllExcept({"Queen's Pawn"});
        expect(await service.hiddenFamilies(), isEmpty);
      });
    });
  });
}
