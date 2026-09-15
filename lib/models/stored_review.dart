/// Kaydedilmiş bir oyun incelemesi.
///
/// İncelemenin tamamını değil, yeniden kurmak için gereken en küçük
/// veriyi saklar: hamlelerin kendisi zaten oyunun içinde duruyor, burada
/// yalnızca motorun her hamle için söyledikleri var. Kırk hamlelik bir
/// oyun için yaklaşık üç kilobayt; yüz kayıtlık iki liste bu yüzden
/// makul bir yer kaplıyor.
///
/// Yedeğe girmez: cihaza özel, başka cihazda yeniden üretilebilir.
class StoredReview {
  /// Derin inceleme mi, hızlı inceleme mi?
  final bool deep;

  /// İncelemenin yapıldığı an.
  final DateTime at;

  final double whiteAccuracy;
  final double blackAccuracy;

  /// Hamle sırasına göre motorun söyledikleri.
  final List<StoredReviewMove> moves;

  const StoredReview({
    required this.deep,
    required this.at,
    required this.whiteAccuracy,
    required this.blackAccuracy,
    required this.moves,
  });

  Map<String, dynamic> toJson() => {
        'deep': deep,
        'at': at.toIso8601String(),
        'w': whiteAccuracy,
        'b': blackAccuracy,
        'm': moves.map((m) => m.toJson()).toList(),
      };

  factory StoredReview.fromJson(Map<String, dynamic> json) => StoredReview(
        deep: json['deep'] as bool? ?? false,
        at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now(),
        whiteAccuracy: (json['w'] as num?)?.toDouble() ?? 0,
        blackAccuracy: (json['b'] as num?)?.toDouble() ?? 0,
        moves: (json['m'] as List? ?? const [])
            .map((e) =>
                StoredReviewMove.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

/// Tek bir hamle için saklanan inceleme verisi.
///
/// Alan adları kısa: yüz oyunluk iki liste söz konusu, uzun adlar
/// dosyayı gereksiz büyütüyor.
class StoredReviewMove {
  /// Hamleden önce, oynayanın bakışıyla en iyi değerlendirme.
  final int bestScoreCp;

  /// Oynanan hamleden sonra, oynayanın bakışıyla değerlendirme.
  final int playedScoreCp;

  /// Motorun önerdiği hamle (UCI).
  final String bestMoveUci;

  /// `MoveQuality` sıralamasındaki yeri.
  final int quality;

  final double accuracy;

  const StoredReviewMove({
    required this.bestScoreCp,
    required this.playedScoreCp,
    required this.bestMoveUci,
    required this.quality,
    required this.accuracy,
  });

  Map<String, dynamic> toJson() => {
        'a': bestScoreCp,
        'p': playedScoreCp,
        'u': bestMoveUci,
        'q': quality,
        'c': accuracy,
      };

  factory StoredReviewMove.fromJson(Map<String, dynamic> json) =>
      StoredReviewMove(
        bestScoreCp: (json['a'] as num?)?.toInt() ?? 0,
        playedScoreCp: (json['p'] as num?)?.toInt() ?? 0,
        bestMoveUci: json['u'] as String? ?? '',
        quality: (json['q'] as num?)?.toInt() ?? 0,
        accuracy: (json['c'] as num?)?.toDouble() ?? 0,
      );
}
