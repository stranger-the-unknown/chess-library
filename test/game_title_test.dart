import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/models/playlist.dart';
import 'package:chess_pgn_reader/screens/game_screen.dart';
import 'package:chess_pgn_reader/screens/list_game_screen.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/widgets/chess_board_widget.dart';

/// 24 Kasım 2026: listeden ya da PGN'den açılan oyunda oyunun adı üst
/// çubukta yazmıyor (kullanıcının isteği).
///
/// Adı çoğu zaman "Beyaz - Siyah"; telefonda üst çubuğa hiç sığmayıp üç
/// noktaya iniyordu, oyun okurken ve ekran kaydında kötü görünüyordu. İki ad
/// tahtanın yanındaki oyuncu satırlarında zaten tam yazıyor.

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

Future<void> _pump(WidgetTester tester, Widget screen) async {
  // Telefon boyutu: adın sığmadığı yer.
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(412, 915);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pumpAndSettle();
}

Finder _inAppBar(Finder finder) =>
    find.descendant(of: find.byType(AppBar), matching: finder);

const _italian = ['e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1c4', 'f8c5'];
const _white = 'Ian Nepomniachtchi';
const _black = 'Maxime Vachier-Lagrave';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    _silencePlugins();
    SharedPreferences.setMockInitialValues({
      'flutter.soundEnabled': false,
      'flutter.soundDefaultsRestored': true,
    });
    await SettingsService.instance.load();
    Strings.language = AppLanguage.turkish;
  });

  tearDown(() => Strings.language = AppLanguage.system);

  testWidgets('listeden açılan oyunda üst çubukta ad yok, adlar tahtanın '
      'yanında', (tester) async {
    await _pump(
      tester,
      ListGameScreen(
        games: [
          SavedGame(
            name: '$_white - $_black',
            uciMoves: _italian,
            createdAt: DateTime(2026, 11, 24),
            white: _white,
            black: _black,
          ),
        ],
        initialIndex: 0,
      ),
    );
    expect(find.byType(AppBar), findsOneWidget);
    expect(_inAppBar(find.textContaining('Nepomniachtchi')), findsNothing,
        reason: 'oyunun adı üst çubukta yazmıyor');
    expect(_inAppBar(find.byTooltip(t('common.flipBoard'))), findsOneWidget,
        reason: 'düğmeler duruyor');
    expect(find.text(_white), findsOneWidget, reason: 'oyuncu satırında');
    expect(find.text(_black), findsOneWidget, reason: 'oyuncu satırında');
    expect(tester.widget<GameScreen>(find.byType(GameScreen)).title,
        '$_white - $_black',
        reason: 'ad kaydetmede ve kayıt dosyasının adında kullanılıyor');
  });

  // Kullanıcı (24 Kasım 2026): telefonda adlar tahtanın üstünde ve altında
  // kopuk duruyordu; artan boşluk adlarla tahtanın arasına giriyordu.
  // Artık adlar tahtaya bitişik, üçü tek blok olarak ortada.
  testWidgets('telefonda adlar tahtaya bitişik, blok ortada', (tester) async {
    for (final size in const [Size(412, 915), Size(360, 800), Size(412, 1100)]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: ListGameScreen(
          games: [
            SavedGame(
              name: '$_white - $_black',
              uciMoves: _italian,
              createdAt: DateTime(2026, 11, 24),
              white: _white,
              black: _black,
            ),
          ],
          initialIndex: 0,
        ),
      ));
      await tester.pumpAndSettle();
      final board = tester.getRect(find.byType(ChessBoardWidget));
      final top = tester.getRect(find.text(_black));
      final bottom = tester.getRect(find.text(_white));
      expect(board.top - top.bottom, lessThan(24),
          reason: '$size: üstteki ad tahtaya bitişik');
      expect(bottom.top - board.bottom, lessThan(24),
          reason: '$size: alttaki ad tahtaya bitişik');
      expect(board.width, greaterThan(size.width - 24),
          reason: '$size: tahta yine ekranın genişliği kadar');
    }
  });

  // 10.13.0 (inceleme): oyuncu adı olmayan oyunda ad üst çubuktan kalkınca
  // oyunu tanıtan hiçbir şey kalmıyordu; eski "A - B" adlı kayıtlarda da
  // adlar tahtanın yanına gelmiyordu.
  testWidgets('oyuncusu olmayan oyunda ad üst çubukta kalıyor',
      (tester) async {
    await _pump(
      tester,
      ListGameScreen(
        games: [
          SavedGame(
            name: 'Oyun 2026-11-24 10:05',
            uciMoves: _italian,
            createdAt: DateTime(2026, 11, 24),
          ),
        ],
        initialIndex: 0,
      ),
    );
    expect(_inAppBar(find.text('Oyun 2026-11-24 10:05')), findsOneWidget);
  });

  testWidgets('eski "A - B" adlı kayıtta adlar tahtanın yanında',
      (tester) async {
    await _pump(
      tester,
      ListGameScreen(
        games: [
          SavedGame(
            name: 'Capablanca - Alekhine',
            uciMoves: _italian,
            createdAt: DateTime(2026, 11, 24),
          ),
        ],
        initialIndex: 0,
      ),
    );
    expect(find.text('Capablanca'), findsOneWidget);
    expect(find.text('Alekhine'), findsOneWidget);
    expect(_inAppBar(find.textContaining('Capablanca')), findsNothing);
  });

  testWidgets('kısa ekran başlıkları duruyor', (tester) async {
    await _pump(tester, GameScreen(title: t('home.freeBoard')));
    expect(_inAppBar(find.text(t('home.freeBoard'))), findsOneWidget);

    await _pump(tester, const GameScreen(uciMoves: _italian));
    expect(_inAppBar(find.text(t('game.board'))), findsOneWidget);
  });
}
