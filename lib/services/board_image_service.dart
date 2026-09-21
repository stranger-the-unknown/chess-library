import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../l10n/app_strings.dart';

/// Tahtanın ekran görüntüsünü PNG olarak kaydeder.
///
/// Kaydedilecek tahta bir [RepaintBoundary] ile sarılır; buradaki
/// [GlobalKey] o sınırı bulup çizimi görüntüye dönüştürmek için kullanılır.
/// Böylece görüntü ekrandaki piksellerden değil, doğrudan çizim ağacından
/// üretilir: istenen çözünürlükte ve arayüzün geri kalanı karışmadan.
class BoardImageService {
  BoardImageService._();

  /// Kaydetme sonucunu anlatan durum.
  static const String savedOk = 'ok';
  static const String cancelled = 'cancelled';
  static const String failed = 'failed';

  /// [boundaryKey] ile işaretlenmiş tahtayı PNG'ye çevirip kullanıcının
  /// seçtiği konuma yazar.
  ///
  /// [pixelRatio] büyütme katsayısıdır; 3 ile 320 piksellik bir tahta
  /// 960×960 çıkar. Sonuç [savedOk], [cancelled] ya da [failed] olur.
  static Future<String> saveBoardPng(
    GlobalKey boundaryKey, {
    required String fileName,
    double pixelRatio = 3,
  }) async {
    final bytes = await capture(boundaryKey, pixelRatio: pixelRatio);
    if (bytes == null) return failed;

    try {
      final path = await FilePicker.platform.saveFile(
        fileName: _safeName(fileName),
        bytes: bytes,
      );
      return path == null ? cancelled : savedOk;
    } catch (_) {
      return failed;
    }
  }

  /// Tahtayı PNG baytlarına çevirir; çizim henüz hazır değilse `null`.
  static Future<Uint8List?> capture(
    GlobalKey boundaryKey, {
    double pixelRatio = 3,
  }) async {
    final object = boundaryKey.currentContext?.findRenderObject();
    if (object is! RenderRepaintBoundary) return null;

    try {
      final image = await object.toImage(pixelRatio: pixelRatio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) return null;
      return data.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  /// Dosya adından işletim sisteminin kabul etmediği karakterleri atar.
  static String _safeName(String name) {
    final clean = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return clean.isEmpty ? '${t('file.defaultBoardName')}.png' : clean;
  }
}
