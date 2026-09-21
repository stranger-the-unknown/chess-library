import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:chess_pgn_reader/services/engine/engine_coordinator.dart';
import 'package:chess_pgn_reader/services/engine/search_result.dart';

/// Tek motorun sahipliği.
///
/// 9.0.3–9.0.9 arasında beş ayrı hata aynı kökten geldi: analiz, ipucu ve
/// motorun kendi hamlesi aynı Stockfish'i paylaşıyor ve her yeni istek
/// önceki aramayı kesiyordu. Burada kural motordan bağımsız olarak
/// doğrulanıyor: gerçek süreç yok, işler elle tutuluyor.

/// Sonucu elle verilen sahte arama.
class _Job {
  final Completer<SearchResult> gate = Completer<SearchResult>();
  bool started = false;

  Future<SearchResult> run() {
    started = true;
    return gate.future;
  }
}

SearchResult _result(String best) => SearchResult(
      bestMoveUci: best,
      scoreCp: 0,
      depth: 1,
      nodes: 1,
      pvUci: [best],
    );

/// Kuyruğun mikro görevlerini işlet.
Future<void> _settle() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late int stops;
  late EngineCoordinator coordinator;

  setUp(() {
    stops = 0;
    coordinator = EngineCoordinator(stopSearch: () async => stops++);
  });

  test('analiz motorun hamlesini kesmiyor, sırasını bekliyor', () async {
    final play = _Job();
    final playFuture = coordinator.submit(EngineJobKind.play, play.run);
    await _settle();
    expect(play.started, isTrue);

    final analysis = _Job();
    final analysisFuture =
        coordinator.submit(EngineJobKind.analysis, analysis.run);
    await _settle();

    expect(analysis.started, isFalse,
        reason: 'analiz motorun hamlesini beklemeli');
    expect(stops, 0, reason: 'motorun aramasına stop gönderilmemeli');

    play.gate.complete(_result('e2e4'));
    await _settle();

    expect((await playFuture).bestMoveUci, 'e2e4');
    expect(analysis.started, isTrue, reason: 'sıra analize gelmeli');

    analysis.gate.complete(_result('d2d4'));
    expect((await analysisFuture).bestMoveUci, 'd2d4');
  });

  test('motorun hamlesi süren analizi kesiyor', () async {
    final analysis = _Job();
    final analysisFuture =
        coordinator.submit(EngineJobKind.analysis, analysis.run);
    await _settle();
    expect(analysis.started, isTrue);

    final play = _Job();
    final playFuture = coordinator.submit(EngineJobKind.play, play.run);
    await _settle();

    expect(stops, 1, reason: 'analiz durdurulmalı');
    expect(play.started, isFalse, reason: 'motor, duran aramayı bekler');

    // Stockfish `stop` sonrası kendi sonucunu gönderir.
    analysis.gate.complete(_result('a2a3'));
    await _settle();

    final dropped = await analysisFuture;
    expect(dropped.cancelled, isTrue,
        reason: 'kesilen arama "iptal" olarak dönmeli');
    expect(dropped.bestMoveUci, isEmpty);

    expect(play.started, isTrue);
    play.gate.complete(_result('g1f3'));
    expect((await playFuture).bestMoveUci, 'g1f3');
  });

  test('aynı türden yeni istek bekleyenin yerine geçiyor', () async {
    final running = _Job();
    coordinator.submit(EngineJobKind.analysis, running.run);
    await _settle();

    final first = _Job();
    final firstFuture = coordinator.submit(EngineJobKind.analysis, first.run);
    final second = _Job();
    final secondFuture = coordinator.submit(EngineJobKind.analysis, second.run);
    await _settle();

    expect((await firstFuture).cancelled, isTrue,
        reason: 'eski konumun analizini çalıştırmanın anlamı yok');
    expect(first.started, isFalse);

    running.gate.complete(_result('a2a3'));
    await _settle();

    expect(second.started, isTrue);
    second.gate.complete(_result('b2b3'));
    expect((await secondFuture).bestMoveUci, 'b2b3');
  });

  test('ipucu analizden önce, oyun hamlesinden sonra çalışıyor', () async {
    final play = _Job();
    coordinator.submit(EngineJobKind.play, play.run);
    await _settle();

    final analysis = _Job();
    coordinator.submit(EngineJobKind.analysis, analysis.run);
    final hint = _Job();
    coordinator.submit(EngineJobKind.hint, hint.run);
    await _settle();

    expect(analysis.started, isFalse);
    expect(hint.started, isFalse);

    play.gate.complete(_result('e2e4'));
    await _settle();

    expect(hint.started, isTrue, reason: 'ipucu analizin önünde');
    expect(analysis.started, isFalse);

    hint.gate.complete(_result('d2d4'));
    await _settle();
    expect(analysis.started, isTrue);
  });

  test('analizi iptal etmek motorun hamlesine dokunmuyor', () async {
    final play = _Job();
    final playFuture = coordinator.submit(EngineJobKind.play, play.run);
    await _settle();

    final analysis = _Job();
    final analysisFuture =
        coordinator.submit(EngineJobKind.analysis, analysis.run);
    await _settle();

    await coordinator.cancel(EngineJobKind.analysis);
    await _settle();

    expect(stops, 0, reason: 'çalışan iş analiz değil, ona stop gitmemeli');
    expect((await analysisFuture).cancelled, isTrue);

    play.gate.complete(_result('e2e4'));
    expect((await playFuture).bestMoveUci, 'e2e4',
        reason: 'motorun hamlesi iptalden etkilenmemeli');
  });

  test('süren analiz iptal edilince durduruluyor', () async {
    final analysis = _Job();
    final analysisFuture =
        coordinator.submit(EngineJobKind.analysis, analysis.run);
    await _settle();

    await coordinator.cancel(EngineJobKind.analysis);
    expect(stops, 1);

    analysis.gate.complete(_result('a2a3'));
    expect((await analysisFuture).cancelled, isTrue);
  });
}
