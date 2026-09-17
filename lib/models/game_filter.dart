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

/// Oyun listesindeki oyuncu ve sonuç süzgeci.
///
/// Arama kutusu tek bir metni her alanda arıyor; bu süzgeç ise "beyaz
/// şu, siyah bu" diye sorabilmek için var. Boş bırakılan alan
/// aranmıyor, yani yalnız siyah oyuncuyu yazmak da geçerli bir süzgeç.
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

  const GameFilter({
    this.white = '',
    this.black = '',
    this.result = ResultFilter.any,
    this.winner = '',
  });

  static const GameFilter none = GameFilter();

  /// Süzgeç gerçekten bir şey eliyor mu?
  ///
  /// "Şu oyuncu kazanır" seçili ama ad yazılmamışsa hiçbir şey elenmez;
  /// şerit de bu yüzden görünmez.
  bool get isActive =>
      white.trim().isNotEmpty ||
      black.trim().isNotEmpty ||
      (result == ResultFilter.playerWins
          ? winner.trim().isNotEmpty
          : result != ResultFilter.any);

  bool matches(SavedGame game) {
    if (!_nameMatches(game.white, white)) return false;
    if (!_nameMatches(game.black, black)) return false;

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

  GameFilter copyWith({
    String? white,
    String? black,
    ResultFilter? result,
    String? winner,
  }) =>
      GameFilter(
        white: white ?? this.white,
        black: black ?? this.black,
        result: result ?? this.result,
        winner: winner ?? this.winner,
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
