import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/services/app_store.dart';

/// `flutter test --dart-define=CL_FILE_STORE=true` ile koşulduğunda
/// servis testleri Windows'un dosya deposuyla ([FileStore]) çalışır.
///
/// Aynı testlerin iki depoda da geçmesi, taşımanın servislerin
/// davranışını değiştirmediğinin kanıtı.
const bool fileStoreMode = bool.fromEnvironment('CL_FILE_STORE');

/// Boş (ya da [values] ile kurulmuş) bir cihaz.
///
/// Dosya deposu kipinde her çağrı yeni bir geçici klasörde yeni bir depo
/// açıyor; [values] içindeki veri anahtarları, gerçek bir güncellemede
/// olduğu gibi açılışta dosyalara taşınıyor.
Future<void> resetDevice([Map<String, Object> values = const {}]) async {
  SharedPreferences.setMockInitialValues(values);
  if (fileStoreMode) {
    final dir = await Directory.systemTemp.createTemp('cl_filestore_');
    addTearDown(() async {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });
    AppStore.instance = await FileStore.open(dir);
  }
}
