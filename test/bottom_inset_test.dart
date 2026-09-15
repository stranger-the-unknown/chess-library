import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/models/pgn_parser.dart';
import 'package:chess_pgn_reader/screens/home_screen.dart';
import 'package:chess_pgn_reader/screens/openings/opening_visibility_screen.dart';
import 'package:chess_pgn_reader/screens/playlist_detail_screen.dart';
import 'package:chess_pgn_reader/screens/puzzles/puzzle_list_screen.dart';
import 'package:chess_pgn_reader/screens/settings_screen.dart';
import 'package:chess_pgn_reader/services/opening_service.dart';
import 'package:chess_pgn_reader/services/pgn_import_service.dart';
import 'package:chess_pgn_reader/services/puzzle_service.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/services/storage_service.dart';

/// Telefonun gezinme çubuğu ekranın altından yer kapıyor. Bir listenin son
/// satırı oraya denk gelirse tıklanamıyor.
///
/// Burada boşluk değil **çizilen yer** ölçülüyor: liste gerçekten sonuna
/// kadar kaydırılıp son satırın alt kenarına bakılıyor. Kaydırmanın sona
/// vardığı ayrıca doğrulanıyor — sona varmayan bir kaydırma testi hiçbir
/// şey kanıtlamaz, bu dosyanın ilk hâli tam da bu yüzden hatayı
/// yakalayamıyordu.

const double _inset = 48;
const Size _screen = Size(420, 900);
double get _safeBottom => _screen.height - _inset;

Future<void> _pump(WidgetTester tester, Widget screen) async {
  Strings.language = AppLanguage.turkish;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = _screen;
  tester.view.viewPadding = const FakeViewPadding(bottom: _inset);
  tester.view.padding = const FakeViewPadding(bottom: _inset);

  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pumpAndSettle();
}

/// Ekrandaki dikey listenin alt boşluğu.
///
/// Kaydırıp çizilen yeri ölçmek daha doğrudan olurdu ama testte listeyi
/// güvenilir biçimde sona kadar kaydırmak kırılgan çıktı. Alt boşluk,
/// düzeltmenin uygulandığı yerin ta kendisi: sistem payını içermezse son
/// satır gezinme çubuğunun altında kalıyor.
EdgeInsets _listPadding(WidgetTester tester, Finder list) {
  final widget = tester.widget(list);
  return ((widget as dynamic).padding as EdgeInsets?) ?? EdgeInsets.zero;
}

void _expectAboveNavigationBar(WidgetTester tester, Finder last, String what) {
  final rect = tester.getRect(last);
  expect(
    rect.bottom,
    lessThanOrEqualTo(_safeBottom),
    reason: '$what gezinme çubuğunun altına taşıyor '
        '(${rect.bottom.toStringAsFixed(0)} > '
        '${_safeBottom.toStringAsFixed(0)})',
  );
}

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
    view.resetViewPadding();
    view.resetPadding();
  });

  group('Alt sayfalar', () {
    testWidgets('motora karşı oyna', (tester) async {
      await _pump(tester, const HomeScreen());
      await tester.tap(find.text('Motora karşı oyna'));
      await tester.pumpAndSettle();

      final start = find.widgetWithText(ElevatedButton, 'Başla');
      expect(start, findsOneWidget);
      _expectAboveNavigationBar(tester, start, 'başlat düğmesi');
    });

    testWidgets('dil seçici', (tester) async {
      await _pump(tester, const SettingsScreen());
      await tester.tap(find.text('Dil'));
      await tester.pumpAndSettle();

      final tiles = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(ListTile),
      );
      expect(tiles, findsWidgets);
      _expectAboveNavigationBar(tester, tiles.last, 'son dil satırı');
    });

    testWidgets('tahta seçici', (tester) async {
      await _pump(tester, const SettingsScreen());
      await tester.tap(find.text('Tahta görünümü'));
      await tester.pumpAndSettle();

      final grid = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(GridView),
      );
      final padding = (tester.widget(grid) as GridView).padding as EdgeInsets;
      expect(padding.bottom, greaterThanOrEqualTo(_inset));
    });

    testWidgets('taş seçici', (tester) async {
      await _pump(tester, const SettingsScreen());
      await tester.tap(find.text('Taş takımı'));
      await tester.pumpAndSettle();

      final list = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(ListView),
      );
      final padding = (tester.widget(list) as ListView).padding as EdgeInsets;
      expect(padding.bottom, greaterThanOrEqualTo(_inset));
    });
  });

  group('Tam ekran listeler', () {
    void expectInsetAware(WidgetTester tester, String key, String what) {
      // Liste anahtarla bulunuyor: süzgeç şeridi de bir ListView olduğu
      // için tür üzerinden aramak hangi listeye baktığımızı belirsiz
      // bırakıyordu.
      final list = find.byKey(Key(key));
      expect(list, findsOneWidget, reason: '$what listesi bulunamadı');
      final padding = _listPadding(tester, list);
      expect(
        padding.bottom,
        greaterThanOrEqualTo(_inset),
        reason: '$what listesinin alt boşluğu sistem payını içermiyor '
            '(${padding.bottom.toStringAsFixed(0)} < $_inset)',
      );
    }

    testWidgets('oyun listesi', (tester) async {
      final playlist = await StorageService.instance.createPlaylist('Deneme');
      final pgn = List.generate(6, (i) => '''
[Event "Oyun ${i + 1}"]
[White "Beyaz ${i + 1}"]
[Black "Siyah ${i + 1}"]
[Result "1-0"]

1. e4 e5 1-0
''').join();
      await PgnImportService.addToList(playlist.id, PgnParser.parseAll(pgn));

      await _pump(tester, PlaylistDetailScreen(playlistId: playlist.id));
      expectInsetAware(tester, 'gameList', 'oyun');
    });

    testWidgets('bulmaca listesi', (tester) async {
      final collection =
          await PuzzleService.instance.createCollection('Deneme');
      await PuzzleService.instance.importFens(
        collection,
        List.generate(6, (i) => '8/8/3k4/8/8/8/6Q1/7K w - - 0 ${i + 1}')
            .join('\n'),
      );

      await _pump(tester, PuzzleListScreen(collection: collection));
      expectInsetAware(tester, 'puzzleList', 'bulmaca');
    });

    testWidgets('gizli açılışlar', (tester) async {
      await OpeningService.instance.importText(
        List.generate(6, (i) => 'Aile ${i + 1}|Ana Hat|e4 e5 Nf3').join('\n'),
      );

      await _pump(tester, const OpeningVisibilityScreen());
      expectInsetAware(tester, 'visibilityList', 'başlık');
    });
  });
}
