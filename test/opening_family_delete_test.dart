import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/screens/openings/opening_list_screen.dart';
import 'package:chess_pgn_reader/services/opening_service.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';

/// Başlığı silme düğmesi açılış ekranının kendisinde sınanır: mantık
/// doğru olsa bile menü, `ExpansionTile`'ın açılma okuyla ya da başlığa
/// dokunmayla çakışırsa kullanıcı ona hiç erişemez.

Future<void> seed() async {
  SharedPreferences.setMockInitialValues({});
  OpeningService.instance.resetCache();
  await SettingsService.instance.load();
  Strings.language = AppLanguage.turkish;

  final service = OpeningService.instance;
  await service.addFromSan(
    family: 'Sicilya',
    variation: 'Najdorf',
    moveText: '1. e4 c5 2. Nf3 d6 3. d4 cxd4 4. Nxd4 Nf6 5. Nc3 a6',
  );
  await service.addFromSan(
    family: 'Sicilya',
    variation: 'Dragon',
    moveText: '1. e4 c5 2. Nf3 d6 3. d4 cxd4 4. Nxd4 Nf6 5. Nc3 g6',
  );
  await service.addFromSan(
    family: 'Fransız',
    variation: 'Winawer',
    moveText: '1. e4 e6 2. d4 d5 3. Nc3 Bb4',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(seed);
  tearDown(() => Strings.language = AppLanguage.system);

  testWidgets('başlık menüsünden silme bütün aileyi kaldırır', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: OpeningListScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Sicilya'), findsOneWidget);
    expect(find.text('Fransız'), findsOneWidget);

    // Sicilya başlığının kendi menüsü.
    final menu = find.descendant(
      of: find.ancestor(
        of: find.text('Sicilya'),
        matching: find.byType(ExpansionTile),
      ),
      matching: find.byIcon(Icons.more_vert),
    );
    expect(menu, findsOneWidget);

    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Başlığı sil').last);
    await tester.pumpAndSettle();

    // Onay istenmeli; onaysız silinmemeli.
    expect(find.textContaining('2 varyantın hepsi'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sil'));
    await tester.pumpAndSettle();

    expect(find.text('Sicilya'), findsNothing);
    expect(find.text('Fransız'), findsOneWidget);
    expect((await OpeningService.instance.all()), hasLength(1));
  });

  testWidgets('menüye dokunmak başlığı açıp kapatmaz', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: OpeningListScreen()));
    await tester.pumpAndSettle();

    // Kapalıyken varyant adları görünmüyor.
    expect(find.text('Najdorf'), findsNothing);

    final menu = find.descendant(
      of: find.ancestor(
        of: find.text('Sicilya'),
        matching: find.byType(ExpansionTile),
      ),
      matching: find.byIcon(Icons.more_vert),
    );
    await tester.tap(menu);
    await tester.pumpAndSettle();

    expect(find.text('Najdorf'), findsNothing,
        reason: 'menü dokunuşu başlığı da açmamalı');
  });
}
