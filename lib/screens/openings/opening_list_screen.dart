import 'package:flutter/material.dart';

import '../../widgets/responsive.dart';

import '../../l10n/app_strings.dart';
import '../../models/opening.dart';
import '../../models/puzzle_search.dart' show foldForSearch;
import '../../services/opening_service.dart';
import 'opening_visibility_screen.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_dialogs.dart';
import 'opening_study_screen.dart';
import 'package:flutter/services.dart';
import '../../services/file_pick.dart';
import '../../services/text_file_service.dart';

/// Açılış kütüphanesi: aileye göre gruplanmış varyantlar.
class OpeningListScreen extends StatefulWidget {
  const OpeningListScreen({super.key});

  @override
  State<OpeningListScreen> createState() => _OpeningListScreenState();
}

class _OpeningListScreenState extends State<OpeningListScreen> {
  final OpeningService _service = OpeningService.instance;
  final TextEditingController _searchController = TextEditingController();

  List<Opening> _all = [];
  Map<String, OpeningProgress> _progress = {};
  Set<String> _hidden = <String>{};
  String _query = '';
  bool _onlyFavorites = false;
  bool _loading = true;

  /// Başlıklar açık mı kapalı mı kurulsun.
  ///
  /// Menüdeki "hepsini aç" / "hepsini kapat" bunu değiştiriyor. Arama
  /// buna karışmıyor: eskiden arama yapılınca eşleşen başlıklar kendi
  /// kendine açılıyordu, artık açılmıyor.
  bool _expandAll = false;

  /// Başlıkları yeniden kurmak için sayaç.
  ///
  /// [ExpansionTile] `initiallyExpanded` değerini yalnızca kurulurken
  /// okur; sonradan değiştirmek bir şey yapmaz. Sayaç anahtarın parçası
  /// olduğu için, artınca bütün başlıklar yeni açılış hâliyle sıfırdan
  /// kuruluyor. Kullanıcının tek tek yaptığı açıp kapamalar arada
  /// korunuyor, çünkü anahtar aynı kaldıkça durum da kalıyor.
  int _expansionEpoch = 0;

