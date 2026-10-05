import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/models/game_filter.dart';
import 'package:chess_pgn_reader/models/playlist.dart';
import 'package:chess_pgn_reader/services/backup_service.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/services/storage_service.dart';
import 'support/device.dart';

/// 10.8.0: servis tarafı — "oyuncunun gözünden oku" (kayıt, yön kuralı,
/// tam yedek) ve beş izleme hızı. İki depoyla da koşuyor (bkz. BUILD.md);
/// ekran testleri `v1080_test.dart` içinde.

final _storage = StorageService.instance;
final _settings = SettingsService.instance;

Future<void> _fresh([Map<String, Object> extra = const {}]) async {
  await resetDevice({
    'flutter.soundEnabled': false,
    'flutter.soundDefaultsRestored': true,
    ...extra,
  });
  _storage.resetCache();
  await _settings.load();
  Strings.language = AppLanguage.turkish;
}

SavedGame _game({String? white, String? black, String? name}) => SavedGame(
      name: name ?? '${white ?? '?'} - ${black ?? '?'}',
      uciMoves: const ['e2e4'],
      createdAt: DateTime(2026, 10, 1),
      white: white,
      black: black,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('cl_v1080_backup_');
    BackupService.snapshotDirectory = () async => dir;
  });

  setUp(_fresh);

  tearDown(() => Strings.language = AppLanguage.system);

  group('Oyuncunun gözünden: yön kuralı', () {
    test('oyuncu beyazsa beyazdan, siyahsa siyahtan', () {
      final asWhite =
          _game(white: 'Fischer, Robert James', black: 'Spassky, Boris');
      final asBlack =
          _game(white: 'Spassky, Boris', black: 'Fischer, Robert James');
      expect(listGameFlipped(asWhite, blackSide: false, player: 'fischer'),
          isFalse);
      expect(listGameFlipped(asBlack, blackSide: false, player: 'fischer'),
          isTrue);
      expect(listGameFlipped(asWhite, blackSide: true, player: 'fischer'),
          isFalse,
          reason: 'oyuncu bulununca listenin siyah işaretinin önüne geçer');
    });

    test('oyuncu oyunda yoksa listenin kendi yönü', () {
      final other = _game(white: 'Tal, Mikhail', black: 'Botvinnik');
      expect(listGameFlipped(other, blackSide: false, player: 'fischer'),
          isFalse);
      expect(listGameFlipped(other, blackSide: true, player: 'fischer'),
          isTrue);
    });

    test('ad iki tarafa da uyuyorsa listenin kendi yönü', () {
      final both = _game(white: 'Polgar, Judit', black: 'Polgar, Susan');
      expect(listGameFlipped(both, blackSide: true, player: 'polgar'),
          isTrue);
      expect(listGameFlipped(both, blackSide: false, player: 'polgar'),
          isFalse);
    });

    test('gevşek eşleşme: parça, büyük-küçük harf, Türkçe harf, sıra', () {
      final game = _game(white: 'Kasparov', black: 'Şahin Çağlar');
      expect(listGameFlipped(game, blackSide: false, player: 'sahin'),
          isTrue);
      expect(listGameFlipped(game, blackSide: false, player: 'ÇAĞLAR şahin'),
          isTrue);
      expect(listGameFlipped(game, blackSide: false, player: 'kaspa'),
          isFalse);
    });

    test('adlar PGN başlığından ya da "Beyaz - Siyah" adından', () {
      final fromName = _game(name: 'Spassky - Fischer');
      expect(listGameFlipped(fromName, blackSide: false, player: 'fischer'),
          isTrue);
      final fromTags = SavedGame(
        name: 'Oyun',
        uciMoves: const ['e2e4'],
        createdAt: DateTime(2026, 10, 1),
        tags: const {'White': 'Spassky', 'Black': 'Fischer'},
      );
      expect(listGameFlipped(fromTags, blackSide: false, player: 'fischer'),
          isTrue);
    });

    test('boş ad: listenin kendi yönü', () {
      final game = _game(white: 'A', black: 'B');
      expect(listGameFlipped(game, blackSide: true, player: '  '), isTrue);
      expect(listGameFlipped(game, blackSide: false), isFalse);
    });
  });

  group('Oyuncunun gözünden: kayıt', () {
    test('kalıcı, kırpılıyor, boş ad kaldırıyor', () async {
      final a = await _storage.createPlaylist('A');
      final b = await _storage.createPlaylist('B');
      await _storage.setPlaylistPlayer(a.id, '  Fischer ');
      await _storage.setPlaylistPlayer(b.id, 'Tal');
      _storage.resetCache();
      expect(await _storage.playlistPlayers(), {a.id: 'Fischer', b.id: 'Tal'});

      await _storage.setPlaylistPlayer(a.id, '');
      _storage.resetCache();
      expect(await _storage.playlistPlayers(), {b.id: 'Tal'});
    });

    test('silinen listenin adı da gidiyor', () async {
      final a = await _storage.createPlaylist('A');
      await _storage.setPlaylistPlayer(a.id, 'Fischer');
      await _storage.deletePlaylist(a.id);
      _storage.resetCache();
      expect(await _storage.playlistPlayers(), isEmpty);
    });

    test('değiştir: tam yedekten geri geliyor', () async {
      final a = await _storage.createPlaylist('A');
      await _storage.setPlaylistPlayer(a.id, 'Fischer');
      final text = await BackupService.instance.exportAll();

      await _fresh();
      expect(await _storage.playlistPlayers(), isEmpty);
      final (_, data) = await BackupService.instance.read(text);
      await BackupService.instance.apply(data);
      expect(await _storage.playlistPlayers(), {a.id: 'Fischer'});
    });

    test('birleştir: iki taraftaki adlar kalıyor, aynı listede yedeki',
        () async {
      final a = await _storage.createPlaylist('Yedekteki');
      await _storage.setPlaylistPlayer(a.id, 'Fischer');
      final text = await BackupService.instance.exportAll();

      await _fresh();
      final c = await _storage.createPlaylist('Cihazdaki');
      await _storage.setPlaylistPlayer(c.id, 'Tal');
      final (_, data) = await BackupService.instance.read(text);
      await BackupService.instance.apply(data, mode: ImportMode.merge);
      _storage.resetCache();
      expect(await _storage.playlistPlayers(), {a.id: 'Fischer', c.id: 'Tal'});
    });
  });

  group('Beş izleme hızı', () {
    test('ekrandaki sıra yavaştan hızlıya, adlar', () {
      expect(WatchSpeed.ordered, hasLength(5));
      for (var i = 1; i < WatchSpeed.ordered.length; i++) {
        expect(WatchSpeed.ordered[i].pace,
            lessThan(WatchSpeed.ordered[i - 1].pace));
      }
      expect(WatchSpeed.ordered.map((s) => s.label),
          ['Çok yavaş', 'Yavaş', 'Normal', 'Hızlı', 'Çok hızlı']);
      expect(WatchSpeed.normal.pace, const Duration(milliseconds: 900));
      expect(WatchSpeed.veryFast.pace, const Duration(milliseconds: 500));
    });

    test('10.7.0 kayıtları yerinde: eski "Hızlı" (0,5 sn) "Çok hızlı" oldu',
        () async {
      for (final (stored, speed) in const [
        (0, WatchSpeed.slow),
        (1, WatchSpeed.normal),
        (2, WatchSpeed.veryFast),
      ]) {
        await _fresh({
          'flutter.openingWatchSpeed': stored,
          'flutter.gameWatchSpeed': stored,
        });
        expect(_settings.openingWatchSpeed, speed);
        expect(_settings.gameWatchSpeed, speed);
      }
    });

    test('yeni hızlar saklanıp okunuyor', () async {
      _settings.openingWatchSpeed = WatchSpeed.verySlow;
      _settings.gameWatchSpeed = WatchSpeed.fast;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await _settings.load();
      expect(_settings.openingWatchSpeed, WatchSpeed.verySlow);
      expect(_settings.gameWatchSpeed, WatchSpeed.fast);
    });
  });
}
