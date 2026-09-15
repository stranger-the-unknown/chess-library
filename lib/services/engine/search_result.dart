/// Motorun bir pozisyon için verdiği sonuç.
///
/// Motor değiştiğinde çağrı yerlerinin değişmemesi için ayrı dosyada
/// duruyor: ekranlar ve inceleme kodu yalnızca bu türü tanıyor.
class SearchResult {
  /// En iyi hamle, UCI gösteriminde (`e2e4`). Oyun bittiyse boş.
  final String bestMoveUci;

  /// Puan, **sıradaki tarafın** bakışıyla ve santipiyon cinsinden.
  /// Mat skorları ±30000 civarına ölçeklenir.
  final int scoreCp;

  /// Zorunlu mat varsa kaç hamlede; sıradaki taraf mat ediyorsa artı,
  /// mat oluyorsa eksi. Yoksa null.
  final int? mateIn;

  /// Ulaşılan arama derinliği (yarım hamle).
  final int depth;

  /// Bakılan düğüm sayısı.
  final int nodes;

  /// Ana varyant, UCI gösteriminde.
  final List<String> pvUci;

  /// Pozisyonda yasal hamle yoksa true.
  final bool isGameOver;

  const SearchResult({
    required this.bestMoveUci,
    required this.scoreCp,
    required this.depth,
    required this.nodes,
    required this.pvUci,
    this.mateIn,
    this.isGameOver = false,
  });
}
