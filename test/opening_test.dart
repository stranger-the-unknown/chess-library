import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/services/opening_service.dart';

/// Açılış varyantlarının eklenmesi, düzenlenmesi ve metinle taşınması.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Strings.language = AppLanguage.turkish;
    OpeningService.instance.resetCache();
  });

  tearDown(() => Strings.language = AppLanguage.system);

  test('aynı ailenin altına birden çok varyant eklenebilir', () async {
    final service = OpeningService.instance;
    await service.addFromSan(
      family: 'İspanyol Açılışı',
      variation: 'Breyer',
      moveText: '1. e4 e5 2. Nf3 Nc6 3. Bb5 a6',
    );
    await service.addFromSan(
      family: 'İspanyol Açılışı',
      variation: 'Berlin',
      moveText: '1. e4 e5 2. Nf3 Nc6 3. Bb5 Nf6',
    );

    final all = await service.all();
    final family = all.where((o) => o.family == 'İspanyol Açılışı').toList();
    expect(family.length, 2);
    expect(family.map((o) => o.variation), containsAll(['Breyer', 'Berlin']));
  });

  test('varyant adı boşsa aile içinde numaralandırılır', () async {
    final service = OpeningService.instance;
    for (int i = 0; i < 3; i++) {
      await service.addFromSan(
        family: 'Sicilya',
        variation: '',
        moveText: '1. e4 c5 2. Nf3',
      );
    }
    // Başka bir ailede numaralandırma sıfırdan başlamalı.
    await service.addFromSan(
      family: 'Fransız',
      variation: '',
      moveText: '1. e4 e6',
    );

    final all = await service.all();
    final sicilian = all.where((o) => o.family == 'Sicilya').toList();
    final french = all.where((o) => o.family == 'Fransız').toList();

    final prefix = t('openings.defaultVariation');
    expect(
      sicilian.map((o) => o.variation).toList(),
      ['$prefix 1', '$prefix 2', '$prefix 3'],
    );
    expect(french.single.variation, '$prefix 1');
  });

  test('silme sonrası numara çakışmaz', () async {
    final service = OpeningService.instance;
    final prefix = t('openings.defaultVariation');
    for (int i = 0; i < 3; i++) {
      await service.addFromSan(
        family: 'Kral Hint',
        variation: '',
        moveText: '1. d4 Nf6 2. c4 g6',
      );
    }
    final all = await service.all();
    final second =
        all.firstWhere((o) => o.variation == '$prefix 2');
    await service.deleteCustom(second.id);

    await service.addFromSan(
      family: 'Kral Hint',
      variation: '',
      moveText: '1. d4 Nf6 2. c4 g6 3. Nc3',
    );
    final after = await service.all();
    final names =
        after.where((o) => o.family == 'Kral Hint').map((o) => o.variation);
    expect(names.toSet().length, names.length, reason: 'numara tekrar etmemeli');
    expect(names, contains('$prefix 4'));
  });

  test('varyant düzenlenebilir', () async {
    final service = OpeningService.instance;
    final added = await service.addFromSan(
      family: 'Eski aile',
      variation: 'Eski ad',
      moveText: '1. e4 e5',
    );
    expect(added, isNotNull);

    final ok = await service.editCustom(
      id: added!.id,
      family: 'Yeni aile',
      variation: 'Yeni ad',
      moveText: '1. d4 d5 2. c4',
    );
    expect(ok, isTrue);

    final all = await service.all();
    final edited = all.firstWhere((o) => o.id == added.id);
    expect(edited.family, 'Yeni aile');
    expect(edited.variation, 'Yeni ad');
    expect(edited.sanMoves, ['d4', 'd5', 'c4']);
  });

  test('geçersiz hamlelerle düzenleme kaydı bozmaz', () async {
    final service = OpeningService.instance;
    final added = await service.addFromSan(
      family: 'Aile',
      variation: 'Varyant',
      moveText: '1. e4 e5',
    );
    final ok = await service.editCustom(
      id: added!.id,
      family: 'Aile',
      variation: 'Varyant',
      moveText: 'bu hamle değil',
    );
    expect(ok, isFalse);

    final all = await service.all();
    expect(all.firstWhere((o) => o.id == added.id).sanMoves, ['e4', 'e5']);
  });

  test('metinden alma: üç biçim de tanınır', () async {
    final service = OpeningService.instance;
    const text = '''
# yorum satırı

Aile A|Varyant A|1. e4 e5 2. Nf3
C20|Aile B|Varyant B|1. d4 d5
C42|Aile C|Varyant C|e2e4 e7e5|1. e4 e5
bu satır bozuk
''';
    final added = await service.importText(text);
    expect(added, 3);

    final all = await service.all();
    expect(all.map((o) => o.family),
        containsAll(['Aile A', 'Aile B', 'Aile C']));
    expect(all.firstWhere((o) => o.family == 'Aile B').eco, 'C20');
  });

  test('verilen metin aynen geri okunur', () async {
    final service = OpeningService.instance;
    await service.addFromSan(
      family: 'İspanyol',
      variation: 'Ana hat',
      moveText: '1. e4 e5 2. Nf3 Nc6 3. Bb5',
    );
    await service.addFromSan(
      family: 'Sicilya',
      variation: 'Najdorf',
      moveText: '1. e4 c5 2. Nf3 d6 3. d4 cxd4 4. Nxd4 Nf6 5. Nc3 a6',
    );
    final text = await service.exportText();

    SharedPreferences.setMockInitialValues({});
    service.resetCache();
    final added = await service.importText(text);

    expect(added, 2, reason: 'başlık satırları atlanmalı');
    final all = await service.all();
    expect(all.length, 2);
    final naj = all.firstWhere((o) => o.variation == 'Najdorf');
    expect(naj.sanMoves.length, 10);
    expect(naj.family, 'Sicilya');
  });

  test('büyük alma ilerleme bildirir ve donmaz', () async {
    final service = OpeningService.instance;
    final lines = List<String>.generate(
      600,
      (i) => 'Aile ${i % 7}||1. e4 e5 2. Nf3 Nc6',
    );
    int reports = 0;
    int lastDone = 0;
    final added = await service.importText(
      lines.join('\n'),
      onProgress: (done, total) {
        expect(total, 600);
        expect(done, greaterThanOrEqualTo(lastDone));
        lastDone = done;
        reports++;
      },
    );
    expect(added, 600);
    expect(lastDone, 600);
    expect(reports, greaterThan(1));
  });
}
