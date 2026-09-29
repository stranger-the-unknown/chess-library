import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/models/playlist.dart';
import 'package:chess_pgn_reader/screens/game_screen.dart';
import 'package:chess_pgn_reader/screens/playlist_detail_screen.dart';
import 'package:chess_pgn_reader/screens/playlist_screen.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/services/storage_service.dart';
import 'package:chess_pgn_reader/widgets/chess_board_widget.dart';

/// 10.6.0: oyun listelerinde siyah tarafından okuma — ekranlar.
///
/// Liste menüsünde "Siyah tarafından oku"; işaretli listenin kartında
/// "Siyah" etiketi, oyunları tahta çevrili açılıyor. Aynı işaret listenin
/// içindeki menüde de var. Yalnızca tercih deposuyla koşuyor: sahte saatli
/// ekran testlerinde dosya deposunun gerçek disk işlemleri bitmiyor.

final _storage = StorageService.instance;

void _silencePlugins() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final channel in const [
    MethodChannel('com.ryanheise.just_audio.methods'),
    MethodChannel('dev.fluttercommunity.plus/wakelock'),
  ]) {
    messenger.setMockMethodCallHandler(channel, (call) async => null);
  }
}

Future<Playlist> _list(String name) => _storage.createPlaylistWithGames(
      name,
      [
        SavedGame(
          name: 'Oyun 1',
          uciMoves: const ['e2e4', 'c7c5'],
          createdAt: DateTime(2026, 9, 1),
          white: 'Beyaz Oyuncu',
          black: 'Siyah Oyuncu',
          result: '0-1',
        ),
      ],
    );

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(700, 1100);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pumpAndSettle();
}

/// Listeler ekranında bir kartın menüsü.
Future<void> _openCardMenu(WidgetTester tester, String name) async {
  final card = find.ancestor(of: find.text(name), matching: find.byType(InkWell));
  await tester.tap(find.descendant(
    of: card.first,
    matching: find.byType(PopupMenuButton<String>),
  ));
  await tester.pumpAndSettle();
}

/// Kartın "Siyah" etiketi var mı?
Finder _badge(String name) => find.descendant(
      of: find.ancestor(of: find.text(name), matching: find.byType(InkWell))
          .first,
      matching: find.text(t('common.black')),
    );

Future<bool> _openFirstGameFlipped(WidgetTester tester) async {
  await tester.tap(find.text('Beyaz Oyuncu'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.byType(GameScreen), findsOneWidget);
  return tester.widget<ChessBoardWidget>(find.byType(ChessBoardWidget)).flipped;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    _silencePlugins();
    SharedPreferences.setMockInitialValues({
      'flutter.soundEnabled': false,
      'flutter.soundDefaultsRestored': true,
    });
    _storage.resetCache();
    await SettingsService.instance.load();
    Strings.language = AppLanguage.turkish;
  });

  tearDown(() => Strings.language = AppLanguage.system);

  testWidgets('liste menüsünden işaretleniyor, kartta etiket çıkıyor',
      (tester) async {
    final list = await _list('Sicilya oyunları');
    await _list('Karışık');
    await _pump(tester, const PlaylistScreen());
    expect(_badge('Sicilya oyunları'), findsNothing);

    await _openCardMenu(tester, 'Sicilya oyunları');
    final item = find.widgetWithText(
        CheckedPopupMenuItem<String>, t('lists.blackSide'));
    expect(item, findsOneWidget);
    expect(tester.widget<CheckedPopupMenuItem<String>>(item).checked, isFalse);
    await tester.tap(item);
    await tester.pumpAndSettle();

    expect(_badge('Sicilya oyunları'), findsOneWidget);
    expect(_badge('Karışık'), findsNothing);
    expect(await _storage.blackPlaylists(), {list.id});

    // Menü işaretli gösteriyor; yeniden seçince kalkıyor.
    await _openCardMenu(tester, 'Sicilya oyunları');
    expect(tester.widget<CheckedPopupMenuItem<String>>(item).checked, isTrue);
    await tester.tap(item);
    await tester.pumpAndSettle();
    expect(_badge('Sicilya oyunları'), findsNothing);
    expect(await _storage.blackPlaylists(), isEmpty);
  });

  testWidgets('işaretli listenin oyunu tahta çevrili açılıyor',
      (tester) async {
    final list = await _list('Siyahla');
    await _storage.setPlaylistBlack(list.id, true);
    await _pump(tester, PlaylistDetailScreen(playlistId: list.id));
    expect(await _openFirstGameFlipped(tester), isTrue);
  });

  testWidgets('işaretsiz listenin oyunu beyazın gözünden', (tester) async {
    final list = await _list('Beyazla');
    await _pump(tester, PlaylistDetailScreen(playlistId: list.id));
    expect(await _openFirstGameFlipped(tester), isFalse);
  });

  testWidgets('liste içindeki menüden de açılıp kapanıyor', (tester) async {
    final list = await _list('İçeriden');
    await _pump(tester, PlaylistDetailScreen(playlistId: list.id));

    // Uygulama çubuğundaki son menü.
    await tester.tap(find.descendant(
      of: find.byType(AppBar),
      matching: find.byType(PopupMenuButton<String>),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(
        CheckedPopupMenuItem<String>, t('lists.blackSide')));
    await tester.pumpAndSettle();
    expect(await _storage.blackPlaylists(), {list.id});

    expect(await _openFirstGameFlipped(tester), isTrue,
        reason: 'işaret hemen geçerli olmalı, ekrandan çıkıp girmeden');
  });
}
