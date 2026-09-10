import 'package:flutter/material.dart';

import '../../widgets/responsive.dart';

import '../../l10n/app_strings.dart';
import '../../models/puzzle.dart';
import '../../services/puzzle_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_dialogs.dart';
import 'puzzle_list_screen.dart';
import '../../widgets/cursors.dart';

/// Bulmaca listelerinin ana ekranı.
class PuzzleCollectionsScreen extends StatefulWidget {
  const PuzzleCollectionsScreen({super.key});

  @override
  State<PuzzleCollectionsScreen> createState() =>
      _PuzzleCollectionsScreenState();
}

class _PuzzleCollectionsScreenState extends State<PuzzleCollectionsScreen> {
  final PuzzleService _service = PuzzleService.instance;

  List<PuzzleCollection> _collections = [];
  final Map<String, _CollectionStats> _stats = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await _loadInner();
    } catch (_) {
      // Beklenmedik bir okuma hatasında ekran boş listeyle açılsın;
      // dönen çarkta asılı kalmaktan iyidir.
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadInner() async {
    final collections = await _service.collections();
    final progress = await _service.progressMap();

    _stats.clear();
    for (final collection in collections) {
      final puzzles = await _service.puzzlesOf(collection);
      int solved = 0;
      int favorites = 0;
      for (final puzzle in puzzles) {
        final entry = progress[puzzle.id];
        if (entry == null) continue;
        if (entry.solved) solved++;
        if (entry.favorite) favorites++;
      }
      _stats[collection.id] = _CollectionStats(
        total: puzzles.length,
        solved: solved,
        favorites: favorites,
      );
    }

    if (!mounted) return;
    setState(() {
      _collections = collections;
      _loading = false;
    });
  }

  Future<void> _createCollection() async {
    final name = await AppDialogs.prompt(
      context,
      title: t('puzzles.newCollection'),
      label: t('game.listName'),
    );
    if (name == null) return;
    await _service.createCollection(name);
    await _load();
  }

  Future<void> _renameCollection(PuzzleCollection collection) async {
    final name = await AppDialogs.prompt(
      context,
      title: t('puzzles.renameCollection'),
      label: t('game.listName'),
      initialValue: collection.name,
    );
    if (name == null) return;
    await _service.renameCollection(collection.id, name);
    await _load();
  }

  Future<void> _deleteCollection(PuzzleCollection collection) async {
    final confirmed = await AppDialogs.confirm(
      context,
      title: t('lists.deleteList'),
      message: t('puzzles.deleteCollectionMessage', {'name': collection.name}),
      confirmLabel: t('common.delete'),
      destructive: true,
    );
    if (!confirmed) return;
    await _service.deleteCollection(collection.id);
    await _load();
  }

  Future<void> _resetProgress(PuzzleCollection collection) async {
    final confirmed = await AppDialogs.confirm(
      context,
      title: t('puzzles.resetProgress'),
      message: t('puzzles.resetProgressMessage', {'name': collection.name}),
      confirmLabel: t('common.reset'),
      destructive: true,
    );
    if (!confirmed) return;
    await _service.resetProgress(collection.id);
    await _load();
  }

  Future<void> _resetEdits(PuzzleCollection collection) async {
    final confirmed = await AppDialogs.confirm(
      context,
      title: t('puzzles.resetEdits'),
      message: t('puzzles.resetEditsMessage'),
      confirmLabel: t('game.takeBack'),
      destructive: true,
    );
    if (!confirmed) return;
    await _service.resetCollection(collection.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(t('puzzles.title')),
        actions: [
          IconButton(
            tooltip: t('lists.newList'),
            icon: const Icon(Icons.add_rounded),
            onPressed: _createCollection,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ContentWidth(
                child: _collections.isEmpty
                    ? ListView(
                        // Kaydırılabilir kalmalı: RefreshIndicator ancak
                        // kaydırılabilir bir çocukla çalışır.
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                        children: [_emptyState(scheme)],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                        itemCount: _collections.length + (_hasPuzzles ? 1 : 0),
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          if (index == _collections.length) {
                            return _totalCard(scheme);
                          }
                          return _collectionCard(_collections[index], scheme);
                        },
                      ),
              ),
            ),
    );
  }

  Widget _collectionCard(PuzzleCollection collection, ColorScheme scheme) {
    final stats = _stats[collection.id] ?? const _CollectionStats();
    final ratio = stats.total == 0 ? 0.0 : stats.solved / stats.total;

    return Material(
      color: scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        mouseCursor: kClickable,
        borderRadius: BorderRadius.circular(18),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PuzzleListScreen(collection: collection),
            ),
          );
          await _load();
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: collection.isBuiltIn
                          ? scheme.primary.withValues(alpha: 0.18)
                          : scheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      collection.isBuiltIn
                          ? Icons.auto_awesome_mosaic_rounded
                          : Icons.folder_special_rounded,
                      color: collection.isBuiltIn
                          ? scheme.primary
                          : scheme.onSecondaryContainer,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          collection.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (collection.description != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              collection.description!,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      switch (value) {
                        case 'rename':
                          _renameCollection(collection);
                          break;
                        case 'progress':
                          _resetProgress(collection);
                          break;
                        case 'edits':
                          _resetEdits(collection);
                          break;
                        case 'delete':
                          _deleteCollection(collection);
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      if (!collection.isBuiltIn)
                        PopupMenuItem(
                          value: 'rename',
                          child: Text(t('common.rename')),
                        ),
                      PopupMenuItem(
                        value: 'progress',
                        child: Text(t('puzzles.resetProgress')),
                      ),
                      PopupMenuItem(
                        value: 'edits',
                        child: Text(t('puzzles.resetEdits')),
                      ),
                      if (!collection.isBuiltIn)
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(t('lists.deleteList')),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 6,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    t('puzzles.solvedRatio', {
                      'solved': stats.solved,
                      'total': stats.total,
                    }),
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  if (stats.favorites > 0) ...[
                    Icon(Icons.star_rounded, size: 14, color: scheme.warning),
                    const SizedBox(width: 3),
                    Text(
                      '${stats.favorites}',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Listelerde en az bir bulmaca var mı?
  ///
  /// Hiç yokken alttaki toplam yazısı boş bir bilgi satırı gibi durduğu
  /// için gizlenir.
  bool get _hasPuzzles => _stats.values.any((s) => s.total > 0);

  Widget _emptyState(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.only(top: 48),
      child: Column(
        children: [
          Icon(
            Icons.extension_outlined,
            size: 48,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            t('puzzles.emptyTitle'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              t('puzzles.emptyHint'),
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.45),
            ),
          ),
          const SizedBox(height: 22),
          ElevatedButton.icon(
            onPressed: _createCollection,
            icon: const Icon(Icons.add_rounded),
            label: Text(t('puzzles.createFirst')),
          ),
        ],
      ),
    );
  }

  Widget _totalCard(ColorScheme scheme) {
    int total = 0;
    int solved = 0;
    for (final stat in _stats.values) {
      total += stat.total;
      solved += stat.solved;
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.emoji_events_outlined, color: scheme.secondary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              t('puzzles.totalSummary', {'total': total, 'solved': solved}),
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _CollectionStats {
  final int total;
  final int solved;
  final int favorites;

  const _CollectionStats({this.total = 0, this.solved = 0, this.favorites = 0});
}
