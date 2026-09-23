import 'package:flutter_test/flutter_test.dart';

import 'package:chess_pgn_reader/models/playlist.dart';
import 'package:chess_pgn_reader/services/storage_service.dart';
import 'support/device.dart';

SavedGame _game(String name) => SavedGame(
      name: name,
      uciMoves: const ['e2e4', 'e7e5'],
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Depo bir tekil olduğu için tüm adımlar tek testte sırayla yürütülür.
  test('toplu ekleme, okundu işareti ve bildirim', () async {
    await resetDevice({});
    final storage = StorageService.instance;

    int notifications = 0;
    void onChange() => notifications++;
    storage.addListener(onChange);

    // Yeni liste tek yazmada oluşur.
    final playlist = await storage.createPlaylistWithGames(
      'PGN dosyası',
      [_game('Bir'), _game('İki'), _game('Üç')],
    );
    expect(playlist.games.length, 3);
    expect(notifications, 1);

    // Toplu ekleme tek bildirim üretir.
    final added = await storage.addGames(
      playlist.id,
      [_game('Dört'), _game('Beş')],
    );
    expect(added, 2);
    expect(notifications, 2);

    final lists = await storage.loadPlaylists();
    final saved = lists.firstWhere((p) => p.id == playlist.id);
    expect(saved.games.length, 5);
    expect(saved.games.every((g) => !g.read), isTrue);

    // Tek oyunun işareti değişir.
    final first = saved.games.first;
    expect(await storage.toggleGameRead(playlist.id, first.id), isTrue);
    expect(saved.games.first.read, isTrue);
    expect(await storage.toggleGameRead(playlist.id, first.id), isFalse);

    // Toplu işaretleme.
    await storage.setAllRead(playlist.id, true);
    expect(saved.games.where((g) => g.read).length, 5);
    await storage.setAllRead(playlist.id, false);
    expect(saved.games.where((g) => g.read).length, 0);

    // Bilinmeyen liste sessizce yok sayılır.
    expect(await storage.addGames('yok', [_game('X')]), 0);
    expect(await storage.toggleGameRead('yok', first.id), isFalse);

    storage.removeListener(onChange);
  });

  test('okundu işareti kaydedilip geri okunur', () {
    final game = _game('Deneme')..read = true;
    final restored = SavedGame.fromJson(game.toJson());
    expect(restored.read, isTrue);
    expect(restored.name, 'Deneme');

    final unread = SavedGame.fromJson(_game('Diğer').toJson());
    expect(unread.read, isFalse);
  });
}
