import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Uygulama silinince verinin de gitmesi.
///
/// İki platformda da veri, uygulamanın kendi klasörünün dışında
/// tutuluyordu ve silme işlemi oraya dokunmuyordu:
///
/// * **Android**: otomatik yedekleme açıkken `shared_prefs` Drive'a
///   gidiyor, uygulama yeniden kurulunca geri geliyordu.
/// * **Windows**: veri `%APPDATA%` altında duruyor, kaldırma işlemi
///   yalnızca kurulum klasörünü siliyordu.
///
/// İkisi de ayar dosyalarında çözülüyor; buradaki testler o ayarların
/// yerinde durduğunu doğruluyor. Kodla sınanamayan tek yol bu.
void main() {
  group('Android', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    test('otomatik yedekleme kapalı', () {
      expect(
        manifest,
        contains('android:allowBackup="false"'),
        reason: 'açık kalırsa silinen uygulamanın verisi Drive\'dan döner',
      );
      expect(manifest, contains('android:fullBackupContent="false"'));
    });

    test('yeni telefona aktarma da kapalı', () {
      // Android 12+ için ayrı bir kural dosyası gerekiyor;
      // `allowBackup` tek başına cihazdan cihaza aktarmayı durdurmuyor.
      expect(
        manifest,
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
      );
      final rules =
          File('android/app/src/main/res/xml/data_extraction_rules.xml');
      expect(rules.existsSync(), isTrue, reason: 'kural dosyası yok');
      final text = rules.readAsStringSync();
      for (final section in ['cloud-backup', 'device-transfer']) {
        expect(text, contains('<$section>'), reason: section);
      }
      expect(
        '<exclude'.allMatches(text).length,
        greaterThanOrEqualTo(10),
        reason: 'her iki bölümde de tüm alanlar dışarıda bırakılmalı',
      );
    });
  });

  group('Windows', () {
    final script =
        File('windows/installer/chess_library.iss').readAsStringSync();

    test('kaldırma kullanıcı verisini de siliyor', () {
      expect(
        script,
        contains('io.github.strangertheunknown'),
        reason: 'veri klasörünün yolu betikte yazmalı',
      );
      expect(script, contains('CurUninstallStepChanged'));
      expect(script, contains('DelTree'));
    });

    test('silmeden önce soruluyor ve soru iki dilde', () {
      expect(script, contains('turkish.RemoveData='));
      expect(script, contains('english.RemoveData='));
      expect(script, contains("CustomMessage('RemoveData')"));
    });
  });
}
