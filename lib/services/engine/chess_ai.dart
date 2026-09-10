/// Cihazda (offline) çalışan satranç motoru.
///
/// Bu dosya bilinçli olarak Flutter'dan bağımsızdır: sadece `dart:*`
/// kullanır, böylece bir `Isolate` içinde çalıştırılabilir ve arayüz
/// hiçbir zaman donmaz. Arama tarafındaki temsil, `models/chess_engine.dart`
/// içindeki nesne tabanlı temsilden ayrıdır; orası okunabilirlik, burası
/// hız için tasarlanmıştır (düz dizi tahta, yap/geri-al, tahsis yok).
///
/// Kare numaralandırması uygulamanın geri kalanıyla aynıdır:
/// `index = satır * 8 + sütun`, satır 0 = 8. yatay, sütun 0 = a dosyası.
library;

import 'dart:math' as math;

// ---------------------------------------------------------------------------
// Taş kodları
// ---------------------------------------------------------------------------

const int kEmpty = 0;
const int wPawn = 1, wKnight = 2, wBishop = 3, wRook = 4, wQueen = 5, wKing = 6;
const int bPawn = 7, bKnight = 8, bBishop = 9, bRook = 10, bQueen = 11;
const int bKing = 12;

const int white = 0;
const int black = 1;

int pieceColor(int piece) => piece >= bPawn ? black : white;
int pieceKind(int piece) => piece >= bPawn ? piece - 6 : piece; // 1..6

/// Rok hakkı bitleri.
const int castleWK = 1, castleWQ = 2, castleBK = 4, castleBQ = 8;

/// Hamle bayrakları.
const int flagEnPassant = 1, flagCastle = 2, flagDoublePush = 4;

/// Hamle 32 bitlik bir tamsayıya sıkıştırılır:
/// `from | to << 6 | promo << 12 | flags << 15`
/// promo: 0 yok, 2=at, 3=fil, 4=kale, 5=vezir (taş türü kodları).
int encodeMove(int from, int to, {int promo = 0, int flags = 0}) =>
    from | (to << 6) | (promo << 12) | (flags << 15);

int moveFrom(int move) => move & 63;
int moveTo(int move) => (move >> 6) & 63;
int movePromo(int move) => (move >> 12) & 7;
int moveFlags(int move) => (move >> 15) & 7;

const String _files = 'abcdefgh';

String squareName(int index) => '${_files[index % 8]}${8 - index ~/ 8}';

int? squareIndex(String name) {
  if (name.length < 2) return null;
  final file = _files.indexOf(name[0].toLowerCase());
  final rank = int.tryParse(name[1]);
  if (file < 0 || rank == null || rank < 1 || rank > 8) return null;
  return (8 - rank) * 8 + file;
}

/// UCI gösterimi ("e2e4", "e7e8q").
String moveToUci(int move) {
  final buffer = StringBuffer()
    ..write(squareName(moveFrom(move)))
    ..write(squareName(moveTo(move)));
  switch (movePromo(move)) {
    case wQueen:
      buffer.write('q');
      break;
    case wRook:
      buffer.write('r');
      break;
    case wBishop:
      buffer.write('b');
      break;
    case wKnight:
      buffer.write('n');
      break;
  }
  return buffer.toString();
}

// ---------------------------------------------------------------------------
// Önceden hesaplanmış hamle tabloları
// ---------------------------------------------------------------------------

class _Tables {
  static final List<List<int>> knight = _buildStep([
    [-2, -1],
    [-2, 1],
    [-1, -2],
    [-1, 2],
    [1, -2],
    [1, 2],
    [2, -1],
    [2, 1],
  ]);

  static final List<List<int>> king = _buildStep([
    [-1, -1],
    [-1, 0],
    [-1, 1],
    [0, -1],
    [0, 1],
    [1, -1],
    [1, 0],
    [1, 1],
  ]);

  /// Her kare için 8 yönde ışın; 0-3 çapraz, 4-7 düz.
  static final List<List<List<int>>> rays = _buildRays();

  static List<List<int>> _buildStep(List<List<int>> deltas) {
    return List.generate(64, (index) {
      final row = index ~/ 8, col = index % 8;
      final targets = <int>[];
      for (final d in deltas) {
        final r = row + d[0], c = col + d[1];
        if (r >= 0 && r < 8 && c >= 0 && c < 8) targets.add(r * 8 + c);
      }
      return targets;
    });
  }

  static List<List<List<int>>> _buildRays() {
    const dirs = [
      [-1, -1], [-1, 1], [1, -1], [1, 1], // çapraz
      [-1, 0], [1, 0], [0, -1], [0, 1], // düz
    ];
    return List.generate(64, (index) {
      final row = index ~/ 8, col = index % 8;
      return List.generate(8, (d) {
        final ray = <int>[];
        int r = row + dirs[d][0], c = col + dirs[d][1];
        while (r >= 0 && r < 8 && c >= 0 && c < 8) {
          ray.add(r * 8 + c);
          r += dirs[d][0];
          c += dirs[d][1];
        }
        return ray;
      });
    });
  }
}

// ---------------------------------------------------------------------------
// Zobrist anahtarları
// ---------------------------------------------------------------------------

class _Zobrist {
  static final List<List<int>> pieces = _init();
  static final List<int> castling = List.generate(16, (_) => _rand());
  static final List<int> enPassantFile = List.generate(8, (_) => _rand());
  static final int side = _rand();

  static final math.Random _random = math.Random(0x5EED);

  /// Anahtarlar 16 bitlik parçalardan kurulur.
  ///
  /// `nextInt(1 << 32)` taşınabilir değildir: JavaScript'e derlenen kodda
  /// kaydırma 32 bit üzerinden yapıldığı için `1 << 32` sıfıra düşer ve
  /// `nextInt(0)` hata fırlatır.
  static int _rand() {
    int value = 0;
    for (int i = 0; i < 4; i++) {
      value = (value << 16) ^ _random.nextInt(1 << 16);
    }
    return value;
  }

