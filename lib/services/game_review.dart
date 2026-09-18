import 'dart:math' as math;

import '../models/chess_engine.dart' as engine;
import '../models/move_entry.dart';
import 'engine/engine_service.dart';

/// Bir hamlenin niteliği.
enum MoveQuality { best, excellent, good, inaccuracy, mistake, blunder, forced }

extension MoveQualityInfo on MoveQuality {
  /// Sıralama/gösterim için kısa anahtar (çeviri tablolarında kullanılır).
  String get key => name;
}

/// Tek bir hamlenin inceleme sonucu.
class ReviewedMove {
  final int index;
  final MoveEntry entry;
  final engine.Color mover;

  /// Hamleden önce, oynayanın bakış açısıyla en iyi değerlendirme.
  final int bestScoreCp;

  /// Oynanan hamleden sonra, oynayanın bakış açısıyla değerlendirme.
  final int playedScoreCp;

  /// Motorun önerdiği hamle (UCI) ve SAN karşılığı.
  final String bestMoveUci;
  final String bestMoveSan;

  final MoveQuality quality;

  /// Bu hamle için doğruluk yüzdesi (0-100).
  final double accuracy;

  const ReviewedMove({
    required this.index,
    required this.entry,
    required this.mover,
    required this.bestScoreCp,
    required this.playedScoreCp,
    required this.bestMoveUci,
    required this.bestMoveSan,
    required this.quality,
    required this.accuracy,
  });

  /// Kaybedilen değer (santipiyon); negatif olamaz.
  int get lossCp => math.max(0, bestScoreCp - playedScoreCp);

  bool get playedBest => entry.uci == bestMoveUci;

  /// Beyazın bakış açısıyla değerlendirme (grafik için).
  int get whiteScoreCp =>
      mover == engine.Color.white ? playedScoreCp : -playedScoreCp;
}

/// Tüm oyunun inceleme sonucu.
class GameReview {
  final List<ReviewedMove> moves;
  final double whiteAccuracy;
  final double blackAccuracy;
  final String startFen;

  const GameReview({
    required this.moves,
    required this.whiteAccuracy,
    required this.blackAccuracy,
    required this.startFen,
  });

  int countFor(engine.Color color, MoveQuality quality) =>
      moves.where((m) => m.mover == color && m.quality == quality).length;

  /// En çok değer kaybettiren hamleler (dönüm noktaları).
  List<ReviewedMove> get turningPoints {
    final sorted = List<ReviewedMove>.from(moves)
      ..sort((a, b) => b.lossCp.compareTo(a.lossCp));
    return sorted.where((m) => m.lossCp >= 100).take(6).toList();
  }
}

/// Biten (ya da yarım kalan) bir oyunu cihazdaki motorla inceler.
///
/// Her pozisyon yalnızca bir kez analiz edilir: `i` pozisyonunun
/// değerlendirmesi oynayanın en iyi seçeneğini, `i+1` pozisyonunun
/// işaret değiştirilmiş değerlendirmesi ise gerçekte oynanan hamlenin
/// sonucunu verir. Böylece N hamle için N+1 analiz yeterlidir.
class GameReviewer {
  /// Tek analiz profili (eski "derin" kalite: movetime/depth).
  ///
  /// Asıl sınırlayıcı movetime'dır (`go movetime … depth …`).
  static const int analysisMovetimeMs = 1200;
  static const int analysisDepth = 28;

  /// Eski adlar — geriye dönük sabitler.
  static const int deepMovetimeMs = analysisMovetimeMs;
  static const int deepDepth = analysisDepth;
  static const int quickMovetimeMs = analysisMovetimeMs;
  static const int quickDepth = analysisDepth;

  /// Mat skorlarını grafikte taşmasın diye sınırlar.
  static const int _cap = 1200;

