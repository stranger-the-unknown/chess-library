/// Kaydedilmiş bir oyun.
class SavedGame {
  final String id;
  String name;
  List<String> uciMoves;
  DateTime createdAt;
  String? result;

  /// Standart olmayan bir pozisyondan başlıyorsa başlangıç FEN'i.
  String? startFen;

  String? white;
  String? black;
  String? note;

  /// Kullanıcı bu oyunu okuduğunu/çalıştığını işaretledi mi?
  bool read;

  /// Favorilere eklendi mi?
  bool favorite;

  SavedGame({
    String? id,
    required this.name,
    required this.uciMoves,
    required this.createdAt,
    this.result,
    this.startFen,
    this.white,
    this.black,
    this.note,
    this.read = false,
    this.favorite = false,
  }) : id = id ?? 'g_${DateTime.now().microsecondsSinceEpoch}';

  int get moveCount => uciMoves.length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'uciMoves': uciMoves,
        'createdAt': createdAt.toIso8601String(),
        if (result != null) 'result': result,
        if (startFen != null) 'startFen': startFen,
        if (white != null) 'white': white,
        if (black != null) 'black': black,
        if (note != null) 'note': note,
        if (read) 'read': true,
        if (favorite) 'favorite': true,
      };

  factory SavedGame.fromJson(Map<String, dynamic> json) => SavedGame(
        id: json['id'] as String?,
        name: json['name'] as String? ?? 'Oyun',
        uciMoves: List<String>.from(json['uciMoves'] as List? ?? const []),
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        result: json['result'] as String?,
        startFen: json['startFen'] as String?,
        white: json['white'] as String?,
        black: json['black'] as String?,
        note: json['note'] as String?,
        read: json['read'] as bool? ?? false,
        favorite: json['favorite'] as bool? ?? false,
      );
}

/// Oyun listesi (kullanıcının kendi klasörü).
class Playlist {
  final String id;
  String name;
  List<SavedGame> games;

  Playlist({String? id, required this.name, List<SavedGame>? games})
      : id = id ?? 'l_${DateTime.now().microsecondsSinceEpoch}',
        games = games ?? <SavedGame>[];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'games': games.map((g) => g.toJson()).toList(),
      };

  factory Playlist.fromJson(Map<String, dynamic> json) => Playlist(
        id: json['id'] as String?,
        name: json['name'] as String? ?? 'Liste',
        games: (json['games'] as List? ?? const [])
            .map((e) => SavedGame.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}
