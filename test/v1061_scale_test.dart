import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/screens/game_screen.dart';
import 'package:chess_pgn_reader/screens/home_shell.dart';
import 'package:chess_pgn_reader/services/opening_service.dart';
import 'package:chess_pgn_reader/services/puzzle_service.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/services/storage_service.dart';
import 'package:chess_pgn_reader/widgets/chess_board_widget.dart';
import 'package:chess_pgn_reader/widgets/responsive.dart';

/// 10.6.1: Linux'ta bütün arayüz sistemin ölçeği kadar büyüyor.
///
/// Windows aynı ekranı %125'le çiziyor (Flutter'a piksel oranı olarak
/// geliyor); Linux Mint %100'de bırakıp yalnızca yazıları büyütüyor
/// (`text-scaling-factor` 1,2). Uygulama Linux'ta Windows'takinin %80'i
/// boyunda kalıyordu: kartlar dar, yazılar ve simgeler küçük.

/// Kullanıcının bilgisayarındaki pencere (1920×1080, üst panel hariç).
const _window = Size(1920, 1008);

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

/// Uygulamanın kendi `builder`'ıyla, sistem yazı ölçeği [system] iken.
Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  required bool linux,
  double system = 1.2,
}) async {
  Layout.debugDesktopOverride = true;
  Layout.debugLinuxOverride = linux;
  tester.platformDispatcher.textScaleFactorTestValue = system;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = _window;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) => DesktopScale(child: child!),
    home: home,
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Ekranın içinden görülen MediaQuery.
MediaQueryData _inner(WidgetTester tester) =>
    MediaQuery.of(tester.element(find.byKey(const Key('probe'))));

