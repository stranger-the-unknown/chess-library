import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../widgets/responsive.dart';

import '../../l10n/app_strings.dart';
import '../../models/chess_engine.dart' as engine;
import '../../models/puzzle.dart';
import '../../models/puzzle_search.dart';
import '../../services/puzzle_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_dialogs.dart';
import '../../widgets/mini_board.dart';
import '../board_editor_screen.dart';
import 'puzzle_solve_screen.dart';
import '../../widgets/cursors.dart';
import '../../services/text_file_service.dart';

import 'package:flutter/services.dart';

enum _Filter { all, unsolved, solved, favorites, mateInOne, enPassant, custom }

/// Bir listedeki bulmacaları gösterir; arama, süzme ve düzenleme sunar.
class PuzzleListScreen extends StatefulWidget {
  final PuzzleCollection collection;

  const PuzzleListScreen({super.key, required this.collection});

  @override
  State<PuzzleListScreen> createState() => _PuzzleListScreenState();
}

class _PuzzleListScreenState extends State<PuzzleListScreen> {
  final PuzzleService _service = PuzzleService.instance;
  final TextEditingController _searchController = TextEditingController();

  List<Puzzle> _all = [];

  /// Bulmaca kimliği -> tam listedeki sıra numarası (1'den başlar).
  final Map<String, int> _numbers = {};
  Map<String, PuzzleProgress> _progress = {};
  _Filter _filter = _Filter.all;
  String _query = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final puzzles = await _service.puzzlesOf(widget.collection);
    final progress = await _service.progressMap();
    if (!mounted) return;
    // Kaynağında numarası olan bulmacalar (mat problemleri) kitaptaki
    // numarayı korur; diğerleri listedeki sıraya göre numaralanır.
    _numbers.clear();
    for (int i = 0; i < puzzles.length; i++) {
      _numbers[puzzles[i].id] = puzzles[i].number ?? i + 1;
    }

