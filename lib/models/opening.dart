import '../l10n/app_strings.dart';

/// Bir açılış varyantı.
class Opening {
  final String id;
  final String eco;
  String family;
  String variation;

  /// Hamleler; ikisi de aynı sırayı gösterir.
  List<String> uciMoves;
  List<String> sanMoves;

  String? note;

  /// Kullanıcının kendi eklediği varyantlar için `true`.
  final bool custom;

  Opening({
    required this.id,
    required this.eco,
    required this.family,
    required this.variation,
    required this.uciMoves,
    required this.sanMoves,
    this.note,
    this.custom = false,
  });

  String get title => '$family · $variation';

  int get length => uciMoves.length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'eco': eco,
        'family': family,
        'variation': variation,
        'uci': uciMoves,
        'san': sanMoves,
        if (note != null) 'note': note,
        'custom': custom,
      };

  factory Opening.fromJson(Map<String, dynamic> json) => Opening(
        id: json['id'] as String,
        eco: json['eco'] as String? ?? '---',
        family: json['family'] as String? ?? t('openings.ownFamily'),
        variation:
            json['variation'] as String? ?? t('openings.defaultVariation'),
        uciMoves: List<String>.from(json['uci'] as List? ?? const []),
        sanMoves: List<String>.from(json['san'] as List? ?? const []),
        note: json['note'] as String?,
        custom: json['custom'] as bool? ?? false,
      );

  /// "ECO|Aile|Varyant|UCI|SAN" biçimindeki varlık satırını okur.
  static Opening? fromAssetLine(String line, String id) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) return null;
    final parts = trimmed.split('|');
    if (parts.length < 5) return null;
    final uci = parts[3].split(' ').where((m) => m.isNotEmpty).toList();
    final san = parts[4].split(' ').where((m) => m.isNotEmpty).toList();
    if (uci.isEmpty) return null;
    return Opening(
      id: id,
      eco: parts[0],
      family: parts[1],
      variation: parts[2],
      uciMoves: uci,
      sanMoves: san,
    );
  }
}

/// Kullanıcının bir açılıştaki ilerlemesi.
class OpeningProgress {
  bool learned;
  bool favorite;

  /// Alıştırmada üst üste kaç kez hatasız tamamlandı.
  int streak;

  OpeningProgress({
    this.learned = false,
    this.favorite = false,
    this.streak = 0,
  });

  Map<String, dynamic> toJson() => {'l': learned, 'f': favorite, 's': streak};

  factory OpeningProgress.fromJson(Map<String, dynamic> json) =>
      OpeningProgress(
        learned: json['l'] as bool? ?? false,
        favorite: json['f'] as bool? ?? false,
        streak: json['s'] as int? ?? 0,
      );
}
