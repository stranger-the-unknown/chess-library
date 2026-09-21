import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/services/opening_service.dart';

/// Açılış içe aktarmada da harf büyüklüğü anlam taşır.
///
/// PGN okuyucuda düzeltilen hatanın aynısı burada duruyordu: SAN metni
/// karşılaştırmadan önce büyük harfe çevriliyordu, yani `bxc3` (b
/// sütunundaki piyon) ile `Bxc3` (fil) aynı görünüyordu. İkisi de
/// oynanabilirken listede önce gelen seçiliyor ve varyant sessizce
/// yanlış kaydediliyordu.

/// Aynı konumda hem `bxc3` (b2 piyonu) hem `Bxc3` (d2 fili) oynanabilir.
const _pawnLine = '1. d4 Nf6 2. Nc3 Ne4 3. Bd2 Nxc3 4. bxc3';
const _bishopLine = '1. d4 Nf6 2. Nc3 Ne4 3. Bd2 Nxc3 4. Bxc3';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    OpeningService.instance.resetCache();
  });

  test('b piyonu ile fil karışmıyor', () async {
    // Metin büyük harfe çevrilince ikisi de aynı anahtara iniyordu ve
    // hangisinin seçileceği hamle üretim sırasına kalıyordu: iki satır
    // da aynı hamleyle bitiyor, yani varyantlardan biri sessizce yanlış.
    final pawn = await OpeningService.instance.addFromSan(
      family: 'Deneme',
      variation: 'piyon',
      moveText: _pawnLine,
    );
    final bishop = await OpeningService.instance.addFromSan(
      family: 'Deneme',
      variation: 'fil',
      moveText: _bishopLine,
    );

    expect(pawn, isNotNull, reason: 'piyon satırı okunamadı');
    expect(bishop, isNotNull, reason: 'fil satırı okunamadı');
    expect(pawn!.uciMoves, hasLength(7));
    expect(bishop!.uciMoves, hasLength(7));

    expect(pawn.uciMoves.last, 'b2c3', reason: 'bxc3 b piyonu olmalı');
    expect(bishop.uciMoves.last, 'd2c3', reason: 'Bxc3 d2 fili olmalı');
    expect(
      pawn.uciMoves.last == bishop.uciMoves.last,
      isFalse,
      reason: 'iki farklı hamle aynı sayıldı: harf büyüklüğü yutuluyor',
    );
  });

  test('rok ve terfi harfi büyük küçük yazılabiliyor', () async {
    // Harfin anlam taşımadığı iki yerde hoşgörü sürmeli.
    final castle = await OpeningService.instance.addFromSan(
      family: 'Deneme',
      variation: 'rok',
      moveText: '1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. o-o d6',
    );
    expect(castle, isNotNull);
    expect(castle!.uciMoves, contains('e1g1'));

    final promotion = await OpeningService.instance.addFromSan(
      family: 'Deneme',
      variation: 'terfi',
      moveText: '1. a4 Nf6 2. a5 Ne4 3. a6 Nc6 4. axb7 Nb8 5. bxa8=q',
    );
    expect(promotion, isNotNull);
    expect(promotion!.uciMoves.last, 'b7a8q');
  });
}