  static List<List<int>> _init() =>
      List.generate(13, (_) => List.generate(64, (_) => _rand()));
}

// ---------------------------------------------------------------------------
// Yap / geri-al kaydı
// ---------------------------------------------------------------------------

class _Undo {
  int move = 0;
  int captured = kEmpty;
  int castling = 0;
  int enPassant = -1;
  int halfmove = 0;
  int hash = 0;
}

// ---------------------------------------------------------------------------
// Pozisyon
// ---------------------------------------------------------------------------

class AiPosition {
  final List<int> squares = List<int>.filled(64, kEmpty);
  int side = white;
  int castling = 0;
  int enPassant = -1;
  int halfmove = 0;
  int fullmove = 1;
  int hash = 0;

  final List<_Undo> _undoStack = List.generate(256, (_) => _Undo());
  int _ply = 0;

  /// Tekrar tespiti için oynanan konumların hash geçmişi.
  final List<int> historyHashes = <int>[];

  /// Beyaz ve siyah şahın bulunduğu kareler; her hamlede güncellenir.
  final List<int> kingSquares = <int>[-1, -1];

  AiPosition.fromFen(String fen) {
    final parts = fen.trim().split(RegExp(r'\s+'));
    final rows = parts[0].split('/');
    for (int row = 0; row < 8 && row < rows.length; row++) {
      int col = 0;
      for (final rune in rows[row].runes) {
        final char = String.fromCharCode(rune);
        final digit = int.tryParse(char);
        if (digit != null) {
          col += digit;
          continue;
        }
        if (col > 7) break;
        squares[row * 8 + col] = _pieceFromChar(char);
        col++;
      }
    }
    side = (parts.length > 1 && parts[1] == 'b') ? black : white;
    final rights = parts.length > 2 ? parts[2] : '-';
    if (rights.contains('K')) castling |= castleWK;
    if (rights.contains('Q')) castling |= castleWQ;
    if (rights.contains('k')) castling |= castleBK;
    if (rights.contains('q')) castling |= castleBQ;
    if (parts.length > 3 && parts[3] != '-') {
      enPassant = squareIndex(parts[3]) ?? -1;
    }
    halfmove = parts.length > 4 ? (int.tryParse(parts[4]) ?? 0) : 0;
    fullmove = parts.length > 5 ? (int.tryParse(parts[5]) ?? 1) : 1;
    kingSquares[white] = squares.indexOf(wKing);
    kingSquares[black] = squares.indexOf(bKing);
    hash = _computeHash();
    historyHashes.add(hash);
  }

  static int _pieceFromChar(String char) {
    switch (char) {
      case 'P':
        return wPawn;
      case 'N':
        return wKnight;
      case 'B':
        return wBishop;
      case 'R':
        return wRook;
      case 'Q':
        return wQueen;
      case 'K':
        return wKing;
      case 'p':
        return bPawn;
      case 'n':
        return bKnight;
      case 'b':
        return bBishop;
      case 'r':
        return bRook;
      case 'q':
        return bQueen;
      case 'k':
        return bKing;
      default:
        return kEmpty;
    }
  }

  int _computeHash() {
    int h = 0;
    for (int i = 0; i < 64; i++) {
      final piece = squares[i];
      if (piece != kEmpty) h ^= _Zobrist.pieces[piece][i];
    }
    h ^= _Zobrist.castling[castling];
    if (enPassant >= 0) h ^= _Zobrist.enPassantFile[enPassant % 8];
    if (side == black) h ^= _Zobrist.side;
    return h;
  }

  int kingSquare(int color) => kingSquares[color];

  bool get inCheck {
    final ks = kingSquare(side);
    return ks >= 0 && isAttacked(ks, side ^ 1);
  }

  /// [square] karesi [byColor] tarafından tehdit ediliyor mu?
  bool isAttacked(int square, int byColor) {
    // Piyon
    final row = square ~/ 8, col = square % 8;
    final pawnRow = byColor == white ? row + 1 : row - 1;
    if (pawnRow >= 0 && pawnRow < 8) {
      final pawn = byColor == white ? wPawn : bPawn;
      if (col > 0 && squares[pawnRow * 8 + col - 1] == pawn) return true;
      if (col < 7 && squares[pawnRow * 8 + col + 1] == pawn) return true;
    }

    // At
    final knight = byColor == white ? wKnight : bKnight;
    for (final target in _Tables.knight[square]) {
      if (squares[target] == knight) return true;
    }

    // Şah
    final king = byColor == white ? wKing : bKing;
    for (final target in _Tables.king[square]) {
      if (squares[target] == king) return true;
    }

    // Kayan taşlar
    final bishop = byColor == white ? wBishop : bBishop;
    final rook = byColor == white ? wRook : bRook;
    final queen = byColor == white ? wQueen : bQueen;
    final rays = _Tables.rays[square];
    for (int d = 0; d < 8; d++) {
      final ray = rays[d];
      for (int i = 0; i < ray.length; i++) {
        final piece = squares[ray[i]];
        if (piece == kEmpty) continue;
        if (d < 4) {
          if (piece == bishop || piece == queen) return true;
        } else {
          if (piece == rook || piece == queen) return true;
        }
        break;
      }
    }
    return false;
  }

  // -------------------------------------------------------------------------
  // Hamle üretimi
  // -------------------------------------------------------------------------

