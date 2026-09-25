import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:chess_pgn_reader/models/chess_engine.dart' as engine;
import 'package:chess_pgn_reader/services/engine/maia/maia_encoder.dart';
import 'package:chess_pgn_reader/services/engine/maia/maia_net.dart';
import 'package:chess_pgn_reader/services/engine/maia/maia_player.dart';

/// Maia-3'ün Dart ile yeniden yazılmış ağı, orijinal Python modeliyle
/// aynı olasılıkları üretmeli.
///
/// Referans: `tools/maia_reference.py` (orijinal kod, 16 bite yuvarlanmış
/// ağırlıklar). Ağırlık dosyası depoda değil (`tools/maia_export.py` ile
/// üretiliyor); yoksa test atlanır.
const _weights = 'assets/maia/maia3-5m.bin';

/// Yasal hamleler üzerinde softmax; UCI → olasılık.
Map<String, double> _probabilities(
  MaiaNet net,
  List<engine.ChessGame> boards,
  int selfElo,
  int oppoElo,
) {
  final current = boards.last;
  final legal = current.allLegalMoves();
  final indices = [
    for (final move in legal) MaiaEncoder.moveIndex(move, current.sideToMove),
  ];
  final logits = net.logits(
    MaiaEncoder.encode(boards, net.c.history),
    selfElo,
    oppoElo,
    indices,
  );
  final max = logits.reduce(math.max);
  final exps = [for (final l in logits) math.exp(l - max)];
  final sum = exps.fold<double>(0, (a, b) => a + b);
  return {
    for (var i = 0; i < legal.length; i++) legal[i].uci: exps[i] / sum,
  };
}

/// Yalnızca başlık ve manifest; tensör yok.
Uint8List _manifestOnly({required int heads}) {
  final manifest = utf8.encode(jsonEncode({
    'dtype': 'f16',
    'config': {
      'history': 8,
      'dim_emb': 128,
      'dim_vit': 256,
      'head_hid_dim': 256,
      'num_heads': heads,
      'num_blocks': 8,
      'mlp_dim': 512,
      'gab_gen_size': 64,
      'gab_intermediate_dim': 64,
      'elo_upper': 5000,
      'rms_eps': 1.1920929e-07,
      'ln_eps': 1e-5,
    },
    'tensors': [],
  }));
  final header = ByteData(12);
  const magic = 'MAIA3W01';
  for (var i = 0; i < 8; i++) {
    header.setUint8(i, magic.codeUnitAt(i));
  }
  header.setUint32(8, manifest.length, Endian.little);
  return Uint8List.fromList([...header.buffer.asUint8List(), ...manifest]);
}

