import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Okunamayan tercih dosyasını kenara alır.
///
/// Windows'ta bütün veri tek bir `shared_preferences.json` dosyasında
/// duruyor ve eklenti bu dosyayı her yazmada baştan, atomik olmadan
/// yazıyor. Yazma yarıda kalırsa (güç kesintisi, zorla kapatma, disk
/// dolu) dosya yarım JSON olarak kalıyor; eklenti okurken bunu
/// yakalamıyor ve `SharedPreferences.getInstance` hata veriyor. Açılışta
/// bu, `runApp`'e hiç ulaşılmaması demekti: uygulama bir daha açılmıyor,
/// tek çıkış dosyayı elle silmek, yani bütün veriyi kaybetmekti.
///
/// Artık açılış bu hatayı yakalıyor, dosya gerçekten bozuksa onu
/// `shared_preferences.bozuk-<zaman>.json` adıyla kenara alıyor ve boş
/// başlıyor. İçerik aynen saklandığı için elle kurtarılabiliyor;
/// kullanıcıya da yedekten geri yükleyebileceği söyleniyor.
///
/// 10.2.0'dan beri Windows'ta bu dosyada yalnızca ayarlar kalıyor; veri
/// kendi dosyalarında ve atomik yazılıyor (bkz. `FileStore`). Yani bozulan
/// bir tercih dosyası artık yalnızca ayarları sıfırlıyor.
class PrefsRecovery {
  PrefsRecovery._();

  /// Açılışta kenara alınan dosyanın yolu; bir şey olmadıysa `null`.
  static final ValueNotifier<String?> quarantined = ValueNotifier(null);

  /// Tercih dosyasını bulur ve bozuksa kenara alır.
  ///
  /// Yalnızca Windows'ta anlamlı: Android'in kendi tercih dosyası yazmada
  /// yedek dosya kullanıyor ve yarım kalmıyor. Kenara alınan dosyanın
  /// yeni yolunu, bir şey yapılmadıysa `null` döndürür.
  static Future<String?> recover() async {
    if (kIsWeb || !Platform.isWindows) return null;
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File(
        '${dir.path}${Platform.pathSeparator}shared_preferences.json',
      );
      return await quarantineIfCorrupt(file);
    } catch (_) {
      return null;
    }
  }

  /// [file] JSON olarak okunamıyorsa yeniden adlandırır.
  ///
  /// Sağlam, boş ya da olmayan dosyaya **dokunmaz**: açılış hatası başka
  /// bir sebepten olabilir ve sağlam veriyi kenara almak, önlemeye
  /// çalıştığımız kaybın ta kendisi olurdu.
  @visibleForTesting
  static Future<String?> quarantineIfCorrupt(File file) async {
    if (!await file.exists()) return null;
    try {
      final text = await file.readAsString();
      if (text.trim().isEmpty) return null;
      jsonDecode(text);
      return null;
    } catch (_) {
      // Okunamadı ya da çözülemedi: bozuk.
    }
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final target = '${file.parent.path}${Platform.pathSeparator}'
        'shared_preferences.bozuk-$stamp.json';
    await file.rename(target);
    return target;
  }
}
