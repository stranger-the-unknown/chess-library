import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'search_result.dart';

/// Ayrı bir işletim sistemi sürecinde UCI konuşan Stockfish sarmalayıcı.
///
/// Süreç çökerse `null` döner; Dart motoru yedek olarak kullanılmaz. SF
/// uygulamanın içinde değil, ayrı süreçte çalıştığı için ölmesi uygulamayı
/// götürmez. Uygun olduğunda süreç yeniden başlatılır.
///
/// stdout satırları tek bir abonelikten dispatch ile dağıtılır.
/// Bekleyiciler / analiz dinleyicileri **komut yazılmadan önce** silahlanır;
/// böylece broadcast StreamController yarışı (uciok / bestmove kaçırma)
/// olmaz. Eski satır taraması yapılmaz (yanlış eşleşme riski).
class StockfishUci {
  Process? _process;
  StreamSubscription<String>? _outSub;
  bool _ready = false;
  String? _binaryPath;
  Completer<SearchResult?>? _activeSearch;

  /// Komut yanıtı için tek-seferlik bekleyiciler (stdout dispatch).
  final List<_LineWaiter> _waiters = <_LineWaiter>[];

  /// analyze sırasında satır dinleyicileri (go yazılmadan önce eklenir).
  final List<void Function(String line)> _lineListeners =
      <void Function(String line)>[];

  /// Son uygulanan güç ayarları (gereksiz setoption'ları azaltmak için).
  int? _appliedSkill;
  bool? _appliedLimitStrength;
  int? _appliedElo;

