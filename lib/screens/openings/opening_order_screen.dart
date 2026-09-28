import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../services/opening_service.dart';
import '../../widgets/responsive.dart';

/// Açılış başlıklarının ya da bir başlığın varyantlarının sırası.
///
/// [family] boşsa başlıklar sıralanıyor; doluysa o başlığın varyantları.
/// Satır solundaki tutamaçla sürükleniyor (dokunur dokunmaz, uzun basma
/// gerekmeden); sağdaki düğme satırı en üste taşıyor — binlerce başlıkta
/// sürüklemek uzun sürüyor. Her taşıma hemen kaydediliyor.
class OpeningOrderScreen extends StatefulWidget {
  final String? family;

  const OpeningOrderScreen({super.key, this.family});

  @override
  State<OpeningOrderScreen> createState() => _OpeningOrderScreenState();
}

class _OrderItem {
  /// Başlık sıralanıyorsa başlığın adı, varyant sıralanıyorsa kimliği.
  final String key;
  final String title;
  final String subtitle;
  final bool hidden;

  const _OrderItem(this.key, this.title, this.subtitle, {this.hidden = false});
}

class _OpeningOrderScreenState extends State<OpeningOrderScreen> {
  final OpeningService _service = OpeningService.instance;
  List<_OrderItem> _items = [];
  bool _loading = true;

  bool get _families => widget.family == null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await _service.all();
    final hidden = await _service.hiddenFamilies();
    final items = <_OrderItem>[];
    if (_families) {
      final counts = <String, int>{};
      for (final opening in all) {
        counts[opening.family] = (counts[opening.family] ?? 0) + 1;
      }
      for (final entry in counts.entries) {
        items.add(_OrderItem(
          entry.key,
          entry.key,
          t('openings.familySummaryShort', {'count': entry.value}),
          hidden: hidden.contains(entry.key),
        ));
      }
    } else {
      for (final opening in all) {
        if (opening.family != widget.family) continue;
        items.add(_OrderItem(
          opening.id,
          opening.variation,
          opening.sanMoves.take(8).join(' '),
        ));
      }
    }
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _move(int from, int to) async {
    if (from == to) return;
    setState(() {
      final item = _items.removeAt(from);
      _items.insert(to, item);
    });
    final keys = [for (final item in _items) item.key];
    if (_families) {
      await _service.reorderFamilies(keys);
    } else {
      await _service.reorderVariations(widget.family!, keys);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _families
              ? t('openings.orderFamilies')
              : t('openings.orderVariationsOf', {'family': widget.family}),
        ),
      ),
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
                      itemCount: _items.length,
                      // Hedef, çıkarılan satır hesaba katılmış hâlde geliyor.
                      onReorderItem: _move,
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        return ListTile(
                          key: ValueKey(item.key),
                          contentPadding:
                              const EdgeInsets.only(left: 4, right: 4),
                          leading: ReorderableDragStartListener(
                            index: index,
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(Icons.drag_handle_rounded),
                            ),
                          ),
                          title: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 14.5),
                                ),
                              ),
                              if (item.hidden) ...[
                                const SizedBox(width: 6),
                                Tooltip(
                                  message: t('openings.hidden'),
                                  child: Icon(
                                    Icons.visibility_off_outlined,
                                    size: 16,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Text(
                            item.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
