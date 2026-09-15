import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../models/opening.dart';
import '../../services/opening_service.dart';
import '../../widgets/app_dialogs.dart';

/// Açılış başlıklarını gizleyip gösterir.
///
/// Bir dosyadan bin dört yüz başlık alındığında kullanıcı hepsiyle değil,
/// o dönem çalıştığı birkaçıyla ilgileniyor. Silmek çözüm değil, sonra
/// geri getirmek gerekiyor.
///
/// Ekranda iki ayrı şey var ve karıştırılmamalı: **kutucuk seçimdir**,
/// satırın sonundaki göz **o başlığın şu anki durumudur**. Toplu işlemler
/// seçime bakar; hiçbir şey seçili değilken "seçilenler hariç" ifadesi
/// anlamsız olacağından menü kendini "hepsi" diye adlandırır.
class OpeningVisibilityScreen extends StatefulWidget {
  const OpeningVisibilityScreen({super.key});

  @override
  State<OpeningVisibilityScreen> createState() =>
      _OpeningVisibilityScreenState();
}

class _OpeningVisibilityScreenState extends State<OpeningVisibilityScreen> {
  final OpeningService _service = OpeningService.instance;

  /// Aile adı -> varyant sayısı, ada göre sıralı.
  Map<String, int> _families = {};
  Set<String> _hidden = <String>{};
  final Set<String> _selected = <String>{};
  String _query = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await _service.all();
    final hidden = await _service.hiddenFamilies();
    final counts = <String, int>{};
    for (final Opening opening in all) {
      counts[opening.family] = (counts[opening.family] ?? 0) + 1;
    }
    final sorted = counts.keys.toList()..sort();
    if (!mounted) return;
    setState(() {
      _families = {for (final name in sorted) name: counts[name]!};
      _hidden = Set<String>.from(hidden);
      _selected.removeWhere((name) => !counts.containsKey(name));
      _loading = false;
    });
  }

  List<String> get _listed {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _families.keys.toList();
    return _families.keys
        .where((name) => name.toLowerCase().contains(query))
        .toList();
  }

  Future<void> _toggle(String family) async {
    final hide = !_hidden.contains(family);
    await _service.setFamilyHidden(family, hide);
    await _load();
  }

  Future<void> _hideAllExceptSelected() async {
    await _service.hideAllExcept(Set<String>.from(_selected));
    await _load();
    if (mounted) _report();
  }

  Future<void> _showAllExceptSelected() async {
    await _service.showAllExcept(Set<String>.from(_selected));
    await _load();
    if (mounted) _report();
  }

  void _report() {
    AppDialogs.snack(
      context,
      t('openings.hiddenCount', {'count': _hidden.length}),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final listed = _listed;
    final hasSelection = _selected.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(t('openings.hidden')),
        actions: [
          if (hasSelection)
            IconButton(
              tooltip: t('common.clearSelection'),
              icon: const Icon(Icons.deselect_rounded),
              onPressed: () => setState(_selected.clear),
            ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'hide') _hideAllExceptSelected();
              if (value == 'show') _showAllExceptSelected();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'hide',
                child: ListTile(
                  leading: const Icon(Icons.visibility_off_outlined),
                  title: Text(hasSelection
                      ? t('openings.hideAllExcept',
                          {'count': _selected.length})
                      : t('openings.hideAll')),
                ),
              ),
              PopupMenuItem(
                value: 'show',
                child: ListTile(
                  leading: const Icon(Icons.visibility_outlined),
                  title: Text(hasSelection
                      ? t('openings.showAllExcept',
                          {'count': _selected.length})
                      : t('openings.showAll')),
                ),
              ),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: TextField(
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: t('openings.search'),
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                isDense: true,
              ),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _families.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      t('openings.emptyTitle'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              t('openings.visibilitySummary', {
                                'total': _families.length,
                                'hidden': _hidden.length,
                              }),
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          if (hasSelection)
                            Text(
                              t('openings.selectedCount',
                                  {'count': _selected.length}),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: scheme.primary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        key: const Key('visibilityList'),
                        padding: EdgeInsets.only(
                          bottom: 16 + MediaQuery.viewPaddingOf(context).bottom,
                        ),
                        itemCount: listed.length,
                        itemBuilder: (context, index) {
                          final family = listed[index];
                          final hidden = _hidden.contains(family);
                          return CheckboxListTile(
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                            value: _selected.contains(family),
                            onChanged: (checked) => setState(() {
                              if (checked == true) {
                                _selected.add(family);
                              } else {
                                _selected.remove(family);
                              }
                            }),
                            title: Text(
                              family,
                              style: TextStyle(
                                fontSize: 14,
                                color: hidden ? scheme.onSurfaceVariant : null,
                                decoration:
                                    hidden ? TextDecoration.lineThrough : null,
                              ),
                            ),
                            subtitle: Text(
                              t('openings.familySummaryShort',
                                  {'count': _families[family]}),
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            secondary: IconButton(
                              tooltip: hidden
                                  ? t('openings.show')
                                  : t('openings.hideOne'),
                              icon: Icon(
                                hidden
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: hidden ? scheme.onSurfaceVariant : null,
                              ),
                              onPressed: () => _toggle(family),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}
