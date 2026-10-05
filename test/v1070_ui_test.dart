import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/models/chess_engine.dart' as engine;
import 'package:chess_pgn_reader/models/opening.dart';
import 'package:chess_pgn_reader/models/playlist.dart';
import 'package:chess_pgn_reader/screens/game_screen.dart';
import 'package:chess_pgn_reader/screens/openings/opening_list_screen.dart';
import 'package:chess_pgn_reader/screens/openings/opening_study_screen.dart';
import 'package:chess_pgn_reader/screens/playlist_detail_screen.dart';
import 'package:chess_pgn_reader/screens/playlist_order_screen.dart';
import 'package:chess_pgn_reader/screens/playlist_screen.dart';
import 'package:chess_pgn_reader/screens/settings_screen.dart';
import 'package:chess_pgn_reader/services/engine/engine_service.dart';
import 'package:chess_pgn_reader/services/opening_service.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/services/storage_service.dart';
import 'package:chess_pgn_reader/widgets/chess_board_widget.dart';
import 'package:chess_pgn_reader/widgets/move_list.dart';

/// 10.7.0: bekleyen işler — ekranlar.
///
/// * Siyahla alıştırmada "Baştan" beyazın ilk hamlesini yeniden oynuyor.
/// * Açılış başlığında "Tümü öğrenildi / öğrenilmedi", varyant satırında
///   içine girmeden öğrenildi işareti.
/// * Çalışma ekranında önceki / sonraki varyant (listedeki sırayla).
/// * Oyun listesinden açılan oyunda önceki / sonraki oyun ve "İzle".
/// * "İzle" sonda "Baştan izle"; hızı ayarlardan (iki ayrı ayar).
/// * Oyun listelerinin sırası.
///
/// Yalnızca tercih deposuyla koşuyor: sahte saatli ekran testlerinde
/// dosya deposunun gerçek disk işlemleri bitmiyor. Servis tarafı
/// `v1070_service_test.dart` içinde.

final _openings = OpeningService.instance;
final _storage = StorageService.instance;
final _settings = SettingsService.instance;

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

Future<Opening> _add(String family, String variation, String moves) async =>
    (await _openings.addFromSan(
      family: family,
      variation: variation,
      moveText: moves,
    ))!;

Future<void> _pump(
  WidgetTester tester,
  Widget screen, {
  Size size = const Size(700, 1100),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pumpAndSettle();
}

ChessBoardWidget _board(WidgetTester tester) =>
    tester.widget<ChessBoardWidget>(find.byType(ChessBoardWidget));

int _cursor(WidgetTester tester) =>
    tester.widget<MoveList>(find.byType(MoveList)).currentIndex;

/// Düğmenin basılabilir olup olmadığı (ipucu yazısından).
bool _enabled(WidgetTester tester, String tooltip) => tester
        .widget<IconButton>(find.ancestor(
          of: find.byTooltip(tooltip),
          matching: find.byType(IconButton),
        ))
        .onPressed !=
    null;

Finder _appBarText(String text) =>
    find.descendant(of: find.byType(AppBar), matching: find.text(text));

Future<void> _openFamilyMenu(WidgetTester tester, String family) async {
  final tile = find.ancestor(
    of: find.text(family),
    matching: find.byType(ExpansionTile),
  );
  await tester.tap(find.descendant(
    of: tile,
    matching: find.byTooltip(t('openings.familyMenu')),
  ));
  await tester.pumpAndSettle();
}

/// Ekranı kapatıp bekleyen zamanlayıcıları boşaltır.
Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 2));
}

SavedGame _game(String white, List<String> moves, {bool read = false}) =>
    SavedGame(
      name: '$white - Rakip',
      uciMoves: moves,
      createdAt: DateTime(2026, 9, 1),
      white: white,
      black: 'Rakip',
      read: read,
    );

