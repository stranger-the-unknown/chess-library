import 'package:flutter/material.dart';

import '../widgets/responsive.dart';

import 'package:flutter/services.dart';

import '../l10n/app_strings.dart';
import '../models/playlist.dart';
import '../services/pgn_import_service.dart';
import '../services/analysis_queue.dart';
import '../services/storage_service.dart';
import '../widgets/app_dialogs.dart';
import 'playlist_detail_screen.dart';
import '../widgets/cursors.dart';

/// Kayıtlı oyun listeleri.
class PlaylistScreen extends StatefulWidget {
  const PlaylistScreen({super.key});

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  final StorageService _storage = StorageService.instance;
  List<Playlist> _playlists = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // PGN içe aktarma gibi başka ekranlardaki değişiklikler de yansısın.
    _storage.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    _storage.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    // Analiz listeleri her zaman en üstte; silinemez ve yeniden
    // adlandırılamazlar.
    final analysis = await _storage.loadAnalysisLists();
    final playlists = [...analysis, ...await _storage.loadPlaylists()];
    if (!mounted) return;
    setState(() {
      _playlists = playlists;
      _loading = false;
    });
  }

  Future<void> _create() async {
    final name = await AppDialogs.prompt(
      context,
      title: t('lists.newList'),
      label: t('game.listName'),
    );
    if (name == null) return;
    await _storage.createPlaylist(name);
    await _load();
  }

  Future<void> _rename(Playlist playlist) async {
    final name = await AppDialogs.prompt(
      context,
      title: t('common.rename'),
      label: t('game.listName'),
      initialValue: playlist.name,
    );
    if (name == null) return;
    await _storage.renamePlaylist(playlist.id, name);
    await _load();
  }

  Future<void> _delete(Playlist playlist) async {
    final confirmed = await AppDialogs.confirm(
      context,
      title: t('lists.deleteList'),
      message: t('lists.deleteListMessage', {
        'name': playlist.name,
        'count': playlist.games.length,
      }),
      confirmLabel: t('common.delete'),
      destructive: true,
    );
    if (!confirmed) return;
    await _storage.deletePlaylist(playlist.id);
    await _load();
  }

  Future<void> _exportBackup() async {
    final json = await _storage.exportAll();
    await Clipboard.setData(ClipboardData(text: json));
    if (mounted) {
      AppDialogs.snack(context, t('lists.backupCopied'));
    }
  }

  Future<void> _importBackup() async {
    final json = await AppDialogs.prompt(
      context,
      title: t('lists.restoreBackup'),
      label: t('lists.pasteBackup'),
      maxLines: 6,
      confirmLabel: t('common.load'),
    );
    if (json == null || !mounted) return;
    try {
      final added = await _storage.importAll(json);
      await _load();
      if (mounted) {
        AppDialogs.snack(context, t('lists.backupImported', {'count': added}));
      }
    } catch (_) {
      if (mounted) AppDialogs.snack(context, t('lists.backupUnreadable'));
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(t('lists.title')),
        actions: [
          IconButton(
            tooltip: t('lists.newList'),
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: _create,
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'export') _exportBackup();
              if (value == 'import') _importBackup();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'export',
                child: Text(t('lists.copyBackup')),
              ),
              PopupMenuItem(
                value: 'import',
                child: Text(t('lists.restoreBackup')),
              ),
            ],
          ),
        ],
      ),
      body: ListenableBuilder(
        // Kuyruk ilerledikçe şerit kendini tazelesin.
        listenable: AnalysisQueue.instance,
        builder: (context, _) => Column(
          children: [
            if (AnalysisQueue.instance.isRunning) _queueBanner(scheme),
            Expanded(child: _body(scheme)),
          ],
        ),
      ),
    );
  }

  Widget _body(ColorScheme scheme) {
    return _loading
          ? const Center(child: CircularProgressIndicator())
          : _playlists.isEmpty
              ? _empty(scheme)
              : ContentWidth(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                    itemCount: _playlists.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final playlist = _playlists[index];
                      return Material(
                        color: scheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          mouseCursor: kClickable,
                          borderRadius: BorderRadius.circular(16),
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PlaylistDetailScreen(
                                    playlistId: playlist.id),
                              ),
                            );
                            await _load();
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: scheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    Icons.folder_rounded,
                                    color: scheme.secondary,
                                    size: 21,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        // Analiz listelerinin adı
                                        // çeviriden gelir; kimlikleri
                                        // sabit olduğu için dil
                                        // değişince adı da değişir.
                                        StorageService.isSystemList(
                                          playlist.id,
                                        )
                                            ? t(
                                                playlist.id ==
                                                        StorageService
                                                            .deepListId
                                                    ? 'analysis.deepList'
                                                    : 'analysis.quickList',
                                              )
                                            : playlist.name,
                                        style: const TextStyle(
                                          fontSize: 15.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        // Okunan sayısı listeye girmeden
                                        // görünsün; eskiden listenin
                                        // içindeki süzgeç şeridindeydi ve
                                        // orada hem yer kaplıyordu hem de
                                        // ancak girince görülüyordu.
                                        t('lists.gameCountRead', {
                                          'count': playlist.games.length,
                                          'read': playlist.games
                                              .where((g) => g.read)
                                              .length,
                                        }),
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  onSelected: (value) {
                                    if (value == 'rename') _rename(playlist);
                                    if (value == 'export') _exportPgn(playlist);
                                    if (value == 'delete') _delete(playlist);
                                  },
                                  itemBuilder: (context) => [
                                    // Analiz listeleri silinemez ve
                                    // yeniden adlandırılamaz; komutları
                                    // göstermek yerine hiç sunulmuyor.
                                    if (!StorageService.isSystemList(
                                      playlist.id,
                                    )) ...[
                                      PopupMenuItem(
                                        value: 'rename',
                                        child: Text(t('common.rename')),
                                      ),
                                    ],
                                    PopupMenuItem(
                                      value: 'export',
                                      child: Text(t('lists.exportPgn')),
                                    ),
                                    if (!StorageService.isSystemList(
                                      playlist.id,
                                    ))
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
                    },
                  ),
                );
  }

  /// Toplu analiz sürerken görünen ilerleme şeridi.
  ///
  /// Listeler sekmesinde duruyor: kullanıcı analizi başlatıp başka yere
  /// gidiyor, işin sürdüğünü bir yerde görmesi gerekiyor.
  Widget _queueBanner(ColorScheme scheme) {
    final queue = AnalysisQueue.instance;
    return Container(
      width: double.infinity,
      color: scheme.secondaryContainer,
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('analysis.progress', {
                    'done': queue.done,
                    'total': queue.total,
                  }),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSecondaryContainer,
                  ),
                ),
                if (queue.current != null)
                  Text(
                    queue.current!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: queue.cancel,
            child: Text(t('common.cancel')),
          ),
        ],
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
              Icons.folder_open_rounded,
              size: 48,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              t('lists.empty'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              t('lists.emptyHint'),
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
            ),
            const SizedBox(height: 22),
            ElevatedButton.icon(
              onPressed: _create,
              icon: const Icon(Icons.add_rounded),
              label: Text(t('lists.createList')),
            ),
          ],
        ),
      ),
    );
  }
}
