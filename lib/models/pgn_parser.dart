import 'dart:convert';

import '../l10n/app_strings.dart';
import 'chess_engine.dart' as engine;

/// PGN metinlerini okur ve yazar.
///
/// Hamle eşleştirmesi, SAN gösterimini elle çözümlemek yerine pozisyondaki
/// tüm yasal hamlelerin SAN karşılığını üretip metinle karşılaştırarak
/// yapılır. Böylece ayırt etme ("Nbd2"), az terfi ("e8=N"), en passant ve
/// rok gibi tüm özel durumlar motorun kendi kurallarıyla tutarlı olur.
class PgnParser {
  late engine.ChessGame game;

  /// Okunan hamleler, UCI gösteriminde.
  final List<String> moves = <String>[];

  /// PGN başlıkları (Event, White, Black, Date, Result, FEN ...).
  final Map<String, String> headers = <String, String>{};

  /// PGN'de `[FEN "..."]` varsa başlangıç pozisyonu; yoksa `null`.
  String? startFen;

  /// Oyun sonucu: "1-0", "0-1", "1/2-1/2" veya `null`.
  String? gameResult;

  /// Çözümlenemeyen hamle metinleri (kullanıcıya uyarı göstermek için).
  final List<String> skippedTokens = <String>[];

  PgnParser() {
    game = engine.ChessGame();
  }

