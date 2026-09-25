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
import 'package:chess_pgn_reader/widgets/chess_board_widget.dart';

/// Motor cevap veremezse tahta kilitlenmemeli.
///
/// Motora karşı oyunda tahta yalnızca kullanıcının rengine açıktı.
/// Stockfish bulunamaz ya da boş cevap dönerse sıra motorda kalıyor,
/// kullanıcı hiçbir taşı oynatamıyordu: tek çıkış oyunu yeniden
/// başlatmaktı. Siyah oynayan biri ilk hamleyi sonsuza kadar bekliyordu.

engine.Color? _movableSide(WidgetTester tester) {
  return tester
      .widget<ChessBoardWidget>(find.byType(ChessBoardWidget))
      .movableSide;
}

/// Gerçek eklentiler testte yok.
///
/// Bu dosyada `runAsync` kullanılıyor (motoru başlatma denemesi gerçek
/// zamanda oluyor); o sırada eklenti çağrıları da gerçekten gidiyor ve
/// karşılıksız kalan her biri testi düşürüyor.
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
    _silencePlugins();
    SharedPreferences.setMockInitialValues({
      'flutter.soundEnabled': false,
      'flutter.hapticsEnabled': false,
      'flutter.animateMoves': false,
      // Olmazsa ayarlar sesi bir kereliğine açık hâle getiriyor ve
      // `runAsync` sırasında gerçek ses eklentisi aranıyor.
      'flutter.soundDefaultsRestored': true,
    });
    Strings.language = AppLanguage.turkish;
    await SettingsService.instance.load();
    // Motoru yok say: ikili dosya bulunamayınca sonuç boş geliyor.
    StockfishUci.cachedBinaryPath =
        '${Directory.systemTemp.path}/chesslib-yok-sf';
    // Bu test Stockfish'i sınıyor; varsayılan seviye artık Maia.
    SettingsService.instance.engineLevel = 9; // Uzman
  });

  tearDown(() async {
    StockfishUci.cachedBinaryPath = null;
    await EngineService.instance.dispose();
  });

  testWidgets('motor cevap veremeyince tahta iki tarafa da açılıyor',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: GameScreen(
        mode: GameMode.versusEngine,
        playerColor: engine.Color.black,
      ),
    ));
    await tester.pump();

    // Motor düşünürken tahta hâlâ kullanıcının rengine kilitli.
    expect(_movableSide(tester), engine.Color.black);

    // Motoru başlatma denemesi gerçek zamanda oluyor (dosya yok, süreç
    // açılmıyor); sahte saat bunu beklemiyor.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    // Sonra en az düşünme süresi (500 ms) dolsun.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(_movableSide(tester), isNull,
        reason: 'motor oynayamıyorsa tahta kilitli kalmamalı');
  });

  testWidgets('bozuk FEN ekranı düşürmüyor', (tester) async {
    // Elle düzenlenmiş bir yedekten böyle bir kayıt gelebiliyor;
    // `fromFen` FormatException atıyor ve hata initState içinde olduğu
    // için ekran hiç açılmıyordu.
    await tester.pumpWidget(const MaterialApp(
      home: GameScreen(startFen: 'bu bir fen degil'),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(ChessBoardWidget), findsOneWidget);
    expect(find.text(t('game.fenCorrupt')), findsOneWidget);
  });
}
