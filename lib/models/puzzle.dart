import '../l10n/app_strings.dart';
import 'chess_engine.dart' as engine;

/// Tek bir bulmaca: bir FEN pozisyonu ve ona iliştirilmiş bilgiler.
class Puzzle {
  /// Koleksiyon içinde benzersiz kimlik ("oyunsonu#128" ya da "u_17...").
  final String id;

  String fen;
  String? title;
  String? note;
  List<String> tags;

  /// Biliniyorsa çözüm dizisi (UCI). Mat problemlerinde doludur; motorla
  /// değerlendirilen listelerde boştur.
  List<String> solution;

  /// Kaynak kitaptaki/dosyadaki sıra numarası. Listedeki konumdan
  /// bağımsızdır: bulmaca silinse bile kalanların numarası değişmez ve
  /// numaralandırma kaynağıyla birebir aynı kalır.
  final int? number;

  /// Kullanıcının kendi eklediği bulmacalar için `true`.
  final bool custom;

  Puzzle({
    required this.id,
    required this.fen,
    this.title,
    this.note,
    List<String>? tags,
    List<String>? solution,
    this.number,
    this.custom = false,
  })  : tags = tags ?? <String>[],
        solution = solution ?? <String>[];

  bool get hasSolution => solution.isNotEmpty;

  /// Çözümün kaç hamlede mat ettiği (yarım hamle sayısından).
  int get mateInMoves => (solution.length + 1) ~/ 2;

  /// Hamle sırası kimde?
  engine.Color get sideToMove {
    final parts = fen.split(' ');
    return (parts.length > 1 && parts[1] == 'b')
        ? engine.Color.black
        : engine.Color.white;
  }

  String get sideToMoveLabel => sideToMove == engine.Color.white
      ? t('puzzles.whiteToMove')
      : t('puzzles.blackToMove');

  /// Etiketlerin okunabilir karşılıkları ("mat-1" -> "1 hamlede mat").
  List<String> get tagLabels => tags.map(tagLabel).toList();

  /// Tek bir etiketin okunabilir karşılığı; bilinmeyen etiket olduğu gibi
  /// gösterilir (kullanıcının kendi eklediği etiketler için).
  static String tagLabel(String tag) {
    const known = {
      'oyunsonu': 'tag.endgame',
      'ortaoyun': 'tag.middlegame',
      'mat-1': 'tag.mate1',
      'mat-2': 'tag.mate2',
      'mat-3': 'tag.mate3',
      'sah': 'tag.check',
      'ustunluk': 'tag.advantage',
      'savunma': 'tag.defence',
      'az-tas': 'tag.fewPieces',
      'gecerken-alma': 'tag.enPassant',
    };
    final key = known[tag];
    return key == null ? tag : t(key);
  }

  Puzzle copyWith({
    String? fen,
    String? title,
    String? note,
    List<String>? tags,
    List<String>? solution,
  }) {
    // Pozisyon değiştiyse eski çözüm artık geçerli değildir.
    final keepSolution = fen == null || fen == this.fen;
    return Puzzle(
      id: id,
      fen: fen ?? this.fen,
      title: title ?? this.title,
      note: note ?? this.note,
      tags: tags ?? List<String>.from(this.tags),
      solution: solution ??
          (keepSolution ? List<String>.from(this.solution) : const <String>[]),
      number: number,
      custom: custom,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'fen': fen,
        if (title != null) 'title': title,
        if (note != null) 'note': note,
        if (tags.isNotEmpty) 'tags': tags,
        if (solution.isNotEmpty) 'solution': solution,
        if (number != null) 'number': number,
        'custom': custom,
      };

  factory Puzzle.fromJson(Map<String, dynamic> json) => Puzzle(
        id: json['id'] as String,
        fen: json['fen'] as String,
        title: json['title'] as String?,
        note: json['note'] as String?,
        tags: (json['tags'] as List?)?.map((e) => e.toString()).toList(),
        solution:
            (json['solution'] as List?)?.map((e) => e.toString()).toList(),
        number: json['number'] as int?,
        custom: json['custom'] as bool? ?? false,
      );

  /// "fen|etiketler|çözüm|numara" biçimindeki varlık satırını okur.
  /// Çözüm ve numara bölümleri isteğe bağlıdır.
  static Puzzle? fromAssetLine(String line, String id) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) return null;
    final parts = trimmed.split('|');
    final fen = parts[0].trim();
    if (fen.isEmpty) return null;

    final tags = parts.length > 1
        ? parts[1]
            .split(',')
            .map((t) => t.trim())
            .where((t) => t.isNotEmpty)
            .toList()
        : <String>[];
    final solution = parts.length > 2
        ? parts[2].split(' ').where((m) => m.isNotEmpty).toList()
        : <String>[];
    final number = parts.length > 3 ? int.tryParse(parts[3].trim()) : null;

    return Puzzle(
      id: id,
      fen: fen,
      tags: tags,
      solution: solution,
      number: number,
    );
  }
}

/// Kullanıcının bulmaca ilerlemesi.
class PuzzleProgress {
  bool solved;
  bool favorite;
  int attempts;
  DateTime? lastAttempt;

  PuzzleProgress({
    this.solved = false,
    this.favorite = false,
    this.attempts = 0,
    this.lastAttempt,
  });

  bool get isEmpty => !solved && !favorite && attempts == 0;

  Map<String, dynamic> toJson() => {
        's': solved,
        'f': favorite,
        'a': attempts,
        if (lastAttempt != null) 'd': lastAttempt!.millisecondsSinceEpoch,
      };

  factory PuzzleProgress.fromJson(Map<String, dynamic> json) => PuzzleProgress(
        solved: json['s'] as bool? ?? false,
        favorite: json['f'] as bool? ?? false,
        attempts: json['a'] as int? ?? 0,
        lastAttempt: json['d'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(json['d'] as int),
      );
}

/// Bir bulmaca listesi.
///
/// Hazır listeler (oyun sonları, orta oyun) uygulama varlıklarından
/// yüklenir; kullanıcının yaptığı düzenlemeler ayrı bir "değişiklik"
/// katmanında saklanır. Böylece binlerce pozisyon her açılışta yeniden
/// kaydedilmek zorunda kalmaz.
class PuzzleCollection {
  final String id;
  String name;
  String? description;

  /// Hazır listelerde varlık dosyasının yolu, kullanıcı listelerinde `null`.
  final String? assetPath;

  bool get isBuiltIn => assetPath != null;

  /// Yalnızca kullanıcı listelerinde dolu olur.
  List<Puzzle> puzzles;

  PuzzleCollection({
    required this.id,
    required this.name,
    this.description,
    this.assetPath,
    List<Puzzle>? puzzles,
  }) : puzzles = puzzles ?? <Puzzle>[];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (description != null) 'description': description,
        if (assetPath != null) 'asset': assetPath,
        'puzzles': puzzles.map((p) => p.toJson()).toList(),
      };

  factory PuzzleCollection.fromJson(Map<String, dynamic> json) =>
      PuzzleCollection(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        assetPath: json['asset'] as String?,
        puzzles: (json['puzzles'] as List? ?? [])
            .map((e) => Puzzle.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}
