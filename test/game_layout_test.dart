import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/screens/game_screen.dart';
import 'package:chess_pgn_reader/screens/settings_screen.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/widgets/chess_board_widget.dart';
import 'package:chess_pgn_reader/widgets/move_list.dart';
import 'package:chess_pgn_reader/widgets/responsive.dart';

/// Masaüstü oyun yerleşimi.
///
/// Geniş pencerede de telefon düzeni kullanılıyordu: tahta 520 pikselde
/// kalıyor, hamleler altta ince bir şeritte yan yana diziliyor, pencerenin
/// iki yanı boş duruyordu.

const Size _wide = Size(1400, 1000);
const Size _narrow = Size(800, 700);

const _moves = ['e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1b5', 'a7a6'];

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
  await tester.pumpAndSettle();
}

double _boardSide(WidgetTester tester) =>
    tester.getSize(find.byType(ChessBoardWidget)).width;

bool _listIsVertical(WidgetTester tester) =>
    tester.widget<MoveList>(find.byType(MoveList)).vertical;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'flutter.soundEnabled': false,
      'flutter.hapticsEnabled': false,
      'flutter.animateMoves': false,
      'flutter.soundDefaultsRestored': true,
    });
    Strings.language = AppLanguage.turkish;
    await SettingsService.instance.load();
    _silencePlugins();
  });

  tearDown(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views
        .first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('geniş pencerede hamle listesi yanda ve tahta büyük',
      (tester) async {
    await _pump(tester, const GameScreen(uciMoves: _moves), _wide);

    expect(_listIsVertical(tester), isTrue,
        reason: 'hamleler tahtanın yanına geçmeli');
    expect(_boardSide(tester), Layout.boardSizes[1],
        reason: 'varsayılan boyut Orta (640)');
  });

  testWidgets('dar pencerede eski yerleşim duruyor', (tester) async {
    await _pump(tester, const GameScreen(uciMoves: _moves), _narrow);

    expect(_listIsVertical(tester), isFalse);
    expect(_boardSide(tester), lessThanOrEqualTo(Layout.maxBoardSide));
  });

  testWidgets('yerleşim "Altta" seçilince geniş pencerede de alt şerit',
      (tester) async {
    SettingsService.instance.verticalLayout = false;
    addTearDown(() => SettingsService.instance.verticalLayout = true);

    await _pump(tester, const GameScreen(uciMoves: _moves), _wide);

    expect(_listIsVertical(tester), isFalse);
    expect(_boardSide(tester), lessThanOrEqualTo(Layout.maxBoardSide),
        reason: 'alt şeritte tahta eski sınırında kalır');
  });

  testWidgets('tahta boyutu ayarı tahtayı büyütüyor', (tester) async {
    SettingsService.instance.boardSize = 2;
    addTearDown(() => SettingsService.instance.boardSize = 1);

    await _pump(tester, const GameScreen(uciMoves: _moves), _wide);

    expect(_boardSide(tester), Layout.boardSizes[2]);
  });

  testWidgets('yerleşim ayarları yalnızca geniş pencerede görünüyor',
      (tester) async {
    await _pump(tester, const SettingsScreen(), _narrow);
    expect(find.text(t('settings.gameLayout')), findsNothing,
        reason: 'çalışmayan bir ayar gösterilmemeli');
    expect(find.text(t('settings.boardSize')), findsNothing);

    await _pump(tester, const SettingsScreen(), _wide);
    expect(find.text(t('settings.gameLayout')), findsOneWidget);
    expect(find.text(t('settings.boardSize')), findsOneWidget);
  });
}
