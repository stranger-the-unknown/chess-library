import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/models/pgn_parser.dart';
import 'package:chess_pgn_reader/screens/home_screen.dart';
import 'package:chess_pgn_reader/screens/openings/opening_list_screen.dart';
import 'package:chess_pgn_reader/models/chess_engine.dart' as engine;
import 'package:chess_pgn_reader/screens/board_editor_screen.dart';
import 'package:chess_pgn_reader/screens/game_screen.dart';
import 'package:chess_pgn_reader/screens/pgn_import_screen.dart';
import 'package:chess_pgn_reader/screens/playlist_detail_screen.dart';
import 'package:chess_pgn_reader/screens/settings_screen.dart';
import 'package:chess_pgn_reader/services/engine/engine_service.dart';
import 'package:chess_pgn_reader/services/opening_service.dart';
import 'package:chess_pgn_reader/services/puzzle_service.dart';
import 'package:chess_pgn_reader/services/pgn_import_service.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/services/sound_service.dart';
import 'package:chess_pgn_reader/services/storage_service.dart';
import 'package:chess_pgn_reader/widgets/app_dialogs.dart';
import 'package:chess_pgn_reader/widgets/piece_widget.dart';
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
      // Başlangıçta yalnızca eksiksiz okunan iki oyun seçili: eksik
      // okunan bir oyun fark edilmeden kaydedilmesin diye (9.0.6).
      expect(find.textContaining('· 2 seçili'), findsOneWidget);

      // Kullanıcı eksik olanı da isterse elle işaretliyor.
      await tester.tap(find.text('Eksik - Rakip'));
      await tester.pumpAndSettle();
      expect(find.textContaining('· 3 seçili'), findsOneWidget);

      await tester.tap(find.byType(FilterChip));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('· 2 seçili'),
        findsOneWidget,
        reason: 'gizlenen oyun kaydedilecek oyunlar arasında kalmamalı',
      );
    });

    testWidgets('süzgeç açıkken yalnızca sağlam oyunlar kaydediliyor',
        (tester) async {
      // Süzgecin asıl işi bu: listeye giden oyunlar.
      await _pump(
        tester,
        PgnImportScreen(games: games, suggestedName: 'Deneme'),
      );
      await tester.tap(find.byType(FilterChip));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Yeni liste'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tamam'));
      await tester.pumpAndSettle();

      final saved = await StorageService.instance.loadPlaylists();
      expect(saved, hasLength(1));
      expect(
        saved.first.games.map((g) => g.name),
        ['Sağlam bir - Rakip', 'Sağlam iki - Rakip'],
        reason: 'eksik hamleli oyun listeye girmemeli',
      );
    });

    testWidgets('süzgeç kapanınca eski seçim geri geliyor', (tester) async {
      await _pump(
        tester,
        PgnImportScreen(games: games, suggestedName: 'Deneme'),
      );
      await tester.tap(find.text('Eksik - Rakip'));
      await tester.pumpAndSettle();
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

  group('Denetim sonrası düzeltmeler', () {
    testWidgets('gizlenen oyunlar yüzünden seçim boşalınca düğmeler kapanıyor',
        (tester) async {
      // Düğmeler `_selected`e bakarken, süzgeç açıkken kaydedilecek bir
      // şey kalmasa da etkin görünüp hiçbir şey yapmıyorlardı.
      await _pump(
        tester,
        PgnImportScreen(
          games: [_pgnGame('Eksik', skipped: 4)],
          suggestedName: 'Deneme',
        ),
      );

      // Eksik okunan oyun kendiliğinden seçili gelmiyor (9.0.6);
      // kullanıcı işaretleyince düğme etkinleşiyor.
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull,
      );
      await tester.tap(find.text('Eksik - Rakip'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNotNull,
      );

      await tester.tap(find.byType(FilterChip));
      await tester.pumpAndSettle();

      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull,
        reason: 'kaydedilecek oyun kalmadı, düğme etkin kalmamalı',
      );
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
    });

    testWidgets('arama açılış başlıklarını kendiliğinden açmıyor',
        (tester) async {
      await OpeningService.instance.importText(
        'C00|French|Ana Hat|e4 e6\n'
        'B90|Sicilian|Najdorf|e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6\n',
      );
      await _pump(tester, const OpeningListScreen());

      // Aranan kelime başlığın kendisi: varyant adı yazılırsa arama
      // kutusundaki metin de eşleşir ve ölçüm anlamsızlaşır.
      await tester.enterText(find.byType(TextField).first, 'Sicilian');
      await tester.pumpAndSettle();

      expect(find.text('French'), findsNothing, reason: 'süzgeç çalışmalı');
      expect(
        find.text('Najdorf'),
        findsNothing,
        reason: 'arama başlığı kendiliğinden açmamalı',
      );
    });

    testWidgets('ses kapalıyken titreşim de verilmiyor', (tester) async {
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call.method);
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      SettingsService.instance.soundEnabled = true;
      SoundService.instance.playMoveSound();
      await tester.pump();
      expect(
        calls.where((m) => m.startsWith('HapticFeedback')),
        isNotEmpty,
        reason: 'ses açıkken titreşim olmalı',
      );

      calls.clear();
      SettingsService.instance.soundEnabled = false;
      SoundService.instance.playMoveSound();
      await tester.pump();
      expect(
        calls.where((m) => m.startsWith('HapticFeedback')),
        isEmpty,
        reason: 'ses kapalıyken telefon titrememeli',
      );

      SettingsService.instance.soundEnabled = true;
    });

    testWidgets("tahta seçicideki kutuların kendi Material'ı var",
        (tester) async {
      await _pump(tester, const SettingsScreen());
      await tester.tap(find.text('Tahta görünümü'));
      await tester.pumpAndSettle();

      final tile = find
          .descendant(
            of: find.byType(GridView),
            matching: find.byType(InkWell),
          )
          .first;
      expect(
        find.ancestor(
          of: tile,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Material &&
                widget.type == MaterialType.transparency &&
                widget.clipBehavior != Clip.none,
          ),
        ),
        findsOneWidget,
        reason: 'kırpan Material yoksa vurgu listenin dışına taşar',
      );
    });

  });

  group('Titreşim ayarı', () {
    tearDown(() => SettingsService.debugVibrationSupported = null);

    test('ses kapanınca titreşim de kapanıyor', () {
      final settings = SettingsService.instance;
      settings.soundEnabled = true;
      settings.vibrationEnabled = true;

      settings.soundEnabled = false;
      expect(settings.vibrationEnabled, isFalse);
    });

    test('ses kapalıyken titreşim açılamıyor', () {
      final settings = SettingsService.instance;
      settings.soundEnabled = false;

      settings.vibrationEnabled = true;
      expect(settings.vibrationEnabled, isFalse);
    });

    test('ses geri açılınca titreşim kendiliğinden açılmıyor', () {
      final settings = SettingsService.instance;
      settings.soundEnabled = true;
      settings.vibrationEnabled = true;

      settings.soundEnabled = false;
      settings.soundEnabled = true;

      expect(
        settings.vibrationEnabled,
        isFalse,
        reason: 'kullanıcı isterse kendisi açar',
      );
    });

    testWidgets('telefonda anahtar var, ses kapalıyken sönük', (tester) async {
      SettingsService.debugVibrationSupported = true;
      await _pump(tester, const SettingsScreen());
      // Ses bölümü listenin altında. Başlığa kadar kaydırılıyor;
      // "Hamle sesleri"ne kadar gidilirse başlık yukarıda kalıyor ve
      // liste onu ağaçtan düşürüyor.
      await tester.scrollUntilVisible(
        find.text('Ses ve titreşim'.toUpperCase()),
        100,
      );
      await tester.pumpAndSettle();

      expect(find.text('Ses ve titreşim'.toUpperCase()), findsOneWidget);
      expect(find.text('Titreşim'), findsOneWidget);
      expect(find.text('Kapalıyken titreşim de verilmez.'), findsOneWidget);

      SwitchListTile vibrationTile() => tester.widget<SwitchListTile>(
            find.ancestor(
              of: find.text('Titreşim'),
              matching: find.byType(SwitchListTile),
            ),
          );
      expect(vibrationTile().onChanged, isNotNull);

      await tester.tap(find.text('Hamle sesleri'));
      await tester.pumpAndSettle();

      expect(
        vibrationTile().onChanged,
        isNull,
        reason: 'ses kapalıyken titreşim anahtarı sönük olmalı',
      );
      expect(vibrationTile().value, isFalse);
    });

    testWidgets("Windows'ta titreşim anahtarı ve açıklaması yok",
        (tester) async {
      SettingsService.debugVibrationSupported = false;
      await _pump(tester, const SettingsScreen());
      await tester.scrollUntilVisible(find.text('Ses'.toUpperCase()), 100);
      await tester.pumpAndSettle();

      expect(find.text('Titreşim'), findsNothing);
      expect(find.text('Kapalıyken titreşim de verilmez.'), findsNothing);
      expect(find.text('Ses ve titreşim'.toUpperCase()), findsNothing);
      expect(find.text('Ses'.toUpperCase()), findsOneWidget);
    });
  });

  group('Konum kurma taş paleti', () {
    testWidgets('silgi taşların sağında ve iki sıranın ortasında',
        (tester) async {
      await _pump(
        tester,
        const BoardEditorScreen(
          initialFen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
        ),
      );

      // Tahtanın kendisi de taş çiziyor; yalnızca paletteki on iki taş.
      final palette = find.ancestor(
        of: find.byIcon(Icons.backspace_outlined),
        matching: find.byType(FittedBox),
      );
      final pieces = find.descendant(
        of: palette,
        matching: find.byType(PieceWidget),
      );
      expect(pieces, findsNWidgets(12));

      await tester.ensureVisible(find.byIcon(Icons.backspace_outlined));
      await tester.pumpAndSettle();

      final white = tester.getCenter(pieces.first);
      final black = tester.getCenter(pieces.at(6));
      final eraser = tester.getCenter(find.byIcon(Icons.backspace_outlined));

      expect(
        eraser.dx,
        greaterThan(tester.getBottomRight(pieces.at(5)).dx),
        reason: 'silgi taşların sağında olmalı',
      );
      expect(
        eraser.dy,
        closeTo((white.dy + black.dy) / 2, 1),
        reason: 'silgi iki sıranın tam ortasında olmalı',
      );
    });

    testWidgets('palet dar telefonda da taşmıyor', (tester) async {
      // Yedi hücre en dar yaygın telefonda (360) kıl payı sığıyor;
      // FittedBox gerekirse küçültüyor. Taşma olsaydı test düşerdi.
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      await tester.pumpWidget(
        KeyedSubtree(
          key: UniqueKey(),
          child: const MaterialApp(
            home: BoardEditorScreen(
              initialFen: '8/8/8/8/8/8/8/K6k w - - 0 1',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final palette = find.ancestor(
        of: find.byIcon(Icons.backspace_outlined),
        matching: find.byType(FittedBox),
      );
      expect(tester.getSize(palette).width, lessThanOrEqualTo(360));
    });

    testWidgets('masaüstünde de silgi sağda ve ortada', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1400, 1000);
      await tester.pumpWidget(
        KeyedSubtree(
          key: UniqueKey(),
          child: const MaterialApp(
            home: BoardEditorScreen(
              initialFen: '8/8/8/8/8/8/8/K6k w - - 0 1',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final palette = find.ancestor(
        of: find.byIcon(Icons.backspace_outlined),
        matching: find.byType(FittedBox),
      );
      final pieces = find.descendant(
        of: palette,
        matching: find.byType(PieceWidget),
      );
      final eraser = tester.getCenter(find.byIcon(Icons.backspace_outlined));

      expect(eraser.dx, greaterThan(tester.getBottomRight(pieces.at(5)).dx));
      expect(
        eraser.dy,
        closeTo(
          (tester.getCenter(pieces.first).dy +
                  tester.getCenter(pieces.at(6)).dy) /
              2,
          1,
        ),
      );
    });
  });

  group('Takılı kalmış ses ayarı', () {
    // Telefonda saklanmış bir `soundEnabled=false` vardı ve Android'in
    // otomatik yedeklemesi onu silip kurmaya rağmen geri getiriyordu.
    test('bir kereliğine varsayılana dönülüyor', () async {
      SharedPreferences.setMockInitialValues({'soundEnabled': false});
      await SettingsService.instance.load();

      expect(SettingsService.instance.soundEnabled, isTrue);
      expect(SettingsService.instance.vibrationEnabled, isTrue);
    });

    test('kullanıcı sonradan kapatırsa kapalı kalıyor', () async {
      SharedPreferences.setMockInitialValues({'soundEnabled': false});
      await SettingsService.instance.load();

      SettingsService.instance.soundEnabled = false;
      await SettingsService.instance.load();

      expect(
        SettingsService.instance.soundEnabled,
        isFalse,
        reason: 'ezme yalnızca bir kez olmalı',
      );
    });
  });

  group('Oyun kartında hizalama', () {
    testWidgets('numara kaç haneli olursa olsun adlar aynı hizada',
        (tester) async {
      // Numara ile beyazın adı aynı satırdaydı, siyahın adı ise sabit
      // girintiyle altındaydı: numara bir hane büyüyünce iki ad
      // birbirinden kayıyordu.
      final playlist = await StorageService.instance.createPlaylist('Hiza');
      final pgn = List.generate(12, (i) => """
[White "Alpha${i + 1}"]
[Black "Beta${i + 1}"]

1. e4 e5 *
""").join();
      await PgnImportService.addToList(playlist.id, PgnParser.parseAll(pgn));

      Strings.language = AppLanguage.turkish;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(500, 1800);
      await tester.pumpWidget(
        KeyedSubtree(
          key: UniqueKey(),
          child: MaterialApp(
            home: PlaylistDetailScreen(playlistId: playlist.id),
          ),
        ),
      );
      await tester.pumpAndSettle();

      double left(String name) => tester.getTopLeft(find.text(name)).dx;

      // Tek haneli ve iki haneli numaralı satırlar.
      expect(left('Alpha1'), left('Beta1'),
          reason: 'aynı satırdaki iki ad hizasız');
      expect(left('Alpha12'), left('Beta12'));
      expect(left('Alpha1'), left('Alpha12'),
          reason: 'numara haneleri satırları kaydırıyor');
    });
  });

  group('"Pes et" yalnızca kendi oyununda', () {
    Future<void> openBoard(WidgetTester tester, GameScreen screen) async {
      Strings.language = AppLanguage.turkish;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(500, 1100);
      await tester.pumpWidget(
        KeyedSubtree(key: UniqueKey(), child: MaterialApp(home: screen)),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byType(PopupMenuButton<String>),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('PGN okurken menüde yok', (tester) async {
      // Başkasının oyununa sonuç yazmaktan başka bir şey yapmıyordu.
      await openBoard(
        tester,
        const GameScreen(uciMoves: ['e2e4', 'e7e5'], title: 'Okunan oyun'),
      );
      expect(find.text('Pes et'), findsNothing);
      expect(find.text('PGN kopyala'), findsOneWidget,
          reason: 'menü gerçekten açılmış olmalı');
    });

    testWidgets('motora karşı oynarken var', (tester) async {
      await openBoard(
        tester,
        const GameScreen(
          mode: GameMode.versusEngine,
          uciMoves: ['e2e4', 'e7e5'],
        ),
      );
      expect(find.text('Pes et'), findsOneWidget);
    });

    testWidgets('hamle oynanmamışken yok', (tester) async {
      await openBoard(
        tester,
        GameScreen(
          startFen: engine.ChessGame().fen,
          title: 'Serbest tahta',
        ),
      );
      // Henüz hamle yok: pes edilecek bir oyun da yok.
      expect(find.text('Pes et'), findsNothing);
    });
  });
}
