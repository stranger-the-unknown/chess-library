import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/screens/home_shell.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';

/// Geri tuşu, başka bir sekmedeyken uygulamadan çıkıyordu. Android'in
/// gezinme kuralı, geri tuşunun önce başlangıç hedefine götürmesini ve
/// çıkışın oradan olmasını söyler. Bu dosya o davranışı bağlar.

Future<void> _pumpShell(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  await SettingsService.instance.load();
  Strings.language = AppLanguage.turkish;

  tester.view.devicePixelRatio = 1;
  // Dar pencere: alt gezinme çubuğu görünsün.
  tester.view.physicalSize = const Size(420, 900);

  await tester.pumpWidget(const MaterialApp(home: HomeShell()));
  await tester.pumpAndSettle();
}

/// Kabuğun geri tuşuna izin verip vermediği.
bool _canPop(WidgetTester tester) {
  // `PopScope` genel türlü olduğu için `byType` ile aranamıyor.
  final finder = find.byWidgetPredicate((widget) => widget is PopScope);
  final scope = tester.widgetList(finder).first as dynamic;
  return scope.canPop as bool;
}

/// Sistem geri tuşunu taklit eder.
Future<void> _pressBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    Strings.language = AppLanguage.system;
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views
        .first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('ilk sekmede geri tuşu uygulamadan çıkar', (tester) async {
    await _pumpShell(tester);
    expect(
      _canPop(tester),
      isTrue,
      reason: 'Oyna sekmesindeyken geri tuşu çıkışa izin vermeli',
    );
  });

  testWidgets('başka sekmede geri tuşu önce Oyna sekmesine döner', (
    tester,
  ) async {
    await _pumpShell(tester);

    await tester.tap(find.text('Ayarlar'));
    await tester.pumpAndSettle();
    expect(
      _canPop(tester),
      isFalse,
      reason: 'Ayarlar sekmesindeyken geri tuşu çıkmamalı',
    );

    await _pressBack(tester);

    // Oyna sekmesine dönülmüş olmalı: artık çıkışa izin var.
    expect(
      _canPop(tester),
      isTrue,
      reason: 'geri tuşu Oyna sekmesine döndürmedi',
    );
  });

  testWidgets('her sekmeden tek geri tuşuyla Oyna sekmesine dönülür', (
    tester,
  ) async {
    await _pumpShell(tester);

    for (final tab in ['Bulmacalar', 'Açılışlar', 'Listelerim', 'Ayarlar']) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      expect(_canPop(tester), isFalse, reason: '$tab sekmesinde çıkılıyor');

      await _pressBack(tester);
      expect(
        _canPop(tester),
        isTrue,
        reason: '$tab sekmesinden Oyna sekmesine dönülmedi',
      );
    }
  });
}
