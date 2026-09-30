import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/services/opening_service.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/services/storage_service.dart';
import 'support/device.dart';

/// 10.7.0: servis tarafı — listelerin sırası, başlığın bütün varyantlarını
/// işaretleme ve izleme hızı ayarları. İki depoyla da koşuyor (bkz.
/// BUILD.md); ekran testleri `v1070_ui_test.dart` içinde.

final _storage = StorageService.instance;
final _openings = OpeningService.instance;
final _settings = SettingsService.instance;

Future<void> _fresh([Map<String, Object> extra = const {}]) async {
  await resetDevice({
    'flutter.soundEnabled': false,
    'flutter.soundDefaultsRestored': true,
    ...extra,
  });
  _storage.resetCache();
  _openings.resetCache();
  await _settings.load();
  Strings.language = AppLanguage.turkish;
}

Future<List<String>> _names() async {
  _storage.resetCache();
  return [for (final p in await _storage.loadPlaylists()) p.name];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(_fresh);

  tearDown(() => Strings.language = AppLanguage.system);

  group('Listelerin sırası', () {
    test('verilen sıraya diziliyor ve kalıcı', () async {
      final a = await _storage.createPlaylist('A');
      final b = await _storage.createPlaylist('B');
      final c = await _storage.createPlaylist('C');
      await _storage.reorderPlaylists([c.id, a.id, b.id]);
      expect(await _names(), ['C', 'A', 'B']);
    });

    test('sırada olmayan liste sonda kalıyor, bilinmeyen kimlik yok sayılıyor',
        () async {
      final a = await _storage.createPlaylist('A');
      final b = await _storage.createPlaylist('B');
      await _storage.createPlaylist('Yeni');
      await _storage.reorderPlaylists(['yok', b.id, a.id]);
      expect(await _names(), ['B', 'A', 'Yeni']);
    });

    test('oyunlar ve siyah işareti sıralamayla kaybolmuyor', () async {
      final a = await _storage.createPlaylist('A');
      final b = await _storage.createPlaylist('B');
      await _storage.setPlaylistBlack(a.id, true);
      await _storage.reorderPlaylists([b.id, a.id]);
      _storage.resetCache();
      final lists = await _storage.loadPlaylists();
      expect(lists.map((p) => p.id), [b.id, a.id]);
      expect(await _storage.blackPlaylists(), {a.id});
    });
  });

  group('Başlığın bütün varyantları', () {
    test('tek yazmayla işaretleniyor; değişen sayısı dönüyor', () async {
      final a1 = await _openings.addFromSan(
          family: 'Açık', variation: 'a1', moveText: '1. e4 e5');
      final a2 = await _openings.addFromSan(
          family: 'Açık', variation: 'a2', moveText: '1. e4 e5 2. Nf3');
      await _openings.markLearned(a1!.id);

      expect(
        await _openings.markManyLearned([a1.id, a2!.id], learned: true),
        1,
        reason: 'a1 zaten öğrenilmişti',
      );
      _openings.resetCache();
      expect((await _openings.progressOf(a1.id)).learned, isTrue);
      expect((await _openings.progressOf(a2.id)).learned, isTrue);

      expect(
        await _openings.markManyLearned([a1.id, a2.id], learned: false),
        2,
      );
      _openings.resetCache();
      expect((await _openings.progressOf(a1.id)).learned, isFalse);
      expect((await _openings.progressOf(a2.id)).learned, isFalse);
    });

    test('kaydı olmayan varyant için boş kayıt açılmıyor', () async {
      final a1 = await _openings.addFromSan(
          family: 'Açık', variation: 'a1', moveText: '1. e4 e5');
      expect(await _openings.markManyLearned([a1!.id], learned: false), 0);
      expect((await _openings.progressMap()).containsKey(a1.id), isFalse);
    });
  });

  group('İzleme hızı', () {
    test('varsayılan Normal; bugünkü hız 0,9 sn', () {
      expect(_settings.openingWatchSpeed, WatchSpeed.normal);
      expect(_settings.gameWatchSpeed, WatchSpeed.normal);
      expect(WatchSpeed.normal.pace, const Duration(milliseconds: 900));
      expect(WatchSpeed.slow.pace, greaterThan(WatchSpeed.normal.pace));
      expect(WatchSpeed.fast.pace, lessThan(WatchSpeed.normal.pace));
    });

    test('iki ayar ayrı ayrı saklanıyor', () async {
      _settings.openingWatchSpeed = WatchSpeed.fast;
      _settings.gameWatchSpeed = WatchSpeed.slow;
      // Yazma sırası beklensin.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('openingWatchSpeed'), WatchSpeed.fast.index);
      expect(prefs.getInt('gameWatchSpeed'), WatchSpeed.slow.index);

      await _settings.load();
      expect(_settings.openingWatchSpeed, WatchSpeed.fast);
      expect(_settings.gameWatchSpeed, WatchSpeed.slow);
    });

    test('tanınmayan değer Normal’e dönüyor', () async {
      await _fresh({
        'flutter.openingWatchSpeed': 9,
        'flutter.gameWatchSpeed': -1,
      });
      expect(_settings.openingWatchSpeed, WatchSpeed.normal);
      expect(_settings.gameWatchSpeed, WatchSpeed.normal);
    });
  });
}
