import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/models/opening.dart';
import 'package:chess_pgn_reader/models/playlist.dart';
import 'package:chess_pgn_reader/screens/game_screen.dart';
import 'package:chess_pgn_reader/screens/openings/opening_list_screen.dart';
import 'package:chess_pgn_reader/screens/openings/opening_study_screen.dart';
import 'package:chess_pgn_reader/screens/playlist_detail_screen.dart';
import 'package:chess_pgn_reader/screens/playlist_screen.dart';
import 'package:chess_pgn_reader/services/engine/engine_service.dart';
import 'package:chess_pgn_reader/services/opening_service.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/services/storage_service.dart';
import 'package:chess_pgn_reader/widgets/chess_board_widget.dart';
import 'package:chess_pgn_reader/widgets/move_list.dart';
import 'package:chess_pgn_reader/widgets/player_side.dart';

/// 10.8.0: bekleyen işler — ekranlar.
///
/// Yalnızca tercih deposuyla koşuyor: sahte saatli ekran testlerinde
/// dosya deposunun gerçek disk işlemleri bitmiyor.

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

Future<void> _pump(
  WidgetTester tester,
  Widget screen, {
  Size size = const Size(412, 915),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pumpAndSettle();
}

ChessBoardWidget _board(WidgetTester tester) =>
    tester.widget<ChessBoardWidget>(find.byType(ChessBoardWidget));

Rect _boardRect(WidgetTester tester) =>
    tester.getRect(find.byType(ChessBoardWidget));

const _italian = ['e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1c4', 'f8c5'];

int _cursor(WidgetTester tester) =>
    tester.widget<MoveList>(find.byType(MoveList)).currentIndex;

bool _enabled(WidgetTester tester, String tooltip) => tester
        .widget<IconButton>(find.ancestor(
          of: find.byTooltip(tooltip),
          matching: find.byType(IconButton),
        ))
        .onPressed !=
    null;

/// Ekranı kapatıp bekleyen zamanlayıcıları boşaltır.
Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 3));
}

/// Motor düğmesi soluk mu (kilitli görünüyor mu)?
bool _engineLooksLocked(WidgetTester tester) {
  final color = tester.widget<Icon>(find.byIcon(Icons.insights_rounded)).color;
  return color != null && color.a < 0.5;
}

/// Ekrandaki hız düğmesinden hız seçer.
Future<void> _pickSpeed(WidgetTester tester, WatchSpeed speed) async {
  await tester.tap(find.byIcon(Icons.speed_rounded));
  await tester.pumpAndSettle();
  await tester.tap(find.text(speed.label).last);
  await tester.pumpAndSettle();
}

Opening _line() => Opening(
      id: 'o1',
      eco: 'C50',
      family: 'İtalyan',
      variation: 'Giuoco Piano',
      uciMoves: _italian,
      sanMoves: const ['e4', 'e5', 'Nf3', 'Nc6', 'Bc4', 'Bc5'],
      custom: true,
    );

