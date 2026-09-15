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
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => Strings.language = AppLanguage.system);

  testWidgets('analiz listeleri en üstte ve adlandırılmış', (tester) async {
    await _seed();
    await _pump(tester, const PlaylistScreen());

    expect(find.text('Son derin analizler'), findsOneWidget);
    expect(find.text('Son hızlı analizler'), findsOneWidget);

    final deep = tester.getRect(find.text('Son derin analizler'));
    final quick = tester.getRect(find.text('Son hızlı analizler'));
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
      of: find.text('Son derin analizler'),
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
}
