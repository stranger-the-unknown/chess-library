import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/models/opening.dart';
import 'package:chess_pgn_reader/models/puzzle.dart';
import 'package:chess_pgn_reader/screens/game_screen.dart';
import 'package:chess_pgn_reader/screens/openings/opening_study_screen.dart';
import 'package:chess_pgn_reader/screens/puzzles/puzzle_solve_screen.dart';
import 'package:chess_pgn_reader/services/engine/engine_service.dart';
import 'package:chess_pgn_reader/services/engine/stockfish_uci.dart';
import 'package:chess_pgn_reader/services/puzzle_service.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/widgets/chess_board_widget.dart';
import 'package:chess_pgn_reader/widgets/responsive.dart';

/// 10.1.0: yan yana yerleşim artık tahtası olan her ekranda.
///
/// Eskiden yalnızca oyun ekranındaydı. Geniş pencerede bulmaca ve açılış
/// ekranları telefon düzeninde kalıyor, tahta 520'de duruyordu.

const Size _wide = Size(1400, 1000);

const _oyun = ['e2e4', 'e7e5', 'g1f3', 'b8c6'];

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

Future<void> _pump(WidgetTester tester, Widget screen, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Masaüstü yazı ölçeğiyle kurar.
///
/// Ölçeği uygulamada `ChessApp`'in `builder`'ı veriyor; testler ekranı
/// doğrudan `MaterialApp` içine koyduğu için o katman devreye girmiyordu.
/// Yani %15 büyümüş yazılarla oluşan bir taşma testlerden sessizce
/// geçerdi — sabit yükseklikli şeritler ve 340 piksellik yan panel
/// düşünülürse en muhtemel taşma yeri tam orası.
Future<void> _pumpScaled(WidgetTester tester, Widget screen, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: const TextScaler.linear(Layout.desktopTextScale),
      ),
      child: child!,
    ),
    home: screen,
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

double _boardSide(WidgetTester tester) =>
    tester.getSize(find.byType(ChessBoardWidget)).width;

