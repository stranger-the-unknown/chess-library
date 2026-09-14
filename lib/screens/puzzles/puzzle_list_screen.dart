import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../widgets/responsive.dart';

import '../../l10n/app_strings.dart';
import '../../models/chess_engine.dart' as engine;
import '../../models/puzzle.dart';
import '../../models/puzzle_search.dart';
import '../../services/puzzle_service.dart';
import '../../services/settings_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_dialogs.dart';
import '../../widgets/mini_board.dart';
import '../../widgets/range_dialog.dart';
import '../board_editor_screen.dart';
import 'puzzle_solve_screen.dart';
import '../../widgets/cursors.dart';
import '../../services/text_file_service.dart';

import 'package:flutter/services.dart';

enum _Filter {
  all,
  unsolved,
  solved,
  favorites,
  custom,
  whiteWin,
  draw,
  blackWin,
}

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

  /// Liste sondan başa mı sıralansın?
  ///
  /// Varsayılan hayır: bulmaca kitapları baştan sona çözülür, liste de
  /// kitaptaki sırayla açılır. Başlıktaki okla ters çevrilebilir.
  /// Numaralar sıralamadan etkilenmez; onlar her zaman listedeki asıl
  /// sırayı gösterir.
  bool _descending = false;

  /// Bugün (yerel gece yarısından beri) çözülen bulmaca sayısı.
  int _solvedToday = 0;

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

    final today = DateTime.now();
    int todayCount = 0;
    for (final puzzle in puzzles) {
      if (progress[puzzle.id]?.solvedOn(today) == true) todayCount++;
    }

    setState(() {
      _all = puzzles;
      _progress = progress;
      _solvedToday = todayCount;
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
        case _Filter.whiteWin:
          if (!puzzle.marksWhiteWin) return false;
          break;
        case _Filter.draw:
          if (!puzzle.marksDraw) return false;
          break;
        case _Filter.blackWin:
          if (!puzzle.marksBlackWin) return false;
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

  /// Ekranda görünen sıra.
  ///
  /// Süzme her zaman asıl sıra üzerinde yapılır, ters çevirme en sonda
  /// uygulanır; böylece süzgeç açıkken de sıralama aynı yönde kalır.
  List<Puzzle> get _ordered {
    final list = _visible;
    return _descending ? list.reversed.toList() : list;
  }

  /// Bir bulmacanın süzgeçten bağımsız, listedeki asıl numarası.
  int _numberOf(Puzzle puzzle) => _numbers[puzzle.id] ?? 0;

  // -------------------------------------------------------------------------
  // İşlemler
  // -------------------------------------------------------------------------

  Future<void> _open(Puzzle puzzle) async {
    final visible = _ordered;
    final index = visible.indexWhere((p) => p.id == puzzle.id);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PuzzleSolveScreen(
          collection: widget.collection,
          puzzles: visible,
          initialIndex: index < 0 ? 0 : index,
          // Başlık ve bilgi satırı süzgeçten bağımsız numarayı gösterir.
          numbers: Map<String, int>.from(_numbers),
          totalInCollection: _all.length,
        ),
      ),
    );
    await _load();
  }

  Future<void> _startNextUnsolved() async {
    if (_all.isEmpty) return;
    final ordered = _ordered;
    if (ordered.isEmpty) return;
    final next = ordered.firstWhere(
      (p) => _progress[p.id]?.solved != true,
      orElse: () => ordered.first,
    );
    await _open(next);
  }

  Future<void> _startRandom() async {
    final visible = _ordered;
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

  /// Numara aralığındaki bulmacaları toplu olarak işaretler.
  ///
  /// Numaralar süzgeçten bağımsızdır: kullanıcı ekranda gördüğü numarayı
  /// yazar, hangi süzgeç açık olursa olsun aynı bulmacalar işaretlenir.
  Future<void> _markRange() async {
    if (_all.isEmpty) return;
    final numbers = _all.map(_numberOf).toList()..sort();
    final result = await showDialog<(int, int, bool)>(
      context: context,
      builder: (dialogContext) => RangeDialog(
        min: numbers.first,
        max: numbers.last,
        hint: t('puzzles.rangeHint', {
          'min': numbers.first,
          'max': numbers.last,
        }),
        markLabel: t('puzzles.markSolved'),
        unmarkLabel: t('puzzles.markUnsolved'),
      ),
    );
    if (result == null || !mounted) return;

    final (from, to, solved) = result;
    final ids = _all
        .where((p) => _numberOf(p) >= from && _numberOf(p) <= to)
        .map((p) => p.id)
        .toList();
    final changed = await _service.markManySolved(ids, solved: solved);
    await _load();
    if (!mounted) return;
    AppDialogs.snack(
      context,
      changed == 0
          ? t('puzzles.rangeNone')
          : t('puzzles.rangeMarked', {'count': changed}),
    );
  }

  /// Oyun sonu listelerinde bir bulmacanın sonucunu işaretler.
  Future<void> _setOutcome(Puzzle puzzle, String? tag) async {
    const outcomes = {'beyaz-kazanir', 'white-wins', 'beraberlik', 'draw',
        'siyah-kazanir', 'black-wins'};
    final tags = puzzle.tags.where((t) => !outcomes.contains(t)).toList();
    if (tag != null) tags.add(tag);
    await _service.updatePuzzle(
      widget.collection,
      puzzle,
      fen: puzzle.fen,
      title: puzzle.title,
      note: puzzle.note,
      tags: tags,
    );
    await _load();
  }

  /// Bulmacanın notunu siler.
  Future<void> _deleteNote(Puzzle puzzle) async {
    await _service.updatePuzzle(
      widget.collection,
      puzzle,
      fen: puzzle.fen,
      title: puzzle.title,
      note: null,
      tags: puzzle.tags,
    );
    await _load();
    if (mounted) AppDialogs.snack(context, t('common.noteDeleted'));
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
    final visible = _ordered;
    final showToday =
        SettingsService.instance.showDailyCount && _solvedToday > 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.collection.name),
        actions: [
          if (showToday)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
              child: Chip(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                label: Text(
                  t('puzzles.todaySolved', {'count': _solvedToday}),
                  style: const TextStyle(fontSize: 11.5),
                ),
              ),
            ),
          IconButton(
            tooltip:
                _descending ? t('puzzles.sortOldest') : t('puzzles.sortNewest'),
            icon: Icon(
              _descending
                  ? Icons.arrow_downward_rounded
                  : Icons.arrow_upward_rounded,
            ),
            onPressed: () => setState(() => _descending = !_descending),
          ),
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
              if (value == 'range') _markRange();
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
              PopupMenuItem(
                value: 'range',
                child: ListTile(
                  leading: const Icon(Icons.done_all_rounded),
                  title: Text(t('puzzles.markRange')),
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
                    _filterChip(t('puzzles.filterCustom'), _Filter.custom),
                    // Sonuç süzgeçleri yalnızca oyun sonu listelerinde
                    // anlamlı; başka listelerde yer kaplamasınlar.
                    if (widget.collection.isEndgame) ...[
                      _filterChip(
                        t('puzzles.filterWhiteWin'),
                        _Filter.whiteWin,
                      ),
                      _filterChip(t('puzzles.filterDraw'), _Filter.draw),
                      _filterChip(
                        t('puzzles.filterBlackWin'),
                        _Filter.blackWin,
                      ),
                    ],
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
                        _puzzleTile(visible[index], scheme),
                  ),
                ),
    );
  }

  /// Süzgeci değiştirir ve sıralamayı varsayılana döndürür.
  ///
  /// Ters sıralama çoğunlukla bir soruya bakmak için bir kerelik
  /// açılıyor (ör. en son çözüleni görmek). Süzgeç değişince o niyet
  /// bitmiş oluyor; sıralama açık kalırsa kullanıcının her seferinde
  /// oku yeniden tıklaması gerekiyordu.
  void _selectFilter(_Filter value) {
    if (_filter == value) return;
    setState(() {
      _filter = value;
      _descending = false;
    });
  }

  Widget _filterChip(String label, _Filter value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ChoiceChip(
        mouseCursor: kClickable,
        label: Text(label),
        selected: _filter == value,
        onSelected: (_) => _selectFilter(value),
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

  Widget _puzzleTile(Puzzle puzzle, ColorScheme scheme) {
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
                              puzzle.title ?? '#${_numberOf(puzzle)}',
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
                      case 'deleteNote':
                        await _deleteNote(puzzle);
                        break;
                      case 'outWhite':
                        await _setOutcome(puzzle, 'beyaz-kazanir');
                        break;
                      case 'outDraw':
                        await _setOutcome(puzzle, 'beraberlik');
                        break;
                      case 'outBlack':
                        await _setOutcome(puzzle, 'siyah-kazanir');
                        break;
                      case 'outNone':
                        await _setOutcome(puzzle, null);
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
                    if (puzzle.note != null && puzzle.note!.isNotEmpty)
                      PopupMenuItem(
                        value: 'deleteNote',
                        child: Text(t('common.deleteNote')),
                      ),
                    if (widget.collection.isEndgame) ...[
                      const PopupMenuDivider(),
                      CheckedPopupMenuItem(
                        value: 'outWhite',
                        checked: puzzle.marksWhiteWin,
                        child: Text(t('puzzles.filterWhiteWin')),
                      ),
                      CheckedPopupMenuItem(
                        value: 'outDraw',
                        checked: puzzle.marksDraw,
                        child: Text(t('puzzles.filterDraw')),
                      ),
                      CheckedPopupMenuItem(
                        value: 'outBlack',
                        checked: puzzle.marksBlackWin,
                        child: Text(t('puzzles.filterBlackWin')),
                      ),
                      PopupMenuItem(
                        value: 'outNone',
                        child: Text(t('puzzles.outcomeNone')),
                      ),
                      const PopupMenuDivider(),
                    ],
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
