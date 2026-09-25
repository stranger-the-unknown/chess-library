import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:chess_pgn_reader/services/engine/engine_service.dart';
import 'package:chess_pgn_reader/services/engine/stockfish_uci.dart';

/// Bilinen tek hamlelik son oyun (K+P vs K): beyazın en iyisi e1f1.
const endgameFen = '8/8/8/8/8/4k3/4P3/4K3 w - - 0 1';

/// Zayıf bir Stockfish ayarı (eski "Acemi", skill 2). Listenin başı
/// artık Maia; bu testler Stockfish'i sınıyor.
const _weakest = EngineLevel(index: 0, depth: 1, movetimeMs: 150, skill: 2);

void main() {
  tearDown(() async {
    StockfishUci.cachedBinaryPath = null;
    await EngineService.instance.dispose();
  });

  group('SF-only: missing / crash isolation', () {
    test('start fails cleanly when binary missing', () async {
      StockfishUci.cachedBinaryPath =
          '${Directory.systemTemp.path}/chesslib-missing-sf-binary';
      final sf = StockfishUci();
      expect(await sf.start(), isFalse);
      expect(await sf.analyze(endgameFen, movetimeMs: 100, depth: 2), isNull);
      await sf.dispose();
    });

    test('EngineService returns empty when SF missing (no Dart fallback)',
        () async {
      StockfishUci.cachedBinaryPath =
          '${Directory.systemTemp.path}/chesslib-missing-sf-binary-2';
      final result = await EngineService.instance.analyze(
        endgameFen,
        depth: 4,
        movetimeMs: 200,
      );
      expect(result.bestMoveUci, isEmpty);

      final play = await EngineService.instance.bestMoveForLevel(
        endgameFen,
        _weakest,
      );
      expect(play.bestMoveUci, isEmpty);
    });

    test('dying UCI process yields null / empty, app stays up', () async {
      final script = await _writeScript('dying', Uint8List.fromList([35,33,47,98,105,110,47,115,104,10,119,104,105,108,101,32,73,70,83,61,32,114,101,97,100,32,45,114,32,108,105,110,101,59,32,100,111,10,32,32,99,97,115,101,32,34,36,108,105,110,101,34,32,105,110,10,32,32,32,32,117,99,105,41,32,101,99,104,111,32,34,105,100,32,110,97,109,101,32,68,121,105,110,103,70,105,115,104,34,59,32,101,99,104,111,32,34,117,99,105,111,107,34,32,59,59,10,32,32,32,32,105,115,114,101,97,100,121,41,32,101,99,104,111,32,34,114,101,97,100,121,111,107,34,32,59,59,10,32,32,32,32,113,117,105,116,41,32,101,120,105,116,32,48,32,59,59,10,32,32,32,32,103,111,42,41,32,101,120,105,116,32,49,32,59,59,10,32,32,101,115,97,99,10,100,111,110,101,10]));
      addTearDown(() {
        try {
          script.deleteSync();
        } catch (_) {}
      });

      StockfishUci.cachedBinaryPath = script.path;
      final sf = StockfishUci();
      expect(await sf.start(), isTrue);
      final mid = await sf.analyze(endgameFen, movetimeMs: 300, depth: 4);
      expect(mid, isNull);
      await sf.dispose();

      StockfishUci.cachedBinaryPath = script.path;
      final viaService = await EngineService.instance.analyze(
        endgameFen,
        depth: 4,
        movetimeMs: 300,
      );
      expect(viaService.bestMoveUci, isEmpty);
    }, onPlatform: {
      'windows': [Skip('POSIX shell UCI fake')],
    });

    test('stopSearch completes without hanging the UI', () async {
      final script = await _writeScript('slow', Uint8List.fromList([35,33,47,98,105,110,47,115,104,10,119,104,105,108,101,32,73,70,83,61,32,114,101,97,100,32,45,114,32,108,105,110,101,59,32,100,111,10,32,32,99,97,115,101,32,34,36,108,105,110,101,34,32,105,110,10,32,32,32,32,117,99,105,41,32,101,99,104,111,32,34,105,100,32,110,97,109,101,32,83,108,111,119,70,105,115,104,34,59,32,101,99,104,111,32,34,117,99,105,111,107,34,32,59,59,10,32,32,32,32,105,115,114,101,97,100,121,41,32,101,99,104,111,32,34,114,101,97,100,121,111,107,34,32,59,59,10,32,32,32,32,115,116,111,112,41,32,101,99,104,111,32,34,98,101,115,116,109,111,118,101,32,48,48,48,48,34,32,59,59,10,32,32,32,32,113,117,105,116,41,32,101,120,105,116,32,48,32,59,59,10,32,32,32,32,103,111,42,41,32,115,108,101,101,112,32,51,48,59,32,101,99,104,111,32,34,98,101,115,116,109,111,118,101,32,101,50,101,52,34,32,59,59,10,32,32,101,115,97,99,10,100,111,110,101,10]));
      addTearDown(() {
        try {
          script.deleteSync();
        } catch (_) {}
      });
      StockfishUci.cachedBinaryPath = script.path;
      final sf = StockfishUci();
      expect(await sf.start(), isTrue);
      final future = sf.analyze(endgameFen, movetimeMs: 8000, depth: 40);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      final sw = Stopwatch()..start();
      await sf.stopSearch();
      final result = await future.timeout(const Duration(seconds: 2));
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(2000));
      expect(result, isNull);
      await sf.dispose();
    }, onPlatform: {
      'windows': [Skip('POSIX shell UCI fake')],
    });
  });

  group('Strength options', () {
    test('weak level sets Skill + LimitStrength; analyze resets full', () async {
      final script = await _writeScript('rec', Uint8List.fromList([35,33,47,98,105,110,47,115,104,10,76,79,71,61,34,36,48,46,108,111,103,34,10,119,104,105,108,101,32,73,70,83,61,32,114,101,97,100,32,45,114,32,108,105,110,101,59,32,100,111,10,32,32,101,99,104,111,32,34,36,108,105,110,101,34,32,62,62,32,34,36,76,79,71,34,10,32,32,99,97,115,101,32,34,36,108,105,110,101,34,32,105,110,10,32,32,32,32,117,99,105,41,32,101,99,104,111,32,34,105,100,32,110,97,109,101,32,82,101,99,70,105,115,104,34,59,32,101,99,104,111,32,34,117,99,105,111,107,34,32,59,59,10,32,32,32,32,105,115,114,101,97,100,121,41,32,101,99,104,111,32,34,114,101,97,100,121,111,107,34,32,59,59,10,32,32,32,32,113,117,105,116,41,32,101,120,105,116,32,48,32,59,59,10,32,32,32,32,103,111,42,41,10,32,32,32,32,32,32,101,99,104,111,32,34,105,110,102,111,32,100,101,112,116,104,32,49,32,115,99,111,114,101,32,99,112,32,50,48,32,112,118,32,101,50,101,52,34,10,32,32,32,32,32,32,101,99,104,111,32,34,98,101,115,116,109,111,118,101,32,101,50,101,52,34,10,32,32,32,32,32,32,59,59,10,32,32,101,115,97,99,10,100,111,110,101,10]));
      addTearDown(() {
        try {
          script.deleteSync();
          File('${script.path}.log').deleteSync();
        } catch (_) {}
      });
      StockfishUci.cachedBinaryPath = script.path;

      final play = await EngineService.instance.bestMoveForLevel(
        endgameFen,
        _weakest, // skill 2
      );
      expect(play.bestMoveUci, isNotEmpty);

      final analysis = await EngineService.instance.analyze(
        endgameFen,
        depth: 6,
        movetimeMs: 50,
      );
      expect(analysis.bestMoveUci, isNotEmpty);

      final log = await File('${script.path}.log').readAsString();
      expect(log, contains('setoption name Skill Level value 2'));
      expect(log, contains('setoption name UCI_LimitStrength value true'));
      expect(log, contains('setoption name UCI_Elo value'));
      expect(log, contains('setoption name Skill Level value 20'));
      expect(log, contains('setoption name UCI_LimitStrength value false'));
    }, onPlatform: {
      'windows': [Skip('POSIX shell UCI fake')],
    });
  });


  group('Optional Stockfish integration', () {
    test('real binary endgame best e1f1 (skip if missing)', () async {
      StockfishUci.cachedBinaryPath = null;
      final path = await StockfishUci.resolveBinaryPath();
      if (path == null) {
        // ignore: avoid_print
        print('SKIP: Stockfish binary yok');
        return;
      }
      final sf = StockfishUci();
      expect(await sf.start(), isTrue);
      final result =
          await sf.analyze(endgameFen, movetimeMs: 800, depth: 22);
      await sf.dispose();
      expect(result, isNotNull);
      expect(result!.bestMoveUci, anyOf('e1f1', 'e1d1'));
      // ignore: avoid_print
      print('REAL_BESTMOVE ${result.bestMoveUci}');
    });

    test('real binary: weak level then analyze resets to full strength', () async {
      StockfishUci.cachedBinaryPath = null;
      final path = await StockfishUci.resolveBinaryPath();
      if (path == null) {
        // ignore: avoid_print
        print('SKIP: Stockfish binary yok');
        return;
      }
      StockfishUci.cachedBinaryPath = path;

      final weak = await EngineService.instance.bestMoveForLevel(
        endgameFen,
        _weakest,
      );
      expect(weak.bestMoveUci, isNotEmpty);
      // ignore: avoid_print
      print('WEAK_BEST ${weak.bestMoveUci}');

      final full = await EngineService.instance.analyze(
        endgameFen,
        depth: 22,
        movetimeMs: 800,
      );
      expect(full.bestMoveUci, anyOf('e1f1', 'e1d1'));
      // ignore: avoid_print
      print('FULL_BEST ${full.bestMoveUci}');
    });
  });
}


Future<File> _writeScript(String tag, Uint8List bytes) async {
  final file = File(
    '${Directory.systemTemp.path}/chesslib_${tag}_uci_${DateTime.now().microsecondsSinceEpoch}.sh',
  );
  await file.writeAsBytes(bytes);
  await Process.run('chmod', ['+x', file.path]);
  return file;
}
