/// Stockfish (veya başka bir UCI motor) arama sonucu.
class SearchResult {
  final String bestMoveUci;
  final int scoreCp;
  final int? mateIn;
  final int depth;
  final int nodes;
  final List<String> pvUci;
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

  /// SF yok / çöktü / iptal: boş ama güvenli sonuç.
  static const empty = SearchResult(
    bestMoveUci: '',
    scoreCp: 0,
    depth: 0,
    nodes: 0,
    pvUci: [],
    isGameOver: false,
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
