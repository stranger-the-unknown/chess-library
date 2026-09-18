import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_strings.dart';
import '../models/playlist.dart';
import '../models/stored_review.dart';

/// Oyun listelerini cihazda saklar.
///
/// Listeler kimlikle (id) adreslenir; böylece bir liste yeniden
/// adlandırıldığında içindeki oyunlar kaybolmaz.
///
/// Bir [ChangeNotifier]'dır: veri değiştiğinde açık ekranlar haberdar olur
/// ve kendini tazeler (ör. PGN dosyasından yeni liste oluşturulduğunda
/// "Listelerim" sekmesi anında güncellenir).
class StorageService extends ChangeNotifier {
  static final StorageService instance = StorageService._();
  StorageService._();

  static const _key = 'playlists_v2';
  static const _legacyKey = 'playlists';

  /// Analiz listeleri ayrı anahtarda.
  ///
  /// İki sebeple: yedeğe girmemeleri gerekiyor (yüz oyunun hamle hamle
  /// değerlendirmesi yedeği gereksiz şişirirdi) ve uygulamayı sıfırlama
  /// onları da götürmeli. Ayrı anahtar ikisini de kendiliğinden
  /// sağlıyor; tek anahtarda olsalardı her iki yerde de elle ayıklamak
  /// gerekirdi.
  static const analysisKey = 'analysis_lists_v1';

  /// Tek sabit analiz listesi (eski `sys_deep` / `sys_quick` birleşimi).
  static const analysisListId = 'sys_analysis';

  /// Eski kimlikler — yalnızca yüklemede birleştirme için.
  static const deepListId = 'sys_deep';
  static const quickListId = 'sys_quick';

  /// Analiz listesinde tutulan en fazla kayıt sayısı.
  static const analysisLimit = 100;

  List<Playlist>? _cache;
  List<Playlist>? _analysisCache;

  /// Bellekteki önbelleği boşaltır ve açık ekranları uyarır.
  ///
  /// Yedek geri yüklendiğinde ve testlerde soğuk başlangıç için kullanılır.
  void resetCache() {
    _cache = null;
    _analysisCache = null;
    notifyListeners();
  }

  /// Çakışan oyun kimliklerini onarır; bir şey değiştiyse true döner.
  bool _repairDuplicateIds(List<Playlist> playlists) {
    bool changed = false;
    final seen = <String>{};
    for (final playlist in playlists) {
      for (int i = 0; i < playlist.games.length; i++) {
        final game = playlist.games[i];
        if (seen.add(game.id)) continue;
        playlist.games[i] = SavedGame(
          name: game.name,
          uciMoves: game.uciMoves,
          createdAt: game.createdAt,
          result: game.result,
          startFen: game.startFen,
          white: game.white,
          black: game.black,
          note: game.note,
          read: game.read,
          favorite: game.favorite,
          tags: game.tags,
        );
        seen.add(playlist.games[i].id);
        changed = true;
      }
    }
    return changed;
  }

