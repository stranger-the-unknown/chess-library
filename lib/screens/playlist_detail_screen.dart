import 'package:flutter/material.dart';

import '../widgets/responsive.dart';

import 'package:flutter/services.dart';

import '../l10n/app_strings.dart';
import '../models/pgn_parser.dart';
import '../models/playlist.dart';
import '../models/puzzle_search.dart';
import '../services/pgn_import_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/range_dialog.dart';
import 'game_screen.dart';
import '../widgets/cursors.dart';

/// Liste içindeki oyun süzgeci.
enum _GameFilter { all, unread, read, favorites }

/// Bir listedeki kayıtlı oyunlar.
class PlaylistDetailScreen extends StatefulWidget {
  final String playlistId;

  const PlaylistDetailScreen({super.key, required this.playlistId});

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  final StorageService _storage = StorageService.instance;
  final TextEditingController _searchController = TextEditingController();

  Playlist? _playlist;
  bool _loading = true;
  String _query = '';
  _GameFilter _filter = _GameFilter.all;

  /// Oyun kimliği -> listedeki sıra numarası (1'den başlar). Süzgeç
  /// uygulansa da numara değişmez, böylece "#42" ile aranabilir.
  final Map<String, int> _numbers = {};

  @override
  void initState() {
    super.initState();
    // Başka ekranlardaki değişiklikler de yansısın.
    _storage.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    _storage.removeListener(_load);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final playlists = await _storage.loadPlaylists();
    if (!mounted) return;

    final matches = playlists.where((p) => p.id == widget.playlistId).toList();
    final playlist = matches.isEmpty ? null : matches.first;

    _numbers.clear();
    if (playlist != null) {
      for (int i = 0; i < playlist.games.length; i++) {
        _numbers[playlist.games[i].id] = i + 1;
      }
    }

    setState(() {
      _playlist = playlist;
      _loading = false;
    });
  }

