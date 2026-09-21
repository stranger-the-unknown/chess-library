import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../models/chess_engine.dart' as engine;
import '../services/settings_service.dart';
import '../services/sound_service.dart';
import '../theme/app_theme.dart';
import 'piece_widget.dart';
import 'cursors.dart';
import 'board_background.dart';

/// Tahtaya çizilen ok (motor ipucu, çözüm gösterimi).
class BoardArrow {
  final engine.Position from;
  final engine.Position to;
  final Color color;

  /// Makinenin önerdiği ok mu?
  ///
  /// Kullanıcının sağ tıkla çizdiği ok kasıtlı ve kalıcı bir nottur;
  /// motorun oku her hamlede kendiliğinden değişen geçici bir öneridir.
  /// İkisi aynı renkte olduğu için ayrım kalınlık ve saydamlıkta:
  /// öneri daha ince ve daha sönük çiziliyor.
  final bool faint;

  const BoardArrow(this.from, this.to, this.color, {this.faint = false});
}

/// Etkileşimli satranç tahtası.
///
/// Tahta oyunu **değiştirmez**; seçilen hamleyi [onMove] ile üst widget'a
/// bildirir. Pozisyonun tek bir sahibi olması, PGN gezinme / geri alma /
/// motorla oynama gibi akışlarda tutarsızlığı önler.
class ChessBoardWidget extends StatefulWidget {
  final engine.ChessGame game;

  /// Tahta siyahın bakış açısıyla mı gösterilsin?
  final bool flipped;

  /// Kullanıcı hamle yapabilir mi?
  final bool interactive;

  /// Yalnızca bu renk oynatılabilir (motora karşı oyun, bulmaca).
  final engine.Color? movableSide;

  /// Vurgulanacak son hamle.
  final engine.ChessMove? lastMove;

  /// Kullanıcı geçerli bir hamle seçtiğinde çağrılır.
  final void Function(engine.ChessMove move)? onMove;

  /// Tahtaya çizilecek oklar.
  final List<BoardArrow> arrows;

  /// Ek kare renklendirmeleri (bulmaca geri bildirimi vb.).
  final Map<int, Color> squareTints;

  /// Son hamle canlandırılsın mı?
  ///
  /// Hamle listesinde **geri** giderken taşın ileri doğru kaymasını
  /// izlemek kafa karıştırıcı: konum geriye gidiyor ama animasyon
  /// hamleyi oynuyormuş gibi duruyor. Geri gidişte ve uzağa atlarken
  /// kapatılıyor.
  final bool animateLastMove;

  const ChessBoardWidget({
    super.key,
    required this.game,
    this.flipped = false,
    this.interactive = true,
    this.movableSide,
    this.lastMove,
    this.onMove,
    this.arrows = const [],
    this.squareTints = const {},
    this.animateLastMove = true,
  });

  @override
  State<ChessBoardWidget> createState() => _ChessBoardWidgetState();
}

