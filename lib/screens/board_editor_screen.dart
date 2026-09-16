import 'dart:async';

import 'package:flutter/material.dart';

import '../widgets/responsive.dart';

import 'package:flutter/services.dart';

import '../l10n/app_strings.dart';
import '../models/chess_engine.dart' as engine;
import '../services/board_image_service.dart';
import '../services/settings_service.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/piece_widget.dart';
import '../widgets/cursors.dart';
import '../widgets/board_background.dart';

/// Pozisyon düzenleyici.
///
/// Taş paletinden bir taş seçilip karelere dokunularak tahta kurulur.
/// Hamle sırası, rok hakları ve en passant karesi de buradan ayarlanır.
/// Kaydedildiğinde sonuç FEN metni geri döndürülür.
class BoardEditorScreen extends StatefulWidget {
  final String initialFen;
  final String title;

  const BoardEditorScreen({
    super.key,
    required this.initialFen,
    this.title = '',
  });

  @override
  State<BoardEditorScreen> createState() => _BoardEditorScreenState();
}

class _BoardEditorScreenState extends State<BoardEditorScreen> {
  late List<engine.Piece?> _board;
  engine.Color _sideToMove = engine.Color.white;
  bool _wk = false, _wq = false, _bk = false, _bq = false;
  String _enPassant = '-';
  bool _flipped = false;

  /// Palette seçili taş; `null` ise silgi.
  engine.Piece? _brush = const engine.Piece(
    engine.PieceType.pawn,
    engine.Color.white,
  );
  bool _eraser = false;

  late final TextEditingController _fenController = TextEditingController();

  /// İlk FEN yüklendi mi (hatalı girişte tahtayı korumak için).
  bool _initialised = false;

  /// FEN alanındaki metin tahtaya uygulanamıyorsa gösterilen hata.
  String? _fenFieldError;

  /// Tahtanın PNG olarak kaydedilebilmesi için çizim sınırı.
  final GlobalKey _boardKey = GlobalKey();

  /// Yazma durduktan sonra hata iletisini göstermek için sayaç.
  Timer? _errorTimer;

  @override
  void initState() {
    super.initState();
    _applyFen(widget.initialFen, updateField: true);
  }

  @override
  void dispose() {
    _errorTimer?.cancel();
    _fenController.dispose();
    super.dispose();
  }

  /// FEN'i tahtaya uygular. Çözümlenemezse tahtaya dokunmaz ve `false`
  /// döner (kullanıcının kurduğu pozisyon yazım hatasıyla silinmesin).
  bool _applyFen(String fen, {bool updateField = false}) {
    try {
      final game = engine.ChessGame.fromFen(fen);
      _board = List<engine.Piece?>.from(game.board);
      _sideToMove = game.sideToMove;
      _wk = game.whiteKingSideCastle;
      _wq = game.whiteQueenSideCastle;
      _bk = game.blackKingSideCastle;
      _bq = game.blackQueenSideCastle;
      _enPassant = game.enPassantTarget == null
          ? '-'
          : engine.Position.fromIndex(game.enPassantTarget!).algebraic;
    } catch (_) {
      if (_initialised) return false;
      // İlk yüklemede geçersiz FEN gelirse boş tahtayla başla.
      _board = List<engine.Piece?>.filled(64, null);
      _sideToMove = engine.Color.white;
      _wk = _wq = _bk = _bq = false;
      _enPassant = '-';
    }
    _initialised = true;
    if (updateField) _fenController.text = _currentFen;
    return true;
  }

  /// Tahtadan üretilen FEN.
  String get _currentFen {
    final buffer = StringBuffer();
    for (int row = 0; row < 8; row++) {
      int empty = 0;
      for (int col = 0; col < 8; col++) {
        final piece = _board[row * 8 + col];
        if (piece == null) {
          empty++;
          continue;
        }
        if (empty > 0) {
          buffer.write(empty);
          empty = 0;
        }
        buffer.write(_charFor(piece));
      }
      if (empty > 0) buffer.write(empty);
      if (row < 7) buffer.write('/');
    }

    buffer.write(_sideToMove == engine.Color.white ? ' w ' : ' b ');
    final rights = StringBuffer();
    if (_wk) rights.write('K');
    if (_wq) rights.write('Q');
    if (_bk) rights.write('k');
    if (_bq) rights.write('q');
    buffer.write(rights.isEmpty ? '-' : rights.toString());
    buffer.write(' $_enPassant 0 1');
    return buffer.toString();
  }

