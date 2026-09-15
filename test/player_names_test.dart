import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/screens/game_screen.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';

/// Oyuncu adları tahtanın üstünde ve altında yazılıyor; tahta dönünce
/// yer değiştiriyorlar. Kartta sığmayan uzun adlar burada tam görünüyor.

const white = 'Garry Kasparov';
const black = 'Anatoly Karpov';

Future<void> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  await SettingsService.instance.load();
  Strings.language = AppLanguage.turkish;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(500, 1100);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(const MaterialApp(
    home: GameScreen(
      uciMoves: ['e2e4', 'e7e5'],
      title: 'Kasparov - Karpov',
      whiteName: white,
      blackName: black,
    ),
  ));
  await tester.pumpAndSettle();
}

/// Adın dikey konumu; küçük olan üsttedir.
double _top(WidgetTester tester, String name) =>
    tester.getRect(find.text(name)).top;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => Strings.language = AppLanguage.system);

  testWidgets('iki ad da görünüyor', (tester) async {
    await _pump(tester);
    expect(find.text(white), findsOneWidget);
    expect(find.text(black), findsOneWidget);
  });

  testWidgets('başlangıçta siyah üstte, beyaz altta', (tester) async {
    await _pump(tester);
    expect(_top(tester, black), lessThan(_top(tester, white)));
  });

  testWidgets('tahta dönünce adlar da yer değiştiriyor', (tester) async {
    await _pump(tester);
    final beforeWhite = _top(tester, white);

    await tester.tap(find.byIcon(Icons.swap_vert_rounded));
    await tester.pumpAndSettle();

    expect(_top(tester, white), lessThan(_top(tester, black)),
        reason: 'tahta dönünce beyaz üste geçmeliydi');
    expect(_top(tester, white), isNot(beforeWhite));
  });

  testWidgets('ad yoksa rengin adı yazılıyor', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.load();
    Strings.language = AppLanguage.turkish;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(500, 1100);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const MaterialApp(
      home: GameScreen(uciMoves: ['e2e4'], title: 'Oyun'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Beyaz'), findsOneWidget);
    expect(find.text('Siyah'), findsOneWidget);
  });
}
