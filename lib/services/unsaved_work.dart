import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../widgets/app_dialogs.dart';

/// Kaydedilmemiş iş taşıyan ekranların kaydı.
///
/// Oyun ekranı geri tuşunda "kaydedilmemiş hamleler kaybolacak" diye
/// soruyordu, ama Windows'ta pencereyi X ile kapatmak bu korumayı
/// atlıyordu: uygulama hiç sormadan kapanıyor, hamleler gidiyordu.
/// Pencere kapatma isteği uygulama düzeyinde geliyor; hangi ekranın
/// kaydedilmemiş işi olduğunu bilmek için ekranlar burada kendini
/// bildiriyor.
class UnsavedWork {
  UnsavedWork._();

  static final Set<bool Function()> _checks = {};

  /// [check] kaydedilmemiş iş varsa `true` döndürmeli.
  static void register(bool Function() check) => _checks.add(check);

  static void unregister(bool Function() check) => _checks.remove(check);

  /// Açık ekranlardan herhangi birinde kaydedilmemiş iş var mı?
  static bool get any {
    for (final check in _checks) {
      try {
        if (check()) return true;
      } catch (_) {
        // Bozuk bir denetim kullanıcıyı pencerede hapsetmesin.
      }
    }
    return false;
  }

  /// Masaüstünde pencere kapatılırken çağrılır; `true` kapansın demek.
  ///
  /// Kaydedilmemiş iş yoksa sormadan çıkılıyor. Varsa oyun ekranının geri
  /// tuşunda sorduğu onay burada da soruluyor. Ne olursa olsun kullanıcı
  /// pencerede hapsolmamalı: bir hata çıkarsa ya da onay gösterilemezse
  /// çıkışa izin veriliyor.
  static Future<bool> confirmExit(BuildContext? context) async {
    try {
      if (!any || context == null || !context.mounted) {
        return true;
      }
      final leave = await AppDialogs.confirm(
        context,
        title: t('game.exitTitle'),
        message: t('game.exitMessage'),
        confirmLabel: t('game.exitConfirm'),
        destructive: true,
        optional: true,
      );
      return leave;
    } catch (_) {
      return true;
    }
  }
}
