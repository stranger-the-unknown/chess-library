import 'dart:async' show Completer;
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/main.dart' show unawaited;
import 'package:chess_pgn_reader/services/app_store.dart';
import 'package:chess_pgn_reader/services/backup_service.dart';
import 'package:chess_pgn_reader/services/corrupt_data.dart';
import 'package:chess_pgn_reader/services/opening_service.dart';
import 'package:chess_pgn_reader/services/puzzle_service.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/services/storage_service.dart';

/// 10.2.0: Windows'ta veri kendi dosyalarında (B-1'in kökten çözümü, B-3).

const _playlists = '[{"id":"p1","name":"Tal","games":[]}]';
const _collections = '[{"id":"u_1","name":"Mat","puzzles":[]}]';
const _progress = '{"u_1#0":{"solved":true}}';
const _hidden = ['Fransız', 'Sicilya'];

/// 10.1.x'teki gibi her şey tercih dosyasında.
Map<String, Object> _legacyPrefs() => {
      'playlists_v2': _playlists,
      'puzzle_collections_v1': _collections,
      'puzzle_progress_v1': _progress,
      'openings_hidden_v1': List<String>.from(_hidden),
      'themeMode': 2,
      'soundEnabled': false,
    };

void main() {
  late Directory support;
  final sep = Platform.pathSeparator;

  File dataFile(String name) => File('${support.path}${sep}veri$sep$name');
  Future<Set<String>> prefsKeys() async =>
      (await SharedPreferences.getInstance()).getKeys();
  List<File> filesIn(Directory dir, bool Function(String name) test) => dir
      .listSync()
      .whereType<File>()
      .where((f) => test(f.uri.pathSegments.last))
      .toList();

  setUp(() async {
    support = await Directory.systemTemp.createTemp('cl_v1020_');
    AppStore.instance = PrefsStore();
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    AppStore.instance = PrefsStore();
    BackupService.debugAfterWrite = null;
    try {
      await support.delete(recursive: true);
    } catch (_) {}
  });

  group('taşıma', () {
    test('veri kendi dosyalarına geçiyor, ayarlar tercih dosyasında kalıyor',
        () async {
      SharedPreferences.setMockInitialValues(_legacyPrefs());
      await File('${support.path}${sep}shared_preferences.json')
          .writeAsString('ESKI-TERCIH-DOSYASI');

      final store = await FileStore.open(support);

      expect(await dataFile('playlists_v2.txt').readAsString(), _playlists);
      expect(await dataFile('puzzle_collections_v1.txt').readAsString(),
          _collections);
      expect(await dataFile('puzzle_progress_v1.txt').readAsString(),
          _progress);
      expect(
          jsonDecode(
              await dataFile('openings_hidden_v1.list.json').readAsString()),
          _hidden);
      expect(await prefsKeys(), {'themeMode', 'soundEnabled'},
          reason: 'tercih dosyasında yalnızca ayarlar kalmalı');

      expect(await store.getString('playlists_v2'), _playlists);
      expect(await store.getStringList('openings_hidden_v1'), _hidden);

      final copies = filesIn(
          support, (n) => n.startsWith(FileStore.migrationCopyPrefix));
      expect(copies, hasLength(1), reason: 'eski dosyanın kopyası kalmalı');
      expect(await copies.single.readAsString(), 'ESKI-TERCIH-DOSYASI');
    });

    test('ikinci açılışta taşınacak bir şey yok, veri aynı', () async {
      SharedPreferences.setMockInitialValues(_legacyPrefs());
      await File('${support.path}${sep}shared_preferences.json')
          .writeAsString('x');
      await FileStore.open(support);
      final again = await FileStore.open(support);

      expect(await again.getString('puzzle_progress_v1'), _progress);
      expect(
          filesIn(support, (n) => n.startsWith(FileStore.migrationCopyPrefix)),
          hasLength(1));
    });

    test('yazılamayan anahtar tercih dosyasından silinmiyor', () async {
      SharedPreferences.setMockInitialValues(_legacyPrefs());
      // Dosyanın yerinde bir klasör var: yazma (yeniden adlandırma) olmaz.
      await Directory('${support.path}${sep}veri${sep}playlists_v2.txt')
          .create(recursive: true);

      final store = await FileStore.open(support);

      expect(await prefsKeys(), contains('playlists_v2'),
          reason: 'doğrulanmadan silinmemeli');
      expect(await store.getString('playlists_v2'), _playlists,
          reason: 'tercih dosyasından okunmaya devam etmeli');
      expect(await prefsKeys(), isNot(contains('puzzle_progress_v1')),
          reason: 'diğerleri taşınmalı');
    });

    test('eski sürüme dönülüp geri gelinince yenisi geçerli, eskisi saklanıyor',
        () async {
      await dataFile('x').parent.create(recursive: true);
      await dataFile('playlists_v2.txt').writeAsString('[ESKI]');
      SharedPreferences.setMockInitialValues({'playlists_v2': '[YENI]'});

      final store = await FileStore.open(support);

      expect(await store.getString('playlists_v2'), '[YENI]');
      expect(await dataFile('playlists_v2.txt').readAsString(), '[YENI]');
      final kept = filesIn(Directory('${support.path}${sep}veri'),
          (n) => n.startsWith('playlists_v2.txt.eski-'));
      expect(kept, hasLength(1), reason: 'üstüne yazılan dosya saklanmalı');
      expect(await kept.single.readAsString(), '[ESKI]');
    });

    test('klasör açılamazsa hata veriyor, veri tercih dosyasında kalıyor',
        () async {
      SharedPreferences.setMockInitialValues(_legacyPrefs());
      final notADir = File('${support.path}${sep}dosya');
      await notADir.writeAsString('x');

      await expectLater(
          FileStore.open(Directory(notADir.path)), throwsA(anything));
      expect(await prefsKeys(), containsAll(<String>['playlists_v2']));
    });
  });

  group('B-1 yarıda kalan yazma veriyi bozmuyor', () {
    test('yeniden adlandırılamamış geçici dosya yok sayılıyor', () async {
      final store = await FileStore.open(support);
      expect(await store.setString('puzzle_progress_v1', '{"a":1}'), isTrue);

      // Süreç yazmanın ortasında öldü: geçici dosya yarım, asıl dosya eski.
      await dataFile('puzzle_progress_v1.txt.tmp').writeAsString('{"a":');

      final reopened = await FileStore.open(support);
      expect(await reopened.getString('puzzle_progress_v1'), '{"a":1}');
      expect(await dataFile('puzzle_progress_v1.txt.tmp').exists(), isFalse);
    });

    test('tercih dosyası kaybolsa da veri yerinde', () async {
      SharedPreferences.setMockInitialValues(_legacyPrefs());
      await FileStore.open(support);

      // 10.1.3'e kadar bu, bütün verinin kaybı demekti.
      SharedPreferences.setMockInitialValues({});
      final store = await FileStore.open(support);

      expect(await store.getString('playlists_v2'), _playlists);
      expect(await store.getString('puzzle_collections_v1'), _collections);
      expect(await store.getStringList('openings_hidden_v1'), _hidden);
    });

    test('bozuk liste dosyası kenara alınıyor, açılış sürüyor', () async {
      await dataFile('x').parent.create(recursive: true);
      await dataFile('openings_hidden_v1.list.json').writeAsString('["Fra');
      final before = corruptRecords.value;

      final store = await FileStore.open(support);

      expect(await store.getStringList('openings_hidden_v1'), isNull);
      expect(corruptRecords.value, before + 1);
      expect(
          filesIn(Directory('${support.path}${sep}veri'),
              (n) => n.startsWith('openings_hidden_v1.list.json.bozuk-')),
          hasLength(1),
          reason: 'silinmemeli, kenara alınmalı');
    });
  });

  group('B-3 her yazma yalnızca kendi dosyasını yazıyor', () {
    test('ayar ve ilerleme yazmaları büyük veriye dokunmuyor', () async {
      SharedPreferences.setMockInitialValues(_legacyPrefs());
      final store = await FileStore.open(support);
      final big = dataFile('puzzle_collections_v1.txt');
      final lists = dataFile('playlists_v2.txt');
      final bigTime = await big.lastModified();
      final listsTime = await lists.lastModified();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Ayar: yalnızca küçük tercih dosyası. Eskiden bu, bütün veriyi
      // taşıyan tek dosyanın baştan yazılması demekti.
      await (await SharedPreferences.getInstance()).setInt('themeMode', 1);
      expect((await prefsKeys()).where(AppStore.isDataKey), isEmpty,
          reason: 'tercih dosyası veri taşımamalı');

      // Bulmaca denemesi: yalnızca ilerleme dosyası.
      await store.setString('puzzle_progress_v1', '{"u_1#0":{"attempts":2}}');
      expect(await dataFile('puzzle_progress_v1.txt').readAsString(),
          '{"u_1#0":{"attempts":2}}');
      expect(await big.lastModified(), bigTime);
      expect(await lists.lastModified(), listsTime);
    });

    test('aynı anahtara art arda yazmalar sırayla, sonuncusu kalıyor',
        () async {
      final store = await FileStore.open(support);
      final writes = [
        for (var i = 0; i < 50; i++)
          store.setString('puzzle_progress_v1', '{"n":$i}'),
      ];
      expect(await Future.wait(writes), everyElement(isTrue));

      expect(await dataFile('puzzle_progress_v1.txt').readAsString(),
          '{"n":49}');
      expect(await store.getString('puzzle_progress_v1'), '{"n":49}');
      expect(await dataFile('puzzle_progress_v1.txt.tmp').exists(), isFalse);
    });
  });

  group('servisler ve yedek dosya deposunda', () {
    setUp(() {
      BackupService.snapshotDirectory = () async => support;
      StorageService.instance.resetCache();
      PuzzleService.instance.resetCache();
      OpeningService.instance.resetCache();
    });

    test('yedeğin biçimi iki depoda aynı (eski ve yeni sürüm birbirini okur)',
        () async {
      SharedPreferences.setMockInitialValues(_legacyPrefs());
      final fromPrefs = jsonDecode(await BackupService.instance.exportAll())
          as Map<String, dynamic>;

      SharedPreferences.setMockInitialValues(_legacyPrefs());
      AppStore.instance = await FileStore.open(support);
      final fromFiles = jsonDecode(await BackupService.instance.exportAll())
          as Map<String, dynamic>;

      expect(fromFiles['data'], fromPrefs['data']);
      expect(fromFiles['checksum'], fromPrefs['checksum']);
    });

    test('dosya deposunda silme ve geri yükleme tam tur', () async {
      SharedPreferences.setMockInitialValues(_legacyPrefs());
      final store = await FileStore.open(support);
      AppStore.instance = store;
      await SettingsService.instance.load();
      final text = await BackupService.instance.exportAll();

      await BackupService.instance.wipeAll();
      expect((await store.readAll()).keys.where(AppStore.isDataKey), isEmpty);
      expect(
          filesIn(Directory('${support.path}${sep}veri'),
              (n) => n.endsWith('.txt') || n.endsWith('.list.json')),
          isEmpty);

      final (_, data) = await BackupService.instance.read(text);
      await BackupService.instance.apply(data);
      expect(await store.getString('playlists_v2'), _playlists);
      expect(await store.getStringList('openings_hidden_v1'), _hidden);
      expect((await StorageService.instance.loadPlaylists()).single.name,
          'Tal');
      expect(await dataFile('playlists_v2.txt').readAsString(), _playlists);
    });

    test('yarıda kalan geri yükleme dosya deposunda da geri alınıyor',
        () async {
      SharedPreferences.setMockInitialValues(_legacyPrefs());
      final store = await FileStore.open(support);
      AppStore.instance = store;
      final before = await store.readAll();

      final frozen = Completer<void>();
      BackupService.debugAfterWrite = (written) {
        if (!frozen.isCompleted) frozen.complete();
        return Completer<void>().future; // süreç burada öldü
      };
      unawaited(BackupService.instance.apply(const {
        'playlists_v2': '[]',
        'x_ayar': 1,
      }));
      await frozen.future;
      BackupService.debugAfterWrite = null;

      // Uygulama yeniden açılıyor: aynı klasörde yeni bir depo.
      AppStore.instance = await FileStore.open(support);
      expect(await BackupService.instance.recoverInterruptedRestore(), isTrue);
      final after = await AppStore.instance.readAll();
      for (final key in before.keys.where(AppStore.isDataKey)) {
        expect(after[key], before[key], reason: key);
      }
    });
  });
}
