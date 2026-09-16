import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/models/pgn_parser.dart';
import 'package:chess_pgn_reader/screens/board_editor_screen.dart';
import 'package:chess_pgn_reader/screens/pgn_import_screen.dart';
import 'package:chess_pgn_reader/screens/playlist_detail_screen.dart';
import 'package:chess_pgn_reader/screens/settings_screen.dart';
import 'package:chess_pgn_reader/services/opening_service.dart';
import 'package:chess_pgn_reader/services/pgn_import_service.dart';
import 'package:chess_pgn_reader/services/puzzle_service.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/services/storage_service.dart';
import 'package:chess_pgn_reader/theme/app_theme.dart';
import 'package:chess_pgn_reader/widgets/filter_strip.dart';
import 'package:chess_pgn_reader/widgets/responsive.dart';

/// Masaüstü yerleşimi.
///
/// İki ayrı şikâyet, iki ayrı kural:
///
/// * **Süzgeç düğmeleri** geniş pencerede metin kadar dar, her biri başka
///   boyda ve birbirinden kopuk duruyordu. Orada artık eşit genişlikte
///   bir segment şeridi var ve yedi süzgeç bile kaydırma istemiyor.
/// * **Fare tekerleği** imleç pencerenin kenarına yakınken çalışmıyordu:
///   liste `ContentWidth` ile daraltıldığı için kaydırma alanı da
///   daralıyordu. Liste artık tüm genişliği kaplıyor, ortalama listenin
///   kendi dolgusuyla yapılıyor.

/// Geniş pencere.
///
/// Testteki yazı tipi her harfi bir em genişliğinde çiziyor, yani
/// etiketler gerçekte olduğundan çok daha geniş ölçülüyor. Pencere de
/// buna göre geniş tutuldu; ölçülen şey yazı tipi değil, yerleşim kuralı.
const Size _wide = Size(1800, 1000);
const Size _phone = Size(420, 900);

Future<void> _pump(WidgetTester tester, Widget screen, Size size) async {
  Strings.language = AppLanguage.turkish;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  await tester.pumpWidget(
    KeyedSubtree(key: UniqueKey(), child: MaterialApp(home: screen)),
  );
  await tester.pumpAndSettle();
}

const _sevenFilters = [
  'Tümü',
  'Okunmamış',
  'Okunmuş',
  'Favoriler',
  'Beyaz kazanır',
  'Berabere',
  'Siyah kazanır',
];

Widget _strip(List<String> labels) {
  return Scaffold(
    body: FilterStrip(
      options: [
        for (final (i, label) in labels.indexed)
          FilterOption(label: label, selected: i == 0, onTap: () {}),
      ],
    ),
  );
}

