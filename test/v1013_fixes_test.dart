import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:async' show Completer;
import 'dart:io';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/main.dart';
import 'package:chess_pgn_reader/services/backup_service.dart';
import 'package:chess_pgn_reader/services/prefs_recovery.dart';
import 'package:chess_pgn_reader/services/unsaved_work.dart';
import 'package:chess_pgn_reader/widgets/chess_board_widget.dart';
import 'package:chess_pgn_reader/models/chess_engine.dart' as engine;
import 'package:chess_pgn_reader/models/move_entry.dart';
import 'package:chess_pgn_reader/models/pgn_parser.dart';
import 'package:chess_pgn_reader/models/repetition.dart';
import 'package:chess_pgn_reader/screens/game_screen.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';

/// 10.1.3: 10.1.2 denetiminin birinci aşaması.

engine.ChessMove _move(engine.ChessGame game, String uci) {
  final move = game.moveFromUci(uci);
  if (move == null) throw StateError('yasadışı: $uci');
  return move;
}

void main() {
  group('B-8 üç tekrar: geçerken alma yalnızca mümkünse sayılıyor', () {
    test('çift kare sürüşten sonraki konum tekrarlardan ayrı sayılmıyor', () {
      // FIDE 9.2: 1...e5 sonrası e6 hedef karesi yazılıyor ama onu
      // alabilecek beyaz piyon yok; konum 3...Ng8 ve 5...Ng8 sonrasındakiyle
      // aynı. Eskiden sayım 2 çıkıyordu.
      final game = engine.ChessGame();
      final fens = <String>[game.fen];
      for (final uci in [
        'e2e4', 'e7e5', 'g1f3', 'g8f6', 'f3g1', 'f6g8',
        'g1f3', 'g8f6', 'f3g1', 'f6g8',
      ]) {
        game.makeMove(_move(game, uci));
        fens.add(game.fen);
      }

      expect(repetitionCount(fens, game.fen), 3);
      expect(isThreefold(fens, game.fen), isTrue);
    });

    test('gerçekten alınabilen geçerken alma konumu ayırıyor', () {
      // e5'teki beyaz piyon d6'yı alabilir: hedef kare anahtarda kalmalı.
      const alinabilir =
          'rnbqkb1r/ppp1pppp/5n2/3pP3/8/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 3';
      expect(positionKey(alinabilir).split(' ').last, 'd6');
    });

    test('açmazdaki piyonun geçerken alması sayılmıyor', () {
      // b5xc6 e.p. a5-h5 hattını açar: yasadışı, anahtarda kalmamalı.
      const acmaz = '8/8/8/KPp4r/8/8/8/7k w - c6 0 2';
      expect(positionKey(acmaz).split(' ').last, '-');
    });
  });

  group('B-9 FEN: tahtayla tutarsız geçerken alma karesi düşürülüyor', () {
    test('arkasında piyon olmayan kare yasadışı hamle üretmiyor', () {
      // e5'te siyah piyon yok; eskiden d5-e6 "alma"sı üretiliyordu.
      final game = engine.ChessGame.fromFen('4k3/8/8/3P4/8/8/8/4K3 w - e6 0 1');
      final ucis = game.allLegalMoves().map((m) => m.uci).toList();

      expect(ucis, isNot(contains('d5e6')));
      expect(game.fen.split(' ')[3], '-');
    });

    test('tutarlı kare korunuyor', () {
      final game = engine.ChessGame.fromFen(
        'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1',
      );
      expect(game.fen.split(' ')[3], 'e3');
    });

    test('yanlış sıradaki kare düşürülüyor', () {
      // Beyaz oynarken hedef kare 6. sırada olmalı.
      final game = engine.ChessGame.fromFen(
        '4k3/8/8/8/8/3p4/4P3/4K3 w - e4 0 1',
      );
      expect(game.fen.split(' ')[3], '-');
    });

    test('sayaçlar sınırlanıyor', () {
      final game = engine.ChessGame.fromFen('4k3/8/8/8/8/8/8/4K3 w - - -5 0');
      final parts = game.fen.split(' ');
      expect(parts[4], '0', reason: 'yarım hamle sayacı negatif olamaz');
      expect(parts[5], '1', reason: 'hamle numarası 1\'den başlar');
    });
  });

  test('B-16 yasadışı hamle kaydı üretmiyor, açıkça reddediliyor', () {
    // Eskiden yalnızca `assert` vardı: sürüm derlemesinde kalkıyor ve
    // geçmiş ile tahta sessizce ayrışıyordu.
    final game = engine.ChessGame();
    final illegal = engine.ChessMove(
      from: engine.Position.fromAlgebraic('e2'),
      to: engine.Position.fromAlgebraic('e5'),
    );
    final before = game.fen;

    expect(() => MoveEntry.play(game, illegal), throwsStateError);
    expect(game.fen, before, reason: 'tahta değişmemeli');
  });

  group('B-10 PGN: kapanmamış yorum ya da varyant sessiz kalmıyor', () {
    test('kapanmamış süslü parantez işaretleniyor', () {
      // Eskiden `{` sonrası her şey yorum sayılıyor, oyun 1 hamleyle ve
      // hiçbir uyarı olmadan geliyordu.
      final games = PgnParser.parseAll('1. e4 { hiç kapanmıyor e5 2. Nf3 *');
      expect(games, hasLength(1));
      expect(games.first.unclosed, isTrue);
      expect(games.first.isClean, isFalse,
          reason: 'çoklu içe aktarmada işaretsiz gelmeli');
    });

    test('kapanmamış varyant işaretleniyor', () {
      final games = PgnParser.parseAll('1. e4 (1. d4 d5 e5 2. Nf3 *');
      expect(games.first.unclosed, isTrue);
    });

    test('iç içe ama kapanmış yorum ve varyant temiz', () {
      final games = PgnParser.parseAll(
        '1. e4 {a {b} c} (1. d4 (1. c4) d5) e5 2. Nf3 {[%clk 0:03:00]} *',
      );
      expect(games.first.unclosed, isFalse);
      expect(games.first.isClean, isTrue);
    });
  });

  group('B-11 PGN: desteklenmeyen varyant açıkça bildiriliyor', () {
    const chess960 = '[Variant "Chess960"]\n[SetUp "1"]\n'
        '[FEN "bqnrkrnb/pppppppp/8/8/8/8/PPPPPPPP/BQNRKRNB w KQkq - 0 1"]'
        '\n\n1. O-O *\n\n';
    const standard = '[Event "normal"]\n\n1. e4 e5 *\n\n';

    test('Chess960 oyunları sayılıyor ve alınmıyor', () {
      var skipped = 0;
      final games = PgnParser.parseAll(
        '$chess960$standard',
        onSkippedVariants: (count) => skipped = count,
      );
      expect(games, hasLength(1), reason: 'standart oyun gelmeli');
      expect(skipped, 1, reason: 'varyant oyunu sayılmalı');
    });

    test('"Standard" varyant başlığı normal oyun sayılıyor', () {
      var skipped = 0;
      final games = PgnParser.parseAll(
        '[Variant "Standard"]\n\n1. e4 e5 *',
        onSkippedVariants: (count) => skipped = count,
      );
      expect(games, hasLength(1));
      expect(skipped, 0);
    });
  });

  testWidgets('tek oyunluk PGN uyarısı tahta ekranına ulaşıyor',
      (tester) async {
    // Ana ekrandan tek oyunluk dosya doğrudan tahtaya gidiyordu ve atlanan
    // hamle, okunamayan FEN ya da kapanmamış yorum hiç söylenmiyordu.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dev.fluttercommunity.plus/wakelock'),
            (c) async => null);
    SharedPreferences.setMockInitialValues({
      'flutter.soundEnabled': false,
      'flutter.soundDefaultsRestored': true,
    });
    Strings.language = AppLanguage.turkish;
    await SettingsService.instance.load();

    final game = PgnParser.parseAll('1. e4 { kapanmıyor e5 *').single;
    expect(game.warningText, isNotNull);

    await tester.pumpWidget(MaterialApp(
      home: GameScreen(
        uciMoves: game.uciMoves,
        initialWarning: game.warningText,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining(t('pgn.unclosed')), findsOneWidget);
  });

  group('B-1 bozuk tercih dosyası uygulamayı açılmaz bırakmıyor', () {
    // Windows eklentisi dosyayı her yazmada baştan ve atomik olmadan
    // yazıyor, okurken de bozuk JSON'u yakalamıyor. Yazma yarıda kalırsa
    // `SharedPreferences.getInstance` hata veriyor ve `runApp`'e hiç
    // ulaşılmıyordu. Artık dosya kenara alınıp boş başlanıyor.
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('tercih_kurtarma');
    });
    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    File prefs() => File('${dir.path}${Platform.pathSeparator}'
        'shared_preferences.json');

    test('yarım JSON kenara alınıyor, içeriği korunuyor', () async {
      const yarim = '{"flutter.playlists_v2":"[{\\"id\\":\\"a\\"';
      prefs().writeAsStringSync(yarim);

      final moved = await PrefsRecovery.quarantineIfCorrupt(prefs());

      expect(moved, isNotNull);
      expect(prefs().existsSync(), isFalse,
          reason: 'eklenti bir sonraki okumada boş başlamalı');
      expect(File(moved!).readAsStringSync(), yarim,
          reason: 'elle kurtarılabilsin diye içerik aynen saklanmalı');
    });

    test('sağlam dosyaya dokunulmuyor', () async {
      prefs().writeAsStringSync('{"flutter.a":"b"}');
      expect(await PrefsRecovery.quarantineIfCorrupt(prefs()), isNull);
      expect(prefs().existsSync(), isTrue,
          reason: 'hata başka bir sebepten; sağlam veri kenara alınmamalı');
    });

    test('boş ya da olmayan dosyada bir şey yapılmıyor', () async {
      expect(await PrefsRecovery.quarantineIfCorrupt(prefs()), isNull);
      prefs().writeAsStringSync('');
      expect(await PrefsRecovery.quarantineIfCorrupt(prefs()), isNull);
      expect(prefs().existsSync(), isTrue);
    });
  });

  group('B-6 Windows: kaydedilmemiş oyunla pencere kapatılırken soruluyor', () {
    setUp(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('dev.fluttercommunity.plus/wakelock'),
              (c) async => null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('com.ryanheise.just_audio.methods'),
              (c) async => null);
      SharedPreferences.setMockInitialValues({
        'flutter.soundEnabled': false,
        'flutter.soundDefaultsRestored': true,
        'flutter.animateMoves': false,
      });
      Strings.language = AppLanguage.turkish;
      await SettingsService.instance.load();
    });

    Future<void> openBoardWithMove(WidgetTester tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(420, 900);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const ChessApp());
      await tester.pumpAndSettle();
      tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .push(MaterialPageRoute(builder: (_) => const GameScreen()));
      await tester.pumpAndSettle();
      final board = tester.getRect(find.byType(ChessBoardWidget));
      final s = board.width / 8;
      Offset at(String sq) => Offset(
            board.left + ('abcdefgh'.indexOf(sq[0]) + 0.5) * s,
            board.top + (8 - int.parse(sq[1]) + 0.5) * s,
          );
      await tester.tapAt(at('e2'));
      await tester.pump();
      await tester.tapAt(at('e4'));
      await tester.pumpAndSettle();
    }

    // Runner'ın yaptığı gibi kanaldan "pencere kapanabilir mi?" diye sorar.
    // (Flutter'ın kendi çıkış isteği bu uygulamada Windows'ta hiç gelmiyor:
    // motor onu ses eklentisinin gizli pencereleri yüzünden iletmiyor.)
    Future<bool?> requestClose() {
      const codec = StandardMethodCodec();
      final reply = Completer<bool?>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        'chess_library/window',
        codec.encodeMethodCall(const MethodCall('requestClose')),
        (data) => reply.complete(
            data == null ? null : codec.decodeEnvelope(data) as bool?),
      );
      return reply.future;
    }

    testWidgets('kaydedilmemiş hamle varsa onay isteniyor, vazgeçilebiliyor',
        (tester) async {
      await openBoardWithMove(tester);
      expect(UnsavedWork.any, isTrue, reason: 'oyun ekranı kendini bildirmeli');

      final response = requestClose();
      await tester.pumpAndSettle();
      expect(find.text(t('game.exitTitle')), findsOneWidget,
          reason: 'pencere kapatılırken onay sorulmalı');

      await tester.tap(find.text(t('common.giveUp')));
      await tester.pumpAndSettle();
      expect(await response, isFalse, reason: 'pencere açık kalmalı');
    });

    testWidgets('onaylanınca pencere kapanıyor', (tester) async {
      await openBoardWithMove(tester);
      final response = requestClose();
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('game.exitConfirm')));
      await tester.pumpAndSettle();
      expect(await response, isTrue);
    });

    testWidgets('kaydedilmemiş iş yoksa sormadan çıkılıyor', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(420, 900);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const ChessApp());
      await tester.pumpAndSettle();

      expect(UnsavedWork.any, isFalse);
      final response = requestClose();
      await tester.pump();
      expect(await response, isTrue);
    });
  });

  group('B-5 geri yükleme yarıda kalırsa veri tutarlı kalıyor', () {
    late Directory dir;
    late Future<Directory> Function() originalDirectory;
    // Açılıştan sonraki gerçek depo (ayar varsayılanları da yazılıyor).
    late Map<String, Object?> before;

    // Cihazdaki veri: yedekte olmayan anahtarlar da var.
    const old = <String, Object>{
      'playlists_v2': 'eski-listeler',
      'puzzle_progress_v1': 'eski-ilerleme',
      'openings_notes_v1': 'eski-notlar',
      'analysis_lists_v1': 'yerel-analiz',
    };
    // Yedekteki veri.
    const incoming = <String, Object?>{
      'playlists_v2': 'yeni-listeler',
      'openings_custom_v1': 'yeni-acilislar',
      'x_sayi': 7,
    };

    File snapshot() => File('${dir.path}${Platform.pathSeparator}'
        'restore-snapshot.json');

    Future<Map<String, Object?>> stored() async {
      final prefs = await SharedPreferences.getInstance();
      return {for (final key in prefs.getKeys()) key: prefs.get(key)};
    }

    setUpAll(() => originalDirectory = BackupService.snapshotDirectory);

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('cl_v1013_b5_');
      BackupService.snapshotDirectory = () async => dir;
      SharedPreferences.setMockInitialValues(
          {for (final e in old.entries) 'flutter.${e.key}': e.value});
      await SettingsService.instance.load();
      before = await stored();
      expect(before, containsPair('puzzle_progress_v1', 'eski-ilerleme'));
    });

    tearDown(() async {
      BackupService.debugAfterWrite = null;
      BackupService.snapshotDirectory = originalDirectory;
      await dir.delete(recursive: true);
    });

    test('Değiştir kipi yarıda kesilince eski veri silinmemiş, açılışta geri dönülüyor',
        () async {
      final frozen = Completer<void>();
      BackupService.debugAfterWrite = (written) {
        if (written < 1) return Future.value();
        if (!frozen.isCompleted) frozen.complete();
        // Süreç tam burada öldü: geri yükleme hiç devam etmiyor.
        return Completer<void>().future;
      };
      unawaited(BackupService.instance.apply(incoming));
      await frozen.future;

      // Eskiden önce bütün anahtarlar siliniyordu: burada eski veri
      // çoktan gitmiş olurdu.
      final halfway = await stored();
      expect(halfway['puzzle_progress_v1'], 'eski-ilerleme');
      expect(halfway['openings_notes_v1'], 'eski-notlar');
      expect(snapshot().existsSync(), isTrue);

      // Uygulama yeniden açılıyor.
      BackupService.debugAfterWrite = null;
      expect(await BackupService.instance.recoverInterruptedRestore(), isTrue);
      expect(await stored(), before);
      expect(snapshot().existsSync(), isFalse);
    });

    test('başarılı geri yüklemeden sonra kopya kalmıyor, açılışta bir şey yapılmıyor',
        () async {
      // Önceki bir geri yüklemeden silinemeyip boşaltılmış kopya kalmış.
      await snapshot().writeAsString('');
      await BackupService.instance.apply(incoming);
      final after = await stored();
      for (final entry in incoming.entries) {
        expect(after, containsPair(entry.key, entry.value));
      }
      expect(after.containsKey('puzzle_progress_v1'), isFalse);
      expect(after.containsKey('openings_notes_v1'), isFalse);
      // Cihaza özel anahtar Değiştir kipinde de korunuyor.
      expect(after, containsPair('analysis_lists_v1', 'yerel-analiz'));
      expect(snapshot().existsSync(), isFalse);
      expect(await BackupService.instance.recoverInterruptedRestore(), isFalse);
      expect((await stored())['playlists_v2'], 'yeni-listeler');
    });

    test('anlık kopya yazılamazsa geri yükleme hiç başlamıyor', () async {
      // Klasörün yerinde bir dosya var: kopya yazılamaz.
      final blocker = File('${dir.path}${Platform.pathSeparator}engel');
      await blocker.writeAsString('x');
      BackupService.snapshotDirectory = () async => Directory(blocker.path);

      await expectLater(
        BackupService.instance.apply(incoming),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', 'writeFailed')),
      );
      expect(await stored(), before);
    });

    test('yarım ya da boş kopya veriye dokunmadan temizleniyor', () async {
      await snapshot().writeAsString('{"app": "chess-library-bac');
      expect(await BackupService.instance.recoverInterruptedRestore(), isFalse);
      expect(await stored(), before);
      expect(snapshot().existsSync(), isFalse);
    });
  });
}