  bool parse(String pgn) {
    moves.clear();
    headers.clear();
    skippedTokens.clear();
    startFen = null;
    gameResult = null;

    try {
      _readHeaders(pgn);

      final fenHeader = headers['FEN'];
      if (fenHeader != null &&
          engine.ChessGame.validateFen(fenHeader) == null) {
        startFen = fenHeader;
        game = engine.ChessGame.fromFen(fenHeader);
      } else {
        game = engine.ChessGame();
      }

      final body = _stripDecorations(pgn);

      final resultMatch = RegExp(r'(1-0|0-1|1/2-1/2)').firstMatch(body);
      gameResult = resultMatch?.group(1) ?? headers['Result'];
      if (gameResult == '*') gameResult = null;

      for (final token in _tokenize(body)) {
        final uci = _matchSanToken(token);
        if (uci == null) {
          skippedTokens.add(token);
          continue;
        }
        game.makeUciMove(uci);
        moves.add(uci);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  void _readHeaders(String pgn) {
    final regex = RegExp(r'\[\s*(\w+)\s*"([^"]*)"\s*\]');
    for (final match in regex.allMatches(pgn)) {
      headers[match.group(1)!] = match.group(2)!;
    }
  }

  /// Başlıkları, yorumları, varyasyonları ve NAG işaretlerini temizler.
  String _stripDecorations(String pgn) {
    var clean = pgn.replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
    clean = clean.replaceAll(RegExp(r'\{[^}]*\}', dotAll: true), ' ');
    clean = clean.replaceAll(RegExp(r';[^\n]*'), ' ');
    clean = _stripParentheses(clean);
    clean = clean.replaceAll(RegExp(r'\$\d+'), ' ');
    return clean;
  }

  /// İç içe olsa dahi parantezli varyasyonları kaldırır.
  String _stripParentheses(String input) {
    final buffer = StringBuffer();
    int depth = 0;
    for (final rune in input.runes) {
      final char = String.fromCharCode(rune);
      if (char == '(') {
        depth++;
      } else if (char == ')') {
        if (depth > 0) depth--;
      } else if (depth == 0) {
        buffer.write(char);
      }
    }
    return buffer.toString();
  }

  List<String> _tokenize(String body) {
    var text = body
        .replaceAll('1-0', ' ')
        .replaceAll('0-1', ' ')
        .replaceAll('1/2-1/2', ' ')
        .replaceAll('*', ' ');
    // Hamle numaraları: "12." veya "12..."
    text = text.replaceAll(RegExp(r'\b\d+\.(\.\.)?'), ' ');
    return text
        .split(RegExp(r'\s+'))
        .map((token) => token.trim())
        .where((token) => token.isNotEmpty && token != '.')
        .toList();
  }

  /// SAN metnini bu pozisyondaki bir hamleyle eşler.
  String? _matchSanToken(String token) {
    final wanted = _normalizeSan(token);
    if (wanted.isEmpty) return null;

    final moves = game.allLegalMoves();

    // Önce hedef karesi tutan hamleleri dene: SAN üretmek pozisyon kopyası
    // gerektirdiği için bu eleme uzun dosyalarda büyük fark yaratır.
    final target = _targetSquareOf(token);
    if (target != null) {
      for (final move in moves) {
        if (move.to.algebraic != target) continue;
        if (_matchesSan(move, wanted, moves)) return move.uci;
      }
    }

    for (final move in moves) {
      if (target != null && move.to.algebraic == target) continue;
      if (_matchesSan(move, wanted, moves)) return move.uci;
    }
    return null;
  }

  /// Hamlenin SAN karşılığı aranan metinle aynı mı?
  ///
  /// `+` / `#` eki karşılaştırmada zaten atıldığı için üretilmez de: eki
  /// bulmak hamleyi bir kopya üzerinde oynamayı gerektirir ve uzun
  /// dosyalarda sürenin çoğunu bu alır.
  bool _matchesSan(
    engine.ChessMove move,
    String wanted,
    List<engine.ChessMove> legalMoves,
  ) {
    final san = game.sanFor(
      move,
      includeCheckSuffix: false,
      legalMoves: legalMoves,
    );
    return _normalizeSan(san) == wanted;
  }

  /// SAN metninden hedef kareyi ("Nxe5+!" -> "e5") okur; çıkaramazsa null.
  static String? _targetSquareOf(String token) {
    var text = token.replaceAll(RegExp(r'[+#!?]'), '');
    final promotion = text.indexOf('=');
    if (promotion >= 0) text = text.substring(0, promotion);
    if (text.length < 2) return null;
    final square = text.substring(text.length - 2);
    return RegExp(r'^[a-h][1-8]$').hasMatch(square) ? square : null;
  }

  /// Karşılaştırmayı bozan süsleri atar: "Nxe5+!?" -> "NE5".
  static String _normalizeSan(String san) {
    final buffer = StringBuffer();
    for (final rune in san.runes) {
      final char = String.fromCharCode(rune);
      if (char == '+' ||
          char == '#' ||
          char == '!' ||
          char == '?' ||
          char == '-' ||
          char == 'x' ||
          char == 'X') {
        continue;
      }
      buffer.write(char == '0' ? 'O' : char.toUpperCase());
    }
    return buffer.toString();
  }

  // -------------------------------------------------------------------------
  // ÇOK OYUNLU DOSYALAR
  // -------------------------------------------------------------------------

  /// Bir dosya içindeki oyunları ayırır.
  ///
  /// Yeni bir oyun, hamleler görüldükten sonra gelen ilk başlık satırıyla
  /// ("[Event ...]") başlar. Başlıksız tek oyunlar da doğru çalışır.
  static List<String> splitGames(String text) {
    final games = <String>[];
    var buffer = StringBuffer();
    bool seenMoves = false;

    void flush() {
      final content = buffer.toString().trim();
      if (content.isNotEmpty) games.add(content);
      buffer = StringBuffer();
      seenMoves = false;
    }

    for (final line in const LineSplitter().convert(text)) {
      final trimmed = line.trim();
      final isTag = trimmed.startsWith('[') && trimmed.endsWith(']');
      if (isTag && seenMoves) flush();
      if (!isTag && trimmed.isNotEmpty) seenMoves = true;
      buffer.writeln(line);
    }
    flush();
    return games;
  }

  /// Dosyadaki tüm oyunları çözümler. Okunamayan oyunlar atlanır.
  static List<PgnGame> parseAll(String text) {
    final games = <PgnGame>[];
    for (final chunk in splitGames(text)) {
      final game = _parseOne(chunk);
      if (game != null) games.add(game);
    }
    return games;
  }

  /// [parseAll] ile aynı işi yapar, ama arada olay döngüsüne dönerek
  /// arayüzün donmasını önler ve ilerlemeyi bildirir. Yüzlerce oyunluk
  /// dosyalarda bunu kullan.
  static Future<List<PgnGame>> parseAllAsync(
    String text, {
    void Function(int done, int total)? onProgress,
  }) async {
    final chunks = splitGames(text);
    final games = <PgnGame>[];

    for (int i = 0; i < chunks.length; i++) {
      final game = _parseOne(chunks[i]);
      if (game != null) games.add(game);

      // Her birkaç oyunda bir kareyi çizmeye izin ver.
      if (i % 5 == 4 || i == chunks.length - 1) {
        onProgress?.call(i + 1, chunks.length);
        await Future<void>.delayed(Duration.zero);
      }
    }
    return games;
  }

  static PgnGame? _parseOne(String chunk) {
    final parser = PgnParser();
    if (!parser.parse(chunk) || parser.moves.isEmpty) return null;
    return PgnGame(
      headers: Map<String, String>.from(parser.headers),
      uciMoves: List<String>.from(parser.moves),
      startFen: parser.startFen,
      result: parser.gameResult,
      skippedCount: parser.skippedTokens.length,
    );
  }

  // -------------------------------------------------------------------------
  // PGN ÜRETİMİ
  // -------------------------------------------------------------------------

  /// UCI hamle listesinden okunabilir bir PGN metni üretir.
  static String buildPgn({
    required List<String> uciMoves,
    Map<String, String>? tags,
    String? startFen,
    String? result,
  }) {
    final position = startFen != null
        ? engine.ChessGame.fromFen(startFen)
        : engine.ChessGame();

    final buffer = StringBuffer();
    final headerTags = <String, String>{
      'Event': tags?['Event'] ?? t('app.title'),
      'Site': tags?['Site'] ?? '-',
      'Date': tags?['Date'] ??
          DateTime.now()
              .toIso8601String()
              .substring(0, 10)
              .replaceAll('-', '.'),
      'White': tags?['White'] ?? '?',
      'Black': tags?['Black'] ?? '?',
      'Result': result ?? tags?['Result'] ?? '*',
    };
    if (startFen != null) {
      headerTags['SetUp'] = '1';
      headerTags['FEN'] = startFen;
    }
    headerTags.forEach((key, value) => buffer.writeln('[$key "$value"]'));
    buffer.writeln();

    final parts = <String>[];
    for (int i = 0; i < uciMoves.length; i++) {
      final move = position.moveFromUci(uciMoves[i]);
      if (move == null) break;
      final san = position.sanFor(move);
      if (position.sideToMove == engine.Color.white) {
        parts.add('${position.fullmoveNumber}. $san');
      } else if (i == 0) {
        parts.add('${position.fullmoveNumber}... $san');
      } else {
        parts.add(san);
      }
      position.makeMove(move);
    }
    parts.add(result ?? '*');

    // Satırları 80 karaktere sığdır.
    var line = StringBuffer();
    for (final part in parts) {
      if (line.length + part.length + 1 > 80) {
        buffer.writeln(line.toString());
        line = StringBuffer();
      }
      if (line.isNotEmpty) line.write(' ');
      line.write(part);
    }
    if (line.isNotEmpty) buffer.writeln(line.toString());

    return buffer.toString();
  }
}

/// Bir PGN dosyasından okunmuş tek oyun.
class PgnGame {
  final Map<String, String> headers;
  final List<String> uciMoves;
  final String? startFen;
  final String? result;

  /// Çözümlenemeyen hamle sayısı (0 değilse oyun eksik okunmuştur).
  final int skippedCount;

  const PgnGame({
    required this.headers,
    required this.uciMoves,
    this.startFen,
    this.result,
    this.skippedCount = 0,
  });

  String get white => headers['White'] ?? '?';
  String get black => headers['Black'] ?? '?';
  String get event => headers['Event'] ?? '';
  String get date => headers['Date'] ?? '';
  int get moveCount => uciMoves.length;

  /// Listede gösterilecek ad: "Karpov - Kasparov".
  String get title {
    if (white == '?' && black == '?') {
      return event.isNotEmpty ? event : 'PGN';
    }
    return '$white - $black';
  }

  /// Ad altında gösterilen ayrıntı satırı.
  String get subtitle {
    final parts = <String>[];
    if (event.isNotEmpty && event != '?') parts.add(event);
    if (date.isNotEmpty && date != '?' && date != '????.??.??') parts.add(date);
    return parts.join(' · ');
  }
}
