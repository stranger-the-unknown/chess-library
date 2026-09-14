import 'package:flutter_test/flutter_test.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';

/// Dil tablolarının bütünlüğü.
///
/// İki dilin anahtar kümesi birebir aynı olmalı: biri eksik kalırsa o
/// ekranda ham anahtar ya da yanlış dilde metin görünür. Ayrıca Türkçe
/// harflerin derlenmiş ikiliye bozulmadan geldiği denetlenir.

/// Türkçe metinlerde geçmesi beklenen, ASCII dışı harfler.
const String _turkishLetters = 'çğıöşüÇİÖŞ';


void main() {
  tearDown(() => Strings.language = AppLanguage.system);

  test('yalnızca Türkçe ve İngilizce var', () {
    expect(AppLanguage.values, [
      AppLanguage.system,
      AppLanguage.turkish,
      AppLanguage.english,
    ]);
  });

  test('iki dil aynı anahtarlara sahip', () {
    final tr = Strings.debugKeys('tr');
    final en = Strings.debugKeys('en');
    expect(tr.difference(en), isEmpty, reason: 'İngilizcede eksik anahtarlar');
    expect(en.difference(tr), isEmpty, reason: 'Türkçede eksik anahtarlar');
    expect(tr.length, greaterThan(300));
  });

  test('hiçbir metinde bozuk karakter yok', () {
    for (final code in ['tr', 'en']) {
      for (final key in Strings.debugKeys(code)) {
        final value = Strings.debugValue(code, key);
        expect(value.contains('\u{FFFD}'), isFalse,
            reason: '$code/$key bozuk karakter içeriyor');
        expect(RegExp(r'Ã[-¿]|Å[-¿]').hasMatch(value), isFalse,
            reason: '$code/$key yanlış kodlanmış görünüyor');
      }
    }
  });

  test('Türkçe harfler yerinde', () {
    final blob = Strings.debugKeys('tr')
        .map((k) => Strings.debugValue('tr', k))
        .join();
    final missing = <String>[];
    for (final letter in _turkishLetters.split('')) {
      if (!blob.contains(letter)) missing.add(letter);
    }
    expect(missing, isEmpty, reason: 'görünmeyen harfler: ${missing.join()}');
  });

  test('yer tutucular iki dilde de aynı', () {
    final placeholder = RegExp(r'\{(\w+)\}');
    Set<String> holders(String text) =>
        placeholder.allMatches(text).map((m) => m.group(1)!).toSet();

    for (final key in Strings.debugKeys('en')) {
      expect(
        holders(Strings.debugValue('tr', key)),
        holders(Strings.debugValue('en', key)),
        reason: '$key yer tutucuları farklı',
      );
    }
  });

  test('dil seçimi metinleri değiştiriyor', () {
    Strings.language = AppLanguage.english;
    expect(Strings.get('nav.play'), 'Play');
    Strings.language = AppLanguage.turkish;
    expect(Strings.get('nav.play'), 'Oyna');
  });

  test('ürün adı çevrilmiyor', () {
    for (final language in AppLanguage.values) {
      Strings.language = language;
      expect(Strings.get('app.title'), 'Chess Library');
    }
  });

  test('değişken doldurma çalışıyor', () {
    Strings.language = AppLanguage.turkish;
    final text = Strings.get('puzzles.imported', {'count': 42});
    expect(text, contains('42'));
    expect(text, isNot(contains('{')));
  });

  test('bilinmeyen anahtar ham hâliyle döner', () {
    expect(Strings.get('boyle.bir.anahtar.yok'), 'boyle.bir.anahtar.yok');
  });
}
