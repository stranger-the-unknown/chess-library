import 'dart:async';

import 'search_result.dart';

/// Motordan ne istendiği. Öncelik: [play] > [hint] > [analysis].
///
/// Sıralama bir tercih değil, geçmişte tekrar tekrar kırılan bir kural:
/// motorun **kendi hamlesi** hiçbir şey tarafından kesilmemeli. Analiz en
/// kolay feda edilendir; konum değişince zaten baştan istenir.
enum EngineJobKind { play, hint, analysis }

int _priority(EngineJobKind kind) => switch (kind) {
      EngineJobKind.play => 3,
      EngineJobKind.hint => 2,
      EngineJobKind.analysis => 1,
    };

class _EngineJob {
  _EngineJob(this.kind, this.run);

  final EngineJobKind kind;
  final Future<SearchResult> Function() run;
  final Completer<SearchResult> completer = Completer<SearchResult>();

  /// Başka bir istek yüzünden kesildi; sonucu çağırana verilmeyecek.
  bool superseded = false;

  void finish(SearchResult result) {
    if (!completer.isCompleted) completer.complete(result);
  }
}

/// Tek Stockfish sürecinin sahibi.
///
/// Uygulamada tek bir motor var ve ona üç yerden istek geliyor: motorun
/// kendi hamlesi, canlı analiz ve ipucu. Eskiden her çağıran motoru
/// doğrudan kullanıyordu ve `analyze()` işe başlarken süren aramayı
/// kesiyordu. Sonuç: analizi açmak/kapatmak motorun hamlesini yarıda
/// kesiyor, ipucu analizin sonucunu eziyor, iptal edilen arama "motor
/// cevap vermedi" sanılıyordu. 9.0.3'ten 9.0.9'a kadar bu ailenin
/// beş ayrı üyesi tek tek yamandı.
///
/// Burada istekler tek sıraya giriyor:
///
/// * aynı anda yalnızca bir arama çalışır;
/// * daha yüksek öncelikli bir istek geleni keser (analiz, oyun hamlesini
///   **kesemez**; tersi olur);
/// * aynı türden ikinci bir istek beklemedekinin yerine geçer (eski konumun
///   analizini çalıştırmanın anlamı yok);
/// * kesilen isteğin sonucu [SearchResult.superseded] olarak döner, yani
///   çağıran "motor cevap veremedi" ile "benim isteğim düştü" arasındaki
///   farkı görebilir.
class EngineCoordinator {
  EngineCoordinator({required this.stopSearch});

  /// Süren aramayı durdurur (motor süreci kapanmaz).
  final Future<void> Function() stopSearch;

  _EngineJob? _running;
  final Map<EngineJobKind, _EngineJob> _queued = {};

  bool get isBusy => _running != null || _queued.isNotEmpty;

  /// Çalışan işin türü; boştaysa `null`.
  EngineJobKind? get runningKind => _running?.kind;

  Future<SearchResult> submit(
    EngineJobKind kind,
    Future<SearchResult> Function() run,
  ) {
    final job = _EngineJob(kind, run);
    final running = _running;

    if (running == null) {
      _start(job);
      return job.completer.future;
    }

    // Aynı türden bekleyen varsa yenisi onun yerine geçer.
    _queued.remove(kind)?.finish(SearchResult.superseded);
    _queued[kind] = job;

    final preempt =
        kind == running.kind || _priority(kind) > _priority(running.kind);
    if (preempt) {
      running.superseded = true;
      unawaited(stopSearch());
    }
    return job.completer.future;
  }

  /// Bu türdeki bekleyen ve süren işleri iptal eder.
  ///
  /// Oyun hamlesine dokunmaz: ekranlar "analizi kapat" derken motorun
  /// hamlesini de kesiyordu.
  Future<void> cancel(EngineJobKind kind) async {
    _queued.remove(kind)?.finish(SearchResult.superseded);
    final running = _running;
    if (running != null && running.kind == kind) {
      running.superseded = true;
      await stopSearch();
    }
  }

  void _start(_EngineJob job) {
    _running = job;
    job.run().then(
      (result) => _complete(job, result),
      onError: (_) => _complete(job, SearchResult.empty),
    );
  }

  void _complete(_EngineJob job, SearchResult result) {
    if (identical(_running, job)) _running = null;
    job.finish(job.superseded ? SearchResult.superseded : result);
    _pump();
  }

  void _pump() {
    if (_running != null || _queued.isEmpty) return;
    final kind = _queued.keys.reduce(
      (a, b) => _priority(a) >= _priority(b) ? a : b,
    );
    final job = _queued.remove(kind)!;
    _start(job);
  }

  /// `dart:async`'ın `unawaited`'ı yalnızca bunun için içe aktarılmasın.
  static void unawaited(Future<void> future) {
    future.catchError((_) {});
  }
}
