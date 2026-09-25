import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../../models/chess_engine.dart' as engine;
import 'maia_encoder.dart';
import 'maia_net.dart';

/// Maia'nın seçtiği hamle ve olasılığı.
class MaiaMove {
  final String uci;
  final double probability;

  const MaiaMove(this.uci, this.probability);
}

/// İnsan gibi oynayan rakip: Maia-3 (CSSLab, AGPL-3.0), cihazda.
///
/// Stockfish'in zayıflatılmış seviyeleri en iyi hamleyi arayıp arada
/// rastgele büyük hatalar yapıyordu: bir konumda taktik görüp başka bir
/// konumda vezir asıyordu. Maia en iyi hamleyi aramıyor; o puandaki
/// insanların o konumda hangi hamleleri hangi sıklıkla oynadığını
/// tahmin ediyor. Hamle bu dağılımdan çekiliyor, yani hataları da o
/// puandaki insanların hataları.
///
/// Ağ arka plan isolate'inde çalışıyor (tek hamle birkaç yüz ms
/// sürebiliyor, arayüz takılmasın). Hiçbir şey cihaz dışına çıkmıyor.
class MaiaPlayer {
  static final MaiaPlayer instance = MaiaPlayer._();
  MaiaPlayer._();

  /// Olasılık dağılımının sıcaklığı: 1 = modelin tahmini olduğu gibi.
  static const double temperature = 1.0;

  /// En olası hamlelerin toplam olasılığı bu değere ulaşınca geri
  /// kalanlar atılıyor: dağılımın en ucundaki anlamsız hamleler
  /// (%5'lik kuyruk) oynanmasın.
  static const double topP = 0.95;

  /// Ağırlık dosyasının yolu (Flutter varlığı).
  static const String asset = 'assets/maia/maia3-5m.bin';

  /// Ağırlıkları okur; testler değiştirir.
  @visibleForTesting
  static Future<Uint8List> Function() loadBytes = () async {
    final data = await rootBundle.load(asset);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  };

  _MaiaWorker? _worker;
  Future<_MaiaWorker?>? _starting;

  /// Ağırlıklar okunamadı ya da ağ kurulamadı; Maia kullanılamıyor.
  bool get unavailable => _failed;
  bool _failed = false;

  /// Maia neden kullanılamıyor (hata metni); oyun ekranı bunu gösteriyor
  /// ki bir hata fark edilmeden kalmasın.
  String? get failure => _failure;
  String? _failure;

  /// Ağı önceden kurar (oyun ekranı açılınca); ilk hamle beklemesin.
  Future<void> warmUp() async {
    await _ensureWorker();
  }

  Future<_MaiaWorker?> _ensureWorker() {
    final worker = _worker;
    if (worker != null && !worker.dead) return Future.value(worker);
    _worker = null;
    if (_failed) return Future.value(null);
    return _starting ??= () async {
      try {
        final bytes = await loadBytes();
        final started = await _MaiaWorker.spawn(bytes);
        _worker = started;
        return started;
      } catch (e) {
        _failed = true;
        final text = '$e';
        _failure = text.length > 200 ? '${text.substring(0, 200)}…' : text;
        return null;
      } finally {
        _starting = null;
      }
    }();
  }

  /// [history]: eskiden yeniye FEN'ler; sonuncusu hamle sırası olan konum.
  /// [elo]: Maia'nın oynayacağı puan; [opponentElo]: karşısındakinin
  /// puanı (bilinmiyorsa aynısı). Oynanacak hamle yoksa ya da Maia
  /// kullanılamıyorsa `null`.
  Future<MaiaMove?> move(
    List<String> history,
    int elo, {
    int? opponentElo,
    math.Random? random,
  }) async {
    if (history.isEmpty) return null;
    final worker = await _ensureWorker();
    if (worker == null) return null;
    // Ağ yalnızca son birkaç konuma bakıyor: uzun bir oyunda her hamlede
    // bütün geçmişi çözümlemeye gerek yok.
    final recent = history.length > worker.history
        ? history.sublist(history.length - worker.history)
        : history;
    final boards = <engine.ChessGame>[];
    try {
      for (final fen in recent) {
        boards.add(engine.ChessGame.fromFen(fen));
      }
    } catch (_) {
      return null;
    }
    final current = boards.last;
    final legal = current.allLegalMoves();
    if (legal.isEmpty) return null;

    final Float64List logits;
    try {
      logits = await worker.logits(
        MaiaEncoder.encode(boards, worker.history),
        elo,
        opponentElo ?? elo,
        [
          for (final m in legal)
            MaiaEncoder.moveIndex(m, current.sideToMove),
        ],
      );
    } catch (_) {
      return null;
    }
    final probabilities = softmax(logits, temperature);
    final pick = sample(probabilities, topP, random ?? math.Random());
    return MaiaMove(legal[pick].uci, probabilities[pick]);
  }

  /// Sıcaklıklı softmax.
  @visibleForTesting
  static Float64List softmax(Float64List logits, double temperature) {
    final t = temperature <= 0 ? 1e-6 : temperature;
    var max = double.negativeInfinity;
    for (final l in logits) {
      if (l > max) max = l;
    }
    final out = Float64List(logits.length);
    var sum = 0.0;
    for (var i = 0; i < logits.length; i++) {
      out[i] = math.exp((logits[i] - max) / t);
      sum += out[i];
    }
    for (var i = 0; i < out.length; i++) {
      out[i] /= sum;
    }
    return out;
  }

