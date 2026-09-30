import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../models/playlist.dart';
import '../services/storage_service.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/responsive.dart';

/// Oyun listelerinin sırası.
///
/// Açılış başlıklarını sıralama ekranının (`OpeningOrderScreen`) eşi:
/// satır solundaki tutamaçla sürükleniyor (dokunur dokunmaz, uzun basma
/// gerekmeden), sağdaki düğme satırı en üste taşıyor. Her taşıma hemen
/// kaydediliyor. Listelerin içindeki oyunların sırasına dokunulmuyor:
/// oyun numaraları o sıradan geliyor.
class PlaylistOrderScreen extends StatefulWidget {
  const PlaylistOrderScreen({super.key});

  @override
  State<PlaylistOrderScreen> createState() => _PlaylistOrderScreenState();
}

class _PlaylistOrderScreenState extends State<PlaylistOrderScreen> {
  final StorageService _storage = StorageService.instance;
  List<Playlist> _playlists = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final playlists = (await _storage.loadPlaylists()).toList();
    if (!mounted) return;
    setState(() {
      _playlists = playlists;
      _loading = false;
    });
  }

  Future<void> _move(int from, int to) async {
    if (from == to) return;
    setState(() {
      final item = _playlists.removeAt(from);
      _playlists.insert(to, item);
    });
    try {
      await _storage.reorderPlaylists([for (final p in _playlists) p.id]);
    } catch (_) {
      // Yazılamadıysa ekrandaki sıra kayıttakine dönüyor.
      if (mounted) AppDialogs.snack(context, t('lists.saveFailed'));
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(t('lists.order'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ContentWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                    child: Text(
                      t('openings.orderHint'),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                      itemCount: _playlists.length,
                      // Hedef, çıkarılan satır hesaba katılmış hâlde geliyor.
                      onReorderItem: _move,
                      itemBuilder: (context, index) {
                        final playlist = _playlists[index];
                        return ListTile(
                          key: ValueKey(playlist.id),
                          contentPadding:
                              const EdgeInsets.only(left: 4, right: 4),
                          leading: ReorderableDragStartListener(
                            index: index,
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(Icons.drag_handle_rounded),
                            ),
                          ),
                          title: Text(
                            playlist.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14.5),
                          ),
                          subtitle: Text(
                            t('lists.gameCount', {
                              'count': playlist.games.length,
                            }),
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          trailing: IconButton(
                            tooltip: t('openings.moveToTop'),
                            icon: const Icon(Icons.vertical_align_top_rounded),
                            onPressed:
                                index == 0 ? null : () => _move(index, 0),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
