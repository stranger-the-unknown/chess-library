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
/// En büyük tahtanın (760) alt şeritli yerleşimde de sığdığı pencere.
const Size _tall = Size(1400, 1300);
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

/// Sağdaki sütun (hamle listesi, motor satırı, gezinme).
final _panel = find.byWidgetPredicate(
  (w) => w is SizedBox && w.width == Layout.sidePanelWidth,
);

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
    // 10.0.4: boyut ayarı burada da geçerli. 10.0.0'da bilerek eski
    // sınırda bırakılmıştı, ama ayar bu yerleşimde de görünüyor ve
    // kaydediliyordu: seçilen Orta/Büyük hiçbir şey yapmıyor, tahta
    // 520'de (yani "Küçük"te) kalıyordu.
    expect(_boardSide(tester), Layout.boardSizes[1],
        reason: 'alt şeritte de seçilen boyut geçerli');
  });

  testWidgets('"Altta" yerleşiminde büyük tahta da seçilebiliyor',
      (tester) async {
    SettingsService.instance.verticalLayout = false;
    SettingsService.instance.boardSize = 2;
    addTearDown(() {
      SettingsService.instance.verticalLayout = true;
      SettingsService.instance.boardSize = 1;
    });

    await _pump(tester, const GameScreen(uciMoves: _moves), _tall);

    // Tam 760 değil: alt şeritli yerleşim `ContentWidth` kullanıyor ve
    // uygulama genelindeki içerik sınırı 760; tahtanın kendi boşluğu
    // düşünce 744 kalıyor. Önemli olan seçimin işe yaraması.
    expect(_boardSide(tester), greaterThan(Layout.boardSizes[1]),
        reason: 'Büyük seçimi Orta boyuttan büyük olmalı');
  });

  testWidgets('tahta ile hamle paneli arasında koca boşluk yok',
      (tester) async {
    // Sol sütun kalan genişliğin tamamını alıyor, tahta da onun ortasına
    // oturuyordu: 1400 piksellik pencerede tahtayla panel arasında ~200
    // piksel boşluk kalıyordu (1920'de ~470).
    await _pump(tester, const GameScreen(uciMoves: _moves), _wide);

    final board = tester.getRect(find.byType(ChessBoardWidget));
    final panel = tester.getRect(_panel);
    final gap = panel.left - board.right;

    expect(gap, greaterThanOrEqualTo(0), reason: 'panel tahtanın sağında');
    expect(gap, lessThan(40), reason: 'aradaki boşluk kapanmalı: $gap');
  });

  testWidgets('panel pencere boyunca uzamıyor', (tester) async {
    // `stretch` yüzünden panel gövdenin tamamını kaplıyordu: tahta ortada
    // yüzerken panelin dibindeki gezinme düğmeleri ekranın en altına
    // iniyordu.
    await _pump(tester, const GameScreen(uciMoves: _moves), _wide);

    final panel = tester.getSize(_panel).height;
    final board = _boardSide(tester);

    expect(panel, lessThan(_wide.height - 150),
        reason: 'panel pencere boyunda kalmamalı: $panel');
    expect(panel, greaterThan(board),
        reason: 'panel tahta sütununu karşılamalı');
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