  /// Kullanıcının kendi listeleri.
  Future<List<Playlist>> loadPlaylists() async {
    if (_cache != null) return _cache!;
    final prefs = await SharedPreferences.getInstance();

    final raw = prefs.getString(_key);
    if (raw != null) {
      _cache = (jsonDecode(raw) as List)
          .map((e) => Playlist.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      if (_repairDuplicateIds(_cache!)) await _save(notify: false);
      return _cache!;
    }

    final legacy = prefs.getString(_legacyKey);
    if (legacy != null) {
      _cache = (jsonDecode(legacy) as List)
          .map((e) => Playlist.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      await _save(notify: false);
      await prefs.remove(_legacyKey);
      return _cache!;
    }

    _cache = <Playlist>[];
    return _cache!;
  }

  /// Tek sabit analiz listesi: "Son Analizler".
  ///
  /// Eski `sys_deep` / `sys_quick` varsa oyunları birleştirir (kimliğe göre
  /// tekilleştirir), eski listeleri bırakır.
  Future<List<Playlist>> loadAnalysisLists() async {
    if (_analysisCache != null) return _analysisCache!;
    final prefs = await SharedPreferences.getInstance();
    final lists = <Playlist>[];
    final raw = prefs.getString(analysisKey);
    if (raw != null) {
      lists.addAll((jsonDecode(raw) as List)
          .map((e) => Playlist.fromJson(Map<String, dynamic>.from(e as Map))));
    }

    Playlist? analysis;
    final legacyGames = <SavedGame>[];
    var migrated = false;

    for (final p in lists) {
      if (p.id == analysisListId) {
        analysis = p;
      } else if (p.id == deepListId || p.id == quickListId) {
        legacyGames.addAll(p.games);
        migrated = true;
      }
    }

    analysis ??= Playlist(id: analysisListId, name: analysisListId);

    if (legacyGames.isNotEmpty || migrated) {
      final seen = <String>{for (final g in analysis.games) g.id};
      for (final g in legacyGames) {
        if (seen.add(g.id)) analysis.games.add(g);
      }
      analysis.games.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (analysis.games.length > analysisLimit) {
        analysis.games.removeRange(analysisLimit, analysis.games.length);
      }
    }

    _analysisCache = [analysis];
    if (migrated || !lists.any((p) => p.id == analysisListId)) {
      await _saveAnalysis(notify: false);
    }
    return _analysisCache!;
  }

  /// Kimliğine göre liste; analiz listeleri de bulunur.
  Future<Playlist?> playlistById(String id) async {
    if (isSystemList(id) || id == deepListId || id == quickListId) {
      final lists = await loadAnalysisLists();
      // Eski kimlikler tek listeye yönlendirilir.
      return lists.first;
    }
    final lists = await loadPlaylists();
    for (final playlist in lists) {
      if (playlist.id == id) return playlist;
    }
    return null;
  }

  Future<void> _save({bool notify = true}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(_cache!.map((p) => p.toJson()).toList()),
    );
    if (notify) notifyListeners();
  }

  Future<void> _saveAnalysis({bool notify = true}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      analysisKey,
      jsonEncode(_analysisCache!.map((p) => p.toJson()).toList()),
    );
    if (notify) notifyListeners();
  }

  /// Ekranda gösterilecek liste adı.
  static String displayName(Playlist playlist) {
    if (playlist.id == analysisListId ||
        playlist.id == deepListId ||
        playlist.id == quickListId) {
      return t('analysis.recentList');
    }
    return playlist.name;
  }

  /// Bu liste kullanıcının silemeyeceği bir analiz listesi mi?
  static bool isSystemList(String id) =>
      id == analysisListId || id == deepListId || id == quickListId;

  Future<Playlist> createPlaylist(String name) async {
    final playlists = await loadPlaylists();
    final playlist = Playlist(name: name);
    playlists.add(playlist);
    await _save();
    return playlist;
  }

  Future<void> renamePlaylist(String id, String name) async {
    if (isSystemList(id)) return;
    final playlists = await loadPlaylists();
    final index = playlists.indexWhere((p) => p.id == id);
    if (index == -1) return;
    playlists[index].name = name;
    await _save();
  }

  Future<void> deletePlaylist(String id) async {
    if (isSystemList(id)) return;
    final playlists = await loadPlaylists();
    playlists.removeWhere((p) => p.id == id);
    await _save();
  }

  Future<void> addGame(String playlistId, SavedGame game) =>
      addGames(playlistId, [game]);

  Future<int> addGames(String playlistId, List<SavedGame> games) async {
    if (games.isEmpty) return 0;
    final playlists = await loadPlaylists();
    final index = playlists.indexWhere((p) => p.id == playlistId);
    if (index == -1) return 0;
    playlists[index].games.addAll(games);
    await _save();
    return games.length;
  }

  Future<Playlist> createPlaylistWithGames(
    String name,
    List<SavedGame> games,
  ) async {
    final playlists = await loadPlaylists();
    final playlist = Playlist(name: name, games: List<SavedGame>.from(games));
    playlists.add(playlist);
    await _save();
    return playlist;
  }

  Future<void> updateGame(String playlistId, SavedGame game) async {
    final playlists = await loadPlaylists();
    final playlist = playlists.firstWhere(
      (p) => p.id == playlistId,
      orElse: () => Playlist(name: ''),
    );
    final index = playlist.games.indexWhere((g) => g.id == game.id);
    if (index == -1) return;
    playlist.games[index] = game;
    await _save();
  }

