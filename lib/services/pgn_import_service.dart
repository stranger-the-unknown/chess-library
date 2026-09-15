import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';

import 'package:flutter/foundation.dart';

import '../models/pgn_parser.dart';
import '../models/playlist.dart';
import 'storage_service.dart';

/// PGN dosyalarını açar ve içindeki oyunları listelere kaydeder.
class PgnImportService {
  PgnImportService._();

  /// Kullanıcıya dosya seçtirir ve içeriği metin olarak döner.
  ///
  /// Seçim iptal edilirse ya da dosya okunamazsa `null` döner.
  static Future<PickedPgn?> pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;

    final file = result.files.first;
    String? text;

    final bytes = file.bytes;
    if (bytes != null) {
      text = _decode(bytes);
    } else if (file.path != null) {
      text = _decode(await File(file.path!).readAsBytes());
    }
    if (text == null || text.trim().isEmpty) return null;

    return PickedPgn(name: file.name, content: text);
  }

  /// PGN dosyaları çoğunlukla UTF-8'dir; değilse Latin-1'e düşülür.
  static String _decode(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes);
    }
  }

  /// Listeyi PGN dosyası olarak kaydeder.
  ///
  /// Kullanıcı bir konum seçer; iptal ederse ya da platform kaydetme
  /// penceresini desteklemiyorsa `null` döner (çağıran panoya kopyalamaya
  /// düşebilir).
  static Future<String?> exportPlaylist(
    Playlist playlist, {
    void Function(int done, int total)? onProgress,
  }) async {
    final text = await buildListPgnAsync(playlist, onProgress: onProgress);
    if (text.trim().isEmpty) return null;

    final safeName =
        playlist.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return FilePicker.platform.saveFile(
      fileName: '${safeName.isEmpty ? 'oyunlar' : safeName}.pgn',
      bytes: Uint8List.fromList(utf8.encode(text)),
    );
  }

  /// Seçilen oyunları yeni bir listeye yazar ve listeyi döner.
  static Future<Playlist> saveAsNewList(String listName, List<PgnGame> games) {
    return StorageService.instance.createPlaylistWithGames(
      listName,
      games.map(_toSavedGame).toList(),
    );
  }

  /// Seçilen oyunları var olan bir listeye ekler; eklenen sayıyı döner.
  static Future<int> addToList(String playlistId, List<PgnGame> games) {
    return StorageService.instance.addGames(
      playlistId,
      games.map(_toSavedGame).toList(),
    );
  }

  static SavedGame _toSavedGame(PgnGame game) => SavedGame(
        name: game.title,
        uciMoves: game.uciMoves,
        createdAt: DateTime.now(),
        result: game.result,
        startFen: game.startFen,
        white: game.white == '?' ? null : game.white,
        black: game.black == '?' ? null : game.black,
        tags: game.headers,
        note: game.subtitle.isEmpty ? null : game.subtitle,
      );
}

/// Bir listedeki tüm oyunları tek bir PGN metnine dönüştürür.
String buildListPgn(Playlist playlist) {
  final buffer = StringBuffer();
  for (final game in playlist.games) {
    buffer.write(_gameToPgn(playlist, game));
    buffer.writeln();
  }
  return buffer.toString();
}

/// [buildListPgn] ile aynı çıktıyı verir, ama arada olay döngüsüne dönerek
/// arayüzü dondurmaz ve ilerlemeyi bildirir. Büyük listelerde bunu kullan.
Future<String> buildListPgnAsync(
  Playlist playlist, {
  void Function(int done, int total)? onProgress,
}) async {
  final buffer = StringBuffer();
  final total = playlist.games.length;

  for (int i = 0; i < total; i++) {
    buffer.write(_gameToPgn(playlist, playlist.games[i]));
    buffer.writeln();

    if (i % 20 == 19 || i == total - 1) {
      onProgress?.call(i + 1, total);
      await Future<void>.delayed(Duration.zero);
    }
  }
  return buffer.toString();
}

String _gameToPgn(Playlist playlist, SavedGame game) {
  return PgnParser.buildPgn(
    uciMoves: game.uciMoves,
    startFen: game.startFen,
    result: game.result,
    tags: {
      'Event': playlist.name,
      'White': game.white ?? game.name,
      'Black': game.black ?? '?',
      'Date': game.createdAt
          .toIso8601String()
          .substring(0, 10)
          .replaceAll('-', '.'),
    },
  );
}

/// Seçilen dosyanın adı ve içeriği.
class PickedPgn {
  final String name;
  final String content;

  const PickedPgn({required this.name, required this.content});

  /// Dosya adından uzantısız liste adı üretir.
  String get suggestedListName {
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    return base.trim().isEmpty ? name : base.trim();
  }
}