  void _setAllExpanded(bool expanded) {
    setState(() {
      _expandAll = expanded;
      _expansionEpoch++;
    });
  }

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
    final all = await _service.all();
    final progress = await _service.progressMap();
    final hidden = await _service.hiddenFamilies();
    if (!mounted) return;
    setState(() {
      _all = all;
      _progress = progress;
      _hidden = Set<String>.from(hidden);
      _loading = false;
    });
  }

  /// Gizlenen ailelerin dışındaki açılışlar.
  List<Opening> get _shown =>
      _all.where((o) => !_hidden.contains(o.family)).toList();

  List<Opening> get _visible {
    final query = _query.trim().toLowerCase();
    return _shown.where((opening) {
      if (_onlyFavorites && _progress[opening.id]?.favorite != true) {
        return false;
      }
      if (query.isEmpty) return true;
      return opening.family.toLowerCase().contains(query) ||
          opening.variation.toLowerCase().contains(query) ||
          opening.eco.toLowerCase().contains(query) ||
          opening.sanMoves.join(' ').toLowerCase().contains(query);
    }).toList();
  }

  Map<String, List<Opening>> get _grouped {
    final grouped = <String, List<Opening>>{};
    for (final opening in _visible) {
      grouped.putIfAbsent(opening.family, () => <Opening>[]).add(opening);
    }
    return grouped;
  }

  Future<void> _open(Opening opening) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => OpeningStudyScreen(opening: opening)),
    );
    await _load();
  }

  Future<void> _addOwn() => _openEditor();

  /// Varyant ekleme ve düzenleme aynı formu kullanır.
  ///
  /// [existing] verildiğinde alanlar dolu gelir ve kaydetme düzenleme
  /// yapar; verilmediğinde yeni varyant eklenir. [family]: başlığın
  /// menüsündeki "Varyant ekle"den gelindiyse o başlık hazır yazılı.
  Future<void> _openEditor({Opening? existing, String? family}) async {
    final editing = existing != null;
    // Başlık kutusu var olan başlıkları önersin (gizliler dahil): elle
    // yazarken "Ispanyol" ile "İspanyol" iki ayrı başlık oluyordu.
    final families = {for (final o in _all) o.family}.toList()..sort();
    // Alanların denetleyicileri pencerenin kendisinde: pencere kapanma
    // animasyonu sürerken de metin kutularını yeniden çiziyor. Eskiden
    // denetleyiciler pencere döner dönmez atılıyordu ve kapanan pencere
    // atılmış denetleyiciye dokunuyordu (hata ayıklama derlemesinde
    // "TextEditingController was used after being disposed").
    final form = await showDialog<_EditorResult>(
      context: context,
      builder: (_) => _OpeningEditorDialog(
        existing: existing,
        initialFamily: family,
        families: families,
      ),
    );
    if (form == null || !mounted) return;

    if (editing) {
      final ok = await _service.editCustom(
        id: existing.id,
        family: form.family,
        variation: form.name,
        moveText: form.moves,
      );
      if (!mounted) return;
      if (!ok) {
        AppDialogs.snack(context, t('openings.noValidMove'));
        return;
      }
      // Değişiklik listede görünüyor; ayrıca bildirim göstermiyoruz.
      await _load();
      return;
    }

    // Hamle kutusunda alt alta birden çok varyant olabilir. Eskiden
    // ilk satırdan sonrası sessizce atılıyordu.
    final result = await _service.addManyFromSan(
      family: form.family,
      variation: form.name,
      moveText: form.moves,
    );
    if (!mounted) return;
    final added = result.added;
    if (added.isEmpty) {
      AppDialogs.snack(context, t('openings.noValidMove'));
      return;
    }
    await _load();
    if (!mounted) return;
    // Eklenemeyen ya da yarıda kesilen varyant da söyleniyor: eskiden
    // geçersiz hamlede sessizce durulup "eklendi" deniyordu.
    final parts = [
      added.length == 1
          ? t('openings.added', {'count': added.single.sanMoves.length})
          : t('openings.imported', {'count': added.length}),
      if (result.skipped > 0)
        t('openings.skippedInvalid', {'count': result.skipped}),
      if (result.truncated > 0)
        t('openings.truncatedAtInvalid', {'count': result.truncated}),
    ];
    AppDialogs.snack(context, parts.join(' '));
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
    // Kapanistaki (closure) kullanim icin ayri degisken: cozumleyici
    // govdesi disarida atanan final bir yereli kapanis icinde daraltmiyor.
    final content = picked.content;
    final ImportResult result;
    try {
      result = await AppDialogs.runWithProgress<ImportResult>(
        context,
        message: t('openings.importing'),
        task: (report) => _service.importText(
          content,
          onProgress: (done, total) => report(total == 0 ? 0 : done / total),
        ),
      );
    } catch (_) {
      if (mounted) AppDialogs.snack(context, t('lists.saveFailed'));
      return;
    }
    await _load();
    if (!mounted) return;
    // Atlananları söylemezsek, listede zaten bulunan bir dosyayı yeniden
    // alan kullanıcı "0 varyant eklendi" görüp bozuk sanıyor.
    AppDialogs.snack(
      context,
      result.skipped == 0
          ? t('openings.imported', {'count': result.added})
          : t('openings.importedWithSkips', {
              'count': result.added,
              'skipped': result.skipped,
            }),
    );
  }

  Future<void> _deleteAll() async {
    if (_all.isEmpty) {
      AppDialogs.snack(context, t('openings.deleteAllEmpty'));
      return;
    }
    final confirmed = await AppDialogs.confirm(
      context,
      title: t('openings.deleteAll'),
      message: t('openings.deleteAllMessage', {'count': _all.length}),
      confirmLabel: t('common.delete'),
      destructive: true,
    );
    if (!confirmed) return;
    final removed = await _service.deleteAll();
    await _load();
    if (mounted) {
      AppDialogs.snack(context, t('openings.familyDeleted', {'count': removed}));
    }
  }

  Future<void> _manageVisibility() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const OpeningVisibilityScreen()),
    );
    await _load();
  }

  Future<void> _exportToFile() async {
    if (_all.isEmpty) {
      AppDialogs.snack(context, t('openings.exportEmpty'));
      return;
    }
    final text = await _service.exportText();
    if (!mounted) return;
    String? path;
    try {
      path = await TextFileService.save(t('openings.title'), text);
    } catch (_) {
      path = null;
    }
    if (!mounted) return;
    if (path == null) {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) AppDialogs.snack(context, t('puzzles.exportFallback'));
      return;
    }
    AppDialogs.snack(context, t('openings.exported', {'count': _all.length}));
  }

  Future<void> _deleteCustom(Opening opening) async {
    final confirmed = await AppDialogs.confirm(
      context,
      title: t('openings.deleteVariation'),
      message: t('openings.deleteMessage', {'name': opening.title}),
      confirmLabel: t('common.delete'),
      destructive: true,
    );
    if (!confirmed) return;
    await _service.deleteCustom(opening.id);
    await _load();
  }

  /// Başlığı yeniden adlandırır: altındaki bütün varyantlar yeni ada
  /// taşınıyor. Yeni ad var olan bir başlıksa önce birleştirme soruluyor
  /// (geri almak varyant varyant düzenlemek demek).
  Future<void> _renameFamily(String family) async {
    final name = await AppDialogs.prompt(
      context,
      title: t('openings.renameFamily'),
      label: t('openings.family'),
      initialValue: family,
      confirmLabel: t('common.save'),
    );
    if (name == null || !mounted) return;
    final target = name.trim();
    if (target.isEmpty || target == family) return;
    if (_all.any((o) => o.family == target)) {
      final count = _all.where((o) => o.family == family).length;
      final merge = await AppDialogs.confirm(
        context,
        title: t('openings.renameFamily'),
        message: t('openings.mergeFamilyMessage', {
          'from': family,
          'to': target,
          'count': count,
        }),
        confirmLabel: t('openings.merge'),
      );
      if (!merge || !mounted) return;
    }
    final moved = await _service.renameFamily(family, target);
    await _load();
    if (!mounted) return;
    AppDialogs.snack(
      context,
      t('openings.familyRenamed', {'count': moved, 'name': target}),
    );
  }

  Future<void> _deleteFamily(String family) async {
    // Onay, **süzgeçsiz** sayıyı söylemeli: ekrandaki liste aramaya ve
    // "yalnızca favoriler"e göre daralıyor ama silme o ailenin tümünü
    // götürüyordu. "Najdorf" arayıp aileyi silen kullanıcı "1 varyant"
    // onayı verip yirmisini birden kaybedebiliyordu.
    final count = _all.where((o) => o.family == family).length;
    final confirmed = await AppDialogs.confirm(
      context,
      title: t('openings.deleteFamily'),
      message: t('openings.deleteFamilyMessage', {
        'name': family,
        'count': count,
      }),
      confirmLabel: t('common.delete'),
      destructive: true,
    );
    if (!confirmed) return;
    final removed = await _service.deleteFamily(family);
    await _load();
    if (mounted) {
      AppDialogs.snack(
        context,
        t('openings.familyDeleted', {'count': removed}),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final grouped = _grouped;
    final families = grouped.keys.toList();

    final learned =
        _shown.where((o) => _progress[o.id]?.learned == true).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(t('openings.title')),
        actions: [
          IconButton(
            tooltip: _onlyFavorites
                ? t('common.showAll')
                : t('common.onlyFavorites'),
            icon: Icon(
              _onlyFavorites ? Icons.star_rounded : Icons.star_border_rounded,
              color: _onlyFavorites ? scheme.warning : null,
            ),
            onPressed: () => setState(() => _onlyFavorites = !_onlyFavorites),
          ),
          IconButton(
            tooltip: t('openings.addOwn'),
            icon: const Icon(Icons.add_rounded),
            onPressed: _addOwn,
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'expandAll') _setAllExpanded(true);
              if (value == 'collapseAll') _setAllExpanded(false);
              if (value == 'import') _importFromFile();
              if (value == 'export') _exportToFile();
              if (value == 'visibility') _manageVisibility();
              if (value == 'deleteAll') _deleteAll();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'expandAll',
                child: ListTile(
                  leading: const Icon(Icons.unfold_more_rounded),
                  title: Text(t('openings.expandAll')),
                ),
              ),
              PopupMenuItem(
                value: 'collapseAll',
                child: ListTile(
                  leading: const Icon(Icons.unfold_less_rounded),
                  title: Text(t('openings.collapseAll')),
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'import',
                child: ListTile(
                  leading: const Icon(Icons.file_open_outlined),
                  title: Text(t('openings.importFile')),
                ),
              ),
              PopupMenuItem(
                value: 'export',
                child: ListTile(
                  leading: const Icon(Icons.ios_share_rounded),
                  title: Text(t('openings.exportFile')),
                ),
              ),
              PopupMenuItem(
                value: 'visibility',
                child: ListTile(
                  leading: const Icon(Icons.visibility_off_outlined),
                  title: Text(t('openings.hidden')),
                  subtitle: _hidden.isEmpty
                      ? null
                      : Text(t('openings.hiddenCount',
                          {'count': _hidden.length})),
                ),
              ),
              PopupMenuItem(
                value: 'deleteAll',
                child: ListTile(
                  leading: const Icon(Icons.delete_forever_outlined),
                  title: Text(t('openings.deleteAll')),
                ),
              ),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          // Arama kutusu da içerik genişliğinde: geniş pencerede tek
          // başına pencereye yapışık duruyordu.
          child: ContentWidth(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: t('openings.search'),
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
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ContentInset(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              builder: (context, padding) => ListView(
                padding: padding,
                children: [
                  if (_shown.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.menu_book_rounded,
                            size: 20,
                            color: scheme.onSecondaryContainer,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              learned == 0
                                  ? t('openings.summaryCount', {
                                      'total': _shown.length,
                                    })
                                  : t('openings.summary', {
                                      'total': _shown.length,
                                      'learned': learned,
                                    }),
                              style: TextStyle(
                                fontSize: 12.5,
                                color: scheme.onSecondaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_shown.isNotEmpty) const SizedBox(height: 12),
                  if (_all.isEmpty)
                    _emptyState(scheme)
                  // Her şey gizliyken "eşleşen yok" demek yanıltıcı ve
                  // kullanıcıyı çıkışsız bırakıyor; gizleme ekranına yol
                  // gösterilmeli.
                  else if (_shown.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 60),
                      child: Column(
                        children: [
                          Icon(
                            Icons.visibility_off_outlined,
                            size: 40,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            t('openings.allHidden'),
                            textAlign: TextAlign.center,
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 18),
                          ElevatedButton.icon(
                            onPressed: _manageVisibility,
                            icon: const Icon(Icons.visibility_outlined),
                            label: Text(t('openings.hidden')),
                          ),
                        ],
                      ),
                    )
                  else if (families.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 60),
                      child: Center(
                        child: Text(
                          t('openings.noMatch'),
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ),
                  for (final family in families)
                    _familyTile(family, grouped[family]!, scheme),
                ],
              ),
            ),
    );
  }

  Widget _emptyState(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.only(top: 48),
      child: Column(
        children: [
          Icon(
            Icons.menu_book_outlined,
            size: 48,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            t('openings.emptyTitle'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              t('openings.emptyHint'),
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.45),
            ),
          ),
          const SizedBox(height: 22),
          ElevatedButton.icon(
            onPressed: _addOwn,
            icon: const Icon(Icons.add_rounded),
            label: Text(t('openings.addOwn')),
          ),
        ],
      ),
    );
  }

  Widget _familyTile(
    String family,
    List<Opening> openings,
    ColorScheme scheme,
  ) {
    final learned =
        openings.where((o) => _progress[o.id]?.learned == true).length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      // Boyanmış bir Container, ListTile'ın mürekkep dalgasını gizliyor;
      // zemini Material verince başlığa dokunma geri bildirimi görünüyor.
      child: Material(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: ValueKey('$family|$_expansionEpoch'),
            initiallyExpanded: _expandAll,
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    family,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                // Menü dokunuşu kendine alıyor, başlık açılıp kapanmıyor.
                PopupMenuButton<String>(
                  tooltip: t('openings.familyMenu'),
                  icon: Icon(
                    Icons.more_vert,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                  onSelected: (value) {
                    switch (value) {
                      case 'add':
                        _openEditor(family: family);
                      case 'rename':
                        _renameFamily(family);
                      case 'deleteFamily':
                        _deleteFamily(family);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem<String>(
                      value: 'add',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.playlist_add_rounded),
                        title: Text(t('openings.addToFamily')),
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'rename',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.drive_file_rename_outline),
                        title: Text(t('openings.renameFamily')),
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'deleteFamily',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.delete_sweep_outlined),
                        title: Text(t('openings.deleteFamily')),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            subtitle: Text(
              learned == 0
                  ? t('openings.familySummaryShort', {
                      'count': openings.length,
                    })
                  : t('openings.familySummary', {
                      'count': openings.length,
                      'learned': learned,
                    }),
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            children: [
              for (final opening in openings)
                ListTile(
                  dense: true,
                  onTap: () => _open(opening),
                  leading: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      opening.eco,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  title: Text(
                    opening.variation,
                    style: const TextStyle(fontSize: 14),
                  ),
                  subtitle: Text(
                    opening.sanMoves.take(8).join(' '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_progress[opening.id]?.favorite == true)
                        Icon(
                          Icons.star_rounded,
                          size: 16,
                          color: scheme.warning,
                        ),
                      if (_progress[opening.id]?.learned == true)
                        Icon(
                          Icons.check_circle_rounded,
                          size: 16,
                          color: scheme.success,
                        ),
                      if (opening.custom)
                        PopupMenuButton<String>(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.more_vert_rounded, size: 18),
                          onSelected: (value) {
                            if (value == 'edit') {
                              _openEditor(existing: opening);
                            }
                            if (value == 'delete') _deleteCustom(opening);
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'edit',
                              child: ListTile(
                                leading: const Icon(Icons.edit_outlined),
                                title: Text(t('openings.editVariation')),
                              ),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: ListTile(
                                leading: const Icon(Icons.delete_outline),
                                title: Text(t('openings.deleteVariation')),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Varyant formunun sonucu (alanlar kırpılmış; hamleler olduğu gibi).
typedef _EditorResult = ({String family, String name, String moves});

/// Varyant ekleme / düzenleme penceresi.
///
/// Denetleyiciler burada yaşıyor ve pencere ağaçtan tamamen çıkınca
/// atılıyor; kapanma animasyonu boyunca geçerli kalıyorlar.
class _OpeningEditorDialog extends StatefulWidget {
  final Opening? existing;

  /// Başlığın menüsünden "Varyant ekle" ile gelindiyse o başlık.
  final String? initialFamily;

  /// Önerilecek var olan başlıklar.
  final List<String> families;

  const _OpeningEditorDialog({
    this.existing,
    this.initialFamily,
    this.families = const [],
  });

  @override
  State<_OpeningEditorDialog> createState() => _OpeningEditorDialogState();
}

class _OpeningEditorDialogState extends State<_OpeningEditorDialog> {
  late final TextEditingController _family = TextEditingController(
    text: widget.existing?.family ?? widget.initialFamily ?? '',
  );
  final FocusNode _familyFocus = FocusNode();
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.variation ?? '');
  late final TextEditingController _moves =
      TextEditingController(text: widget.existing?.sanMoves.join(' ') ?? '');

  @override
  void dispose() {
    _family.dispose();
    _familyFocus.dispose();
    _name.dispose();
    _moves.dispose();
    super.dispose();
  }

  /// Yazılanla eşleşen başlıklar: önce yazılanla başlayanlar, sonra
  /// içinde geçenler; Türkçe harf ve büyük/küçük harf farkı gözetmeden.
  /// Yazılan zaten bir başlığın tam adıysa öneri yok.
  Iterable<String> _familyOptions(TextEditingValue value) {
    final query = foldForSearch(value.text);
    if (query.isEmpty) return const [];
    final starts = <String>[];
    final contains = <String>[];
    for (final family in widget.families) {
      final folded = foldForSearch(family);
      if (folded == query) return const [];
      if (folded.startsWith(query)) {
        starts.add(family);
      } else if (folded.contains(query)) {
        contains.add(family);
      }
    }
    return [...starts, ...contains].take(8);
  }

  Widget _familyOptionsView(
    BuildContext context,
    AutocompleteOnSelected<String> onSelected,
    Iterable<String> options,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final list = options.toList();
    return Material(
      key: const ValueKey('opening-family-options'),
      elevation: 4,
      borderRadius: BorderRadius.circular(10),
      color: scheme.surfaceContainerHigh,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 240),
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 4),
          shrinkWrap: true,
          itemCount: list.length,
          itemBuilder: (context, index) {
            // Klavyeyle (masaüstü) gezilen öneri vurgulu.
            final highlighted =
                AutocompleteHighlightedOption.of(context) == index;
            return ListTile(
              dense: true,
              selected: highlighted,
              selectedTileColor: scheme.secondaryContainer,
              title: Text(list[index]),
              onTap: () => onSelected(list[index]),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return AlertDialog(
      title: Text(
        editing ? t('openings.editVariation') : t('openings.addOwn'),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Var olan başlıklar yazarken öneriliyor; öneri seçmek
            // zorunlu değil, yeni bir başlık da yazılabilir.
            RawAutocomplete<String>(
              textEditingController: _family,
              focusNode: _familyFocus,
              optionsBuilder: _familyOptions,
              optionsViewBuilder: _familyOptionsView,
              fieldViewBuilder: (context, controller, focusNode, onSubmit) =>
                  TextField(
                controller: controller,
                focusNode: focusNode,
                onSubmitted: (_) => onSubmit(),
                decoration: InputDecoration(
                  labelText: t('openings.family'),
                  hintText: t('openings.familyHint'),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _name,
              decoration: InputDecoration(
                labelText: t('openings.variationName'),
                hintText: t('openings.variationHint'),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _moves,
              // Başlık hazır geldiyse sıra hamlelerde.
              autofocus: widget.initialFamily != null,
              maxLines: 5,
              minLines: 3,
              style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
              decoration: InputDecoration(
                labelText: t('openings.moves'),
                hintText: t('openings.movesHint'),
                // Düzenlerken tek varyant; birden çok varyant yalnızca
                // eklerken.
                helperText: editing ? null : t('openings.movesHelp'),
                helperMaxLines: 4,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t('common.cancel')),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop<_EditorResult>(context, (
            family: _family.text.trim(),
            name: _name.text.trim(),
            moves: _moves.text,
          )),
          child: Text(editing ? t('common.save') : t('common.add')),
        ),
      ],
    );
  }
}
