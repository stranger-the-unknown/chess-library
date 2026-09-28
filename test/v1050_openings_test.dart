import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/services/backup_service.dart';
import 'package:chess_pgn_reader/services/opening_service.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'support/device.dart';

/// 10.5.0: açılışlarda sıralama ve siyah tarafından çalışma — servis,
/// metin dosyası ve tam yedek. İki depoyla da koşuyor (bkz. BUILD.md);
/// ekran testleri `v1050_openings_ui_test.dart` içinde (sahte saatli
/// ekran testlerinde dosya deposunun gerçek disk işlemleri bitmiyor).

final _service = OpeningService.instance;

Future<void> _add(String family, String variation, String moves) =>
    _service.addFromSan(family: family, variation: variation, moveText: moves);

/// Kayıttaki sıra: (aile, varyant) çiftleri.
Future<List<String>> _order() async {
  _service.resetCache();
  return [for (final o in await _service.all()) '${o.family}/${o.variation}'];
}

Future<void> _fresh() async {
  await resetDevice({
    'flutter.soundEnabled': false,
    'flutter.animateMoves': true,
    'flutter.soundDefaultsRestored': true,
  });
  _service.resetCache();
  await SettingsService.instance.load();
  Strings.language = AppLanguage.turkish;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('cl_v1050_backup_');
    BackupService.snapshotDirectory = () async => dir;
  });

  setUp(_fresh);

  tearDown(() => Strings.language = AppLanguage.system);

  group('Sıralama (servis)', () {
    test('başlıklar yeni sırayla, içleri korunuyor', () async {
      await _add('A', 'a1', '1. e4');
      await _add('B', 'b1', '1. d4');
      await _add('A', 'a2', '1. e4 e5');
      await _add('C', 'c1', '1. c4');

      await _service.reorderFamilies(['C', 'A']);
      // B listede yok: eski sırasıyla sonda.
      expect(await _order(), ['C/c1', 'A/a1', 'A/a2', 'B/b1']);
    });

    test('varyantlar başlığın içinde yer değiştiriyor, başkaları yerinde',
        () async {
      await _add('A', 'a1', '1. e4');
      await _add('B', 'b1', '1. d4');
      await _add('A', 'a2', '1. e4 e5');
      await _add('A', 'a3', '1. e4 c5');
      final ids = {
        for (final o in await _service.all()) o.variation: o.id,
      };

      await _service.reorderVariations('A', [ids['a3']!, ids['a1']!]);
      // A'nın varyantları ilk varyantının yerinde toplanıyor; a2 listede
      // yok, sona.
      expect(await _order(), ['A/a3', 'A/a1', 'A/a2', 'B/b1']);
    });
  });

  group('Siyah tarafı (servis)', () {
    test('işaret, yeniden adlandırma ve silme', () async {
      await _add('Sicilya', 'Najdorf', '1. e4 c5');
      await _add('İspanyol', 'Ana', '1. e4 e5');
      await _service.setFamilyBlack('Sicilya', true);
      expect(await _service.blackFamilies(), {'Sicilya'});

      await _service.renameFamily('Sicilya', 'Sicilya Savunması');
      _service.resetCache();
      expect(await _service.blackFamilies(), {'Sicilya Savunması'});

      // Silinen başlığın ayarları gidiyor: aynı adla sonradan eklenen
      // başlık gizli ya da siyahtan başlamasın.
      await _service.setFamilyHidden('Sicilya Savunması', true);
      await _service.deleteFamily('Sicilya Savunması');
      _service.resetCache();
      expect(await _service.blackFamilies(), isEmpty);
      expect(await _service.hiddenFamilies(), isEmpty);
    });

    test('metin dosyasıyla taşınıyor, eski sürüm satırı atlıyor', () async {
      await _add('Sicilya', 'Najdorf', '1. e4 c5 2. Nf3 d6');
      await _add('İspanyol', 'Ana', '1. e4 e5 2. Nf3 Nc6 3. Bb5');
      await _service.setFamilyBlack('Sicilya', true);
      final text = await _service.exportText();
      expect(text, contains('#side|black|Sicilya'));

      await _fresh();
      final result = await _service.importText(text);
      expect(result.added, 2);
      expect(await _service.blackFamilies(), {'Sicilya'});
      // Sıra da korunuyor.
      expect(await _order(), ['Sicilya/Najdorf', 'İspanyol/Ana']);
    });
  });

  group('Tam yedek', () {
    test('değiştir: sıra ve siyah tarafı geri geliyor', () async {
      await _add('A', 'a1', '1. e4');
      await _add('B', 'b1', '1. d4');
      await _service.reorderFamilies(['B', 'A']);
      await _service.setFamilyBlack('B', true);
      final text = await BackupService.instance.exportAll();

      await _fresh();
      final (_, data) = await BackupService.instance.read(text);
      await BackupService.instance.apply(data);
      _service.resetCache();
      expect(await _order(), ['B/b1', 'A/a1']);
      expect(await _service.blackFamilies(), {'B'});
    });

    test('birleştir: siyah işaretleri ekleniyor, cihazın sırası kalıyor',
        () async {
      await _add('A', 'a1', '1. e4');
      await _service.setFamilyBlack('A', true);
      final text = await BackupService.instance.exportAll();

      await _fresh();
      await _add('C', 'c1', '1. c4');
      await _service.setFamilyBlack('C', true);
      final (_, data) = await BackupService.instance.read(text);
      await BackupService.instance.apply(data, mode: ImportMode.merge);
      _service.resetCache();
      expect(await _service.blackFamilies(), {'A', 'C'});
      expect(await _order(), ['C/c1', 'A/a1']);
    });
  });
}
