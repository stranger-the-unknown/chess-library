import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:chess_pgn_reader/services/engine/maia/maia_net.dart';

/// Maia ağının bir hamlesi ne kadar sürüyor (derlenmiş kodda)?
///
/// `flutter test` JIT ile koşuyor ve yayın derlemesinden yavaş. Ağ saf
/// Dart olduğu için ayrıca derlenip ölçülebiliyor:
///
///     dart compile exe tool/maia_bench.dart -o build/maia_bench.exe
///     build/maia_bench.exe assets/maia/maia3-5m.bin
///
/// Girdi yapay (rastgele bir tahta, 30 hamle): süre içeriğe bağlı değil.
void main(List<String> args) {
  final path = args.isNotEmpty ? args.first : 'assets/maia/maia3-5m.bin';
  final load = Stopwatch()..start();
  final net = MaiaNet(MaiaWeights.parse(File(path).readAsBytesSync()));
  load.stop();
  stdout.writeln('yükleme: ${load.elapsedMilliseconds} ms');

  final random = math.Random(1);
  final channels = net.c.history * 12;
  final board = Float32List(64 * channels);
  for (var square = 0; square < 64; square++) {
    if (random.nextDouble() < 0.5) {
      board[square * channels + random.nextInt(channels)] = 1;
    }
  }
  final moves = List<int>.generate(30, (_) => random.nextInt(MaiaNet.moveCount));

  // Isınma: ilk çağrılar ölçüme girmesin.
  for (var i = 0; i < 3; i++) {
    net.logits(board, 1500, 1500, moves);
  }
  final times = <int>[];
  for (var i = 0; i < 30; i++) {
    final watch = Stopwatch()..start();
    net.logits(board, 1500, 1500, moves);
    watch.stop();
    times.add(watch.elapsedMicroseconds);
  }
  times.sort();
  String ms(int us) => (us / 1000).toStringAsFixed(1);
  stdout.writeln('hamle başına: en az ${ms(times.first)} ms, '
      'ortanca ${ms(times[times.length ~/ 2])} ms, '
      'en çok ${ms(times.last)} ms');
}