  /// Olasılıklara göre çekiliş; en olasılardan toplamı [topP]'yi
  /// aşmayanlar tutuluyor (en olası hamle her zaman dahil).
  @visibleForTesting
  static int sample(Float64List probabilities, double topP, math.Random random) {
    final order = List<int>.generate(probabilities.length, (i) => i)
      ..sort((a, b) => probabilities[b].compareTo(probabilities[a]));
    final kept = <int>[];
    var cumulative = 0.0;
    for (final i in order) {
      cumulative += probabilities[i];
      if (kept.isNotEmpty && cumulative > topP) break;
      kept.add(i);
    }
    final total = kept.fold<double>(0, (s, i) => s + probabilities[i]);
    var roll = random.nextDouble() * total;
    for (final i in kept) {
      roll -= probabilities[i];
      if (roll <= 0) return i;
    }
    return kept.last;
  }

  /// Testler için: isolate'i kapatır, bir sonraki istekte yeniden kurulur.
  @visibleForTesting
  void reset() {
    _worker?.close();
    _worker = null;
    _starting = null;
    _failed = false;
    _failure = null;
  }
}

/// Ağı tutan arka plan isolate'i.
class _MaiaWorker {
  final Isolate _isolate;
  final SendPort _requests;
  final ReceivePort _responses;
  final ReceivePort _exit = ReceivePort();
  final int history;
  final Map<int, Completer<Float64List>> _pending = {};
  int _nextId = 0;

  /// Isolate kapandı (bellek yetersizliği gibi); bir sonraki istekte
  /// yenisi kuruluyor.
  bool dead = false;

  /// Tek bir hamlenin en uzun süresi. Aşılırsa istek başarısız sayılıyor:
  /// oyun "motor cevap vermedi" diyor, sonsuza kadar beklemiyor.
  static const Duration timeout = Duration(seconds: 20);

  _MaiaWorker._(this._isolate, this._requests, this._responses, this.history) {
    _responses.listen(_onMessage);
    _isolate.addOnExitListener(_exit.sendPort);
    _exit.listen((_) {
      dead = true;
      _failAll('isolate kapandı');
    });
  }

  void _failAll(String reason) {
    for (final c in _pending.values) {
      c.completeError(StateError('maia: $reason'));
    }
    _pending.clear();
  }

  static Future<_MaiaWorker> spawn(Uint8List bytes) async {
    final boot = ReceivePort();
    final errors = ReceivePort();
    final isolate = await Isolate.spawn(
      _entry,
      [boot.sendPort, TransferableTypedData.fromList([bytes])],
      onError: errors.sendPort,
      errorsAreFatal: true,
    );
    final first = await Future.any<Object?>([
      boot.first,
      errors.first.then((e) => ['error', '$e']),
    ]);
    boot.close();
    errors.close();
    if (first is! List || first.isEmpty || first[0] != 'ready') {
      isolate.kill(priority: Isolate.immediate);
      throw StateError('maia: ağ kurulamadı: $first');
    }
    final responses = ReceivePort();
    (first[1] as SendPort).send(responses.sendPort);
    return _MaiaWorker._(isolate, first[1] as SendPort, responses, first[2] as int);
  }

  Future<Float64List> logits(
    Float32List board,
    int selfElo,
    int oppoElo,
    List<int> moves,
  ) {
    if (dead) return Future.error(StateError('maia: isolate kapalı'));
    final id = _nextId++;
    final completer = Completer<Float64List>();
    _pending[id] = completer;
    _requests.send([id, board, selfElo, oppoElo, moves]);
    return completer.future.timeout(timeout, onTimeout: () {
      _pending.remove(id);
      throw TimeoutException('maia: süre aşıldı', timeout);
    });
  }

  void _onMessage(Object? message) {
    if (message is! List || message.length < 2) return;
    final completer = _pending.remove(message[0]);
    if (completer == null) return;
    final result = message[1];
    if (result is Float64List) {
      completer.complete(result);
    } else {
      completer.completeError(StateError('maia: $result'));
    }
  }

  void close() {
    dead = true;
    _failAll('kapatıldı');
    _responses.close();
    _exit.close();
    _isolate.kill(priority: Isolate.immediate);
  }

  static void _entry(List<Object?> args) {
    final main = args[0] as SendPort;
    final MaiaNet net;
    try {
      final bytes =
          (args[1] as TransferableTypedData).materialize().asUint8List();
      net = MaiaNet(MaiaWeights.parse(bytes));
    } catch (e) {
      main.send(['error', '$e']);
      return;
    }
    final requests = ReceivePort();
    main.send(['ready', requests.sendPort, net.c.history]);
    SendPort? reply;
    requests.listen((message) {
      if (message is SendPort) {
        reply = message;
        return;
      }
      final m = message as List<Object?>;
      Object result;
      try {
        result = net.logits(
          m[1] as Float32List,
          m[2] as int,
          m[3] as int,
          (m[4] as List).cast<int>(),
        );
      } catch (e) {
        result = '$e';
      }
      reply?.send([m[0], result]);
    });
  }
}
