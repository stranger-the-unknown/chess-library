import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

/// Düz metin dosyalarını açar ve kaydeder.
///
/// Bulmaca listelerinin metin olarak alınıp verilmesi için kullanılır.
/// PGN akışı kendi servisini kullanmayı sürdürür; ikisi birbirinden
/// bağımsızdır.
class TextFileService {
  TextFileService._();

  /// Kullanıcıya bir metin dosyası seçtirir ve içeriğini döner.
  ///
  /// Seçim iptal edilirse ya da dosya boşsa `null` döner.
  static Future<PickedText?> pick() async {
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

    return PickedText(name: file.name, content: text);
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

  /// Metin dosyaları çoğunlukla UTF-8'dir; değilse Latin-1'e düşülür.
  static String _decode(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes);
    }
  }
}

class PickedText {
  final String name;
  final String content;

  const PickedText({required this.name, required this.content});
}