List<Size> _chipSizes(WidgetTester tester) {
  final chips = find.descendant(
    of: find.byType(FilterStrip),
    matching: find.byType(InkWell),
  );
  return [
    for (int i = 0; i < tester.widgetList(chips).length; i++)
      tester.getSize(chips.at(i)),
  ];
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
  });

  group('Süzgeç şeridi', () {
    testWidgets('masaüstünde yedi düğme kaydırmasız sığıyor', (tester) async {
      await _pump(tester, _strip(_sevenFilters), _wide);

      expect(
        find.descendant(
          of: find.byType(FilterStrip),
          matching: find.byType(Scrollable),
        ),
        findsNothing,
        reason: 'masaüstünde süzgeçler için kaydırma gerekmemeli',
      );
      expect(_chipSizes(tester), hasLength(7));
    });

    testWidgets('masaüstünde düğmeler eşit genişlikte', (tester) async {
      await _pump(tester, _strip(_sevenFilters), _wide);

      final widths = _chipSizes(tester).map((s) => s.width).toList();
      for (final width in widths) {
        expect(
          width,
          closeTo(widths.first, 0.5),
          reason: 'düğmeler farklı uzunlukta görünüyor',
        );
      }
    });

    testWidgets('masaüstünde düğmeler dar değil', (tester) async {
      await _pump(tester, _strip(_sevenFilters.take(4).toList()), _wide);

      final widths = _chipSizes(tester).map((s) => s.width).toList();
      for (final width in widths) {
        expect(width, greaterThan(100), reason: 'düğmeler hâlâ ufak');
      }
    });

    testWidgets('masaüstünde şerit içerik genişliğinde ortalanıyor',
        (tester) async {
      await _pump(tester, _strip(_sevenFilters.take(4).toList()), _wide);

      final sizes = _chipSizes(tester);
      final chips = find.descendant(
        of: find.byType(FilterStrip),
        matching: find.byType(InkWell),
      );
      final left = tester.getTopLeft(chips.first).dx;
      final right = tester.getTopRight(chips.at(sizes.length - 1)).dx;

      expect(right - left, lessThanOrEqualTo(Layout.maxContentWidth));
      expect(
        (left + right) / 2,
        closeTo(_wide.width / 2, 2),
        reason: 'şerit ortalanmamış',
      );
    });

    testWidgets('telefonda kısa etiketler satırı dolduruyor', (tester) async {
      // İngilizce süzgeçler kısa; doğal genişlikle dizildiklerinde
      // çipler metin kadar daralıp düğmeye benzemekten çıkıyordu.
      // Etiketler kısa tutuldu: testteki yazı tipi harfleri gerçekte
      // olduğundan geniş çiziyor, uzun etiketlerle şerit kaydırmaya
      // düşüyor ve ölçülen şey kural olmaktan çıkıyor.
      await _pump(
        tester,
        _strip(const ['All', 'Unread', 'Read', 'Fav']),
        _phone,
      );

      final widths = _chipSizes(tester).map((s) => s.width).toList();
      expect(widths, hasLength(4));

      final used = widths.fold<double>(0, (sum, w) => sum + w);
      expect(
        used,
        greaterThan(_phone.width * 0.85),
        reason: 'çipler satırın çoğunu kaplamalı',
      );
      expect(
        widths.reduce((a, b) => a < b ? a : b),
        greaterThan(_phone.width / 8),
        reason: 'kısa etiketli çip metin kadar dar kalmamalı',
      );
    });

    testWidgets('telefonda eski davranış duruyor', (tester) async {
      // Sığan süzgeçler: sabit satır, kaydırma yok. Etiketler kısa
      // seçildi; testteki yazı tipi gerçek genişlikleri temsil etmiyor,
      // ölçülen şey "sığıyorsa satır" kuralı.
      await _pump(tester, _strip(const ['Tümü', 'Yeni']), _phone);
      expect(
        find.descendant(
          of: find.byType(FilterStrip),
          matching: find.byType(Scrollable),
        ),
        findsNothing,
      );

      // Sığmayanlar: eskisi gibi kaydırmalı şerit.
      await _pump(tester, _strip(_sevenFilters), _phone);
      expect(
        find.descendant(
          of: find.byType(FilterStrip),
          matching: find.byType(Scrollable),
        ),
        findsOneWidget,
      );
    });
  });

  group('Fare tekerleği için kaydırma alanı', () {
    /// Listenin kaydırma alanı ile içeriğinin genişliği.
    (double area, double content) measure(WidgetTester tester, Finder list) {
      final area = tester.getSize(list).width;
      final padding = (tester.widget(list) as dynamic).padding as EdgeInsets;
      return (area, area - padding.horizontal);
    }

    testWidgets('ayarlar listesi pencere kadar geniş', (tester) async {
      await _pump(tester, const SettingsScreen(), _wide);

      final list = find.byType(ListView).first;
      final (area, content) = measure(tester, list);

      expect(
        area,
        _wide.width,
        reason: 'kaydırma alanı dar; imleç kenardayken tekerlek çalışmaz',
      );
      expect(
        content,
        lessThanOrEqualTo(Layout.maxContentWidth),
        reason: 'içerik yine de ortada ve sınırlı kalmalı',
      );
    });

    testWidgets('oyun listesi pencere kadar geniş', (tester) async {
      final playlist = await StorageService.instance.createPlaylist('Deneme');
      final pgn = List.generate(6, (i) => '''
[Event "Oyun ${i + 1}"]
[White "Beyaz ${i + 1}"]
[Black "Siyah ${i + 1}"]
[Result "1-0"]

1. e4 e5 1-0
''').join();
      await PgnImportService.addToList(playlist.id, PgnParser.parseAll(pgn));

      await _pump(tester, PlaylistDetailScreen(playlistId: playlist.id), _wide);

      final list = find.byKey(const Key('gameList'));
      final (area, content) = measure(tester, list);

      expect(area, _wide.width);
      expect(content, lessThanOrEqualTo(Layout.maxContentWidth));
    });

    testWidgets('PGN alma listesi pencere kadar geniş', (tester) async {
      // Denetimde atlanmış olduğu görüldü: uzun oyun listesi tam da
      // kaydırma gereken ekran.
      await _pump(
        tester,
        PgnImportScreen(
          games: [
            for (int i = 0; i < 12; i++)
              PgnGame(
                headers: {'White': 'Beyaz $i', 'Black': 'Siyah $i'},
                uciMoves: const ['e2e4', 'e7e5'],
              ),
          ],
          suggestedName: 'Deneme',
        ),
        _wide,
      );

      final list = find.byKey(const Key('pgnGameList'));
      final (area, content) = measure(tester, list);
      expect(area, _wide.width);
      expect(content, lessThanOrEqualTo(Layout.maxContentWidth));
    });

    testWidgets('tahta düzenleyici pencere kadar geniş', (tester) async {
      await _pump(
        tester,
        const BoardEditorScreen(
          initialFen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
        ),
        _wide,
      );

      final list = find.byType(ListView).first;
      final (area, content) = measure(tester, list);
      expect(area, _wide.width);
      expect(content, lessThanOrEqualTo(Layout.maxContentWidth));
    });

    testWidgets('arama kutusu içerik genişliğini aşmıyor', (tester) async {
      final playlist = await StorageService.instance.createPlaylist('Deneme');
      await PgnImportService.addToList(
        playlist.id,
        PgnParser.parseAll('''
[White "Beyaz"]
[Black "Siyah"]

1. e4 e5 *
'''),
      );

      await _pump(tester, PlaylistDetailScreen(playlistId: playlist.id), _wide);

      final field = find.byType(TextField);
      expect(field, findsOneWidget);
      expect(
        tester.getSize(field).width,
        lessThanOrEqualTo(Layout.maxContentWidth),
        reason: 'arama kutusu tek başına pencereye yapışık kalmamalı',
      );
    });

    testWidgets('telefonda dolgu büyümüyor', (tester) async {
      await _pump(tester, const SettingsScreen(), _phone);

      final list = find.byType(ListView).first;
      final padding = (tester.widget(list) as ListView).padding as EdgeInsets;
      expect(padding.left, 16);
      expect(padding.right, 16);
    });
  });

  group('Etiketler sığıyor mu', () {
    /// Oyun sonu listesindeki yedi süzgeç, uygulamanın kendi temasıyla ve
    /// **başlık çubuğunun içinde**.
    ///
    /// Bağlam önemli: `Text`, biçemi üstteki `DefaultTextStyle` ile
    /// birleştiriyor ve oradan gelen harf aralığı (0.3 piksel) ölçüme
    /// girmiyordu. Çıplak bir `Scaffold` gövdesinde bu fark görünmez;
    /// hata da tam burada ortaya çıkmıştı.
    const endgame = [
      'Tümü',
      'Çözülmemiş',
      'Çözülmüş',
      'Favoriler',
      'Beyaz kazanır',
      'Berabere',
      'Siyah kazanır',
    ];

    Future<void> pumpInAppBar(WidgetTester tester, Size size) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        KeyedSubtree(
          key: UniqueKey(),
          child: MaterialApp(
            theme: AppTheme.dark,
            home: Scaffold(
              appBar: AppBar(
                title: const Text('Oyun sonu'),
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(44),
                  child: FilterStrip(
                    options: [
                      for (final (i, label) in endgame.indexed)
                        FilterOption(
                          label: label,
                          selected: i == 0,
                          onTap: () {},
                        ),
                    ],
                  ),
                ),
              ),
              body: const SizedBox(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// Kurulmuş olan çiplerin metnini denetler; kaç tanesine baktığını
    /// döndürür. Kaydırmalı şeritte görünmeyen çipler kurulmuyor.
    int expectNoEllipsis(WidgetTester tester) {
      var checked = 0;
      for (final label in endgame) {
        final finder = find.text(label);
        if (finder.evaluate().isEmpty) continue;
        final paragraph = tester.renderObject<RenderParagraph>(finder);
        expect(
          paragraph.didExceedMaxLines,
          isFalse,
          reason: '"$label" çipe sığmıyor, üç noktaya düşüyor',
        );
        checked++;
      }
      return checked;
    }

    testWidgets('arama kutusu süzgeç şeridinden uzun', (tester) async {
      // Yedi süzgeçli oyun sonu listesinde şerit içerik genişliğini
      // aşıyor; kutu sabit kalınca ondan kısa görünüyordu.
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = _wide;
      await tester.pumpWidget(
        KeyedSubtree(
          key: UniqueKey(),
          child: MaterialApp(
            theme: AppTheme.dark,
            home: Scaffold(
              appBar: AppBar(
                title: const Text('Oyun sonu'),
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(104),
                  child: ListToolbar(
                    search: const Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: TextField(),
                    ),
                    options: [
                      for (final (i, label) in endgame.indexed)
                        FilterOption(
                          label: label,
                          selected: i == 0,
                          onTap: () {},
                        ),
                    ],
                  ),
                ),
              ),
              body: const SizedBox(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final chips = find.descendant(
        of: find.byType(FilterStrip),
        matching: find.byType(InkWell),
      );
      final strip = tester.getTopRight(chips.at(endgame.length - 1)).dx -
          tester.getTopLeft(chips.first).dx;
      final search = tester.getSize(find.byType(TextField)).width;

      expect(
        search,
        greaterThan(strip),
        reason: 'arama kutusu şeritten kısa kalmamalı',
      );
    });

    testWidgets('masaüstünde uzun etiketler üç noktaya düşmüyor',
        (tester) async {
      await pumpInAppBar(tester, _wide);
      expect(
        expectNoEllipsis(tester),
        endgame.length,
        reason: 'masaüstünde yedisi de görünür olmalı',
      );
    });

    testWidgets('telefonda da düşmüyor', (tester) async {
      await pumpInAppBar(tester, _phone);
      expect(expectNoEllipsis(tester), greaterThan(2));
    });
  });
}
