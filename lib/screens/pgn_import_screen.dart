import 'package:flutter/material.dart';

import '../widgets/responsive.dart';

import '../l10n/app_strings.dart';
import '../models/pgn_parser.dart';
import '../models/playlist.dart';
import '../services/pgn_import_service.dart';
import '../services/storage_service.dart';
import '../widgets/app_dialogs.dart';
import 'game_screen.dart';
import '../widgets/cursors.dart';

/// Bir PGN dosyasındaki oyunları listeler; seçilenleri kaydeder ya da açar.
class PgnImportScreen extends StatefulWidget {
  final List<PgnGame> games;

  /// Yeni liste adı önerisi (dosya adından üretilir).
  final String suggestedName;

  const PgnImportScreen({
    super.key,
    required this.games,
    required this.suggestedName,
  });

  @override
  State<PgnImportScreen> createState() => _PgnImportScreenState();
}

class _PgnImportScreenState extends State<PgnImportScreen> {
  late final Set<int> _selected = Set<int>.from(
    List<int>.generate(widget.games.length, (i) => i),
  );
  bool _saving = false;

  /// Okunamayan hamlesi olan oyunlar listeden gizlensin mi?
  ///
  /// Gizlenenler seçimden de düşüyor, yani kaydedilmiyorlar. Süzgeç
  /// kapatılınca eski seçimleri geri geliyor: seçim kümesi hiç
  /// değiştirilmiyor, yalnızca görünenlerle kesiştiriliyor.
  bool _hidePartial = false;

  /// Hamlesi eksik okunan oyun sayısı.
  int get _partialCount =>
      widget.games.where((g) => g.skippedCount > 0).length;

  /// Listede gösterilen oyunların sıra numaraları.
  List<int> get _shown => [
        for (int i = 0; i < widget.games.length; i++)
          if (!_hidePartial || widget.games[i].skippedCount == 0) i,
      ];

  List<PgnGame> get _selectedGames => [
        for (final i in _shown)
          if (_selected.contains(i)) widget.games[i],
      ];

  void _toggleAll() {
    final shown = _shown;
    setState(() {
      if (shown.every(_selected.contains)) {
        _selected.removeAll(shown);
      } else {
        _selected.addAll(shown);
      }
    });
  }

