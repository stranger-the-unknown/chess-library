import 'package:flutter/material.dart';

import '../../widgets/responsive.dart';

import 'package:flutter/services.dart';

import '../../l10n/app_strings.dart';
import '../../models/chess_engine.dart' as engine;
import '../../models/move_entry.dart';
import '../../models/puzzle.dart';
import '../../services/board_image_service.dart';
import '../../services/engine/engine_service.dart';
import '../../services/puzzle_service.dart';
import '../../services/sound_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_dialogs.dart';
import '../../widgets/chess_board_widget.dart';
import '../../widgets/move_list.dart';
import '../board_editor_screen.dart';
import '../game_screen.dart';

enum _Feedback { none, thinking, correct, wrong, finished }

/// Bulmaca çözme ekranı.
///
/// Bu listelerde hazır çözüm anahtarı yoktur; bu yüzden doğruluk, cihazdaki
/// motorun değerlendirmesiyle ölçülür: kullanıcının hamlesi pozisyonun
/// değerini en iyi hamleye göre belirgin biçimde düşürmüyorsa doğru sayılır.
/// Böylece tek bir "kabul edilen" hamle yerine eşdeğer iyi hamleler de
/// kabul edilir.
class PuzzleSolveScreen extends StatefulWidget {
  final PuzzleCollection collection;
  final List<Puzzle> puzzles;
  final int initialIndex;

  /// Bulmaca kimliği -> listedeki asıl numara.
  ///
  /// Ekrandaki liste süzülmüş ya da ters çevrilmiş olabilir; başlıkta ve
  /// bilgi satırında ise her zaman bu numara görünür, böylece kullanıcının
  /// gördüğü numara kitaptaki/listedeki numarayla aynı kalır.
  final Map<String, int> numbers;

  /// Süzgeçsiz listedeki toplam bulmaca sayısı.
  final int totalInCollection;

  const PuzzleSolveScreen({
    super.key,
    required this.collection,
    required this.puzzles,
    required this.initialIndex,
    this.numbers = const {},
    this.totalInCollection = 0,
  });

  @override
  State<PuzzleSolveScreen> createState() => _PuzzleSolveScreenState();
}

class _PuzzleSolveScreenState extends State<PuzzleSolveScreen> {
  static const int _toleranceCp = 80;

  final PuzzleService _service = PuzzleService.instance;

  late int _index;
  late Puzzle _puzzle;
  late engine.ChessGame _game;
  late engine.Color _solverColor;

  final List<MoveEntry> _moves = [];
  SearchResult? _baseline;

  /// Kullanıcı kayıtlı çözüm dizisini takip ediyor mu?
  bool _onSolutionLine = false;
  _Feedback _feedback = _Feedback.none;
  String _feedbackText = '';
  bool _busy = false;
  bool _showHint = false;
  bool _solved = false;
  bool _favorite = false;
  bool _flipped = false;

  /// Kullanıcı tahtayı el ile çevirdiyse, sonraki bulmacalarda da o yön
  /// korunur; aksi hâlde çözen tarafa göre otomatik ayarlanır.
  bool _manualFlip = false;
  int _loadToken = 0;

