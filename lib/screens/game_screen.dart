import 'dart:async';

import 'package:flutter/material.dart';

import '../widgets/responsive.dart';

import 'package:flutter/services.dart';

import '../l10n/app_strings.dart';
import '../models/chess_engine.dart' as engine;
import '../models/move_entry.dart';
import '../models/pgn_parser.dart';
import '../models/playlist.dart';
import '../services/engine/engine_service.dart';
import '../services/settings_service.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/captured_pieces.dart';
import '../widgets/chess_board_widget.dart';
import '../widgets/eval_bar.dart';
import '../widgets/move_list.dart';
import 'board_editor_screen.dart';
import 'game_review_screen.dart';
import '../widgets/cursors.dart';

enum GameMode {
  /// PGN okuma / serbest analiz.
  analysis,

  /// Cihazdaki motora karşı oyun.
  versusEngine,
}

/// Tahta ekranı: PGN okuma, serbest oynama, analiz ve motora karşı oyun.
class GameScreen extends StatefulWidget {
  final GameMode mode;
  final String? pgnContent;
  final List<String>? uciMoves;
  final String? startFen;
  final String? title;
  final String? initialResult;

  /// Motora karşı oyunda kullanıcının rengi.
  final engine.Color playerColor;

  /// Motora karşı oyunda seviye (yoksa ayarlardaki seviye).
  final int? engineLevelIndex;

