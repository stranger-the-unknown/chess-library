import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/models/opening.dart';
import 'package:chess_pgn_reader/screens/game_screen.dart';
import 'package:chess_pgn_reader/screens/openings/opening_list_screen.dart';
import 'package:chess_pgn_reader/screens/openings/opening_order_screen.dart';
import 'package:chess_pgn_reader/screens/openings/opening_study_screen.dart';
import 'package:chess_pgn_reader/services/engine/engine_service.dart';
import 'package:chess_pgn_reader/services/opening_service.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/widgets/chess_board_widget.dart';

/// 10.5.0: açılış ekranları — başlık menüsü (siyah tarafı, en üste taşı),
/// sıralama ekranı, çalışma ekranında motor, siyah tarafı ve geri almada
/// animasyon. Yalnızca tercih deposuyla koşuyor: sahte saatli ekran
/// testlerinde dosya deposunun gerçek disk işlemleri bitmiyor.

final _service = OpeningService.instance;

Future<void> _add(String family, String variation, String moves) =>
    _service.addFromSan(family: family, variation: variation, moveText: moves);

/// Kayıttaki sıra: (aile, varyant) çiftleri.
Future<List<String>> _order() async {
  _service.resetCache();
  return [for (final o in await _service.all()) '${o.family}/${o.variation}'];
}

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

ChessBoardWidget _board(WidgetTester tester) =>
    tester.widget<ChessBoardWidget>(find.byType(ChessBoardWidget));

