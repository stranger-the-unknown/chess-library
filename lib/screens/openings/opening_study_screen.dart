import 'dart:async';

import 'package:flutter/material.dart';

import '../../widgets/responsive.dart';

import '../../l10n/app_strings.dart';
import '../../models/chess_engine.dart' as engine;
import '../../models/opening.dart';
import '../../services/opening_service.dart';
import '../../services/sound_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_dialogs.dart';
import '../../widgets/chess_board_widget.dart';
import '../game_screen.dart';

enum StudyMode {
  /// Varyantı adım adım izle.
  watch,

  /// Hamleleri sen oyna; yanlışta uyarı al.
  practice,
}

/// Tek bir açılış varyantını çalışma ekranı.
class OpeningStudyScreen extends StatefulWidget {
  final Opening opening;

  const OpeningStudyScreen({super.key, required this.opening});

  @override
  State<OpeningStudyScreen> createState() => _OpeningStudyScreenState();
}

class _OpeningStudyScreenState extends State<OpeningStudyScreen> {
  final OpeningService _service = OpeningService.instance;

  late engine.ChessGame _game;
  int _cursor = -1;
  StudyMode _mode = StudyMode.watch;
  bool _flipped = false;
  bool _autoPlaying = false;
  bool _showHint = false;
  bool _mistakeMade = false;
  String? _message;
  bool _messageIsError = false;
  bool _favorite = false;
  bool _learned = false;
  Timer? _autoTimer;