  Future<GameReview> review(
    List<MoveEntry> history, {
    String? startFen,
    @Deprecated('Tek profil; yok sayılır') bool deep = true,
    void Function(int done, int total)? onProgress,
  }) async {
    final baseFen = startFen ?? engine.ChessGame().fen;
    const movetime = analysisMovetimeMs;
    const depth = analysisDepth;

    // Pozisyonları ve sıradaki tarafı topla.
    final position = engine.ChessGame.fromFen(baseFen);
    final fens = <String>[baseFen];
    final movers = <engine.Color>[];
    for (final entry in history) {
      movers.add(position.sideToMove);
      position.makeMove(entry.move);
      fens.add(position.fen);
    }

    final total = fens.length;
    final results = <SearchResult>[];
    for (int i = 0; i < total; i++) {
      final result = await EngineService.instance.analyze(
        fens[i],
        depth: depth,
        movetimeMs: movetime,
      );
      results.add(result);
      onProgress?.call(i + 1, total);
    }

    final reviewed = <ReviewedMove>[];
    double whiteSum = 0, blackSum = 0;
    int whiteCount = 0, blackCount = 0;

    for (int i = 0; i < history.length; i++) {
      final before = results[i];
      final after = results[i + 1];

      final bestScore = _clamp(_scoreOf(before));
      // `after` rakibin bakış açısındandır; işareti çevirerek oynayana getir.
      final playedScore = _clamp(-_scoreOf(after));

      final bestUci = before.bestMoveUci;
      String bestSan = bestUci;
      final probe = engine.ChessGame.fromFen(fens[i]);
      final bestMove = probe.moveFromUci(bestUci);
      if (bestMove != null) bestSan = probe.sanFor(bestMove);

      final legalCount = probe.allLegalMoves().length;
      final loss = math.max(0, bestScore - playedScore);
      final quality = legalCount <= 1
          ? MoveQuality.forced
          : _classify(history[i].uci == bestUci, loss);

      final accuracy = _accuracy(bestScore, playedScore);
      if (movers[i] == engine.Color.white) {
        whiteSum += accuracy;
        whiteCount++;
      } else {
        blackSum += accuracy;
        blackCount++;
      }

      reviewed.add(
        ReviewedMove(
          index: i,
          entry: history[i],
          mover: movers[i],
          bestScoreCp: bestScore,
          playedScoreCp: playedScore,
          bestMoveUci: bestUci,
          bestMoveSan: bestSan,
          quality: quality,
          accuracy: accuracy,
        ),
      );
    }

    return GameReview(
      moves: reviewed,
      whiteAccuracy: whiteCount == 0 ? 0 : whiteSum / whiteCount,
      blackAccuracy: blackCount == 0 ? 0 : blackSum / blackCount,
      startFen: baseFen,
    );
  }

  static int _scoreOf(SearchResult result) {
    final mate = result.mateIn;
    if (mate != null) {
      // Mat skorunu grafik için büyük ama sonlu bir değere indir.
      return mate > 0 ? _cap : -_cap;
    }
    return result.scoreCp;
  }

  static int _clamp(int value) => value.clamp(-_cap, _cap);

  static MoveQuality _classify(bool isBest, int loss) {
    if (isBest) return MoveQuality.best;
    if (loss < 20) return MoveQuality.excellent;
    if (loss < 50) return MoveQuality.good;
    if (loss < 100) return MoveQuality.inaccuracy;
    if (loss < 250) return MoveQuality.mistake;
    return MoveQuality.blunder;
  }

  /// Santipiyonu kazanma yüzdesine çevirir (lojistik eğri).
  static double _winPercent(int cp) {
    return 50 + 50 * (2 / (1 + math.exp(-0.00368208 * cp)) - 1);
  }

  /// Tek bir hamlenin doğruluk yüzdesi.
  static double _accuracy(int bestCp, int playedCp) {
    final before = _winPercent(bestCp);
    final after = _winPercent(playedCp);
    final drop = math.max(0.0, before - after);
    final value = 103.1668 * math.exp(-0.04354 * drop) - 3.1669;
    return value.clamp(0.0, 100.0);
  }
}