  Future<void> _openGame(SavedGame game) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GameScreen(
          uciMoves: game.uciMoves,
          startFen: game.startFen,
          title: game.name,
          initialResult: game.result,
        ),
      ),
    );
    await _load();
  }

  Future<void> _rename(SavedGame game) async {
    final name = await AppDialogs.prompt(
      context,
      title: t('lists.renameGame'),
      label: t('lists.name'),
      initialValue: game.name,
    );
    if (name == null) return;
    game.name = name;
    await _storage.updateGame(widget.playlistId, game);
    await _load();
  }

  Future<void> _delete(SavedGame game) async {
    final confirmed = await AppDialogs.confirm(
      context,
      title: t('lists.deleteGame'),
      message: t('lists.deleteGameMessage', {'name': game.name}),
      confirmLabel: t('common.delete'),
      destructive: true,
    );
    if (!confirmed) return;
    await _storage.deleteGame(widget.playlistId, game.id);
    await _load();
  }

  Future<void> _copyPgn(SavedGame game) async {
    final pgn = PgnParser.buildPgn(
      uciMoves: game.uciMoves,
      startFen: game.startFen,
      result: game.result,
      tags: {'Event': game.name},
    );
    await Clipboard.setData(ClipboardData(text: pgn));
    if (mounted) AppDialogs.snack(context, t('lists.pgnCopied'));
  }

  Future<void> _move(SavedGame game) async {
    final playlists = await _storage.loadPlaylists();
    if (!mounted) return;
    final targets = playlists.where((p) => p.id != widget.playlistId).toList();
    if (targets.isEmpty) {
      AppDialogs.snack(context, t('lists.noOtherList'));
      return;
    }

    final target = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(t('lists.moveWhere')),
        children: targets
            .map(
              (p) => SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext, p.id),
                child: Text(p.name),
              ),
            )
            .toList(),
      ),
    );
    if (target == null) return;
    await _storage.moveGame(widget.playlistId, target, game.id);
    await _load();
  }

  /// Bir PGN dosyasındaki tüm oyunları bu listeye ekler.
  Future<void> _importPgnFile() async {
    PickedPgn? picked;
    try {
      picked = await PgnImportService.pickFile();
    } catch (_) {
      picked = null;
    }
    if (!mounted) return;
    if (picked == null) {
      AppDialogs.snack(context, t('pgn.readError'));
      return;
    }

    final content = picked.content;
    final games = await AppDialogs.runWithProgress<List<PgnGame>>(
      context,
      message: t('pgn.reading'),
      task: (report) => PgnParser.parseAllAsync(
        content,
        onProgress: (done, total) => report(total == 0 ? 0 : done / total),
      ),
    );
    if (!mounted) return;
    if (games.isEmpty) {
      AppDialogs.snack(context, t('pgn.noGames'));
      return;
    }

    final added = await PgnImportService.addToList(widget.playlistId, games);
    await _load();
    if (mounted) {
      AppDialogs.snack(context, t('pgn.saved', {'count': added}));
    }
  }

  /// Listeyi PGN dosyası olarak kaydeder; kaydedilemezse panoya kopyalar.
  Future<void> _exportPgn(Playlist playlist) async {
    if (playlist.games.isEmpty) {
      AppDialogs.snack(context, t('lists.exportEmpty'));
      return;
    }

    String? path;
    Object? failure;
    try {
      path = await AppDialogs.runWithProgress<String?>(
        context,
        message: t('lists.exporting'),
        task: (report) => PgnImportService.exportPlaylist(
          playlist,
          onProgress: (done, total) => report(total == 0 ? 0 : done / total),
        ),
      );
    } catch (error) {
      failure = error;
    }
    if (!mounted) return;

    if (failure != null) {
      await Clipboard.setData(ClipboardData(text: buildListPgn(playlist)));
      if (mounted) AppDialogs.snack(context, t('lists.exportFallback'));
      return;
    }
    AppDialogs.snack(
      context,
      path == null ? t('lists.exportCancelled') : t('lists.exported'),
    );
  }

  /// Arama ve süzgeçten geçen oyunlar.
  List<SavedGame> get _visible {
    final games = _playlist?.games ?? const <SavedGame>[];
    final query = foldForSearch(_query);

    return games.where((game) {
      switch (_filter) {
        case _GameFilter.unread:
          if (game.read) return false;
          break;
        case _GameFilter.read:
          if (!game.read) return false;
          break;
        case _GameFilter.favorites:
          if (!game.favorite) return false;
          break;
        case _GameFilter.all:
          break;
      }
      if (query.isEmpty) return true;

      // "42" ya da "#42" -> sıra numarası
      final number = _numbers[game.id];
      if (number != null) {
        final digits = query.replaceAll('#', '');
        if (digits.isNotEmpty &&
            int.tryParse(digits) != null &&
            '$number'.startsWith(digits)) {
          return true;
        }
      }

      final haystack = <String>[
        game.name,
        game.white ?? '',
        game.black ?? '',
        game.note ?? '',
        game.result ?? '',
      ];
      return haystack.any((value) => foldForSearch(value).contains(query));
    }).toList();
  }

  Future<void> _toggleRead(SavedGame game) async {
    await _storage.toggleGameRead(widget.playlistId, game.id);
  }

  Future<void> _setAllRead(bool read) async {
    await _storage.setAllRead(widget.playlistId, read);
  }

  Future<void> _toggleFavorite(SavedGame game) async {
    await _storage.toggleGameFavorite(widget.playlistId, game.id);
  }

  /// Oyunun notunu siler.
  Future<void> _deleteNote(SavedGame game) async {
    game.note = null;
    await _storage.updateGame(widget.playlistId, game);
    if (mounted) AppDialogs.snack(context, t('common.noteDeleted'));
  }

  /// Sıra numarası aralığındaki oyunları okundu/okunmadı yapar.
  ///
  /// Numaralar süzgeçten bağımsızdır; kullanıcı satırda gördüğü numarayı
  /// yazar.
  Future<void> _markRange() async {
    final games = _playlist?.games ?? const <SavedGame>[];
    if (games.isEmpty) return;
    final numbers = games.map((g) => _numbers[g.id] ?? 0).toList()..sort();

    final result = await showDialog<(int, int, bool)>(
      context: context,
      builder: (dialogContext) => RangeDialog(
        min: numbers.first,
        max: numbers.last,
        hint: t('lists.rangeHint', {
          'min': numbers.first,
          'max': numbers.last,
        }),
        markLabel: t('lists.markRead'),
        unmarkLabel: t('lists.markUnread'),
      ),
    );
    if (result == null || !mounted) return;

    final (from, to, read) = result;
    final ids = games
        .where((g) {
          final number = _numbers[g.id];
          return number != null && number >= from && number <= to;
        })
        .map((g) => g.id)
        .toList();
    final changed = await _storage.markManyRead(
      widget.playlistId,
      ids,
      read: read,
    );
    if (!mounted) return;
    AppDialogs.snack(
      context,
      changed == 0
          ? t('puzzles.rangeNone')
          : t('lists.rangeMarked', {'count': changed}),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final playlist = _playlist;
    final total = playlist?.games.length ?? 0;
    final readCount = playlist?.games.where((g) => g.read).length ?? 0;
    final visible = _visible;

    return Scaffold(
      appBar: AppBar(
        title: Text(playlist?.name ?? t('game.list')),
        actions: [
          IconButton(
            tooltip: t('pgn.importIntoList'),
            icon: const Icon(Icons.file_open_outlined),
            onPressed: _importPgnFile,
          ),
          IconButton(
            tooltip: t('lists.exportPgn'),
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: playlist == null ? null : () => _exportPgn(playlist),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'allRead') _setAllRead(true);
              if (value == 'allUnread') _setAllRead(false);
              if (value == 'range') _markRange();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'allRead',
                child: Text(t('lists.markAllRead')),
              ),
              PopupMenuItem(
                value: 'allUnread',
                child: Text(t('lists.markAllUnread')),
              ),
              PopupMenuItem(
                value: 'range',
                child: Text(t('lists.markRange')),
              ),
            ],
          ),
        ],
        bottom: total == 0
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(104),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (value) => setState(() => _query = value),
                        decoration: InputDecoration(
                          hintText: t('lists.search'),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            size: 20,
                          ),
                          isDense: true,
                          suffixIcon: _query.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(
                                    Icons.clear_rounded,
                                    size: 18,
                                  ),
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
                          _filterChip(t('puzzles.filterAll'), _GameFilter.all),
                          _filterChip(
                            t('lists.filterUnread'),
                            _GameFilter.unread,
                          ),
                          _filterChip(t('lists.filterRead'), _GameFilter.read),
                          _filterChip(
                            t('common.onlyFavorites'),
                            _GameFilter.favorites,
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 8, top: 10),
                            child: Text(
                              t('lists.readRatio', {
                                'read': readCount,
                                'total': total,
                              }),
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : total == 0
              ? _emptyState(scheme)
              : visible.isEmpty
                  ? Center(
                      child: Text(
                        t('lists.noMatch'),
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    )
                  : ContentWidth(
                      child: ListView.separated(
                        key: const Key('gameList'),
                        // Telefonun gezinme çubuğu ekranın altından yer
                        // kapıyor; son satır oraya denk gelirse tıklanamıyor.
                        padding: EdgeInsets.fromLTRB(
                          16,
                          8,
                          16,
                          28 + MediaQuery.viewPaddingOf(context).bottom,
                        ),
                        itemCount: visible.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) =>
                            _gameTile(visible[index], scheme),
                      ),
                    ),
    );
  }

  Widget _filterChip(String label, _GameFilter value) {
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

  Widget _emptyState(ColorScheme scheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.sports_esports_outlined,
              size: 46,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 14),
            Text(
              t('lists.emptyGames'),
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gameTile(SavedGame game, ColorScheme scheme) {
    return Material(
      color: scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        mouseCursor: kClickable,
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openGame(game),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 10, 6, 10),
          child: Row(
            children: [
              IconButton(
                tooltip:
                    game.read ? t('lists.markUnread') : t('lists.markRead'),
                icon: Icon(
                  game.read
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                  size: 22,
                  color: game.read ? scheme.success : scheme.onSurfaceVariant,
                ),
                onPressed: () => _toggleRead(game),
              ),
              IconButton(
                tooltip: game.favorite
                    ? t('common.favoriteRemove')
                    : t('common.favoriteAdd'),
                icon: Icon(
                  game.favorite ? Icons.star_rounded : Icons.star_border_rounded,
                  size: 20,
                  color:
                      game.favorite ? scheme.warning : scheme.onSurfaceVariant,
                ),
                onPressed: () => _toggleFavorite(game),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${_numbers[game.id] ?? 0}.',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            game.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: game.read
                                  ? scheme.onSurfaceVariant
                                  : scheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          t('lists.moveCount', {'count': game.moveCount}),
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        if (game.result != null) ...[
                          const SizedBox(width: 8),
                          _resultChip(game.result!, scheme),
                        ],
                        if (game.startFen != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            t('lists.customPosition'),
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.secondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'read':
                      _toggleRead(game);
                      break;
                    case 'favorite':
                      _toggleFavorite(game);
                      break;
                    case 'deleteNote':
                      _deleteNote(game);
                      break;
                    case 'rename':
                      _rename(game);
                      break;
                    case 'pgn':
                      _copyPgn(game);
                      break;
                    case 'move':
                      _move(game);
                      break;
                    case 'delete':
                      _delete(game);
                      break;
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'read',
                    child: Text(
                      game.read ? t('lists.markUnread') : t('lists.markRead'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'favorite',
                    child: Text(
                      game.favorite
                          ? t('common.favoriteRemove')
                          : t('common.favoriteAdd'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'rename',
                    child: Text(t('common.rename')),
                  ),
                  if (game.note != null && game.note!.isNotEmpty)
                    PopupMenuItem(
                      value: 'deleteNote',
                      child: Text(t('common.deleteNote')),
                    ),
                  PopupMenuItem(value: 'pgn', child: Text(t('game.copyPgn'))),
                  PopupMenuItem(
                    value: 'move',
                    child: Text(t('lists.moveToList')),
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
    );
  }

  Widget _resultChip(String result, ColorScheme scheme) {
    final color = switch (result) {
      '1-0' => scheme.success,
      '0-1' => scheme.error,
      _ => scheme.drawColor,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        result == '1/2-1/2' ? '½-½' : result,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
