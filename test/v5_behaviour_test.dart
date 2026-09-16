import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/models/pgn_parser.dart';
import 'package:chess_pgn_reader/models/playlist.dart';
import 'package:chess_pgn_reader/screens/home_screen.dart';
import 'package:chess_pgn_reader/screens/openings/opening_list_screen.dart';
import 'package:chess_pgn_reader/screens/pgn_import_screen.dart';
import 'package:chess_pgn_reader/services/analysis_queue.dart';
import 'package:chess_pgn_reader/services/engine/engine_service.dart';
import 'package:chess_pgn_reader/services/opening_service.dart';
import 'package:chess_pgn_reader/services/puzzle_service.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/services/storage_service.dart';
import 'package:chess_pgn_reader/widgets/app_dialogs.dart';
import 'package:chess_pgn_reader/widgets/picker_panel.dart';

/// Sürüm 5'te değişen davranışlar.
///
/// Her biri kullanıcının bildirdiği somut bir şikâyete karşılık geliyor;
/// testler de o şikâyetin diliyle yazıldı.

const Size _phone = Size(420, 900);

Future<void> _pump(WidgetTester tester, Widget screen) async {
  Strings.language = AppLanguage.turkish;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = _phone;
  await tester.pumpWidget(
    KeyedSubtree(key: UniqueKey(), child: MaterialApp(home: screen)),
  );
  await tester.pumpAndSettle();
}