  /// Android ilk-çalıştırma çıkartması vb. için önceden çözülmüş yol.
  static String? cachedBinaryPath;

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
        _dispatchLine,
        onError: (_) {},
        onDone: () {
          _ready = false;
          _process = null;
          _appliedSkill = null;
          _appliedLimitStrength = null;
          _appliedElo = null;
          _failAllWaiters();
          final pending = _activeSearch;
          if (pending != null && !pending.isCompleted) {
            pending.complete(null);
          }
        },
      );
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((_) {});

      // Bekleyiciyi yazmadan önce silahla (broadcast yarışı yok).
      final uciOk = _armWait((l) => l == 'uciok', const Duration(seconds: 5));
      _write('uci');
      if (!await uciOk) {
        await dispose();
        return false;
      }
      final ready1 = _armWait((l) => l == 'readyok', const Duration(seconds: 5));
      _write('isready');
      if (!await ready1) {
        await dispose();
        return false;
      }
      _write('setoption name Hash value 64');
      _write('setoption name Threads value 1');
      final ready2 = _armWait((l) => l == 'readyok', const Duration(seconds: 5));
      _write('isready');
      await ready2;
      _ready = true;
      _appliedSkill = null;
      _appliedLimitStrength = null;
      _appliedElo = null;
      return true;
    } catch (_) {
      await dispose();
      return false;
    }
  }

  /// Devam eden aramayı `stop` ile keser; bekleyen [analyze] hemen döner.
  Future<void> stopSearch() async {
    try {
      _write('stop');
    } catch (_) {}
    final pending = _activeSearch;
    if (pending != null && !pending.isCompleted) {
      pending.complete(null);
    }
  }

  /// UCI güç seçeneklerini `go` öncesi uygular.
  ///
  /// [skillLevel] Stockfish `Skill Level` (0–20). Tam güç için 20 +
  /// [limitStrength] false. Zayıf seviyelerde ayrıca `UCI_LimitStrength` /
  /// `UCI_Elo` kullanılır.
  Future<bool> applyStrength({
    required int skillLevel,
    required bool limitStrength,
    int? elo,
  }) async {
    if (!await start()) return false;
    final skill = skillLevel.clamp(0, 20);
    final useElo = limitStrength ? (elo ?? eloForSkill(skill)) : null;

    final same = _appliedSkill == skill &&
        _appliedLimitStrength == limitStrength &&
        _appliedElo == useElo;
    if (same) return true;

    try {
      _write('setoption name Skill Level value $skill');
      _write(
        'setoption name UCI_LimitStrength value ${limitStrength ? 'true' : 'false'}',
      );
      if (limitStrength && useElo != null) {
        _write('setoption name UCI_Elo value $useElo');
      }
      final ready = _armWait((l) => l == 'readyok', const Duration(seconds: 3));
      _write('isready');
      if (!await ready) {
        await _restart();
        return isRunning;
      }
      _appliedSkill = skill;
      _appliedLimitStrength = limitStrength;
      _appliedElo = useElo;
      return true;
    } catch (_) {
      await _restart();
      return false;
    }
  }

  /// EngineLevel.skill → yaklaşık UCI_Elo (UI'da gösterilmez).
  static int eloForSkill(int skill) {
    const map = <int, int>{
      2: 1350,
      5: 1550,
      9: 1750,
      13: 2000,
      17: 2300,
      20: 2850,
    };
    return map[skill] ?? (1320 + skill * 80).clamp(1320, 3190);
  }

  Future<SearchResult?> analyze(
    String fen, {
    int depth = 20,
    int movetimeMs = 1000,
    int skillLevel = 20,
    bool limitStrength = false,
    int? elo,
    void Function(SearchResult partial)? onProgress,
  }) async {
    if (!await start()) return null;

    // Önceki arama varsa kes.
    await stopSearch();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    try {
      if (!await applyStrength(
        skillLevel: skillLevel,
        limitStrength: limitStrength,
        elo: elo,
      )) {
        return null;
      }

      _write('ucinewgame');
      final readyNg = _armWait((l) => l == 'readyok', const Duration(seconds: 3));
      _write('isready');
      if (!await readyNg) {
        await _restart();
        if (!isRunning) return null;
        if (!await applyStrength(
          skillLevel: skillLevel,
          limitStrength: limitStrength,
          elo: elo,
        )) {
          return null;
        }
      }

      _write('position fen $fen');

      var best = '';
      var scoreCp = 0;
      int? mateIn;
      var reachedDepth = 0;
      var nodes = 0;
      var pv = const <String>[];

      final done = Completer<SearchResult?>();
      _activeSearch = done;
      final timer = Timer(Duration(milliseconds: movetimeMs + 4000), () {
        if (!done.isCompleted) {
          try {
            _write('stop');
          } catch (_) {}
          done.complete(null);
        }
      });

      // Dinleyiciyi go yazılmadan önce ekle (yarış yok).
      void onLine(String line) {
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
      }

      _lineListeners.add(onLine);
      // movetime duvar saati; yüksek depth tavanı SF'nin movetime içinde
      // gidebildiği kadar derine inmesine izin verir.
      _write('go movetime $movetimeMs depth $depth');

      final result = await done.future;
      _lineListeners.remove(onLine);
      timer.cancel();
      if (identical(_activeSearch, done)) _activeSearch = null;
      return result;
    } catch (_) {
      await _restart();
      return null;
    }
  }

  Future<void> dispose() async {
    _ready = false;
    _appliedSkill = null;
    _appliedLimitStrength = null;
    _appliedElo = null;
    final pending = _activeSearch;
    if (pending != null && !pending.isCompleted) {
      pending.complete(null);
    }
    _activeSearch = null;
    _failAllWaiters();
    _lineListeners.clear();
    try {
      _write('quit');
    } catch (_) {}
    await _outSub?.cancel();
    _outSub = null;
    try {
      _process?.kill();
    } catch (_) {}
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
    try {
      p.stdin.writeln(cmd);
    } catch (_) {}
  }

  void _dispatchLine(String line) {
    // Bekleyicileri önce çöz (tek-seferlik).
    if (_waiters.isNotEmpty) {
      final snapshot = List<_LineWaiter>.from(_waiters);
      for (final w in snapshot) {
        if (w.completer.isCompleted) {
          _waiters.remove(w);
          continue;
        }
        if (w.match(line)) {
          w.completer.complete(true);
          _waiters.remove(w);
        }
      }
    }
    // Analiz dinleyicileri.
    if (_lineListeners.isNotEmpty) {
      for (final listener in List<void Function(String)>.from(_lineListeners)) {
        listener(line);
      }
    }
  }

  /// Yanıt bekleyicisini kaydeder; çağıran **sonra** komutu yazmalıdır.
  Future<bool> _armWait(bool Function(String) match, Duration timeout) {
    final completer = Completer<bool>();
    final waiter = _LineWaiter(match, completer);
    _waiters.add(waiter);
    Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.complete(false);
      }
      _waiters.remove(waiter);
    });
    return completer.future;
  }

  void _failAllWaiters() {
    for (final w in List<_LineWaiter>.from(_waiters)) {
      if (!w.completer.isCompleted) {
        w.completer.complete(false);
      }
    }
    _waiters.clear();
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
    // Explicit override (tests / Android extract): if set, do not fall through.
    if (cachedBinaryPath != null) {
      if (await File(cachedBinaryPath!).exists()) return cachedBinaryPath;
      return null;
    }

    final env = Platform.environment['STOCKFISH_PATH'];
    if (env != null && env.isNotEmpty && await File(env).exists()) {
      return env;
    }

    final sep = Platform.pathSeparator;
    final candidates = <String>[];

    if (Platform.isWindows) {
      candidates.add(
        <String>[Directory.current.path, 'windows', 'stockfish', 'stockfish.exe']
            .join(sep),
      );
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
    } else if (Platform.isAndroid) {
      // Geliştirme / manuel kopya yolları; APK içi çıkartma
      // [ensureAndroidStockfishBinary] ile cachedBinaryPath'e yazılır.
      candidates.add(
        <String>[
          Directory.current.path,
          'android',
          'stockfish',
          'stockfish-arm64-v8a',
        ].join(sep),
      );
      candidates.add(
        <String>[
          Directory.current.path,
          'android',
          'stockfish',
          'stockfish-armeabi-v7a',
        ].join(sep),
      );
      try {
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        candidates.add(<String>[exeDir, 'stockfish'].join(sep));
        candidates.add(<String>[exeDir, 'libstockfish.so'].join(sep));
      } catch (_) {}
    } else {
      // Linux/macOS: smoke / CI
      candidates.add(
        <String>[Directory.current.path, 'stockfish'].join(sep),
      );
      candidates.add('/usr/games/stockfish');
      candidates.add('/usr/bin/stockfish');
    }

    for (final path in candidates) {
      if (await File(path).exists()) return path;
    }
    return null;
  }
}

class _LineWaiter {
  final bool Function(String) match;
  final Completer<bool> completer;

  _LineWaiter(this.match, this.completer);
}
