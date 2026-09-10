import 'package:flutter_test/flutter_test.dart';

import 'package:chess_pgn_reader/models/pgn_parser.dart';

/// 40 hamlelik gerçekçi bir oyun (Kasparov - Topalov, 1999 açılışı).
const _sampleMoves =
    '1. e4 d6 2. d4 Nf6 3. Nc3 g6 4. Be3 Bg7 5. Qd2 c6 6. f3 b5 7. Nge2 Nbd7 '
    '8. Bh6 Bxh6 9. Qxh6 Bb7 10. a3 e5 11. O-O-O Qe7 12. Kb1 a6 13. Nc1 O-O-O '
    '14. Nb3 exd4 15. Rxd4 c5 16. Rd1 Nb6 17. g3 Kb8 18. Na5 Ba8 19. Bh3 d5 '
    '20. Qf4+ Ka7 21. Rhe1 d4 22. Nd5 Nbxd5 23. exd5 Qd6 24. Rxd4 cxd4 '
    '25. Re7+ Kb6 26. Qxd4+ Kxa5 27. b4+ Ka4 28. Qc3 Qxd5 29. Ra7 Bb7 '
    '30. Rxb7 Qc4 31. Qxf6 Kxa3 32. Qxa6+ Kxb4 33. c3+ Kxc3 34. Qa1+ Kd2 '
    '35. Qb2+ Kd1 36. Bf1 Rd2 37. Rd7 Rxd7 38. Bxc4 bxc4 39. Qxh8 Rd3 '
    '40. Qa8 c3 41. Qa4+ Ke1 42. f4 f5 43. Kc1 Rd2 44. Qa7 1-0';

String _buildFile(int gameCount) {
  final buffer = StringBuffer();
  for (int i = 1; i <= gameCount; i++) {
    buffer
      ..writeln('[Event "Turnuva $i"]')
      ..writeln('[Site "Test"]')
      ..writeln('[Date "2026.01.0${i % 9 + 1}"]')
      ..writeln('[White "Beyaz $i"]')
      ..writeln('[Black "Siyah $i"]')
      ..writeln('[Result "1-0"]')
      ..writeln()
      ..writeln(_sampleMoves)
      ..writeln();
  }
  return buffer.toString();
}

void main() {
  test('tek oyun tam okunur', () {
    final games = PgnParser.parseAll(_buildFile(1));
    expect(games.length, 1);
    // 44 tam hamle = 87 yarım hamle (son hamle beyazın).
    expect(games.first.uciMoves.length, 87);
    expect(games.first.result, '1-0');
  });

  test('parça parça okuma aynı sonucu verir', () async {
    final text = _buildFile(12);
    int lastDone = 0;
    int lastTotal = 0;
    final games = await PgnParser.parseAllAsync(
      text,
      onProgress: (done, total) {
        lastDone = done;
        lastTotal = total;
      },
    );
    expect(games.length, 12);
    expect(lastDone, 12);
    expect(lastTotal, 12);
    expect(games.map((g) => g.uciMoves).toList(),
        PgnParser.parseAll(text).map((g) => g.uciMoves).toList());
  });

  test('büyük dosya ölçeği', () {
    for (final count in [10, 100, 500]) {
      final text = _buildFile(count);
      final watch = Stopwatch()..start();
      final games = PgnParser.parseAll(text);
      watch.stop();

      expect(games.length, count);
      expect(games.last.uciMoves.length, 87);

      final kb = (text.length / 1024).round();
      // ignore: avoid_print
      print('$count oyun · $kb KB · ${watch.elapsedMilliseconds} ms · '
          '${(watch.elapsedMilliseconds / count).toStringAsFixed(1)} ms/oyun');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
