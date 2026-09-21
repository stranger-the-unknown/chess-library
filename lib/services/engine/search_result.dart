/// Stockfish (veya başka bir UCI motor) arama sonucu.
class SearchResult {
  final String bestMoveUci;
  final int scoreCp;
  final int? mateIn;
  final int depth;
  final int nodes;
  final List<String> pvUci;
  final bool isGameOver;

  /// İstek başka bir istek yüzünden düştü mü?
  ///
  /// "Motor cevap veremedi" ile "benim aramam iptal edildi" ayrı şeyler.
  /// İkisi de boş sonuç döndürdüğü için eskiden karışıyordu: geri alma
  /// yüzünden iptal olan arama, ekranda "motor cevap vermedi" uyarısına
  /// ve tahtanın iki tarafa açılmasına yol açıyordu.
  final bool cancelled;

  const SearchResult({
    required this.bestMoveUci,
    required this.scoreCp,
    required this.depth,
    required this.nodes,
    required this.pvUci,
    this.mateIn,
    this.isGameOver = false,
    this.cancelled = false,
  });

  /// SF yok / çöktü: boş ama güvenli sonuç.
  static const empty = SearchResult(
    bestMoveUci: '',
    scoreCp: 0,
    depth: 0,
    nodes: 0,
    pvUci: [],
    isGameOver: false,
  );

  /// Arama başka bir istek yüzünden kesildi; ekran buna göre sessiz kalır.
  static const superseded = SearchResult(
    bestMoveUci: '',
    scoreCp: 0,
    depth: 0,
    nodes: 0,
    pvUci: [],
    isGameOver: false,
    cancelled: true,
  );

  Map<String, dynamic> toMap() => {
        'best': bestMoveUci,
        'score': scoreCp,
        'mate': mateIn,
        'depth': depth,
        'nodes': nodes,
        'pv': pvUci,
        'over': isGameOver,
      };

  factory SearchResult.fromMap(Map<String, dynamic> map) => SearchResult(
        bestMoveUci: map['best'] as String,
        scoreCp: map['score'] as int,
        mateIn: map['mate'] as int?,
        depth: map['depth'] as int,
        nodes: map['nodes'] as int,
        pvUci: List<String>.from(map['pv'] as List),
        isGameOver: map['over'] as bool? ?? false,
      );
}
