import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../widgets/filter_strip.dart';
import '../../widgets/responsive.dart';

import '../../l10n/app_strings.dart';
import '../../models/chess_engine.dart' as engine;
import '../../models/puzzle.dart';
import '../../models/puzzle_search.dart';
import '../../services/puzzle_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_dialogs.dart';
import '../../widgets/mini_board.dart';
import '../../widgets/range_dialog.dart';
import '../board_editor_screen.dart';
import 'puzzle_solve_screen.dart';
import '../../widgets/cursors.dart';
import '../../services/file_pick.dart';
import '../../services/text_file_service.dart';

import 'package:flutter/services.dart';

enum _Filter {
  all,
  unsolved,
  solved,
  favorites,
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

  /// Yalnızca bu numara aralığındaki bulmacalar listelenir; null ise hepsi.
  (int, int)? _range;

  /// Bugün (yerel gece yarısından beri) çözülen bulmaca sayısı.

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
        case _Filter.whiteWin:
          if (!puzzle.marksWhiteWin) return false;
          break;
        case _Filter.draw:
          if (!puzzle.marksDraw) return false;
          break;
        case _Filter.blackWin:
          if (!puzzle.marksBlackWin) return false;
          break;
        case _Filter.all:
          break;
      }
      final range = _range;
      if (range != null) {
        final number = _numbers[puzzle.id];
        if (number == null || number < range.$1 || number > range.$2) {
          return false;
        }
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

  /// Listede sonucu işaretlenmiş en az bir bulmaca var mı?
  ///
  /// Yoksa sonuç süzgeçleri hiçbir şey bulamaz; gösterilirlerse
  /// "süzgeç çalışmıyor" gibi görünür. Bir bulmacanın sonucu satır
  /// menüsünden işaretlenince ya da etiketli bir dosya alınınca
  /// süzgeçler kendiliğinden belirir.
  bool get _hasOutcomes => _all.any(
        (p) => p.marksWhiteWin || p.marksDraw || p.marksBlackWin,
      );

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
    // Ad penceresini iptal etmek bulmacayı iptal eder. Eskiden iptale
    // rağmen adsız bir bulmaca ekleniyordu.
    if (title == null || !mounted) return;
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
    final PickedText? picked;
    try {
      picked = await TextFileService.pick();
    } catch (error) {
      if (mounted) AppDialogs.snack(context, pickFailureMessage(error));
      return;
    }
    if (!mounted || picked == null) return;
    await _runImport(picked.content);
  }

  /// Metni listeye aktarır; uzun sürebileceği için ilerleme gösterir.
  Future<void> _runImport(String text) async {
    final int added;
    try {
      added = await AppDialogs.runWithProgress<int>(
        context,
        message: t('puzzles.importing'),
        task: (report) => _service.importFens(
          widget.collection,
          text,
          onProgress: (done, total) => report(total == 0 ? 0 : done / total),
        ),
      );
    } catch (_) {
      // Diske yazılamadıysa "eklendi" demek yanlış: veri yalnızca
      // bellekte kalıyor ve uygulama kapanınca gidiyor.
      if (mounted) AppDialogs.snack(context, t('lists.saveFailed'));
      return;
    }
    await _load();
    if (mounted) {
      AppDialogs.snack(context, t('puzzles.imported', {'count': added}));
    }
  }

  /// Numara aralığındaki bulmacaları toplu olarak işaretler.
  ///
  /// Numaralar süzgeçten bağımsızdır: kullanıcı ekranda gördüğü numarayı
  /// yazar, hangi süzgeç açık olursa olsun aynı bulmacalar işaretlenir.
  /// Listeyi bir numara aralığına daraltır.
  Future<void> _pickRange() async {
    if (_all.isEmpty) return;
    final numbers = _all.map((p) => _numbers[p.id] ?? 0).toList()..sort();

    final result = await showDialog<(int, int, bool)>(
      context: context,
      builder: (dialogContext) => RangeDialog(
        title: t('puzzles.showRange'),
        min: numbers.first,
        max: numbers.last,
        hint: t('puzzles.rangeHint', {
          'min': numbers.first,
          'max': numbers.last,
        }),
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _range = (result.$1, result.$2));
  }

  Future<void> _markRange() async {
    if (_all.isEmpty) return;
    final numbers = _all.map(_numberOf).toList()..sort();
    final result = await showDialog<(int, int, bool)>(
      context: context,
      builder: (dialogContext) => RangeDialog(
        title: t('puzzles.markRange'),
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
    // Not listeden zaten kalkıyor; ayrıca bildirim göstermiyoruz.
    await _load();
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

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.collection.name),
        actions: [
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
              if (value == 'showRange') _pickRange();
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
              PopupMenuItem(
                value: 'showRange',
                child: ListTile(
                  leading: const Icon(Icons.filter_list_rounded),
                  title: Text(t('puzzles.showRange')),
                ),
              ),
            ],
          ),
        ],
        // Arama kutusu ile süzgeç şeridinin genişliği birbirine bağlı:
        // geniş pencerede kutu şeritten biraz uzun duruyor. Oyun sonu
        // listelerindeki yedi süzgeç şeridi genişletiyor; kutu sabit
        // kalsaydı altındaki şeritten kısa görünürdü.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(104),
          child: ListToolbar(
            search: Padding(
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
            options: [
              FilterOption(
                label: t('puzzles.filterAll'),
                selected: _filter == _Filter.all,
                onTap: () => _selectFilter(_Filter.all),
              ),
              FilterOption(
                label: t('puzzles.filterUnsolved'),
                selected: _filter == _Filter.unsolved,
                onTap: () => _selectFilter(_Filter.unsolved),
              ),
              FilterOption(
                label: t('puzzles.filterSolved'),
                selected: _filter == _Filter.solved,
                onTap: () => _selectFilter(_Filter.solved),
              ),
              FilterOption(
                label: t('puzzles.filterFavorites'),
                selected: _filter == _Filter.favorites,
                onTap: () => _selectFilter(_Filter.favorites),
              ),
              // Sonuç süzgeçleri yalnızca oyun sonu listelerinde
              // anlamlı; başka listelerde yer kaplamasınlar.
              if (widget.collection.isEndgame && _hasOutcomes) ...[
                FilterOption(
                  label: t('puzzles.filterWhiteWin'),
                  selected: _filter == _Filter.whiteWin,
                  onTap: () => _selectFilter(_Filter.whiteWin),
                ),
                FilterOption(
                  label: t('puzzles.filterDraw'),
                  selected: _filter == _Filter.draw,
                  onTap: () => _selectFilter(_Filter.draw),
                ),
                FilterOption(
                  label: t('puzzles.filterBlackWin'),
                  selected: _filter == _Filter.blackWin,
                  onTap: () => _selectFilter(_Filter.blackWin),
                ),
              ],
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
          : Column(
              children: [
                if (_range != null) _rangeBanner(scheme),
                Expanded(
                  child: visible.isEmpty
                      ? _empty(scheme)
                      : ContentInset(
                          padding: EdgeInsets.fromLTRB(
                            12,
                            8,
                            12,
                            90 + MediaQuery.viewPaddingOf(context).bottom,
                          ),
                          builder: (context, padding) => ListView.builder(
                            key: const Key('puzzleList'),
                            padding: padding,
                            itemCount: visible.length,
                            itemBuilder: (context, index) =>
                                _puzzleTile(visible[index], scheme),
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  /// Aralık süzgeci açıkken görünen şerit.
  ///
  /// Olmasaydı kullanıcı kısalmış listeye bakıp sebebini anlamaz ve
  /// süzgeci kapatmanın yolunu bulamazdı.
  Widget _rangeBanner(ColorScheme scheme) {
    final range = _range!;
    return Container(
      width: double.infinity,
      color: scheme.secondaryContainer,
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              t('puzzles.rangeActive', {'from': range.$1, 'to': range.$2}),
              style: TextStyle(
                fontSize: 12.5,
                color: scheme.onSecondaryContainer,
              ),
            ),
          ),
          IconButton(
            tooltip: t('common.clearSelection'),
            icon: const Icon(Icons.close_rounded, size: 18),
            color: scheme.onSecondaryContainer,
            onPressed: () => setState(() => _range = null),
          ),
        ],
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
