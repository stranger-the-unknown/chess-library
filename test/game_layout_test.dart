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
/// Kullanıcının gerçek ekranı: 1920x1080 panel, %125 ölçek.
///
/// Boyut ayarının "çalışıyor gibi görünüp çalışmaması" burada ortaya
/// çıkmıştı: tahtayı sınırlayan şey genişlik değil yükseklik.
const Size _gercek = Size(1536, 816);
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

/// Ayarı değiştirip ekranı **sıfırdan** kurar ve tahtanın kenarını verir.
///
/// Aradaki boş pump şart: aynı `const` ekran yeniden pump edilince
/// Flutter ağacı koruyor ve yeni ayar okunmuyor.
Future<double> _sideFor(WidgetTester tester, int boyut, Size ekran) async {
  SettingsService.instance.boardSize = boyut;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = ekran;
  await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
  await tester.pumpWidget(const MaterialApp(home: GameScreen(uciMoves: _moves)));
  await tester.pumpAndSettle();
  return _boardSide(tester);
}

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
    expect(_boardSide(tester), Layout.maxWideBoardSide * Layout.boardScales[1],
        reason: 'varsayılan boyut Orta');
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
  });

  testWidgets('"Altta" yerleşiminde boyut seçimi tahtayı değiştirmiyor',
      (tester) async {
    // Alt şeritte tahtayı sınırlayan şey seçim değil, altındaki
    // şeritlerden artan yükseklik. Bu yüzden ayar orada gösterilmiyor
    // ve tahta sığdığı kadar büyük kalıyor.
    SettingsService.instance.verticalLayout = false;
    addTearDown(() {
      SettingsService.instance.verticalLayout = true;
      SettingsService.instance.boardSize = 1;
    });

    final kucuk = await _sideFor(tester, 0, _gercek);
    final buyuk = await _sideFor(tester, 2, _gercek);

    expect(kucuk, buyuk, reason: 'alt şeritte seçim tahtayı değiştirmez');
    expect(kucuk, greaterThan(500),
        reason: 'tahta sığdığı kadar büyük kalmalı: $kucuk');
  });

  testWidgets('"Altta" yerleşiminde boyut ayarı gösterilmiyor',
      (tester) async {
    SettingsService.instance.verticalLayout = false;
    addTearDown(() => SettingsService.instance.verticalLayout = true);

    await _pump(tester, const SettingsScreen(), _wide);

    expect(find.text(t('settings.gameLayout')), findsOneWidget,
        reason: 'yerleşim seçimi durmalı');
    expect(find.text(t('settings.boardSize')), findsNothing,
        reason: 'çalışmayan bir ayar gösterilmemeli');
  });

  testWidgets('gerçek ekranda üç boyut da gözle ayrılıyor', (tester) async {
    // Asıl kusur buydu: 1536x816'da mutlak 520/640/760 istendiğinde
    // sonuç 520/640/690 oluyor, yani Orta ile Büyük arasında %8 kalıyor
    // ve seçim gözle ayırt edilmiyordu.
    addTearDown(() => SettingsService.instance.boardSize = 1);

    final kucuk = await _sideFor(tester, 0, _gercek);
    final orta = await _sideFor(tester, 1, _gercek);
    final buyuk = await _sideFor(tester, 2, _gercek);

    expect(orta - kucuk, greaterThan(60),
        reason: 'Küçük -> Orta görünür olmalı: $kucuk -> $orta');
    expect(buyuk - orta, greaterThan(60),
        reason: 'Orta -> Büyük görünür olmalı: $orta -> $buyuk');
    // Büyük, pencerenin verebildiğinin tamamı olmalı: bugünkü 690'dan
    // küçük bir tahta sunmak geriye gidiş olurdu.
    expect(buyuk, greaterThanOrEqualTo(685),
        reason: 'Büyük sığanın tamamını almalı: $buyuk');
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

    expect(_boardSide(tester), Layout.maxWideBoardSide,
        reason: 'geniş pencerede Büyük tavana ulaşır');
  });

  testWidgets('yerleşim ayarları yalnızca geniş pencerede görünüyor',
      (tester) async {
    await _pump(tester, const SettingsScreen(), _narrow);
    expect(find.text(t('settings.gameLayout')), findsNothing,
        reason: 'çalışmayan bir ayar gösterilmemeli');
    expect(find.text(t('settings.boardSize')), findsNothing);

    await _pump(tester, const SettingsScreen(), _wide);
    expect(find.text(t('settings.gameLayout')), findsOneWidget);
    // Varsayılan yerleşim "Yanda": boyut ayarı orada geçerli.
    expect(find.text(t('settings.boardSize')), findsOneWidget);
  });
}
