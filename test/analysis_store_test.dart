import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/models/playlist.dart';
import 'package:chess_pgn_reader/models/stored_review.dart';
import 'package:chess_pgn_reader/services/backup_service.dart';
import 'package:chess_pgn_reader/services/storage_service.dart';

/// Analiz listeleri: ayrı anahtar, yüz kayıt sınırı, tek yönlü bağ.
///
/// Bu üçü birbirine değdiği için ayrı ayrı sınanıyor; en çok hata
/// çıkabilecek yer burası.

StoredReview _review({bool deep = true}) => StoredReview(
      deep: deep,
      at: DateTime.now(),
      whiteAccuracy: 90,
      blackAccuracy: 70,
      moves: const [
        StoredReviewMove(
          bestScoreCp: 30,
          playedScoreCp: -120,
          bestMoveUci: 'e2e4',
          quality: 5,
          accuracy: 40,
        ),
      ],
    );

Future<(Playlist, SavedGame)> _seed() async {
  SharedPreferences.setMockInitialValues({});
  StorageService.instance.resetCache();
  final playlist = await StorageService.instance.createPlaylist('Tal');
  final game = SavedGame(
    name: 'Tal - Botvinnik',
    uciMoves: const ['e2e4', 'e7e5'],
    createdAt: DateTime.now(),
    white: 'Tal',
    black: 'Botvinnik',
  );
  await StorageService.instance.addGames(playlist.id, [game]);
  return (playlist, game);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('iki analiz listesi her zaman var ve sırası sabit', () async {
    SharedPreferences.setMockInitialValues({});
    StorageService.instance.resetCache();
    final lists = await StorageService.instance.loadAnalysisLists();
    expect(lists, hasLength(2));
    expect(lists.first.id, StorageService.deepListId);
    expect(lists.last.id, StorageService.quickListId);
  });

  test('analiz listeleri kullanıcı listelerine karışmıyor', () async {
    final (playlist, _) = await _seed();
    final user = await StorageService.instance.loadPlaylists();
    expect(user.map((p) => p.id), [playlist.id]);
  });

  test('yeni analiz başa ekleniyor, eskisi silinmiyor', () async {
    final (playlist, game) = await _seed();
    for (int i = 0; i < 3; i++) {
      await StorageService.instance.addAnalysis(
        source: game,
        sourcePlaylistId: playlist.id,
        review: _review(),
      );
    }
    final deep = (await StorageService.instance.loadAnalysisLists()).first;
    expect(deep.games, hasLength(3),
        reason: 'tekrar analiz eskisini silmemeli');
  });

  test('hızlı ve derin ayrı listelere gidiyor', () async {
    final (playlist, game) = await _seed();
    await StorageService.instance.addAnalysis(
      source: game,
      sourcePlaylistId: playlist.id,
      review: _review(deep: true),
    );
    await StorageService.instance.addAnalysis(
      source: game,
      sourcePlaylistId: playlist.id,
      review: _review(deep: false),
    );
    final lists = await StorageService.instance.loadAnalysisLists();
    expect(lists.first.games, hasLength(1));
    expect(lists.last.games, hasLength(1));
  });

  test('yüz kaydı aşınca en eski düşüyor', () async {
    final (playlist, _) = await _seed();
    for (int i = 0; i < StorageService.analysisLimit + 5; i++) {
      await StorageService.instance.addAnalysis(
        source: SavedGame(
          name: 'Oyun $i',
          uciMoves: const ['e2e4'],
          createdAt: DateTime.now(),
        ),
        sourcePlaylistId: playlist.id,
        review: _review(),
      );
    }
    final deep = (await StorageService.instance.loadAnalysisLists()).first;
    expect(deep.games, hasLength(StorageService.analysisLimit));
    expect(deep.games.first.name, 'Oyun ${StorageService.analysisLimit + 4}',
        reason: 'en yeni başta olmalı');
    expect(deep.games.last.name, 'Oyun 5', reason: 'en eskiler düşmeliydi');
  });

  group('Tek yönlü bağ', () {
    test('analizde okundu işaretlemek asıl oyunu da işaretliyor', () async {
      final (playlist, game) = await _seed();
      await StorageService.instance.addAnalysis(
        source: game,
        sourcePlaylistId: playlist.id,
        review: _review(),
      );
      final deep = (await StorageService.instance.loadAnalysisLists()).first;
      await StorageService.instance.toggleGameRead(deep.id, deep.games.first.id);

      final source =
          (await StorageService.instance.loadPlaylists()).first.games.first;
      expect(source.read, isTrue);
    });

    test('asıl oyunu işaretlemek analiz kaydına dokunmuyor', () async {
      final (playlist, game) = await _seed();
      await StorageService.instance.addAnalysis(
        source: game,
        sourcePlaylistId: playlist.id,
        review: _review(),
      );
      await StorageService.instance.toggleGameRead(playlist.id, game.id);

      final deep = (await StorageService.instance.loadAnalysisLists()).first;
      expect(deep.games.first.read, isFalse,
          reason: 'ters yön bilerek bağlı değil');
    });

    test('asıl oyun silinmişse bağ sessizce boşa düşüyor', () async {
      final (playlist, game) = await _seed();
      await StorageService.instance.addAnalysis(
        source: game,
        sourcePlaylistId: playlist.id,
        review: _review(),
      );
      await StorageService.instance.deletePlaylist(playlist.id);

      final deep = (await StorageService.instance.loadAnalysisLists()).first;
      final read = await StorageService.instance
          .toggleGameRead(deep.id, deep.games.first.id);
      expect(read, isTrue, reason: 'kaydın kendi işareti yine de konmalı');
    });
  });

  group('Yedek ve sıfırlama', () {
    test('analiz kayıtları yedeğe girmiyor', () async {
      final (playlist, game) = await _seed();
      await StorageService.instance.addAnalysis(
        source: game,
        sourcePlaylistId: playlist.id,
        review: _review(),
      );
      final text = await BackupService.instance.exportAll();
      expect(text.contains(StorageService.analysisKey), isFalse);
      expect(text.contains('Tal - Botvinnik'), isTrue,
          reason: 'kullanıcı listesi yedeğe girmeli');
    });

    test('geri yükleme cihazdaki analizleri silmiyor', () async {
      final (playlist, game) = await _seed();
      final text = await BackupService.instance.exportAll();
      await StorageService.instance.addAnalysis(
        source: game,
        sourcePlaylistId: playlist.id,
        review: _review(),
      );

      final (_, data) = await BackupService.instance.read(text);
      await BackupService.instance.apply(data);

      final deep = (await StorageService.instance.loadAnalysisLists()).first;
      expect(deep.games, hasLength(1));
    });

    test('tüm verileri sıfırlama analizleri de siliyor', () async {
      final (playlist, game) = await _seed();
      await StorageService.instance.addAnalysis(
        source: game,
        sourcePlaylistId: playlist.id,
        review: _review(),
      );
      await BackupService.instance.wipeAll();

      final deep = (await StorageService.instance.loadAnalysisLists()).first;
      expect(deep.games, isEmpty);
    });
  });
}
