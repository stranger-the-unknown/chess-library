import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../widgets/filter_strip.dart';
import '../widgets/responsive.dart';

import 'package:flutter/services.dart';

import '../l10n/app_strings.dart';
import '../models/game_filter.dart';
import '../models/pgn_parser.dart';
import '../models/playlist.dart';
import '../models/puzzle_search.dart';
import '../services/file_pick.dart';
import '../services/pgn_import_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_dialogs.dart';
import 'pgn_import_screen.dart';
import '../widgets/game_filter_dialog.dart';
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

  /// Oyuncu ve sonuç süzgeci; üç nokta menüsünden kuruluyor.
  GameFilter _gameFilter = GameFilter.none;
  /// Liste kitaptaki sırayla gelir; ok bunu tersine çevirir.
  bool _descending = false;

  /// Yalnızca bu numara aralığındaki oyunlar listelenir; null ise hepsi.
  (int, int)? _range;

  /// Toplu analiz için seçim kipi ve seçilen oyunlar.
  ///
  /// Seçim kipi ayrı bir kip: satıra dokunmak normalde oyunu açıyor,
  /// seçim kipinde ise işaretliyor. İki davranışı aynı anda vermek
  /// (uzun basma gibi) telefonda yanlış dokunuşa çok açık.

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
    // playlistById analiz listelerini de buluyor; yalnızca
    // loadPlaylists()'e bakmak analiz listelerini boş gösteriyordu.
    final playlist = await _storage.playlistById(widget.playlistId);
    if (!mounted) return;

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
          whiteName: game.white,
          blackName: game.black,
        ),
      ),
    );
    await _load();
  }

  /// Numara sütununun genişliği.
  ///
  /// Listedeki en büyük numaranın hane sayısına göre; böylece üç haneli
  /// bir listede de, beş oyunluk bir listede de adlar aynı hizadan
  /// başlıyor ve boşuna yer kaplamıyor.
  double get _numberWidth {
    var digits = 1;
    for (final number in _numbers.values) {
      digits = math.max(digits, number.toString().length);
    }
    return 8.0 * digits + 12;
  }

  /// Diske yazan bir işi çalıştırır; başarısız olursa kullanıcıya söyler.
  ///
  /// `StorageService._save` cihazda yer kalmadığında hata fırlatıyor.
  /// Liste **içindeki** işlemler (ad değiştir, sil, taşı, okundu, PGN
  /// ekle) bunu yakalamıyordu; ana liste ekranı 9.0.8'de kapatılmıştı.
  Future<bool> _guard(Future<void> Function() task) async {
    try {
      await task();
      return true;
    } catch (_) {
      if (mounted) AppDialogs.snack(context, t('lists.saveFailed'));
      return false;
    }
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
    await _guard(() => _storage.updateGame(widget.playlistId, game));
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
    await _guard(() => _storage.deleteGame(widget.playlistId, game.id));
    await _load();
  }

  Future<void> _copyPgn(SavedGame game) async {
    final tags = Map<String, String>.from(game.tags);
    if (game.white != null && game.white!.trim().isNotEmpty) {
      tags['White'] = game.white!;
    }
    if (game.black != null && game.black!.trim().isNotEmpty) {
      tags['Black'] = game.black!;
    }
    if ((tags['Event'] ?? '').trim().isEmpty) {
      tags['Event'] = game.name;
    }
    final pgn = PgnParser.buildPgn(
      uciMoves: game.uciMoves,
      startFen: game.startFen,
      result: game.result,
      tags: tags,
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
    await _guard(() => _storage.moveGame(widget.playlistId, target, game.id));
    await _load();
  }

  /// Bir PGN dosyasındaki tüm oyunları bu listeye ekler.
  Future<void> _importPgnFile() async {
    final PickedPgn? picked;
    try {
      picked = await PgnImportService.pickFile();
    } catch (error) {
      if (mounted) AppDialogs.snack(context, pickFailureMessage(error));
      return;
    }
    if (!mounted || picked == null) return;

    final content = picked.content;
    final suggested = picked.suggestedListName;
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

    // Seçim ekranından geçiliyor: eksik okunan oyunlar orada işaretsiz
    // geliyor ve kullanıcı ne kaydettiğini görüyor. Eskiden buradan
    // alınan dosyada hepsi doğrudan listeye yazılıyordu — sapmış
    // oyunlar dahil.
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PgnImportScreen(
          games: games,
          suggestedName: suggested,
        ),
      ),
    );
    await _load();
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

    final matched = games.where((game) {
      final range = _range;
      if (range != null) {
        final number = _numbers[game.id];
        if (number == null || number < range.$1 || number > range.$2) {
          return false;
        }
      }
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
      if (!_gameFilter.matches(game)) return false;
      if (query.isEmpty) return true;

      // Yalnızca rakam yazıldıysa arama sıra numarasıyla sınırlı kalır.
      // Eskiden metne de bakılıyordu ve "1" yazınca adında 1 geçen her
      // oyun çıkıyordu; kullanıcı 1 ile başlayan numaraları arıyordu.
      final digits = query.replaceAll('#', '');
      if (digits.isNotEmpty && int.tryParse(digits) != null) {
        final number = _numbers[game.id];
        return number != null && '$number'.startsWith(digits);
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
    return _descending ? matched.reversed.toList() : matched;
  }

  /// PGN başlıklarını okunur bir pencerede gösterir.
  ///
  /// Turnuva, yer, tarih, tur, ECO gibi bilgiler PGN'de duruyordu ama
  /// hiçbir yerde görünmüyordu.
  Future<void> _showInfo(SavedGame game) async {
    // Bilinen başlıklar önce ve tanıdık sırayla; gerisi alfabetik.
    const order = [
      'Event',
      'Site',
      'Date',
      'Round',
      'White',
      'Black',
      'Result',
      'ECO',
      'Opening',
      'WhiteElo',
      'BlackElo',
      'TimeControl',
    ];
    final tags = Map<String, String>.from(game.tags);
    final rows = <MapEntry<String, String>>[
      for (final key in order)
        if ((tags.remove(key) ?? '').trim().isNotEmpty ||
            (game.tags[key] ?? '').trim().isNotEmpty)
          MapEntry(key, game.tags[key]!),
      ...(tags.entries.toList()..sort((a, b) => a.key.compareTo(b.key))),
    ]..removeWhere((e) => e.value.trim().isEmpty || e.value.trim() == '?');

    if (!mounted) return;
    final scheme = Theme.of(context).colorScheme;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t('lists.gameInfo')),
        content: rows.isEmpty
            ? Text(t('lists.gameInfoEmpty'))
            : SizedBox(
                width: 360,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final row in rows)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 110,
                                child: Text(
                                  row.key,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: SelectableText(
                                  row.value,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(t('common.close')),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleRead(SavedGame game) async {
    await _guard(() => _storage.toggleGameRead(widget.playlistId, game.id));
  }

  Future<void> _setAllRead(bool read) async {
    await _guard(() => _storage.setAllRead(widget.playlistId, read));
  }

  Future<void> _toggleFavorite(SavedGame game) async {
    await _guard(() => _storage.toggleGameFavorite(widget.playlistId, game.id));
  }

  /// Oyunun notunu siler.
  ///
  /// Not ekrandan kalkıyor; ayrıca bir bildirim göstermeye gerek yok.
  Future<void> _deleteNote(SavedGame game) async {
    game.note = null;
    await _guard(() => _storage.updateGame(widget.playlistId, game));
  }

  /// Sıra numarası aralığındaki oyunları okundu/okunmadı yapar.
  ///
  /// Numaralar süzgeçten bağımsızdır; kullanıcı satırda gördüğü numarayı
  /// yazar.


  /// Seçilen oyunları toplu analize gönderir.
  /// Seçilen oyunları kuyruğa verir; sıra [analysisOrder] ile kuruluyor.

  /// Listeyi bir numara aralığına daraltır.
  Future<void> _pickRange() async {
    final games = _playlist?.games ?? const <SavedGame>[];
    if (games.isEmpty) return;
    final numbers = games.map((g) => _numbers[g.id] ?? 0).toList()..sort();

    final result = await showDialog<(int, int, bool)>(
      context: context,
      builder: (dialogContext) => RangeDialog(
        title: t('lists.showRange'),
        min: numbers.first,
        max: numbers.last,
        hint: t('lists.rangeHint', {
          'min': numbers.first,
          'max': numbers.last,
        }),
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _range = (result.$1, result.$2));
  }

  Future<void> _markRange() async {
    final games = _playlist?.games ?? const <SavedGame>[];
    if (games.isEmpty) return;
    final numbers = games.map((g) => _numbers[g.id] ?? 0).toList()..sort();

    final result = await showDialog<(int, int, bool)>(
      context: context,
      builder: (dialogContext) => RangeDialog(
        title: t('lists.markRange'),
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
    final visible = _visible;

    return Scaffold(
      appBar: AppBar(
        // Analiz listesinin adı uzun ("Son Analizler"); telefonda
        // başlık çubuğuna sığmıyordu. Sığmadığında küçülüyor, kırpılmıyor.
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            playlist == null ? t('game.list') : playlist.name,
          ),
        ),
        actions: [
          IconButton(
            tooltip: _descending
                ? t('puzzles.sortOldest')
                : t('puzzles.sortNewest'),
            icon: Icon(
              _descending
                  ? Icons.arrow_downward_rounded
                  : Icons.arrow_upward_rounded,
            ),
            onPressed: () => setState(() => _descending = !_descending),
          ),
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
              if (value == 'showRange') _pickRange();
              if (value == 'filter') _pickFilter();
              
            },
            itemBuilder: (context) => [
              ...[
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
              PopupMenuItem(
                value: 'filter',
                child: Text(t('lists.filterGames')),
              ),
              PopupMenuItem(
                value: 'showRange',
                child: Text(t('lists.showRange')),
              ),
            ],
          ),
        ],
        bottom: total == 0
            ? null
            // Arama kutusu ile süzgeç şeridinin genişliği birbirine
            // bağlı: geniş pencerede kutu şeritten biraz uzun duruyor.
            : PreferredSize(
                preferredSize: const Size.fromHeight(104),
                child: ListToolbar(
                  search: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) => setState(() => _query = value),
                      decoration: InputDecoration(
                        hintText: t('lists.search'),
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
                      selected: _filter == _GameFilter.all,
                      onTap: () => _selectFilter(_GameFilter.all),
                    ),
                    FilterOption(
                      label: t('lists.filterUnread'),
                      selected: _filter == _GameFilter.unread,
                      onTap: () => _selectFilter(_GameFilter.unread),
                    ),
                    FilterOption(
                      label: t('lists.filterRead'),
                      selected: _filter == _GameFilter.read,
                      onTap: () => _selectFilter(_GameFilter.read),
                    ),
                    FilterOption(
                      label: t('common.favorites'),
                      selected: _filter == _GameFilter.favorites,
                      onTap: () => _selectFilter(_GameFilter.favorites),
                    ),
                  ],
                ),
              ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : total == 0
              ? _emptyState(scheme)
              : Column(
                  children: [
                    if (_range != null) _rangeBanner(scheme),
                    if (_gameFilter.isActive)
                      _filterBanner(scheme, visible.length),
                    Expanded(child: _list(visible, scheme)),
                  ],
                ),
    );
  }

  /// Oyuncu ve sonuç süzgecini soran pencere.
  Future<void> _pickFilter() async {
    final chosen = await showDialog<GameFilter>(
      context: context,
      builder: (_) => GameFilterDialog(filter: _gameFilter),
    );
    if (chosen == null || !mounted) return;
    setState(() => _gameFilter = chosen);
  }

  /// Şeritte yazan özet: yalnızca doldurulmuş alanlar.
  String get _filterSummary {
    final parts = <String>[];
    final a = _gameFilter.white.trim();
    final b = _gameFilter.black.trim();
    if (_gameFilter.ignoreColor) {
      if (a.isNotEmpty && b.isNotEmpty) {
        parts.add('$a – $b');
      } else if (a.isNotEmpty) {
        parts.add(a);
      } else if (b.isNotEmpty) {
        parts.add(b);
      }
    } else {
      if (a.isNotEmpty) {
        parts.add("${t('lists.filterWhite')}: $a");
      }
      if (b.isNotEmpty) {
        parts.add("${t('lists.filterBlack')}: $b");
      }
    }
    if (_gameFilter.year != null) {
      parts.add('${_gameFilter.year}');
    }
    switch (_gameFilter.result) {
      case ResultFilter.any:
        break;
      case ResultFilter.whiteWins:
        parts.add(t('lists.resultWhiteWins'));
        break;
      case ResultFilter.draw:
        parts.add(t('lists.resultDraw'));
        break;
      case ResultFilter.blackWins:
        parts.add(t('lists.resultBlackWins'));
        break;
      case ResultFilter.playerWins:
        if (_gameFilter.winner.isNotEmpty) {
          parts.add("${t('lists.filterWinner')}: ${_gameFilter.winner}");
        }
        break;
    }
    return parts.join(' · ');
  }

  /// Süzgeç şeridi: ne süzüldüğü ve kaç oyun kaldığı.
  Widget _filterBanner(ColorScheme scheme, int count) {
    return Container(
      width: double.infinity,
      color: scheme.secondaryContainer,
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              "${t('lists.filterActive', {'summary': _filterSummary})}"
              " · ${t('lists.filterMatches', {'count': count})}",
              style: TextStyle(
                fontSize: 12.5,
                color: scheme.onSecondaryContainer,
              ),
            ),
          ),
          IconButton(
            tooltip: t('lists.filterClear'),
            icon: const Icon(Icons.close_rounded, size: 18),
            color: scheme.onSecondaryContainer,
            onPressed: () => setState(() => _gameFilter = GameFilter.none),
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
              t('lists.rangeActive', {'from': range.$1, 'to': range.$2}),
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

  Widget _list(List<SavedGame> visible, ColorScheme scheme) {
    return visible.isEmpty
                  ? Center(
                      child: Text(
                        t('lists.noMatch'),
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    )
                  : ContentInset(
                      // Telefonun gezinme çubuğu ekranın altından yer
                      // kapıyor; son satır oraya denk gelirse tıklanamıyor.
                      padding: EdgeInsets.fromLTRB(
                        16,
                        8,
                        16,
                        28 + MediaQuery.viewPaddingOf(context).bottom,
                      ),
                      builder: (context, padding) => ListView.separated(
                        key: const Key('gameList'),
                        padding: padding,
                        itemCount: visible.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) =>
                            _gameTile(visible[index], scheme),
                      ),
                    );
  }

  /// Süzgeci değiştirir ve sıralamayı varsayılana döndürür.
  ///
  /// Ters sıralama çoğunlukla tek bir bakış için açılıyor; süzgeç
  /// değişince o iş bitmiş oluyor. Bulmaca listesindeki kuralla aynı.
  void _selectFilter(_GameFilter value) {
    if (_filter == value) return;
    setState(() {
      _filter = value;
      _descending = false;
    });
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
        onTap: () =>
            _openGame(game),
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
                    // Numara sabit genişlikte bir sütunda; iki oyuncu adı
                    // onun sağında alt alta. Eskiden numara ile beyazın
                    // adı aynı satırdaydı, siyahın adı ise sabit bir
                    // girintiyle altındaydı: numara bir hane büyüyünce
                    // iki ad birbirinden kayıyordu.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: _numberWidth,
                          child: Text(
                            '${_numbers[game.id] ?? 0}.',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                game.cardWhite.isNotEmpty
                                    ? game.cardWhite
                                    : (game.resolvedWhite ??
                                        (game.name.trim() == '?' ||
                                                game.name.trim().isEmpty
                                            ? 'PGN'
                                            : game.name)),
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
                              if (game.cardBlack.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 1),
                                  child: Text(
                                    game.cardBlack,
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
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Wrap, Row değil: tarih eklendikten sonra dar
                    // ekranlarda satır taşıyordu. Sığmayan parça alta
                    // iniyor, kırpılmıyor.
                    Wrap(
                      spacing: 8,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          t('lists.moveCount', {'count': game.moveCount}),
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        if (game.result != null) _resultChip(game.result!, scheme),
                        // PGN'de tarih varsa; eksikse yalnızca yıl, yıl
                        // da yoksa hiç yazılmıyor.
                        if (game.displayDate != null)
                          Text(
                            game.displayDate!,
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        if (game.startFen != null)
                          Text(
                            t('lists.customPosition'),
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.secondary,
                            ),
                          ),
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
                    case 'info':
                      _showInfo(game);
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
                  ...[
                    PopupMenuItem(
                      value: 'rename',
                      child: Text(t('common.rename')),
                    ),
                    if (game.note != null && game.note!.isNotEmpty)
                      PopupMenuItem(
                        value: 'deleteNote',
                        child: Text(t('common.deleteNote')),
                      ),
                  ],
                  PopupMenuItem(
                    value: 'info',
                    child: Text(t('lists.gameInfo')),
                  ),
                  PopupMenuItem(value: 'pgn', child: Text(t('game.copyPgn'))),
                  ...[
                    PopupMenuItem(
                      value: 'move',
                      child: Text(t('lists.moveToList')),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(t('common.delete')),
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