void main() {
  final available = File(_weights).existsSync();

  test('orijinal modelle aynı hamle olasılıkları', () {
    final net = MaiaNet(MaiaWeights.parse(File(_weights).readAsBytesSync()));
    final fixture = jsonDecode(
      File('test/fixtures/maia3_reference.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final cases = fixture['cases'] as List;

    var worst = 0.0;
    var worstCase = '';
    final watch = Stopwatch()..start();
    for (final raw in cases) {
      final c = raw as Map<String, dynamic>;
      final boards = [
        for (final fen in c['history'] as List)
          engine.ChessGame.fromFen(fen as String),
      ];
      final mine = _probabilities(
        net,
        boards,
        c['selfElo'] as int,
        c['oppoElo'] as int,
      );
      for (final entry in c['moves'] as List) {
        final uci = entry[0] as String;
        final expected = (entry[1] as num).toDouble();
        final got = mine[uci];
        expect(got, isNotNull, reason: '$uci yasal sayılmadı: ${boards.last.fen}');
        final diff = (got! - expected).abs();
        if (diff > worst) {
          worst = diff;
          worstCase = '${boards.last.fen} $uci $got / $expected';
        }
      }
    }
    watch.stop();
    // ignore: avoid_print
    print('maia: ${cases.length} konum, en büyük fark '
        '${worst.toStringAsFixed(6)} ($worstCase), konum başına '
        '${(watch.elapsedMilliseconds / cases.length).toStringAsFixed(1)} ms');
    expect(worst, lessThan(2e-3));
  }, skip: available ? false : 'ağırlık dosyası yok (tools/maia_export.py)');

  group('MaiaPlayer', () {
    const start = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
    // 1.e4 e5 2.Vh5 Ac6 3.Fc4 Af6?? — Vxf7# var.
    const mateFen =
        'r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4';

    setUp(() {
      MaiaPlayer.instance.reset();
      MaiaPlayer.loadBytes = () async => File(_weights).readAsBytesSync();
    });
    tearDown(() => MaiaPlayer.instance.reset());

    test('arka planda yasal bir hamle seçiyor', () async {
      final move = await MaiaPlayer.instance.move([start], 1500);
      expect(move, isNotNull);
      final legal = engine.ChessGame.fromFen(start)
          .allLegalMoves()
          .map((m) => m.uci)
          .toSet();
      expect(legal, contains(move!.uci));
      expect(move.probability, greaterThan(0));
    }, skip: available ? false : 'ağırlık dosyası yok');

    test('aynı konumda hep aynı hamleyi oynamıyor, mat fırsatını çoğunlukla '
        'görüyor', () async {
      final random = math.Random(5);
      final openings = <String>{};
      for (var i = 0; i < 30; i++) {
        openings.add((await MaiaPlayer.instance
                .move([start], 1500, random: random))!
            .uci);
      }
      expect(openings.length, greaterThan(1));

      var mates = 0;
      for (var i = 0; i < 20; i++) {
        final move = await MaiaPlayer.instance
            .move([mateFen], 1900, random: random);
        if (move!.uci == 'h5f7') mates++;
      }
      // Model 1900'de matı ~%86 olasılıkla oynuyor.
      expect(mates, greaterThanOrEqualTo(12));
    }, skip: available ? false : 'ağırlık dosyası yok');

    test('ağırlık dosyası yoksa çökmüyor, null dönüyor', () async {
      MaiaPlayer.loadBytes = () async => throw const FileSystemException('yok');
      expect(await MaiaPlayer.instance.move([start], 1500), isNull);
      expect(MaiaPlayer.instance.unavailable, isTrue);
    });

    test('bozuk ağırlık dosyası çökertmiyor', () async {
      MaiaPlayer.loadBytes = () async => Uint8List.fromList(List.filled(64, 7));
      expect(await MaiaPlayer.instance.move([start], 1500), isNull);
      expect(MaiaPlayer.instance.unavailable, isTrue);
    });

    test('uzun oyunda yalnızca son konumlar okunuyor', () async {
      // Ağ son sekiz konuma bakıyor; daha eskisi hiç çözümlenmemeli
      // (her hamlede bütün oyunu okumak boşa iş). Eski ve okunamayan
      // bir konum bu yüzden hamleyi engellememeli.
      final history = [
        'bozuk',
        for (var i = 0; i < 20; i++) start,
      ];
      final move = await MaiaPlayer.instance.move(history, 1500);
      expect(move, isNotNull);
    }, skip: available ? false : 'ağırlık dosyası yok');

    test('tensörü eksik dosya kullanılmıyor, Stockfish oynuyor',
        () async {
      // Başlığı ve manifesti doğru ama ağırlıkları eksik bir dosya.
      // Eskiden ağ kuruluyor, her hamlede hata verip "motor cevap
      // vermedi" diyecekti; artık kurulmuyor, Maia kullanılamaz sayılıyor.
      MaiaPlayer.loadBytes = () async => _manifestOnly(heads: 8);
      expect(await MaiaPlayer.instance.move([start], 1500), isNull);
      expect(MaiaPlayer.instance.unavailable, isTrue);
    });

    test('dörde bölünmeyen boyutlar reddediliyor', () {
      // Dörtlü vektör döngüleri kalanı atlardı: sessizce yanlış sonuç.
      expect(
        () => MaiaNet(MaiaWeights.parse(_manifestOnly(heads: 16))),
        throwsFormatException,
      );
    });

    test('çekilişte en uçtaki hamleler atılıyor', () {
      // Orijinal koddaki gibi: toplam olasılığı eşiği aşan hamle de
      // dışarıda (0,5 + 0,3 + 0,1 = 0,9 ≤ 0,95; dördüncüyle 1,0).
      final probabilities = Float64List.fromList([0.5, 0.3, 0.1, 0.1]);
      final random = math.Random(1);
      final seen = <int>{};
      for (var i = 0; i < 2000; i++) {
        seen.add(MaiaPlayer.sample(probabilities, 0.95, random));
      }
      expect(seen, {0, 1, 2}, reason: 'kuyruktaki hamle hiç seçilmemeli');
    });
  });
}
