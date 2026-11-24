import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/services.dart';

import '../theme/app_look.dart';

/// Uygulamanın simgesini seçili görünüme çevirir (10.13.0).
///
/// * Android: her görünümün başlatıcıda kendi girdisi var (manifestteki
///   `activity-alias`'lar); seçilen açılır, ötekiler kapatılır
///   (`AppIcon.kt`).
/// * Öteki platformlarda simge değişmez; yalnızca uygulamanın renkleri
///   değişir.
class AppIcon {
  AppIcon._();

  static const MethodChannel channel = MethodChannel('chess_library/icon');

  /// Testler için: platformu taklit eder.
  @visibleForTesting
  static bool? debugAndroid;

  static bool get _android =>
      debugAndroid ?? (!kIsWeb && Platform.isAndroid);

  /// Simgeyi [look]'a çevirir; olmazsa hatanın metnini, olursa `null` döner.
  static Future<String?> apply(AppLook look) async {
    if (!_android) return null;
    try {
      await channel.invokeMethod<void>('set', look.id);
      return null;
    } on PlatformException catch (error) {
      return error.message ?? error.code;
    } catch (error) {
      return '$error';
    }
  }
}
