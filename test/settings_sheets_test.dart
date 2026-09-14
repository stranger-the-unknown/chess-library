import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/screens/settings_screen.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';

/// Tahta ve taş seçicileri alt sayfa olarak açılıyor. Telefonlarda
/// ekranın altında bir gezinme çubuğu var; liste onun altına uzarsa son
/// satır tıklanamaz hâle geliyor. Bu yüzden listelerin alt boşluğu
/// sistem payını da içermeli.
///
/// Masaüstünde pay sıfır olduğu için bu testler yalnızca payın hesaba
/// katıldığını gösterir; paylı ve paysız durum ayrı ayrı ölçülür.

/// Belirtilen alt sistem payıyla ayarlar ekranını kurar.
///
/// Pay pencereye verilir, widget ağacına değil: alt sayfa Navigator'ın
/// katmanında açıldığı için ekranın içine konan bir `MediaQuery` ona
/// ulaşmaz. Gerçek uygulamada pay zaten pencereden gelir.
Future<void> _pumpSettings(WidgetTester tester, double bottomInset) async {
  SharedPreferences.setMockInitialValues({});
  await SettingsService.instance.load();
  Strings.language = AppLanguage.turkish;

  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(420, 900);
  tester.view.viewPadding = FakeViewPadding(bottom: bottomInset);
  tester.view.padding = FakeViewPadding(bottom: bottomInset);

  await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
  await tester.pumpAndSettle();
}

/// Açık olan alt sayfadaki kaydırılabilir listenin alt boşluğu.
///
/// Ayarlar ekranının kendisi de kaydırılabilir; aranan liste alt
/// sayfanın içindeki.
double _bottomPadding(WidgetTester tester, Type listType) {
  final widget = tester.widget(
    find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(listType),
    ),
  );
  final padding = (widget as dynamic).padding as EdgeInsets;
  return padding.bottom;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    Strings.language = AppLanguage.system;
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views
        .first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
    view.resetViewPadding();
    view.resetPadding();
  });

  testWidgets('tahta seçici gezinme çubuğunun altına uzanmaz', (tester) async {
    const inset = 48.0;

    await _pumpSettings(tester, 0);
    await tester.tap(find.text('Tahta görünümü'));
    await tester.pumpAndSettle();
    final withoutInset = _bottomPadding(tester, GridView);

    await _pumpSettings(tester, inset);
    await tester.tap(find.text('Tahta görünümü'));
    await tester.pumpAndSettle();
    final withInset = _bottomPadding(tester, GridView);

    expect(
      withInset - withoutInset,
      inset,
      reason: 'alt sistem payı listeye eklenmemiş',
    );
  });

  testWidgets('taş seçici gezinme çubuğunun altına uzanmaz', (tester) async {
    const inset = 48.0;

    await _pumpSettings(tester, 0);
    await tester.tap(find.text('Taş takımı'));
    await tester.pumpAndSettle();
    final withoutInset = _bottomPadding(tester, ListView);

    await _pumpSettings(tester, inset);
    await tester.tap(find.text('Taş takımı'));
    await tester.pumpAndSettle();
    final withInset = _bottomPadding(tester, ListView);

    expect(
      withInset - withoutInset,
      inset,
      reason: 'alt sistem payı listeye eklenmemiş',
    );
  });
}
