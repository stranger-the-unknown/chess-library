import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:stockfish_chess_engine/stockfish_chess_engine.dart';
import 'package:stockfish_chess_engine/stockfish_chess_engine_state.dart';

import '../../models/chess_engine.dart' as rules;
import 'search_result.dart';

/// Stockfish'i UCI üzerinden konuşturan sarmalayıcı.
///
/// Uygulamanın geri kalanı motoru yalnızca [analyze] ile tanıyor; bu
/// sınıf eski Dart motoruyla aynı [SearchResult] türünü döndürüyor, o
/// yüzden çağrı yerleri değişmiyor.
///
/// Üç şeye dikkat edilmesi gerekiyor:
///
///  * **Tek örnek.** Paket birden çok Stockfish örneğine izin vermiyor,
///    bu yüzden istekler sıraya giriyor. UCI zaten durumlu bir protokol:
///    `position` ile `go` arasına başka bir arama giremez.
///  * **Kural dışı pozisyon çökertiyor.** Paketin kendi uyarısı bu.
///    Gelen FEN, uygulamanın perft ile doğrulanmış kural motorundan
///    geçirilmeden Stockfish'e verilmiyor.
///  * **Motor ağır açılıyor.** İlk `analyze` çağrısında NNUE ağı
///    yükleniyor; hazırlık bir kez yapılıp saklanıyor.
class StockfishEngine {
  static final StockfishEngine instance = StockfishEngine._();
  StockfishEngine._();

  Stockfish? _engine;
  StreamSubscription<String>? _output;
  Future<void>? _starting;

  /// Motor bir kez açılamadıysa her çağrıda yeniden denemenin anlamı yok;
  /// her denemede yirmi saniye beklemek uygulamayı kullanılmaz yapardı.
  bool _failed = false;

  /// Sırada bekleyen işler; UCI tek kanal olduğu için teker teker.
  final Queue<_Job> _queue = Queue<_Job>();
  _Job? _running;

  /// Şu an motorda kurulu olan seçenekler; gereksiz `setoption` yok.
  int? _skill;
  int? _elo;

  bool get isRunning => _engine?.state.value == StockfishState.ready;

  // ---------------------------------------------------------------------
  // Başlatma
  // ---------------------------------------------------------------------

  Future<void> _ensureStarted() {
    if (isRunning) return Future<void>.value();
    if (_failed) return Future<void>.error(StateError('Stockfish yok'));
    return _starting ??= _start();
  }

  Future<void> _start() async {
    final engine = Stockfish();
    _engine = engine;

    // Motor iki isolate açıyor; hazır olana kadar bekle.
    if (engine.state.value != StockfishState.ready) {
      final ready = Completer<void>();
      void listener() {
        final state = engine.state.value;
        if (state == StockfishState.ready && !ready.isCompleted) {
          ready.complete();
        } else if (state == StockfishState.error && !ready.isCompleted) {
          ready.completeError(StateError('Stockfish başlatılamadı'));
        }
      }

      engine.state.addListener(listener);
      try {
        await ready.future.timeout(const Duration(seconds: 20));
      } finally {
        engine.state.removeListener(listener);
      }
    }

    _output = engine.stdout.listen(_onLine);
    engine.stdin = 'uci';
    engine.stdin = 'setoption name Threads value 1';
    engine.stdin = 'setoption name Hash value 64';
    engine.stdin = 'isready';
  }

  // ---------------------------------------------------------------------
  // Arama
  // ---------------------------------------------------------------------

  /// [fen] pozisyonunu inceler.
  ///
  /// [depth] ve [movetimeMs] üst sınırlar; hangisine önce varılırsa arama
  /// orada biter. [skill] 20 ise motor tam gücünde oynar, düşükse
  /// Stockfish'in kendi zayıflatma düzeneği kullanılır. [elo] verilirse
  /// güç doğrudan o dereceye sabitlenir.
  Future<SearchResult> analyze(
    String fen, {
    int depth = 16,
    int movetimeMs = 1000,
    int skill = 20,
    int? elo,
    List<String> moves = const <String>[],
    void Function(SearchResult partial)? onProgress,
  }) async {
    // Kural dışı pozisyon Stockfish'i çökertiyor; kendi kural motorumuz
    // kapıda duruyor.
    final position = _validate(fen, moves);
    if (position == null) {
      return const SearchResult(
        bestMoveUci: '',
        scoreCp: 0,
        depth: 0,
        nodes: 0,
        pvUci: <String>[],
        isGameOver: true,
      );
    }
    if (position.allLegalMoves().isEmpty) {
      return SearchResult(
        bestMoveUci: '',
        scoreCp: position.isKingInCheck(position.sideToMove) ? -30000 : 0,
        mateIn: position.isKingInCheck(position.sideToMove) ? 0 : null,
        depth: 0,
        nodes: 0,
        pvUci: const <String>[],
        isGameOver: true,
      );
    }

    // Yerel kütüphane açılamazsa uygulama çökmemeli; analiz yapılmamış
    // gibi davranıp devam etmeli.
    try {
      await _ensureStarted();
    } catch (error) {
      debugPrint('Stockfish başlatılamadı: $error');
      _failed = true;
      return const SearchResult(
        bestMoveUci: '',
        scoreCp: 0,
        depth: 0,
        nodes: 0,
        pvUci: <String>[],
      );
    }

    final job = _Job(
      fen: fen,
      moves: moves,
      depth: depth,
      movetimeMs: movetimeMs,
      skill: skill,
      elo: elo,
      onProgress: onProgress,
    );
    _queue.add(job);
    _pump();
    return job.completer.future;
  }

