import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/models/puzzle.dart';
import 'package:chess_pgn_reader/screens/puzzles/puzzle_list_screen.dart';
import 'package:chess_pgn_reader/services/puzzle_service.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';

/// Aralık süzgeci: listeyi numara aralığına daraltır ve daraldığını
/// söyler. Şerit olmasa kullanıcı kısalmış listenin sebebini anlamaz.

Future<PuzzleCollection> _seed() async {
  SharedPreferences.setMockInitialValues({});
  PuzzleService.instance.resetCache();
  await SettingsService.instance.load();
  Strings.language = AppLanguage.turkish;
  final collection = await PuzzleService.instance.createCollection('Deneme');
  await PuzzleService.instance.importFens(
    collection,
    List.generate(10, (i) => '8/8/3k4/8/8/8/6Q1/7K w - - 0 ${i + 1}').join('\n'),
  );
  return collection;
}

List<String> _numbers(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data ?? '')
    .where((s) => s.startsWith('#'))
    .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => Strings.language = AppLanguage.system);

  testWidgets('aralık listeyi daraltıyor ve şerit görünüyor', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 1600);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final collection = await _seed();
    await tester.pumpWidget(
      MaterialApp(home: PuzzleListScreen(collection: collection)),
    );
    await tester.pumpAndSettle();
    expect(_numbers(tester), hasLength(10));

    await tester.tap(find.byIcon(Icons.more_vert).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aralık göster'));
    await tester.pumpAndSettle();

    // Arama kutusu da bir TextField; alanlar pencere içinde aranmalı.
    final fields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), '3');
    await tester.enterText(fields.at(1), '5');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Tamam'));
    await tester.pumpAndSettle();

    expect(_numbers(tester), ['#3', '#4', '#5']);
    expect(find.textContaining('3-5 arası'), findsOneWidget);

    // Şeritteki çarpı süzgeci kaldırmalı.
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(_numbers(tester), hasLength(10));
  });
}