  /// Bir analizin sonucunu tek listenin başına ekler.
  Future<void> addAnalysis({
    required SavedGame source,
    String? sourcePlaylistId,
    required StoredReview review,
  }) async {
    final lists = await loadAnalysisLists();
    final target = lists.firstWhere((p) => p.id == analysisListId);

    target.games.insert(
      0,
      SavedGame(
        name: source.name,
        uciMoves: List<String>.from(source.uciMoves),
        createdAt: DateTime.now(),
        result: source.result,
        startFen: source.startFen,
        white: source.white,
        black: source.black,
        tags: source.tags,
        review: review,
        sourceGameId: sourcePlaylistId == null ? null : source.id,
        sourcePlaylistId: sourcePlaylistId,
      ),
    );
    if (target.games.length > analysisLimit) {
      target.games.removeRange(analysisLimit, target.games.length);
    }
    await _saveAnalysis();
  }

  Future<SavedGame?> _findGame(String playlistId, String gameId) async {
    final playlist = await playlistById(playlistId);
    if (playlist == null) return null;
    for (final game in playlist.games) {
      if (game.id == gameId) return game;
    }
    return null;
  }

  Future<void> _persist(String playlistId) =>
      isSystemList(playlistId) ? _saveAnalysis() : _save();

  Future<void> _mirrorToSource(
    SavedGame game, {
    bool? read,
    bool? favorite,
  }) async {
    final listId = game.sourcePlaylistId;
    final gameId = game.sourceGameId;
    if (listId == null || gameId == null) return;
    if (isSystemList(listId)) return;

    final source = await _findGame(listId, gameId);
    if (source == null) return;
    if (read != null) source.read = read;
    if (favorite != null) source.favorite = favorite;
    await _save();
  }

  Future<bool> toggleGameRead(String playlistId, String gameId) async {
    final game = await _findGame(playlistId, gameId);
    if (game == null) return false;
    game.read = !game.read;
    await _persist(playlistId);
    await _mirrorToSource(game, read: game.read);
    return game.read;
  }

  Future<void> setAllRead(String playlistId, bool read) async {
    final playlists = await loadPlaylists();
    final index = playlists.indexWhere((p) => p.id == playlistId);
    if (index == -1) return;
    for (final game in playlists[index].games) {
      game.read = read;
    }
    await _save();
  }

  Future<bool> toggleGameFavorite(String playlistId, String gameId) async {
    final game = await _findGame(playlistId, gameId);
    if (game == null) return false;
    game.favorite = !game.favorite;
    await _persist(playlistId);
    await _mirrorToSource(game, favorite: game.favorite);
    return game.favorite;
  }

  Future<int> markManyRead(
    String playlistId,
    Iterable<String> gameIds, {
    required bool read,
  }) async {
    final playlists = await loadPlaylists();
    final index = playlists.indexWhere((p) => p.id == playlistId);
    if (index == -1) return 0;
    final wanted = gameIds.toSet();
    int changed = 0;
    for (final game in playlists[index].games) {
      if (!wanted.contains(game.id)) continue;
      if (game.read == read) continue;
      game.read = read;
      changed++;
    }
    if (changed > 0) await _save();
    return changed;
  }

  Future<void> deleteGame(String playlistId, String gameId) async {
    final playlists = await loadPlaylists();
    final index = playlists.indexWhere((p) => p.id == playlistId);
    if (index == -1) return;
    playlists[index].games.removeWhere((g) => g.id == gameId);
    await _save();
  }

  Future<void> moveGame(
    String fromPlaylistId,
    String toPlaylistId,
    String gameId,
  ) async {
    if (fromPlaylistId == toPlaylistId) return;
    final playlists = await loadPlaylists();
    final from = playlists.indexWhere((p) => p.id == fromPlaylistId);
    final to = playlists.indexWhere((p) => p.id == toPlaylistId);
    if (from == -1 || to == -1) return;
    final index = playlists[from].games.indexWhere((g) => g.id == gameId);
    if (index == -1) return;
    final game = playlists[from].games.removeAt(index);
    playlists[to].games.add(game);
    await _save();
  }
}
