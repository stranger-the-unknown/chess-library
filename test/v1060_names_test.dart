import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/screens/game_screen.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/widgets/responsive.dart';

/// 10.6.0: oyun ekranında oyuncu adları üç noktaya düşmüyor.
///
/// Ad ile alınan taşlar şeridi satırı yarı yarıya paylaşıyordu (ad
/// `Flexible`, şerit `Expanded`, ikisi de flex 1). Geniş pencerede bile ad
/// satırın en fazla yarısını alabiliyordu: listede tamamı görünen ad oyun
/// ekranına girince kırpılıyordu. Artık önce ad yerleşiyor, şerit kalan
/// yere sığıyor (zaten küçülerek sığabiliyor).

/// Android'in yazı tipi (Roboto) Flutter'ın önbelleğinden.
///
/// Test ortamının varsayılan yazı tipi her harfi kare çiziyor; adlar
/// gerçekte olduğundan çok daha geniş ölçülür ve "telefonda sığıyor mu"
/// sorusu anlamsızlaşır.
Future<void> _loadRoboto() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final dir = '$root/bin/cache/artifacts/material_fonts';
  final loader = FontLoader('Roboto');
  for (final file in ['Roboto-Regular.ttf', 'Roboto-Bold.ttf']) {
    final bytes = File('$dir/$file').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

/// Veri tabanlarından gelen PGN'lerde görülen türden uzun bir ad.
const _uzun = 'Nepomniachtchi, Ian Alexandrovich (RUS)';
const _orta = 'Vachier-Lagrave, Maxime';

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

Future<void> _pump(
  WidgetTester tester,
  Size size, {
  required String white,
  required String black,
  List<String> moves = const ['e2e4', 'e7e5'],
  bool desktop = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(fontFamily: 'Roboto'),
    // Masaüstünde uygulama yazıları %15 büyütüyor (main.dart).
    builder: (context, child) => desktop
        ? MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(Layout.desktopTextScale),
            ),
            child: child!,
          )
        : child!,
    home: GameScreen(
      uciMoves: moves,
      title: 'Oyun',
      initialResult: '1/2-1/2',
      whiteName: white,
      blackName: black,
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Ad kırpıldı mı (üç nokta)?
bool _truncated(WidgetTester tester, String name) =>
    tester.renderObject<RenderParagraph>(find.text(name)).didExceedMaxLines;

/// Çok taş alınmış bir oyun: şerit dolu.
const _takasli = [
  'e2e4', 'd7d5', 'e4d5', 'd8d5', 'b1c3', 'd5a5', 'd2d4', 'c7c6',
  'g1f3', 'g8f6', 'f1c4', 'c8f5', 'c1d2', 'e7e6', 'c3d5', 'a5d8',
  'd5f6', 'd8f6', 'c4d3', 'f5d3', 'c2d3', 'f6d4', 'f3d4',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadRoboto);

  setUp(() async {
    _silencePlugins();
    SharedPreferences.setMockInitialValues({
      'flutter.soundEnabled': false,
      'flutter.soundDefaultsRestored': true,
    });
    await SettingsService.instance.load();
    Strings.language = AppLanguage.turkish;
  });

  tearDown(() {
    Layout.debugDesktopOverride = null;
    Strings.language = AppLanguage.system;
  });

  testWidgets('geniş pencerede uzun adlar tam görünüyor', (tester) async {
    Layout.debugDesktopOverride = true;
    await _pump(tester, const Size(1536, 816),
        white: _uzun, black: _orta, desktop: true);
    expect(_truncated(tester, _uzun), isFalse,
        reason: 'masaüstünde ad kırpılmamalı');
    expect(_truncated(tester, _orta), isFalse);
  });

  testWidgets('geniş pencerede taşlar alınmışken de ad tam', (tester) async {
    Layout.debugDesktopOverride = true;
    await _pump(tester, const Size(1536, 816),
        white: _uzun, black: _orta, moves: _takasli, desktop: true);
    expect(_truncated(tester, _uzun), isFalse);
    expect(_truncated(tester, _orta), isFalse);
  });

  testWidgets('telefonda yaygın uzunlukta ad tam görünüyor', (tester) async {
    Layout.debugDesktopOverride = false;
    await _pump(tester, const Size(412, 915),
        white: _orta, black: 'Carlsen, Magnus', moves: _takasli);
    expect(_truncated(tester, _orta), isFalse,
        reason: 'telefonda "Soyad, Ad" biçimi sığmalı');
  });

  testWidgets('sığmayan ad küçülüyor, en son üç noktaya düşüyor',
      (tester) async {
    // 360 dp'lik telefonda bu ad 15 puntoda sığmıyor: önce punto
    // düşüyor; o da yetmezse kırpılıyor ama satır taşmıyor.
    Layout.debugDesktopOverride = false;
    await _pump(tester, const Size(360, 780), white: _uzun, black: _orta);
    final text = tester.widget<Text>(find.text(_uzun));
    expect(text.style?.fontSize, lessThan(15));
    expect(tester.takeException(), isNull, reason: 'satır taşmamalı');
  });

  testWidgets('alınan taşlar şeridi hâlâ görünüyor', (tester) async {
    Layout.debugDesktopOverride = true;
    await _pump(tester, const Size(1536, 816),
        white: _uzun, black: _orta, moves: _takasli, desktop: true);
    // Şerit adın yanında, sıfır genişliğe inmemiş.
    final strips = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == 'CapturedPieces');
    expect(strips, findsNWidgets(2));
    for (final element in strips.evaluate()) {
      expect((element.renderObject! as RenderBox).size.width,
          greaterThan(60));
    }
  });
}
