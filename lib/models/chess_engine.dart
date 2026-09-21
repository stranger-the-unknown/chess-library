import '../l10n/app_strings.dart';

enum Color { white, black }

enum PieceType { pawn, knight, bishop, rook, queen, king }

enum GameStatus { playing, check, checkmate, stalemate }

class Piece {
  final PieceType type;
  final Color color;

  const Piece(this.type, this.color);

  Piece copy() => Piece(type, color);

  @override
  String toString() {
    return '${color.name}_${type.name}';
  }
}

class Position {
  final int row;
  final int col;

  const Position(this.row, this.col);

  bool get isInside {
    return row >= 0 && row < 8 && col >= 0 && col < 8;
  }

  int get index => row * 8 + col;

  static Position fromIndex(int index) {
    return Position(index ~/ 8, index % 8);
  }

  static Position fromAlgebraic(String square) {
    if (square.length != 2) {
      throw ArgumentError('Geçersiz kare: $square');
    }

    final file = square.codeUnitAt(0) - 'a'.codeUnitAt(0);
    final rank = int.tryParse(square[1]);

    if (rank == null || file < 0 || file > 7 || rank < 1 || rank > 8) {
      throw ArgumentError('Geçersiz kare: $square');
    }

    // Tahtada row 0 = 8. sıra, row 7 = 1. sıra.
    return Position(8 - rank, file);
  }

  String get algebraic {
    final file = String.fromCharCode('a'.codeUnitAt(0) + col);

    final rank = (8 - row).toString();

    return '$file$rank';
  }

  bool sameAs(Position other) {
    return row == other.row && col == other.col;
  }

  @override
  bool operator ==(Object other) {
    return other is Position && other.row == row && other.col == col;
  }

  @override
  int get hashCode => Object.hash(row, col);

  @override
  String toString() => algebraic;
}

class ChessMove {
  final Position from;
  final Position to;

  /// Sadece piyon son sıraya ulaştığında kullanılır.
  final PieceType? promotion;

  const ChessMove({required this.from, required this.to, this.promotion});

  bool sameAs(ChessMove other) {
    return from == other.from && to == other.to && promotion == other.promotion;
  }

  String get uci {
    String result = '${from.algebraic}${to.algebraic}';

    if (promotion != null) {
      result += switch (promotion!) {
        PieceType.queen => 'q',
        PieceType.rook => 'r',
        PieceType.bishop => 'b',
        PieceType.knight => 'n',
        _ => '',
      };
    }

    return result;
  }

  @override
  String toString() => uci;
}

class ChessGame {
  static const int whiteKingStart = 60;
  static const int whiteQueenRookStart = 56;
  static const int whiteKingRookStart = 63;

  static const int blackKingStart = 4;
  static const int blackQueenRookStart = 0;
  static const int blackKingRookStart = 7;

  final List<Piece?> board;

  Color sideToMove;

  // Rok hakları
  bool whiteKingSideCastle;
  bool whiteQueenSideCastle;
  bool blackKingSideCastle;
  bool blackQueenSideCastle;

  // En passant için hedef kare.
  int? enPassantTarget;

  // 50 hamle kuralı için yarım hamle sayacı.
  int halfmoveClock;

  // Siyah hamlesinden sonra artırılır.
  int fullmoveNumber;

  ChessGame()
      : board = List<Piece?>.filled(64, null),
        sideToMove = Color.white,
        whiteKingSideCastle = true,
        whiteQueenSideCastle = true,
        blackKingSideCastle = true,
        blackQueenSideCastle = true,
        enPassantTarget = null,
        halfmoveClock = 0,
        fullmoveNumber = 1 {
    setupInitialPosition();
  }

  ChessGame._({
    required this.sideToMove,
    required this.whiteKingSideCastle,
    required this.whiteQueenSideCastle,
    required this.blackKingSideCastle,
    required this.blackQueenSideCastle,
    required this.enPassantTarget,
    required this.halfmoveClock,
    required this.fullmoveNumber,
    required this.board,
  });

  // ------------------------------------------------------------
  // COPY
  // ------------------------------------------------------------

  ChessGame copy() {
    return ChessGame._(
      board: List<Piece?>.from(board.map((piece) => piece?.copy())),
      sideToMove: sideToMove,
      whiteKingSideCastle: whiteKingSideCastle,
      whiteQueenSideCastle: whiteQueenSideCastle,
      blackKingSideCastle: blackKingSideCastle,
      blackQueenSideCastle: blackQueenSideCastle,
      enPassantTarget: enPassantTarget,
      halfmoveClock: halfmoveClock,
      fullmoveNumber: fullmoveNumber,
    );
  }

  // ------------------------------------------------------------
  // INITIAL POSITION
  // ------------------------------------------------------------

  void setupInitialPosition() {
    for (int i = 0; i < 64; i++) {
      board[i] = null;
    }

    sideToMove = Color.white;

    whiteKingSideCastle = true;
    whiteQueenSideCastle = true;
    blackKingSideCastle = true;
    blackQueenSideCastle = true;

    enPassantTarget = null;
    halfmoveClock = 0;
    fullmoveNumber = 1;

    // Siyah
    board[0] = const Piece(PieceType.rook, Color.black);
    board[1] = const Piece(PieceType.knight, Color.black);
    board[2] = const Piece(PieceType.bishop, Color.black);
    board[3] = const Piece(PieceType.queen, Color.black);
    board[4] = const Piece(PieceType.king, Color.black);
    board[5] = const Piece(PieceType.bishop, Color.black);
    board[6] = const Piece(PieceType.knight, Color.black);
    board[7] = const Piece(PieceType.rook, Color.black);

    for (int col = 0; col < 8; col++) {
      board[8 + col] = const Piece(PieceType.pawn, Color.black);
    }

    // Beyaz
    board[56] = const Piece(PieceType.rook, Color.white);
    board[57] = const Piece(PieceType.knight, Color.white);
    board[58] = const Piece(PieceType.bishop, Color.white);
    board[59] = const Piece(PieceType.queen, Color.white);
    board[60] = const Piece(PieceType.king, Color.white);
    board[61] = const Piece(PieceType.bishop, Color.white);
    board[62] = const Piece(PieceType.knight, Color.white);
    board[63] = const Piece(PieceType.rook, Color.white);

    for (int col = 0; col < 8; col++) {
      board[48 + col] = const Piece(PieceType.pawn, Color.white);
    }
  }