SearchResult _result(String pv) => SearchResult(
      bestMoveUci: pv.split(' ').first,
      scoreCp: 25,
      depth: 12,
      nodes: 1,
      pvUci: pv.split(' '),
    );

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

  group('Açılış ekranında tahta kaymıyor', () {
    for (final size in const [Size(412, 915), Size(360, 640)]) {
      testWidgets('motor açılıp kapanınca (${size.width.toInt()}×'
          '${size.height.toInt()})', (tester) async {
        OpeningStudyScreen.debugAnalyze =
            (fen) async => _result('e2e4 e7e5 g1f3 b8c6 f1c4 f8c5');
        await _pump(tester, OpeningStudyScreen(opening: _line()), size: size);
        final before = _boardRect(tester);

        await tester.tap(find.byTooltip(t('game.analysisOn')));
        await tester.pump();
        expect(_boardRect(tester), before, reason: 'motor düşünürken');
        await tester.pumpAndSettle();
        expect(find.textContaining('+0.25'), findsOneWidget);
        expect(_boardRect(tester), before, reason: 'sonuç gelince');

        await tester.tap(find.byTooltip(t('game.analysisOff')));
        await tester.pumpAndSettle();
        expect(_boardRect(tester), before, reason: 'motor kapanınca');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('alıştırmada uyarı çıkınca', (tester) async {
      await _pump(tester, OpeningStudyScreen(opening: _line()));
      await tester.tap(find.text(t('openings.practice')));
      await tester.pumpAndSettle();
      final before = _boardRect(tester);

      final game = _board(tester).game;
      _board(tester).onMove!(game.moveFromUci('e2e4')!);
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();
      expect(find.text(t('openings.rightMove', {'move': 'e4'})),
          findsOneWidget);
      expect(_boardRect(tester), before, reason: '"Doğru" yazısı çıkınca');

      _board(tester).onMove!(_board(tester).game.moveFromUci('d2d4')!);
      await tester.pumpAndSettle();
      expect(find.text(t('openings.wrongMove')), findsOneWidget);
      expect(_boardRect(tester), before, reason: 'yanlış hamle uyarısında');
    });
  });

  testWidgets('açılış listesinden favori ekleniyor ve çıkarılıyor',
      (tester) async {
    final a1 = (await _openings.addFromSan(
        family: 'Açık', variation: 'a1', moveText: '1. e4 e5'))!;
    await _pump(tester, const OpeningListScreen(), size: const Size(700, 1100));
    await tester.tap(find.text('Açık'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.star_rounded), findsNothing);

    await tester.tap(find.byTooltip(t('openings.variationMenu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t('common.favoriteAdd')));
    await tester.pumpAndSettle();
    expect((await _openings.progressOf(a1.id)).favorite, isTrue);
    expect(find.byType(OpeningStudyScreen), findsNothing,
        reason: 'varyanta girilmedi');

    await tester.tap(find.byTooltip(t('openings.variationMenu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t('common.favoriteRemove')));
    await tester.pumpAndSettle();
    expect((await _openings.progressOf(a1.id)).favorite, isFalse);
  });

  group('İzlerken motor duruyor', () {
    final asked = <String>[];
    setUp(asked.clear);

    Future<SearchResult> analyze(String fen) async {
      asked.add(fen);
      return _result('e2e4');
    }

    testWidgets('açılış: kilitli, bitince geri açılıyor; baştan izle de',
        (tester) async {
      OpeningStudyScreen.debugAnalyze = analyze;
      _settings.openingWatchSpeed = WatchSpeed.veryFast;
      await _pump(tester, OpeningStudyScreen(opening: _line()));
      await tester.tap(find.byTooltip(t('game.analysisOn')));
      await tester.pumpAndSettle();
      expect(asked, hasLength(1));

      await tester.tap(find.byTooltip(t('common.play')));
      await tester.pump();
      expect(find.byTooltip(t('game.analysisOff')), findsNothing,
          reason: 'motor izlerken kapalı');
      expect(_enabled(tester, t('game.analysisOn')), isFalse,
          reason: 'düğmesi kilitli');
      expect(_engineLooksLocked(tester), isTrue,
          reason: 'kilitli olduğu görünüyor');
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      await tester.pumpAndSettle();
      expect(_cursor(tester), 5);
      expect(asked, hasLength(2), reason: 'izlerken motor sorulmadı');
      expect(find.byTooltip(t('game.analysisOff')), findsOneWidget,
          reason: 'bitince geri açıldı');
      expect(asked.last, _board(tester).game.fen, reason: 'son konum soruldu');

      // Baştan izle: yine kilitleniyor; duraklatınca geri açılıyor.
      await tester.tap(find.byTooltip(t('common.watchAgain')));
      await tester.pump();
      expect(_enabled(tester, t('game.analysisOn')), isFalse);
      await tester.pump(const Duration(milliseconds: 510));
      await tester.tap(find.byTooltip(t('common.pause')));
      await tester.pumpAndSettle();
      expect(find.byTooltip(t('game.analysisOff')), findsOneWidget);
      expect(_enabled(tester, t('game.analysisOff')), isTrue);
      expect(_engineLooksLocked(tester), isFalse);
      await _dispose(tester);
    });

    testWidgets('açılış: motor kapalıyken izlenirse kapalı kalıyor',
        (tester) async {
      OpeningStudyScreen.debugAnalyze = analyze;
      _settings.openingWatchSpeed = WatchSpeed.veryFast;
      await _pump(tester, OpeningStudyScreen(opening: _line()));
      await tester.tap(find.byTooltip(t('common.play')));
      for (var i = 0; i < 7; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      await tester.pumpAndSettle();
      expect(_enabled(tester, t('game.analysisOn')), isTrue);
      expect(asked, isEmpty);
      await _dispose(tester);
    });

    testWidgets('oyun: kilitli, elle gezinince ve bitince geri açılıyor',
        (tester) async {
      GameScreen.debugAnalyze = analyze;
      _settings.gameWatchSpeed = WatchSpeed.veryFast;
      await _pump(tester, const GameScreen(uciMoves: _italian, title: 'x'));
      await tester.tap(find.byTooltip(t('game.analysisOn')));
      await tester.pumpAndSettle();
      expect(asked, hasLength(1));

      await tester.tap(find.byTooltip(t('common.play')));
      await tester.pump(const Duration(milliseconds: 510));
      expect(_enabled(tester, t('game.analysisOn')), isFalse);
      expect(_engineLooksLocked(tester), isTrue);
      await tester.pump(const Duration(milliseconds: 500));
      expect(_cursor(tester), 1);
      await tester.pump(const Duration(seconds: 1));
      expect(asked, hasLength(1), reason: 'izlerken motor sorulmadı');

      // Elle gezinmek izlemeyi durduruyor, motor geri açılıyor.
      await tester.tap(find.byTooltip(t('common.previous')));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byTooltip(t('game.analysisOff')), findsOneWidget);
      expect(asked.length, greaterThanOrEqualTo(2));

      // Kendiliğinden bitince de.
      final before = asked.length;
      await tester.tap(find.byTooltip(t('common.play')));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(_cursor(tester), 5);
      expect(find.byTooltip(t('game.analysisOff')), findsOneWidget);
      expect(asked.length, before + 1, reason: 'yalnızca son konum soruldu');
      await _dispose(tester);
    });
  });

  group('Ekrandaki hız düğmesi', () {
    testWidgets('açılış: ayara yazıyor, izlerken hemen geçerli',
        (tester) async {
      _settings.openingWatchSpeed = WatchSpeed.veryFast;
      await _pump(tester, OpeningStudyScreen(opening: _line()));
      await tester.tap(find.byTooltip(t('common.play')));
      await tester.pump(const Duration(milliseconds: 510));
      expect(_cursor(tester), 0);

      // Seçim, menü kapanmadan (yarım saniye) önce geçerli oluyor; yeni
      // tempo seçim anından sayılıyor.
      await _pickSpeed(tester, WatchSpeed.verySlow);
      expect(_settings.openingWatchSpeed, WatchSpeed.verySlow);
      final at = _cursor(tester);
      await tester.pump(const Duration(milliseconds: 1500));
      expect(_cursor(tester), at, reason: 'Çok yavaş: 2,5 sn');
      await tester.pump(const Duration(milliseconds: 700));
      expect(_cursor(tester), at + 1);
      expect(find.byTooltip(t('common.pause')), findsOneWidget,
          reason: 'hız değişince izleme sürüyor');
      await _dispose(tester);
    });

    testWidgets('oyun: ayara yazıyor; motora karşı oyunda yok',
        (tester) async {
      await _pump(tester, const GameScreen(uciMoves: _italian, title: 'x'));
      await _pickSpeed(tester, WatchSpeed.fast);
      expect(_settings.gameWatchSpeed, WatchSpeed.fast);
      expect(_settings.openingWatchSpeed, WatchSpeed.normal);
      expect(
        find.byTooltip(t('settings.watchSpeedNow',
            {'speed': WatchSpeed.fast.label})),
        findsOneWidget,
      );
      await _dispose(tester);
    });
  });

  group('Oyuncunun gözünden oku', () {
    SavedGame game(String white, String black) => SavedGame(
          name: '$white - $black',
          uciMoves: const ['e2e4', 'e7e5'],
          createdAt: DateTime(2026, 10, 1),
          white: white,
          black: black,
        );

    Future<Playlist> list() => _storage.createPlaylistWithGames('Maçlar', [
          game('Fischer, Robert James', 'Spassky, Boris'),
          game('Spassky, Boris', 'Fischer, Robert James'),
          game('Tal, Mikhail', 'Botvinnik, Mikhail'),
        ]);

    Future<void> setName(WidgetTester tester, String name) async {
      await tester.enterText(find.byType(TextField).last, name);
      await tester.tap(find.text(t('common.save')));
      await tester.pumpAndSettle();
    }

    testWidgets('kart menüsünden ad yazılıyor, kartta görünüyor, '
        'kaldırılıyor', (tester) async {
      final playlist = await list();
      await _pump(tester, const PlaylistScreen(), size: const Size(700, 1100));
      final card =
          find.ancestor(of: find.text('Maçlar'), matching: find.byType(InkWell));
      Future<void> openMenu() async {
        await tester.tap(find.descendant(
          of: card.first,
          matching: find.byType(PopupMenuButton<String>),
        ));
        await tester.pumpAndSettle();
      }

      await openMenu();
      await tester.tap(find.text(t('lists.playerSide')));
      await tester.pumpAndSettle();
      await setName(tester, 'fischer');
      expect(await _storage.playlistPlayers(), {playlist.id: 'fischer'});
      expect(find.byType(PlayerSideBadge), findsOneWidget);

      await openMenu();
      await tester.tap(
          find.text(t('lists.playerSideNamed', {'name': 'fischer'})));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('lists.playerSideRemove')));
      await tester.pumpAndSettle();
      expect(await _storage.playlistPlayers(), isEmpty);
      expect(find.byType(PlayerSideBadge), findsNothing);
    });

    testWidgets('oyuncunun olduğu taraf aşağıda; oyundan oyuna değişiyor',
        (tester) async {
      final playlist = await list();
      await _storage.setPlaylistBlack(playlist.id, true);
      await _pump(tester, PlaylistDetailScreen(playlistId: playlist.id),
          size: const Size(700, 1100));

      // Listenin içindeki menüden.
      await tester.tap(find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(PopupMenuButton<String>),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('lists.playerSide')));
      await tester.pumpAndSettle();
      await setName(tester, 'Fischer');

      await tester.tap(find.text('Spassky, Boris').first);
      await tester.pumpAndSettle();
      expect(find.text(t('lists.gamePosition', {'n': 1, 'total': 3})),
          findsOneWidget);
      expect(_board(tester).flipped, isFalse,
          reason: 'Fischer beyaz: siyah işaretine rağmen beyazdan');

      await tester.tap(find.byTooltip(t('lists.nextGame')));
      await tester.pumpAndSettle();
      expect(_board(tester).flipped, isTrue, reason: 'Fischer siyah');

      await tester.tap(find.byTooltip(t('lists.nextGame')));
      await tester.pumpAndSettle();
      expect(_board(tester).flipped, isTrue,
          reason: 'Fischer yok: listenin siyah işareti');

      // Elle çevirme, oyunun kendi yönüne göre taşınıyor.
      await tester.tap(find.byTooltip(t('lists.previousGame')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(t('common.flipBoard')));
      await tester.pumpAndSettle();
      expect(_board(tester).flipped, isFalse);
      await tester.tap(find.byTooltip(t('lists.previousGame')));
      await tester.pumpAndSettle();
      expect(_board(tester).flipped, isTrue,
          reason: 'Fischer beyaz ama tahta elle çevrilmişti');
    });

    testWidgets('küçük telefonda kart: etiketler ada yer bırakıyor',
        (tester) async {
      // Eskiden etiketler adın yanındaydı: "Siyah" + uzun oyuncu adıyla
      // 360 piksellik telefonda ada 2 piksel kalıyor, ad harf harf alt
      // alta diziliyordu (308 piksel boy). Artık sayı satırındalar.
      final playlist = await _storage.createPlaylistWithGames(
          'Fischer maçları', [game('Fischer', 'Spassky')]);
      await _storage.setPlaylistBlack(playlist.id, true);
      await _storage.setPlaylistPlayer(playlist.id, 'Fischer, Robert James');
      await _pump(tester, const PlaylistScreen(), size: const Size(360, 640));
      expect(tester.takeException(), isNull);
      final title = tester.getSize(find.text('Fischer maçları'));
      expect(title.width, greaterThan(150));
      expect(title.height, lessThan(60), reason: 'en çok iki satır');
      expect(find.byType(PlayerSideBadge), findsOneWidget);
    });

    testWidgets('pencerede vazgeçince bir şey değişmiyor', (tester) async {
      final playlist = await list();
      await _storage.setPlaylistPlayer(playlist.id, 'Tal');
      await _pump(tester, PlaylistDetailScreen(playlistId: playlist.id),
          size: const Size(700, 1100));
      await tester.tap(find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(PopupMenuButton<String>),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('lists.playerSideNamed', {'name': 'Tal'})));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Tal'), findsOneWidget,
          reason: 'yazılı ad hazır geliyor');
      await tester.enterText(find.byType(TextField).last, 'Fischer');
      await tester.tap(find.text(t('common.cancel')));
      await tester.pumpAndSettle();
      expect(await _storage.playlistPlayers(), {playlist.id: 'Tal'});
    });
  });
}
