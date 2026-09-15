import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/screens/settings_screen.dart';
import 'package:chess_pgn_reader/services/backup_service.dart';
import 'package:chess_pgn_reader/services/opening_service.dart';
import 'package:chess_pgn_reader/services/puzzle_service.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/services/storage_service.dart';

/// "Tüm verileri sıfırla" geri dönüşü olmayan tek işlem.
///
/// İki şey ayrı ayrı sınanıyor: gerçekten her şeyi siliyor mu, ve
/// onaylanmadan hiçbir şeye dokunmuyor mu.

Future<void> _seed() async {
  SharedPreferences.setMockInitialValues({});
  StorageService.instance.resetCache();
  PuzzleService.instance.resetCache();
  OpeningService.instance.resetCache();
  await SettingsService.instance.load();
  Strings.language = AppLanguage.turkish;

  await StorageService.instance.createPlaylist('Tal');
  final collection = await PuzzleService.instance.createCollection('Matlar');
  await PuzzleService.instance.importFens(
    collection,
    '3q1rk1/5pbp/5Qp1/8/8/2B5/5PPP/6K1 w - - 0 1',
  );
  await OpeningService.instance.importText('Sicilya|Najdorf|e4 c5 Nf3 d6');
  SettingsService.instance.soundEnabled = false;
}

Future<bool> _isEmpty() async {
  StorageService.instance.resetCache();
  PuzzleService.instance.resetCache();
  OpeningService.instance.resetCache();
  final lists = await StorageService.instance.loadPlaylists();
  final collections = await PuzzleService.instance.collections();
  final openings = await OpeningService.instance.all();
  return lists.isEmpty && collections.isEmpty && openings.isEmpty;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => Strings.language = AppLanguage.system);

  test('her şeyi siliyor ve ayarları varsayılana döndürüyor', () async {
    await _seed();
    expect(await _isEmpty(), isFalse, reason: 'önce dolu olmalıydı');

    final removed = await BackupService.instance.wipeAll();
    expect(removed, greaterThan(0));

    expect(await _isEmpty(), isTrue);
    // Ayar da sıfırlanmalı: ses varsayılanı açık.
    expect(SettingsService.instance.soundEnabled, isTrue);
  });

  test('silme sonrası sayaç artıyor, açık ekranlar tazeleniyor', () async {
    await _seed();
    final before = dataVersion.value;
    await BackupService.instance.wipeAll();
    expect(dataVersion.value, greaterThan(before));
  });

  testWidgets('onaylanmadan hiçbir şey silinmiyor', (tester) async {
    await _seed();
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Tüm verileri sıfırla'), 300);
    await tester.tap(find.text('Tüm verileri sıfırla'));
    await tester.pumpAndSettle();

    // Onay istenmeli ve neyin gideceğini söylemeli.
    expect(find.textContaining('geri alınamaz'), findsOneWidget);

    // Vazgeç: hiçbir şey silinmemeli.
    await tester.tap(find.widgetWithText(TextButton, 'Vazgeç'));
    await tester.pumpAndSettle();
    expect(await _isEmpty(), isFalse, reason: 'vazgeçince silinmemeliydi');

    // Şimdi onayla.
    await tester.tap(find.text('Tüm verileri sıfırla'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Hepsini sil'));
    await tester.pumpAndSettle();
    expect(await _isEmpty(), isTrue);
  });
}