  /// Sözde yasal hamleler. [capturesOnly] ise sadece almalar ve terfiler.
  List<int> generateMoves({bool capturesOnly = false}) {
    final moves = <int>[];
    final me = side;
    final them = me ^ 1;

    for (int from = 0; from < 64; from++) {
      final piece = squares[from];
      if (piece == kEmpty || pieceColor(piece) != me) continue;
      final kind = pieceKind(piece);

      switch (kind) {
        case wPawn:
          _pawnMoves(moves, from, me, capturesOnly);
          break;
        case wKnight:
          for (final to in _Tables.knight[from]) {
            final target = squares[to];
            if (target != kEmpty && pieceColor(target) == me) continue;
            if (capturesOnly && target == kEmpty) continue;
            moves.add(encodeMove(from, to));
          }
          break;
        case wKing:
          for (final to in _Tables.king[from]) {
            final target = squares[to];
            if (target != kEmpty && pieceColor(target) == me) continue;
            if (capturesOnly && target == kEmpty) continue;
            moves.add(encodeMove(from, to));
          }
          if (!capturesOnly) _castleMoves(moves, from, me, them);
          break;
        default:
          final start = kind == wRook ? 4 : 0;
          final end = kind == wBishop ? 4 : 8;
          final rays = _Tables.rays[from];
          for (int d = start; d < end; d++) {
            final ray = rays[d];
            for (int i = 0; i < ray.length; i++) {
              final to = ray[i];
              final target = squares[to];
              if (target == kEmpty) {
                if (!capturesOnly) moves.add(encodeMove(from, to));
                continue;
              }
              if (pieceColor(target) != me) moves.add(encodeMove(from, to));
              break;
            }
          }
      }
    }
    return moves;
  }

  void _pawnMoves(List<int> moves, int from, int me, bool capturesOnly) {
    final dir = me == white ? -8 : 8;
    final row = from ~/ 8, col = from % 8;
    final startRow = me == white ? 6 : 1;
    final promoRow = me == white ? 0 : 7;

    final one = from + dir;
    if (one >= 0 && one < 64 && squares[one] == kEmpty) {
      if (one ~/ 8 == promoRow) {
        for (final promo in const [wQueen, wRook, wBishop, wKnight]) {
          moves.add(encodeMove(from, one, promo: promo));
        }
      } else if (!capturesOnly) {
        moves.add(encodeMove(from, one));
        final two = one + dir;
        if (row == startRow && squares[two] == kEmpty) {
          moves.add(encodeMove(from, two, flags: flagDoublePush));
        }
      }
    }

    for (final dc in const [-1, 1]) {
      final c = col + dc;
      if (c < 0 || c > 7) continue;
      final to = one + dc;
      if (to < 0 || to > 63) continue;
      final target = squares[to];
      if (target != kEmpty && pieceColor(target) != me) {
        if (to ~/ 8 == promoRow) {
          for (final promo in const [wQueen, wRook, wBishop, wKnight]) {
            moves.add(encodeMove(from, to, promo: promo));
          }
        } else {
          moves.add(encodeMove(from, to));
        }
      } else if (target == kEmpty && to == enPassant) {
        moves.add(encodeMove(from, to, flags: flagEnPassant));
      }
    }
  }

  void _castleMoves(List<int> moves, int from, int me, int them) {
    if (me == white) {
      if (from != 60) return;
      if (isAttacked(60, them)) return;
      if ((castling & castleWK) != 0 &&
          squares[61] == kEmpty &&
          squares[62] == kEmpty &&
          squares[63] == wRook &&
          !isAttacked(61, them) &&
          !isAttacked(62, them)) {
        moves.add(encodeMove(60, 62, flags: flagCastle));
      }
      if ((castling & castleWQ) != 0 &&
          squares[59] == kEmpty &&
          squares[58] == kEmpty &&
          squares[57] == kEmpty &&
          squares[56] == wRook &&
          !isAttacked(59, them) &&
          !isAttacked(58, them)) {
        moves.add(encodeMove(60, 58, flags: flagCastle));
      }
    } else {
      if (from != 4) return;
      if (isAttacked(4, them)) return;
      if ((castling & castleBK) != 0 &&
          squares[5] == kEmpty &&
          squares[6] == kEmpty &&
          squares[7] == bRook &&
          !isAttacked(5, them) &&
          !isAttacked(6, them)) {
        moves.add(encodeMove(4, 6, flags: flagCastle));
      }
      if ((castling & castleBQ) != 0 &&
          squares[3] == kEmpty &&
          squares[2] == kEmpty &&
          squares[1] == kEmpty &&
          squares[0] == bRook &&
          !isAttacked(3, them) &&
          !isAttacked(2, them)) {
        moves.add(encodeMove(4, 2, flags: flagCastle));
      }
    }
  }

  /// Sadece gerçekten yasal olan hamleler (kendi şahını açıkta bırakmayanlar).
  List<int> generateLegalMoves() {
    final legal = <int>[];
    for (final move in generateMoves()) {
      if (makeMove(move)) {
        undoMove();
        legal.add(move);
      }
    }
    return legal;
  }

  // -------------------------------------------------------------------------
  // Yap / geri-al
  // -------------------------------------------------------------------------

