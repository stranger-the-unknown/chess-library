import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/screens/openings/opening_list_screen.dart';
import 'package:chess_pgn_reader/screens/openings/opening_visibility_screen.dart';
import 'package:chess_pgn_reader/services/opening_service.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';

/// Gizleme ekranını ekranın kendisinde sınar: servis doğru olsa bile
/// kutucuk (seçim) ile göz düğmesi (durum) karışırsa özellik kullanılamaz
/// hale gelir.

const _text = '''
B90|Sicilian: Najdorf|Main Line|e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6
C00|French|Ana Hat|e4 e6
D00|Queen's Pawn|Ana Hat|d4 d5
''';

Future<void> _seed() async {
  SharedPreferences.setMockInitialValues({});
  OpeningService.instance.resetCache();
  await SettingsService.instance.load();
  Strings.language = AppLanguage.turkish;
  await OpeningService.instance.importText(_text);
}

Future<void> _pumpVisibility(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    const MaterialApp(home: OpeningVisibilityScreen()),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(_seed);
  tearDown(() {
    Strings.language = AppLanguage.system;
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('gizlenen başlık ana listede görünmez', (tester) async {
    await OpeningService.instance.setFamilyHidden('French', true);

    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(const MaterialApp(home: OpeningListScreen()));
    await tester.pumpAndSettle();

    expect(find.text('French'), findsNothing);
    expect(find.text('Sicilian: Najdorf'), findsOneWidget);
    expect(find.text("Queen's Pawn"), findsOneWidget);
  });

  testWidgets('göz düğmesi tek başlığı gizler', (tester) async {
    await _pumpVisibility(tester);

    final row = find.ancestor(
      of: find.text('French'),
      matching: find.byType(CheckboxListTile),
    );
    await tester.tap(find.descendant(of: row, matching: find.byType(IconButton)));
    await tester.pumpAndSettle();

    expect(await OpeningService.instance.hiddenFamilies(), {'French'});
  });

  testWidgets('seçilenler hariç hepsini gizle', (tester) async {
    await _pumpVisibility(tester);

    // Kutucuk seçimdir: işaretlenen başlık görünür kalır.
    await tester.tap(find.descendant(
      of: find.ancestor(
        of: find.text('French'),
        matching: find.byType(CheckboxListTile),
      ),
      matching: find.byType(Checkbox),
    ));
    await tester.pumpAndSettle();
    expect(find.text('1 seçili'), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('hariç hepsini gizle').last);
    await tester.pumpAndSettle();

    expect(await OpeningService.instance.hiddenFamilies(),
        {'Sicilian: Najdorf', "Queen's Pawn"});
  });

  testWidgets('seçim yokken menü hepsini gizler', (tester) async {
    await _pumpVisibility(tester);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Hepsini gizle'), findsOneWidget);
    await tester.tap(find.text('Hepsini gizle'));
    await tester.pumpAndSettle();

    expect(await OpeningService.instance.hiddenFamilies(), hasLength(3));
  });

  testWidgets('her şey gizliyken yol gösterilir', (tester) async {
    // "Eşleşen açılış yok" demek burada yanıltıcı olurdu: liste dolu,
    // sadece hepsi gizli. Kullanıcı çıkışsız kalmamalı.
    await OpeningService.instance.hideAllExcept(<String>{});

    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(const MaterialApp(home: OpeningListScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Eşleşen açılış yok.'), findsNothing);
    expect(find.textContaining('Bütün başlıklar gizli'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Gizli açılışlar'));
    await tester.pumpAndSettle();
    expect(find.byType(OpeningVisibilityScreen), findsOneWidget);
  });

  testWidgets('hepsini göster gizlilikleri kaldırır', (tester) async {
    await OpeningService.instance.hideAllExcept(<String>{});
    await _pumpVisibility(tester);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hepsini göster'));
    await tester.pumpAndSettle();

    expect(await OpeningService.instance.hiddenFamilies(), isEmpty);
  });
}