  const GameScreen({
    super.key,
    this.mode = GameMode.analysis,
    this.pgnContent,
    this.uciMoves,
    this.startFen,
    this.title,
    this.initialResult,
    this.playerColor = engine.Color.white,
    this.engineLevelIndex,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late String _startFen;
  late engine.ChessGame _game;

  final List<MoveEntry> _history = [];
  int _cursor = -1;

  bool _flipped = false;
  String? _resultText;
  String? _warning;

  /// Pes edildi mi? (Oyun bitmiş sayılır, tahta kilitlenir.)
  bool _resigned = false;

  /// Kayıtlı bir oyunu incelerken denenen hamleler.
  ///
  /// Bu hamleler oyunun kendisine yazılmaz: hamle listesinde görünmezler,
  /// PGN'e girmezler ve ekrandan çıkınca kaybolurlar. Amaç "şu hamle
  /// oynansaydı motor ne derdi?" sorusunu tahtada denemektir.
  final List<MoveEntry> _explore = [];

  /// Ekran hazır bir oyunu (PGN ya da kayıtlı oyun) gösteriyor mu?
  ///
  /// Böyle bir oyunda tahtaya oynanan hamleler oyunu değiştirmez, deneme
  /// sayılır. Serbest tahtada ise hamleler oyunun kendisidir. Okunamayan
  /// bir PGN hamle üretmediyse ekran yine serbest tahta gibi davranır.
  bool get _replayMode =>
      widget.mode == GameMode.analysis &&
      (widget.pgnContent != null || widget.uciMoves != null) &&
      _history.isNotEmpty;

  // Motor
  bool _analysisOn = false;
  bool _thinking = false;
  SearchResult? _analysis;
  Timer? _analysisDebounce;
  int _analysisToken = 0;

  late EngineLevel _level;

  @override
  void initState() {
    super.initState();
    _level = EngineLevel.all[
        (widget.engineLevelIndex ?? SettingsService.instance.engineLevel)
            .clamp(0, EngineLevel.all.length - 1)];
    _flipped = widget.playerColor == engine.Color.black &&
        widget.mode == GameMode.versusEngine;
    _resultText = widget.initialResult;
    _loadInitialPosition();
  }

  @override
  void dispose() {
    _analysisDebounce?.cancel();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Kurulum
  // -------------------------------------------------------------------------

  void _loadInitialPosition() {
    _startFen = widget.startFen ?? engine.ChessGame().fen;

    if (widget.pgnContent != null) {
      final parser = PgnParser();
      if (parser.parse(widget.pgnContent!)) {
        _startFen = parser.startFen ?? _startFen;
        _history
          ..clear()
          ..addAll(MoveEntry.fromUciList(parser.moves, startFen: _startFen));
        _resultText ??= parser.gameResult;
        if (parser.skippedTokens.isNotEmpty) {
          _warning = t('game.pgnSkipped', {
            'count': parser.skippedTokens.length,
            'tokens': parser.skippedTokens.take(4).join(', '),
          });
        }
        if (parser.moves.isEmpty) {
          _warning = t('game.pgnNoMoves');
        }
      } else {
        _warning = t('game.pgnUnreadable');
      }
    } else if (widget.uciMoves != null) {
      _history
        ..clear()
        ..addAll(MoveEntry.fromUciList(widget.uciMoves!, startFen: _startFen));
    }

    _cursor = -1;
    _game = engine.ChessGame.fromFen(_startFen);

    if (widget.mode == GameMode.versusEngine) {
      SoundService.instance.playGameStart();
      // Kullanıcı siyahsa motor ilk hamleyi yapar.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _maybePlayEngineMove(),
      );
    }
  }

  /// Konumu [_startFen] üzerinden [index] hamleye kadar yeniden kurar.
  engine.ChessGame _positionAt(int index) {
    final position = engine.ChessGame.fromFen(_startFen);
    for (int i = 0; i <= index && i < _history.length; i++) {
      position.makeMove(_history[i].move);
    }
    return position;
  }

  // -------------------------------------------------------------------------
  // Hamleler
  // -------------------------------------------------------------------------

  void _onBoardMove(engine.ChessMove move) {
    // Kayıtlı oyunda tahtaya oynamak oyunu değiştirmez, denemedir.
    if (_replayMode) {
      _exploreMove(move);
      return;
    }

    // Geçmişin ortasındayken oynanan hamle sonrasını siler.
    if (_cursor < _history.length - 1) {
      _history.removeRange(_cursor + 1, _history.length);
    }

    final entry = MoveEntry.play(_game, move);
    setState(() {
      _history.add(entry);
      _cursor = _history.length - 1;
      _resultText = null;
    });

    _announce(entry);
    _afterPositionChanged();

    if (widget.mode == GameMode.versusEngine) _maybePlayEngineMove();
  }

  /// Deneme hamlesi oynar; oyunun kendisine dokunmaz.
  void _exploreMove(engine.ChessMove move) {
    final entry = MoveEntry.play(_game, move);
    setState(() {
      _explore.add(entry);
      // Denemenin amacı değerlendirmeyi görmek; analiz kapalıysa açılır.
      _analysisOn = true;
    });
    SoundService.instance.playForSan(entry.san);
    _afterPositionChanged();
  }

  /// Son deneme hamlesini geri alır.
  void _undoExplore() {
    if (_explore.isEmpty) return;
    setState(() {
      _explore.removeLast();
      _game = _positionWithExplore();
    });
    _afterPositionChanged();
  }

  /// Tüm denemeleri atıp oyunun kendisine döner.
  void _clearExplore() {
    if (_explore.isEmpty) return;
    setState(() {
      _explore.clear();
      _game = _positionAt(_cursor);
    });
    _afterPositionChanged();
  }

  /// Ana hattın üzerine deneme hamleleri uygulanmış konum.
  engine.ChessGame _positionWithExplore() {
    final position = _positionAt(_cursor);
    for (final entry in _explore) {
      position.makeMove(entry.move);
    }
    return position;
  }

  void _goTo(int index) {
    final clamped = index.clamp(-1, _history.length - 1);
    final forward = clamped > _cursor;
    final position = _positionAt(clamped);

    setState(() {
      // Oyunda gezinmek denemeleri sonlandırır.
      _explore.clear();
      _cursor = clamped;
      _game = position;
    });

    if (forward && clamped >= 0) {
      _announce(_history[clamped], replay: true);
    }
    _afterPositionChanged();
  }

  /// Hamlenin sesini çalar ve oyun bittiyse sonucu yazar.
  void _announce(
    MoveEntry entry, {
    bool opponent = false,
    bool replay = false,
  }) {
    final gameOver = _game.isCheckmate || _game.isStalemate;

    if (gameOver) {
      SoundService.instance.playGameEnd();
    } else {
      SoundService.instance.playForSan(entry.san, opponent: opponent);
    }

    if (!replay && gameOver) {
      setState(() => _resultText = _autoResult());
      _offerReview();
    }
  }

  /// Oyun bitince incelemeyi teklif eder.
  void _offerReview() {
    if (!mounted || _history.isEmpty) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(t('game.finishedOfferReview')),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: t('game.review'),
            onPressed: _openReview,
          ),
        ),
      );
  }

  void _openReview() {
    if (_history.isEmpty) {
      AppDialogs.snack(context, t('game.nothingToReview'));
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GameReviewScreen(
          history: List<MoveEntry>.from(_history),
          startFen: _startFen == engine.ChessGame().fen ? null : _startFen,
        ),
      ),
    );
  }

  String? _autoResult() {
    if (_game.isCheckmate) {
      return _game.sideToMove == engine.Color.white ? '0-1' : '1-0';
    }
    if (_game.isStalemate) return '1/2-1/2';
    if (_game.fiftyMoveRule) return '1/2-1/2';
    if (_game.insufficientMaterial) return '1/2-1/2';
    return null;
  }

  void _afterPositionChanged() {
    if (!_analysisOn) return;
    _analysisDebounce?.cancel();
    _analysisDebounce = Timer(const Duration(milliseconds: 220), _runAnalysis);
  }

  // -------------------------------------------------------------------------
  // Motor
  // -------------------------------------------------------------------------

  Future<void> _runAnalysis() async {
    if (!_analysisOn) return;
    final fen = _game.fen;
    final token = ++_analysisToken;
    setState(() => _thinking = true);

    final result = await EngineService.instance.analyze(
      fen,
      depth: 16,
      movetimeMs: 1200,
      onProgress: (partial) {
        if (token != _analysisToken || !mounted) return;
        setState(() => _analysis = partial);
      },
    );

    if (token != _analysisToken || !mounted) return;
    setState(() {
      _analysis = result;
      _thinking = false;
    });
  }

  Future<void> _maybePlayEngineMove() async {
    if (widget.mode != GameMode.versusEngine) return;
    if (!mounted || _resigned) return;
    if (_game.sideToMove == widget.playerColor) return;
    if (_game.isCheckmate || _game.isStalemate) return;
    if (_cursor != _history.length - 1) return;

    setState(() => _thinking = true);
    final fen = _game.fen;
    final result = await EngineService.instance.bestMoveForLevel(fen, _level);
    if (!mounted) return;
    setState(() => _thinking = false);

    if (result.bestMoveUci.isEmpty) return;
    // Kullanıcı bu sırada geri aldıysa hamleyi uygulama.
    if (_game.fen != fen) return;

    final move = _game.moveFromUci(result.bestMoveUci);
    if (move == null) return;

    final entry = MoveEntry.play(_game, move);
    setState(() {
      _history.add(entry);
      _cursor = _history.length - 1;
    });
    _announce(entry, opponent: true);
  }

  Future<void> _takeBack() async {
    if (_history.isEmpty) return;
    // Motora karşı oyunda kendi hamlemize dönmek için iki hamle geri al.
    final steps = widget.mode == GameMode.versusEngine ? 2 : 1;
    final target = (_history.length - steps).clamp(0, _history.length);
    setState(() {
      _history.removeRange(target, _history.length);
      _cursor = _history.length - 1;
      _game = _positionAt(_cursor);
      _resultText = null;
    });
    _afterPositionChanged();
  }

  Future<void> _showHint() async {
    setState(() => _thinking = true);
    final result = await EngineService.instance.analyze(
      _game.fen,
      depth: 12,
      movetimeMs: 1200,
    );
    if (!mounted) return;
    setState(() {
      _thinking = false;
      _analysis = result;
      _analysisOn = true;
    });
  }

  // -------------------------------------------------------------------------
  // Menü işlemleri
  // -------------------------------------------------------------------------

  String _buildPgn() {
    return PgnParser.buildPgn(
      uciMoves: _history.map((e) => e.uci).toList(),
      startFen: _startFen == engine.ChessGame().fen ? null : _startFen,
      result: _resultText,
      tags: {'Event': widget.title ?? t('app.title')},
    );
  }

  Future<void> _copyPgn() async {
    await Clipboard.setData(ClipboardData(text: _buildPgn()));
    if (mounted) AppDialogs.snack(context, t('game.pgnCopied'));
  }

  Future<void> _copyFen() async {
    await Clipboard.setData(ClipboardData(text: _game.fen));
    if (mounted) AppDialogs.snack(context, t('game.fenCopiedToClipboard'));
  }

  Future<void> _pasteFen() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      if (mounted) AppDialogs.snack(context, t('common.noClipboardText'));
      return;
    }
    final error = engine.ChessGame.validateFen(text);
    if (error != null) {
      if (mounted) {
        AppDialogs.snack(context, t('common.invalidFen', {'error': error}));
      }
      return;
    }
    setState(() {
      _startFen = text;
      _history.clear();
      _cursor = -1;
      _game = engine.ChessGame.fromFen(text);
      _resultText = null;
    });
    _afterPositionChanged();
  }

  Future<void> _editPosition() async {
    final fen = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => BoardEditorScreen(initialFen: _game.fen),
      ),
    );
    if (fen == null || !mounted) return;
    setState(() {
      _startFen = fen;
      _history.clear();
      _cursor = -1;
      _game = engine.ChessGame.fromFen(fen);
      _resultText = null;
    });
    _afterPositionChanged();
  }

  /// Kullanıcı pes eder; oyun rakibin kazancıyla biter.
  Future<void> _resign() async {
    final confirmed = await AppDialogs.confirm(
      context,
      title: t('game.resign'),
      message: t('game.resignMessage'),
      confirmLabel: t('game.resign'),
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    // Motora karşı oyunda kullanıcının rengi, serbest tahtada sırası gelen
    // taraf pes etmiş sayılır.
    final loser = widget.mode == GameMode.versusEngine
        ? widget.playerColor
        : _game.sideToMove;

    setState(() {
      _resigned = true;
      _resultText = loser == engine.Color.white ? '0-1' : '1-0';
    });
    SoundService.instance.playGameEnd();
    _offerReview();
  }

  Future<void> _restart() async {
    final confirmed = await AppDialogs.confirm(
      context,
      title: t('game.restart'),
      message: t('game.restartMessage'),
      confirmLabel: t('common.delete'),
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _history.clear();
      _cursor = -1;
      _game = engine.ChessGame.fromFen(_startFen);
      _resultText = null;
      _analysis = null;
      _resigned = false;
    });
    if (widget.mode == GameMode.versusEngine) _maybePlayEngineMove();
  }

  Future<void> _saveGame() async {
    if (_history.isEmpty) {
      AppDialogs.snack(context, t('game.nothingToSave'));
      return;
    }

    final storage = StorageService.instance;
    var playlists = await storage.loadPlaylists();
    if (!mounted) return;

    if (playlists.isEmpty) {
      final name = await AppDialogs.prompt(
        context,
        title: t('game.newList'),
        label: t('game.listName'),
        initialValue: t('game.defaultListName'),
      );
      if (name == null || !mounted) return;
      await storage.createPlaylist(name);
      playlists = await storage.loadPlaylists();
      if (!mounted) return;
    }

    String selectedId = playlists.first.id;
    final nameController = TextEditingController(
      text: widget.title ??
          t('game.defaultGameName', {
            'date': DateTime.now().toString().substring(0, 16),
          }),
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text(t('game.saveGame')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                mouseCursor: kClickable,
                initialValue: selectedId,
                decoration: InputDecoration(labelText: t('game.list')),
                items: playlists
                    .map(
                      (p) => DropdownMenuItem(
                        value: p.id,
                        child: Text(p.name, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setLocalState(() => selectedId = value ?? selectedId),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                decoration: InputDecoration(labelText: t('game.gameName')),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(t('common.cancel')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(t('common.save')),
            ),
          ],
        ),
      ),
    );

    if (saved != true || !mounted) return;

    await storage.addGame(
      selectedId,
      SavedGame(
        name: nameController.text.trim().isEmpty
            ? 'Oyun'
            : nameController.text.trim(),
        uciMoves: _history.map((e) => e.uci).toList(),
        createdAt: DateTime.now(),
        result: _resultText,
        startFen: _startFen == engine.ChessGame().fen ? null : _startFen,
      ),
    );
    if (mounted) AppDialogs.snack(context, t('game.saved'));
  }

  // -------------------------------------------------------------------------
  // Arayüz
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final settings = SettingsService.instance;
    final atLive = _cursor == _history.length - 1 && !_resigned;

    final arrows = <BoardArrow>[];
    final best = _analysis?.bestMoveUci;
    if (_analysisOn && best != null && best.length >= 4) {
      final move = _game.moveFromUci(best);
      if (move != null) {
        arrows.add(
          BoardArrow(
            move.from,
            move.to,
            scheme.primary.withValues(alpha: 0.75),
          ),
        );
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title ??
              (widget.mode == GameMode.versusEngine
                  ? t('game.vsEngine', {'level': _level.name})
                  : t('game.board')),
        ),
        actions: [
          IconButton(
            tooltip: t('common.flipBoard'),
            icon: const Icon(Icons.swap_vert_rounded),
            onPressed: () => setState(() => _flipped = !_flipped),
          ),
          IconButton(
            tooltip: _analysisOn ? t('game.analysisOff') : t('game.analysisOn'),
            icon: Icon(
              Icons.insights_rounded,
              color: _analysisOn ? scheme.primary : null,
            ),
            onPressed: () {
              setState(() => _analysisOn = !_analysisOn);
              if (_analysisOn) {
                _runAnalysis();
              } else {
                _analysisToken++;
                setState(() {
                  _analysis = null;
                  _thinking = false;
                });
              }
            },
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'review':
                  _openReview();
                  break;
                case 'save':
                  _saveGame();
                  break;
                case 'pgn':
                  _copyPgn();
                  break;
                case 'fen':
                  _copyFen();
                  break;
                case 'paste':
                  _pasteFen();
                  break;
                case 'edit':
                  _editPosition();
                  break;
                case 'resign':
                  _resign();
                  break;
                case 'restart':
                  _restart();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'review',
                child: ListTile(
                  leading: const Icon(Icons.query_stats_rounded),
                  title: Text(t('game.reviewGame')),
                ),
              ),
              PopupMenuItem(
                value: 'save',
                child: ListTile(
                  leading: const Icon(Icons.bookmark_add_outlined),
                  title: Text(t('game.saveToList')),
                ),
              ),
              PopupMenuItem(
                value: 'pgn',
                child: ListTile(
                  leading: const Icon(Icons.copy_all_rounded),
                  title: Text(t('game.copyPgn')),
                ),
              ),
              PopupMenuItem(
                value: 'fen',
                child: ListTile(
                  leading: const Icon(Icons.copy_rounded),
                  title: Text(t('common.copyFen')),
                ),
              ),
              PopupMenuItem(
                value: 'paste',
                child: ListTile(
                  leading: const Icon(Icons.content_paste_rounded),
                  title: Text(t('common.pasteFen')),
                ),
              ),
              PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  leading: const Icon(Icons.dashboard_customize_outlined),
                  title: Text(t('common.editPosition')),
                ),
              ),
              if (_history.isNotEmpty && _resultText == null)
                PopupMenuItem(
                  value: 'resign',
                  child: ListTile(
                    leading: const Icon(Icons.flag_outlined),
                    title: Text(t('game.resign')),
                  ),
                ),
              PopupMenuItem(
                value: 'restart',
                child: ListTile(
                  leading: const Icon(Icons.restart_alt_rounded),
                  title: Text(t('game.restart')),
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ContentWidth(
          child: Column(
            children: [
              if (_warning != null) _warningBanner(scheme),
              _playerRow(scheme, top: true),
              // Tahta, kalan alana sığacak en büyük kare olarak çizilir;
              // böylece kısa ekranlarda taşma olmaz.
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final showBar =
                            settings.showEvaluationBar && _analysisOn;
                        final barWidth = showBar ? 26.0 : 0.0;
                        // Geniş pencerede tahta sınırsız büyümesin.
                        final side = Layout.boardSide(
                          constraints.maxWidth - barWidth,
                          constraints.maxHeight,
                        );
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (showBar) ...[
                              SizedBox(
                                height: side,
                                child: EvalBar(
                                  scoreCp: _whiteScore,
                                  mateIn: _whiteMate,
                                  flipped: _flipped,
                                  thinking: _thinking,
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            SizedBox(
                              width: side,
                              height: side,
                              child: ChessBoardWidget(
                                game: _game,
                                flipped: _flipped,
                                // Kayıtlı oyunda hamle oynamak oyunu
                                // değiştirmez; deneme olarak çalışır.
                                interactive: _replayMode || atLive,
                                movableSide:
                                    widget.mode == GameMode.versusEngine
                                        ? widget.playerColor
                                        : null,
                                lastMove: _explore.isNotEmpty
                                    ? _explore.last.move
                                    : (_cursor >= 0
                                        ? _history[_cursor].move
                                        : null),
                                onMove: _onBoardMove,
                                arrows: arrows,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
              _playerRow(scheme, top: false),
              if (_explore.isNotEmpty) _exploreCard(scheme),
              if (_analysisOn) _engineLine(scheme),
              // Deneme sırasında tahtadaki konum oyunun sonucunu yansıtmaz.
              if (_resultText != null && _explore.isEmpty)
                _resultBanner(scheme),
              _controls(scheme),
            ],
          ),
        ),
      ),
    );
  }

  int? get _whiteScore {
    final analysis = _analysis;
    if (analysis == null) return null;
    final sign = _game.sideToMove == engine.Color.white ? 1 : -1;
    return analysis.scoreCp * sign;
  }

  int? get _whiteMate {
    final mate = _analysis?.mateIn;
    if (mate == null) return null;
    return _game.sideToMove == engine.Color.white ? mate : -mate;
  }

  Widget _warningBanner(ColorScheme scheme) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: scheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _warning!,
              style: TextStyle(color: scheme.onErrorContainer, fontSize: 12),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: () => setState(() => _warning = null),
          ),
        ],
      ),
    );
  }

  Widget _playerRow(ColorScheme scheme, {required bool top}) {
    // Üst sıra her zaman tahtanın uzak tarafındaki oyuncudur.
    final isWhiteSide = top ? _flipped : !_flipped;
    final side = isWhiteSide ? engine.Color.white : engine.Color.black;
    final toMove = _game.sideToMove == side;

    String name;
    if (widget.mode == GameMode.versusEngine) {
      name = side == widget.playerColor
          ? t('game.you')
          : t('game.engine', {'level': _level.name});
    } else {
      name = side == engine.Color.white ? t('common.white') : t('common.black');
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: side == engine.Color.white
                  ? const Color(0xFFF2EEE7)
                  : const Color(0xFF3B3630),
              border: Border.all(color: scheme.outlineVariant),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            name,
            style: TextStyle(
              fontWeight: toMove ? FontWeight.w800 : FontWeight.w500,
              color: toMove ? scheme.onSurface : scheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
          if (toMove && _thinking) ...[
            const SizedBox(width: 8),
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
          const SizedBox(width: 12),
          Expanded(
            child: CapturedPieces(side: side, game: _game, size: 16),
          ),
        ],
      ),
    );
  }

  /// Denenen hamleleri ve bunların kaydedilmediğini gösteren şerit.
  Widget _exploreCard(ColorScheme scheme) {
    final sanMoves = _explore.map((e) => e.san).join(' ');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.alt_route_rounded,
            size: 17,
            color: scheme.onSecondaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sanMoves,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSecondaryContainer,
                  ),
                ),
                Text(
                  t('game.exploreHint'),
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSecondaryContainer.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: t('game.undoExplore'),
            icon: const Icon(Icons.undo_rounded, size: 20),
            color: scheme.onSecondaryContainer,
            onPressed: _undoExplore,
          ),
          IconButton(
            tooltip: t('game.backToGame'),
            icon: const Icon(Icons.close_rounded, size: 20),
            color: scheme.onSecondaryContainer,
            onPressed: _clearExplore,
          ),
        ],
      ),
    );
  }

  Widget _engineLine(ColorScheme scheme) {
    final analysis = _analysis;
    final text = analysis == null
        ? t('game.enginePreparing')
        : _describeAnalysis(analysis);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.memory_rounded, size: 16, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  String _describeAnalysis(SearchResult analysis) {
    final evaluation = analysis.mateIn != null
        ? t('game.mateIn', {'n': analysis.mateIn!.abs()})
        : (_whiteScore! / 100).toStringAsFixed(2);

    // Ana varyantı SAN'a çevir.
    final position = _game.copy();
    final sanMoves = <String>[];
    for (final uci in analysis.pvUci.take(6)) {
      final move = position.moveFromUci(uci);
      if (move == null) break;
      sanMoves.add(position.sanFor(move));
      position.makeMove(move);
    }

    return '$evaluation  ·  ${t('game.depth')} ${analysis.depth}  ·  '
        '${sanMoves.isEmpty ? "—" : sanMoves.join(" ")}';
  }

  Widget _resultBanner(ColorScheme scheme) {
    final result = _resultText!;
    final label = switch (result) {
      '1-0' => t('game.whiteWon'),
      '0-1' => t('game.blackWon'),
      '1/2-1/2' => t('game.drawn'),
      _ => result,
    };
    final color = switch (result) {
      '1-0' => scheme.success,
      '0-1' => scheme.error,
      _ => scheme.drawColor,
    };

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _resigned
            ? '$label · ${t('game.resigned')}  ($result)'
            : '$label  ($result)',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
    );
  }

  Widget _controls(ColorScheme scheme) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 52,
            child: MoveList(
              moves: _history,
              currentIndex: _cursor,
              onMoveTap: _goTo,
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                if (widget.mode == GameMode.versusEngine)
                  _navButton(
                    Icons.undo_rounded,
                    _history.isEmpty ? null : _takeBack,
                    t('game.takeBack'),
                  )
                else
                  _navButton(
                    Icons.first_page_rounded,
                    _cursor >= 0 ? () => _goTo(-1) : null,
                    t('game.toStart'),
                  ),
                _navButton(
                  Icons.chevron_left_rounded,
                  _cursor >= 0 ? () => _goTo(_cursor - 1) : null,
                  t('common.previous'),
                ),
                _navButton(
                  Icons.chevron_right_rounded,
                  _cursor < _history.length - 1
                      ? () => _goTo(_cursor + 1)
                      : null,
                  t('game.forward'),
                ),
                _navButton(
                  Icons.last_page_rounded,
                  _cursor < _history.length - 1
                      ? () => _goTo(_history.length - 1)
                      : null,
                  t('game.toEnd'),
                ),
                _navButton(
                  Icons.lightbulb_outline_rounded,
                  _thinking ? null : _showHint,
                  t('common.hint'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _navButton(IconData icon, VoidCallback? onPressed, String tooltip) {
    return IconButton(
      icon: Icon(icon),
      iconSize: 26,
      tooltip: tooltip,
      onPressed: onPressed,
    );
  }
}
