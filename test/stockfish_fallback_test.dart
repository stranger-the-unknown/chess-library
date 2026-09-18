import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:chess_pgn_reader/services/engine/engine_service.dart';
import 'package:chess_pgn_reader/services/engine/stockfish_uci.dart';

/// Bilinen tek hamlelik son oyun (K+P vs K): beyazin en iyisi e1f1.
const endgameFen = '8/8/8/8/8/4k3/4P3/4K3 w - - 0 1';

void main() {
  tearDown(() async {
    StockfishUci.cachedBinaryPath = null;
    await EngineService.instance.dispose();
  });

  group('Dart-only gameplay API', () {
    test('analyzeDart returns a move without Stockfish', () async {
      final result = await EngineService.instance.analyzeDart(
        endgameFen,
        depth: 6,
        movetimeMs: 400,
        skill: 20,
      );
      expect(result.bestMoveUci, isNotEmpty);
    });

    test('bestMoveForLevel does not throw', () async {
      final level = EngineLevel.all[2];
      final result =
          await EngineService.instance.bestMoveForLevel(endgameFen, level);
      expect(result.bestMoveUci, isNotEmpty);
    });
  });

  group('Stockfish crash isolation', () {
    test('start fails cleanly when binary missing', () async {
      StockfishUci.cachedBinaryPath =
          '${Directory.systemTemp.path}/chesslib-missing-sf-binary';
      final sf = StockfishUci();
      expect(await sf.start(), isFalse);
      expect(await sf.analyze(endgameFen, movetimeMs: 100, depth: 2), isNull);
      await sf.dispose();
    });

    test('dying UCI process yields null then Dart fallback', () async {
      final script = await _writeDyingUciScript();
      addTearDown(() {
        try {
          script.deleteSync();
        } catch (_) {}
      });

      StockfishUci.cachedBinaryPath = script.path;
      final sf = StockfishUci();
      final started = await sf.start();
      expect(started, isTrue);
      final mid = await sf.analyze(endgameFen, movetimeMs: 300, depth: 4);
      expect(mid, isNull);
      await sf.dispose();

      final dart = await EngineService.instance.analyzeDart(
        endgameFen,
        depth: 4,
        movetimeMs: 300,
      );
      expect(dart.bestMoveUci, isNotEmpty);
    }, onPlatform: {
      'windows': [Skip('POSIX shell UCI fake')],
    });

    test('stopSearch completes without hanging the UI', () async {
      final script = await _writeSlowUciScript();
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
          await sf.analyze(endgameFen, movetimeMs: 400, depth: 20);
      await sf.dispose();
      expect(result, isNotNull);
      expect(result!.bestMoveUci, 'e1f1');
    });
  });
}

Future<File> _writeDyingUciScript() async {
  final file = File(
    '${Directory.systemTemp.path}/chesslib_dying_uci_${DateTime.now().microsecondsSinceEpoch}.sh',
  );
  await file.writeAsString(r'''#!/bin/sh
while IFS= read -r line; do
  case "$line" in
    uci)
      echo "id name DyingFish"
      echo "uciok"
      ;;
    isready)
      echo "readyok"
      ;;
    quit)
      exit 0
      ;;
    go*)
      exit 1
      ;;
  esac
done
''');
  await Process.run('chmod', ['+x', file.path]);
  return file;
}

Future<File> _writeSlowUciScript() async {
  final file = File(
    '${Directory.systemTemp.path}/chesslib_slow_uci_${DateTime.now().microsecondsSinceEpoch}.sh',
  );
  await file.writeAsString(r'''#!/bin/sh
while IFS= read -r line; do
  case "$line" in
    uci)
      echo "id name SlowFish"
      echo "uciok"
      ;;
    isready)
      echo "readyok"
      ;;
    stop)
      echo "bestmove 0000"
      ;;
    quit)
      exit 0
      ;;
    go*)
      sleep 30
      echo "bestmove e2e4"
      ;;
  esac
done
''');
  await Process.run('chmod', ['+x', file.path]);
  return file;
}