    setState(() {
      _all = puzzles;
      _progress = progress;
      _loading = false;
    });
  }

  List<Puzzle> get _visible {
    final query = _query.trim().toLowerCase();
    return _all.where((puzzle) {
      final entry = _progress[puzzle.id];
      switch (_filter) {
        case _Filter.unsolved:
          if (entry?.solved == true) return false;
          break;
        case _Filter.solved:
          if (entry?.solved != true) return false;
          break;
        case _Filter.favorites:
          if (entry?.favorite != true) return false;
          break;
        case _Filter.mateInOne:
          if (!puzzle.tags.contains('mat-1')) return false;
          break;
        case _Filter.enPassant:
          if (!puzzle.tags.contains('gecerken-alma')) return false;
          break;
        case _Filter.custom:
          if (!puzzle.custom) return false;
          break;
        case _Filter.all:
          break;
      }
      if (query.isEmpty) return true;
      return puzzleMatches(puzzle, query, number: _numbers[puzzle.id]);
    }).toList();
  }

  // -------------------------------------------------------------------------
  // İşlemler
  // -------------------------------------------------------------------------

  Future<void> _open(Puzzle puzzle) async {
    final visible = _visible;
    final index = visible.indexWhere((p) => p.id == puzzle.id);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PuzzleSolveScreen(
          collection: widget.collection,
          puzzles: visible,
          initialIndex: index < 0 ? 0 : index,
        ),
      ),
    );
    await _load();
  }

  Future<void> _startNextUnsolved() async {
    final next = _visible.firstWhere(
      (p) => _progress[p.id]?.solved != true,
      orElse: () => _visible.isEmpty ? _all.first : _visible.first,
    );
    if (_all.isEmpty) return;
    await _open(next);
  }

  Future<void> _startRandom() async {
    final visible = _visible;
    if (visible.isEmpty) return;
    await _open(visible[math.Random().nextInt(visible.length)]);
  }

  Future<void> _addPuzzle() async {
    final fen = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => BoardEditorScreen(
          initialFen: engine.ChessGame().fen,
          title: t('puzzles.newPuzzle'),
        ),
      ),
    );
    if (fen == null || !mounted) return;

    final title = await AppDialogs.prompt(
      context,
      title: t('puzzles.puzzleName'),
      label: t('puzzles.nameOptional'),
      initialValue: t('puzzles.defaultName', {'n': _all.length + 1}),
    );
    await _service.addPuzzle(widget.collection, fen: fen, title: title);
    await _load();
  }

  Future<void> _editPuzzle(Puzzle puzzle) async {
    final fen = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => BoardEditorScreen(
          initialFen: puzzle.fen,
          title: t('puzzles.editPuzzle'),
        ),
      ),
    );
    if (fen == null || !mounted) return;
    await _service.updatePuzzle(
      widget.collection,
      puzzle,
      fen: fen,
      title: puzzle.title,
      note: puzzle.note,
      tags: puzzle.tags,
    );
    await _load();
  }

  Future<void> _renamePuzzle(Puzzle puzzle) async {
    final title = await AppDialogs.prompt(
      context,
      title: t('puzzles.puzzleName'),
      label: t('lists.name'),
      initialValue: puzzle.title ?? '',
    );
    if (title == null || !mounted) return;
    await _service.updatePuzzle(
      widget.collection,
      puzzle,
      fen: puzzle.fen,
      title: title,
      note: puzzle.note,
      tags: puzzle.tags,
    );
    await _load();
  }

  Future<void> _deletePuzzle(Puzzle puzzle) async {
    final confirmed = await AppDialogs.confirm(
      context,
      title: t('puzzles.deletePuzzle'),
      message: t('puzzles.deletePuzzleMessage'),
      confirmLabel: t('common.delete'),
      destructive: true,
    );
    if (!confirmed) return;
    await _service.deletePuzzle(widget.collection, puzzle);
    await _load();
  }

  Future<void> _importFens() async {
    final text = await AppDialogs.prompt(
      context,
      title: t('puzzles.importFens'),
      label: t('puzzles.oneFenPerLine'),
      maxLines: 8,
      confirmLabel: t('common.add'),
    );
    if (text == null || !mounted) return;
    await _runImport(text);
  }

  Future<void> _importFromFile() async {
    final picked = await TextFileService.pick();
    if (picked == null) {
      if (mounted) AppDialogs.snack(context, t('puzzles.fileEmpty'));
      return;
    }
    if (!mounted) return;
    await _runImport(picked.content);
  }

  /// Metni listeye aktarır; uzun sürebileceği için ilerleme gösterir.
  Future<void> _runImport(String text) async {
    final added = await AppDialogs.runWithProgress<int>(
      context,
      message: t('puzzles.importing'),
      task: (report) => _service.importFens(
        widget.collection,
        text,
        onProgress: (done, total) => report(total == 0 ? 0 : done / total),
      ),
    );
    await _load();
    if (mounted) {
      AppDialogs.snack(context, t('puzzles.imported', {'count': added}));
    }
  }

  Future<void> _exportPuzzles() async {
    if (_all.isEmpty) {
      AppDialogs.snack(context, t('puzzles.exportEmpty'));
      return;
    }
    final text = await _service.exportText(widget.collection);
    if (!mounted) return;

    String? path;
    try {
      path = await TextFileService.save(widget.collection.name, text);
    } catch (_) {
      path = null;
    }
    if (!mounted) return;

    if (path == null) {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) AppDialogs.snack(context, t('puzzles.exportFallback'));
      return;
    }
    AppDialogs.snack(context, t('puzzles.exported', {'count': _all.length}));
  }

  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visible = _visible;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.collection.name),
        actions: [
          IconButton(
            tooltip: t('puzzles.random'),
            icon: const Icon(Icons.casino_outlined),
            onPressed: visible.isEmpty ? null : _startRandom,
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'add') _addPuzzle();
              if (value == 'import') _importFens();
              if (value == 'importFile') _importFromFile();
              if (value == 'export') _exportPuzzles();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'add',
                child: ListTile(
                  leading: const Icon(Icons.add_rounded),
                  title: Text(t('puzzles.addPuzzle')),
                ),
              ),
              PopupMenuItem(
                value: 'import',
                child: ListTile(
                  leading: const Icon(Icons.playlist_add_rounded),
                  title: Text(t('puzzles.pasteFenList')),
                ),
              ),
              PopupMenuItem(
                value: 'importFile',
                child: ListTile(
                  leading: const Icon(Icons.file_open_outlined),
                  title: Text(t('puzzles.importFile')),
                ),
              ),
              PopupMenuItem(
                value: 'export',
                child: ListTile(
                  leading: const Icon(Icons.ios_share_rounded),
                  title: Text(t('puzzles.exportFile')),
                ),
              ),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(104),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    hintText: t('puzzles.search'),
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    isDense: true,
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                          ),
                  ),
                ),
              ),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    _filterChip(t('puzzles.filterAll'), _Filter.all),
                    _filterChip(t('puzzles.filterUnsolved'), _Filter.unsolved),
                    _filterChip(t('puzzles.filterSolved'), _Filter.solved),
                    _filterChip(
                      t('puzzles.filterFavorites'),
                      _Filter.favorites,
                    ),
                    _filterChip(t('puzzles.filterMate'), _Filter.mateInOne),
                    _filterChip(
                      t('puzzles.filterEnPassant'),
                      _Filter.enPassant,
                    ),
                    _filterChip(t('puzzles.filterCustom'), _Filter.custom),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: visible.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _startNextUnsolved,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(t('puzzles.continue')),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : visible.isEmpty
              ? _empty(scheme)
              : ContentWidth(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
                    itemCount: visible.length,
                    itemBuilder: (context, index) =>
                        _puzzleTile(visible[index], index, scheme),
                  ),
                ),
    );
  }

  Widget _filterChip(String label, _Filter value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ChoiceChip(
        mouseCursor: kClickable,
        label: Text(label),
        selected: _filter == value,
        onSelected: (_) => setState(() => _filter = value),
      ),
    );
  }

  Widget _empty(ColorScheme scheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 46,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 14),
            Text(
              _all.isEmpty
                  ? t('puzzles.emptyCollection')
                  : t('puzzles.emptyFilter'),
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: _addPuzzle,
              icon: const Icon(Icons.add_rounded),
              label: Text(t('puzzles.addPuzzle')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _puzzleTile(Puzzle puzzle, int index, ColorScheme scheme) {
    final progress = _progress[puzzle.id];
    final solved = progress?.solved == true;
    final favorite = progress?.favorite == true;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          mouseCursor: kClickable,
          borderRadius: BorderRadius.circular(14),
          onTap: () => _open(puzzle),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                MiniBoard(
                  fen: puzzle.fen,
                  size: 64,
                  flipped: puzzle.sideToMove == engine.Color.black,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              puzzle.title ??
                                  '#${_numbers[puzzle.id] ?? index + 1}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14.5,
                              ),
                            ),
                          ),
                          if (favorite)
                            Icon(
                              Icons.star_rounded,
                              size: 16,
                              color: scheme.warning,
                            ),
                          if (solved)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Icon(
                                Icons.check_circle_rounded,
                                size: 16,
                                color: scheme.success,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        puzzle.sideToMoveLabel,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if (puzzle.tags.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: puzzle.tagLabels
                              .take(3)
                              .map(
                                (tag) => Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: scheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    tag,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: scheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, size: 20),
                  onSelected: (value) async {
                    switch (value) {
                      case 'edit':
                        _editPuzzle(puzzle);
                        break;
                      case 'rename':
                        _renamePuzzle(puzzle);
                        break;
                      case 'favorite':
                        await _service.toggleFavorite(puzzle.id);
                        await _load();
                        break;
                      case 'solved':
                        await _service.markSolved(
                          puzzle.id,
                          solved: !(progress?.solved ?? false),
                        );
                        await _load();
                        break;
                      case 'delete':
                        _deletePuzzle(puzzle);
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Text(t('common.editPosition')),
                    ),
                    PopupMenuItem(
                      value: 'rename',
                      child: Text(t('common.rename')),
                    ),
                    PopupMenuItem(
                      value: 'favorite',
                      child: Text(
                        favorite
                            ? t('common.favoriteRemove')
                            : t('common.favoriteAdd'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'solved',
                      child: Text(
                        solved
                            ? t('puzzles.markUnsolved')
                            : t('puzzles.markSolved'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(t('common.delete')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
