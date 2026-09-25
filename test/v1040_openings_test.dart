import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/screens/openings/opening_list_screen.dart';
import 'package:chess_pgn_reader/services/opening_service.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';

/// 10.4.0: açılış başlıklarının yönetimi.
///
/// Başlığın menüsünde "Varyant ekle" (başlık hazır yazılı) ve "Başlığı
/// yeniden adlandır"; formda başlık kutusu var olan başlıkları öneriyor.
/// Eskiden bir başlığa varyant eklemek için adını yeniden yazmak
/// gerekiyordu; "Ispanyol" ile "İspanyol" sessizce iki ayrı başlık
/// oluyordu.

final _service = OpeningService.instance;

Future<void> _add(String family, String variation, String moves) async {
  await _service.addFromSan(
    family: family,
    variation: variation,
    moveText: moves,
  );
}

Future<void> _pump(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(700, 1100);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const MaterialApp(home: OpeningListScreen()));
  await tester.pumpAndSettle();
}

/// Bir başlığın ⋮ menüsünü açar.
Future<void> _openFamilyMenu(WidgetTester tester, String family) async {
  final tile = find.ancestor(
    of: find.text(family),
    matching: find.byType(ExpansionTile),
  );
  await tester.tap(find.descendant(
    of: tile,
    matching: find.byTooltip(t('openings.familyMenu')),
  ));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _service.resetCache();
    await SettingsService.instance.load();
    Strings.language = AppLanguage.turkish;
  });

  tearDown(() => Strings.language = AppLanguage.system);

  group('Başlığı yeniden adlandırma (servis)', () {
    test('bütün varyantlar taşınıyor, ilerleme ve not kalıyor', () async {
      await _add('Ispanyol', 'Ana hat', '1. e4 e5 2. Nf3 Nc6 3. Bb5');
      await _add('Ispanyol', 'Berlin', '1. e4 e5 2. Nf3 Nc6 3. Bb5 Nf6');
      await _add('Sicilya', 'Najdorf', '1. e4 c5');
      final berlin =
          (await _service.all()).firstWhere((o) => o.variation == 'Berlin');
      await _service.setNote(berlin.id, 'duvar');

      final moved = await _service.renameFamily('Ispanyol', 'İspanyol');
      expect(moved, 2);

      _service.resetCache();
      final all = await _service.all();
      expect(all.where((o) => o.family == 'İspanyol'), hasLength(2));
      expect(all.where((o) => o.family == 'Ispanyol'), isEmpty);
      expect(all.where((o) => o.family == 'Sicilya'), hasLength(1));
      expect(all.firstWhere((o) => o.id == berlin.id).note, 'duvar');
    });

    test('var olan başlığa taşınınca birleşiyor', () async {
      await _add('A', 'bir', '1. e4');
      await _add('B', 'iki', '1. d4');
      await _add('B', 'üç', '1. c4');
      expect(await _service.renameFamily('A', 'B'), 1);
      final all = await _service.all();
      expect(all.every((o) => o.family == 'B'), isTrue);
    });

    test('görünürlük kaynağın görünürlüğü oluyor', () async {
      await _add('Görünen', 'bir', '1. e4');
      await _add('Gizli hedef', 'iki', '1. d4');
      await _add('Gizli kaynak', 'üç', '1. c4');
      await _service.setHiddenFamilies({'Gizli hedef', 'Gizli kaynak'});

      // Görünen başlık gizli bir başlığa katıldı: birleşen başlık açılıyor.
      await _service.renameFamily('Görünen', 'Gizli hedef');
      expect(await _service.hiddenFamilies(), isNot(contains('Gizli hedef')));

      // Gizli bir başlık yeni ada taşındı: gizli kalıyor.
      await _service.renameFamily('Gizli kaynak', 'Yeni');
      final hidden = await _service.hiddenFamilies();
      expect(hidden, contains('Yeni'));
      expect(hidden, isNot(contains('Gizli kaynak')));
    });

    test('boş ya da aynı ad bir şey değiştirmiyor', () async {
      await _add('A', 'bir', '1. e4');
      expect(await _service.renameFamily('A', '   '), 0);
      expect(await _service.renameFamily('A', 'A'), 0);
      expect(await _service.renameFamily('Yok', 'B'), 0);
      expect((await _service.all()).single.family, 'A');
    });
  });

  group('Başlık menüsü', () {
    testWidgets('"Varyant ekle" formu başlık yazılı açıyor', (tester) async {
      await _add('İspanyol', 'Ana hat', '1. e4 e5 2. Nf3 Nc6 3. Bb5');
      await _pump(tester);

      await _openFamilyMenu(tester, 'İspanyol');
      await tester.tap(find.text(t('openings.addToFamily')));
      await tester.pumpAndSettle();

      final familyField = tester.widget<TextField>(
        find.widgetWithText(TextField, t('openings.family')),
      );
      expect(familyField.controller!.text, 'İspanyol');

      await tester.enterText(
        find.widgetWithText(TextField, t('openings.moves')),
        'Berlin | 1. e4 e5 2. Nf3 Nc6 3. Bb5 Nf6\n'
        'Morphy | 1. e4 e5 2. Nf3 Nc6 3. Bb5 a6',
      );
      await tester.tap(find.text(t('common.add')));
      await tester.pumpAndSettle();

      final family = (await _service.all())
          .where((o) => o.family == 'İspanyol')
          .map((o) => o.variation)
          .toList();
      expect(family, ['Ana hat', 'Berlin', 'Morphy']);
    });

    testWidgets('başlık yeniden adlandırılıyor', (tester) async {
      await _add('Ispanyol', 'Ana hat', '1. e4 e5');
      await _add('Ispanyol', 'Berlin', '1. e4 e5 2. Nf3');
      await _pump(tester);

      await _openFamilyMenu(tester, 'Ispanyol');
      await tester.tap(find.text(t('openings.renameFamily')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'İspanyol');
      await tester.tap(find.text(t('common.save')));
      await tester.pumpAndSettle();

      expect(find.text('İspanyol'), findsOneWidget);
      expect(find.text('Ispanyol'), findsNothing);
      expect(
        (await _service.all()).every((o) => o.family == 'İspanyol'),
        isTrue,
      );
    });

    testWidgets('var olan başlığa verilen ad önce birleştirmeyi soruyor',
        (tester) async {
      await _add('A', 'bir', '1. e4');
      await _add('B', 'iki', '1. d4');
      await _pump(tester);

      await _openFamilyMenu(tester, 'A');
      await tester.tap(find.text(t('openings.renameFamily')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'B');
      await tester.tap(find.text(t('common.save')));
      await tester.pumpAndSettle();

      expect(find.text(t('openings.merge')), findsOneWidget);
      // Vazgeçilirse hiçbir şey değişmiyor.
      await tester.tap(find.text(t('common.giveUp')));
      await tester.pumpAndSettle();
      expect((await _service.all()).map((o) => o.family).toSet(), {'A', 'B'});

      await _openFamilyMenu(tester, 'A');
      await tester.tap(find.text(t('openings.renameFamily')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'B');
      await tester.tap(find.text(t('common.save')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('openings.merge')));
      await tester.pumpAndSettle();
      expect((await _service.all()).map((o) => o.family).toSet(), {'B'});
    });
  });

  group('Başlık önerisi', () {
    Future<void> openForm(WidgetTester tester) async {
      await tester.tap(find.byTooltip(t('openings.addOwn')));
      await tester.pumpAndSettle();
    }

    Finder familyField() => find.widgetWithText(TextField, t('openings.family'));

    /// Öneri listesindeki satır (arkadaki başlık da bir ListTile).
    Finder suggestion(String text) => find.descendant(
          of: find.byKey(const ValueKey('opening-family-options')),
          matching: find.text(text),
        );

    testWidgets('yazarken var olan başlık öneriliyor, seçilince yazılıyor',
        (tester) async {
      await _add('İspanyol Açılışı', 'Ana hat', '1. e4 e5');
      await _add('Sicilya', 'Najdorf', '1. e4 c5');
      await _pump(tester);
      await openForm(tester);

      // Türkçe büyük/küçük harf farkı gözetilmiyor: "isp" → "İspanyol".
      await tester.enterText(familyField(), 'isp');
      await tester.pumpAndSettle();
      final option = suggestion('İspanyol Açılışı');
      expect(option, findsOneWidget);
      expect(suggestion('Sicilya'), findsNothing);

      await tester.tap(option);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(familyField()).controller!.text,
        'İspanyol Açılışı',
      );
      expect(find.byKey(const ValueKey('opening-family-options')),
          findsNothing,
          reason: 'tam ad yazılınca öneri kalkıyor');
    });

    testWidgets('yeni bir başlık da yazılabiliyor', (tester) async {
      await _add('Sicilya', 'Najdorf', '1. e4 c5');
      await _pump(tester);
      await openForm(tester);

      await tester.enterText(familyField(), 'Kendi hattım');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('opening-family-options')),
          findsNothing);
      await tester.enterText(
        find.widgetWithText(TextField, t('openings.moves')),
        '1. d4 d5',
      );
      await tester.tap(find.text(t('common.add')));
      await tester.pumpAndSettle();
      expect(
        (await _service.all()).map((o) => o.family),
        contains('Kendi hattım'),
      );
    });
  });
}
