import 'move_count.dart';

/// Kaydedilmiş bir oyun.
class SavedGame {
  /// Kimlik sayacı.
  ///
  /// Kimlik yalnızca zaman damgasından üretilince, bir PGN dosyasından
  /// alınan oyunlar aynı mikrosaniyeye denk gelip **aynı kimliği**
  /// alıyordu (ölçüldü: art arda üretilen 200 oyundan yalnızca ikisi
  /// farklıydı). Sonucu görünürdü: bir oyunu okundu işaretleyince
  /// listedeki başka bir oyun işaretleniyordu.
  static int _sequence = 0;
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

  /// PGN başlıkları (Event, Site, Date, Round, ECO, Elo ...).
  ///
  /// Ad, oyuncular ve sonuç ayrı alanlarda tutuluyor çünkü listede
  /// sürekli kullanılıyorlar; geri kalan bilgiler burada duruyor ve
  /// yalnızca oyun bilgisi penceresinde okunuyor. Eski kayıtlarda bu
  /// alan yok, boş geliyor.
  Map<String, String> tags;

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
    Map<String, String>? tags,
  })  : tags = tags ?? const <String, String>{},
        id = id ??
            'g_${DateTime.now().microsecondsSinceEpoch}_${_sequence++}';

  /// Beyazın oynadığı hamle sayısı; kural [countWhiteMoves] içinde.
  int get moveCount => countWhiteMoves(uciMoves.length, startFen);

  /// PGN tarihindeki yıl; yoksa veya `????` ise null.
  int? get year {
    final raw = tags['Date'] ?? tags['UTCDate'];
    if (raw == null) return null;
    final token = raw.trim().split('.').first;
    if (token.length != 4) return null;
    return int.tryParse(token);
  }

  /// Kartta gösterilecek tarih; yoksa null.
  ///
  /// PGN tarihi `YYYY.MM.DD` biçiminde ve eksik parçalar `?` ile
  /// yazılıyor (`1997.??.??` gibi). Tam tarih varsa tamamı, yoksa
  /// yalnızca yıl gösterilir; yıl da bilinmiyorsa hiçbir şey yazılmaz.
  String? get displayDate {
    final raw = tags['Date'] ?? tags['UTCDate'];
    if (raw == null) return null;
    final parts = raw.split('.');
    if (parts.isEmpty) return null;
    final year = parts[0];
    if (year.length != 4 || int.tryParse(year) == null) return null;
    if (parts.length < 3) return year;
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (month == null || day == null) return year;
    if (month < 1 || month > 12 || day < 1 || day > 31) return year;
    return '$day.${month.toString().padLeft(2, '0')}.$year';
  }

  /// Kartta kullanılacak beyaz adı (alan, etiket veya `Ad - Ad` biçimindeki isim).
  String? get resolvedWhite =>
      _meaningfulPlayer(white) ??
      _meaningfulPlayer(tags['White']) ??
      _playersFromName?.$1;

  /// Kartta kullanılacak siyah adı.
  String? get resolvedBlack =>
      _meaningfulPlayer(black) ??
      _meaningfulPlayer(tags['Black']) ??
      _playersFromName?.$2;

  /// Kartta beyazın soyadı (ya da kullanıcı adı).
  String get cardWhite => playerLastName(resolvedWhite);

  /// Kartta siyahın soyadı (ya da kullanıcı adı).
  String get cardBlack => playerLastName(resolvedBlack);

  static String? _meaningfulPlayer(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == '?' || trimmed == '-') return null;
    return trimmed;
  }

  /// Eski kayıtlarda `white`/`black` boşken isim `"Beyaz - Siyah"` olarak
  /// yazılmış olabiliyor; kartı iki satıra bölmek için onu çözer.
  (String, String)? get _playersFromName {
    final raw = name.trim();
    const sep = ' - ';
    final index = raw.indexOf(sep);
    if (index <= 0) return null;
    final left = raw.substring(0, index).trim();
    final right = raw.substring(index + sep.length).trim();
    if (left.isEmpty || right.isEmpty) return null;
    if ((left == '?' || left == '-') && (right == '?' || right == '-')) {
      return null;
    }
    return (left, right);
  }

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
        if (tags.isNotEmpty) 'tags': tags,
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
        tags: (json['tags'] as Map?)?.map(
              (key, value) => MapEntry('$key', '$value'),
            ) ??
            const <String, String>{},
      );
}

/// Kartta gösterilecek oyuncu adı: soyad.
///
/// PGN'de hem "Magnus Carlsen" hem "Carlsen, Magnus" geçer. Çevrimiçi
/// oyunlarda ise ad çoğu zaman tek parça bir kullanıcı adıdır; onu
/// kesmek kartı boş bırakırdı, o yüzden tek kelime olduğu gibi kalır.
String playerLastName(String? full) {
  if (full == null) return '';
  var name = full.trim();
  if (name.isEmpty || name == '?' || name == '-') return '';

  name = name.replaceFirst(
    RegExp(r'^(?:W?GM|W?IM|W?FM|W?CM|NM|WH)\s+', caseSensitive: false),
    '',
  );

  final comma = name.indexOf(',');
  if (comma >= 0) {
    final last = name.substring(0, comma).trim();
    return last.isEmpty ? name : last;
  }

  final parts =
      name.split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
  if (parts.length <= 1) return name;
  return parts.last;
}

/// Oyun listesi (kullanıcının kendi klasörü).
class Playlist {
  final String id;
  String name;
  List<SavedGame> games;

  static int _sequence = 0;

  Playlist({String? id, required this.name, List<SavedGame>? games})
      : id = id ??
            'l_${DateTime.now().microsecondsSinceEpoch}_${_sequence++}',
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