  /// Hamleyi oynar. Hamle kendi şahını tehdide açık bırakıyorsa geri alır
  /// ve `false` döner.
  bool makeMove(int move) {
    final undo = _undoStack[_ply];
    undo
      ..move = move
      ..castling = castling
      ..enPassant = enPassant
      ..halfmove = halfmove
      ..hash = hash;

    final from = moveFrom(move);
    final to = moveTo(move);
    final flags = moveFlags(move);
    final promo = movePromo(move);
    final piece = squares[from];
    final me = side;
    int captured = squares[to];

    if (enPassant >= 0) hash ^= _Zobrist.enPassantFile[enPassant % 8];
    hash ^= _Zobrist.castling[castling];

    // En passant alma
    if (flags == flagEnPassant) {
      final capturedSquare = me == white ? to + 8 : to - 8;
      captured = squares[capturedSquare];
      squares[capturedSquare] = kEmpty;
      hash ^= _Zobrist.pieces[captured][capturedSquare];
    } else if (captured != kEmpty) {
      hash ^= _Zobrist.pieces[captured][to];
    }
    undo.captured = captured;

    squares[from] = kEmpty;
    hash ^= _Zobrist.pieces[piece][from];

    int placed = piece;
    if (promo != 0) placed = me == white ? promo : promo + 6;
    squares[to] = placed;
    hash ^= _Zobrist.pieces[placed][to];
    if (pieceKind(placed) == wKing) kingSquares[me] = to;

    // Rok: kaleyi de taşı
    if (flags == flagCastle) {
      final rookFrom = to > from ? to + 1 : to - 2;
      final rookTo = to > from ? to - 1 : to + 1;
      final rook = squares[rookFrom];
      squares[rookFrom] = kEmpty;
      squares[rookTo] = rook;
      hash ^= _Zobrist.pieces[rook][rookFrom] ^ _Zobrist.pieces[rook][rookTo];
    }

    // Rok haklarını güncelle
    castling &= _castleMask(from) & _castleMask(to);
    hash ^= _Zobrist.castling[castling];

    // En passant hedefi
    enPassant = flags == flagDoublePush ? (from + to) ~/ 2 : -1;
    if (enPassant >= 0) hash ^= _Zobrist.enPassantFile[enPassant % 8];

    halfmove =
        (pieceKind(piece) == wPawn || captured != kEmpty) ? 0 : halfmove + 1;
    if (me == black) fullmove++;

    side ^= 1;
    hash ^= _Zobrist.side;
    _ply++;

    // Yasallık: hamleden sonra kendi şahı tehdit altında olmamalı.
    final kingSq = kingSquare(me);
    if (kingSq >= 0 && isAttacked(kingSq, me ^ 1)) {
      undoMove();
      return false;
    }
    return true;
  }

  void undoMove() {
    _ply--;
    final undo = _undoStack[_ply];
    final move = undo.move;
    final from = moveFrom(move);
    final to = moveTo(move);
    final flags = moveFlags(move);
    final promo = movePromo(move);

    side ^= 1;
    if (side == black) fullmove--;

    int piece = squares[to];
    if (promo != 0) piece = side == white ? wPawn : bPawn;
    squares[from] = piece;
    squares[to] = kEmpty;
    if (pieceKind(piece) == wKing) kingSquares[side] = from;

    if (flags == flagEnPassant) {
      final capturedSquare = side == white ? to + 8 : to - 8;
      squares[capturedSquare] = undo.captured;
    } else if (undo.captured != kEmpty) {
      squares[to] = undo.captured;
    }

    if (flags == flagCastle) {
      final rookFrom = to > from ? to + 1 : to - 2;
      final rookTo = to > from ? to - 1 : to + 1;
      squares[rookFrom] = squares[rookTo];
      squares[rookTo] = kEmpty;
    }

    castling = undo.castling;
    enPassant = undo.enPassant;
    halfmove = undo.halfmove;
    hash = undo.hash;
  }

  /// Bir kareden hareket eden ya da bir kareye giren taşın hangi rok
  /// haklarını düşürdüğünü belirten maske.
  static int _castleMask(int square) {
    switch (square) {
      case 60:
        return ~(castleWK | castleWQ);
      case 63:
        return ~castleWK;
      case 56:
        return ~castleWQ;
      case 4:
        return ~(castleBK | castleBQ);
      case 7:
        return ~castleBK;
      case 0:
        return ~castleBQ;
      default:
        return ~0;
    }
  }

  /// Piyon dışı materyali olan taraf var mı (sıfır hamle budaması için).
  bool hasNonPawnMaterial(int color) {
    for (int i = 0; i < 64; i++) {
      final piece = squares[i];
      if (piece == kEmpty || pieceColor(piece) != color) continue;
      final kind = pieceKind(piece);
      if (kind != wPawn && kind != wKing) return true;
    }
    return false;
  }
}

// ---------------------------------------------------------------------------
// Değerlendirme
// ---------------------------------------------------------------------------

class _Eval {
  static const List<int> midValues = [0, 82, 337, 365, 477, 1025, 0];
  static const List<int> endValues = [0, 94, 281, 297, 512, 936, 0];

  /// Faz ağırlıkları (oyun sonu geçişi için).
  static const List<int> phaseWeights = [0, 0, 1, 1, 2, 4, 0];
  static const int totalPhase = 24;

