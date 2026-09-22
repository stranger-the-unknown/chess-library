import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/models/chess_engine.dart' as engine;
import 'package:chess_pgn_reader/screens/game_screen.dart';
import 'package:chess_pgn_reader/services/engine/engine_service.dart';
import 'package:chess_pgn_reader/services/engine/stockfish_uci.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';

/// Analiz şeridi mat olmayan konumda da çizilebilmeli.
///
/// 10.0.0'da "Mat -3" metni okunur hâle getirilirken kimin mat ettiğini
/// hesaplayan satır, mat **yokken** de çalışıyordu: `mateIn` çoğu konumda
/// `null` ve sıra beyazdayken null denetimi patlıyordu. Motor sonucu
/// gelen her konumda (motor yoksa boş sonuçta bile) tahta ekranı kırmızı
/// hata sayfasına düşüyordu.

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
    StockfishUci.cachedBinaryPath =
        '${Directory.systemTemp.path}/chesslib-yok-sf-analiz';
  });

  tearDown(() async {
    StockfishUci.cachedBinaryPath = null;
    await EngineService.instance.dispose();
  });

  testWidgets('analiz açmak mat olmayan konumda ekranı düşürmüyor',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GameScreen()));
    await tester.pumpAndSettle();

    // Sıra beyazda: hatanın çıktığı taraf.
    await tester.tap(find.byIcon(Icons.insights_rounded));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull,
        reason: 'analiz şeridi mat yokken de çizilebilmeli');
  });

  testWidgets('mat metni kimin mat ettiğini söylüyor', (tester) async {
    // Beyaz mat ediyor: skor satırı "Beyaz mat ediyor (2)" demeli.
    await tester.pumpWidget(const MaterialApp(
      home: GameScreen(startFen: '6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1'),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(GameScreen), findsOneWidget);
    expect(engine.ChessGame.validateFen('6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1'),
        isNull);
  });
}
