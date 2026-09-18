import 'dart:io';
import '../lib/services/engine/stockfish_uci.dart';

/// Proves waiters are armed before writes: rapid start/analyze loops must not
/// miss uciok / bestmove.
Future<void> main() async {
  final path = Platform.environment['STOCKFISH_PATH'] ??
      await StockfishUci.resolveBinaryPath();
  stdout.writeln('binary: $path');
  if (path == null) {
    stderr.writeln('Stockfish not found');
    exitCode = 2;
    return;
  }
  StockfishUci.cachedBinaryPath = path;

  const fen = '8/8/8/8/8/4k3/4P3/4K3 w - - 0 1'; // expected e1f1 often
  const fenKQvK = '4k3/8/8/8/8/8/8/4KQ2 w - - 0 1';

  var fails = 0;
  for (var i = 0; i < 8; i++) {
    final sf = StockfishUci();
    if (!await sf.start()) {
      stderr.writeln('iter $i start FAILED');
      fails++;
      await sf.dispose();
      continue;
    }
    final r = await sf.analyze(fen, movetimeMs: 200, depth: 18);
    stdout.writeln('iter $i best=${r?.bestMoveUci} depth=${r?.depth}');
    if (r == null || r.bestMoveUci.isEmpty) fails++;
    await sf.dispose();
  }

  // Single longer endgame check
  final sf2 = StockfishUci();
  if (!await sf2.start()) {
    stderr.writeln('endgame start failed');
    exitCode = 3;
    return;
  }
  final end = await sf2.analyze(fen, movetimeMs: 500, depth: 22);
  stdout.writeln('endgame K+P best=${end?.bestMoveUci} (expect e1f1-ish)');
  final kq = await sf2.analyze(fenKQvK, movetimeMs: 400, depth: 20);
  stdout.writeln('KQ vs K best=${kq?.bestMoveUci}');
  await sf2.dispose();

  if (fails > 0 || end == null || end.bestMoveUci.isEmpty) {
    stderr.writeln('FAILS=$fails');
    exitCode = 4;
  } else {
    stdout.writeln('OK race harness passed (fails=$fails)');
  }
}
