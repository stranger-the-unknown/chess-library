import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/screens/home_screen.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';

/// 10.6.0: bekleyen işlerden kapananlar.
///
/// PGN yapıştırma penceresi: metin kutusunun denetleyicisi `finally`
/// içinde pencere döner dönmez atılıyordu. Pencere kapanma animasyonunda
/// hâlâ çiziliyor ve atılmış denetleyiciye dokunuyordu (hata ayıklama
/// derlemesinde "TextEditingController was used after being disposed").
/// 10.4.0'daki açılış formu gibi: denetleyici pencerenin kendi State'inde.

void _silencePlugins({String? clipboard}) {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final channel in const [
    MethodChannel('com.ryanheise.just_audio.methods'),
    MethodChannel('dev.fluttercommunity.plus/wakelock'),
  ]) {
    messenger.setMockMethodCallHandler(channel, (call) async => null);
  }
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.getData') {
      return clipboard == null ? null : {'text': clipboard};
    }
    return null;
  });
}

Future<void> _openPasteDialog(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(700, 1100);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
  await tester.pumpAndSettle();

  await tester.tap(find.text(t('home.loadPgn')).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(t('pgn.pasteText')));
  await tester.pumpAndSettle();
  expect(find.byType(TextField), findsOneWidget);
}

/// Kapanma animasyonunu kare kare oynatır: hata tam o sırada çıkıyordu.
Future<void> _playClose(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'flutter.soundEnabled': false,
      'flutter.soundDefaultsRestored': true,
    });
    await SettingsService.instance.load();
    Strings.language = AppLanguage.turkish;
  });

  tearDown(() => Strings.language = AppLanguage.system);

  group('PGN yapıştırma penceresi', () {
    testWidgets('Vazgeç: kapanırken atılmış denetleyiciye dokunmuyor',
        (tester) async {
      _silencePlugins();
      await _openPasteDialog(tester);
      await tester.tap(find.text(t('common.cancel')));
      await _playClose(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('masaüstünde kutu odaktayken Vazgeç', (tester) async {
      // Hata masaüstünde, hata ayıklama derlemesinde görülmüştü: kutuya
      // yazılıp pencere kapatılırken.
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      _silencePlugins();
      await _openPasteDialog(tester);
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '1. e4');
      await tester.pump();
      await tester.tap(find.text(t('common.cancel')));
      await _playClose(tester);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('boş metinle Aç: uyarı veriyor, hata yok', (tester) async {
      _silencePlugins();
      await _openPasteDialog(tester);
      await tester.tap(find.text(t('common.open')));
      await _playClose(tester);
      expect(tester.takeException(), isNull);
      expect(find.text(t('home.pgnEmpty')), findsOneWidget);
    });

    testWidgets('panodaki PGN kutuya geliyor', (tester) async {
      const pgn = '1. e4 e5 2. Nf3 Nc6 *';
      _silencePlugins(clipboard: pgn);
      await _openPasteDialog(tester);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        pgn,
      );
      await tester.tap(find.text(t('common.cancel')));
      await _playClose(tester);
      expect(tester.takeException(), isNull);
    });
  });
}