  // ------------------------------------------------------------
  // BOARD HELPERS
  // ------------------------------------------------------------

  Piece? pieceAt(Position position) {
    if (!position.isInside) {
      return null;
    }

    return board[position.index];
  }

  Piece? pieceAtSquare(String square) {
    return pieceAt(Position.fromAlgebraic(square));
  }

  void setPiece(Position position, Piece? piece) {
    board[position.index] = piece;
  }

  void clearBoard() {
    for (int i = 0; i < 64; i++) {
      board[i] = null;
    }
  }

  // ------------------------------------------------------------
  // LEGAL MOVE API
  // ------------------------------------------------------------

  bool isLegalMove(Position from, Position to, {PieceType? promotion}) {
    final piece = pieceAt(from);

    if (piece == null) {
      return false;
    }

    if (piece.color != sideToMove) {
      return false;
    }

    final requested = ChessMove(from: from, to: to, promotion: promotion);

    return legalMovesFrom(from).any((move) => move.sameAs(requested));
  }

  bool isLegalUci(String uci) {
    if (uci.length < 4) {
      return false;
    }

    try {
      final from = Position.fromAlgebraic(uci.substring(0, 2));

      final to = Position.fromAlgebraic(uci.substring(2, 4));

      PieceType? promotion;

      if (uci.length >= 5) {
        promotion = switch (uci[4].toLowerCase()) {
          'q' => PieceType.queen,
          'r' => PieceType.rook,
          'b' => PieceType.bishop,
          'n' => PieceType.knight,
          _ => null,
        };

        if (promotion == null) {
          return false;
        }
      }

      return isLegalMove(from, to, promotion: promotion);
    } catch (_) {
      return false;
    }
  }

  // ------------------------------------------------------------
  // LEGAL MOVE GENERATION
  // ------------------------------------------------------------

  List<ChessMove> allLegalMoves([Color? color]) {
    final requestedColor = color ?? sideToMove;

    final moves = <ChessMove>[];

    for (int index = 0; index < 64; index++) {
      final piece = board[index];

      if (piece == null || piece.color != requestedColor) {
        continue;
      }

      final from = Position.fromIndex(index);

      moves.addAll(legalMovesFrom(from));
    }

    return moves;
  }

  List<ChessMove> legalMovesFrom(Position from) {
    final piece = pieceAt(from);

    if (piece == null) {
      return [];
    }

    if (piece.color != sideToMove) {
      return [];
    }

    final pseudoMoves = _pseudoLegalMovesFrom(from, piece);

    final legalMoves = <ChessMove>[];

    for (final move in pseudoMoves) {
      final simulation = copy();

      simulation._makeMoveUnchecked(move);

      if (!simulation.isKingInCheck(piece.color)) {
        legalMoves.add(move);
      }
    }

    return legalMoves;
  }

  // ------------------------------------------------------------
  // PSEUDO LEGAL MOVES
  // ------------------------------------------------------------

  List<ChessMove> _pseudoLegalMovesFrom(Position from, Piece piece) {
    switch (piece.type) {
      case PieceType.pawn:
        return _pawnMoves(from, piece);

      case PieceType.knight:
        return _knightMoves(from, piece);

      case PieceType.bishop:
        return _slidingMoves(from, piece, const [
          [-1, -1],
          [-1, 1],
          [1, -1],
          [1, 1],
        ]);

      case PieceType.rook:
        return _slidingMoves(from, piece, const [
          [-1, 0],
          [1, 0],
          [0, -1],
          [0, 1],
        ]);

      case PieceType.queen:
        return _slidingMoves(from, piece, const [
          [-1, -1],
          [-1, 1],
          [1, -1],
          [1, 1],
          [-1, 0],
          [1, 0],
          [0, -1],
          [0, 1],
        ]);

      case PieceType.king:
        return _kingMoves(from, piece);
    }
  }

  bool _canCapture(Piece? target, Color movingColor) {
    if (target == null) {
      return true;
    }

    // Satranç hamlesiyle rakip şah alınmaz.
    if (target.type == PieceType.king) {
      return false;
    }

    return target.color != movingColor;
  }

  // ------------------------------------------------------------
  // PAWN
  // ------------------------------------------------------------

