import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_store.dart';
import 'corrupt_data.dart';
import 'prefs_write.dart';

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

  /// 9.0.0'da kaldırılan analiz listelerinin anahtarı.
  ///
  /// Özellik gitti; telefonlarda kalan veri kimsenin göremediği bir yer
  /// kaplıyor, ilk açılışta bir kereliğine siliniyor.
  static const _legacyAnalysisKey = 'analysis_lists_v1';

  /// Bellekteki önbelleği boşaltır ve açık ekranları uyarır.
  ///
  /// Yedek geri yüklendiğinde ve testlerde soğuk başlangıç için kullanılır.
  void resetCache() {
    _cache = null;
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
    // Kaldırılan analiz listelerinden kalan veri bir kereliğine gidiyor.
    if (prefs.containsKey(_legacyAnalysisKey)) {
      await prefs.remove(_legacyAnalysisKey);
    }

    final store = AppStore.instance;
    final raw = await store.getString(_key);
    if (raw != null) {
      // Bozuk ya da yarım yazılmış bir kayıt yüzünden "Listelerim"
      // sekmesi hiç açılmasın: çözümlenemeyen veri bir kenara konuyor,
      // uygulama boş listeyle açılıyor. Eski veri silinmiyor, elle
      // kurtarılabilsin diye ayrı bir anahtara taşınıyor.
      try {
        _cache = (jsonDecode(raw) as List)
            .map((e) => Playlist.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      } catch (_) {
        await store.setString('$_key${AppStore.quarantineSuffix}', raw);
        await store.remove(_key);
        corruptRecords.value++;
        _cache = <Playlist>[];
        return _cache!;
      }
      if (_repairDuplicateIds(_cache!)) await _save(notify: false);
      return _cache!;
    }

    final legacy = await store.getString(_legacyKey);
    if (legacy != null) {
      // v2 kaydı 9.0.3'te korunmuştu; eski anahtar açıkta kalmıştı.
      _cache = await readOrQuarantine<List<Playlist>>(
        _legacyKey,
        legacy,
        (decoded) => (decoded as List)
            .map((e) => Playlist.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        () => <Playlist>[],
      );
      await _save(notify: false);
      await store.remove(_legacyKey);
      return _cache!;
    }

    _cache = <Playlist>[];
    return _cache!;
  }

  /// Kimliğine göre liste.
  Future<Playlist?> playlistById(String id) async {
    final lists = await loadPlaylists();
    for (final playlist in lists) {
      if (playlist.id == id) return playlist;
    }
    return null;
  }

  /// Diske yazar; yazma başarısız olursa bir kez daha dener.
  ///
  /// `setString` disk dolduğunda ya da depo kilitliyken `false` dönüyor
  /// ve eskiden bu sessizce yutuluyordu: kullanıcı kaydettiğini sanıp
  /// veriyi kaybedebilirdi. Şimdi tekrar deniyor, yine olmazsa hata
  /// fırlatıyor — çağıran yolun sessizce "kaydedildi" demesindense
  /// görünür bir hata iyidir.
  Future<void> _save({bool notify = true}) async {
    final payload = jsonEncode(_cache!.map((p) => p.toJson()).toList());
    final ok = await writeString(_key, payload);
    if (!ok) throw StateError('listeler diske yazılamadı');
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

  Future<SavedGame?> _findGame(String playlistId, String gameId) async {
    final playlist = await playlistById(playlistId);
    if (playlist == null) return null;
    for (final game in playlist.games) {
      if (game.id == gameId) return game;
    }
    return null;
  }

  Future<bool> toggleGameRead(String playlistId, String gameId) async {
    final game = await _findGame(playlistId, gameId);
    if (game == null) return false;
    game.read = !game.read;
    await _save();
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
    await _save();
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
