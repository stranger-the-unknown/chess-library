/// Konum tekrarı sayımı.
///
/// Anahtar olarak FEN'in ilk dört alanı kullanılıyor: taş dizilimi, sıra,
/// rok hakları ve geçerken alma karesi. Son iki alan (yarım hamle sayacı
/// ve hamle numarası) her hamlede değiştiği için tekrarı bozar; sayıma
/// girmemeleri gerekir.
///
/// Ekrandan ayrı bir yerde duruyor ki kuralı tahtayı çizmeden
/// sınayabilelim.
String positionKey(String fen) => fen.split(' ').take(4).join(' ');

/// [current] konumu, [fens] içinde (kendisi dahil) kaç kez geçiyor?
int repetitionCount(Iterable<String> fens, String current) {
  final key = positionKey(current);
  var count = 0;
  for (final fen in fens) {
    if (positionKey(fen) == key) count++;
  }
  return count;
}

/// Üç tekrar oldu mu?
bool isThreefold(Iterable<String> fens, String current) =>
    repetitionCount(fens, current) >= 3;