  List<ChessMove> _pawnMoves(Position from, Piece piece) {
    final moves = <ChessMove>[];

    final direction = piece.color == Color.white ? -1 : 1;

    final startRow = piece.color == Color.white ? 6 : 1;

    final promotionRow = piece.color == Color.white ? 0 : 7;

    // Tek ileri
    final oneForward = Position(from.row + direction, from.col);

    if (oneForward.isInside && pieceAt(oneForward) == null) {
      if (oneForward.row == promotionRow) {
        moves.addAll(_promotionMoves(from, oneForward));
      } else {
        moves.add(ChessMove(from: from, to: oneForward));
      }

      // İki ileri
      final twoForward = Position(from.row + direction * 2, from.col);

      if (from.row == startRow &&
          twoForward.isInside &&
          pieceAt(twoForward) == null) {
        moves.add(ChessMove(from: from, to: twoForward));
      }
    }

    // Çapraz alma
    for (final dc in [-1, 1]) {
      final target = Position(from.row + direction, from.col + dc);

      if (!target.isInside) {
        continue;
      }

      final targetPiece = pieceAt(target);

      // Normal capture
      if (targetPiece != null &&
          targetPiece.color != piece.color &&
          targetPiece.type != PieceType.king) {
        if (target.row == promotionRow) {
          moves.addAll(_promotionMoves(from, target));
        } else {
          moves.add(ChessMove(from: from, to: target));
        }
      }

      // En passant
      if (targetPiece == null && enPassantTarget == target.index) {
        moves.add(ChessMove(from: from, to: target));
      }
    }

    return moves;
  }

  List<ChessMove> _promotionMoves(Position from, Position to) {
    return [
      ChessMove(from: from, to: to, promotion: PieceType.queen),
      ChessMove(from: from, to: to, promotion: PieceType.rook),
      ChessMove(from: from, to: to, promotion: PieceType.bishop),
      ChessMove(from: from, to: to, promotion: PieceType.knight),
    ];
  }

  // ------------------------------------------------------------
  // KNIGHT
  // ------------------------------------------------------------

  List<ChessMove> _knightMoves(Position from, Piece piece) {
    const offsets = [
      [-2, -1],
      [-2, 1],
      [-1, -2],
      [-1, 2],
      [1, -2],
      [1, 2],
      [2, -1],
      [2, 1],
    ];

    final moves = <ChessMove>[];

    for (final offset in offsets) {
      final target = Position(from.row + offset[0], from.col + offset[1]);

      if (!target.isInside) {
        continue;
      }

      final targetPiece = pieceAt(target);

      if (_canCapture(targetPiece, piece.color)) {
        moves.add(ChessMove(from: from, to: target));
      }
    }

    return moves;
  }

  // ------------------------------------------------------------
  // SLIDING PIECES
  // ------------------------------------------------------------

  List<ChessMove> _slidingMoves(
    Position from,
    Piece piece,
    List<List<int>> directions,
  ) {
    final moves = <ChessMove>[];

    for (final direction in directions) {
      int row = from.row + direction[0];
      int col = from.col + direction[1];

      while (row >= 0 && row < 8 && col >= 0 && col < 8) {
        final target = Position(row, col);
        final targetPiece = pieceAt(target);

        if (targetPiece == null) {
          moves.add(ChessMove(from: from, to: target));
        } else {
          if (_canCapture(targetPiece, piece.color)) {
            moves.add(ChessMove(from: from, to: target));
          }

          // Bir taş gördüğümüzde ilerleyemeyiz.
          break;
        }

        row += direction[0];
        col += direction[1];
      }
    }

    return moves;
  }

  // ------------------------------------------------------------
  // KING
  // ------------------------------------------------------------

  List<ChessMove> _kingMoves(Position from, Piece piece) {
    final moves = <ChessMove>[];

    for (int dr = -1; dr <= 1; dr++) {
      for (int dc = -1; dc <= 1; dc++) {
        if (dr == 0 && dc == 0) {
          continue;
        }

        final target = Position(from.row + dr, from.col + dc);

        if (!target.isInside) {
          continue;
        }

        final targetPiece = pieceAt(target);

        if (_canCapture(targetPiece, piece.color)) {
          moves.add(ChessMove(from: from, to: target));
        }
      }
    }

    // Roklar
    moves.addAll(_castlingMoves(from, piece));

    return moves;
  }

  // ------------------------------------------------------------
  // CASTLING
  // ------------------------------------------------------------

  List<ChessMove> _castlingMoves(Position from, Piece king) {
    final moves = <ChessMove>[];

    if (king.type != PieceType.king) {
      return moves;
    }

    // Şah başlangıç karesinde değilse rok yok.
    final expectedRow = king.color == Color.white ? 7 : 0;

    if (from.row != expectedRow || from.col != 4) {
      return moves;
    }

    // Şah şu anda tehdit altında ise rok yapamaz.
    if (isSquareAttacked(from, _opposite(king.color))) {
      return moves;
    }

    // ----------------------------------------------------------
    // KISA ROK
    // ----------------------------------------------------------

    final canKingSide =
        king.color == Color.white ? whiteKingSideCastle : blackKingSideCastle;

    if (canKingSide) {
      final rookSquare = Position(expectedRow, 7);

      final fSquare = Position(expectedRow, 5);

      final gSquare = Position(expectedRow, 6);

      final rook = pieceAt(rookSquare);

      if (rook != null &&
          rook.type == PieceType.rook &&
          rook.color == king.color &&
          pieceAt(fSquare) == null &&
          pieceAt(gSquare) == null) {
        final enemy = _opposite(king.color);

        final fAttacked = isSquareAttacked(fSquare, enemy);

        final gAttacked = isSquareAttacked(gSquare, enemy);

        if (!fAttacked && !gAttacked) {
          moves.add(ChessMove(from: from, to: gSquare));
        }
      }
    }

    // ----------------------------------------------------------
    // UZUN ROK
    // ----------------------------------------------------------

    final canQueenSide =
        king.color == Color.white ? whiteQueenSideCastle : blackQueenSideCastle;

    if (canQueenSide) {
      final rookSquare = Position(expectedRow, 0);

      final bSquare = Position(expectedRow, 1);

      final cSquare = Position(expectedRow, 2);

      final dSquare = Position(expectedRow, 3);

      final rook = pieceAt(rookSquare);

      if (rook != null &&
          rook.type == PieceType.rook &&
          rook.color == king.color &&
          pieceAt(bSquare) == null &&
          pieceAt(cSquare) == null &&
          pieceAt(dSquare) == null) {
        final enemy = _opposite(king.color);

        final cAttacked = isSquareAttacked(cSquare, enemy);

        final dAttacked = isSquareAttacked(dSquare, enemy);

        if (!cAttacked && !dAttacked) {
          moves.add(ChessMove(from: from, to: cSquare));
        }
      }
    }

    return moves;
  }