  // Kare-taş tabloları beyaz bakış açısıyla, a8 = 0.
  static const List<int> pawnMid = [
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    98,
    134,
    61,
    95,
    68,
    126,
    34,
    -11,
    -6,
    7,
    26,
    31,
    65,
    56,
    25,
    -20,
    -14,
    13,
    6,
    21,
    23,
    12,
    17,
    -23,
    -27,
    -2,
    -5,
    12,
    17,
    6,
    10,
    -25,
    -26,
    -4,
    -4,
    -10,
    3,
    3,
    33,
    -12,
    -35,
    -1,
    -20,
    -23,
    -15,
    24,
    38,
    -22,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
  ];
  static const List<int> pawnEnd = [
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    178,
    173,
    158,
    134,
    147,
    132,
    165,
    187,
    94,
    100,
    85,
    67,
    56,
    53,
    82,
    84,
    32,
    24,
    13,
    5,
    -2,
    4,
    17,
    17,
    13,
    9,
    -3,
    -7,
    -7,
    -8,
    3,
    -1,
    4,
    7,
    -6,
    1,
    0,
    -5,
    -1,
    -8,
    13,
    8,
    8,
    10,
    13,
    0,
    2,
    -7,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
  ];
  static const List<int> knightMid = [
    -167,
    -89,
    -34,
    -49,
    61,
    -97,
    -15,
    -107,
    -73,
    -41,
    72,
    36,
    23,
    62,
    7,
    -17,
    -47,
    60,
    37,
    65,
    84,
    129,
    73,
    44,
    -9,
    17,
    19,
    53,
    37,
    69,
    18,
    22,
    -13,
    4,
    16,
    13,
    28,
    19,
    21,
    -8,
    -23,
    -9,
    12,
    10,
    19,
    17,
    25,
    -16,
    -29,
    -53,
    -12,
    -3,
    -1,
    18,
    -14,
    -19,
    -105,
    -21,
    -58,
    -33,
    -17,
    -28,
    -19,
    -23,
  ];
  static const List<int> knightEnd = [
    -58,
    -38,
    -13,
    -28,
    -31,
    -27,
    -63,
    -99,
    -25,
    -8,
    -25,
    -2,
    -9,
    -25,
    -24,
    -52,
    -24,
    -20,
    10,
    9,
    -1,
    -9,
    -19,
    -41,
    -17,
    3,
    22,
    22,
    22,
    11,
    8,
    -18,
    -18,
    -6,
    16,
    25,
    16,
    17,
    4,
    -18,
    -23,
    -3,
    -1,
    15,
    10,
    -3,
    -20,
    -22,
    -42,
    -20,
    -10,
    -5,
    -2,
    -20,
    -23,
    -44,
    -29,
    -51,
    -23,
    -15,
    -22,
    -18,
    -50,
    -64,
  ];
  static const List<int> bishopMid = [
    -29,
    4,
    -82,
    -37,
    -25,
    -42,
    7,
    -8,
    -26,
    16,
    -18,
    -13,
    30,
    59,
    18,
    -47,
    -16,
    37,
    43,
    40,
    35,
    50,
    37,
    -2,
    -4,
    5,
    19,
    50,
    37,
    37,
    7,
    -2,
    -6,
    13,
    13,
    26,
    34,
    12,
    10,
    4,
    0,
    15,
    15,
    15,
    14,
    27,
    18,
    10,
    4,
    15,
    16,
    0,
    7,
    21,
    33,
    1,
    -33,
    -3,
    -14,
    -21,
    -13,
    -12,
    -39,
    -21,
  ];
  static const List<int> bishopEnd = [
    -14,
    -21,
    -11,
    -8,
    -7,
    -9,
    -17,
    -24,
    -8,
    -4,
    7,
    -12,
    -3,
    -13,
    -4,
    -14,
    2,
    -8,
    0,
    -1,
    -2,
    6,
    0,
    4,
    -3,
    9,
    12,
    9,
    14,
    10,
    3,
    2,
    -6,
    3,
    13,
    19,
    7,
    10,
    -3,
    -9,
    -12,
    -3,
    8,
    10,
    13,
    3,
    -7,
    -15,
    -14,
    -18,
    -7,
    -1,
    4,
    -9,
    -15,
    -27,
    -23,
    -9,
    -23,
    -5,
    -9,
    -16,
    -5,
    -17,
  ];
  static const List<int> rookMid = [
    32,
    42,
    32,
    51,
    63,
    9,
    31,
    43,
    27,
    32,
    58,
    62,
    80,
    67,
    26,
    44,
    -5,
    19,
    26,
    36,
    17,
    45,
    61,
    16,
    -24,
    -11,
    7,
    26,
    24,
    35,
    -8,
    -20,
    -36,
    -26,
    -12,
    -1,
    9,
    -7,
    6,
    -23,
    -45,
    -25,
    -16,
    -17,
    3,
    0,
    -5,
    -33,
    -44,
    -16,
    -20,
    -9,
    -1,
    11,
    -6,
    -71,
    -19,
    -13,
    1,
    17,
    16,
    7,
    -37,
    -26,
  ];
  static const List<int> rookEnd = [
    13,
    10,
    18,
    15,
    12,
    12,
    8,
    5,
    11,
    13,
    13,
    11,
    -3,
    3,
    8,
    3,
    7,
    7,
    7,
    5,
    4,
    -3,
    -5,
    -3,
    4,
    3,
    13,
    1,
    2,
    1,
    -1,
    2,
    3,
    5,
    8,
    4,
    -5,
    -6,
    -8,
    -11,
    -4,
    0,
    -5,
    -1,
    -7,
    -12,
    -8,
    -16,
    -6,
    -6,
    0,
    2,
    -9,
    -9,
    -11,
    -3,
    -9,
    2,
    3,
    -1,
    -5,
    -13,
    4,
    -20,
  ];
  static const List<int> queenMid = [
    -28,
    0,
    29,
    12,
    59,
    44,
    43,
    45,
    -24,
    -39,
    -5,
    1,
    -16,
    57,
    28,
    54,
    -13,
    -17,
    7,
    8,
    29,
    56,
    47,
    57,
    -27,
    -27,
    -16,
    -16,
    -1,
    17,
    -2,
    1,
    -9,
    -26,
    -9,
    -10,
    -2,
    -4,
    3,
    -3,
    -14,
    2,
    -11,
    -2,
    -5,
    2,
    14,
    5,
    -35,
    -8,
    11,
    2,
    8,
    15,
    -3,
    1,
    -1,
    -18,
    -9,
    10,
    -15,
    -25,
    -31,
    -50,
  ];
  static const List<int> queenEnd = [
    -9,
    22,
    22,
    27,
    27,
    19,
    10,
    20,
    -17,
    20,
    32,
    41,
    58,
    25,
    30,
    0,
    -20,
    6,
    9,
    49,
    47,
    35,
    19,
    9,
    3,
    22,
    24,
    45,
    57,
    40,
    57,
    36,
    -18,
    28,
    19,
    47,
    31,
    34,
    39,
    23,
    -16,
    -27,
    15,
    6,
    9,
    17,
    10,
    5,
    -22,
    -23,
    -30,
    -16,
    -16,
    -23,
    -36,
    -32,
    -33,
    -28,
    -22,
    -43,
    -5,
    -32,
    -20,
    -41,
  ];
  static const List<int> kingMid = [
    -65,
    23,
    16,
    -15,
    -56,
    -34,
    2,
    13,
    29,
    -1,
    -20,
    -7,
    -8,
    -4,
    -38,
    -29,
    -9,
    24,
    2,
    -16,
    -20,
    6,
    22,
    -22,
    -17,
    -20,
    -12,
    -27,
    -30,
    -25,
    -14,
    -36,
    -49,
    -1,
    -27,
    -39,
    -46,
    -44,
    -33,
    -51,
    -14,
    -14,
    -22,
    -46,
    -44,
    -30,
    -15,
    -27,
    1,
    7,
    -8,
    -64,
    -43,
    -16,
    9,
    8,
    -15,
    36,
    12,
    -54,
    8,
    -28,
    24,
    14,
  ];
  static const List<int> kingEnd = [
    -74,
    -35,
    -18,
    -18,
    -11,
    15,
    4,
    -17,
    -12,
    17,
    14,
    17,
    17,
    38,
    23,
    11,
    10,
    17,
    23,
    15,
    20,
    45,
    44,
    13,
    -8,
    22,
    24,
    27,
    26,
    33,
    26,
    3,
    -18,
    -4,
    21,
    24,
    27,
    23,
    9,
    -11,
    -19,
    -3,
    11,
    21,
    23,
    16,
    7,
    -9,
    -27,
    -11,
    4,
    13,
    14,
    4,
    -5,
    -17,
    -53,
    -34,
    -21,
    -11,
    -28,
    -14,
    -24,
    -43,
  ];

