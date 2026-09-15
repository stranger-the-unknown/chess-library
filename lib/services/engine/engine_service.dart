import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show kIsWeb;

import '../../l10n/app_strings.dart';
import 'chess_ai.dart';

export 'chess_ai.dart' show SearchResult;

/// Motorun oyun gücü kademeleri.
///
/// Her kademe hem arama süresini/derinliğini hem de motorun bilerek
/// yaptığı hata payını belirler; böylece "Acemi" seviyesi gerçekten
/// yenilebilir, "Usta" seviyesi ise cihazın verdiği kadar güçlü olur.
class EngineLevel {
  /// Çeviri tablosundaki sıra numarası (`level.<index>.name`).
  final int index;
  final int depth;
  final int movetimeMs;
  final int skill;

  const EngineLevel({
    required this.index,
    required this.depth,
    required this.movetimeMs,
    required this.skill,
  });

  String get name => t('level.$index.name');

  String get description => t('level.$index.desc');

  static const List<EngineLevel> all = [
    EngineLevel(
      index: 0,
      depth: 1,
      movetimeMs: 150,
      skill: 2,
    ),
    EngineLevel(
      index: 1,
      depth: 2,
      movetimeMs: 300,
      skill: 5,
    ),
    EngineLevel(
      index: 2,
      depth: 4,
      movetimeMs: 700,
      skill: 9,
    ),
    EngineLevel(
      index: 3,
      depth: 6,
      movetimeMs: 1400,
      skill: 13,
    ),
    EngineLevel(
      index: 4,
      depth: 9,
      movetimeMs: 2500,
      skill: 17,
    ),
    EngineLevel(
      index: 5,
      depth: 20,
      movetimeMs: 5000,
      skill: 20,
    ),
  ];
}

class _Request {
  final int id;
  final String fen;
  final int depth;
  final int movetimeMs;
  final int skill;
  final List<int> history;

  const _Request(
    this.id,
    this.fen,
    this.depth,
    this.movetimeMs,
    this.skill,
    this.history,
  );

  List<Object?> toMessage() => [id, fen, depth, movetimeMs, skill, history];
}

/// Motoru ayrı bir `Isolate` içinde çalıştırır; arayüz arama sırasında
/// tamamen akıcı kalır.
class EngineService {
  static final EngineService instance = EngineService._();
  EngineService._();

  Isolate? _isolate;
  SendPort? _toIsolate;
  ReceivePort? _fromIsolate;
  Completer<void>? _starting;

  /// Isolate açılamadıysa (ör. web) arama aynı isolate içinde yapılır.
  bool _inlineFallback = false;
  ChessAi? _inlineAi;

  int _nextId = 1;
  final Map<int, Completer<SearchResult>> _pending = {};
  final Map<int, void Function(SearchResult)> _listeners = {};

  Future<void> _ensureStarted() async {
    if (_toIsolate != null) return;
    if (_inlineFallback) return;
    if (_starting != null) return _starting!.future;

    // Web'de `dart:isolate` yalnızca bir taslaktır; aramayı yerinde yap.
    if (kIsWeb) {
      _inlineFallback = true;
      return;
    }

    final starting = Completer<void>();
    _starting = starting;

    // ReceivePort ve Isolate.spawn bazı platformlarda (ör. web)
    // desteklenmez; ikisi de aynı korumanın içinde denenir.
    late final ReceivePort receivePort;
    try {
      receivePort = ReceivePort();
      _fromIsolate = receivePort;
      _isolate = await Isolate.spawn(_worker, receivePort.sendPort);
    } catch (_) {
      _fromIsolate = null;
      _inlineFallback = true;
      _starting = null;
      if (!starting.isCompleted) starting.complete();
      return starting.future;
    }

    receivePort.listen((message) {
      if (message is SendPort) {
        _toIsolate = message;
        _starting = null;
        if (!starting.isCompleted) starting.complete();
        return;
      }
      if (message is! List) return;

      final id = message[0] as int;
      final isFinal = message[1] as bool;
      final result = SearchResult.fromMap(
        Map<String, dynamic>.from(message[2] as Map),
      );

      if (isFinal) {
        _listeners.remove(id);
        _pending.remove(id)?.complete(result);
      } else {
        _listeners[id]?.call(result);
      }
    });

    return starting.future;
  }

  /// Pozisyonu analiz eder ve en iyi hamleyi döner.
  ///
  /// [onProgress] her tamamlanan derinlikte çağrılır; analiz ekranında
  /// değerlendirmenin canlı güncellenmesi için kullanılır.
  Future<SearchResult> analyze(
    String fen, {
    int depth = 12,
    int movetimeMs = 1500,
    int skill = 20,
    List<int> repetitionHashes = const [],
    void Function(SearchResult partial)? onProgress,
  }) async {
    await _ensureStarted();

    if (_inlineFallback) {
      // Arayüzün en az bir kare çizmesine izin ver, sonra hesapla.
      await Future<void>.delayed(Duration.zero);
      final ai = _inlineAi ??= ChessAi();
      return ai.search(
        fen,
        maxDepth: depth,
        movetimeMs: movetimeMs,
        skill: skill,
        repetitionHashes: repetitionHashes.isEmpty ? null : repetitionHashes,
        onProgress: onProgress,
      );
    }

    final id = _nextId++;
    final completer = Completer<SearchResult>();
    _pending[id] = completer;
    if (onProgress != null) _listeners[id] = onProgress;

    _toIsolate!.send(
      _Request(id, fen, depth, movetimeMs, skill, repetitionHashes).toMessage(),
    );
    return completer.future;
  }

  /// Belirli bir seviyeye göre hamle üretir.
  Future<SearchResult> bestMoveForLevel(String fen, EngineLevel level) {
    return analyze(
      fen,
      depth: level.depth,
      movetimeMs: level.movetimeMs,
      skill: level.skill,
    );
  }

  /// Süren aramayı iptal eder. Dart isolate'i çalışan bir hesaplamanın
  /// ortasında mesaj işleyemediği için isolate sonlandırılıp bir sonraki
  /// istekte yeniden başlatılır.
  Future<void> cancel() async {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.complete(
          const SearchResult(
            bestMoveUci: '',
            scoreCp: 0,
            depth: 0,
            nodes: 0,
            pvUci: [],
            isGameOver: false,
          ),
        );
      }
    }
    _pending.clear();
    _listeners.clear();
    await dispose();
  }

  Future<void> dispose() async {
    _isolate?.kill(priority: Isolate.immediate);
    _fromIsolate?.close();
    _isolate = null;
    _fromIsolate = null;
    _toIsolate = null;
    _starting = null;
  }

  static void _worker(SendPort toMain) {
    final fromMain = ReceivePort();
    toMain.send(fromMain.sendPort);

    final ai = ChessAi();
    fromMain.listen((message) {
      if (message is! List) return;
      final id = message[0] as int;
      final fen = message[1] as String;
      final depth = message[2] as int;
      final movetime = message[3] as int;
      final skill = message[4] as int;
      final history = List<int>.from(message[5] as List);

      final result = ai.search(
        fen,
        maxDepth: depth,
        movetimeMs: movetime,
        skill: skill,
        repetitionHashes: history.isEmpty ? null : history,
        onProgress: (partial) => toMain.send([id, false, partial.toMap()]),
      );
      toMain.send([id, true, result.toMap()]);
    });
  }
}