  // ------------------------------------------------------------
  // MAKE MOVE
  // ------------------------------------------------------------

  bool makeMove(ChessMove move) {
    final legalMoves = legalMovesFrom(move.from);

    final actualMove = legalMoves.cast<ChessMove?>().firstWhere(
          (candidate) => candidate!.sameAs(move),
          orElse: () => null,
        );

    if (actualMove == null) {
      return false;
    }

    _makeMoveUnchecked(actualMove);

    return true;
  }

  bool makeUciMove(String uci) {
    if (uci.length < 4) {
      return false;
    }

    try {
      final from = Position.fromAlgebraic(uci.substring(0, 2));

      final to = Position.fromAlgebraic(uci.substring(2, 4));

      PieceType? promotion;

      if (uci.length >= 5) {
        promotion = switch (uci[4].toLowerCase()) {
          'q' => PieceType.queen,
          'r' => PieceType.rook,
          'b' => PieceType.bishop,
          'n' => PieceType.knight,
          _ => null,
        };

        if (promotion == null) {
          return false;
        }
      }

      return makeMove(ChessMove(from: from, to: to, promotion: promotion));
    } catch (_) {
      return false;
    }
  }

  void _makeMoveUnchecked(ChessMove move) {
    final movingPiece = pieceAt(move.from);

    if (movingPiece == null) {
      throw StateError('Kaynak karede taş yok.');
    }

    final targetPiece = pieceAt(move.to);

    final isPawn = movingPiece.type == PieceType.pawn;

    final isCapture = targetPiece != null;

    // ----------------------------------------------------------
    // ROK HAKLARINI GÜNCELLE
    // ----------------------------------------------------------

    _updateCastlingRightsForMove(move.from, movingPiece, move.to, targetPiece);

    // ----------------------------------------------------------
    // EN PASSANT CAPTURE
    // ----------------------------------------------------------

    bool isEnPassant = false;

    if (isPawn &&
        move.from.col != move.to.col &&
        targetPiece == null &&
        enPassantTarget == move.to.index) {
      isEnPassant = true;

      final capturedPawnPosition = Position(move.from.row, move.to.col);

      board[capturedPawnPosition.index] = null;
    }

    // ----------------------------------------------------------
    // TAŞI KAYNAKTAN AL
    // ----------------------------------------------------------

    board[move.from.index] = null;

    // ----------------------------------------------------------
    // PROMOTION
    // ----------------------------------------------------------

    Piece pieceToPlace = movingPiece;

    if (isPawn && (move.to.row == 0 || move.to.row == 7)) {
      final promotion = move.promotion ?? PieceType.queen;

      pieceToPlace = Piece(promotion, movingPiece.color);
    }

    board[move.to.index] = pieceToPlace;

    // ----------------------------------------------------------
    // CASTLING - KALE HAREKETİ
    // ----------------------------------------------------------

    if (movingPiece.type == PieceType.king &&
        (move.to.col - move.from.col).abs() == 2) {
      final row = move.from.row;

      // Kısa rok
      if (move.to.col == 6) {
        final rookFrom = Position(row, 7);
        final rookTo = Position(row, 5);

        final rook = pieceAt(rookFrom);

        board[rookFrom.index] = null;
        board[rookTo.index] = rook;
      }

      // Uzun rok
      if (move.to.col == 2) {
        final rookFrom = Position(row, 0);
        final rookTo = Position(row, 3);

        final rook = pieceAt(rookFrom);

        board[rookFrom.index] = null;
        board[rookTo.index] = rook;
      }
    }

    // ----------------------------------------------------------
    // EN PASSANT TARGET
    // ----------------------------------------------------------

    enPassantTarget = null;

    if (movingPiece.type == PieceType.pawn &&
        (move.to.row - move.from.row).abs() == 2) {
      final middleRow = (move.from.row + move.to.row) ~/ 2;

      enPassantTarget = Position(middleRow, move.from.col).index;
    }

    // ----------------------------------------------------------
    // 50-HAMLE SAYACI
    // ----------------------------------------------------------

    if (isPawn || isCapture || isEnPassant) {
      halfmoveClock = 0;
    } else {
      halfmoveClock++;
    }

    // ----------------------------------------------------------
    // TUR
    // ----------------------------------------------------------

    if (sideToMove == Color.black) {
      fullmoveNumber++;
    }

    sideToMove = _opposite(sideToMove);
  }

  // ------------------------------------------------------------
  // CASTLING RIGHTS UPDATE
  // ------------------------------------------------------------