  static final List<List<int>> midTables = [
    const [],
    pawnMid,
    knightMid,
    bishopMid,
    rookMid,
    queenMid,
    kingMid,
  ];
  static final List<List<int>> endTables = [
    const [],
    pawnEnd,
    knightEnd,
    bishopEnd,
    rookEnd,
    queenEnd,
    kingEnd,
  ];

  /// Hamle sırası olan tarafın bakış açısından skor (santipiyon).
  static int evaluate(AiPosition pos) {
    int midScore = 0, endScore = 0, phase = 0;
    final pawnFiles = [List<int>.filled(8, 0), List<int>.filled(8, 0)];
    final bishops = [0, 0];

    for (int i = 0; i < 64; i++) {
      final piece = pos.squares[i];
      if (piece == kEmpty) continue;
      final color = pieceColor(piece);
      final kind = pieceKind(piece);
      // Siyah için tabloyu dikey olarak yansıt.
      final tableIndex = color == white ? i : (7 - i ~/ 8) * 8 + i % 8;
      final sign = color == white ? 1 : -1;

      midScore += sign * (midValues[kind] + midTables[kind][tableIndex]);
      endScore += sign * (endValues[kind] + endTables[kind][tableIndex]);
      phase += phaseWeights[kind];

      if (kind == wPawn) pawnFiles[color][i % 8]++;
      if (kind == wBishop) bishops[color]++;
    }

    // Fil çifti
    if (bishops[white] >= 2) {
      midScore += 30;
      endScore += 45;
    }
    if (bishops[black] >= 2) {
      midScore -= 30;
      endScore -= 45;
    }

    // Çift ve izole piyonlar
    for (int color = 0; color < 2; color++) {
      final sign = color == white ? 1 : -1;
      for (int file = 0; file < 8; file++) {
        final count = pawnFiles[color][file];
        if (count == 0) continue;
        if (count > 1) {
          midScore -= sign * 12 * (count - 1);
          endScore -= sign * 24 * (count - 1);
        }
        final left = file > 0 ? pawnFiles[color][file - 1] : 0;
        final right = file < 7 ? pawnFiles[color][file + 1] : 0;
        if (left == 0 && right == 0) {
          midScore -= sign * 16;
          endScore -= sign * 20;
        }
      }
    }

    if (phase > totalPhase) phase = totalPhase;
    final score =
        (midScore * phase + endScore * (totalPhase - phase)) ~/ totalPhase;
    return pos.side == white ? score : -score;
  }
}

// ---------------------------------------------------------------------------
// Arama
// ---------------------------------------------------------------------------

/// Aramanın ürettiği sonuç.
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

class _TtEntry {
  final int depth;
  final int score;
  final int flag; // 0 kesin, 1 alt sınır, 2 üst sınır
  final int move;
  const _TtEntry(this.depth, this.score, this.flag, this.move);
}

const int _mateScore = 30000;
const int _infinity = 40000;

/// Negamax + alfa-beta arama motoru.
class ChessAi {
  static const int maxPly = 64;

  final Map<int, _TtEntry> _tt = <int, _TtEntry>{};
  final List<List<int>> _killers = List.generate(maxPly, (_) => <int>[0, 0]);
  final List<List<int>> _history = List.generate(
    13,
    (_) => List<int>.filled(64, 0),
  );

  int _nodes = 0;
  int _deadline = 0;
  bool _aborted = false;

