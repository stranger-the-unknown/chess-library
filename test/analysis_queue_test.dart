import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/models/playlist.dart';
import 'package:chess_pgn_reader/services/analysis_queue.dart';
import 'package:chess_pgn_reader/services/storage_service.dart';

/// Toplu analiz kuyruğu.
///
/// Kuyruk gerçek motoru çalıştırdığı için testler kısa oyunlarla ve az
/// sayıda kayıtla yapılıyor; ölçülen şey motorun gücü değil, kuyruğun
/// davranışı: sıra, kayıt, iptal ve bozuk kayda dayanıklılık.

SavedGame _game(String name, {List<String>? moves, String? startFen}) =>
    SavedGame(
      name: name,
      uciMoves: moves ?? const ['e2e4', 'e7e5', 'g1f3'],
      createdAt: DateTime.now(),
      startFen: startFen,
      white: 'Beyaz',
      black: 'Siyah',
    );

Future<Playlist> _seed(List<SavedGame> games) async {
  SharedPreferences.setMockInitialValues({});
  StorageService.instance.resetCache();
  final playlist = await StorageService.instance.createPlaylist('Deneme');
  await StorageService.instance.addGames(playlist.id, games);
  return playlist;
}

/// Ekran kilidinin gerçekten alınıp bırakıldığını izleyen sahte.
class _FakeLock implements ScreenLock {
  int enabled = 0;
  int disabled = 0;
  bool failOnEnable = false;

  @override
  Future<void> enable() async {
    enabled++;
    if (failOnEnable) throw StateError('ekran kilidi yok');
  }

  @override
  Future<void> disable() async => disabled++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeLock lock;
  setUp(() {
    lock = _FakeLock();
    AnalysisQueue.instance.screenLock = lock;
  });

  group('Ekran kilidi', () {
    test('analiz sürerken alınıyor, bitince bırakılıyor', () async {
      final games = [_game('Bir')];
      final playlist = await _seed(games);

      await AnalysisQueue.instance.enqueue(
        playlistId: playlist.id,
        games: games,
        deep: false,
      );

      expect(lock.enabled, 1);
      expect(lock.disabled, 1, reason: 'kilit bırakılmadı, ekran açık kalır');
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('kilit kurulamazsa analiz yine de yapılıyor', () async {
      lock.failOnEnable = true;
      final games = [_game('Bir')];
      final playlist = await _seed(games);

      await AnalysisQueue.instance.enqueue(
        playlistId: playlist.id,
        games: games,
        deep: false,
      );

      final quick = (await StorageService.instance.loadAnalysisLists()).last;
      expect(quick.games, hasLength(1));
      expect(lock.disabled, 1, reason: 'yine de bırakılmalı');
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('bozuk oyunda da kilit bırakılıyor', () async {
      final games = [_game('Bozuk', moves: const ['zzzz'])];
      final playlist = await _seed(games);

      await AnalysisQueue.instance.enqueue(
        playlistId: playlist.id,
        games: games,
        deep: false,
      );

      expect(lock.disabled, 1);
    }, timeout: const Timeout(Duration(minutes: 5)));
  });

  test('seçilen oyunlar sırayla analiz edilip kaydediliyor', () async {
    final games = [_game('Bir'), _game('İki')];
    final playlist = await _seed(games);

    await AnalysisQueue.instance.enqueue(
      playlistId: playlist.id,
      games: games,
      deep: false,
    );

    final quick = (await StorageService.instance.loadAnalysisLists()).last;
    expect(quick.games, hasLength(2));
    // En yeni başta: sonuncu analiz edilen ilk sırada.
    expect(quick.games.first.name, 'İki');
    expect(quick.games.last.name, 'Bir');
    expect(quick.games.first.review, isNotNull);
    expect(quick.games.first.review!.deep, isFalse);
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('derin analiz derin listeye gidiyor', () async {
    final games = [_game('Bir')];
    final playlist = await _seed(games);

    await AnalysisQueue.instance.enqueue(
      playlistId: playlist.id,
      games: games,
      deep: true,
    );

    final lists = await StorageService.instance.loadAnalysisLists();
    expect(lists.first.games, hasLength(1), reason: 'derin liste');
    expect(lists.last.games, isEmpty, reason: 'hızlı liste boş kalmalı');
    expect(lists.first.games.first.review!.deep, isTrue);
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('kayıt her oyundan sonra yapılıyor', () async {
    // Yarıda kesilirse bitenler kalsın diye önemli.
    final games = [_game('Bir'), _game('İki'), _game('Üç')];
    final playlist = await _seed(games);

    final seen = <int>[];
    void watcher() {
      if (!AnalysisQueue.instance.isRunning) return;
      seen.add(AnalysisQueue.instance.done);
    }

    AnalysisQueue.instance.addListener(watcher);
    await AnalysisQueue.instance.enqueue(
      playlistId: playlist.id,
      games: games,
      deep: false,
    );
    AnalysisQueue.instance.removeListener(watcher);

    // İlerleme aşama aşama bildirilmiş olmalı.
    expect(seen, contains(1));
    expect(seen, contains(2));
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('bozuk oyun kuyruğu durdurmuyor', () async {
    // Ortadaki oyunun hamleleri kural dışı; diğerleri yine de işlenmeli.
    final games = [
      _game('Sağlam bir'),
      _game('Bozuk', moves: const ['e2e9', 'zzzz']),
      _game('Sağlam iki'),
    ];
    final playlist = await _seed(games);

    await AnalysisQueue.instance.enqueue(
      playlistId: playlist.id,
      games: games,
      deep: false,
    );

    final quick = (await StorageService.instance.loadAnalysisLists()).last;
    final names = quick.games.map((g) => g.name).toList();
    expect(names, contains('Sağlam bir'));
    expect(names, contains('Sağlam iki'));
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('analiz kaydı asıl oyuna bağlı', () async {
    final games = [_game('Bir')];
    final playlist = await _seed(games);

    await AnalysisQueue.instance.enqueue(
      playlistId: playlist.id,
      games: games,
      deep: false,
    );

    final record =
        (await StorageService.instance.loadAnalysisLists()).last.games.first;
    expect(record.sourceGameId, games.first.id);
    expect(record.sourcePlaylistId, playlist.id);
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('iş bitince kuyruk boşalıyor', () async {
    final games = [_game('Bir')];
    final playlist = await _seed(games);

    await AnalysisQueue.instance.enqueue(
      playlistId: playlist.id,
      games: games,
      deep: false,
    );

    expect(AnalysisQueue.instance.isRunning, isFalse);
    expect(AnalysisQueue.instance.total, 0);
    expect(AnalysisQueue.instance.current, isNull);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