  void _updateCastlingRightsForMove(
    Position from,
    Piece movingPiece,
    Position to,
    Piece? capturedPiece,
  ) {
    // Şah hareket ettiyse iki rok da biter.
    if (movingPiece.type == PieceType.king) {
      if (movingPiece.color == Color.white) {
        whiteKingSideCastle = false;
        whiteQueenSideCastle = false;
      } else {
        blackKingSideCastle = false;
        blackQueenSideCastle = false;
      }
    }

    // Kale hareket ettiyse ilgili rok biter.
    if (movingPiece.type == PieceType.rook) {
      _removeRookCastleRight(from.index, movingPiece.color);
    }

    // Kale alındıysa rakibin ilgili rokhakkı biter.
    if (capturedPiece?.type == PieceType.rook) {
      _removeRookCastleRight(to.index, capturedPiece!.color);
    }
  }

  void _removeRookCastleRight(int square, Color rookColor) {
    if (rookColor == Color.white) {
      if (square == whiteKingRookStart) {
        whiteKingSideCastle = false;
      }

      if (square == whiteQueenRookStart) {
        whiteQueenSideCastle = false;
      }
    } else {
      if (square == blackKingRookStart) {
        blackKingSideCastle = false;
      }

      if (square == blackQueenRookStart) {
        blackQueenSideCastle = false;
      }
    }
  }

  // ------------------------------------------------------------
  // CHECK
  // ------------------------------------------------------------

  bool isKingInCheck(Color color) {
    final kingPosition = _findKing(color);

    // Geçersiz pozisyon.
    if (kingPosition == null) {
      return true;
    }

    return isSquareAttacked(kingPosition, _opposite(color));
  }

  bool isCurrentPlayerInCheck() {
    return isKingInCheck(sideToMove);
  }

  Position? _findKing(Color color) {
    for (int i = 0; i < 64; i++) {
      final piece = board[i];

      if (piece != null &&
          piece.type == PieceType.king &&
          piece.color == color) {
        return Position.fromIndex(i);
      }
    }

    return null;
  }

  // ------------------------------------------------------------
  // SQUARE ATTACK DETECTION
  // ------------------------------------------------------------

  bool isSquareAttacked(Position target, Color byColor) {
    // ----------------------------------------------------------
    // PAWN
    // ----------------------------------------------------------

    final pawnDirection = byColor == Color.white ? -1 : 1;

    final pawnSourceRow = target.row - pawnDirection;

    for (final dc in [-1, 1]) {
      final source = Position(pawnSourceRow, target.col + dc);

      if (!source.isInside) {
        continue;
      }

      final piece = pieceAt(source);

      if (piece != null &&
          piece.color == byColor &&
          piece.type == PieceType.pawn) {
        return true;
      }
    }

    // ----------------------------------------------------------
    // KNIGHT
    // ----------------------------------------------------------

    const knightOffsets = [
      [-2, -1],
      [-2, 1],
      [-1, -2],
      [-1, 2],
      [1, -2],
      [1, 2],
      [2, -1],
      [2, 1],
    ];

    for (final offset in knightOffsets) {
      final source = Position(target.row + offset[0], target.col + offset[1]);

      if (!source.isInside) {
        continue;
      }

      final piece = pieceAt(source);

      if (piece != null &&
          piece.color == byColor &&
          piece.type == PieceType.knight) {
        return true;
      }
    }

    // ----------------------------------------------------------
    // BISHOP / QUEEN
    // ----------------------------------------------------------

    const diagonalDirections = [
      [-1, -1],
      [-1, 1],
      [1, -1],
      [1, 1],
    ];

    for (final direction in diagonalDirections) {
      int row = target.row + direction[0];
      int col = target.col + direction[1];

      while (row >= 0 && row < 8 && col >= 0 && col < 8) {
        final piece = pieceAt(Position(row, col));

        if (piece != null) {
          if (piece.color == byColor &&
              (piece.type == PieceType.bishop ||
                  piece.type == PieceType.queen)) {
            return true;
          }

          break;
        }

        row += direction[0];
        col += direction[1];
      }
    }

    // ----------------------------------------------------------
    // ROOK / QUEEN
    // ----------------------------------------------------------

    const straightDirections = [
      [-1, 0],
      [1, 0],
      [0, -1],
      [0, 1],
    ];

    for (final direction in straightDirections) {
      int row = target.row + direction[0];
      int col = target.col + direction[1];

      while (row >= 0 && row < 8 && col >= 0 && col < 8) {
        final piece = pieceAt(Position(row, col));

        if (piece != null) {
          if (piece.color == byColor &&
              (piece.type == PieceType.rook || piece.type == PieceType.queen)) {
            return true;
          }

          break;
        }

        row += direction[0];
        col += direction[1];
      }
    }

    // ----------------------------------------------------------
    // KING
    // ----------------------------------------------------------

    for (int dr = -1; dr <= 1; dr++) {
      for (int dc = -1; dc <= 1; dc++) {
        if (dr == 0 && dc == 0) {
          continue;
        }

        final source = Position(target.row + dr, target.col + dc);

        if (!source.isInside) {
          continue;
        }

        final piece = pieceAt(source);

        if (piece != null &&
            piece.color == byColor &&
            piece.type == PieceType.king) {
          return true;
        }
      }
    }

    return false;
  }

  // ------------------------------------------------------------
  // GAME STATUS
  // ------------------------------------------------------------

  GameStatus get status {
    final inCheck = isKingInCheck(sideToMove);

    final moves = allLegalMoves(sideToMove);

    if (moves.isNotEmpty) {
      return inCheck ? GameStatus.check : GameStatus.playing;
    }

    if (inCheck) {
      return GameStatus.checkmate;
    }

    return GameStatus.stalemate;
  }

  bool get isCheck {
    return isKingInCheck(sideToMove);
  }

  bool get isCheckmate {
    return status == GameStatus.checkmate;
  }

  bool get isStalemate {
    return status == GameStatus.stalemate;
  }

