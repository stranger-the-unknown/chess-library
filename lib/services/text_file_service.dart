import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import 'file_pick.dart';

/// Düz metin dosyalarını açar ve kaydeder.
///
/// Bulmaca listelerinin metin olarak alınıp verilmesi için kullanılır.
/// PGN akışı kendi servisini kullanmayı sürdürür; ikisi birbirinden
/// bağımsızdır.
class TextFileService {
  TextFileService._();

  /// Kullanıcıya bir metin dosyası seçtirir ve içeriğini döner.
  ///
  /// İptal edilirse `null`; dosya uygun değilse [PickException]. Yedek
  /// dosyası `.json`, açılış ve bulmaca listeleri `.txt` uzantılıdır;
  /// `.pgn` ve `.csv` de elle hazırlanmış listelerde geçiyor.
  static Future<PickedText?> pick() async {
    final picked = await pickTextFile(
      extensions: const ['txt', 'json', 'pgn', 'csv', 'fen'],
    );
    if (picked == null) return null;
    return PickedText(name: picked.name, content: picked.content);
  }

  /// Metni dosya olarak kaydettirir; seçilen yolu döner.
  ///
  /// Kullanıcı iptal ederse ya da platform kaydetme penceresini
  /// desteklemiyorsa `null` döner (çağıran panoya kopyalamaya düşebilir).
  static Future<String?> save(
    String suggestedName,
    String content, {
    String extension = 'txt',
  }) {
    final safe = suggestedName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return FilePicker.platform.saveFile(
      fileName: '${safe.isEmpty ? 'chess-library' : safe}.$extension',
      bytes: Uint8List.fromList(utf8.encode(content)),
    );
  }
}

class PickedText {
  final String name;
  final String content;

  const PickedText({required this.name, required this.content});
}