  /// Tahtanın PNG olarak kaydedilebilmesi için çizim sınırı.
  final GlobalKey _boardKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.puzzles.length - 1);
    _loadPuzzle();
  }

  // -------------------------------------------------------------------------
  // Yükleme
  // -------------------------------------------------------------------------

  Future<void> _loadPuzzle() async {
    final token = ++_loadToken;
    _puzzle = widget.puzzles[_index];

    setState(() {
      _game = engine.ChessGame.fromFen(_puzzle.fen);
      _solverColor = _game.sideToMove;
      if (!_manualFlip) _flipped = _solverColor == engine.Color.black;
      _moves.clear();
      _onSolutionLine = _puzzle.hasSolution;
      _baseline = null;
      _showHint = false;
      // Çözümü bilinen bulmacalarda motoru beklemeye gerek yok.
      _busy = !_puzzle.hasSolution;
      _feedback = _puzzle.hasSolution ? _Feedback.none : _Feedback.thinking;
      _feedbackText = _puzzle.hasSolution ? '' : t('puzzles.analysing');
    });

    final progress = await _service.progressOf(_puzzle.id);
    if (token != _loadToken || !mounted) return;
    setState(() {
      _solved = progress.solved;
      _favorite = progress.favorite;
    });

    if (_puzzle.hasSolution) return;

    final baseline = await EngineService.instance.analyze(
      _puzzle.fen,
      depth: 30,
      movetimeMs: 1800,
    );
    if (token != _loadToken || !mounted) return;

    setState(() {
      _baseline = baseline;
      _busy = false;
      _feedback = _Feedback.none;
      _feedbackText = '';
    });
  }

  /// Çözüm dizisinde sırada beklenen hamle (UCI); yoksa `null`.
  String? get _expectedMove {
    if (!_onSolutionLine || !_puzzle.hasSolution) return null;
    if (_moves.length >= _puzzle.solution.length) return null;
    return _puzzle.solution[_moves.length];
  }

  /// İpucu ya da çözüm gösterilebilir mi?
  bool get _hasAnswer => _puzzle.hasSolution || _baseline != null;

  String get _goalText {
    if (_puzzle.hasSolution) {
      return t('puzzles.goalMate', {'n': _puzzle.mateInMoves});
    }
    final baseline = _baseline;
    if (baseline == null) return t('puzzles.positionAnalysing');
    if (baseline.isGameOver) return t('puzzles.noMoveHere');
    if (baseline.mateIn != null && baseline.mateIn! > 0) {
      return t('puzzles.goalMate', {'n': baseline.mateIn});
    }
    if (baseline.scoreCp >= 250) return t('puzzles.goalWin');
    if (baseline.scoreCp <= -250) return t('puzzles.goalDefend');
    return t('puzzles.goalBest');
  }

  // -------------------------------------------------------------------------
  // Hamle değerlendirme
  // -------------------------------------------------------------------------

  Future<void> _onMove(engine.ChessMove move) async {
    if (_busy) return;
    if (!_puzzle.hasSolution && _baseline == null) return;

    setState(() {
      _busy = true;
      _feedback = _Feedback.thinking;
      _feedbackText = t('puzzles.evaluating');
    });

    final probe = _game.copy();
    final san = probe.sanFor(move);
    probe.makeMove(move);

    final correct = await _isCorrect(move, probe);
    if (!mounted) return;

    await _service.registerAttempt(_puzzle.id);

    if (!correct) {
      SoundService.instance.playWrong();
      setState(() {
        _busy = false;
        _feedback = _Feedback.wrong;
        _feedbackText = t('puzzles.wrong', {'move': san});
      });
      return;
    }

    // Doğru hamle: tahtaya uygula.
    final entry = MoveEntry.play(_game, move);
    setState(() {
      _moves.add(entry);
      _feedback = _Feedback.correct;
      _feedbackText = t('puzzles.correct', {'move': san});
    });
    SoundService.instance.playForSan(san);

    if (!_solved) {
      await _service.markSolved(_puzzle.id);
      if (mounted) setState(() => _solved = true);
    }

    if (_game.isCheckmate || _game.isStalemate) {
      if (_game.isCheckmate) SoundService.instance.playNotify();
      setState(() {
        _busy = false;
        _feedback = _Feedback.finished;
        _feedbackText =
            _game.isCheckmate ? t('puzzles.mateDone') : t('puzzles.stalemate');
      });
      return;
    }

    await _playOpponentReply();
  }

  /// Oynanan hamlenin kabul edilip edilmeyeceğine karar verir.
  ///
  /// Çözümü kayıtlı bulmacalarda önce kayıtlı hamleye bakılır; farklı ama
  /// yine aynı sürede mat eden hamleler de motora danışılarak kabul edilir.
  Future<bool> _isCorrect(engine.ChessMove move, engine.ChessGame after) async {
    if (after.isCheckmate) return true;

    final expected = _expectedMove;
    if (expected != null) {
      if (move.uci == expected) return true;

      // Kayıtlı çözümden ayrıldı: aynı hızda mat eden bir alternatif mi?
      final remaining = _puzzle.solution.length - _moves.length;
      final allowedMoves = (remaining + 1) ~/ 2;
      final reply = await EngineService.instance.analyze(
        after.fen,
        depth: 30,
        movetimeMs: 1200,
      );
      final userMate = reply.mateIn == null ? null : -reply.mateIn!;
      if (userMate != null && userMate > 0 && userMate <= allowedMoves) {
        _onSolutionLine = false;
        return true;
      }
      return false;
    }

    final baseline = _baseline;
    if (baseline == null) return false;
    if (move.uci == baseline.bestMoveUci) return true;

    final reply = await EngineService.instance.analyze(
      after.fen,
      depth: 30,
      movetimeMs: 1400,
    );

    // Sonuç rakibin bakış açısındandır; kullanıcıya çevir.
    final userScore = -reply.scoreCp;
    final userMate = reply.mateIn == null ? null : -reply.mateIn!;

    if (baseline.mateIn != null && baseline.mateIn! > 0) {
      return userMate != null &&
          userMate > 0 &&
          userMate <= baseline.mateIn! + 1;
    }
    return userScore >= baseline.scoreCp - _toleranceCp;
  }

  Future<void> _playOpponentReply() async {
    final fen = _game.fen;

    // Kayıtlı çözüm dizisi varsa rakip o diziyi oynar.
    final scripted = _expectedMove;
    String? uci = scripted;
    if (uci == null) {
      final result = await EngineService.instance.analyze(
        fen,
        depth: 24,
        movetimeMs: 900,
      );
      uci = result.bestMoveUci;
    }
    if (!mounted || _game.fen != fen) return;

    final move = _game.moveFromUci(uci);
    if (move == null) {
      setState(() {
        _busy = false;
        _feedback = _Feedback.finished;
        _feedbackText = t('puzzles.opponentStuck');
      });
      return;
    }

    final entry = MoveEntry.play(_game, move);
    setState(() {
      _moves.add(entry);
      _busy = false;
      if (_game.isCheckmate) {
        _feedback = _Feedback.finished;
        _feedbackText = t('puzzles.opponentMated');
      } else {
        _feedback = _Feedback.correct;
        _feedbackText = t('puzzles.opponentPlayed', {'move': entry.san});
      }
    });
    SoundService.instance.playForSan(entry.san, opponent: true);
  }

  void _retry() {
    setState(() {
      _game = engine.ChessGame.fromFen(_puzzle.fen);
      _onSolutionLine = _puzzle.hasSolution;
      _moves.clear();
      _feedback = _Feedback.none;
      _feedbackText = '';
      _showHint = false;
    });
  }

  Future<void> _revealSolution() async {
    final line = _puzzle.hasSolution
        ? _puzzle.solution
        : (_baseline?.pvUci ?? const <String>[]);
    if (line.isEmpty) return;
    _retry();

    // Çözümü adım adım oyna.
    for (final uci in line.take(8)) {
      if (!mounted) return;
      final move = _game.moveFromUci(uci);
      if (move == null) break;
      final entry = MoveEntry.play(_game, move);
      setState(() => _moves.add(entry));
      await Future<void>.delayed(const Duration(milliseconds: 420));
    }
    if (!mounted) return;
    setState(() {
      _feedback = _Feedback.finished;
      _feedbackText = t('puzzles.solutionShown');
    });
  }

  void _goToPuzzle(int index) {
    if (index < 0 || index >= widget.puzzles.length) return;
    setState(() => _index = index);
    _loadPuzzle();
  }

  Future<void> _toggleFavorite() async {
    final value = await _service.toggleFavorite(_puzzle.id);
    if (mounted) setState(() => _favorite = value);
  }

  Future<void> _editPuzzle() async {
    final fen = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => BoardEditorScreen(
          initialFen: _puzzle.fen,
          title: t('puzzles.editPuzzle'),
        ),
      ),
    );
    if (fen == null || !mounted) return;
    await _service.updatePuzzle(
      widget.collection,
      _puzzle,
      fen: fen,
      title: _puzzle.title,
      note: _puzzle.note,
      tags: _puzzle.tags,
    );
    _puzzle.fen = fen;
    widget.puzzles[_index] = _puzzle;
    _loadPuzzle();
  }

  /// Bulmacanın süzgeçten bağımsız numarası.
  int get _absoluteNumber =>
      widget.numbers[_puzzle.id] ?? _puzzle.number ?? _index + 1;

  /// Tahtanın o anki görüntüsünü PNG olarak kaydeder.
  ///
  /// Dosya adı `board-<liste>-<numara>.png` olur: kaydedilen görüntüler
  /// hangi listenin kaçıncı bulmacası olduğu belli olacak şekilde
  /// birikir.
  Future<void> _saveBoardImage() async {
    final list = widget.collection.name
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .trim();
    final result = await BoardImageService.saveBoardPng(
      _boardKey,
      fileName: 'board-${list.isEmpty ? 'liste' : list}-$_absoluteNumber.png',
    );
    if (!mounted) return;
    AppDialogs.snack(context, t('board.saveResult.$result'));
  }

  Future<void> _addNote() async {
    final note = await AppDialogs.prompt(
      context,
      title: t('common.note'),
      label: t('puzzles.noteLabel'),
      initialValue: _puzzle.note ?? '',
      maxLines: 4,
    );
    if (note == null || !mounted) return;
    await _service.updatePuzzle(
      widget.collection,
      _puzzle,
      fen: _puzzle.fen,
      title: _puzzle.title,
      note: note,
      tags: _puzzle.tags,
    );
    setState(() => _puzzle.note = note);
  }

  /// Bulmacanın notunu siler.
  Future<void> _deleteNote() async {
    await _service.updatePuzzle(
      widget.collection,
      _puzzle,
      fen: _puzzle.fen,
      title: _puzzle.title,
      note: null,
      tags: _puzzle.tags,
    );
    if (!mounted) return;
    setState(() => _puzzle.note = null);
    AppDialogs.snack(context, t('common.noteDeleted'));
  }

  // -------------------------------------------------------------------------
  // Arayüz
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final arrows = <BoardArrow>[];
    if (_showHint) {
      final best =
          _expectedMove ?? (_moves.isEmpty ? _baseline?.bestMoveUci : null);
      if (best != null && best.length >= 4) {
        final move = _game.moveFromUci(best);
        if (move != null) {
          arrows.add(
            BoardArrow(
              move.from,
              move.to,
              scheme.primary.withValues(alpha: 0.8),
            ),
          );
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _puzzle.title ?? t('puzzles.puzzleTitle', {'n': _absoluteNumber}),
        ),
        actions: [
          IconButton(
            tooltip: _favorite
                ? t('common.favoriteRemove')
                : t('common.favoriteAdd'),
            icon: Icon(
              _favorite ? Icons.star_rounded : Icons.star_border_rounded,
              color: _favorite ? scheme.warning : null,
            ),
            onPressed: _toggleFavorite,
          ),
          IconButton(
            tooltip: t('common.flipBoard'),
            icon: const Icon(Icons.swap_vert_rounded),
            onPressed: () => setState(() {
              _flipped = !_flipped;
              _manualFlip = true;
            }),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'edit':
                  _editPuzzle();
                  break;
                case 'note':
                  _addNote();
                  break;
                case 'deleteNote':
                  _deleteNote();
                  break;
                case 'fen':
                  Clipboard.setData(ClipboardData(text: _puzzle.fen));
                  AppDialogs.snack(context, t('common.fenCopied'));
                  break;
                case 'png':
                  _saveBoardImage();
                  break;
                case 'play':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GameScreen(
                        mode: GameMode.versusEngine,
                        startFen: _puzzle.fen,
                        playerColor: _solverColor,
                        title: t('puzzles.continueVsEngine'),
                      ),
                    ),
                  );
                  break;
                case 'analyze':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GameScreen(
                        startFen: _puzzle.fen,
                        title: t('puzzles.analysisTitle'),
                      ),
                    ),
                  );
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'edit',
                child: Text(t('common.editPosition')),
              ),
              PopupMenuItem(value: 'note', child: Text(t('common.addNote'))),
              if (_puzzle.note != null && _puzzle.note!.isNotEmpty)
                PopupMenuItem(
                  value: 'deleteNote',
                  child: Text(t('common.deleteNote')),
                ),
              PopupMenuItem(value: 'fen', child: Text(t('common.copyFen'))),
              PopupMenuItem(value: 'png', child: Text(t('board.savePng'))),
              PopupMenuItem(
                value: 'play',
                child: Text(t('puzzles.playVsEngine')),
              ),
              PopupMenuItem(
                value: 'analyze',
                child: Text(t('common.openInAnalysis')),
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
              _header(scheme),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final side = Layout.boardSide(
                          constraints.maxWidth,
                          constraints.maxHeight,
                        );
                        return RepaintBoundary(
                          key: _boardKey,
                          child: SizedBox(
                            width: side,
                            height: side,
                            child: ChessBoardWidget(
                              game: _game,
                              flipped: _flipped,
                              interactive:
                                  !_busy && _feedback != _Feedback.finished,
                              movableSide: _solverColor,
                              lastMove:
                                  _moves.isEmpty ? null : _moves.last.move,
                              onMove: _onMove,
                              arrows: arrows,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              if (_puzzle.note != null && _puzzle.note!.isNotEmpty)
                _noteCard(scheme),
              _feedbackCard(scheme),
              if (_moves.isNotEmpty)
                SizedBox(
                  height: 46,
                  child: MoveList(
                    moves: _moves,
                    currentIndex: _moves.length - 1,
                    onMoveTap: (_) {},
                  ),
                ),
              _actions(scheme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _solverColor == engine.Color.white
                  ? const Color(0xFFF2EEE7)
                  : const Color(0xFF3B3630),
              border: Border.all(color: scheme.outlineVariant),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              t('puzzles.header', {
                'side': _puzzle.sideToMoveLabel,
                'index': _absoluteNumber,
                'total': widget.totalInCollection == 0
                    ? widget.puzzles.length
                    : widget.totalInCollection,
              }),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          if (_solved)
            Row(
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  size: 15,
                  color: scheme.success,
                ),
                const SizedBox(width: 4),
                Text(
                  t('puzzles.solved'),
                  style: TextStyle(fontSize: 12, color: scheme.success),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _noteCard(ColorScheme scheme) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _puzzle.note!,
        style: TextStyle(fontSize: 12.5, color: scheme.onSecondaryContainer),
      ),
    );
  }

  Widget _feedbackCard(ColorScheme scheme) {
    final (color, icon, text) = switch (_feedback) {
      _Feedback.correct => (
          scheme.correct,
          Icons.check_circle_rounded,
          _feedbackText,
        ),
      _Feedback.wrong => (scheme.wrong, Icons.cancel_rounded, _feedbackText),
      _Feedback.finished => (
          scheme.secondary,
          Icons.flag_rounded,
          _feedbackText,
        ),
      _Feedback.thinking => (
          scheme.onSurfaceVariant,
          Icons.hourglass_top_rounded,
          _feedbackText,
        ),
      _Feedback.none => (
          scheme.onSurfaceVariant,
          Icons.emoji_objects_outlined,
          _goalText,
        ),
    };

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
          if (_busy)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }

  Widget _actions(ColorScheme scheme) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _action(
                Icons.lightbulb_outline_rounded,
                t('common.hint'),
                _hasAnswer ? () => setState(() => _showHint = true) : null,
              ),
              _action(
                Icons.visibility_outlined,
                t('puzzles.solution'),
                _hasAnswer && !_busy ? _revealSolution : null,
              ),
              _action(
                Icons.refresh_rounded,
                t('common.restart'),
                _moves.isEmpty ? null : _retry,
              ),
            ],
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: _index > 0 ? () => _goToPuzzle(_index - 1) : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                  label: Text(t('common.previous')),
                ),
              ),
              Container(width: 1, height: 24, color: scheme.outlineVariant),
              Expanded(
                child: TextButton.icon(
                  onPressed: _index < widget.puzzles.length - 1
                      ? () => _goToPuzzle(_index + 1)
                      : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                  iconAlignment: IconAlignment.end,
                  label: Text(t('common.next')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback? onPressed) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 19),
      label: Text(label, style: const TextStyle(fontSize: 13)),
    );
  }
}
