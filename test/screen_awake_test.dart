import 'package:flutter_test/flutter_test.dart';

import 'package:chess_pgn_reader/services/screen_awake.dart';

/// Ekranın açık tutulması: uzun düşünürken sönmesin, ama masada
/// unutulursa da sonsuza kadar açık kalmasın.
void main() {
  test('açılıyor, süre dolunca bırakıyor', () async {
    final log = <bool>[];
    final awake = ScreenAwake(
      limit: const Duration(milliseconds: 60),
      setter: log.add,
    );

    awake.keep();
    expect(log, [true]);
    expect(awake.isOn, isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(log, [true, false], reason: 'süre dolunca bırakmalı');
    expect(awake.isOn, isFalse);
  });

  test('her hamle süreyi baştan başlatıyor', () async {
    final log = <bool>[];
    final awake = ScreenAwake(
      limit: const Duration(milliseconds: 100),
      setter: log.add,
    );

    awake.keep();
    // Süre dolmadan üç "hamle": sayaç her seferinde sıfırlanıyor.
    for (var i = 0; i < 3; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 60));
      awake.keep();
      expect(awake.isOn, isTrue, reason: 'hamle sürerken sönmemeli');
    }
    expect(log, [true], reason: 'eklenti tekrar tekrar çağrılmamalı');

    await Future<void>.delayed(const Duration(milliseconds: 160));
    expect(awake.isOn, isFalse, reason: 'hareketsizlik sonunda bırakmalı');
    expect(log, [true, false]);
  });

  test('bırakma iki kez çağrılınca da güvenli', () {
    final log = <bool>[];
    final awake = ScreenAwake(setter: log.add);
    awake.keep();
    awake.release();
    awake.release();
    expect(log, [true, false]);
  });

  test('bırakıldıktan sonra yeniden açılabiliyor', () async {
    final log = <bool>[];
    final awake = ScreenAwake(
      limit: const Duration(milliseconds: 40),
      setter: log.add,
    );
    awake.keep();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    awake.keep();
    expect(log, [true, false, true]);
    awake.release();
  });
}
