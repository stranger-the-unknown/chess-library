import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_strings.dart';
import '../models/playlist.dart';

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

  List<Playlist>? _cache;

  /// Bellekteki önbelleği boşaltır ve açık ekranları uyarır.
  ///
  /// Yedek geri yüklendiğinde ve testlerde soğuk başlangıç için kullanılır.
  void resetCache() {
    _cache = null;
    notifyListeners();
  }

  Future<List<Playlist>> loadPlaylists() async {
    if (_cache != null) return _cache!;
    final prefs = await SharedPreferences.getInstance();

    final raw = prefs.getString(_key);
    if (raw != null) {
      _cache = (jsonDecode(raw) as List)
          .map((e) => Playlist.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      return _cache!;
    }

    // Eski sürümden geçiş: aynı biçim, kimlikler otomatik üretilir.
    final legacy = prefs.getString(_legacyKey);
    if (legacy != null) {
      _cache = (jsonDecode(legacy) as List)
          .map((e) => Playlist.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      await _save();
      await prefs.remove(_legacyKey);
      return _cache!;
    }

    _cache = <Playlist>[];
    return _cache!;
  }

  Future<void> _save({bool notify = true}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(_cache!.map((p) => p.toJson()).toList()),
    );
    if (notify) notifyListeners();
  }

  Future<Playlist> createPlaylist(String name) async {
    final playlists = await loadPlaylists();
    final playlist = Playlist(name: name);
    playlists.add(playlist);
    await _save();
    return playlist;
  }

  Future<void> renamePlaylist(String id, String name) async {
    final playlists = await loadPlaylists();
    final index = playlists.indexWhere((p) => p.id == id);
    if (index == -1) return;
    playlists[index].name = name;
    await _save();
  }

  Future<void> deletePlaylist(String id) async {
    final playlists = await loadPlaylists();
    playlists.removeWhere((p) => p.id == id);
    await _save();
  }

  Future<void> addGame(String playlistId, SavedGame game) =>
      addGames(playlistId, [game]);

  /// Birden çok oyunu **tek yazma** ile ekler.
  ///
  /// Oyunları teker teker eklemek, her seferinde tüm listelerin yeniden
  /// kodlanıp diske yazılması demekti; yüzlerce oyunluk bir PGN dosyasında
  /// bu, bekleme süresini kare oranında büyütüyordu. Eklenen sayıyı döner.
  Future<int> addGames(String playlistId, List<SavedGame> games) async {
    if (games.isEmpty) return 0;
    final playlists = await loadPlaylists();
    final index = playlists.indexWhere((p) => p.id == playlistId);
    if (index == -1) return 0;
    playlists[index].games.addAll(games);
    await _save();
    return games.length;
  }

  /// Yeni bir liste oluşturup oyunları tek yazmada içine koyar.
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

  /// Bir oyunun "okundu" işaretini değiştirir ve yeni değeri döner.
  Future<bool> toggleGameRead(String playlistId, String gameId) async {
    final playlists = await loadPlaylists();
    final index = playlists.indexWhere((p) => p.id == playlistId);
    if (index == -1) return false;
    final games = playlists[index].games;
    final gameIndex = games.indexWhere((g) => g.id == gameId);
    if (gameIndex == -1) return false;
    games[gameIndex].read = !games[gameIndex].read;
    await _save();
    return games[gameIndex].read;
  }

  /// Listedeki tüm oyunları okundu / okunmadı yapar.
  Future<void> setAllRead(String playlistId, bool read) async {
    final playlists = await loadPlaylists();
    final index = playlists.indexWhere((p) => p.id == playlistId);
    if (index == -1) return;
    for (final game in playlists[index].games) {
      game.read = read;
    }
    await _save();
  }

  /// Bir oyunun favori durumunu değiştirir; yeni durumu döner.
  Future<bool> toggleGameFavorite(String playlistId, String gameId) async {
    final playlists = await loadPlaylists();
    final index = playlists.indexWhere((p) => p.id == playlistId);
    if (index == -1) return false;
    final games = playlists[index].games;
    final gameIndex = games.indexWhere((g) => g.id == gameId);
    if (gameIndex == -1) return false;
    games[gameIndex].favorite = !games[gameIndex].favorite;
    await _save();
    return games[gameIndex].favorite;
  }

  /// Verilen oyunları toplu olarak okundu/okunmadı işaretler.
  ///
  /// Aralık işaretlemede tek tek çağırmak her seferinde tüm listeleri
  /// yeniden kodlayıp diske yazardı; burada tek yazma yapılır.
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

  /// Tüm verinin yedeği (JSON metni).
  Future<String> exportAll() async {
    final playlists = await loadPlaylists();
    return jsonEncode({
      'version': 2,
      'exportedAt': DateTime.now().toIso8601String(),
      'playlists': playlists.map((p) => p.toJson()).toList(),
    });
  }

  /// Yedeği geri yükler; eklenen liste sayısını döner.
  Future<int> importAll(String json) async {
    final data = jsonDecode(json);
    final list = data is Map ? data['playlists'] : data;
    if (list is! List) {
      throw FormatException(t('lists.invalidBackup'));
    }
    final playlists = await loadPlaylists();
    int added = 0;
    for (final entry in list) {
      final playlist = Playlist.fromJson(
        Map<String, dynamic>.from(entry as Map),
      );
      playlists.add(playlist);
      added++;
    }
    await _save();
    return added;
  }
}
