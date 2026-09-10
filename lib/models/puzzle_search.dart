import 'puzzle.dart';

/// Bulmaca arama eşleştirmesi.
///
/// Hazır bulmacaların adı olmadığı için yalnızca FEN'e bakmak arama
/// çubuğunu işe yaramaz kılıyordu. Burada sıra numarası, okunabilir
/// etiketler ve hamle sırası da aranır; karşılaştırma Türkçe harfleri
/// sadeleştirerek yapılır, böylece "geçerken" ile "gecerken" eşleşir.
bool puzzleMatches(Puzzle puzzle, String rawQuery, {int? number}) {
  final query = foldForSearch(rawQuery);
  if (query.isEmpty) return true;

  // "12" ya da "#12" -> sıra numarası
  if (number != null) {
    final digits = query.replaceAll('#', '');
    if (digits.isNotEmpty &&
        int.tryParse(digits) != null &&
        '$number'.startsWith(digits)) {
      return true;
    }
  }

  final haystack = <String>[
    puzzle.fen,
    puzzle.title ?? '',
    puzzle.note ?? '',
    puzzle.sideToMoveLabel,
    ...puzzle.tags,
    ...puzzle.tagLabels,
  ];
  return haystack.any((value) => foldForSearch(value).contains(query));
}

/// Karşılaştırma için metni sadeleştirir: küçük harf + aksansız harfler.
String foldForSearch(String value) {
  const map = {
    'ç': 'c',
    'ğ': 'g',
    'ı': 'i',
    'ö': 'o',
    'ş': 's',
    'ü': 'u',
    'â': 'a',
    'î': 'i',
    'û': 'u',
  };

  // Türkçe'de 'I' -> 'ı', 'İ' -> 'i'; varsayılan toLowerCase bunu bilmez.
  final lower =
      value.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase().trim();

  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    // Birleştirici nokta (i̇) gibi işaretleri at.
    if (rune == 0x0307) continue;
    buffer.write(map[char] ?? char);
  }
  return buffer.toString();
}
