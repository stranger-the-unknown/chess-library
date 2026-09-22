import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/models/puzzle.dart';
import 'package:chess_pgn_reader/screens/puzzles/puzzle_list_screen.dart';
import 'package:chess_pgn_reader/services/backup_service.dart';
import 'package:chess_pgn_reader/services/opening_service.dart';
import 'package:chess_pgn_reader/services/puzzle_service.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/services/storage_service.dart';

/// Yedekten geri yükleme çalıştığı hâlde ekranda eski veri kalıyordu:
/// ana sayfalar bir `IndexedStack` içinde canlı kaldığı için sekme
/// değiştirmek `initState`'i yeniden çalıştırmıyor. Geri yükleme artık
/// [dataVersion] sayacını artırıyor, kabuk da sayfaları sıfırdan kuruyor.

Future<void> _reset() async {
  SharedPreferences.setMockInitialValues({});
  StorageService.instance.resetCache();
  PuzzleService.instance.resetCache();
  OpeningService.instance.resetCache();
  await SettingsService.instance.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Geri yükleme öncesi anlık kopya diske yazılıyor; testte
  // `path_provider` olmadığı için geçici bir klasör veriliyor.
  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('cl_backup_test_');
    BackupService.snapshotDirectory = () async => dir;
  });
  setUp(_reset);

  group('Geri yükleme sonrası tazeleme', () {
    test('veri sürümü her geri yüklemede artar', () async {
      await StorageService.instance.createPlaylist('Liste');
      final text = await BackupService.instance.exportAll();
      final (_, data) = await BackupService.instance.read(text);

      final before = dataVersion.value;
      await BackupService.instance.apply(data);
      expect(dataVersion.value, greaterThan(before),
          reason: 'değiştirme kipinde sayaç artmadı');

      final middle = dataVersion.value;
      await BackupService.instance.apply(data, mode: ImportMode.merge);
      expect(dataVersion.value, greaterThan(middle),
          reason: 'birleştirme kipinde sayaç artmadı');
    });

    test('birleştirme yedekteki listeyi gerçekten ekliyor', () async {
      // Kaynak cihaz
      final playlist = await StorageService.instance.createPlaylist('Tal');
      final collection =
          await PuzzleService.instance.createCollection('Matlar');
      await PuzzleService.instance.importFens(
        collection,
        '3q1rk1/5pbp/5Qp1/8/8/2B5/5PPP/6K1 w - - 0 1',
      );
      final text = await BackupService.instance.exportAll();
      expect(playlist.name, 'Tal');

      // Hedef cihaz: kendi verisi var
      await _reset();
      await StorageService.instance.createPlaylist('Kendi listem');
      await PuzzleService.instance.createCollection('Kendi bulmacalarım');

      final (_, data) = await BackupService.instance.read(text);
      await BackupService.instance.apply(data, mode: ImportMode.merge);

      final names = (await StorageService.instance.loadPlaylists())
          .map((p) => p.name)
          .toList();
      expect(names, containsAll(['Kendi listem', 'Tal']));

      final collections = (await PuzzleService.instance.collections())
          .map((c) => c.name)
          .toList();
      expect(collections, containsAll(['Kendi bulmacalarım', 'Matlar']));
    });
  });

  group('Sonuç süzgeçleri', () {
    Future<PuzzleCollection> seed(String content) async {
      final collection = await PuzzleService.instance.createCollection(
        'Oyun sonu',
        isEndgame: true,
      );
      await PuzzleService.instance.importFens(collection, content);
      return collection;
    }

    Future<void> pump(WidgetTester tester, PuzzleCollection collection) async {
      tester.view.physicalSize = const Size(1600, 1400);
      tester.view.devicePixelRatio = 1;
      Strings.language = AppLanguage.turkish;
      await tester.pumpWidget(
        MaterialApp(home: PuzzleListScreen(collection: collection)),
      );
      await tester.pumpAndSettle();
    }

    tearDown(() {
      Strings.language = AppLanguage.system;
      final view =
          TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });

    testWidgets('etiket yoksa süzgeçler gösterilmez', (tester) async {
      // Sonucu işaretli hiçbir bulmaca yokken süzgeçler hiçbir şey
      // bulamaz; görünmeleri "çalışmıyor" izlenimi veriyordu.
      final collection = await seed(
        '8/8/3k4/8/8/8/6Q1/7K w - - 0 1|az-tas||1\n'
        '8/8/3k4/8/8/8/6R1/7K w - - 0 1|az-tas||2\n',
      );
      await pump(tester, collection);
      expect(find.text('Beyaz kazanır'), findsNothing);
      expect(find.text('Beraberlik'), findsNothing);
      expect(find.text('Siyah kazanır'), findsNothing);
    });

    testWidgets('etiketli dosyada süzgeçler görünür ve süzer', (tester) async {
      final collection = await seed(
        '8/8/3k4/8/8/8/6Q1/7K w - - 0 1|az-tas,beyaz-kazanir||1\n'
        '3k4/8/2KP4/8/8/8/8/8 b - - 0 1|az-tas,beraberlik||2\n'
        '8/8/3p1K2/1k1P4/8/8/8/8 b - - 0 1|az-tas,siyah-kazanir||3\n',
      );
      await pump(tester, collection);

      List<String> numbers() => tester
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data ?? '')
          .where((t) => t.startsWith('#'))
          .toList();

      expect(numbers(), ['#1', '#2', '#3']);

      await tester.tap(find.text('Beyaz kazanır'));
      await tester.pumpAndSettle();
      expect(numbers(), ['#1']);

      await tester.tap(find.text('Beraberlik'));
      await tester.pumpAndSettle();
      expect(numbers(), ['#2']);

      await tester.tap(find.text('Siyah kazanır'));
      await tester.pumpAndSettle();
      expect(numbers(), ['#3']);
    });
  });

  test('hamle sesleri varsayılan olarak açık', () async {
    expect(SettingsService.instance.soundEnabled, isTrue);

    // Kapatılıp yeniden okunduğunda kapalı kalmalı, silinince açılmalı.
    SettingsService.instance.soundEnabled = false;
    await SettingsService.instance.load();
    expect(SettingsService.instance.soundEnabled, isFalse);

    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.load();
    expect(SettingsService.instance.soundEnabled, isTrue);
  });
}