Widget _probe({VoidCallback? onTap}) => Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 100, top: 50),
          child: SizedBox(
            key: const Key('probe'),
            width: 200,
            height: 40,
            child: ElevatedButton(onPressed: onTap, child: const Text('Dokun')),
          ),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    _silencePlugins();
    SharedPreferences.setMockInitialValues({
      'flutter.soundEnabled': false,
      'flutter.soundDefaultsRestored': true,
    });
    StorageService.instance.resetCache();
    PuzzleService.instance.resetCache();
    OpeningService.instance.resetCache();
    await SettingsService.instance.load();
    Strings.language = AppLanguage.turkish;
  });

  tearDown(() {
    Layout.debugDesktopOverride = null;
    Layout.debugLinuxOverride = null;
    Strings.language = AppLanguage.system;
  });

  group('Ölçek kuralı', () {
    tearDown(() {
      Layout.debugDesktopOverride = null;
      Layout.debugLinuxOverride = null;
    });

    test('Linux masaüstünde sistemin ölçeği', () {
      Layout.debugDesktopOverride = true;
      Layout.debugLinuxOverride = true;
      expect(Layout.uiZoom(1.2), 1.2);
      expect(Layout.uiZoom(1.0), 1.0);
    });

    test('sınırlar: 1 ile 2 arası', () {
      Layout.debugDesktopOverride = true;
      Layout.debugLinuxOverride = true;
      expect(Layout.uiZoom(0.8), 1.0,
          reason: 'Windows %100\'ünden küçük çizilmesin');
      expect(Layout.uiZoom(3.0), 2.0);
      expect(Layout.uiZoom(double.nan), 1.0);
    });

    test('Windows\'ta ve telefonda büyütme yok', () {
      Layout.debugDesktopOverride = true;
      Layout.debugLinuxOverride = false;
      expect(Layout.uiZoom(1.2), 1.0,
          reason: 'Windows ölçeği zaten piksel oranı olarak geliyor');
      Layout.debugDesktopOverride = false;
      Layout.debugLinuxOverride = true;
      expect(Layout.uiZoom(1.2), 1.0, reason: 'telefon değişmemeli');
    });
  });

  group('DesktopScale', () {
    testWidgets('Linux: yerleşim küçük pencere gibi, çizim büyük',
        (tester) async {
      var taps = 0;
      await _pump(tester, _probe(onTap: () => taps++), linux: true);

      final inner = _inner(tester);
      expect(inner.size.width, closeTo(_window.width / 1.2, 0.01));
      expect(inner.size.height, closeTo(_window.height / 1.2, 0.01));
      expect(inner.textScaler.scale(10), closeTo(11.5, 0.001),
          reason: 'yazılar arayüze göre Windows\'taki oranda (×1,15)');

      // Kutu 200×40 birim, ekranda 240×48 piksel; yeri de büyümüş.
      final rect = tester.getRect(find.byKey(const Key('probe')));
      expect(rect.width, closeTo(240, 0.01));
      expect(rect.height, closeTo(48, 0.01));
      expect(rect.left, closeTo(120, 0.01));
      expect(rect.top, closeTo(60, 0.01));

      // Dokunma dönüşümden geçip düğmeyi buluyor.
      await tester.tap(find.text('Dokun'));
      expect(taps, 1);
      // Büyümemiş koordinattaki bir dokunuş düğmenin dışında kalıyor.
      await tester.tapAt(const Offset(101, 51));
      expect(taps, 1);
    });

    testWidgets('Windows: yalnızca yazılar büyüyor', (tester) async {
      await _pump(tester, _probe(), linux: false);
      final inner = _inner(tester);
      expect(inner.size, _window);
      expect(inner.textScaler.scale(10), closeTo(11.5, 0.001));
      expect(tester.getRect(find.byKey(const Key('probe'))).width, 200);
    });

    testWidgets('sistem ölçeği 1 ise Linux da değişmiyor', (tester) async {
      await _pump(tester, _probe(), linux: true, system: 1.0);
      expect(_inner(tester).size, _window);
    });

    testWidgets('açılan menü de büyüyor ve seçilebiliyor', (tester) async {
      String? chosen;
      await _pump(
        tester,
        Scaffold(
          appBar: AppBar(actions: [
            PopupMenuButton<String>(
              onSelected: (v) => chosen = v,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'a', child: Text('Birinci')),
                PopupMenuItem(value: 'b', child: Text('İkinci')),
              ],
            ),
          ]),
          body: const SizedBox(key: Key('probe')),
        ),
        linux: true,
      );
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      final item = tester.getRect(find.text('İkinci'));
      expect(item.right, lessThanOrEqualTo(_window.width),
          reason: 'menü pencerenin içinde kalmalı');
      await tester.tap(find.text('İkinci'));
      await tester.pumpAndSettle();
      expect(chosen, 'b');
    });
  });

  group('Gerçek ekranlar (1920×1008, ölçek 1,2)', () {
    testWidgets('ana kabuk taşmadan açılıyor, sekmeler geziliyor',
        (tester) async {
      await _pump(tester, const HomeShell(), linux: true);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final tab in [
        t('nav.puzzles'),
        t('nav.openings'),
        t('nav.lists'),
        t('nav.settings'),
        t('nav.play'),
      ]) {
        await tester.tap(find.text(tab).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$tab sekmesi');
      }
    });

    testWidgets('oyun ekranında tahta büyüyor, yan panel duruyor',
        (tester) async {
      const game = GameScreen(
        uciMoves: ['e2e4', 'e7e5', 'g1f3', 'b8c6'],
        title: 'Oyun',
        whiteName: 'Beyaz Oyuncu',
        blackName: 'Siyah Oyuncu',
      );
      await _pump(tester, game, linux: false);
      final plain = tester.getRect(find.byType(ChessBoardWidget)).width;

      await _pump(tester, game, linux: true);
      expect(tester.takeException(), isNull);
      final zoomed = tester.getRect(find.byType(ChessBoardWidget)).width;
      expect(find.byWidgetPredicate(
        (w) => w is SizedBox && w.width == Layout.sidePanelWidth,
      ), findsOneWidget, reason: 'iki sütunlu yerleşim korunmalı');
      // Tahta yükseklikten sınırlı: pencere yüksekliği 1,2'ye bölünüp
      // çizim 1,2 büyüdüğü için ekrandaki boyu kabaca aynı kalır, ama
      // küçülmemeli.
      expect(zoomed, greaterThanOrEqualTo(plain * 0.95));
    });
  });

  test('Linux başlatıcısı Windows\'taki gibi büyütülmüş açıyor', () {
    // Windows sürümü 2.0.0'dan beri büyütülmüş açılıyor; 10.5.0'da
    // Linux'a taşınırken unutulmuştu (kullanıcı: "oyuna girince ekran
    // büyük oluyordu").
    final runner = File('linux/runner/my_application.cc').readAsStringSync();
    final windows =
        File('windows/runner/win32_window.cpp').readAsStringSync();
    expect(windows, contains('SW_SHOWMAXIMIZED'));
    expect(runner, contains('gtk_window_maximize(window);'));
    // Pencere ilk kare çizilince gösteriliyor (first_frame_cb); büyütme
    // görünüm kurulmadan önce yapılmalı.
    expect(runner.indexOf('gtk_window_maximize(window);'),
        lessThan(runner.indexOf('fl_view_new(project)')),
        reason: 'pencere gösterilmeden önce büyütülmeli');
  });

  test('Linux başlatıcısı pencereyi aynı oranda açıyor', () {
    final runner = File('linux/runner/my_application.cc').readAsStringSync();
    expect(runner, contains('"gtk-xft-dpi"'));
    expect(runner, contains('1180 * zoom'));
    expect(runner, contains('820 * zoom'));
  });
}
