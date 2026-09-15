import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/main.dart';
import 'package:chess_pgn_reader/screens/home_shell.dart';
import 'package:chess_pgn_reader/services/backup_service.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/services/storage_service.dart';

/// Tema varsayılanı: ilk kurulumda cihazın ayarı.
///
/// Kullanıcı ayarlardan açıkça bir kip seçmediği sürece uygulama telefonun
/// gece/gündüz ayarını izler. Seçim yapıldığında kaydedilir ve cihazı
/// izlemeyi bırakır — varsayılanı değiştirmek bu seçimi ezmemeli.

Future<void> _freshInstall() async {
  SharedPreferences.setMockInitialValues({});
  StorageService.instance.resetCache();
  await SettingsService.instance.load();
}

/// [ChessApp]'i kurup gerçekte hangi temanın uygulandığını döndürür.
Future<Brightness> _renderedBrightness(
  WidgetTester tester,
  Brightness device,
) async {
  tester.platformDispatcher.platformBrightnessTestValue = device;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(420, 900);

  await tester.pumpWidget(const ChessApp());
  await tester.pumpAndSettle();

  final context = tester.element(find.byType(HomeShell));
  return Theme.of(context).brightness;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await _freshInstall();
    Strings.language = AppLanguage.turkish;
  });

  tearDown(() {
    Strings.language = AppLanguage.system;
    final binding = TestWidgetsFlutterBinding.instance;
    binding.platformDispatcher.clearPlatformBrightnessTestValue();
    binding.platformDispatcher.views.first
      ..resetPhysicalSize()
      ..resetDevicePixelRatio();
  });

  test('ilk kurulumda cihazın ayarı izleniyor', () async {
    expect(SettingsService.instance.themeMode, ThemeMode.system);
  });

  test('kullanıcının seçimi varsayılanı eziyor', () async {
    for (final chosen in [ThemeMode.dark, ThemeMode.light, ThemeMode.system]) {
      SettingsService.instance.themeMode = chosen;
      // Yeniden açılış: ayar diskten okunuyor.
      await SettingsService.instance.load();
      expect(SettingsService.instance.themeMode, chosen,
          reason: 'kaydedilen seçim açılışta korunmalı');
    }
  });

  test('tüm verileri sıfırlayınca cihazın ayarına dönülüyor', () async {
    SettingsService.instance.themeMode = ThemeMode.light;
    await BackupService.instance.wipeAll();
    await SettingsService.instance.load();
    expect(SettingsService.instance.themeMode, ThemeMode.system);
  });

  group('Ekrana yansıyan tema', () {
    testWidgets('telefon gece modundaysa uygulama da gece modunda açılıyor',
        (tester) async {
      expect(await _renderedBrightness(tester, Brightness.dark),
          Brightness.dark);
    });

    testWidgets('telefon gündüz modundaysa uygulama da gündüz modunda açılıyor',
        (tester) async {
      expect(await _renderedBrightness(tester, Brightness.light),
          Brightness.light);
    });

    testWidgets('seçim yapılmışsa cihazın ayarı dikkate alınmıyor',
        (tester) async {
      SettingsService.instance.themeMode = ThemeMode.dark;
      expect(await _renderedBrightness(tester, Brightness.light),
          Brightness.dark);
    });
  });
}
