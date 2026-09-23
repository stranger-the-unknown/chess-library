import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:chess_pgn_reader/models/playlist.dart';
import 'package:chess_pgn_reader/services/backup_service.dart';
import 'package:chess_pgn_reader/services/opening_service.dart';
import 'package:chess_pgn_reader/services/puzzle_service.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/services/storage_service.dart';
import 'support/device.dart';

/// Yedekleme, uygulamanın kullanıcı verisine dokunan tek yeridir; bir
/// hata sessizce veri kaybettirir. Bu yüzden her yol ayrı denetlenir:
/// tam tur, birleştirme, bozuk dosya, yarım kalan yazma.

Future<void> _resetAll() async {
  await resetDevice({});
  StorageService.instance.resetCache();
  PuzzleService.instance.resetCache();
  OpeningService.instance.resetCache();
  await SettingsService.instance.load();
}

/// Örnek bir veri kümesi kurar ve kaç kayıt yazıldığını döner.
Future<void> _seed() async {
  final playlist = await StorageService.instance.createPlaylist('Tal');
  await StorageService.instance.addGames(playlist.id, [
    SavedGame(
      id: 'g1',
      name: 'Tal - Botvinnik',
      uciMoves: const ['e2e4', 'e7e5'],
      createdAt: DateTime(2026, 1, 2),
      white: 'Tal',
      black: 'Botvinnik',
      result: '1-0',
      note: 'güzel kurban',
      read: true,
      favorite: true,
    ),
    SavedGame(
      id: 'g2',
      name: 'Fischer - Spassky',
      uciMoves: const ['d2d4', 'd7d5'],
      createdAt: DateTime(2026, 1, 3),
      white: 'Fischer',
      black: 'Spassky',
      result: '1/2-1/2',
    ),
  ]);

  final collection = await PuzzleService.instance.createCollection(
    'Matlar',
    isEndgame: true,
  );
  await PuzzleService.instance.importFens(
    collection,
    '3q1rk1/5pbp/5Qp1/8/8/2B5/5PPP/6K1 w - - 0 1\n'
    '6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1',
  );
  final puzzles = await PuzzleService.instance.puzzlesOf(collection);
  await PuzzleService.instance.markSolved(puzzles.first.id);

  await OpeningService.instance.addFromSan(
    family: 'Sicilya',
    variation: 'Najdorf',
    moveText: '1. e4 c5 2. Nf3 d6',
  );

  SettingsService.instance.pieceSet = 'celtic';
  SettingsService.instance.boardTheme = 'teal';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Geri yükleme öncesi anlık kopya diske yazılıyor; testte
  // `path_provider` olmadığı için geçici bir klasör veriliyor.
  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('cl_backup_test_');
    BackupService.snapshotDirectory = () async => dir;
  });
  setUp(_resetAll);

  group('Tam tur', () {
    test('dışa aktarılan yedek birebir geri yüklenir', () async {
      await _seed();
      final text = await BackupService.instance.exportAll();

      final (summary, _) = await BackupService.instance.read(text);
      expect(summary.playlists, 1);
      expect(summary.games, 2);
      expect(summary.puzzleCollections, 1);
      expect(summary.puzzles, 2);
      expect(summary.openings, 1);
      expect(summary.hasSettings, isTrue);

      // Cihazı boşalt, sonra yedeği yükle.
      await _resetAll();
      expect(await StorageService.instance.loadPlaylists(), isEmpty);

      final (_, data) = await BackupService.instance.read(text);
      await BackupService.instance.apply(data);

      final playlists = await StorageService.instance.loadPlaylists();
      expect(playlists, hasLength(1));
      expect(playlists.first.name, 'Tal');
      expect(playlists.first.games, hasLength(2));

      final game = playlists.first.games.first;
      expect(game.read, isTrue, reason: 'okundu işareti taşınmadı');
      expect(game.favorite, isTrue, reason: 'favori taşınmadı');
      expect(game.note, 'güzel kurban', reason: 'not taşınmadı');

      final collections = await PuzzleService.instance.collections();
      expect(collections, hasLength(1));
      expect(collections.first.isEndgame, isTrue,
          reason: 'oyun sonu işareti taşınmadı');

      final puzzles = await PuzzleService.instance.puzzlesOf(collections.first);
      expect(puzzles, hasLength(2));
      final progress = await PuzzleService.instance.progressOf(puzzles.first.id);
      expect(progress.solved, isTrue, reason: 'çözüldü bilgisi taşınmadı');
      expect(progress.solvedAt, isNotNull, reason: 'çözüm tarihi taşınmadı');

      final openings = (await OpeningService.instance.all())
          .where((o) => o.custom)
          .toList();
      expect(openings, hasLength(1));
      expect(openings.first.variation, 'Najdorf');

      expect(SettingsService.instance.pieceSet, 'celtic');
      expect(SettingsService.instance.boardTheme, 'teal');
    });

    test('boş cihazın yedeği de geçerlidir', () async {
      final text = await BackupService.instance.exportAll();
      final (summary, data) = await BackupService.instance.read(text);
      expect(summary.playlists, 0);
      await BackupService.instance.apply(data);
      expect(await StorageService.instance.loadPlaylists(), isEmpty);
    });
  });

  group('Birleştirme', () {
    test('var olan listeler korunur, yedektekiler eklenir', () async {
      await _seed();
      final text = await BackupService.instance.exportAll();

      // Başka bir "cihaz": kendi listesi var.
      await _resetAll();
      await StorageService.instance.createPlaylist('Kendi listem');
      SettingsService.instance.pieceSet = 'fantasy';

      final (_, data) = await BackupService.instance.read(text);
      await BackupService.instance.apply(data, mode: ImportMode.merge);

      final names = (await StorageService.instance.loadPlaylists())
          .map((p) => p.name)
          .toList();
      expect(names, containsAll(['Kendi listem', 'Tal']));

      // Birleştirmede ayarlara dokunulmaz.
      expect(SettingsService.instance.pieceSet, 'fantasy',
          reason: 'birleştirme cihazın ayarını değiştirdi');
    });

    test('aynı kimlikli kayıtta yedekteki geçerlidir', () async {
      final playlist = await StorageService.instance.createPlaylist('Eski ad');
      final text = await BackupService.instance.exportAll();

      await StorageService.instance.renamePlaylist(playlist.id, 'Yeni ad');
      expect((await StorageService.instance.loadPlaylists()).first.name,
          'Yeni ad');

      final (_, data) = await BackupService.instance.read(text);
      await BackupService.instance.apply(data, mode: ImportMode.merge);

      final playlists = await StorageService.instance.loadPlaylists();
      expect(playlists, hasLength(1), reason: 'kayıt ikilendi');
      expect(playlists.first.name, 'Eski ad');
    });

    test('cihazda mantıksal ayar varken birleştirme çökmüyor', () async {
      // `_merged` en başta `getString` çağırıyordu; cihazda aynı adla bir
      // bool ayar duruyorsa (ör. ses) tür hatasıyla patlıyordu. Yedekte
      // ayarlar da bulunduğu için bu, gerçek bir geri yüklemede çöküyordu.
      await _seed();
      SettingsService.instance.soundEnabled = false;
      final text = await BackupService.instance.exportAll();

      await _resetAll();
      SettingsService.instance.soundEnabled = true;
      await StorageService.instance.createPlaylist('Kendi listem');

      final (_, data) = await BackupService.instance.read(text);
      expect(data.containsKey('soundEnabled'), isTrue,
          reason: 'ayarlar yedeğe giriyor; senaryo geçerli');

      await BackupService.instance.apply(data, mode: ImportMode.merge);

      final names = (await StorageService.instance.loadPlaylists())
          .map((p) => p.name)
          .toList();
      expect(names, containsAll(['Kendi listem', 'Tal']));
      expect(SettingsService.instance.soundEnabled, isTrue,
          reason: 'birleştirme ayarlara dokunmamalı');
    });

    test('v5 yedeği geri yüklenince ses seçimi korunuyor', () async {
      // Yedek, "ses varsayılanları bir kez geri getirildi" işaretini de
      // taşıyor; bu yüzden geri yükleme sonrası ezme tekrar çalışmıyor.
      await _seed();
      SettingsService.instance.soundEnabled = false;
      final text = await BackupService.instance.exportAll();

      await _resetAll();
      final (_, data) = await BackupService.instance.read(text);
      await BackupService.instance.apply(data);

      expect(SettingsService.instance.soundEnabled, isFalse,
          reason: 'kullanıcının seçimi geri yüklemeden sağ çıkmalı');
    });

    test('işaretsiz eski yedek ses varsayılanlarına dönüyor', () async {
      // v5 öncesi bir yedekte işaret yok; takılı kalmış "ses kapalı"
      // değeri geri gelmesin diye bir kez varsayılana dönülüyor.
      await _seed();
      final text = await BackupService.instance.exportAll();
      final (_, data) = await BackupService.instance.read(text);
      data['soundEnabled'] = false;
      data.remove('soundDefaultsRestored');

      await _resetAll();
      await BackupService.instance.apply(data);

      expect(SettingsService.instance.soundEnabled, isTrue);
    });

    test('değiştirme kipinde cihazın kendi verisi silinir', () async {
      await _seed();
      final text = await BackupService.instance.exportAll();

      await _resetAll();
      await StorageService.instance.createPlaylist('Silinecek');

      final (_, data) = await BackupService.instance.read(text);
      await BackupService.instance.apply(data);

      final names = (await StorageService.instance.loadPlaylists())
          .map((p) => p.name)
          .toList();
      expect(names, ['Tal']);
    });
  });

  group('Bozuk dosyalar', () {
    test('düz metin reddedilir', () async {
      expect(
        () => BackupService.instance.read('merhaba'),
        throwsA(isA<FormatException>()),
      );
    });

    test('başka bir JSON reddedilir', () async {
      expect(
        () => BackupService.instance.read('{"hello": 1}'),
        throwsA(predicate((e) => e is FormatException && e.message == 'badFile')),
      );
    });

    test('içeriği değiştirilmiş yedek yakalanır', () async {
      await _seed();
      final text = await BackupService.instance.exportAll();
      final document = jsonDecode(text) as Map<String, dynamic>;
      final data = Map<String, dynamic>.from(document['data'] as Map);
      data['playlists_v2'] = '[]';
      document['data'] = data;

      expect(
        () => BackupService.instance.read(jsonEncode(document)),
        throwsA(predicate((e) => e is FormatException && e.message == 'corrupt')),
      );
    });

    test('daha yeni biçim uyarı verir', () async {
      final text = await BackupService.instance.exportAll();
      final document = jsonDecode(text) as Map<String, dynamic>;
      document['format'] = BackupService.formatVersion + 1;

      expect(
        () => BackupService.instance.read(jsonEncode(document)),
        throwsA(
          predicate((e) => e is FormatException && e.message == 'newerFormat'),
        ),
      );
    });

    test('bozuk yedek reddedilince veri olduğu gibi kalır', () async {
      await _seed();
      final before = await StorageService.instance.loadPlaylists();
      expect(before, hasLength(1));

      try {
        await BackupService.instance.read('{"app":"baska"}');
        fail('bozuk dosya kabul edildi');
      } on FormatException {
        // beklenen
      }

      StorageService.instance.resetCache();
      expect(await StorageService.instance.loadPlaylists(), hasLength(1));
    });
  });

  group('Ölçek', () {
    test('binlerce bulmacalı yedek makul sürede tur atar', () async {
      final collection =
          await PuzzleService.instance.createCollection('Büyük liste');
      const fen = '3q1rk1/5pbp/5Qp1/8/8/2B5/5PPP/6K1 w - - 0 1';
      await PuzzleService.instance.importFens(
        collection,
        List.filled(4000, fen).join('\n'),
      );

      final steps = <double>[];
      final watch = Stopwatch()..start();
      final text = await BackupService.instance.exportAll(
        onProgress: steps.add,
      );
      final exportMs = watch.elapsedMilliseconds;

      expect(text.length, greaterThan(100000));
      expect(steps.last, 1.0);

      watch.reset();
      final (summary, data) = await BackupService.instance.read(text);
      await BackupService.instance.apply(data);
      final importMs = watch.elapsedMilliseconds;

      expect(summary.puzzles, 4000);
      final restored = await PuzzleService.instance.collections();
      expect(
        await PuzzleService.instance.puzzlesOf(restored.first),
        hasLength(4000),
      );

      // Ağır bir cihazda bile birkaç saniyeyi geçmemeli; buradaki sınır
      // gerilemeyi yakalamak için geniş tutuldu.
      expect(exportMs, lessThan(20000), reason: 'dışa aktarma yavaşladı');
      expect(importMs, lessThan(20000), reason: 'içe aktarma yavaşladı');
    });
  });
}