const _italian = ['e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1c4', 'f8c5'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    _silencePlugins();
    SharedPreferences.setMockInitialValues({
      'flutter.soundEnabled': false,
      'flutter.animateMoves': true,
      'flutter.soundDefaultsRestored': true,
    });
    _openings.resetCache();
    _storage.resetCache();
    await _settings.load();
    Strings.language = AppLanguage.turkish;
  });

  tearDown(() {
    Strings.language = AppLanguage.system;
    OpeningStudyScreen.debugAnalyze = null;
    GameScreen.debugAnalyze = null;
  });

  group('Alıştırmada "Baştan"', () {
    Opening line() => Opening(
          id: 'o1',
          eco: 'B20',
          family: 'Sicilya',
          variation: 'Najdorf',
          uciMoves: const ['e2e4', 'c7c5', 'g1f3', 'd7d6'],
          sanMoves: const ['e4', 'c5', 'Nf3', 'd6'],
          custom: true,
        );

    testWidgets('siyahla: beyazın ilk hamlesi yeniden oynanıyor, tahta '
        'kilitli kalmıyor', (tester) async {
      await _pump(tester, OpeningStudyScreen(opening: line(), blackSide: true));
      await tester.tap(find.text(t('openings.practice')));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(_cursor(tester), 0, reason: 'beyazın ilk hamlesini tahta oynar');

      // Siyahın doğru hamlesi; tahta beyazın cevabını oynuyor.
      final game = _board(tester).game;
      _board(tester).onMove!(game.moveFromUci('c7c5')!);
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();
      expect(_cursor(tester), 2);

      await tester.tap(find.text(t('common.restart')));
      await tester.pump();
      expect(_cursor(tester), -1, reason: 'önce başa sarılıyor');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(_cursor(tester), 0,
          reason: 'eskiden burada kalıyordu: sıra beyazda, tahta kilitli');
      expect(_board(tester).game.sideToMove, engine.Color.black);
      expect(_board(tester).movableSide, engine.Color.black);
    });

    testWidgets('beyazla: yalnızca başa sarıyor', (tester) async {
      await _pump(tester, OpeningStudyScreen(opening: line()));
      await tester.tap(find.text(t('openings.practice')));
      await tester.pumpAndSettle();
      final game = _board(tester).game;
      _board(tester).onMove!(game.moveFromUci('e2e4')!);
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();
      expect(_cursor(tester), 1);

      await tester.tap(find.text(t('common.restart')));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(_cursor(tester), -1);
      expect(_board(tester).game.sideToMove, engine.Color.white);
    });
  });

  group('Öğrenildi işaretleri', () {
    Future<void> pumpList(WidgetTester tester) =>
        _pump(tester, const OpeningListScreen());

    PopupMenuItem<String> item(WidgetTester tester, String text) =>
        tester.widget<PopupMenuItem<String>>(
            find.widgetWithText(PopupMenuItem<String>, text));

    testWidgets('başlık menüsü: tümü öğrenildi, tümü öğrenilmedi',
        (tester) async {
      final a1 = await _add('Açık', 'a1', '1. e4 e5');
      final a2 = await _add('Açık', 'a2', '1. e4 e5 2. Nf3');
      await pumpList(tester);

      await _openFamilyMenu(tester, 'Açık');
      expect(item(tester, t('openings.markAllNotLearned')).enabled, isFalse,
          reason: 'öğrenilmiş varyant yok');
      await tester.tap(find.text(t('openings.markAllLearned')));
      await tester.pumpAndSettle();
      expect(
        find.text(t('openings.markAllLearnedMessage',
            {'family': 'Açık', 'count': 2})),
        findsOneWidget,
      );
      await tester.tap(find.text(t('openings.mark')));
      await tester.pumpAndSettle();
      expect((await _openings.progressOf(a1.id)).learned, isTrue);
      expect((await _openings.progressOf(a2.id)).learned, isTrue);
      expect(
        find.text(t('openings.familySummary', {'count': 2, 'learned': 2})),
        findsOneWidget,
      );

      await _openFamilyMenu(tester, 'Açık');
      expect(item(tester, t('openings.markAllLearned')).enabled, isFalse);
      await tester.tap(find.text(t('openings.markAllNotLearned')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('openings.mark')));
      await tester.pumpAndSettle();
      expect((await _openings.progressOf(a1.id)).learned, isFalse);
      expect((await _openings.progressOf(a2.id)).learned, isFalse);
    });

    testWidgets('vazgeçince bir şey değişmiyor', (tester) async {
      final a1 = await _add('Açık', 'a1', '1. e4 e5');
      await pumpList(tester);
      await _openFamilyMenu(tester, 'Açık');
      await tester.tap(find.text(t('openings.markAllLearned')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('common.giveUp')));
      await tester.pumpAndSettle();
      expect((await _openings.progressOf(a1.id)).learned, isFalse);
    });

    testWidgets('arama açıkken de başlığın tamamı işaretleniyor',
        (tester) async {
      final a1 = await _add('Açık', 'a1', '1. e4 e5');
      final a2 = await _add('Açık', 'a2', '1. e4 e5 2. Nf3');
      await pumpList(tester);
      await tester.enterText(find.byType(TextField), 'Nf3');
      await tester.pumpAndSettle();

      await _openFamilyMenu(tester, 'Açık');
      await tester.tap(find.text(t('openings.markAllLearned')));
      await tester.pumpAndSettle();
      expect(
        find.text(t('openings.markAllLearnedMessage',
            {'family': 'Açık', 'count': 2})),
        findsOneWidget,
        reason: 'onay süzgeçsiz sayıyı söylemeli',
      );
      await tester.tap(find.text(t('openings.mark')));
      await tester.pumpAndSettle();
      expect((await _openings.progressOf(a1.id)).learned, isTrue);
      expect((await _openings.progressOf(a2.id)).learned, isTrue);
    });

    testWidgets('varyant satırı: içine girmeden işaretleniyor ve kalkıyor',
        (tester) async {
      final a1 = await _add('Açık', 'a1', '1. e4 e5');
      await pumpList(tester);
      await tester.tap(find.text('Açık'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);

      await tester.tap(find.byTooltip(t('openings.variationMenu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('openings.markLearned')));
      await tester.pumpAndSettle();
      expect((await _openings.progressOf(a1.id)).learned, isTrue);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(find.byType(OpeningStudyScreen), findsNothing,
          reason: 'varyanta girilmedi');

      await tester.tap(find.byTooltip(t('openings.variationMenu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('openings.markNotLearned')));
      await tester.pumpAndSettle();
      expect((await _openings.progressOf(a1.id)).learned, isFalse);
      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
    });
  });

  group('Önceki / sonraki varyant', () {
    Future<void> openFromList(
        WidgetTester tester, String family, String variation) async {
      await _pump(tester, const OpeningListScreen());
      await tester.tap(find.text(family));
      await tester.pumpAndSettle();
      await tester.tap(find.text(variation));
      await tester.pumpAndSettle();
      expect(_appBarText(variation), findsOneWidget);
    }

    Future<void> step(WidgetTester tester, String tooltip) async {
      await tester.tap(find.byTooltip(tooltip));
      await tester.pumpAndSettle();
    }

    testWidgets('listedeki sırayla geziyor, kart sınırını aşıyor, sonda '
        'duruyor', (tester) async {
      await _add('Açık', 'a1', '1. e4 e5');
      await _add('Açık', 'a2', '1. e4 e5 2. Nf3');
      await _add('Sicilya', 'b1', '1. e4 c5');
      await _openings.setFamilyBlack('Sicilya', true);
      await openFromList(tester, 'Açık', 'a2');
      expect(_board(tester).flipped, isFalse);

      await step(tester, t('openings.nextVariation'));
      expect(_appBarText('b1'), findsOneWidget,
          reason: 'kartın son varyantından sonraki kartın ilkine');
      expect(_board(tester).flipped, isTrue, reason: 'Sicilya siyahtan');
      expect(_enabled(tester, t('openings.nextVariation')), isFalse,
          reason: 'son kartın son varyantı');

      await step(tester, t('openings.previousVariation'));
      await step(tester, t('openings.previousVariation'));
      expect(_appBarText('a1'), findsOneWidget);
      expect(_board(tester).flipped, isFalse);
      expect(_enabled(tester, t('openings.previousVariation')), isFalse);
      expect(_cursor(tester), -1, reason: 'her varyant baştan açılıyor');
    });

    testWidgets('arama açıkken yalnızca görünen varyantlarda', (tester) async {
      await _add('Açık', 'a1', '1. e4 e5');
      await _add('Açık', 'a2', '1. e4 e5 2. Nf3');
      await _add('Sicilya', 'b1', '1. e4 c5');
      await _pump(tester, const OpeningListScreen());
      await tester.enterText(find.byType(TextField), 'e5');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Açık'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('a1'));
      await tester.pumpAndSettle();

      await step(tester, t('openings.nextVariation'));
      expect(_appBarText('a2'), findsOneWidget);
      expect(_enabled(tester, t('openings.nextVariation')), isFalse,
          reason: 'b1 aramaya uymuyor');
    });

    testWidgets('tek varyant açıksa oklar yok', (tester) async {
      await _add('Açık', 'a1', '1. e4 e5');
      await openFromList(tester, 'Açık', 'a1');
      expect(find.byTooltip(t('openings.nextVariation')), findsNothing);
    });

    testWidgets('alıştırma kipi ve motor yeni varyanta taşınıyor',
        (tester) async {
      final asked = <String>[];
      OpeningStudyScreen.debugAnalyze = (fen) async {
        asked.add(fen);
        return const SearchResult(
          bestMoveUci: 'e2e4',
          scoreCp: 20,
          depth: 10,
          nodes: 1,
          pvUci: ['e2e4'],
        );
      };
      await _add('Açık', 'a1', '1. e4 e5');
      await _add('Sicilya', 'b1', '1. e4 c5');
      await _openings.setFamilyBlack('Sicilya', true);
      await openFromList(tester, 'Açık', 'a1');

      await tester.tap(find.text(t('openings.practice')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(t('game.analysisOn')));
      await tester.pumpAndSettle();
      expect(asked, hasLength(1));

      await tester.tap(find.byTooltip(t('openings.nextVariation')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(_appBarText('b1'), findsOneWidget);
      final segmented = tester.widget<SegmentedButton<StudyMode>>(
          find.byType(SegmentedButton<StudyMode>));
      expect(segmented.selected, {StudyMode.practice});
      expect(find.byTooltip(t('game.analysisOff')), findsOneWidget,
          reason: 'motor açık kaldı');
      expect(asked.length, greaterThanOrEqualTo(2),
          reason: 'yeni varyantın konumu da soruldu');
      expect(_cursor(tester), 0,
          reason: 'siyah başlıkta alıştırma: beyazın ilk hamlesini tahta '
              'oynadı');
      await _dispose(tester);
    });

    testWidgets('geniş pencerede oklar tahtayı küçültmüyor', (tester) async {
      final a1 = await _add('Açık', 'a1', '1. e4 e5');
      final a2 = await _add('Açık', 'a2', '1. e4 e5 2. Nf3');
      const wide = Size(1400, 1000);
      await _pump(tester, OpeningStudyScreen(opening: a1), size: wide);
      final alone = tester.getSize(find.byType(ChessBoardWidget));
      await _pump(
        tester,
        // Anahtar: ilk ekranın durumu yeniden kullanılmasın.
        OpeningStudyScreen(
          key: const ValueKey('sıralı'),
          opening: a1,
          sequence: [a1, a2],
        ),
        size: wide,
      );
      expect(find.byTooltip(t('openings.nextVariation')), findsOneWidget);
      expect(tester.getSize(find.byType(ChessBoardWidget)), alone);
      expect(tester.takeException(), isNull);
    });
  });

  group('İzle', () {
    Opening line() => Opening(
          id: 'o1',
          eco: 'C50',
          family: 'İtalyan',
          variation: 'Giuoco Piano',
          uciMoves: _italian,
          sanMoves: const ['e4', 'e5', 'Nf3', 'Nc6', 'Bc4', 'Bc5'],
          custom: true,
        );

    testWidgets('açılış: ayardaki hızla ilerliyor, sonda "Baştan izle"',
        (tester) async {
      // 0,5 sn: 10.7.0'ın "Hızlı"sı, 10.8.0'da "Çok hızlı".
      _settings.openingWatchSpeed = WatchSpeed.veryFast;
      await _pump(tester, OpeningStudyScreen(opening: line()));
      await tester.tap(find.byTooltip(t('common.play')));
      await tester.pump(const Duration(milliseconds: 510));
      expect(_cursor(tester), 0);
      await tester.pump(const Duration(milliseconds: 500));
      expect(_cursor(tester), 1);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      await tester.pumpAndSettle();
      expect(_cursor(tester), 5);
      expect(find.byTooltip(t('common.watchAgain')), findsOneWidget,
          reason: 'sonda tuş sönük değil, baştan izletiyor');

      await tester.tap(find.byTooltip(t('common.watchAgain')));
      await tester.pump();
      expect(_cursor(tester), -1);
      await tester.pump(const Duration(milliseconds: 510));
      expect(_cursor(tester), 0);

      // Elle gezinmek izlemeyi durduruyor.
      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pump();
      expect(_cursor(tester), 1);
      await tester.pump(const Duration(seconds: 2));
      expect(_cursor(tester), 1);
      expect(find.byTooltip(t('common.play')), findsOneWidget);
      await _dispose(tester);
    });

    testWidgets('oyun: oynat, duraklat, ayardaki hız', (tester) async {
      _settings.gameWatchSpeed = WatchSpeed.slow;
      await _pump(tester, const GameScreen(uciMoves: _italian, title: 'x'));
      await tester.tap(find.byTooltip(t('common.play')));
      await tester.pump(const Duration(milliseconds: 1000));
      expect(_cursor(tester), -1, reason: 'Yavaş: 1,5 sn');
      await tester.pump(const Duration(milliseconds: 510));
      expect(_cursor(tester), 0);
      await tester.pump(const Duration(milliseconds: 1500));
      expect(_cursor(tester), 1);

      await tester.tap(find.byTooltip(t('common.pause')));
      await tester.pump(const Duration(seconds: 4));
      expect(_cursor(tester), 1);
      await _dispose(tester);
    });

    testWidgets('oyun: sonda "Baştan izle"; hamleye dokunmak ve tahtada '
        'denemek izlemeyi durduruyor', (tester) async {
      _settings.gameWatchSpeed = WatchSpeed.veryFast;
      await _pump(tester, const GameScreen(uciMoves: _italian, title: 'x'));
      await tester.tap(find.byTooltip(t('game.toEnd')));
      await tester.pumpAndSettle();
      expect(find.byTooltip(t('common.watchAgain')), findsOneWidget);

      await tester.tap(find.byTooltip(t('common.watchAgain')));
      await tester.pump();
      expect(_cursor(tester), -1);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(_cursor(tester), 5);
      await tester.pump(const Duration(milliseconds: 10));
      expect(find.byTooltip(t('common.watchAgain')), findsOneWidget,
          reason: 'son hamlede hemen duruyor');

      // Hamleye dokunmak.
      await tester.tap(find.byTooltip(t('common.watchAgain')));
      await tester.pump(const Duration(milliseconds: 1010));
      expect(_cursor(tester), 1);
      await tester.tap(find.text('e4').first);
      await tester.pump(const Duration(seconds: 2));
      expect(_cursor(tester), 0);
      expect(find.byTooltip(t('common.play')), findsOneWidget);

      // Tahtada deneme hamlesi.
      await tester.tap(find.byTooltip(t('common.play')));
      await tester.pump(const Duration(milliseconds: 510));
      expect(_cursor(tester), 1);
      final game = _board(tester).game;
      _board(tester).onMove!(game.moveFromUci('d2d4')!);
      await tester.pump(const Duration(seconds: 2));
      expect(_cursor(tester), 1);
      expect(find.byTooltip(t('common.play')), findsOneWidget);
      await _dispose(tester);
    });
  });

  group('Oyun listesinde önceki / sonraki oyun', () {
    Future<Playlist> list([List<SavedGame>? games]) =>
        _storage.createPlaylistWithGames(
          'Liste',
          games ??
              [
                _game('Ali', const ['e2e4', 'e7e5']),
                _game('Banu', const ['d2d4', 'd7d5']),
                _game('Cem', const ['c2c4', 'e7e5']),
              ],
        );

    Future<void> open(WidgetTester tester, String white) async {
      await tester.tap(find.text(white));
      await tester.pumpAndSettle();
      expect(find.byType(GameScreen), findsOneWidget);
    }

    Finder position(int n, int total) =>
        find.text(t('lists.gamePosition', {'n': n, 'total': total}));

    testWidgets('sırayla geziyor ve liste bitince duruyor', (tester) async {
      final playlist = await list();
      await _pump(tester, PlaylistDetailScreen(playlistId: playlist.id));
      await open(tester, 'Banu');
      expect(position(2, 3), findsOneWidget);

      await tester.tap(find.byTooltip(t('lists.nextGame')));
      await tester.pumpAndSettle();
      expect(position(3, 3), findsOneWidget);
      expect(find.text('Cem'), findsOneWidget);
      expect(_enabled(tester, t('lists.nextGame')), isFalse,
          reason: 'sonraki listeye geçilmiyor');

      await tester.tap(find.byTooltip(t('lists.previousGame')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(t('lists.previousGame')));
      await tester.pumpAndSettle();
      expect(position(1, 3), findsOneWidget);
      expect(find.text('Ali'), findsOneWidget);
      expect(_enabled(tester, t('lists.previousGame')), isFalse);

      // Geri dönünce liste ekranı yerinde.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(PlaylistDetailScreen), findsOneWidget);
    });

    testWidgets('süzgeç ve ters sıra izleniyor', (tester) async {
      final playlist = await list([
        _game('Ali', const ['e2e4', 'e7e5'], read: true),
        _game('Banu', const ['d2d4', 'd7d5']),
        _game('Cem', const ['c2c4', 'e7e5']),
      ]);
      await _pump(tester, PlaylistDetailScreen(playlistId: playlist.id));
      await tester.tap(find.text(t('lists.filterUnread')));
      await tester.pumpAndSettle();
      await open(tester, 'Banu');
      expect(position(1, 2), findsOneWidget,
          reason: 'okunmuş oyun sırada yok');
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.text(t('puzzles.filterAll')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(t('puzzles.sortNewest')));
      await tester.pumpAndSettle();
      await open(tester, 'Cem');
      expect(position(1, 3), findsOneWidget);
      await tester.tap(find.byTooltip(t('lists.nextGame')));
      await tester.pumpAndSettle();
      expect(find.text('Banu'), findsOneWidget);
    });

    testWidgets('tahtanın yönü ve analiz yeni oyuna taşınıyor',
        (tester) async {
      final asked = <String>[];
      GameScreen.debugAnalyze = (fen) async {
        asked.add(fen);
        return const SearchResult(
          bestMoveUci: 'e2e4',
          scoreCp: 20,
          depth: 10,
          nodes: 1,
          pvUci: ['e2e4'],
        );
      };
      final playlist = await list();
      await _storage.setPlaylistBlack(playlist.id, true);
      await _pump(tester, PlaylistDetailScreen(playlistId: playlist.id));
      await open(tester, 'Ali');
      expect(_board(tester).flipped, isTrue, reason: 'liste siyahtan');

      await tester.tap(find.byTooltip(t('game.analysisOn')));
      await tester.pumpAndSettle();
      expect(asked, hasLength(1));
      await tester.tap(find.byTooltip(t('common.flipBoard')));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip(t('lists.nextGame')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();
      expect(find.text('Banu'), findsOneWidget);
      expect(_board(tester).flipped, isFalse,
          reason: 'elle çevrilen yön korunuyor');
      expect(find.byTooltip(t('game.analysisOff')), findsOneWidget);
      expect(asked, hasLength(2));
      await _dispose(tester);
    });

    testWidgets('tek oyunluk listede sıra çubuğu yok', (tester) async {
      final playlist = await list([_game('Ali', const ['e2e4'])]);
      await _pump(tester, PlaylistDetailScreen(playlistId: playlist.id));
      await open(tester, 'Ali');
      expect(find.byTooltip(t('lists.nextGame')), findsNothing);
    });
  });

  testWidgets('küçük telefonda sıra çubuğu ve oklar taşmıyor', (tester) async {
    const phone = Size(360, 640);
    final a = Opening(
      id: 'a',
      eco: 'C50',
      family: 'Çok uzun bir açılış başlığı adı, ekrana sığmayacak kadar',
      variation: 'a',
      uciMoves: _italian,
      sanMoves: const ['e4', 'e5', 'Nf3', 'Nc6', 'Bc4', 'Bc5'],
    );
    final b = Opening(
      id: 'b',
      eco: 'C50',
      family: a.family,
      variation: 'b',
      uciMoves: _italian,
      sanMoves: a.sanMoves,
    );
    await _pump(tester, OpeningStudyScreen(opening: a, sequence: [a, b]),
        size: phone);
    expect(tester.takeException(), isNull);
    await _pump(
      tester,
      GameScreen(
        key: const ValueKey('oyun'),
        uciMoves: _italian,
        title: 'x',
        sequence: GameSequence(
          position: 123,
          length: 4567,
          onPrevious: (_) {},
          onNext: (_) {},
        ),
      ),
      size: phone,
    );
    expect(tester.takeException(), isNull);
    expect(
      find.text(t('lists.gamePosition', {'n': 123, 'total': 4567})),
      findsOneWidget,
    );
  });

  group('Listelerin sırası', () {
    Future<List<String>> names() async {
      _storage.resetCache();
      return [for (final p in await _storage.loadPlaylists()) p.name];
    }

    testWidgets('tek listede sıralama düğmesi yok', (tester) async {
      await _storage.createPlaylist('A');
      await _pump(tester, const PlaylistScreen());
      expect(find.byTooltip(t('lists.order')), findsNothing);
    });

    testWidgets('sıralama ekranında en üste taşı; liste ekranı da o sırada',
        (tester) async {
      await _storage.createPlaylist('A');
      await _storage.createPlaylist('B');
      await _storage.createPlaylist('C');
      await _pump(tester, const PlaylistScreen());
      await tester.tap(find.byTooltip(t('lists.order')));
      await tester.pumpAndSettle();
      expect(find.byType(PlaylistOrderScreen), findsOneWidget);

      final buttons = find.byTooltip(t('openings.moveToTop'));
      expect(_enabledAt(tester, buttons, 0), isFalse);
      await tester.tap(buttons.at(2));
      await tester.pumpAndSettle();
      expect(await names(), ['C', 'A', 'B']);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('C')).dy,
        lessThan(tester.getTopLeft(find.text('A')).dy),
      );
    });

    testWidgets('kart menüsünden en üste taşı', (tester) async {
      await _storage.createPlaylist('A');
      await _storage.createPlaylist('B');
      await _pump(tester, const PlaylistScreen());
      final card = find.ancestor(
          of: find.text('B'), matching: find.byType(InkWell));
      await tester.tap(find.descendant(
        of: card.first,
        matching: find.byType(PopupMenuButton<String>),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('openings.moveToTop')));
      await tester.pumpAndSettle();
      expect(await names(), ['B', 'A']);
    });
  });

  group('Ayarlar', () {
    // 10.8.0: beş hız, açılır listede (üç parçalı düğme telefona
    // sığmıyordu).
    Future<void> choose(
        WidgetTester tester, Finder tile, WatchSpeed speed) async {
      await tester.scrollUntilVisible(tile, 200,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: tile, matching: find.byType(DropdownButton<WatchSpeed>)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(speed.label).last);
      await tester.pumpAndSettle();
    }

    testWidgets('izleme hızı: iki ayrı ayar', (tester) async {
      await _pump(tester, const SettingsScreen(), size: const Size(360, 800));
      final openings = find.byKey(const Key('watchSpeed-openings'));
      final games = find.byKey(const Key('watchSpeed-games'));

      await choose(tester, openings, WatchSpeed.fast);
      expect(_settings.openingWatchSpeed, WatchSpeed.fast);
      expect(_settings.gameWatchSpeed, WatchSpeed.normal);

      await choose(tester, games, WatchSpeed.verySlow);
      expect(_settings.gameWatchSpeed, WatchSpeed.verySlow);
      expect(_settings.openingWatchSpeed, WatchSpeed.fast);
      expect(tester.takeException(), isNull, reason: 'dar ekranda taşmıyor');
    });
  });
}

bool _enabledAt(WidgetTester tester, Finder tooltips, int index) => tester
        .widget<IconButton>(find.ancestor(
          of: tooltips.at(index),
          matching: find.byType(IconButton),
        ))
        .onPressed !=
    null;
