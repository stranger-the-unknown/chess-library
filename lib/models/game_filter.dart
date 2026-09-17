import 'playlist.dart';
import 'puzzle_search.dart';

/// Sonuç süzgecinin seçenekleri.
enum ResultFilter {
  any,

  /// Beyaz kazanır (1-0).
  whiteWins,

  /// Beraberlik (1/2-1/2).
  draw,

  /// Siyah kazanır (0-1).
  blackWins,

  /// Adı yazılan oyuncu kazanır; hangi renkle oynadığına bakılmaz.
  playerWins,
}

/// Oyun listesindeki oyuncu, sonuç ve yıl filtresi.
///
/// Arama kutusu tek bir metni her alanda arıyor; bu pencere ise "beyaz
/// şu, siyah bu, yıl 2018" diye sorabilmek için var. Boş bırakılan alan
/// aranmıyor.
///
/// [ignoreColor] kapalıyken ad alanları renk bağlar: üstteki beyaz, alttaki
/// siyah. Açıkken (varsayılan kapalı) renk düşer: tek ad o oyuncunun
/// bütün oyunlarını, iki ad da o iki kişinin birbirine karşı oynadığı
/// bütün oyunları getirir.
///
/// Eşleştirme parça parça: "magnus carlsen" yazınca "Carlsen, Magnus"
/// da eşleşiyor, çünkü PGN dosyalarında ad sırası dosyadan dosyaya
/// değişiyor. Karşılaştırma Türkçe harfleri sadeleştirerek yapılıyor
/// ([foldForSearch]).
class GameFilter {
  final String white;
  final String black;
  final ResultFilter result;

  /// [ResultFilter.playerWins] seçiliyken kazanan oyuncunun adı.
  final String winner;

  /// Ad alanları renk fark etmeksizin eşleşsin.
  final bool ignoreColor;

  /// PGN tarihindeki yıl; null ise yıla bakılmaz.
  final int? year;

  const GameFilter({
    this.white = '',
    this.black = '',
    this.result = ResultFilter.any,
    this.winner = '',
    this.ignoreColor = false,
    this.year,
  });

  static const GameFilter none = GameFilter();

  /// Filtre gerçekten bir şey eliyor mu?
  ///
  /// "Şu oyuncu kazanır" seçili ama ad yazılmamışsa hiçbir şey elenmez;
  /// şerit de bu yüzden görünmez. Yalnızca [ignoreColor] işaretliyse
  /// de elenmez: o bir kip, tek başına süzgeç değil.
  bool get isActive =>
      white.trim().isNotEmpty ||
      black.trim().isNotEmpty ||
      year != null ||
      (result == ResultFilter.playerWins
          ? winner.trim().isNotEmpty
          : result != ResultFilter.any);

  bool matches(SavedGame game) {
    if (!_playersMatch(game)) return false;
    if (!_yearMatches(game)) return false;

    final outcome = _outcome(game.result);
    switch (result) {
      case ResultFilter.any:
        return true;
      case ResultFilter.whiteWins:
        return outcome == _white;
      case ResultFilter.draw:
        return outcome == _draw;
      case ResultFilter.blackWins:
        return outcome == _black;
      case ResultFilter.playerWins:
        if (winner.trim().isEmpty) return true;
        if (outcome == _white) return _nameMatches(game.white, winner);
        if (outcome == _black) return _nameMatches(game.black, winner);
        return false;
    }
  }

  bool _yearMatches(SavedGame game) {
    if (year == null) return true;
    return game.year == year;
  }

  bool _playersMatch(SavedGame game) {
    final a = white.trim();
    final b = black.trim();
    if (a.isEmpty && b.isEmpty) return true;

    if (ignoreColor) {
      if (b.isEmpty) {
        return _nameMatches(game.white, a) || _nameMatches(game.black, a);
      }
      if (a.isEmpty) {
        return _nameMatches(game.white, b) || _nameMatches(game.black, b);
      }
      final direct =
          _nameMatches(game.white, a) && _nameMatches(game.black, b);
      final swapped =
          _nameMatches(game.white, b) && _nameMatches(game.black, a);
      return direct || swapped;
    }

    return _nameMatches(game.white, white) && _nameMatches(game.black, black);
  }

  GameFilter copyWith({
    String? white,
    String? black,
    ResultFilter? result,
    String? winner,
    bool? ignoreColor,
    int? year,
    bool clearYear = false,
  }) =>
      GameFilter(
        white: white ?? this.white,
        black: black ?? this.black,
        result: result ?? this.result,
        winner: winner ?? this.winner,
        ignoreColor: ignoreColor ?? this.ignoreColor,
        year: clearYear ? null : (year ?? this.year),
      );
}

const String _white = '1-0';
const String _black = '0-1';
const String _draw = '1/2';

/// PGN sonucunu üç bilinen değere indirger; bilinmiyorsa boş.
///
/// Dosyadan dosyaya "1/2-1/2", "½-½" ve "*" hepsi geçiyor.
String _outcome(String? raw) {
  if (raw == null) return '';
  final text = raw.trim().replaceAll('½', '1/2');
  if (text.contains('1/2')) return _draw;
  if (text == _white) return _white;
  if (text == _black) return _black;
  return '';
}

bool _nameMatches(String? value, String query) {
  final words = foldForSearch(query)
      .split(RegExp(r'[\s,.]+'))
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.isEmpty) return true;
  final folded = foldForSearch(value ?? '');
  return words.every(folded.contains);
}