class _ChessBoardWidgetState extends State<ChessBoardWidget>
    with SingleTickerProviderStateMixin {
  engine.Position? _selected;
  List<engine.ChessMove> _legalFromSelected = const [];

  /// Sağ tıkla işaretlenen kareler (kare dizini).
  final Set<int> _marked = {};

  /// Sağ tuşla sürüklenerek çizilen oklar.
  final List<(engine.Position, engine.Position)> _userArrows = [];

  /// Sürüklenmekte olan işaretin başlangıcı ve o anki ucu.
  engine.Position? _markFrom;
  engine.Position? _markTo;

  // Sürükleme durumu
  engine.Position? _dragFrom;
  Offset? _dragPosition;

  // Hamle animasyonu
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 170),
  );
  engine.ChessMove? _animatingMove;
  engine.Piece? _animatingPiece;

  @override
  void didUpdateWidget(covariant ChessBoardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(oldWidget.game, widget.game)) {
      _selected = null;
      _legalFromSelected = const [];
    }

    final previous = oldWidget.lastMove;
    final current = widget.lastMove;
    if (widget.animateLastMove &&
        SettingsService.instance.animateMoves &&
        current != null &&
        current.uci != previous?.uci) {
      final piece = widget.game.pieceAt(current.to);
      if (piece != null) {
        _animatingMove = current;
        _animatingPiece = piece;
        _animation.forward(from: 0).whenComplete(() {
          if (!mounted) return;
          setState(() {
            _animatingMove = null;
            _animatingPiece = null;
          });
        });
      }
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Yerleşim yardımcıları
  // -------------------------------------------------------------------------

  Offset _offsetFor(engine.Position position, double square) {
    final row = widget.flipped ? 7 - position.row : position.row;
    final col = widget.flipped ? 7 - position.col : position.col;
    return Offset(col * square, row * square);
  }

  engine.Position? _positionAt(Offset local, double square) {
    if (square <= 0) return null;
    int col = (local.dx / square).floor();
    int row = (local.dy / square).floor();
    if (row < 0 || row > 7 || col < 0 || col > 7) return null;
    if (widget.flipped) {
      row = 7 - row;
      col = 7 - col;
    }
    return engine.Position(row, col);
  }

  bool get _canPlay =>
      widget.interactive &&
      widget.onMove != null &&
      (widget.movableSide == null ||
          widget.movableSide == widget.game.sideToMove);

  bool _isOwnPiece(engine.Position position) {
    final piece = widget.game.pieceAt(position);
    return piece != null && piece.color == widget.game.sideToMove;
  }

  void _select(engine.Position position) {
    setState(() {
      _selected = position;
      _legalFromSelected = widget.game.legalMovesFrom(position);
    });
  }

  void _clearSelection() {
    setState(() {
      _selected = null;
      _legalFromSelected = const [];
    });
  }

  // -------------------------------------------------------------------------
  // Etkileşim
  // -------------------------------------------------------------------------

  Future<void> _tryMoveTo(engine.Position target) async {
    final from = _selected;
    if (from == null) return;

    final candidates = _legalFromSelected.where((m) => m.to == target).toList();
    if (candidates.isEmpty) {
      if (_isOwnPiece(target)) {
        // Başka bir kendi taşına geçiş; kural dışı bir deneme değil.
        _select(target);
      } else {
        // Boş ya da rakip bir kareye kural dışı hamle denemesi.
        SoundService.instance.playIllegalMove(inCheck: widget.game.isCheck);
        _clearSelection();
      }
      return;
    }

    engine.ChessMove move = candidates.first;
    if (candidates.length > 1 && candidates.any((m) => m.promotion != null)) {
      final piece = widget.game.pieceAt(from);
      final chosen = await _askPromotion(piece!.color, candidates);
      // Diyalog açıkken ekran kapatılmış olabilir; aşağıdaki iki yol da
      // setState çağırıyor.
      if (!mounted) return;
      if (chosen == null) {
        _clearSelection();
        return;
      }
      move = chosen;
    }

    _clearSelection();
    widget.onMove?.call(move);
  }

  void _onTapUp(TapUpDetails details, double square) {
    // Sol tık tahtayı temizler: işaretler geçicidir, bir sonraki
    // hamleye kadar bile durmaları gerekmez.
    _clearMarks();
    if (!_canPlay) return;
    final position = _positionAt(details.localPosition, square);
    if (position == null) return;

    if (_selected == null) {
      // Seçim yokken herhangi bir kareye dokunmak bir hamle denemesi
      // değildir; uyarı sesi çalmaz.
      if (_isOwnPiece(position)) _select(position);
      return;
    }
    if (position == _selected) {
      _clearSelection();
      return;
    }
    _tryMoveTo(position);
  }

  // -------------------------------------------------------------- işaretler

  /// Sağ tuşla basıldı: işaretin başlangıcı belirlenir.
  void _onMarkStart(Offset local, double square) {
    final position = _positionAt(local, square);
    if (position == null) return;
    setState(() {
      _markFrom = position;
      _markTo = position;
    });
  }

  /// Sağ tuş basılıyken sürüklendi: okun ucu izlenir.
  void _onMarkUpdate(Offset local, double square) {
    if (_markFrom == null) return;
    final position = _positionAt(local, square);
    if (position == _markTo) return;
    setState(() => _markTo = position);
  }

  /// Sağ tuş bırakıldı.
  ///
  /// Aynı karede bırakıldıysa kare işareti açılıp kapanır; başka bir
  /// karede bırakıldıysa aradaki ok eklenir ya da varsa kaldırılır.
  void _onMarkEnd() {
    final from = _markFrom;
    final to = _markTo;
    setState(() {
      _markFrom = null;
      _markTo = null;
      if (from == null) return;
      if (to == null || to == from) {
        final index = from.index;
        if (!_marked.remove(index)) _marked.add(index);
        return;
      }
      final existing = _userArrows.indexWhere(
        (arrow) => arrow.$1 == from && arrow.$2 == to,
      );
      if (existing == -1) {
        _userArrows.add((from, to));
      } else {
        _userArrows.removeAt(existing);
      }
    });
  }

  /// Bütün işaretleri siler.
  void _clearMarks() {
    if (_marked.isEmpty && _userArrows.isEmpty) return;
    setState(() {
      _marked.clear();
      _userArrows.clear();
    });
  }

  void _onPanStart(DragStartDetails details, double square) {
    if (!_canPlay) return;
    final position = _positionAt(details.localPosition, square);
    if (position == null || !_isOwnPiece(position)) return;
    setState(() {
      _dragFrom = position;
      _dragPosition = details.localPosition;
      _selected = position;
      _legalFromSelected = widget.game.legalMovesFrom(position);
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_dragFrom == null) return;
    setState(() => _dragPosition = details.localPosition);
  }

  void _onPanEnd(double square) {
    final from = _dragFrom;
    final at = _dragPosition;
    setState(() {
      _dragFrom = null;
      _dragPosition = null;
    });
    if (from == null || at == null) return;
    final target = _positionAt(at, square);
    if (target == null || target == from) {
      // Kısa sürükleme: seçim açık kalsın, kullanıcı hedefe dokunabilsin.
      return;
    }
    _tryMoveTo(target);
  }

  Future<engine.ChessMove?> _askPromotion(
    engine.Color color,
    List<engine.ChessMove> candidates,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return showDialog<engine.ChessMove>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        title: Text(t('game.promotion')),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final type in const [
              engine.PieceType.queen,
              engine.PieceType.rook,
              engine.PieceType.bishop,
              engine.PieceType.knight,
            ])
              if (candidates.any((m) => m.promotion == type))
                InkWell(
                  mouseCursor: kClickable,
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.pop(
                    dialogContext,
                    candidates.firstWhere((m) => m.promotion == type),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: PieceWidget(
                      piece: engine.Piece(type, color),
                      size: 46,
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Çizim
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService.instance;
    final scheme = Theme.of(context).colorScheme;

    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest.shortestSide;
          final square = size / 8;

          return MouseRegion(
            // Masaüstünde tahta oynanabilir olduğunda imleç el şeklini alır.
            cursor: _canPlay ? SystemMouseCursors.click : MouseCursor.defer,
            // Sağ tuş ayrı bir katmanda dinlenir: hamle tanıyıcıları
            // yalnızca sol tuşu kabul ettiği için ikisi çakışmaz ve
            // işaretleme tahta oynanamaz durumdayken de çalışır.
            child: Listener(
              onPointerDown: (event) {
                if (event.buttons & kSecondaryButton == 0) return;
                _onMarkStart(event.localPosition, square);
              },
              onPointerMove: (event) {
                if (event.buttons & kSecondaryButton == 0) return;
                _onMarkUpdate(event.localPosition, square);
              },
              onPointerUp: (_) => _onMarkEnd(),
              onPointerCancel: (_) => _onMarkEnd(),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) => _onTapUp(details, square),
                onPanStart: (details) => _onPanStart(details, square),
                onPanUpdate: _onPanUpdate,
                onPanEnd: (_) => _onPanEnd(square),
                child: SizedBox(
                  width: size,
                  height: size,
                  child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _buildBoardBackground(settings, size),
                    ..._buildHighlights(square, scheme),
                    if (settings.showCoordinates)
                      _buildCoordinates(square, scheme, settings),
                    ..._buildPieces(square),
                    if (settings.showLegalMoves) ..._buildLegalHints(square),
                    if (widget.arrows.isNotEmpty)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _ArrowPainter(
                              arrows: widget.arrows,
                              flipped: widget.flipped,
                            ),
                          ),
                        ),
                      ),
                    if (_animatingMove != null) _buildAnimatedPiece(square),
                    if (_dragFrom != null && _dragPosition != null)
                      _buildDraggedPiece(square),
                    if (_marked.isNotEmpty ||
                        _userArrows.isNotEmpty ||
                        _markFrom != null)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _MarkPainter(
                              squares: _marked,
                              arrows: _pendingArrows,
                              flipped: widget.flipped,
                              color: Color(
                                BoardAssets.markColor(settings.boardTheme),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Çizilecek oklar: bitmişler ve sürüklenmekte olan.
  List<(engine.Position, engine.Position)> get _pendingArrows {
    final from = _markFrom;
    final to = _markTo;
    if (from == null || to == null || from == to) return _userArrows;
    return [..._userArrows, (from, to)];
  }

  Widget _buildBoardBackground(SettingsService settings, double size) {
    return Positioned.fill(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: BoardBackground(board: settings.boardTheme),
      ),
    );
  }

  List<Widget> _buildHighlights(double square, ColorScheme scheme) {
    final widgets = <Widget>[];

    void add(engine.Position position, Color color) {
      final offset = _offsetFor(position, square);
      widgets.add(
        Positioned(
          left: offset.dx,
          top: offset.dy,
          width: square,
          height: square,
          child: IgnorePointer(child: ColoredBox(color: color)),
        ),
      );
    }

    final last = widget.lastMove;
    if (last != null && SettingsService.instance.highlightLastMove) {
      add(last.from, scheme.lastMove);
      add(last.to, scheme.lastMove);
    }

    if (widget.game.isCheck) {
      for (int i = 0; i < 64; i++) {
        final piece = widget.game.board[i];
        if (piece != null &&
            piece.type == engine.PieceType.king &&
            piece.color == widget.game.sideToMove) {
          widgets.add(_checkGlow(engine.Position.fromIndex(i), square, scheme));
          break;
        }
      }
    }

    widget.squareTints.forEach((index, color) {
      add(engine.Position.fromIndex(index), color);
    });

    final selected = _selected;
    if (selected != null) {
      add(
        selected,
        Color(BoardAssets.markColor(SettingsService.instance.boardTheme))
            .withValues(alpha: 0.55),
      );
    }

    return widgets;
  }

  Widget _checkGlow(engine.Position position, double square, ColorScheme s) {
    final offset = _offsetFor(position, square);
    return Positioned(
      left: offset.dx,
      top: offset.dy,
      width: square,
      height: square,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [s.checkSquare, s.checkSquare.withValues(alpha: 0)],
              stops: const [0.35, 1],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCoordinates(
    double square,
    ColorScheme scheme,
    SettingsService settings,
  ) {
    const files = 'abcdefgh';

    // Tahta görseli çevrilmez; bu yüzden bir hücrenin açık mı koyu mu
    // olduğu her zaman ekrandaki satır/sütun toplamından gelir. Yazı,
    // üzerinde durduğu karenin karşıt rengini alır (chess.com'daki gibi):
    // böylece hangi tahta seçilirse seçilsin okunur kalır.
    TextStyle styleFor(bool onLightSquare) => TextStyle(
          fontSize: square * 0.20,
          fontWeight: FontWeight.w700,
          color: Color(
            BoardAssets.coordinateColor(
              settings.boardTheme,
              onLightSquare: onLightSquare,
            ),
          ),
        );

    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            for (int i = 0; i < 8; i++) ...[
              () {
                final column = widget.flipped ? 7 - i : i;
                // Alt satır 7; (sütun + 7) çift ise kare açıktır.
                return Positioned(
                  left: column * square + square * 0.06,
                  top: 7 * square + square * 0.72,
                  child: Text(files[i], style: styleFor((column + 7).isEven)),
                );
              }(),
              () {
                final row = widget.flipped ? 7 - i : i;
                return Positioned(
                  left: 7 * square + square * 0.80,
                  top: row * square + square * 0.05,
                  child: Text('${8 - i}', style: styleFor((7 + row).isEven)),
                );
              }(),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildPieces(double square) {
    final widgets = <Widget>[];
    for (int i = 0; i < 64; i++) {
      final piece = widget.game.board[i];
      if (piece == null) continue;
      final position = engine.Position.fromIndex(i);

      // Sürüklenen ya da animasyonu süren taş ayrı katmanda çizilir.
      if (_dragFrom == position) continue;
      if (_animatingMove?.to == position && _animatingPiece != null) continue;

      final offset = _offsetFor(position, square);
      widgets.add(
        Positioned(
          left: offset.dx,
          top: offset.dy,
          width: square,
          height: square,
          child: IgnorePointer(
            child: Center(
              child: PieceWidget(piece: piece, size: square * 0.92),
            ),
          ),
        ),
      );
    }
    return widgets;
  }

  List<Widget> _buildLegalHints(double square) {
    if (_selected == null) return const [];
    return _legalFromSelected.map((move) => move.to).toSet().map((target) {
      final offset = _offsetFor(target, square);
      final occupied = widget.game.pieceAt(target) != null;
      return Positioned(
        left: offset.dx,
        top: offset.dy,
        width: square,
        height: square,
        child: IgnorePointer(
          child: Center(
            child: occupied
                ? Container(
                    width: square * 0.92,
                    height: square * 0.92,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.32),
                        width: square * 0.075,
                      ),
                    ),
                  )
                : Container(
                    width: square * 0.28,
                    height: square * 0.28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.28),
                    ),
                  ),
          ),
        ),
      );
    }).toList();
  }

  Widget _buildAnimatedPiece(double square) {
    final move = _animatingMove!;
    final start = _offsetFor(move.from, square);
    final end = _offsetFor(move.to, square);
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(_animation.value);
        final position = Offset.lerp(start, end, t)!;
        return Positioned(
          left: position.dx,
          top: position.dy,
          width: square,
          height: square,
          child: IgnorePointer(child: child),
        );
      },
      child: Center(
        child: PieceWidget(piece: _animatingPiece!, size: square * 0.92),
      ),
    );
  }

  Widget _buildDraggedPiece(double square) {
    final piece = widget.game.pieceAt(_dragFrom!);
    if (piece == null) return const SizedBox.shrink();
    final scale = 1.15;
    return Positioned(
      left: _dragPosition!.dx - square * scale / 2,
      top: _dragPosition!.dy - square * scale / 2,
      width: square * scale,
      height: square * scale,
      child: IgnorePointer(
        child: Center(
          child: PieceWidget(piece: piece, size: square * 0.92 * scale),
        ),
      ),
    );
  }
}

class _ArrowPainter extends CustomPainter {
  final List<BoardArrow> arrows;
  final bool flipped;

  _ArrowPainter({required this.arrows, required this.flipped});

  @override
  void paint(Canvas canvas, Size size) {
    final square = size.width / 8;

    Offset center(engine.Position position) {
      final row = flipped ? 7 - position.row : position.row;
      final col = flipped ? 7 - position.col : position.col;
      return Offset((col + 0.5) * square, (row + 0.5) * square);
    }

    for (final arrow in arrows) {
      final from = center(arrow.from);
      final to = center(arrow.to);
      final direction = (to - from);
      final length = direction.distance;
      if (length == 0) continue;
      final unit = direction / length;

      final headLength = square * (arrow.faint ? 0.36 : 0.42);
      final shaftEnd = to - unit * headLength * 0.85;
      final shaftStart = from + unit * square * 0.28;

      final normal = Offset(-unit.dy, unit.dx);
      final half = square * (arrow.faint ? 0.068 : 0.085);
      final headHalf = headLength * 0.42;

      // Ok tek bir yolla, tek seferde boyanıyor: yarım daire kuyruk,
      // gövde ve uç üçgeni. Eskiden kuyruk ayrı bir yuvarlak uçlu
      // çizgiydi; gövdenin ilk yarım kalınlığı iki kez boyanıyor ve
      // yarı saydam renkte orada koyu bir leke görünüyordu.
      final path = Path()
        ..moveTo(
          shaftStart.dx + normal.dx * half,
          shaftStart.dy + normal.dy * half,
        )
        ..lineTo(
          shaftEnd.dx + normal.dx * half,
          shaftEnd.dy + normal.dy * half,
        )
        ..lineTo(
          shaftEnd.dx + normal.dx * headHalf,
          shaftEnd.dy + normal.dy * headHalf,
        )
        ..lineTo(to.dx, to.dy)
        ..lineTo(
          shaftEnd.dx - normal.dx * headHalf,
          shaftEnd.dy - normal.dy * headHalf,
        )
        ..lineTo(
          shaftEnd.dx - normal.dx * half,
          shaftEnd.dy - normal.dy * half,
        )
        ..lineTo(
          shaftStart.dx - normal.dx * half,
          shaftStart.dy - normal.dy * half,
        )
        // Kuyruğu kapatan yarım daire; geriye doğru şişiyor.
        ..arcToPoint(
          Offset(
            shaftStart.dx + normal.dx * half,
            shaftStart.dy + normal.dy * half,
          ),
          radius: Radius.circular(half),
          clockwise: false,
        )
        ..close();
      canvas.drawPath(path, Paint()..color = arrow.color);
    }
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter old) =>
      old.arrows != arrows || old.flipped != flipped;
}

/// Tahta görseli yüklenemezse kullanılan yedek çizim.

/// Sağ tıkla konan kare işaretleri ve kullanıcı okları.
///
/// Oklar ipucu oklarıyla aynı biçimde çizilir ama rengi tahtadan
/// türetilir; kare işaretleri hem dolgu hem çerçeveyle çizilir, böylece
/// açık ve koyu karede de, doku üstünde de seçilir.
class _MarkPainter extends CustomPainter {
  final Set<int> squares;
  final List<(engine.Position, engine.Position)> arrows;
  final bool flipped;
  final Color color;

  _MarkPainter({
    required this.squares,
    required this.arrows,
    required this.flipped,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final square = size.width / 8;

    Offset topLeft(engine.Position position) {
      final row = flipped ? 7 - position.row : position.row;
      final col = flipped ? 7 - position.col : position.col;
      return Offset(col * square, row * square);
    }

    final inset = square * 0.06;
    final fill = Paint()..color = color.withValues(alpha: 0.30);
    final border = Paint()
      ..color = color.withValues(alpha: 0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = square * 0.075;

    for (final index in squares) {
      final offset = topLeft(engine.Position.fromIndex(index));
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          offset.dx + inset,
          offset.dy + inset,
          square - inset * 2,
          square - inset * 2,
        ),
        Radius.circular(square * 0.14),
      );
      canvas.drawRRect(rect, fill);
      canvas.drawRRect(rect, border);
    }

    if (arrows.isEmpty) return;
    _ArrowPainter(
      arrows: [
        for (final arrow in arrows)
          BoardArrow(arrow.$1, arrow.$2, color.withValues(alpha: 0.85)),
      ],
      flipped: flipped,
    ).paint(canvas, size);
  }

  @override
  bool shouldRepaint(covariant _MarkPainter old) =>
      old.flipped != flipped ||
      old.color != color ||
      old.arrows.length != arrows.length ||
      !setEquals(old.squares, squares) ||
      !listEquals(old.arrows, arrows);
}
