import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/services/backup_service.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/services/storage_service.dart';
import 'support/device.dart';

/// 10.6.0: oyun listelerinde siyah tarafından okuma — servis ve tam yedek.
///
/// Açılışlardaki "Siyah tarafından çalış"ın (10.5.0) listelerdeki karşılığı:
/// işaretli listenin oyunları tahta siyahın gözünden açılıyor. İşaret
/// liste **kimliğine** bağlı (`playlists_black_v1`): ad değişince kopmuyor.
/// İki depoyla da koşuyor (bkz. BUILD.md); ekran testleri
/// `v1060_lists_ui_test.dart` içinde.

final _storage = StorageService.instance;

Future<void> _fresh() async {
  await resetDevice({
    'flutter.soundEnabled': false,
    'flutter.soundDefaultsRestored': true,
  });
  _storage.resetCache();
  await SettingsService.instance.load();
  Strings.language = AppLanguage.turkish;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('cl_v1060_backup_');
    BackupService.snapshotDirectory = () async => dir;
  });

  setUp(_fresh);

  tearDown(() => Strings.language = AppLanguage.system);

  group('Siyah tarafı (servis)', () {
    test('varsayılan beyaz; işaret kalıcı, kaldırılabiliyor', () async {
      final a = await _storage.createPlaylist('Sicilya oyunları');
      final b = await _storage.createPlaylist('Karışık');
      expect(await _storage.blackPlaylists(), isEmpty);

      await _storage.setPlaylistBlack(a.id, true);
      _storage.resetCache();
      expect(await _storage.blackPlaylists(), {a.id});

      await _storage.setPlaylistBlack(b.id, true);
      await _storage.setPlaylistBlack(a.id, false);
      _storage.resetCache();
      expect(await _storage.blackPlaylists(), {b.id});
    });

    test('yeniden adlandırma işareti koparmıyor', () async {
      final a = await _storage.createPlaylist('Eski ad');
      await _storage.setPlaylistBlack(a.id, true);
      await _storage.renamePlaylist(a.id, 'Yeni ad');
      _storage.resetCache();
      expect(await _storage.blackPlaylists(), {a.id});
    });

    test('silinen listenin işareti de gidiyor', () async {
      final a = await _storage.createPlaylist('A');
      final b = await _storage.createPlaylist('B');
      await _storage.setPlaylistBlack(a.id, true);
      await _storage.setPlaylistBlack(b.id, true);

      await _storage.deletePlaylist(a.id);
      _storage.resetCache();
      expect(await _storage.blackPlaylists(), {b.id});
    });
  });

  group('Tam yedek', () {
    test('değiştir: siyah işareti geri geliyor', () async {
      final a = await _storage.createPlaylist('A');
      await _storage.createPlaylist('B');
      await _storage.setPlaylistBlack(a.id, true);
      final text = await BackupService.instance.exportAll();

      await _fresh();
      final (_, data) = await BackupService.instance.read(text);
      await BackupService.instance.apply(data);
      _storage.resetCache();
      expect(await _storage.blackPlaylists(), {a.id});
    });

    test('birleştir: iki taraftaki işaretler birleşiyor', () async {
      final a = await _storage.createPlaylist('Yedekteki');
      await _storage.setPlaylistBlack(a.id, true);
      final text = await BackupService.instance.exportAll();

      await _fresh();
      final c = await _storage.createPlaylist('Cihazdaki');
      await _storage.setPlaylistBlack(c.id, true);
      final (_, data) = await BackupService.instance.read(text);
      await BackupService.instance.apply(data, mode: ImportMode.merge);
      _storage.resetCache();
      expect(await _storage.blackPlaylists(), {a.id, c.id});
    });

    test('geri yükleme bellekteki eski işareti bırakmıyor', () async {
      // Yedek, cihazda işaret okunduktan sonra geri yükleniyor: önbellek
      // tazelenmezse eski (boş) küme kalırdı.
      final a = await _storage.createPlaylist('A');
      await _storage.setPlaylistBlack(a.id, true);
      final text = await BackupService.instance.exportAll();

      await _fresh();
      expect(await _storage.blackPlaylists(), isEmpty);
      final (_, data) = await BackupService.instance.read(text);
      await BackupService.instance.apply(data);
      expect(await _storage.blackPlaylists(), {a.id});
    });
  });
}