  @override
  void initState() {
    super.initState();
    _game = engine.ChessGame();
    _loadProgress();
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadProgress() async {
    final progress = await _service.progressOf(widget.opening.id);
    if (!mounted) return;
    setState(() {
      _favorite = progress.favorite;
      _learned = progress.learned;
    });
  }

  // -------------------------------------------------------------------------
  // Konum yönetimi
  // -------------------------------------------------------------------------

  engine.ChessGame _positionAt(int index) {
    final position = engine.ChessGame();
    for (int i = 0; i <= index && i < widget.opening.uciMoves.length; i++) {
      final move = position.moveFromUci(widget.opening.uciMoves[i]);
      if (move == null) break;
      position.makeMove(move);
    }
    return position;
  }

  engine.ChessMove? get _currentMove {
    if (_cursor < 0 || _cursor >= widget.opening.uciMoves.length) return null;
    return _positionAt(_cursor - 1)
        .moveFromUci(widget.opening.uciMoves[_cursor]);
  }

  /// Sıradaki (henüz oynanmamış) hamle.
  engine.ChessMove? get _nextMove {
    final index = _cursor + 1;
    if (index >= widget.opening.uciMoves.length) return null;
    return _game.moveFromUci(widget.opening.uciMoves[index]);
  }

  void _goTo(int index, {bool silent = false}) {
    final clamped = index.clamp(-1, widget.opening.uciMoves.length - 1);
    final forward = clamped > _cursor;
    setState(() {
      _cursor = clamped;
      _game = _positionAt(clamped);
      _showHint = false;
    });
    if (forward && clamped >= 0 && !silent) {
      SoundService.instance.playForSan(
        widget.opening.sanMoves[clamped],
        opponent: clamped.isOdd,
      );
    }
  }

  void _reset() {
    _autoTimer?.cancel();
    setState(() {
      _autoPlaying = false;
      _mistakeMade = false;
      _message = null;
    });
    _goTo(-1, silent: true);
  }

  void _toggleAutoPlay() {
    if (_autoPlaying) {
      _autoTimer?.cancel();
      setState(() => _autoPlaying = false);
      return;
    }
    setState(() => _autoPlaying = true);
    _autoTimer = Timer.periodic(const Duration(milliseconds: 900), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_cursor >= widget.opening.uciMoves.length - 1) {
        timer.cancel();
        setState(() => _autoPlaying = false);
        return;
      }
      _goTo(_cursor + 1);
    });
  }

  // -------------------------------------------------------------------------
  // Alıştırma
  // -------------------------------------------------------------------------

  Future<void> _onUserMove(engine.ChessMove move) async {
    if (_mode != StudyMode.practice) return;
    final expectedIndex = _cursor + 1;
    if (expectedIndex >= widget.opening.uciMoves.length) return;

    final expected = widget.opening.uciMoves[expectedIndex];
    if (move.uci != expected) {
      SoundService.instance.playWrong();
      setState(() {
        _mistakeMade = true;
        _messageIsError = true;
        _message = t('openings.wrongMove');
      });
      await _service.registerFailure(widget.opening.id);
      return;
    }

    _goTo(expectedIndex);
    setState(() {
      _messageIsError = false;
      _message = t('openings.rightMove', {
        'move': widget.opening.sanMoves[expectedIndex],
      });
    });

    // Rakip hamlesini otomatik oynat ki kullanıcı hep aynı tarafı çalışsın.
    if (_cursor < widget.opening.uciMoves.length - 1) {
      await Future<void>.delayed(const Duration(milliseconds: 380));
      if (!mounted || _mode != StudyMode.practice) return;
      _goTo(_cursor + 1);
    }

    if (_cursor >= widget.opening.uciMoves.length - 1) {
      SoundService.instance.playNotify();
      if (!_mistakeMade) {
        await _service.registerSuccess(widget.opening.id);
      }
      final progress = await _service.progressOf(widget.opening.id);
      if (!mounted) return;
      setState(() {
        _learned = progress.learned;
        _messageIsError = false;
        _message = _mistakeMade
            ? t('openings.finishedWithMistake')
            : t('openings.finishedClean');
      });
    }
  }

  void _setMode(StudyMode mode) {
    _autoTimer?.cancel();
    setState(() {
      _mode = mode;
      _autoPlaying = false;
      _message = null;
      _mistakeMade = false;
    });
    _goTo(-1, silent: true);

    // Alıştırmada siyahı çalışıyorsan ilk hamleyi tahta oynasın.
    if (mode == StudyMode.practice && _flipped) {
      Future<void>.delayed(const Duration(milliseconds: 350), () {
        if (mounted && _cursor == -1) _goTo(0);
      });
    }
  }

  // -------------------------------------------------------------------------

  /// Varyantın notunu siler.
  ///
  /// Servis boş metni "not yok" olarak ele alır; ayrı bir silme yolu
  /// tutmaya gerek yok.
  Future<void> _deleteNote(Opening opening) async {
    await _service.setNote(opening.id, '');
    if (!mounted) return;
    setState(() => opening.note = null);
    AppDialogs.snack(context, t('common.noteDeleted'));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final opening = widget.opening;

    final arrows = <BoardArrow>[];
    if (_showHint) {
      final next = _nextMove;
      if (next != null) {
        arrows.add(
          BoardArrow(next.from, next.to, scheme.primary.withValues(alpha: 0.8)),
        );
      }
    }

    // Alıştırmada kullanıcı yalnızca sırası gelen tarafı oynar.
    final practiceSide = _flipped ? engine.Color.black : engine.Color.white;

    return Scaffold(
      appBar: AppBar(
        title: Text(opening.variation),
        actions: [
          IconButton(
            tooltip: _favorite
                ? t('common.favoriteRemove')
                : t('common.favoriteAdd'),
            icon: Icon(
              _favorite ? Icons.star_rounded : Icons.star_border_rounded,
              color: _favorite ? scheme.warning : null,
            ),
            onPressed: () async {
              final value = await _service.toggleFavorite(opening.id);
              if (mounted) setState(() => _favorite = value);
            },
          ),
          IconButton(
            tooltip: t('common.flipBoard'),
            icon: const Icon(Icons.swap_vert_rounded),
            onPressed: () => setState(() => _flipped = !_flipped),
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              switch (value) {
                case 'note':
                  final note = await AppDialogs.prompt(
                    context,
                    title: t('common.note'),
                    label: t('openings.noteLabel'),
                    initialValue: opening.note ?? '',
                    maxLines: 4,
                  );
                  if (note == null) return;
                  await _service.setNote(opening.id, note);
                  if (mounted) setState(() => opening.note = note);
                  break;
                case 'deleteNote':
                  await _deleteNote(opening);
                  break;
                case 'learned':
                  await _service.markLearned(opening.id, learned: !_learned);
                  if (mounted) setState(() => _learned = !_learned);
                  break;
                case 'play':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GameScreen(
                        mode: GameMode.versusEngine,
                        startFen: _game.fen,
                        playerColor: _game.sideToMove,
                        title: t('openings.continueVsEngine'),
                      ),
                    ),
                  );
                  break;
                case 'analyze':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GameScreen(
                        startFen: _game.fen,
                        title: opening.variation,
                      ),
                    ),
                  );
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'note', child: Text(t('common.addNote'))),
              if (opening.note != null && opening.note!.isNotEmpty)
                PopupMenuItem(
                  value: 'deleteNote',
                  child: Text(t('common.deleteNote')),
                ),
              PopupMenuItem(
                value: 'learned',
                child: Text(
                  _learned
                      ? t('openings.markNotLearned')
                      : t('openings.markLearned'),
                ),
              ),
              PopupMenuItem(
                value: 'play',
                child: Text(t('common.playFromHere')),
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
                        return SizedBox(
                          width: side,
                          height: side,
                          child: ChessBoardWidget(
                            game: _game,
                            flipped: _flipped,
                            interactive: _mode == StudyMode.practice,
                            movableSide: practiceSide,
                            lastMove: _currentMove,
                            onMove: _onUserMove,
                            arrows: arrows,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              if (opening.note != null && opening.note!.isNotEmpty)
                _noteCard(scheme, opening.note!),
              if (_message != null) _messageCard(scheme),
              _moveStrip(scheme),
              _controls(scheme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              widget.opening.eco,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.opening.family,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          if (_learned)
            Icon(Icons.check_circle_rounded, size: 16, color: scheme.success),
        ],
      ),
    );
  }

  Widget _noteCard(ColorScheme scheme, String note) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        note,
        style: TextStyle(fontSize: 12.5, color: scheme.onSecondaryContainer),
      ),
    );
  }

  Widget _messageCard(ColorScheme scheme) {
    final color = _messageIsError ? scheme.wrong : scheme.correct;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            _messageIsError
                ? Icons.error_outline_rounded
                : Icons.check_circle_outline_rounded,
            size: 17,
            color: color,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              _message!,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _moveStrip(ColorScheme scheme) {
    final moves = widget.opening.sanMoves;
    // Alıştırmada henüz gelmemiş hamleler gizlenir.
    final revealed = _mode == StudyMode.practice ? _cursor + 1 : moves.length;

    return Container(
      height: 46,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: (moves.length / 2).ceil(),
        itemBuilder: (context, index) {
          final first = index * 2;
          Widget chip(int i) {
            final hidden = i >= revealed;
            final isCurrent = i == _cursor;
            return MouseRegion(
              cursor: _mode == StudyMode.watch
                  ? SystemMouseCursors.click
                  : MouseCursor.defer,
              child: GestureDetector(
                onTap: _mode == StudyMode.watch ? () => _goTo(i) : null,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: isCurrent ? scheme.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    hidden ? '···' : moves[i],
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                      color: isCurrent
                          ? scheme.onPrimary
                          : (hidden
                              ? scheme.onSurfaceVariant.withValues(alpha: 0.5)
                              : scheme.onSurface),
                    ),
                  ),
                ),
              ),
            );
          }

          return Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, right: 3),
                child: Text(
                  '${index + 1}.',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              chip(first),
              if (first + 1 < moves.length) chip(first + 1),
            ],
          );
        },
      ),
    );
  }

  Widget _controls(ColorScheme scheme) {
    final atEnd = _cursor >= widget.opening.uciMoves.length - 1;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SegmentedButton<StudyMode>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: StudyMode.watch,
                  label: Text(t('openings.watch')),
                  icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
                ),
                ButtonSegment(
                  value: StudyMode.practice,
                  label: Text(t('openings.practice')),
                  icon: const Icon(Icons.school_outlined, size: 18),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (selection) => _setMode(selection.first),
            ),
          ),
          const SizedBox(height: 4),
          if (_mode == StudyMode.watch)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: const Icon(Icons.first_page_rounded),
                  onPressed: _cursor >= 0 ? () => _goTo(-1) : null,
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded),
                  iconSize: 28,
                  onPressed: _cursor >= 0 ? () => _goTo(_cursor - 1) : null,
                ),
                IconButton(
                  icon: Icon(
                    _autoPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                  iconSize: 30,
                  onPressed: atEnd ? null : _toggleAutoPlay,
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded),
                  iconSize: 28,
                  onPressed: atEnd ? null : () => _goTo(_cursor + 1),
                ),
                IconButton(
                  icon: const Icon(Icons.last_page_rounded),
                  onPressed: atEnd
                      ? null
                      : () => _goTo(widget.opening.uciMoves.length - 1),
                ),
              ],
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton.icon(
                  onPressed:
                      atEnd ? null : () => setState(() => _showHint = true),
                  icon: const Icon(Icons.lightbulb_outline_rounded, size: 19),
                  label: Text(t('common.hint')),
                ),
                TextButton.icon(
                  onPressed: _reset,
                  icon: const Icon(Icons.refresh_rounded, size: 19),
                  label: Text(t('common.restart')),
                ),
                TextButton.icon(
                  onPressed: atEnd ? null : () => _goTo(_cursor + 1),
                  icon: const Icon(Icons.skip_next_rounded, size: 19),
                  label: Text(t('openings.show')),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