  /// Verilen FEN için en iyi hamleyi arar.
  ///
  /// [movetimeMs] süre sınırı, [maxDepth] derinlik sınırı. Hangisi önce
  /// dolarsa arama orada biter. [onProgress] her tamamlanan derinlikte
  /// çağrılır (isolate'ten arayüze ilerleme göndermek için).
  SearchResult search(
    String fen, {
    int maxDepth = 12,
    int movetimeMs = 1500,
    int skill = 20,
    List<int>? repetitionHashes,
    void Function(SearchResult partial)? onProgress,
  }) {
    final pos = AiPosition.fromFen(fen);
    if (repetitionHashes != null) {
      pos.historyHashes
        ..clear()
        ..addAll(repetitionHashes);
    }

    _tt.clear();
    _nodes = 0;
    _aborted = false;
    _deadline = DateTime.now().millisecondsSinceEpoch + movetimeMs;
    for (final killer in _killers) {
      killer[0] = 0;
      killer[1] = 0;
    }
    for (final row in _history) {
      for (int i = 0; i < 64; i++) {
        row[i] = 0;
      }
    }

    final rootMoves = pos.generateLegalMoves();
    if (rootMoves.isEmpty) {
      final mated = pos.inCheck;
      return SearchResult(
        bestMoveUci: '',
        scoreCp: mated ? -_mateScore : 0,
        mateIn: mated ? 0 : null,
        depth: 0,
        nodes: 0,
        pvUci: const [],
        isGameOver: true,
      );
    }

    int bestMove = rootMoves.first;
    int bestScore = 0;
    int completedDepth = 0;
    List<int> bestPv = [bestMove];

    for (int depth = 1; depth <= maxDepth; depth++) {
      final scored = <int, int>{};
      int alpha = -_infinity;
      int localBest = bestMove;
      int localBestScore = -_infinity;

      // Önceki yinelemenin en iyi hamlesini öne al.
      rootMoves.sort((a, b) {
        if (a == bestMove) return -1;
        if (b == bestMove) return 1;
        return 0;
      });

      for (final move in rootMoves) {
        if (!pos.makeMove(move)) continue;
        final window = skill >= 20 ? alpha : -_infinity;
        final score = -_negamax(pos, depth - 1, -_infinity, -window, 1, true);
        pos.undoMove();
        if (_aborted) break;
        scored[move] = score;
        if (score > localBestScore) {
          localBestScore = score;
          localBest = move;
          if (score > alpha) alpha = score;
        }
      }

      if (_aborted && completedDepth > 0) break;

      bestMove = _applySkill(localBest, scored, skill);
      bestScore = scored[bestMove] ?? localBestScore;
      completedDepth = depth;
      bestPv = _extractPv(pos, bestMove, depth);

      onProgress?.call(_buildResult(bestMove, bestScore, depth, bestPv));

      // Kesin mat bulunduysa daha derine inmeye gerek yok.
      if (bestScore.abs() >= _mateScore - maxPly) break;
      if (_timeUp()) break;
    }

    return _buildResult(bestMove, bestScore, completedDepth, bestPv);
  }

  SearchResult _buildResult(int move, int score, int depth, List<int> pv) {
    int? mateIn;
    if (score.abs() >= _mateScore - maxPly) {
      final plies = _mateScore - score.abs();
      mateIn = ((plies + 1) ~/ 2) * (score > 0 ? 1 : -1);
    }
    return SearchResult(
      bestMoveUci: moveToUci(move),
      scoreCp: score,
      mateIn: mateIn,
      depth: depth,
      nodes: _nodes,
      pvUci: pv.map(moveToUci).toList(),
    );
  }

  /// Seviye düşükse motoru bilerek zayıflatır: en iyi hamle yerine ona
  /// yakın hamlelerden biri seçilir. `skill` 20 = tam güç.
  int _applySkill(int best, Map<int, int> scored, int skill) {
    if (skill >= 20 || scored.length < 2) return best;
    final bestScore = scored[best]!;
    // Seviye düştükçe kabul edilen skor kaybı artar.
    final tolerance = (20 - skill) * 22;
    final candidates = scored.entries
        .where((e) => bestScore - e.value <= tolerance)
        .map((e) => e.key)
        .toList();
    if (candidates.length <= 1) return best;
    final random = math.Random();
    // Yine de çoğu zaman iyi hamleyi oynasın: %35 ihtimalle alternatif.
    return random.nextDouble() < 0.35
        ? candidates[random.nextInt(candidates.length)]
        : best;
  }

  List<int> _extractPv(AiPosition pos, int firstMove, int maxLength) {
    final pv = <int>[];
    int made = 0;
    int move = firstMove;
    while (pv.length < maxLength) {
      if (!pos.makeMove(move)) break;
      pv.add(move);
      made++;
      final entry = _tt[pos.hash];
      if (entry == null || entry.move == 0) break;
      final legal = pos.generateLegalMoves();
      if (!legal.contains(entry.move)) break;
      move = entry.move;
    }
    for (int i = 0; i < made; i++) {
      pos.undoMove();
    }
    return pv;
  }

  bool _timeUp() {
    if (_aborted) return true;
    if ((_nodes & 1023) != 0) return false;
    if (DateTime.now().millisecondsSinceEpoch >= _deadline) {
      _aborted = true;
      return true;
    }
    return false;
  }