  // ------------------------------------------------------------
  // DRAW HELPERS
  // ------------------------------------------------------------

  bool get fiftyMoveRule {
    return halfmoveClock >= 100;
  }

  bool get insufficientMaterial {
    // Piyon, kale veya vezir varsa basit insufficient-material
    // kontrolü başarısızdır.
    int bishops = 0;
    int knights = 0;
    // Fillerin bulunduğu karelerin rengi: hepsi aynı renkteyse -- kimin
    // fili olduğu fark etmez -- mat imkânsızdır.
    bool lightBishop = false;
    bool darkBishop = false;

    for (int square = 0; square < board.length; square++) {
      final piece = board[square];
      if (piece == null) {
        continue;
      }

      switch (piece.type) {
        case PieceType.king:
          break;

        case PieceType.bishop:
          bishops++;
          if ((square ~/ 8 + square % 8).isEven) {
            lightBishop = true;
          } else {
            darkBishop = true;
          }
          break;

        case PieceType.knight:
          knights++;
          break;

        case PieceType.pawn:
        case PieceType.rook:
        case PieceType.queen:
          return false;
      }
    }

    // Sadece şahlar
    if (bishops == 0 && knights == 0) {
      return true;
    }

    // Filler tek renk karede ve at yok: şah+fil / şah+fil vs şah+fil gibi
    // pozisyonlarda mat edilemez. Eskiden yalnızca tahtada **tek** fil
    // varsa beraberlik yazılıyordu; iki tarafın da aynı renk karede fili
    // olduğu final sonsuza kadar sürüyordu.
    if (knights == 0 && !(lightBishop && darkBishop)) {
      return true;
    }

    // Şah + tek at
    if (bishops == 0 && knights == 1) {
      return true;
    }

    return false;
  }

  // ------------------------------------------------------------
  // UTILS
  // ------------------------------------------------------------

  Color _opposite(Color color) {
    return color == Color.white ? Color.black : Color.white;
  }

  // ------------------------------------------------------------
  // DEBUG / DISPLAY
  // ------------------------------------------------------------

  String asciiBoard() {
    final buffer = StringBuffer();

    for (int row = 0; row < 8; row++) {
      buffer.write('${8 - row} ');

      for (int col = 0; col < 8; col++) {
        final piece = board[row * 8 + col];

        buffer.write('${_pieceChar(piece)} ');
      }

      buffer.writeln();
    }

    buffer.writeln('  a b c d e f g h');

    return buffer.toString();
  }

  String _pieceChar(Piece? piece) {
    if (piece == null) {
      return '.';
    }

    final char = switch (piece.type) {
      PieceType.pawn => 'p',
      PieceType.knight => 'n',
      PieceType.bishop => 'b',
      PieceType.rook => 'r',
      PieceType.queen => 'q',
      PieceType.king => 'k',
    };

    return piece.color == Color.white ? char.toUpperCase() : char;
  }

  // ------------------------------------------------------------
  // FEN
  // ------------------------------------------------------------

  /// Pozisyonun tam FEN gösterimi.
  String get fen {
    final buffer = StringBuffer();

    for (int row = 0; row < 8; row++) {
      int empty = 0;
      for (int col = 0; col < 8; col++) {
        final piece = board[row * 8 + col];
        if (piece == null) {
          empty++;
          continue;
        }
        if (empty > 0) {
          buffer.write(empty);
          empty = 0;
        }
        buffer.write(_pieceChar(piece));
      }
      if (empty > 0) buffer.write(empty);
      if (row < 7) buffer.write('/');
    }

    buffer.write(sideToMove == Color.white ? ' w ' : ' b ');

    final castling = StringBuffer();
    if (whiteKingSideCastle) castling.write('K');
    if (whiteQueenSideCastle) castling.write('Q');
    if (blackKingSideCastle) castling.write('k');
    if (blackQueenSideCastle) castling.write('q');
    buffer.write(castling.isEmpty ? '-' : castling.toString());

    buffer.write(' ');
    buffer.write(
      enPassantTarget == null
          ? '-'
          : Position.fromIndex(enPassantTarget!).algebraic,
    );

    buffer.write(' $halfmoveClock $fullmoveNumber');
    return buffer.toString();
  }

  /// Üç kez tekrar tespiti için kullanılan konum anahtarı: FEN'in ilk dört
  /// alanı (taşlar, sıra, rok hakları, en passant).
  String get positionKey {
    final parts = fen.split(' ');
    return parts.take(4).join(' ');
  }

  /// FEN'i bu oyuna yükler. Biçim bozuksa [FormatException] fırlatır.
  void loadFen(String fenString) {
    final parts = fenString.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) {
      throw FormatException(t('fen.empty'));
    }

    final rows = parts[0].split('/');
    if (rows.length != 8) {
      throw FormatException(t('fen.needEightRows'));
    }

    final newBoard = List<Piece?>.filled(64, null);
    for (int row = 0; row < 8; row++) {
      int col = 0;
      for (final rune in rows[row].runes) {
        final char = String.fromCharCode(rune);
        final digit = int.tryParse(char);
        if (digit != null) {
          col += digit;
          continue;
        }
        if (col > 7) {
          throw FormatException(t('fen.rowTooLong', {'row': rows[row]}));
        }
        final piece = _pieceFromChar(char);
        if (piece == null) {
          throw FormatException(t('fen.unknownPiece', {'char': char}));
        }
        newBoard[row * 8 + col] = piece;
        col++;
      }
      if (col != 8) {
        throw FormatException(t('fen.rowNotEight', {'row': rows[row]}));
      }
    }

    for (int i = 0; i < 64; i++) {
      board[i] = newBoard[i];
    }

