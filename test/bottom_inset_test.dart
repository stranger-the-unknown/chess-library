import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/screens/home_screen.dart';
import 'package:chess_pgn_reader/screens/openings/opening_visibility_screen.dart';
import 'package:chess_pgn_reader/screens/puzzles/puzzle_list_screen.dart';
import 'package:chess_pgn_reader/screens/settings_screen.dart';
import 'package:chess_pgn_reader/services/opening_service.dart';
import 'package:chess_pgn_reader/services/puzzle_service.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';

/// Telefonun gezinme çubuğu ekranın altından yer kapıyor. Alt sayfaların
/// son satırı oraya denk gelirse tıklanamıyor; bu, uygulamada en sık
/// tekrarlayan arayüz hatası oldu.
///
/// Burada boşluk ölçülmüyor, **çizilen yer** ölçülüyor: son öğenin alt
/// kenarı sistem payının içine giriyor mu. Hangi yolla (SafeArea, elle
/// padding) halledildiği fark etmez, sonuç denetlenir.

const double _inset = 48;
const Size _screen = Size(420, 900);

Future<void> _pump(WidgetTester tester, Widget screen) async {
  SharedPreferences.setMockInitialValues({});
  await SettingsService.instance.load();
  Strings.language = AppLanguage.turkish;

  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = _screen;
  tester.view.viewPadding = const FakeViewPadding(bottom: _inset);
  tester.view.padding = const FakeViewPadding(bottom: _inset);

  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pumpAndSettle();
}

/// Sayfadaki son öğe sistem payının üstünde kalmalı.
void _expectAboveNavigationBar(WidgetTester tester, Finder last, String what) {
  final rect = tester.getRect(last);
  expect(
    rect.bottom,
    lessThanOrEqualTo(_screen.height - _inset),
    reason: '$what gezinme çubuğunun altına taşıyor '
        '(${rect.bottom.toStringAsFixed(0)} > ${_screen.height - _inset})',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    Strings.language = AppLanguage.system;
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
    view.resetViewPadding();
    view.resetPadding();
  });

  testWidgets('motora karşı oyna sayfası', (tester) async {
    await _pump(tester, const HomeScreen());
    await tester.tap(find.text('Motora karşı oyna'));
    await tester.pumpAndSettle();

    // Sayfanın en altındaki düğme: başlat.
    final start = find.widgetWithText(ElevatedButton, 'Başla');
    expect(start, findsOneWidget);
    _expectAboveNavigationBar(tester, start, 'başlat düğmesi');
  });

  testWidgets('dil seçici', (tester) async {
    await _pump(tester, const SettingsScreen());
    await tester.tap(find.text('Dil'));
    await tester.pumpAndSettle();

    final tiles = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(ListTile),
    );
    expect(tiles, findsWidgets);
    _expectAboveNavigationBar(tester, tiles.last, 'son dil satırı');
  });

  testWidgets('tahta seçici', (tester) async {
    await _pump(tester, const SettingsScreen());
    await tester.tap(find.text('Tahta görünümü'));
    await tester.pumpAndSettle();

    final grid = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(GridView),
    );
    final padding = (tester.widget(grid) as GridView).padding as EdgeInsets;
    expect(padding.bottom, greaterThanOrEqualTo(_inset),
        reason: 'tahta ızgarasının alt boşluğu sistem payını içermeli');
  });

  testWidgets('taş seçici', (tester) async {
    await _pump(tester, const SettingsScreen());
    await tester.tap(find.text('Taş takımı'));
    await tester.pumpAndSettle();

    final list = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(ListView),
    );
    final padding = (tester.widget(list) as ListView).padding as EdgeInsets;
    expect(padding.bottom, greaterThanOrEqualTo(_inset),
        reason: 'taş listesinin alt boşluğu sistem payını içermeli');
  });

  // Tam ekran açılan liste ekranlarında altta gezinme çubuğu yok; son
  // satır doğrudan telefonun tuşlarının üstüne denk geliyor. Alt
  // sayfalardan farklı olarak bunlarda hiçbir pay hesabı yoktu.

  testWidgets('bulmaca listesinin son satırı', (tester) async {
    SharedPreferences.setMockInitialValues({});
    PuzzleService.instance.resetCache();
    await SettingsService.instance.load();
    final collection =
        await PuzzleService.instance.createCollection('Deneme');
    await PuzzleService.instance.importFens(
      collection,
      List.generate(
        30,
        (i) => '8/8/3k4/8/8/8/6Q1/7K w - - 0 ${i + 1}',
      ).join('\n'),
    );

    await _pump(tester, PuzzleListScreen(collection: collection));
    final list = find.byType(ListView).last;
    await tester.drag(list, const Offset(0, -4000));
    await tester.pumpAndSettle();

    final rows = find.descendant(of: list, matching: find.byType(InkWell));
    expect(rows, findsWidgets);
    _expectAboveNavigationBar(tester, rows.last, 'son bulmaca satırı');
  });

  testWidgets('gizli açılışlar ekranının son satırı', (tester) async {
    SharedPreferences.setMockInitialValues({});
    OpeningService.instance.resetCache();
    await SettingsService.instance.load();
    await OpeningService.instance.importText(
      List.generate(30, (i) => 'Aile $i|Ana Hat|e4 e5 Nf3').join('\n'),
    );

    await _pump(tester, const OpeningVisibilityScreen());
    await tester.drag(find.byType(ListView), const Offset(0, -4000));
    await tester.pumpAndSettle();

    final rows = find.byType(CheckboxListTile);
    expect(rows, findsWidgets);
    _expectAboveNavigationBar(tester, rows.last, 'son başlık satırı');
  });
}