  int _negamax(
    AiPosition pos,
    int depth,
    int alpha,
    int beta,
    int ply,
    bool allowNull,
  ) {
    _nodes++;
    if (_timeUp()) return 0;

    if (pos.halfmove >= 100) return 0;
    if (ply > 0 && _isRepetition(pos)) return 0;

    final inCheck = pos.inCheck;
    if (inCheck) depth++; // şah uzatması

    if (depth <= 0) return _quiescence(pos, alpha, beta, ply);
    if (ply >= maxPly - 1) return _Eval.evaluate(pos);

    final originalAlpha = alpha;
    int ttMove = 0;
    final entry = _tt[pos.hash];
    if (entry != null) {
      ttMove = entry.move;
      if (entry.depth >= depth) {
        if (entry.flag == 0) return entry.score;
        if (entry.flag == 1 && entry.score > alpha) alpha = entry.score;
        if (entry.flag == 2 && entry.score < beta) beta = entry.score;
        if (alpha >= beta) return entry.score;
      }
    }

    // Sıfır hamle budaması
    if (allowNull &&
        !inCheck &&
        depth >= 3 &&
        pos.hasNonPawnMaterial(pos.side)) {
      final savedEp = pos.enPassant;
      final savedHash = pos.hash;
      pos.side ^= 1;
      pos.enPassant = -1;
      pos.hash ^= _Zobrist.side;
      final score = -_negamax(pos, depth - 3, -beta, -beta + 1, ply + 1, false);
      pos.side ^= 1;
      pos.enPassant = savedEp;
      pos.hash = savedHash;
      if (score >= beta) return beta;
    }

    final moves = pos.generateMoves();
    _orderMoves(pos, moves, ttMove, ply);

    int bestScore = -_infinity;
    int bestMove = 0;
    int legalCount = 0;

    for (int i = 0; i < moves.length; i++) {
      final move = moves[i];
      if (!pos.makeMove(move)) continue;
      legalCount++;

      int score;
      final isQuiet = _isQuiet(pos, move);
      if (legalCount == 1) {
        score = -_negamax(pos, depth - 1, -beta, -alpha, ply + 1, true);
      } else {
        // Geç hamle indirimi
        int reduction = 0;
        if (depth >= 3 && legalCount > 3 && isQuiet && !inCheck) {
          reduction = 1 + (legalCount > 8 ? 1 : 0);
        }
        score = -_negamax(
          pos,
          depth - 1 - reduction,
          -alpha - 1,
          -alpha,
          ply + 1,
          true,
        );
        if (score > alpha && (reduction > 0 || score < beta)) {
          score = -_negamax(pos, depth - 1, -beta, -alpha, ply + 1, true);
        }
      }
      pos.undoMove();

      if (_aborted) return 0;

      if (score > bestScore) {
        bestScore = score;
        bestMove = move;
      }
      if (score > alpha) alpha = score;
      if (alpha >= beta) {
        if (isQuiet) {
          final killers = _killers[ply];
          if (killers[0] != move) {
            killers[1] = killers[0];
            killers[0] = move;
          }
          final piece = pos.squares[moveFrom(move)];
          if (piece != kEmpty) {
            _history[piece][moveTo(move)] += depth * depth;
          }
        }
        break;
      }
    }

    if (legalCount == 0) {
      return inCheck ? -_mateScore + ply : 0;
    }

    final flag = bestScore <= originalAlpha
        ? 2
        : bestScore >= beta
            ? 1
            : 0;
    if (_tt.length < 400000) {
      _tt[pos.hash] = _TtEntry(depth, bestScore, flag, bestMove);
    }

    return bestScore;
  }

  int _quiescence(AiPosition pos, int alpha, int beta, int ply) {
    _nodes++;
    if (_timeUp()) return 0;

    final standPat = _Eval.evaluate(pos);
    if (standPat >= beta) return beta;
    if (standPat > alpha) alpha = standPat;
    if (ply >= maxPly - 1) return standPat;

    final moves = pos.generateMoves(capturesOnly: true);
    _orderMoves(pos, moves, 0, ply);

    for (final move in moves) {
      if (!pos.makeMove(move)) continue;
      final score = -_quiescence(pos, -beta, -alpha, ply + 1);
      pos.undoMove();
      if (_aborted) return 0;
      if (score >= beta) return beta;
      if (score > alpha) alpha = score;
    }
    return alpha;
  }

  bool _isQuiet(AiPosition pos, int move) {
    // makeMove sonrası çağrıldığı için hedef karedeki taş artık taşınan
    // taştır; alma olup olmadığını undo kaydından anlamak yerine hamle
    // bayrağı ve terfi bilgisine bakılır.
    return movePromo(move) == 0 &&
        moveFlags(move) != flagEnPassant &&
        pos._undoStack[pos._ply - 1].captured == kEmpty;
  }

  bool _isRepetition(AiPosition pos) {
    int count = 0;
    for (final hash in pos.historyHashes) {
      if (hash == pos.hash) count++;
    }
    return count >= 1;
  }

  void _orderMoves(AiPosition pos, List<int> moves, int ttMove, int ply) {
    final killers = _killers[ply];
    final scores = <int, int>{};

    for (final move in moves) {
      int score = 0;
      final from = moveFrom(move);
      final to = moveTo(move);
      final attacker = pos.squares[from];
      final victim = pos.squares[to];

      if (move == ttMove) {
        score = 1000000;
      } else if (victim != kEmpty) {
        // MVV-LVA
        score = 100000 +
            _Eval.midValues[pieceKind(victim)] * 10 -
            _Eval.midValues[pieceKind(attacker)];
      } else if (movePromo(move) != 0) {
        score = 90000 + _Eval.midValues[movePromo(move)];
      } else if (move == killers[0]) {
        score = 80000;
      } else if (move == killers[1]) {
        score = 79000;
      } else if (attacker != kEmpty) {
        score = _history[attacker][to];
      }
      scores[move] = score;
    }

    moves.sort((a, b) => scores[b]!.compareTo(scores[a]!));
  }
}

// ---------------------------------------------------------------------------
// Perft (hamle üreticisini doğrulamak için)
// ---------------------------------------------------------------------------

int perft(AiPosition pos, int depth) {
  if (depth == 0) return 1;
  int total = 0;
  for (final move in pos.generateMoves()) {
    if (!pos.makeMove(move)) continue;
    total += perft(pos, depth - 1);
    pos.undoMove();
  }
  return total;
}