  /// FEN'i uygulamanın kural motoruyla doğrular; geçersizse null.
  rules.ChessGame? _validate(String fen, List<String> moves) {
    try {
      final game = rules.ChessGame.fromFen(fen);
      for (final uci in moves) {
        final move = game.moveFromUci(uci);
        if (move == null) return null;
        game.makeMove(move);
      }
      return game;
    } catch (_) {
      return null;
    }
  }

  void _pump() {
    if (_running != null || _queue.isEmpty) return;
    final engine = _engine;
    if (engine == null) return;

    final job = _queue.removeFirst();
    _running = job;

    if (job.elo != null) {
      if (_elo != job.elo) {
        _elo = job.elo;
        _skill = null;
        engine.stdin = 'setoption name UCI_LimitStrength value true';
        engine.stdin = 'setoption name UCI_Elo value ${job.elo}';
      }
    } else if (_skill != job.skill || _elo != null) {
      _skill = job.skill;
      _elo = null;
      engine.stdin = 'setoption name UCI_LimitStrength value false';
      engine.stdin = 'setoption name Skill Level value ${job.skill}';
    }

    final suffix = job.moves.isEmpty ? '' : ' moves ${job.moves.join(' ')}';
    engine.stdin = 'position fen ${job.fen}$suffix';
    engine.stdin = 'go depth ${job.depth} movetime ${job.movetimeMs}';

    // Motor bir sebeple susarsa uygulama kilitlenmesin.
    job.guard = Timer(Duration(milliseconds: job.movetimeMs + 15000), () {
      if (identical(_running, job) && !job.completer.isCompleted) {
        engine.stdin = 'stop';
      }
    });
  }

  void _onLine(String line) {
    final job = _running;
    if (job == null) return;

    if (line.startsWith('info ')) {
      final partial = _parseInfo(line, job);
      if (partial != null) {
        job.last = partial;
        job.onProgress?.call(partial);
      }
      return;
    }

    if (line.startsWith('bestmove')) {
      final parts = line.split(RegExp(r'\s+'));
      final best = parts.length > 1 ? parts[1] : '';
      final last = job.last;
      final result = SearchResult(
        bestMoveUci: best == '(none)' ? '' : best,
        scoreCp: last?.scoreCp ?? 0,
        mateIn: last?.mateIn,
        depth: last?.depth ?? 0,
        nodes: last?.nodes ?? 0,
        pvUci: last?.pvUci ?? const <String>[],
        isGameOver: best == '(none)',
      );
      job.guard?.cancel();
      _running = null;
      if (!job.completer.isCompleted) job.completer.complete(result);
      _pump();
    }
  }

  /// `info depth 12 ... score cp 34 ... nodes 1234 ... pv e2e4 e7e5`
  SearchResult? _parseInfo(String line, _Job job) {
    final tokens = line.split(RegExp(r'\s+'));
    int? depth, nodes, scoreCp, mateIn;
    final pv = <String>[];

    for (int i = 0; i < tokens.length; i++) {
      switch (tokens[i]) {
        case 'depth':
          depth = int.tryParse(_at(tokens, i + 1));
          break;
        case 'nodes':
          nodes = int.tryParse(_at(tokens, i + 1));
          break;
        case 'score':
          final kind = _at(tokens, i + 1);
          final value = int.tryParse(_at(tokens, i + 2));
          if (kind == 'cp') {
            scoreCp = value;
          } else if (kind == 'mate' && value != null) {
            mateIn = value;
            // Mat skorunu eski motorun ölçeğine getir; grafik ve
            // sınıflandırma o ölçeğe göre yazılmış.
            scoreCp = value > 0 ? 30000 - value * 2 : -30000 - value * 2;
          }
          break;
        case 'pv':
          pv.addAll(tokens.sublist(i + 1));
          i = tokens.length;
          break;
      }
    }

    // Alt varyantlar (multipv) ve süre bildirimleri ana hattı ezmesin.
    if (depth == null || pv.isEmpty) return null;

    return SearchResult(
      bestMoveUci: pv.first,
      scoreCp: scoreCp ?? job.last?.scoreCp ?? 0,
      mateIn: mateIn,
      depth: depth,
      nodes: nodes ?? job.last?.nodes ?? 0,
      pvUci: pv,
    );
  }

  static String _at(List<String> tokens, int index) =>
      index < tokens.length ? tokens[index] : '';

  /// Süren aramayı keser.
  void stop() {
    if (isRunning) _engine!.stdin = 'stop';
  }

  @visibleForTesting
  Future<void> dispose() async {
    await _output?.cancel();
    _output = null;
    _engine?.dispose();
    _engine = null;
    _starting = null;
    _running = null;
    _queue.clear();
    _skill = null;
    _elo = null;
    _failed = false;
  }
}

class _Job {
  final String fen;
  final List<String> moves;
  final int depth;
  final int movetimeMs;
  final int skill;
  final int? elo;
  final void Function(SearchResult partial)? onProgress;
  final Completer<SearchResult> completer = Completer<SearchResult>();

  /// Motorun gördüğü en son tam bilgi satırı.
  SearchResult? last;
  Timer? guard;

  _Job({
    required this.fen,
    required this.moves,
    required this.depth,
    required this.movetimeMs,
    required this.skill,
    required this.elo,
    required this.onProgress,
  });
}