final _panel = find.byWidgetPredicate(
  (w) => w is SizedBox && w.width == Layout.sidePanelWidth,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    _silencePlugins();
    SharedPreferences.setMockInitialValues({
      'flutter.soundEnabled': false,
      'flutter.hapticsEnabled': false,
      'flutter.animateMoves': false,
      'flutter.soundDefaultsRestored': true,
    });
    Strings.language = AppLanguage.turkish;
    await SettingsService.instance.load();
    PuzzleService.instance.resetCache();
    StockfishUci.cachedBinaryPath =
        '${Directory.systemTemp.path}/chesslib-yok-sf-1010';
  });

  tearDown(() async {
    StockfishUci.cachedBinaryPath = null;
    await EngineService.instance.dispose();
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views
        .first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  group('tablet ölçütü', () {
    test('telefon tablet sayılmıyor', () {
      expect(Layout.isTabletScreen(const Size(412, 915)), isFalse);
      expect(Layout.isTabletScreen(const Size(480, 1000)), isFalse);
    });

    test('yan panelin sığmadığı küçük tablet de sayılmıyor', () {
      // 7": yatayda 960 piksel, iki sütun için gereken 1100'ün altında.
      // Çevirmek tahtayı büyütmez, küçültürdü.
      expect(Layout.isTabletScreen(const Size(600, 960)), isFalse);
    });

    test('yan panelin sığdığı tablet sayılıyor', () {
      expect(Layout.isTabletScreen(const Size(800, 1280)), isTrue);
      expect(Layout.isTabletScreen(const Size(840, 1344)), isTrue);
      expect(Layout.isTabletScreen(const Size(720, 1152)), isTrue);
    });

    test('4:3 tablet de tablet sayılıyor', () {
      // 9.7": yatay genişliği 1024. Eski 1100 eşiğinde "telefon"
      // sayılıp dikey kilitleniyordu; orada tahta genişliğin %93'ünü
      // kaplıyor, altına her şey sıkışıyordu.
      expect(Layout.isTabletScreen(const Size(768, 1024)), isTrue);
    });
  });

  testWidgets('küçük tablette tahta ekranın tamamını kullanıyor',
      (tester) async {
    // 7" tablet telefon gibi davranıyor (dikey, tek sütun) ama tahtası
    // telefon tavanında kalmamalı: 600 piksellik ekranda 520'de duruyor
    // ve sekizde biri boşa gidiyordu.
    Layout.debugDesktopOverride = false;
    addTearDown(() => Layout.debugDesktopOverride = null);

    await _pump(tester, const GameScreen(uciMoves: _oyun),
        const Size(600, 960));

    expect(_panel, findsNothing, reason: 'küçük tablet tek sütun kalmalı');
    expect(_boardSide(tester), greaterThan(Layout.maxBoardSide),
        reason: 'tahta telefon tavanında kalmamalı');
  });

  testWidgets('telefonda tahta genişlikle sınırlı kalıyor', (tester) async {
    // Tavanın kalkması telefonda bir şey değiştirmemeli: orada tahtayı
    // zaten ekran genişliği sınırlıyor.
    Layout.debugDesktopOverride = false;
    addTearDown(() => Layout.debugDesktopOverride = null);

    await _pump(tester, const GameScreen(uciMoves: _oyun),
        const Size(412, 915));

    expect(_boardSide(tester), lessThan(412),
        reason: 'telefonda tahta ekrandan taşmamalı');
  });

  testWidgets('listeden açılan oyunda tahta küçülmüyor', (tester) async {
    // Oyun listesinden ya da PGN'den açılan tahta da bu ekran. Kayıtlı
    // oyunda sonuç afişi var; afiş tahta sütununda dururken grubun boyu
    // değişken oluyor ve tahta 603 yerine 553 piksele iniyordu. Afişler
    // yan panele taşındı, sütunun boyu artık sabit.
    const ekran = Size(1536, 816);

    await _pump(tester, const GameScreen(uciMoves: _oyun), ekran);
    final sade = _boardSide(tester);

    await _pump(
      tester,
      const GameScreen(
        uciMoves: _oyun,
        title: 'Kayıtlı oyun',
        initialResult: '1-0',
        whiteName: 'Kubilay',
        blackName: 'Rakip',
      ),
      ekran,
    );
    final listeden = _boardSide(tester);

    expect(listeden, sade,
        reason: 'sonuç afişi tahtayı küçültmemeli: $sade -> $listeden');
  });

  testWidgets('masaüstü yazı ölçeğinde hiçbir ekran taşmıyor',
      (tester) async {
    const ekran = Size(1536, 816);

    await _pumpScaled(tester, const GameScreen(uciMoves: _oyun), ekran);
    expect(tester.takeException(), isNull, reason: 'oyun ekranı taşmamalı');

    await _pumpScaled(
      tester,
      PuzzleSolveScreen(
        collection: PuzzleCollection(id: 'c', name: 'Deneme'),
        puzzles: [
          Puzzle(
            id: 'c#0',
            fen: '6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1',
            title: 'Mat',
            solution: const ['a1a8'],
          ),
        ],
        initialIndex: 0,
      ),
      ekran,
    );
    expect(tester.takeException(), isNull, reason: 'bulmaca taşmamalı');

    await _pumpScaled(
      tester,
      OpeningStudyScreen(
        opening: Opening(
          id: 'o1',
          eco: 'B20',
          family: 'Sicilya',
          variation: 'Ana hat',
          uciMoves: const ['e2e4', 'c7c5'],
          sanMoves: const ['e4', 'c5'],
        ),
      ),
      ekran,
    );
    expect(tester.takeException(), isNull, reason: 'açılış taşmamalı');
  });

  testWidgets('bulmaca geniş pencerede iki sütuna ayrılıyor', (tester) async {
    final collection = PuzzleCollection(id: 'c', name: 'Deneme');
    final puzzle = Puzzle(
      id: 'c#0',
      fen: '6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1',
      title: 'Mat',
      solution: ['a1a8'],
    );

    await _pump(
      tester,
      PuzzleSolveScreen(
        collection: collection,
        puzzles: [puzzle],
        initialIndex: 0,
      ),
      _wide,
    );

    expect(_panel, findsOneWidget, reason: 'sağda sütun olmalı');
    expect(_boardSide(tester), greaterThan(Layout.maxBoardSide),
        reason: 'tahta artık telefon sınırında kalmamalı');
  });

  testWidgets('açılış çalışma geniş pencerede iki sütuna ayrılıyor',
      (tester) async {
    final opening = Opening(
      id: 'o1',
      eco: 'B20',
      family: 'Sicilya',
      variation: 'Ana hat',
      uciMoves: const ['e2e4', 'c7c5'],
      sanMoves: const ['e4', 'c5'],
    );

    await _pump(tester, OpeningStudyScreen(opening: opening), _wide);

    expect(_panel, findsOneWidget, reason: 'sağda sütun olmalı');
    expect(_boardSide(tester), greaterThan(Layout.maxBoardSide),
        reason: 'tahta artık telefon sınırında kalmamalı');
  });
}