  static String _charFor(engine.Piece piece) {
    final char = switch (piece.type) {
      engine.PieceType.pawn => 'p',
      engine.PieceType.knight => 'n',
      engine.PieceType.bishop => 'b',
      engine.PieceType.rook => 'r',
      engine.PieceType.queen => 'q',
      engine.PieceType.king => 'k',
    };
    return piece.color == engine.Color.white ? char.toUpperCase() : char;
  }

  String? get _error => engine.ChessGame.validateFen(_currentFen);

  void _touch() {
    setState(() => _fenController.text = _currentFen);
  }

  void _onSquareTap(int index) {
    setState(() {
      if (_eraser) {
        _board[index] = null;
      } else if (_board[index] != null &&
          _brush != null &&
          _board[index]!.type == _brush!.type &&
          _board[index]!.color == _brush!.color) {
        // Aynı taşa tekrar dokunmak siler; hızlı düzeltme için pratik.
        _board[index] = null;
      } else {
        _board[index] = _brush;
      }
      _fenController.text = _currentFen;
    });
  }

  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final error = _error;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title.isEmpty ? t('editor.title') : widget.title),
        actions: [
          IconButton(
            tooltip: t('common.flipBoard'),
            icon: const Icon(Icons.swap_vert_rounded),
            onPressed: () => setState(() => _flipped = !_flipped),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'start':
                  setState(() {
                    _applyFen(engine.ChessGame().fen, updateField: true);
                  });
                  break;
                case 'clear':
                  setState(() {
                    _board = List<engine.Piece?>.filled(64, null);
                    _wk = _wq = _bk = _bq = false;
                    _enPassant = '-';
                    _fenController.text = _currentFen;
                  });
                  break;
                case 'paste':
                  _pasteFen();
                  break;
                case 'copy':
                  Clipboard.setData(ClipboardData(text: _currentFen));
                  AppDialogs.snack(context, t('common.fenCopied'));
                  break;
                case 'png':
                  _saveBoardImage();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'start',
                child: Text(t('editor.startArrangement')),
              ),
              PopupMenuItem(
                value: 'clear',
                child: Text(t('editor.clearBoard')),
              ),
              PopupMenuItem(value: 'paste', child: Text(t('common.pasteFen'))),
              PopupMenuItem(value: 'copy', child: Text(t('common.copyFen'))),
              PopupMenuItem(value: 'png', child: Text(t('board.savePng'))),
            ],
          ),
        ],
      ),
      // Liste tüm genişliği kaplıyor, ortalama kendi dolgusuyla
      // yapılıyor; yoksa imleç kenardayken fare tekerleği çalışmıyor.
      body: ContentInset(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        builder: (context, padding) => ListView(
          padding: padding,
          children: [
            _buildBoard(scheme),
            const SizedBox(height: 12),
            _buildPalette(scheme),
            const SizedBox(height: 16),
            _buildOptions(scheme),
            const SizedBox(height: 16),
            TextField(
              controller: _fenController,
              maxLines: 2,
              style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace'),
              decoration: InputDecoration(
                labelText: 'FEN',
                helperText: t('editor.fenHelper'),
                errorText: _fenFieldError,
                suffixIcon: IconButton(
                  tooltip: t('editor.replaceWithClipboard'),
                  icon: const Icon(Icons.content_paste_go_rounded, size: 20),
                  onPressed: _pasteIntoField,
                ),
              ),
              // Yazıldıkça uygula: geçerli olur olmaz tahta güncellenir.
              onChanged: (_) => _applyFieldText(),
              onSubmitted: (_) => _applyFieldText(showError: true),
              onTapOutside: (_) {
                FocusScope.of(context).unfocus();
                _applyFieldText(showError: true);
              },
            ),
          ],
        ),
      ),
      // Onay düğmesi sabit bir alt çubukta durur: kaydırma gerektirmez ve
      // SafeArea sayesinde telefonun gezinme çubuğunun altında kalmaz.
      bottomNavigationBar: ContentWidth(child: _bottomBar(scheme, error)),
    );
  }

  Widget _bottomBar(ColorScheme scheme, String? error) {
    return SafeArea(
      minimum: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      color: scheme.error,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        error,
                        style: TextStyle(color: scheme.error, fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: error == null
                    ? () => Navigator.pop(context, _currentFen)
                    : null,
                icon: const Icon(Icons.check_rounded),
                label: Text(t('editor.usePosition')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBoard(ColorScheme scheme) {
    // Tahta geniş pencerede ekranı kaplamasın: ortalanır ve sınırlanır.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Layout.maxBoardSide),
        child: AspectRatio(
          aspectRatio: 1,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final square = constraints.biggest.shortestSide / 8;
              return RepaintBoundary(
                key: _boardKey,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(
                    children: [
                      // Ortak zemin bileşeni: düz tahtalar çizilir, ahşap
                      // olanlar görselden gelir. Buraya doğrudan
                      // `Image.asset` yazmak, görsel dosyası olmayan düz
                      // tahtalarda tahtayı görünmez bırakıyordu.
                      Positioned.fill(
                        child: BoardBackground(
                          board: SettingsService.instance.boardTheme,
                        ),
                      ),
                      for (int i = 0; i < 64; i++)
                        Positioned(
                          left: (_flipped ? 7 - i % 8 : i % 8) * square,
                          top: (_flipped ? 7 - i ~/ 8 : i ~/ 8) * square,
                          width: square,
                          height: square,
                          // MouseRegion: masaüstünde imleç el şeklini alsın.
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _onSquareTap(i),
                              child: _board[i] == null
                                  ? const SizedBox.expand()
                                  : Center(
                                      child: PieceWidget(
                                        piece: _board[i]!,
                                        size: square * 0.92,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPalette(ColorScheme scheme) {
    const types = [
      engine.PieceType.king,
      engine.PieceType.queen,
      engine.PieceType.rook,
      engine.PieceType.bishop,
      engine.PieceType.knight,
      engine.PieceType.pawn,
    ];

    Widget cell(engine.Piece? piece) {
      final isSelected = piece == null
          ? _eraser
          : (!_eraser &&
              _brush?.type == piece.type &&
              _brush?.color == piece.color);
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => setState(() {
            _eraser = piece == null;
            if (piece != null) _brush = piece;
          }),
          child: Container(
            margin: const EdgeInsets.all(3),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isSelected
                  ? scheme.primary.withValues(alpha: 0.22)
                  : scheme.surfaceContainer,
              border: Border.all(
                color: isSelected ? scheme.primary : scheme.outlineVariant,
                width: isSelected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: piece == null
                ? Icon(
                    Icons.backspace_outlined,
                    size: 26,
                    color: scheme.onSurfaceVariant,
                  )
                : PieceWidget(piece: piece, size: 32),
          ),
        ),
      );
    }

    // Silgi taşların sağında ve iki sıranın tam ortasında duruyor:
    // hem beyaza hem siyaha ait olduğu böyle anlaşılıyor. Altta tek
    // başına bir satır olarak durduğunda kopuk görünüyordu.
    //
    // Yedi hücre dar telefonlarda kıl payı sığıyor; taşmaması için
    // gerektiğinde küçültülüyor.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final type in types)
                    cell(engine.Piece(type, engine.Color.white)),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final type in types)
                    cell(engine.Piece(type, engine.Color.black)),
                ],
              ),
            ],
          ),
          cell(null),
        ],
      ),
    );
  }

  Widget _buildOptions(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t('editor.sideToMove'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        SegmentedButton<engine.Color>(
          segments: [
            ButtonSegment(
              value: engine.Color.white,
              label: Text(t('common.white')),
              icon: const Icon(Icons.circle_outlined),
            ),
            ButtonSegment(
              value: engine.Color.black,
              label: Text(t('common.black')),
              icon: const Icon(Icons.circle),
            ),
          ],
          selected: {_sideToMove},
          onSelectionChanged: (selection) {
            setState(() {
              _sideToMove = selection.first;
              _fenController.text = _currentFen;
            });
          },
        ),
        const SizedBox(height: 16),
        Text(
          t('editor.castlingRights'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        Wrap(
          spacing: 8,
          children: [
            FilterChip(
              mouseCursor: kClickable,
              label: Text(t('editor.whiteShort')),
              selected: _wk,
              onSelected: (v) {
                _wk = v;
                _touch();
              },
            ),
            FilterChip(
              mouseCursor: kClickable,
              label: Text(t('editor.whiteLong')),
              selected: _wq,
              onSelected: (v) {
                _wq = v;
                _touch();
              },
            ),
            FilterChip(
              mouseCursor: kClickable,
              label: Text(t('editor.blackShort')),
              selected: _bk,
              onSelected: (v) {
                _bk = v;
                _touch();
              },
            ),
            FilterChip(
              mouseCursor: kClickable,
              label: Text(t('editor.blackLong')),
              selected: _bq,
              onSelected: (v) {
                _bq = v;
                _touch();
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          t('editor.castlingHint'),
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text(
              t('editor.enPassantSquare'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            DropdownButton<String>(
              mouseCursor: kClickable,
              value: _enPassant,
              items: _enPassantOptions
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _enPassant = value ?? '-';
                  _fenController.text = _currentFen;
                });
              },
            ),
          ],
        ),
      ],
    );
  }

  /// En passant yalnızca 3. ve 6. yataylarda anlamlıdır.
  List<String> get _enPassantOptions {
    final options = <String>['-'];
    const files = 'abcdefgh';
    final rank = _sideToMove == engine.Color.white ? '6' : '3';
    for (final file in files.split('')) {
      options.add('$file$rank');
    }
    if (!options.contains(_enPassant)) options.add(_enPassant);
    return options;
  }

  /// Tahtanın o anki görüntüsünü PNG olarak kaydeder.
  Future<void> _saveBoardImage() async {
    final result = await BoardImageService.saveBoardPng(
      _boardKey,
      fileName: 'pozisyon.png',
    );
    if (!mounted) return;
    AppDialogs.snack(context, t('board.saveResult.$result'));
  }

  /// FEN alanındaki metni tahtaya uygular.
  ///
  /// Geçerli olur olmaz tahta güncellenir; ayrıca onay düğmesine gerek
  /// yoktur. Hata iletisi yazarken değil, yazmaya ara verilince gösterilir –
  /// yarım yazılmış bir FEN her tuşta uyarı çıkarmasın diye.
  void _applyFieldText({bool showError = false}) {
    _errorTimer?.cancel();
    final text = _fenController.text.trim();

    if (text.isEmpty) {
      setState(() => _fenFieldError = null);
      return;
    }

    final message = engine.ChessGame.validateFen(text);
    if (message == null) {
      setState(() {
        _fenFieldError = null;
        _applyFen(text);
      });
      return;
    }

    if (showError) {
      setState(() => _fenFieldError = message);
      return;
    }
    setState(() => _fenFieldError = null);
    _errorTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      final current = _fenController.text.trim();
      if (current.isEmpty) return;
      final error = engine.ChessGame.validateFen(current);
      if (error != null) setState(() => _fenFieldError = error);
    });
  }

  /// Alandaki metni silip panodakini yazar ve doğrudan uygular.
  Future<void> _pasteIntoField() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (!mounted) return;
    if (text == null || text.isEmpty) {
      AppDialogs.snack(context, t('common.noClipboardText'));
      return;
    }
    _fenController.text = text;
    _fenController.selection = TextSelection.collapsed(
      offset: _fenController.text.length,
    );
    _applyFieldText(showError: true);
  }

  Future<void> _pasteFen() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (!mounted) return;
    if (text == null || text.isEmpty) {
      AppDialogs.snack(context, t('common.noClipboardText'));
      return;
    }
    final message = engine.ChessGame.validateFen(text);
    if (message != null) {
      AppDialogs.snack(context, t('common.invalidFen', {'error': message}));
      return;
    }
    setState(() => _applyFen(text, updateField: true));
  }
}