    sideToMove = (parts.length > 1 && parts[1].toLowerCase() == 'b')
        ? Color.black
        : Color.white;

    final rights = parts.length > 2 ? parts[2] : 'KQkq';
    whiteKingSideCastle = rights.contains('K');
    whiteQueenSideCastle = rights.contains('Q');
    blackKingSideCastle = rights.contains('k');
    blackQueenSideCastle = rights.contains('q');

    enPassantTarget = null;
    if (parts.length > 3 && parts[3] != '-' && parts[3].length == 2) {
      try {
        enPassantTarget = Position.fromAlgebraic(parts[3]).index;
      } catch (_) {
        enPassantTarget = null;
      }
    }

    halfmoveClock = parts.length > 4 ? (int.tryParse(parts[4]) ?? 0) : 0;
    fullmoveNumber = parts.length > 5 ? (int.tryParse(parts[5]) ?? 1) : 1;

    // Tahtada karşılığı olmayan rok haklarını temizle; aksi hâlde motor
    // var olmayan bir kaleyle rok üretmeye çalışır.
    normalizeCastlingRights();
  }

  /// Şah ya da kale başlangıç karesinde değilse ilgili rok hakkını kaldırır.
  void normalizeCastlingRights() {
    bool isPiece(int index, PieceType type, Color color) {
      final piece = board[index];
      return piece != null && piece.type == type && piece.color == color;
    }

    if (!isPiece(whiteKingStart, PieceType.king, Color.white)) {
      whiteKingSideCastle = false;
      whiteQueenSideCastle = false;
    } else {
      if (!isPiece(whiteKingRookStart, PieceType.rook, Color.white)) {
        whiteKingSideCastle = false;
      }
      if (!isPiece(whiteQueenRookStart, PieceType.rook, Color.white)) {
        whiteQueenSideCastle = false;
      }
    }

    if (!isPiece(blackKingStart, PieceType.king, Color.black)) {
      blackKingSideCastle = false;
      blackQueenSideCastle = false;
    } else {
      if (!isPiece(blackKingRookStart, PieceType.rook, Color.black)) {
        blackKingSideCastle = false;
      }
      if (!isPiece(blackQueenRookStart, PieceType.rook, Color.black)) {
        blackQueenSideCastle = false;
      }
    }
  }

  /// FEN'den yeni bir oyun kurar.
  static ChessGame fromFen(String fenString) {
    final game = ChessGame();
    game.loadFen(fenString);
    return game;
  }

  /// FEN'i hem biçim hem de satranç kuralları açısından denetler.
  /// Sorun yoksa `null`, varsa kullanıcıya gösterilecek hata metnini döner.
  static String? validateFen(String fenString) {
    ChessGame game;
    try {
      game = ChessGame.fromFen(fenString);
    } on FormatException catch (e) {
      return e.message;
    } catch (_) {
      return t('fen.unparsable');
    }

    int whiteKings = 0;
    int blackKings = 0;
    for (final piece in game.board) {
      if (piece?.type != PieceType.king) continue;
      if (piece!.color == Color.white) {
        whiteKings++;
      } else {
        blackKings++;
      }
    }
    if (whiteKings != 1) return t('fen.oneWhiteKing');
    if (blackKings != 1) return t('fen.oneBlackKing');

    for (int col = 0; col < 8; col++) {
      for (final row in [0, 7]) {
        if (game.board[row * 8 + col]?.type == PieceType.pawn) {
          return t('fen.pawnOnBackRank');
        }
      }
    }

    // Hamle sırası kendisinde olmayan taraf şah çekilmiş olamaz.
    final waiting = game.sideToMove == Color.white ? Color.black : Color.white;
    if (game.isKingInCheck(waiting)) {
      return t('fen.waitingSideInCheck');
    }

    return null;
  }

  static Piece? _pieceFromChar(String char) {
    final color = char.toUpperCase() == char ? Color.white : Color.black;
    switch (char.toLowerCase()) {
      case 'p':
        return Piece(PieceType.pawn, color);
      case 'n':
        return Piece(PieceType.knight, color);
      case 'b':
        return Piece(PieceType.bishop, color);
      case 'r':
        return Piece(PieceType.rook, color);
      case 'q':
        return Piece(PieceType.queen, color);
      case 'k':
        return Piece(PieceType.king, color);
      default:
        return null;
    }
  }

  // ------------------------------------------------------------
  // UCI <-> ChessMove
  // ------------------------------------------------------------

  /// "e2e4" / "e7e8q" gösterimini bu pozisyondaki yasal hamleye çevirir;
  /// hamle yasal değilse `null` döner.
  ChessMove? moveFromUci(String uci) {
    if (uci.length < 4) return null;

    Position from;
    Position to;
    try {
      from = Position.fromAlgebraic(uci.substring(0, 2));
      to = Position.fromAlgebraic(uci.substring(2, 4));
    } catch (_) {
      return null;
    }

    PieceType? promotion;
    if (uci.length >= 5) {
      promotion = switch (uci[4].toLowerCase()) {
        'q' => PieceType.queen,
        'r' => PieceType.rook,
        'b' => PieceType.bishop,
        'n' => PieceType.knight,
        _ => null,
      };
    }

    for (final move in legalMovesFrom(from)) {
      if (move.to != to) continue;
      if (promotion != null) {
        if (move.promotion != promotion) continue;
      } else if (move.promotion != null && move.promotion != PieceType.queen) {
        // Terfi harfi verilmemişse vezire terfi varsayılır.
        continue;
      }
      return move;
    }
    return null;
  }

  // ------------------------------------------------------------
  // SAN (Standart Cebirsel Notasyon)
  // ------------------------------------------------------------

  /// [move] oynanmadan ÖNCE bu pozisyonda çağrılmalıdır; hamlenin SAN
  /// karşılığını üretir ("Nf3", "exd5", "O-O", "e8=Q+", "Qxh7#").
  ///
  /// [includeCheckSuffix] kapatılırsa sondaki `+` / `#` işareti eklenmez.
  /// Bu eki bulmak hamleyi bir kopya üzerinde oynamayı gerektirir; yalnızca
  /// gösterim için değil eşleştirme için SAN üretiliyorsa (PGN okuma) bu
  /// maliyetten kaçınmak ayrıştırmayı belirgin biçimde hızlandırır.
  /// [legalMoves] verilirse ayırt etme ("Nbd2") için yasal hamleler
  /// yeniden üretilmez. Aynı pozisyonda çok sayıda hamlenin SAN'ı
  /// üretilirken (PGN okuma) bu, işi kare sayısı kadar azaltır.
  String sanFor(
    ChessMove move, {
    bool includeCheckSuffix = true,
    List<ChessMove>? legalMoves,
  }) {
    final piece = pieceAt(move.from);
    if (piece == null) return move.uci;

    final buffer = StringBuffer();
    final isCastle = piece.type == PieceType.king &&
        (move.to.col - move.from.col).abs() == 2;

    if (isCastle) {
      buffer.write(move.to.col == 6 ? 'O-O' : 'O-O-O');
    } else {
      final targetPiece = pieceAt(move.to);
      final isEnPassant = piece.type == PieceType.pawn &&
          move.from.col != move.to.col &&
          targetPiece == null;
      final isCapture = targetPiece != null || isEnPassant;

      if (piece.type == PieceType.pawn) {
        if (isCapture) buffer.write(move.from.algebraic[0]);
      } else {
        buffer.write(_pieceLetter(piece.type));
        buffer.write(_disambiguation(move, piece, legalMoves));
      }

      if (isCapture) buffer.write('x');
      buffer.write(move.to.algebraic);

      if (move.promotion != null) {
        buffer.write('=');
        buffer.write(_pieceLetter(move.promotion!));
      }
    }

    if (includeCheckSuffix) {
      // Şah / mat ekini bir kopya üzerinde oynayarak belirle.
      //
      // Önce ucuz olan şah denetimi yapılır: `isCheckmate` rakibin tüm
      // yasal hamlelerini üretmek zorundadır, oysa hamlelerin büyük
      // çoğunluğu şah bile çekmez.
      final probe = copy();
      if (probe.makeMove(move) && probe.isCheck) {
        buffer.write(probe.isCheckmate ? '#' : '+');
      }
    }

    return buffer.toString();
  }

  /// Aynı kareye gidebilen aynı türden başka bir taş varsa ayırt edici
  /// dosya/sıra bilgisini üretir ("Nbd2", "R1e2", "Qh4e1").
  String _disambiguation(
    ChessMove move,
    Piece piece, [
    List<ChessMove>? legalMoves,
  ]) {
    final rivals = <Position>[];

    if (legalMoves != null) {
      for (final candidate in legalMoves) {
        if (candidate.to != move.to) continue;
        if (candidate.from == move.from) continue;
        final other = pieceAt(candidate.from);
        if (other == null || other.type != piece.type) continue;
        rivals.add(candidate.from);
      }
    } else {
      // Hazır bir liste yoksa tüm hamleleri üretmek yerine yalnızca aynı
      // türden taşlara bak: genelde bir ya da iki taş vardır.
      for (int index = 0; index < 64; index++) {
        final other = board[index];
        if (other == null ||
            other.type != piece.type ||
            other.color != piece.color) {
          continue;
        }
        final from = Position.fromIndex(index);
        if (from == move.from) continue;
        if (legalMovesFrom(from).any((m) => m.to == move.to)) {
          rivals.add(from);
        }
      }
    }

    if (rivals.isEmpty) return '';

    final sameFile = rivals.any((p) => p.col == move.from.col);
    final sameRank = rivals.any((p) => p.row == move.from.row);

    if (!sameFile) return move.from.algebraic[0];
    if (!sameRank) return move.from.algebraic[1];
    return move.from.algebraic;
  }

  static String _pieceLetter(PieceType type) {
    return switch (type) {
      PieceType.pawn => 'P',
      PieceType.knight => 'N',
      PieceType.bishop => 'B',
      PieceType.rook => 'R',
      PieceType.queen => 'Q',
      PieceType.king => 'K',
    };
  }

  // ------------------------------------------------------------
  // MATERYAL
  // ------------------------------------------------------------

  /// Bir rengin tahtadaki taşlarını tür -> adet olarak sayar.
  Map<PieceType, int> pieceCounts(Color color) {
    final counts = <PieceType, int>{};
    for (final piece in board) {
      if (piece == null || piece.color != color) continue;
      counts[piece.type] = (counts[piece.type] ?? 0) + 1;
    }
    return counts;
  }

  /// Beyazın materyal farkı (piyon cinsinden). Negatifse siyah öndedir.
  int get materialBalance {
    const values = <PieceType, int>{
      PieceType.pawn: 1,
      PieceType.knight: 3,
      PieceType.bishop: 3,
      PieceType.rook: 5,
      PieceType.queen: 9,
      PieceType.king: 0,
    };
    int total = 0;
    for (final piece in board) {
      if (piece == null) continue;
      final value = values[piece.type]!;
      total += piece.color == Color.white ? value : -value;
    }
    return total;
  }
}
