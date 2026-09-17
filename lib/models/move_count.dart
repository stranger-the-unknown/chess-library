/// Listelerde yazılan hamle sayısı.
///
/// Satrançta bir hamle beyazın ve siyahın birer yarım hamlesidir; oyunun
/// uzunluğu da böyle söylenir ("41 hamlede kazandı"). `uciMoves` ise
/// yarım hamleleri tutuyor, yani ikisinin toplamını: listede doğrudan
/// yazılınca sayı iki katı görünüyordu.
///
/// Analiz ekranındaki "12 / 87" bundan ayrı: orası oyun içinde kaçıncı
/// yarım hamlede olunduğunu gösteriyor, iki yarısı da aynı birimde.
///
/// Siyahın oynayacağı bir konumdan başlayan oyunlarda ilk yarım hamle
/// siyahındır; beyazın sayısı o zaman bir eksik olur.
int countWhiteMoves(int plyCount, String? startFen) {
  if (plyCount <= 0) return 0;
  return _blackStarts(startFen) ? plyCount ~/ 2 : (plyCount + 1) ~/ 2;
}

bool _blackStarts(String? startFen) {
  if (startFen == null) return false;
  final parts = startFen.trim().split(RegExp(r'\s+'));
  return parts.length > 1 && parts[1].toLowerCase() == 'b';
}