Future<void> _pumpList(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(700, 1100);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const MaterialApp(home: OpeningListScreen()));
  await tester.pumpAndSettle();
}

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    _silencePlugins();
    SharedPreferences.setMockInitialValues({
      'flutter.soundEnabled': false,
      'flutter.animateMoves': true,
      'flutter.soundDefaultsRestored': true,
    });
    _service.resetCache();
    await SettingsService.instance.load();
    Strings.language = AppLanguage.turkish;
  });

  tearDown(() {
    Strings.language = AppLanguage.system;
    OpeningStudyScreen.debugAnalyze = null;
  });

  group('Başlık menüsü', () {
    testWidgets('"Siyah tarafından çalış" işaretleniyor, kartta görünüyor, '
        'varyant siyahın gözünden açılıyor', (tester) async {
      await _add('Sicilya', 'Najdorf', '1. e4 c5');
      await _pumpList(tester);
      expect(find.text(t('common.black')), findsNothing);

      await _openFamilyMenu(tester, 'Sicilya');
      await tester.tap(find.text(t('openings.blackSide')));
      await tester.pumpAndSettle();
      expect(find.text(t('common.black')), findsOneWidget);
      expect(await _service.blackFamilies(), {'Sicilya'});

      await tester.tap(find.text('Sicilya'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Najdorf'));
      await tester.pumpAndSettle();
      expect(_board(tester).flipped, isTrue);
    });

    testWidgets('"En üste taşı" başlığı başa alıyor', (tester) async {
      await _add('A', 'a1', '1. e4');
      await _add('B', 'b1', '1. d4');
      await _pumpList(tester);
      await _openFamilyMenu(tester, 'B');
      await tester.tap(find.text(t('openings.moveToTop')));
      await tester.pumpAndSettle();
      expect(await _order(), ['B/b1', 'A/a1']);
      expect(
        tester.getTopLeft(find.text('B')).dy,
        lessThan(tester.getTopLeft(find.text('A')).dy),
      );
    });
  });

  group('Sıralama ekranı', () {
    testWidgets('sürükleyerek ve en üste düğmesiyle', (tester) async {
      await _add('A', 'a1', '1. e4');
      await _add('B', 'b1', '1. d4');
      await _add('C', 'c1', '1. c4');
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(600, 900);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const MaterialApp(home: OpeningOrderScreen()),
      );
      await tester.pumpAndSettle();

      // C'yi en üste.
      await tester.tap(find.byTooltip(t('openings.moveToTop')).at(2));
      await tester.pumpAndSettle();
      expect(await _order(), ['C/c1', 'A/a1', 'B/b1']);

      // A'yı (şimdi ikinci) tutamaçtan en alta sürükle.
      final handle = find.byIcon(Icons.drag_handle_rounded).at(1);
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveBy(const Offset(0, 200));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(await _order(), ['C/c1', 'B/b1', 'A/a1']);
    });

    testWidgets('bir başlığın varyantları', (tester) async {
      await _add('A', 'a1', '1. e4');
      await _add('A', 'a2', '1. e4 e5');
      await _add('B', 'b1', '1. d4');
      await tester.pumpWidget(
        const MaterialApp(home: OpeningOrderScreen(family: 'A')),
      );
      await tester.pumpAndSettle();
      expect(find.text('b1'), findsNothing);
      await tester.tap(find.byTooltip(t('openings.moveToTop')).at(1));
      await tester.pumpAndSettle();
      expect(await _order(), ['A/a2', 'A/a1', 'B/b1']);
    });
  });

  group('Çalışma ekranı', () {
    Opening line() => Opening(
          id: 'x',
          eco: 'B90',
          family: 'Sicilya',
          variation: 'Najdorf',
          uciMoves: const ['e2e4', 'c7c5', 'g1f3', 'd7d6'],
          sanMoves: const ['e4', 'c5', 'Nf3', 'd6'],
          custom: true,
        );

    Future<void> pumpStudy(WidgetTester tester,
        {bool blackSide = false}) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(480, 1000);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: OpeningStudyScreen(opening: line(), blackSide: blackSide),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('motor açılıyor ve konumla birlikte güncelleniyor',
        (tester) async {
      final asked = <String>[];
      OpeningStudyScreen.debugAnalyze = (fen) async {
        asked.add(fen);
        return const SearchResult(
          bestMoveUci: 'e2e4',
          scoreCp: 30,
          depth: 14,
          nodes: 1,
          pvUci: ['e2e4', 'e7e5'],
        );
      };
      await pumpStudy(tester);
      await tester.tap(find.byTooltip(t('game.analysisOn')));
      await tester.pumpAndSettle();
      expect(asked, hasLength(1));
      expect(find.textContaining('+0.30'), findsOneWidget);
      expect(find.textContaining('e4 e5'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(asked, hasLength(2), reason: 'yeni konum da sorulmalı');

      await tester.tap(find.byTooltip(t('game.analysisOff')));
      await tester.pumpAndSettle();
      expect(find.textContaining('+0.30'), findsNothing);
    });

    testWidgets('siyah tarafı: tahta çevrili, analiz tahtası da çevrili',
        (tester) async {
      await pumpStudy(tester, blackSide: true);
      expect(_board(tester).flipped, isTrue);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('common.openInAnalysis')));
      await tester.pumpAndSettle();
      expect(find.byType(GameScreen), findsOneWidget);
      expect(_board(tester).flipped, isTrue);
    });

    testWidgets('beyaz tarafı: analiz tahtası çevrilmeden', (tester) async {
      await pumpStudy(tester);
      expect(_board(tester).flipped, isFalse);
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('common.openInAnalysis')));
      await tester.pumpAndSettle();
      expect(_board(tester).flipped, isFalse);
    });

    testWidgets('geri almada animasyon yok, ileride var', (tester) async {
      // Eskiden geri alınca önceki hamle yeniden oynatılıyordu.
      await pumpStudy(tester);
      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pump();
      expect(_board(tester).animateLastMove, isTrue);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.chevron_left_rounded));
      await tester.pump();
      expect(_board(tester).animateLastMove, isFalse);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.last_page_rounded));
      await tester.pump();
      expect(_board(tester).animateLastMove, isFalse,
          reason: 'uzağa atlama da canlanmıyor');
    });
  });
}
