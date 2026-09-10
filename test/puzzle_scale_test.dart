import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/models/chess_engine.dart' as engine;
import 'package:chess_pgn_reader/services/puzzle_service.dart';

/// Toplu FEN aktarımının ölçeği.
///
/// Kullanıcı bir listeye binlerce pozisyon ekleyebilir. Burada hem sürenin
/// makul kaldığı hem de sonucun eksiksiz yazılıp geri okunabildiği
/// doğrulanır.

/// Gerçekten geçerli, birbirinden farklı FEN'ler üretir.
///
/// İki şah ve bir beyaz kale gezdirilir; şahların bitişik olduğu ya da
/// kareleri çakışan diziliş atlanır. Bu, on binlerce farklı ve kurallara
/// uygun pozisyon vermeye yeter.
List<String> _fens(int count) {
  const files = 'abcdefgh';
  String name(int sq) => '${files[sq % 8]}${sq ~/ 8 + 1}';
  bool adjacent(int a, int b) =>
      (a % 8 - b % 8).abs() <= 1 && (a ~/ 8 - b ~/ 8).abs() <= 1;

  final out = <String>[];
  for (int wk = 0; wk < 64 && out.length < count; wk++) {
    for (int bk = 0; bk < 64 && out.length < count; bk++) {
      if (wk == bk || adjacent(wk, bk)) continue;
      for (int r = 0; r < 64 && out.length < count; r++) {
        if (r == wk || r == bk || adjacent(r, bk)) continue;
        final board = _emptyBoardWith({
          name(wk): 'K',
          name(bk): 'k',
          name(r): 'R',
        });
        final fen = '$board w - - 0 1';
        if (engine.ChessGame.validateFen(fen) == null) out.add(fen);
      }
    }
  }
  return out;
}

String _emptyBoardWith(Map<String, String> pieces) {
  final rows = <String>[];
  for (int rank = 8; rank >= 1; rank--) {
    final cells = List<String>.filled(8, '');
    pieces.forEach((square, symbol) {
      if (int.parse(square[1]) == rank) {
        cells[square.codeUnitAt(0) - 97] = symbol;
      }
    });
    final buffer = StringBuffer();
    int gap = 0;
    for (final cell in cells) {
      if (cell.isEmpty) {
        gap++;
      } else {
        if (gap > 0) buffer.write(gap);
        gap = 0;
        buffer.write(cell);
      }
    }
    if (gap > 0) buffer.write(gap);
    rows.add(buffer.toString());
  }
  return rows.join('/');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PuzzleService.instance.debugReset();
  });

  test('üretilen FEN\'ler geçerli ve benzersiz', () {
    final fens = _fens(600);
    expect(fens.length, 600);
    expect(fens.toSet().length, 600);
    for (final fen in fens.take(50)) {
      expect(engine.ChessGame.validateFen(fen), isNull);
    }
  });

  test('büyük FEN listesi ölçeği', () async {
    final service = PuzzleService.instance;

    for (final count in [500, 2000, 8000]) {
      SharedPreferences.setMockInitialValues({});
      service.debugReset();

      final collection = await service.createCollection('Ölçek $count');
      final text = _fens(count).join('\n');

      int lastDone = 0;
      int reports = 0;
      final watch = Stopwatch()..start();
      final added = await service.importFens(
        collection,
        text,
        onProgress: (done, total) {
          expect(total, count);
          expect(done, greaterThanOrEqualTo(lastDone));
          lastDone = done;
          reports++;
        },
      );
      watch.stop();

      expect(added, count);
      expect(lastDone, count, reason: 'ilerleme sonuna kadar bildirilmeli');
      expect(reports, greaterThan(1), reason: 'ilerleme çubuğu beslenmeli');

      // Geri okuma: liste diskten tazelenince aynı sayıda bulmaca gelmeli.
      service.debugReset();
      final reloaded = (await service.collections())
          .firstWhere((c) => c.name == 'Ölçek $count');
      final puzzles = await service.puzzlesOf(reloaded);
      expect(puzzles.length, count);

      // ignore: avoid_print
      print('$count bulmaca · ${(text.length / 1024).round()} KB · '
          '${watch.elapsedMilliseconds} ms · '
          '${(watch.elapsedMicroseconds / count / 1000).toStringAsFixed(2)}'
          ' ms/bulmaca');
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('dışa aktarılan metin aynen geri okunur', () async {
    final service = PuzzleService.instance;
    final source = await service.createCollection('Kaynak');
    await service
        .importFens(source, _fens(120).join('\n'), tags: ['deneme', 'mat']);

    final text = await service.exportText(source);
    final target = await service.createCollection('Hedef');
    final added = await service.importFens(target, text);

    expect(added, 120, reason: 'başlık satırları atlanmalı');
    final back = await service.puzzlesOf(target);
    final original = await service.puzzlesOf(source);
    expect(back.length, original.length);
    expect(back.first.fen, original.first.fen);
    expect(back.first.tags, original.first.tags);
  });

  test('eski sürümden kalan gömülü listeler düşürülür', () async {
    // Önceki sürümde uygulamayla üç bulmaca kitabı geliyordu. Ayarlarda
    // kalan bu kayıtlar, varlık dosyaları artık pakette olmadığı için
    // liste ekranını kilitliyordu.
    SharedPreferences.setMockInitialValues({
      'puzzle_collections_v1':
          '[{"id":"endgames","name":"Oyun Sonları",'
              '"asset":"assets/puzzles/endgames.txt"},'
              '{"id":"mates","name":"Matlar",'
              '"asset":"assets/puzzles/mates.txt"},'
              '{"id":"u_1","name":"Kendi listem"}]',
    });
    PuzzleService.instance.debugReset();

    final all = await PuzzleService.instance.collections();
    expect(all.map((c) => c.id), ['u_1'],
        reason: 'yalnızca kullanıcının kendi listesi kalmalı');

    // Temizlik kalıcı olmalı: servis soğuk başlasa da aynı sonuç.
    PuzzleService.instance.debugReset();
    final again = await PuzzleService.instance.collections();
    expect(again.map((c) => c.id), ['u_1']);
  });

  test('bozuk satırlar sessizce atlanır', () async {
    final service = PuzzleService.instance;
    final collection = await service.createCollection('Karışık');
    final good = _fens(3);
    final text = [
      '# yorum satırı',
      '',
      good[0],
      'bu bir fen değil',
      '8/8/8/8/8/8/8/8 w - - 0 1', // şahsız: geçersiz
      good[1],
      '   ',
      '12\t${good[2]}', // numara + sekme biçimi
    ].join('\n');

    final added = await service.importFens(collection, text);
    expect(added, 3);
  });
}
