import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/screens/game_screen.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';

/// 10.1.2: oyuncu satırı ve üst başlık.

const _moves = ['e2e4', 'e7e5'];

Future<void> _pump(WidgetTester tester, Widget screen) async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/wakelock'),
          (c) async => null);
  SharedPreferences.setMockInitialValues({
    'flutter.soundEnabled': false,
    'flutter.soundDefaultsRestored': true,
  });
  Strings.language = AppLanguage.turkish;
  await SettingsService.instance.load();
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1536, 816);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pumpAndSettle();
}

TextStyle _styleOf(WidgetTester tester, String metin) =>
    tester.widget<Text>(find.text(metin)).style!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('iki oyuncu adı da birebir aynı biçimde', (tester) async {
    // Sırası gelenin adı koyu, diğerininki soluk yazılıyordu; ekranda
    // biri kalınmış gibi okunuyordu. Sırayı artık adın solundaki
    // yuvarlağın halkası söylüyor.
    await _pump(
      tester,
      const GameScreen(
        uciMoves: _moves,
        whiteName: 'Kubilay',
        blackName: 'Rakip',
      ),
    );

    final beyaz = _styleOf(tester, 'Kubilay');
    final siyah = _styleOf(tester, 'Rakip');

    // İkisi de koyu (onSurface): solgun olan yok.
    final scheme = Theme.of(tester.element(find.byType(GameScreen)))
        .colorScheme;
    expect(beyaz.color, scheme.onSurface, reason: 'beyazın adı koyu olmalı');
    expect(siyah.color, scheme.onSurface, reason: 'siyahın adı koyu olmalı');
    expect(beyaz.color, siyah.color, reason: 'adların rengi aynı olmalı');
    expect(beyaz.fontWeight, siyah.fontWeight,
        reason: 'adların kalınlığı aynı olmalı');
    expect(beyaz.fontSize, siyah.fontSize);
  });

  testWidgets('motora karşı oyunda başlıkta düzey yazmıyor', (tester) async {
    // Dar ekranda başlığa sığmayıp üç noktaya iniyordu; düzey zaten
    // tahtanın yanındaki oyuncu satırında yazıyor.
    await _pump(
      tester,
      const GameScreen(mode: GameMode.versusEngine, uciMoves: _moves),
    );

    expect(find.text(t('game.vsEngine')), findsOneWidget);
    expect(t('game.vsEngine'), isNot(contains('·')),
        reason: 'başlıkta düzey ayracı kalmamalı');
  });
}
