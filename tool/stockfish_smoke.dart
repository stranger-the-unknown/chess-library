import 'dart:io';
import 'package:chess_pgn_reader/services/engine/stockfish_uci.dart';

Future<void> main() async {
  final path = await StockfishUci.resolveBinaryPath();
  stdout.writeln('binary: $path');
  if (path == null) {
    stderr.writeln('Stockfish bulunamadi');
    exitCode = 2;
    return;
  }
  final sf = StockfishUci();
  if (!await sf.start()) {
    stderr.writeln('start failed');
    exitCode = 3;
    return;
  }
  const fen = '8/8/8/8/8/4k3/4P3/4K3 w - - 0 1';
  final result = await sf.analyze(fen, movetimeMs: 400, depth: 20);
  stdout.writeln(
    'best=${result?.bestMoveUci} depth=${result?.depth} '
    'cp=${result?.scoreCp} nodes=${result?.nodes}',
  );
  await sf.dispose();
  if (result == null || result.bestMoveUci.isEmpty) {
    exitCode = 4;
  }
}
