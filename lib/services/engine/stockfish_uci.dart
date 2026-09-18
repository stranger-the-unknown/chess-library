import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'chess_ai.dart';

/// Ayrı bir işletim sistemi sürecinde UCI konuşan Stockfish sarmalayıcı.
///
/// Süreç çökerse `null` döner; çağıran Dart motoruna düşer. SF uygulamanın
/// içinde değil, ayrı süreçte çalıştığı için ölmesi uygulamayı götürmez.
class StockfishUci {
  Process? _process;
  StreamSubscription<String>? _outSub;
  final _lines = StreamController<String>.broadcast();
  bool _ready = false;
  String? _binaryPath;

  bool get isRunning => _process != null && _ready;

  Future<bool> start() async {
    if (isRunning) return true;
    final path = await resolveBinaryPath();
    if (path == null) return false;
    _binaryPath = path;

    try {
      final process = await Process.start(
        path,
        const <String>[],
        mode: ProcessStartMode.normal,
        runInShell: false,
      );
      _process = process;
      _outSub = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        _lines.add,
        onError: (_) {},
        onDone: () {
          _ready = false;
          _process = null;
        },
      );
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((_) {});

      _write('uci');
      if (!await _waitFor((l) => l == 'uciok', const Duration(seconds: 5))) {
        await dispose();
        return false;
      }
      _write('isready');
      if (!await _waitFor((l) => l == 'readyok', const Duration(seconds: 5))) {
        await dispose();
        return false;
      }
      _write('setoption name Hash value 64');
      _write('setoption name Threads value 1');
      _write('isready');
      await _waitFor((l) => l == 'readyok', const Duration(seconds: 5));
      _ready = true;
      return true;
    } catch (_) {
      await dispose();
      return false;
    }
  }

  Future<SearchResult?> analyze(
    String fen, {
    int depth = 20,
    int movetimeMs = 1000,
    void Function(SearchResult partial)? onProgress,
  }) async {
    if (!await start()) return null;

    try {
      _write('stop');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      _write('ucinewgame');
      _write('isready');
      if (!await _waitFor((l) => l == 'readyok', const Duration(seconds: 3))) {
        await _restart();
        if (!isRunning) return null;
      }

      _write('position fen $fen');
      _write('go movetime $movetimeMs depth $depth');

      var best = '';
      var scoreCp = 0;
      int? mateIn;
      var reachedDepth = 0;
      var nodes = 0;
      var pv = const <String>[];

      final done = Completer<SearchResult?>();
      final timer = Timer(Duration(milliseconds: movetimeMs + 4000), () {
        if (!done.isCompleted) {
          _write('stop');
          done.complete(null);
        }
      });

      final sub = _lines.stream.listen((line) {
        if (line.startsWith('info ')) {
          final partial = _parseInfo(line);
          if (partial == null) return;
          if (partial.depth > reachedDepth) reachedDepth = partial.depth;
          if (partial.nodes > nodes) nodes = partial.nodes;
          scoreCp = partial.scoreCp;
          mateIn = partial.mateIn;
          if (partial.pvUci.isNotEmpty) pv = partial.pvUci;
          if (partial.bestMoveUci.isNotEmpty) best = partial.bestMoveUci;
          onProgress?.call(
            SearchResult(
              bestMoveUci: best.isNotEmpty
                  ? best
                  : (pv.isNotEmpty ? pv.first : ''),
              scoreCp: scoreCp,
              mateIn: mateIn,
              depth: reachedDepth,
              nodes: nodes,
              pvUci: pv,
            ),
          );
        } else if (line.startsWith('bestmove ')) {
          final parts = line.split(RegExp(r'\s+'));
          if (parts.length >= 2 && parts[1] != '(none)') {
            best = parts[1];
          }
          timer.cancel();
          if (!done.isCompleted) {
            done.complete(
              SearchResult(
                bestMoveUci: best,
                scoreCp: scoreCp,
                mateIn: mateIn,
                depth: reachedDepth,
                nodes: nodes,
                pvUci: pv.isNotEmpty
                    ? pv
                    : (best.isEmpty ? const <String>[] : <String>[best]),
              ),
            );
          }
        }
      });

      final result = await done.future;
      await sub.cancel();
      timer.cancel();
      return result;
    } catch (_) {
      await _restart();
      return null;
    }
  }

  Future<void> dispose() async {
    _ready = false;
    try {
      _write('quit');
    } catch (_) {}
    await _outSub?.cancel();
    _outSub = null;
    _process?.kill();
    _process = null;
  }

  Future<void> _restart() async {
    final path = _binaryPath;
    await dispose();
    _binaryPath = path;
    await start();
  }

  void _write(String cmd) {
    final p = _process;
    if (p == null) return;
    p.stdin.writeln(cmd);
  }

  Future<bool> _waitFor(bool Function(String) match, Duration timeout) async {
    final completer = Completer<bool>();
    late final StreamSubscription<String> sub;
    final timer = Timer(timeout, () {
      if (!completer.isCompleted) completer.complete(false);
    });
    sub = _lines.stream.listen((line) {
      if (match(line) && !completer.isCompleted) completer.complete(true);
    });
    final ok = await completer.future;
    await sub.cancel();
    timer.cancel();
    return ok;
  }

  static SearchResult? _parseInfo(String line) {
    final depthMatch = RegExp(r'\bdepth (\d+)').firstMatch(line);
    final nodesMatch = RegExp(r'\bnodes (\d+)').firstMatch(line);
    final cpMatch = RegExp(r'\bscore cp (-?\d+)').firstMatch(line);
    final mateMatch = RegExp(r'\bscore mate (-?\d+)').firstMatch(line);
    final pvMatch = RegExp(r'\bpv (.+)$').firstMatch(line);
    if (depthMatch == null && cpMatch == null && mateMatch == null) {
      return null;
    }
    var scoreCp = 0;
    int? mateIn;
    if (mateMatch != null) {
      final m = int.parse(mateMatch.group(1)!);
      mateIn = m;
      scoreCp = m >= 0 ? 100000 - m : -100000 - m;
    } else if (cpMatch != null) {
      scoreCp = int.parse(cpMatch.group(1)!);
    }
    final pv = pvMatch == null
        ? const <String>[]
        : pvMatch.group(1)!.trim().split(RegExp(r'\s+'));
    return SearchResult(
      bestMoveUci: pv.isNotEmpty ? pv.first : '',
      scoreCp: scoreCp,
      mateIn: mateIn,
      depth: depthMatch != null ? int.parse(depthMatch.group(1)!) : 0,
      nodes: nodesMatch != null ? int.parse(nodesMatch.group(1)!) : 0,
      pvUci: pv,
    );
  }

  static Future<String?> resolveBinaryPath() async {
    final env = Platform.environment['STOCKFISH_PATH'];
    if (env != null && env.isNotEmpty && await File(env).exists()) {
      return env;
    }

    final sep = Platform.pathSeparator;
    final candidates = <String>[
      <String>[Directory.current.path, 'windows', 'stockfish', 'stockfish.exe']
          .join(sep),
    ];

    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      candidates.add(<String>[exeDir, 'stockfish.exe'].join(sep));
      candidates.add(<String>[exeDir, 'data', 'stockfish.exe'].join(sep));
      final buildStockfish = <String>[
        exeDir,
        '..',
        '..',
        '..',
        '..',
        '..',
        'windows',
        'stockfish',
        'stockfish.exe',
      ].join(sep);
      candidates.add(File(buildStockfish).absolute.path);
    } catch (_) {}

    for (final path in candidates) {
      if (await File(path).exists()) return path;
    }
    return null;
  }
}
