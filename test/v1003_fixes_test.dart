import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/models/chess_engine.dart' as engine;
import 'package:chess_pgn_reader/models/pgn_parser.dart';
import 'package:chess_pgn_reader/models/puzzle.dart';
import 'package:chess_pgn_reader/screens/game_screen.dart';
import 'package:chess_pgn_reader/screens/puzzles/puzzle_solve_screen.dart';
import 'package:chess_pgn_reader/services/engine/engine_service.dart';
import 'package:chess_pgn_reader/services/engine/stockfish_uci.dart';
import 'package:chess_pgn_reader/services/puzzle_service.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/widgets/chess_board_widget.dart';

/// 10.0.3: iptal edilen arama ekranı çıkışsız bırakmamalı.
///
/// Motor tek; her ekran aynı sürece soruyor. Ekran kapanırken
/// `stopAll()` **motordaki her işi** iptal ediyor, yalnızca kendininkini
/// değil. Flutter kapanan ekranı animasyon bitince yok ettiği için bu
/// emir, alttaki ekran çoktan canlıyken geliyor: o ekranın isteği
/// düşüyor. İsteği düşen kod "iptal edildiyse hiçbir şey yapma" diyor ve
/// çıkıyor — ama tahtayı kilitlerken açtığı bayrağı indirmiyordu.

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

engine.Color? _movableSide(WidgetTester tester) {
  return tester
      .widget<ChessBoardWidget>(find.byType(ChessBoardWidget))
      .movableSide;
}

/// Gerçek zamanda bekle: motoru başlatma denemesi gerçek süreç işi.
Future<void> _realDelay(WidgetTester tester, int ms) {
  return tester.runAsync(
    () => Future<void>.delayed(Duration(milliseconds: ms)),
  );
}

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
    // Motor yok: arama boş dönüyor. İptali `stopAll` üretiyor.
    StockfishUci.cachedBinaryPath =
        '${Directory.systemTemp.path}/chesslib-yok-sf-1003';
    // Bu test Stockfish'i sınıyor; varsayılan seviye artık Maia.
    SettingsService.instance.engineLevel = 9; // Uzman
  });

  tearDown(() async {
    StockfishUci.cachedBinaryPath = null;
    await EngineService.instance.dispose();
  });

  testWidgets('başka ekranın iptali motoru sessizce durdurmuyor',
      (tester) async {
    // Kullanıcı siyah: ilk hamle motorun. Arama başlarken başka bir
    // ekranın kapanışı devreye giriyor ve isteği düşürüyor. Eskiden
    // sonuç "iptal" diye sessizce yutuluyordu: motor hiç oynamıyor,
    // uyarı da çıkmıyor, tahta yalnızca siyaha açık olduğu için hiçbir
    // taş tutmuyordu.
    await tester.pumpWidget(MaterialApp(
      home: GameScreen(
        mode: GameMode.versusEngine,
        playerColor: engine.Color.black,
      ),
    ));
    await tester.pump();

    // Kapanan ekranın temizliği: motordaki her iş iptal.
    await EngineService.instance.stopAll();

    await _realDelay(tester, 600);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(_movableSide(tester), isNull,
        reason: 'motor oynamıyorsa tahta kilitli kalmamalı');
  });

  testWidgets('bulmacada iptal edilen ölçüt ekranı kilitli bırakmıyor',
      (tester) async {
    // Çözümü kayıtlı olmayan bulmacada ekran, ölçüt gelene kadar
    // tahtayı, ileri/geri düğmelerini ve "Yeniden"i kapatıyor. Ölçüt
    // isteği düşerse bunların hepsi kapalı kalıyordu: tek çıkış
    // ekrandan çıkmaktı.
    final collection = PuzzleCollection(id: 'c', name: 'Deneme');
    final puzzle = Puzzle(
      id: 'c#0',
      fen: '6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1',
      title: 'Ölçütsüz',
    );

    await tester.pumpWidget(MaterialApp(
      home: PuzzleSolveScreen(
        collection: collection,
        puzzles: [puzzle, puzzle],
        initialIndex: 0,
      ),
    ));
    await tester.pump();

    await EngineService.instance.stopAll();

    await _realDelay(tester, 600);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    // Ekran bir karara varmalı. Eskiden "Motor pozisyonu inceliyor…"
    // yazısı ve dönen çark sonsuza kadar kalıyordu; o hâlde tahta,
    // ileri/geri ve "Yeniden" kapalı olduğu için çıkışsızdı.
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'değerlendirme limbosunda kalmamalı');
    expect(find.text(t('puzzles.analysing')), findsNothing,
        reason: 'ölçüt isteği düştüyse bekleme yazısı kalmamalı');
    expect(find.text(t('puzzles.engineUnavailable')), findsOneWidget,
        reason: 'yargılayamıyorsak bunu söylemeliyiz');

    // İleri/geri artık açık: ekran meşgul değil.
    final next = tester.widget<TextButton>(
      find.ancestor(
        of: find.text(t('common.next')),
        matching: find.byType(TextButton),
      ),
    );
    expect(next.onPressed, isNotNull,
        reason: 'meşgul olmayan ekranda gezinme açık olmalı');
  });

  test('tırnaklı oyuncu adı PGN turunda bozulmuyor', () {
    // Yazan taraf tırnağı `\"` diye kaçırıyor, okuyan taraf bu kuralı
    // bilmiyordu: `"([^"]*)"` deseni kaçırılmış tırnağı bitiş sanıp adı
    // kesiyordu. Kendi dosyamızı kendimiz yanlış okuyorduk.
    const isim = 'Bob "Bobby" Fischer';
    final pgn = PgnParser.buildPgn(
      uciMoves: const ['e2e4', 'e7e5'],
      tags: const {'White': isim, 'Black': r'Ters \ Bolu'},
    );

    final parser = PgnParser();
    expect(parser.parse(pgn), isTrue);
    expect(parser.headers['White'], isim,
        reason: 'tırnaklı ad harfi harfine dönmeli');
    expect(parser.headers['Black'], r'Ters \ Bolu',
        reason: 'ters bölü de aynen dönmeli');
  });
}
