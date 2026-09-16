import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/models/playlist.dart';
import 'package:chess_pgn_reader/models/stored_review.dart';
import 'package:chess_pgn_reader/screens/playlist_screen.dart';
import 'package:chess_pgn_reader/screens/playlist_detail_screen.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/services/storage_service.dart';

/// Analiz listelerinin arayüzü ve toplu seçim.

Future<Playlist> _seed() async {
  SharedPreferences.setMockInitialValues({});
  StorageService.instance.resetCache();
  await SettingsService.instance.load();
  Strings.language = AppLanguage.turkish;
  final playlist = await StorageService.instance.createPlaylist('Tal');
  await StorageService.instance.addGames(playlist.id, [
    SavedGame(name: 'Bir', uciMoves: const ['e2e4'], createdAt: DateTime.now()),
    SavedGame(name: 'İki', uciMoves: const ['d2d4'], createdAt: DateTime.now()),
  ]);
  return playlist;
}

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(500, 1200);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  // Anahtar verilmezse Flutter aynı türdeki ekranın State'ini koruyor,
  // initState yeniden çalışmıyor ve ekranda bir öncekinin verisi kalıyor.
  await tester.pumpWidget(
    MaterialApp(home: KeyedSubtree(key: UniqueKey(), child: screen)),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => Strings.language = AppLanguage.system);

  testWidgets('analiz listeleri en üstte ve adlandırılmış', (tester) async {
    await _seed();
    await _pump(tester, const PlaylistScreen());

    expect(find.text('Son Derin Analizler'), findsOneWidget);
    expect(find.text('Son Hızlı Analizler'), findsOneWidget);

    final deep = tester.getRect(find.text('Son Derin Analizler'));
    final quick = tester.getRect(find.text('Son Hızlı Analizler'));
    final user = tester.getRect(find.text('Tal'));
    expect(deep.top, lessThan(quick.top));
    expect(quick.top, lessThan(user.top), reason: 'analiz listeleri üstte');
  });

  testWidgets('analiz listesi silinemiyor ve yeniden adlandırılamıyor',
      (tester) async {
    await _seed();
    await _pump(tester, const PlaylistScreen());

    // Analiz listesinin menüsünde silme/yeniden adlandırma olmamalı.
    final card = find.ancestor(
      of: find.text('Son Derin Analizler'),
      matching: find.byType(Row),
    );
    await tester.tap(find.descendant(
      of: card.first,
      matching: find.byType(PopupMenuButton<String>),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Sil'), findsNothing);
    expect(find.text('Yeniden adlandır'), findsNothing);
  });

  test('servis de silmeyi ve adlandırmayı reddediyor', () async {
    await _seed();
    await StorageService.instance.deletePlaylist(StorageService.deepListId);
    await StorageService.instance
        .renamePlaylist(StorageService.deepListId, 'Yeni');

    final lists = await StorageService.instance.loadAnalysisLists();
    expect(lists, hasLength(2), reason: 'silinmemeliydi');
    expect(lists.first.name, isNot('Yeni'), reason: 'adlandırılmamalıydı');
  });

  testWidgets('seçim kipi açılıyor ve düğmeler seçime bağlı', (tester) async {
    final playlist = await _seed();
    await _pump(tester, PlaylistDetailScreen(playlistId: playlist.id));

    // Satırların da menüsü var; başlık çubuğundakini seçiyoruz.
    await tester.tap(find.descendant(
      of: find.byType(AppBar),
      matching: find.byType(PopupMenuButton<String>),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Analiz için oyun seç'));
    await tester.pumpAndSettle();

    expect(find.text('0 oyun seçildi'), findsOneWidget);
    // Seçim yokken analiz düğmeleri kapalı.
    final quick = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Hızlı analiz'),
    );
    expect(quick.onPressed, isNull);

    await tester.tap(find.text('Tümünü seç'));
    await tester.pumpAndSettle();
    expect(find.text('2 oyun seçildi'), findsOneWidget);

    final ready = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Hızlı analiz'),
    );
    expect(ready.onPressed, isNotNull);
  });

  testWidgets('kaydedilmiş analiz listede görünüyor', (tester) async {
    final playlist = await _seed();
    final game = (await StorageService.instance.loadPlaylists()).first.games.first;
    await StorageService.instance.addAnalysis(
      source: game,
      sourcePlaylistId: playlist.id,
      review: StoredReview(
        deep: true,
        at: DateTime.now(),
        whiteAccuracy: 88,
        blackAccuracy: 64,
        moves: const [],
      ),
    );

    await _pump(
      tester,
      PlaylistDetailScreen(playlistId: StorageService.deepListId),
    );
    expect(find.text('Bir'), findsOneWidget);
  });

  testWidgets('analiz listesinin başlığı da çevrilmiş', (tester) async {
    // Ham kimlik ("sys_quick") görünüyordu: ad çözümü listeler
    // sekmesinde yapılıyor ama detay ekranında yapılmıyordu.
    await _seed();
    await _pump(
      tester,
      const PlaylistDetailScreen(playlistId: StorageService.quickListId),
    );
    expect(find.text('Son Hızlı Analizler'), findsOneWidget);
    expect(find.text('sys_quick'), findsNothing);

    await _pump(
      tester,
      const PlaylistDetailScreen(playlistId: StorageService.deepListId),
    );
    expect(find.text('Son Derin Analizler'), findsOneWidget);
    expect(find.text('sys_deep'), findsNothing);
  });

  testWidgets('boş analiz listesi doğru yönlendiriyor', (tester) async {
    // "Tahta ekranından oyun kaydet" demek burada yanlış: bu listeye
    // oyun ancak analizle giriyor.
    await _seed();
    await _pump(
      tester,
      const PlaylistDetailScreen(playlistId: StorageService.deepListId),
    );
    expect(find.textContaining('Henüz analiz yok'), findsOneWidget);
    expect(find.textContaining('Tahta ekranındaki'), findsNothing);
  });

  test('kullanıcı listesinin adı olduğu gibi kalıyor', () async {
    final playlist = await _seed();
    final loaded = (await StorageService.instance.loadPlaylists()).first;
    expect(StorageService.displayName(loaded), 'Tal');
    expect(loaded.id, playlist.id);
  });

  group('Analiz listesinde çalışmayan komutlar gösterilmiyor', () {
    // Bunların hepsi `loadPlaylists()` üzerinden çalışıyor; analiz
    // listeleri ayrı bir anahtarda durduğu için sessizce hiçbir şey
    // yapmıyorlardı.
    Future<Playlist> seedAnalysis() async {
      final playlist = await _seed();
      await StorageService.instance.addAnalysis(
        source: playlist.games.first,
        sourcePlaylistId: playlist.id,
        review: StoredReview(
          deep: false,
          at: DateTime.now(),
          whiteAccuracy: 80,
          blackAccuracy: 70,
          moves: const [
            StoredReviewMove(
              bestScoreCp: 20,
              playedScoreCp: 10,
              bestMoveUci: 'e2e4',
              quality: 1,
              accuracy: 90,
            ),
          ],
        ),
      );
      return (await StorageService.instance.loadAnalysisLists()).last;
    }

    testWidgets('başlık menüsünde toplu okundu ve seçim yok',
        (tester) async {
      final analysis = await seedAnalysis();
      await _pump(tester, PlaylistDetailScreen(playlistId: analysis.id));

      await tester.tap(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byIcon(Icons.more_vert),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Hepsini okundu işaretle'), findsNothing);
      expect(find.text('Hepsini okunmadı işaretle'), findsNothing);
      expect(find.text('Aralığı işaretle'), findsNothing);
      expect(find.text('Analiz için oyun seç'), findsNothing);
      expect(find.text('Aralık göster'), findsOneWidget,
          reason: 'yalnızca görüntüleyen komut kalmalı');
    });

    testWidgets('satır menüsünde yeniden adlandırma, silme ve taşıma yok',
        (tester) async {
      final analysis = await seedAnalysis();
      await _pump(tester, PlaylistDetailScreen(playlistId: analysis.id));

      // Başlık çubuğundaki üç nokta gövdeden sonra çiziliyor; `.last`
      // onu seçiyordu ve satır menüsü hiç açılmıyordu.
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('gameList')),
          matching: find.byIcon(Icons.more_vert),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Yeniden adlandır'), findsNothing);
      expect(find.text('Sil'), findsNothing);
      expect(find.text('Başka listeye taşı'), findsNothing);
      expect(find.text('Oyun bilgileri'), findsOneWidget);
    });

    testWidgets('PGN ekleme düğmesi yok', (tester) async {
      final analysis = await seedAnalysis();
      await _pump(tester, PlaylistDetailScreen(playlistId: analysis.id));
      expect(find.byIcon(Icons.file_open_outlined), findsNothing);
    });

    testWidgets('kullanıcı listesinde hepsi duruyor', (tester) async {
      final playlist = await _seed();
      await _pump(tester, PlaylistDetailScreen(playlistId: playlist.id));

      expect(find.byIcon(Icons.file_open_outlined), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byIcon(Icons.more_vert),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Analiz için oyun seç'), findsOneWidget);
      expect(find.text('Aralığı işaretle'), findsOneWidget);
    });

    testWidgets('uzun başlık başlık çubuğuna sığdırılıyor', (tester) async {
      final analysis = await seedAnalysis();
      tester.view.physicalSize = const Size(360, 800);
      await _pump(tester, PlaylistDetailScreen(playlistId: analysis.id));

      final title = find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Son Hızlı Analizler'),
      );
      expect(title, findsOneWidget);
      expect(
        find.ancestor(of: title, matching: find.byType(FittedBox)),
        findsOneWidget,
        reason: 'sığmayan başlık kırpılmak yerine küçülmeli',
      );
    });
  });
}
