import 'package:flutter_test/flutter_test.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/l10n/app_strings_de.dart';
import 'package:chess_pgn_reader/l10n/app_strings_es.dart';
import 'package:chess_pgn_reader/l10n/app_strings_fr.dart';

/// Dil tablolarının bütünlüğü.
///
/// Özellikle İngiliz alfabesi dışındaki harflerin (ş, ğ, ñ, ö, ç, é, ß…)
/// kaynaktan derlenmiş ikili dosyaya kadar bozulmadan geldiği denetlenir:
/// yanlış kodlamada bu harfler U+FFFD (`�`) ya da mojibake'ye dönüşür.

/// Her dilde bulunması beklenen, ASCII dışı örnek harfler.
///
/// Yalnızca metinlerde gerçekten geçen harfler listelenir: örneğin büyük
/// Ğ ve Ü hiçbir Türkçe metinde bulunmadığı için burada aranmaz.
const Map<String, String> _expectedLetters = {
  'tr': 'çğıöşüÇİÖŞ',
  'es': 'áéíóúñ¿¡',
  'de': 'äöüßÄÖÜ',
  'fr': 'àçéèêîôùû',
};

Map<String, Map<String, String>> get _tables => {
      'tr': _tableFor(AppLanguage.turkish),
      'en': _tableFor(AppLanguage.english),
      'es': esStrings,
      'de': deStrings,
      'fr': frStrings,
    };

/// Etkin dili değiştirip tüm anahtarları okuyarak tabloyu geri kurar.
Map<String, String> _tableFor(AppLanguage language) {
  final previous = Strings.language;
  Strings.language = language;
  final out = <String, String>{};
  for (final key in esStrings.keys) {
    out[key] = Strings.get(key);
  }
  Strings.language = previous;
  return out;
}

void main() {
  tearDown(() => Strings.language = AppLanguage.system);

  test('hiçbir metinde bozuk karakter yok', () {
    for (final entry in _tables.entries) {
      for (final item in entry.value.entries) {
        expect(
          item.value.contains('�'),
          isFalse,
          reason: '${entry.key}/${item.key} bozuk karakter içeriyor',
        );
        // Mojibake izi: UTF-8 baytlarının Latin-1 gibi okunması.
        expect(
          RegExp(r'Ã[-¿]|Å[-¿]').hasMatch(item.value),
          isFalse,
          reason: '${entry.key}/${item.key} yanlış kodlanmış görünüyor',
        );
      }
    }
  });

  test('her dilde kendi özel harfleri gerçekten var', () {
    for (final entry in _expectedLetters.entries) {
      final table = _tables[entry.key]!;
      final blob = table.values.join();
      final missing = <String>[];
      for (final letter in entry.value.split('')) {
        if (!blob.contains(letter)) missing.add(letter);
      }
      expect(missing, isEmpty,
          reason: '${entry.key} tablosunda görünmeyen harfler: '
              '${missing.join()}');
    }
  });

  test('yeni diller İngilizce ile aynı anahtarlara sahip', () {
    final reference = _tableFor(AppLanguage.english).keys.toSet();
    for (final entry
        in {'es': esStrings, 'de': deStrings, 'fr': frStrings}.entries) {
      final keys = entry.value.keys.toSet();
      expect(reference.difference(keys), isEmpty,
          reason: '${entry.key} dilinde eksik anahtarlar');
      expect(keys.difference(reference), isEmpty,
          reason: '${entry.key} dilinde fazladan anahtarlar');
    }
  });

  test('yer tutucular her dilde korunmuş', () {
    final placeholder = RegExp(r'\{(\w+)\}');
    Set<String> holders(String text) =>
        placeholder.allMatches(text).map((m) => m.group(1)!).toSet();

    final english = _tableFor(AppLanguage.english);
    for (final entry
        in {'es': esStrings, 'de': deStrings, 'fr': frStrings}.entries) {
      for (final item in entry.value.entries) {
        final expected = holders(english[item.key] ?? '');
        expect(holders(item.value), expected,
            reason: '${entry.key}/${item.key} yer tutucuları farklı');
      }
    }
  });

  test('dil seçimi metinleri gerçekten değiştiriyor', () {
    Strings.language = AppLanguage.spanish;
    expect(Strings.get('nav.play'), 'Jugar');
    Strings.language = AppLanguage.german;
    expect(Strings.get('nav.play'), 'Spielen');
    Strings.language = AppLanguage.french;
    expect(Strings.get('nav.play'), 'Jouer');
    Strings.language = AppLanguage.turkish;
    expect(Strings.get('nav.play'), contains('Oyna'));
  });

  test('ürün adı hiçbir dilde çevrilmiyor', () {
    for (final language in AppLanguage.values) {
      Strings.language = language;
      expect(Strings.get('app.title'), 'Chess Library');
    }
  });

  test('değişken doldurma çalışıyor', () {
    Strings.language = AppLanguage.french;
    expect(Strings.get('puzzles.imported', {'count': 42}), contains('42'));
    expect(
        Strings.get('puzzles.imported', {'count': 42}), isNot(contains('{')));
  });
}
