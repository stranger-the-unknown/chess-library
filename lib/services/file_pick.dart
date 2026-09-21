import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../l10n/app_strings.dart';

/// Dosya seçmenin başarısızlık sebepleri.
///
/// **İptal bunlardan biri değildir**: iptal `null` ile bildirilir ve
/// çağıran sessizce çıkar. Eskiden ikisi ayırt edilmiyordu, yani
/// pencereyi kapatan herkes "dosya okunamadı" hatası görüyordu.
enum PickFailure { wrongType, tooLarge, empty, unreadable }

class PickException implements Exception {
  final PickFailure reason;

  const PickException(this.reason);

  @override
  String toString() => 'PickException(${reason.name})';
}

/// Seçilen dosyanın metin hâli.
class PickedFile {
  final String name;
  final String content;

  const PickedFile({required this.name, required this.content});
}

/// Kullanıcıya dosya seçtirir ve metnini okur.
///
/// Seçici `FileType.any` ile açılıyor: Android'de özel uzantı süzgeci
/// bazı dosya sağlayıcılarında hiçbir dosyayı seçilebilir bırakmıyor.
/// Denetim seçimden **sonra** yapılıyor:
///
/// * uzantı [extensions] içinde değilse ya da içerik ikili görünüyorsa
///   ([PickFailure.wrongType]) — eskiden video/zip seçmek dosyayı
///   Latin-1'e çevirip ayrıştırmaya çalışıyordu;
/// * dosya [maxBytes]'tan büyükse ([PickFailure.tooLarge]) — eskiden
///   tamamı belleğe alınıyordu;
/// * içerik boşsa ([PickFailure.empty]).
Future<PickedFile?> pickTextFile({
  required List<String> extensions,
  int maxBytes = 32 * 1024 * 1024,
}) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.any,
    // Dosyayı belleğe almadan önce boyutuna bakabilmek için.
    withData: false,
  );
  if (result == null || result.files.isEmpty) return null;

  final file = result.files.first;
  final dot = file.name.lastIndexOf('.');
  final extension =
      dot == -1 ? '' : file.name.substring(dot + 1).toLowerCase();
  if (!extensions.contains(extension)) {
    throw const PickException(PickFailure.wrongType);
  }
  if (file.size > maxBytes) {
    throw const PickException(PickFailure.tooLarge);
  }

  List<int>? bytes = file.bytes;
  if (bytes == null && file.path != null) {
    try {
      bytes = await File(file.path!).readAsBytes();
    } catch (_) {
      throw const PickException(PickFailure.unreadable);
    }
  }
  if (bytes == null) throw const PickException(PickFailure.unreadable);

  // Uzantısı doğru ama içeriği ikili olan dosyalar (adı değiştirilmiş
  // bir zip gibi) burada eleniyor: metinde sıfır bayt bulunmaz.
  final head = bytes.length < 1024 ? bytes : bytes.sublist(0, 1024);
  if (head.contains(0)) throw const PickException(PickFailure.wrongType);

  final text = decodeTextBytes(bytes);
  if (text.trim().isEmpty) throw const PickException(PickFailure.empty);

  return PickedFile(name: file.name, content: text);
}

/// Metin dosyaları çoğunlukla UTF-8'dir; değilse Latin-1'e düşülür.
String decodeTextBytes(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } catch (_) {
    return latin1.decode(bytes);
  }
}

/// Seçim hatasının kullanıcıya gösterilecek karşılığı.
String pickFailureMessage(Object error) {
  if (error is PickException) {
    switch (error.reason) {
      case PickFailure.wrongType:
        return t('file.wrongType');
      case PickFailure.tooLarge:
        return t('file.tooLarge');
      case PickFailure.empty:
        return t('file.empty');
      case PickFailure.unreadable:
        return t('pgn.readError');
    }
  }
  return t('pgn.readError');
}