PgnGame _pgnGame(String name, {int skipped = 0}) => PgnGame(
      headers: {'White': name, 'Black': 'Rakip'},
      uciMoves: const ['e2e4', 'e7e5'],
      skippedCount: skipped,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    StorageService.instance.resetCache();
    PuzzleService.instance.resetCache();
    OpeningService.instance.resetCache();
    await SettingsService.instance.load();
  });

  tearDown(() {
    Strings.language = AppLanguage.system;
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  group('Analiz sırası', () {
    // Analiz listesine her kayıt başa ekleniyor. 1., 2., 3. oyunu seçen
    // kullanıcı analiz listesinde de 1., 2., 3. görmeli; bunun için
    // sondan başlamak gerekiyor.
    SavedGame game(String name) => SavedGame(
          name: name,
          uciMoves: const ['e2e4'],
          createdAt: DateTime.now(),
        );

    test('numarası büyük olan önce analiz ediliyor', () {
      final games = [game('Bir'), game('İki'), game('Üç')];
      final numbers = {
        games[0].id: 1,
        games[1].id: 2,
        games[2].id: 3,
      };

      final order = analysisOrder(games, numbers);
      expect(order.map((g) => g.name), ['Üç', 'İki', 'Bir']);
    });

    test('seçim sırası değil, liste numarası belirliyor', () {
      final games = [game('Bir'), game('İki'), game('Üç')];
      final numbers = {
        games[0].id: 7,
        games[1].id: 2,
        games[2].id: 5,
      };

      // Kullanıcının seçme sırası karışık olsun.
      final order = analysisOrder([games[1], games[2], games[0]], numbers);
      expect(order.map((g) => g.name), ['Bir', 'Üç', 'İki']);
    });

    test('kaynak liste değiştirilmiyor', () {
      final games = [game('Bir'), game('İki')];
      final numbers = {games[0].id: 1, games[1].id: 2};

      analysisOrder(games, numbers);
      expect(games.map((g) => g.name), ['Bir', 'İki']);
    });

    test('numarası olmayan oyun sona düşüyor', () {
      final games = [game('Numarasız'), game('Bir')];
      final numbers = {games[1].id: 1};

      expect(
        analysisOrder(games, numbers).map((g) => g.name),
        ['Bir', 'Numarasız'],
      );
    });
  });

  group('PGN alırken eksik hamleli oyunlar', () {
    final games = [
      _pgnGame('Sağlam bir'),
      _pgnGame('Eksik', skipped: 3),
      _pgnGame('Sağlam iki'),
    ];

    testWidgets('süzgeç yalnızca gerektiğinde görünüyor', (tester) async {
      await _pump(
        tester,
        PgnImportScreen(
          games: [_pgnGame('Sağlam')],
          suggestedName: 'Deneme',
        ),
      );
      expect(find.byType(FilterChip), findsNothing);

      await _pump(
        tester,
        PgnImportScreen(games: games, suggestedName: 'Deneme'),
      );
      expect(find.byType(FilterChip), findsOneWidget);
    });

    testWidgets('süzgeç açılınca eksik oyun listeden çıkıyor', (tester) async {
      await _pump(
        tester,
        PgnImportScreen(games: games, suggestedName: 'Deneme'),
      );
      expect(find.text('Eksik - Rakip'), findsOneWidget);

      await tester.tap(find.byType(FilterChip));
      await tester.pumpAndSettle();

      expect(find.text('Eksik - Rakip'), findsNothing);
      expect(find.text('Sağlam bir - Rakip'), findsOneWidget);
      expect(find.text('Sağlam iki - Rakip'), findsOneWidget);
    });

    testWidgets('gizlenen oyun seçimden de düşüyor', (tester) async {
      await _pump(
        tester,
        PgnImportScreen(games: games, suggestedName: 'Deneme'),
      );
      // Başlangıçta hepsi seçili.
      expect(find.textContaining('· 3 seçili'), findsOneWidget);

      await tester.tap(find.byType(FilterChip));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('· 2 seçili'),
        findsOneWidget,
        reason: 'gizlenen oyun kaydedilecek oyunlar arasında kalmamalı',
      );
    });

    testWidgets('süzgeç kapanınca eski seçim geri geliyor', (tester) async {
      await _pump(
        tester,
        PgnImportScreen(games: games, suggestedName: 'Deneme'),
      );
      await tester.tap(find.byType(FilterChip));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilterChip));
      await tester.pumpAndSettle();

      expect(find.textContaining('· 3 seçili'), findsOneWidget);
    });
  });

  group('Motora karşı oyna', () {
    testWidgets('zorluk, oyun başlamadan geri çıkılsa da kalıyor',
        (tester) async {
      final settings = SettingsService.instance;
      final before = settings.engineLevel;
      final target = before == 0 ? 1 : 0;

      await _pump(tester, const HomeScreen());
      await tester.tap(find.text('Motora karşı oyna'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(EngineLevel.all[target].name));
      await tester.pumpAndSettle();

      // Oyun başlatmadan geri çık.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(
        settings.engineLevel,
        target,
        reason: 'zorluk eski hâline döndü; açılış çalışırken '
            'değiştirilemiyor olduğu için burada kalmalı',
      );
    });
  });

  group('Taş takımı', () {
    test('varsayılan Cburnett ve listede birinci', () {
      expect(BoardAssets.pieceSets.first, 'cburnett');
      expect(SettingsService.instance.pieceSet, 'cburnett');
    });

    test('takım listesinde tekrar yok', () {
      expect(
        BoardAssets.pieceSets.toSet().length,
        BoardAssets.pieceSets.length,
      );
    });
  });

  group('Açılışlarda hepsini aç / hepsini kapat', () {
    const text = '''
B90|Sicilian: Najdorf|Main Line|e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6
C00|French|Ana Hat|e4 e6
C00|French|İleri Varyant|e4 e6 d4 d5 e5
''';

    Future<void> seed() => OpeningService.instance.importText(text);

    testWidgets('menüden hepsi açılıyor ve kapanıyor', (tester) async {
      await seed();
      await _pump(tester, const OpeningListScreen());

      // Kapalıyken varyant adları görünmüyor.
      expect(find.text('Main Line'), findsNothing);

      // Başlık çubuğundaki menü: başlık kutularının her birinde de bir
      // üç nokta var.
      final menu = find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(PopupMenuButton<String>),
      );

      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tüm başlıkları aç'));
      await tester.pumpAndSettle();

      expect(find.text('Main Line'), findsOneWidget);
      expect(find.text('Ana Hat'), findsOneWidget);

      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tüm başlıkları kapat'));
      await tester.pumpAndSettle();

      expect(find.text('Main Line'), findsNothing);
      expect(find.text('Ana Hat'), findsNothing);
    });
  });

  group('Yükleme ilerleme çubuğu', () {
    testWidgets('çubuk ince ve kısa değil', (tester) async {
      // PGN ya da açılış alırken çıkan diyalog. Masaüstünde diyalog
      // içeriğine göre daraldığı için çubuk avuç içi kadar kalıyordu.
      late BuildContext screen;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              screen = context;
              return const Scaffold();
            },
          ),
        ),
      );

      final blocker = Completer<void>();
      final running = AppDialogs.runWithProgress<void>(
        screen,
        message: 'Yükleniyor',
        task: (report) async {
          report(0.5);
          await blocker.future;
        },
      );
      await tester.pump();
      await tester.pump();

      final bar = find.byType(LinearProgressIndicator);
      expect(bar, findsOneWidget);
      expect(
        tester.widget<LinearProgressIndicator>(bar).minHeight,
        greaterThanOrEqualTo(10),
        reason: 'çubuk bir çizgi kadar ince',
      );
      expect(
        tester.getSize(bar).width,
        greaterThanOrEqualTo(380),
        reason: 'çubuk diyalogla birlikte daralmış',
      );
      expect(find.text('%50'), findsOneWidget);

      blocker.complete();
      await running;
      await tester.pumpAndSettle();
    });
  });

  group('Tahta ve taş seçici', () {
    Widget harness() => Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showPickerPanel(
                  context,
                  title: 'Seçici',
                  builder: (context, controller, padding) => ListView(
                    controller: controller,
                    padding: padding,
                    children: [
                      for (int i = 0; i < 40; i++)
                        SizedBox(height: 60, child: Text('Satır $i')),
                    ],
                  ),
                ),
                child: const Text('Aç'),
              ),
            ),
          ),
        );

    Future<void> open(WidgetTester tester, Size size) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        KeyedSubtree(key: UniqueKey(), child: MaterialApp(home: harness())),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aç'));
      await tester.pumpAndSettle();
    }

    testWidgets('telefonda alttan yaprak olarak açılıyor', (tester) async {
      await open(tester, _phone);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('masaüstünde ortada panel olarak açılıyor', (tester) async {
      // Alt yaprak geniş pencerede 640 piksele sıkışıp ortalanıyor;
      // dışında kalan yerde fare tekerleği hiçbir şey yapmıyor.
      await open(tester, const Size(1400, 1000));
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('başlık ve kapatma düğmesi var', (tester) async {
      await open(tester, _phone);
      expect(find.text('Seçici'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    });

    testWidgets('aşağıda içerik kaldıkça solma görünüyor', (tester) async {
      await open(tester, _phone);

      final fade = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(AnimatedOpacity),
      );
      expect(
        tester.widget<AnimatedOpacity>(fade).opacity,
        1,
        reason: 'devamı olan listede solma görünmeli',
      );

      await tester.fling(find.text('Satır 0'), const Offset(0, -4000), 4000);
      await tester.pumpAndSettle();

      expect(
        tester.widget<AnimatedOpacity>(fade).opacity,
        0,
        reason: 'sona gelince solma kalkmalı',
      );
    });
  });
}
