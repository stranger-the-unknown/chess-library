import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:chess_pgn_reader/models/chess_engine.dart' as rules;
import 'package:chess_pgn_reader/models/move_entry.dart';
import 'package:chess_pgn_reader/services/engine/engine_service.dart';
import 'package:chess_pgn_reader/services/game_review.dart';
import 'package:chess_pgn_reader/services/engine/stockfish_engine.dart';

/// Stockfish adaptörünü gerçek motorla sınar.
///
/// Motor yerel bir kütüphane olduğu için düz `flutter test` altında
/// yüklenemiyor; bu dosya varsayılan olarak atlanır. Çalıştırmak için
/// kütüphanenin bulunduğu klasör PATH'e eklenip `SF_TEST=1` verilmeli:
///
/// ```
/// PATH="build/windows/x64/runner/Release:$PATH" SF_TEST=1 \
///   flutter test test/stockfish_test.dart
/// ```
final bool _enabled = Platform.environment['SF_TEST'] == '1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Stockfish', () {
    tearDownAll(() async {
      if (_enabled) await StockfishEngine.instance.dispose();
    });

    test('başlangıç pozisyonunu makul derinlikte inceler', () async {
      final result = await EngineService.instance.analyze(
        'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
        depth: 30,
        movetimeMs: 400,
      );
      expect(result.bestMoveUci, isNotEmpty);
      // Eski Dart motoru aynı bütçede 6,5 yarım hamle görüyordu.
      expect(result.depth, greaterThan(10));
      expect(result.pvUci, isNotEmpty);
    });

    test('zorunlu matı görür', () async {
      final result = await EngineService.instance.analyze(
        '1Q6/8/8/8/8/k2K4/8/8 w - - 0 1',
        depth: 30,
        movetimeMs: 400,
      );
      expect(result.mateIn, isNotNull);
      expect(result.mateIn, lessThanOrEqualTo(2));
    });

    test('mat edilmiş pozisyonda oyun bittiğini bildirir', () async {
      final result = await EngineService.instance.analyze(
        'rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3',
        depth: 20,
        movetimeMs: 300,
      );
      expect(result.isGameOver, isTrue);
      expect(result.bestMoveUci, isEmpty);
    });

    test('kural dışı pozisyon motoru çökertmez', () async {
      // Paketin kendi uyarısı: geçersiz pozisyon programı çökertiyor.
      // Kural motorumuz kapıda duruyor, istek motora hiç ulaşmıyor.
      final result = await EngineService.instance.analyze('bu bir fen değil');
      expect(result.isGameOver, isTrue);
      expect(result.bestMoveUci, isEmpty);

      // Motor bundan sonra hâlâ çalışmalı.
      final after = await EngineService.instance.analyze(
        'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
        depth: 12,
        movetimeMs: 200,
      );
      expect(after.bestMoveUci, isNotEmpty);
    });

    test('istekler sıraya girer, sonuçlar karışmaz', () async {
      // UCI tek kanal; iki arama aynı anda gönderilirse sonuçlar
      // birbirine karışır.
      const mate = '1Q6/8/8/8/8/k2K4/8/8 w - - 0 1';
      const start = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
      final results = await Future.wait([
        EngineService.instance.analyze(mate, depth: 20, movetimeMs: 300),
        EngineService.instance.analyze(start, depth: 20, movetimeMs: 300),
      ]);
      expect(results[0].mateIn, isNotNull, reason: 'mat pozisyonu');
      expect(results[1].mateIn, isNull, reason: 'başlangıç pozisyonu');
    });

    test('seviyeler farklı güçte oynar', () async {
      const fen = 'r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5Q2/PPPP1PPP/RNB1K1NR w KQkq - 4 4';
      for (final level in [EngineLevel.all.first, EngineLevel.all.last]) {
        final result = await EngineService.instance.bestMoveForLevel(fen, level);
        expect(result.bestMoveUci, isNotEmpty,
            reason: '${level.approximateElo} Elo seviyesi hamle üretmeli');
      }
      // Tam güç seviyesi bu pozisyonda mat görmeli (Scholar's mate).
      final strong = await EngineService.instance
          .bestMoveForLevel(fen, EngineLevel.all.last);
      expect(strong.bestMoveUci, 'f3f7');
    });

    test('oyun incelemesi vahim hatayı yakalar', () async {
      // Scholar's mate: 3...Nf6?? veziri f7'ye davet ediyor. İnceleme bu
      // hamleyi vahim hata saymalı. Eski motor 6-8 yarım hamlelik
      // görüşüyle bu tür etiketleri bazen kaçırıyordu.
      const moves = ['e4', 'e5', 'Bc4', 'Nc6', 'Qh5', 'Nf6', 'Qxf7'];
      final board = rules.ChessGame();
      final history = <MoveEntry>[];
      for (final san in moves) {
        final move = board.allLegalMoves().firstWhere(
            (m) => board.sanFor(m).replaceAll(RegExp(r'[+#]'), '') == san);
        final text = board.sanFor(move);
        board.makeMove(move);
        history.add(MoveEntry(move: move, san: text, fenAfter: board.fen));
      }

      final watch = Stopwatch()..start();
      final review = await GameReviewer().review(history);
      watch.stop();

      expect(review.moves, hasLength(moves.length));
      final blunder = review.moves[5]; // 3...Nf6
      expect(blunder.quality, MoveQuality.blunder,
          reason: 'mat yedirten hamle vahim hata olmalı');
      // Siyahın doğruluğu beyazınkinden belirgin düşük olmalı.
      expect(review.blackAccuracy, lessThan(review.whiteAccuracy));

      stdout.writeln('inceleme · ${history.length + 1} pozisyon · '
          '${watch.elapsedMilliseconds} ms · '
          'beyaz %${review.whiteAccuracy.toStringAsFixed(0)} · '
          'siyah %${review.blackAccuracy.toStringAsFixed(0)}');
    }, timeout: const Timeout(Duration(minutes: 2)));
  },
      skip: _enabled
          ? false
          : 'Stockfish yerel kütüphanesi gerekiyor: SF_TEST=1 ve PATH');
}