  Future<void> _openGame(PgnGame game) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GameScreen(
          uciMoves: game.uciMoves,
          startFen: game.startFen,
          title: game.title,
          initialResult: game.result,
          whiteName: game.white == '?' ? null : game.white,
          blackName: game.black == '?' ? null : game.black,
        ),
      ),
    );
  }

  Future<void> _saveAsNewList() async {
    final games = _selectedGames;
    if (games.isEmpty) return;

    final name = await AppDialogs.prompt(
      context,
      title: t('pgn.saveAsNewList'),
      label: t('game.listName'),
      initialValue: widget.suggestedName,
    );
    if (name == null || !mounted) return;

    setState(() => _saving = true);
    try {
      await PgnImportService.saveAsNewList(name, games);
    } catch (_) {
      // Disk dolduğunda yazma başarısız oluyor. Eskiden hata hiç
      // yakalanmıyordu: çark sonsuza kadar dönüyor, kullanıcı ne
      // "kaydedildi" ne de bir hata görüyordu.
      if (!mounted) return;
      setState(() => _saving = false);
      AppDialogs.snack(context, t('lists.saveFailed'));
      return;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    AppDialogs.snack(context, t('pgn.saved', {'count': games.length}));
    Navigator.pop(context, true);
  }

  Future<void> _addToExisting() async {
    final games = _selectedGames;
    if (games.isEmpty) return;

    final playlists = await StorageService.instance.loadPlaylists();
    if (!mounted) return;
    if (playlists.isEmpty) {
      AppDialogs.snack(context, t('pgn.noListYet'));
      return;
    }

    final target = await showDialog<Playlist>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(t('pgn.chooseList')),
        children: [
          for (final playlist in playlists)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, playlist),
              child: Text(
                '${playlist.name}  ·  '
                '${t('lists.gameCount', {'count': playlist.games.length})}',
              ),
            ),
        ],
      ),
    );
    if (target == null || !mounted) return;

    setState(() => _saving = true);
    final int added;
    try {
      added = await PgnImportService.addToList(target.id, games);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppDialogs.snack(context, t('lists.saveFailed'));
      return;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    AppDialogs.snack(context, t('pgn.saved', {'count': added}));
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = _shown;
    final allSelected = shown.isNotEmpty && shown.every(_selected.contains);

    return Scaffold(
      appBar: AppBar(
        title: Text(t('pgn.importTitle')),
        actions: [
          // Süzgeç çipiyle karışmasın diye simgeli: bu bir eylem,
          // aşağıdaki ise listeyi daraltan bir anahtar.
          TextButton.icon(
            onPressed: _toggleAll,
            icon: Icon(
              allSelected
                  ? Icons.remove_done_rounded
                  : Icons.checklist_rtl_rounded,
              size: 20,
            ),
            label: Text(
              allSelected ? t('pgn.clearSelection') : t('pgn.selectAll'),
            ),
          ),
        ],
      ),
      // Liste tüm genişliği kaplıyor, ortalama kendi dolgusuyla
      // yapılıyor: aksi hâlde kaydırma alanı da daralıyor ve imleç
      // pencerenin kenarına yakınken fare tekerleği hiçbir şey yapmıyor.
      // Üstteki özet, süzgeç ve alttaki düğmeler kaydırılmadığı için
      // eskisi gibi ortalanmış duruyor.
      body: Column(
        children: [
          ContentWidth(
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                t('pgn.foundGames', {
                  'count': widget.games.length,
                  'selected': _selectedGames.length,
                }),
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSecondaryContainer,
                ),
              ),
            ),
          ),
          if (_partialCount > 0)
            ContentWidth(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  child: FilterChip(
                    selected: _hidePartial,
                    showCheckmark: false,
                    avatar: Icon(
                      _hidePartial
                          ? Icons.filter_alt_rounded
                          : Icons.filter_alt_off_rounded,
                      size: 18,
                    ),
                    label: Text(
                      t('pgn.hidePartial', {'count': _partialCount}),
                      style: const TextStyle(fontSize: 12.5),
                    ),
                    onSelected: (value) =>
                        setState(() => _hidePartial = value),
                  ),
                ),
              ),
            ),
          Expanded(
            child: ContentInset(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              builder: (context, padding) => ListView.builder(
                key: const Key('pgnGameList'),
                padding: padding,
                itemCount: shown.length,
                itemBuilder: (context, index) => _gameTile(
                  shown[index],
                  widget.games[shown[index]],
                  scheme,
                ),
              ),
            ),
          ),
          ContentWidth(
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        // Kaydedilecek küme `_selectedGames`; süzgeç
                        // açıkken seçili ama gizli oyunlar buna girmiyor.
                        // Düğmeler `_selected`e bakarsa, gizlenen oyunlar
                        // yüzünden kaydedilecek bir şey kalmadığında bile
                        // etkin görünüp hiçbir şey yapmıyorlar.
                        onPressed: _saving || _selectedGames.isEmpty
                            ? null
                            : _addToExisting,
                        icon: const Icon(Icons.playlist_add_rounded, size: 20),
                        label: Text(t('pgn.addToList')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _saving || _selectedGames.isEmpty
                            ? null
                            : _saveAsNewList,
                        icon: const Icon(
                          Icons.create_new_folder_outlined,
                          size: 20,
                        ),
                        label: Text(t('pgn.newList')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _gameTile(int index, PgnGame game, ColorScheme scheme) {
    final selected = _selected.contains(index);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: 0.12)
            : scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          mouseCursor: kClickable,
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() {
            if (selected) {
              _selected.remove(index);
            } else {
              _selected.add(index);
            }
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                Icon(
                  selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  size: 22,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        game.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            t('lists.moveCount', {'count': game.moveCount}),
                            style: TextStyle(
                              fontSize: 11.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          if (game.result != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              game.result == '1/2-1/2' ? '½-½' : game.result!,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                          if (game.subtitle.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                game.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (game.skippedCount > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            t('pgn.partial', {'count': game.skippedCount}),
                            style: TextStyle(fontSize: 11, color: scheme.error),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: t('pgn.preview'),
                  icon: const Icon(Icons.play_circle_outline_rounded),
                  onPressed: () => _openGame(game),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
