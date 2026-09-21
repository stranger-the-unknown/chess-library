import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:chess_pgn_reader/services/engine/engine_service.dart';
import 'package:chess_pgn_reader/services/engine/stockfish_uci.dart';

/// Arama iptali motoru öldürmemeli.
///
/// Eskiden `stopSearch()` bekleyen aramayı doğrudan `null` ile kapatıyor,
/// çağıran da bunu çökme sayıp süreci yeniden kuruyordu: canlı analiz
/// açıkken kesilen her aramada Stockfish kapanıp açılıyordu. Motor `stop`
/// komutundan sonra kendi `bestmove` satırını gönderiyor; artık o
/// bekleniyor.
///
/// Bu testler gerçek Stockfish ikilisiyle çalışır; ikili yoksa atlanır
/// (CI ve ikilisiz makineler için).

const _endgame = '8/8/8/8/8/4k3/4P3/4K3 w - - 0 1';
const _start =
    'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

void main() {
  late String? binary;

  setUpAll(() async {
    StockfishUci.cachedBinaryPath = null;
    binary = await StockfishUci.resolveBinaryPath();
  });

  tearDown(() async {
    StockfishUci.cachedBinaryPath = null;
    await EngineService.instance.dispose();
  });

  test('iptal edilen arama süreci öldürmüyor', () async {
    if (binary == null) {
      markTestSkipped('Stockfish ikilisi yok');
      return;
    }
    final sf = StockfishUci();
    expect(await sf.start(), isTrue);
    final pid = sf.processId;
    expect(pid, isNotNull);

    // Uzun bir arama başlat, sonra yarıda kes.
    final search = sf.analyze(_start, depth: 30, movetimeMs: 8000);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(sf.hasActiveSearch, isTrue, reason: 'arama başlamadı');

    await sf.stopSearch();
    final cancelled = await search;

    expect(
      sf.isRunning,
      isTrue,
      reason: 'iptal süreci öldürmemeli',
    );
    expect(
      sf.processId,
      pid,
      reason: 'süreç yeniden kurulmuş: iptal çökme sayılıyor',
    );
    expect(
      cancelled,
      isNotNull,
      reason: 'iptal edilen arama null dönerse çağıran yeniden kurar',
    );

    // Aynı süreçle yeni arama doğru sonucu vermeli.
    final next = await sf.analyze(_endgame, depth: 20, movetimeMs: 600);
    expect(next, isNotNull);
    // Berabere biten bu konumda iki şah hamlesi de eşdeğer; çok
    // çekirdekli arama hangisini döndüreceği konusunda belirlenimci
    // değil (fallback testi de ikisini birden kabul ediyor).
    expect(next!.bestMoveUci, anyOf('e1f1', 'e1d1'));
    expect(sf.processId, pid, reason: 'ikinci arama süreci değiştirmiş');

    await sf.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('EngineService: iptalden sonra analiz çalışmaya devam ediyor',
      () async {
    if (binary == null) {
      markTestSkipped('Stockfish ikilisi yok');
      return;
    }
    final service = EngineService.instance;

    // Arka planda uzun bir analiz; hemen kesiliyor (hamle değişmiş gibi).
    final pending = service.analyze(_start, depth: 30, movetimeMs: 8000);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await service.stopAnalysis();
    await pending;

    final result = await service.analyze(_endgame, depth: 20, movetimeMs: 600);
    expect(
      result.bestMoveUci,
      anyOf('e1f1', 'e1d1'),
      reason: 'iptalden sonra motor kullanılamaz hâle geldi',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('asılı kalan aramada eski davranış: süreç yeniden kuruluyor',
      () async {
    // Motor yokken iptal beklemede takılmamalı; emniyet süresi dolunca
    // null dönüp çağıranın yeniden kurmasına izin veriyor.
    StockfishUci.cachedBinaryPath =
        '${Directory.systemTemp.path}/chesslib-yok-sf';
    final sf = StockfishUci();
    expect(await sf.start(), isFalse);
    await sf.stopSearch(); // takılmadan dönmeli
    expect(sf.hasActiveSearch, isFalse);
    await sf.dispose();
  });

  group('Motor kaynakları', () {
    test('analiz masaüstünde çok çekirdek ister, telefonda bir', () {
      final threads = EngineService.analysisThreads;
      if (Platform.isAndroid || Platform.isIOS) {
        expect(threads, 1, reason: 'telefonda pil için tek çekirdek');
      } else {
        expect(threads, inInclusiveRange(1, 4));
        if (Platform.numberOfProcessors >= 4) {
          expect(threads, greaterThan(1),
              reason: 'masaüstünde analiz tek çekirdekte kalmış');
        }
      }
    });

    test('oyun hamlesi tek çekirdek, analiz masaüstü ayarı', () async {
      if (binary == null) {
        markTestSkipped('Stockfish ikilisi yok');
        return;
      }
      final sf = StockfishUci();
      expect(await sf.start(), isTrue);

      // Oyun yolu: kademe ne olursa olsun tek çekirdek.
      await sf.analyze(_endgame, depth: 6, movetimeMs: 200, skillLevel: 5,
          limitStrength: true);
      expect(sf.appliedThreads, 1,
          reason: 'oyun hamlesi çok çekirdek kullanırsa kademeler cihaza göre '
              'farklı güçte olur');

      // Analiz yolu: masaüstünde daha fazlası.
      await sf.analyze(_endgame,
          depth: 12,
          movetimeMs: 300,
          threads: EngineService.analysisThreads,
          hashMb: EngineService.analysisHashMb);
      expect(sf.appliedThreads, EngineService.analysisThreads);

      await sf.dispose();
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
