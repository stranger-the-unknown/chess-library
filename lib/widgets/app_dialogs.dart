import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../services/settings_service.dart';

/// Uygulama genelinde tekrar eden küçük diyaloglar.
class AppDialogs {
  AppDialogs._();

  /// Tek satırlık metin ister. İptal edilirse `null` döner.
  static Future<String?> prompt(
    BuildContext context, {
    required String title,
    String? label,
    String? initialValue,
    String? confirmLabel,
    int maxLines = 1,
    String? Function(String value)? validator,
  }) async {
    final controller = TextEditingController(text: initialValue);
    String? error;

    return showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: maxLines,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: label, errorText: error),
            onSubmitted: maxLines == 1
                ? (_) => _submit(
                      dialogContext,
                      controller,
                      validator,
                      (message) => setState(() => error = message),
                    )
                : null,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(t('common.cancel')),
            ),
            ElevatedButton(
              onPressed: () => _submit(
                dialogContext,
                controller,
                validator,
                (message) => setState(() => error = message),
              ),
              child: Text(confirmLabel ?? t('common.ok')),
            ),
          ],
        ),
      ),
    );
  }

  static void _submit(
    BuildContext context,
    TextEditingController controller,
    String? Function(String value)? validator,
    void Function(String? message) setError,
  ) {
    final value = controller.text.trim();
    if (value.isEmpty) {
      setError(t('common.emptyNotAllowed'));
      return;
    }
    final message = validator?.call(value);
    if (message != null) {
      setError(message);
      return;
    }
    Navigator.pop(context, value);
  }

  /// Evet / hayır sorusu.
  ///
  /// [optional]: kaydedilmiş veriyi silmeyen bir onay (kaydedilmemiş
  /// hamlelerle çıkmak, pes etmek...). Kullanıcı "Onay pencereleri"
  /// ayarını kapattıysa sorulmadan `true` döner. Kayıtlı veriyi geri
  /// dönüşsüz silen onaylar bu seçeneği kullanmıyor; her zaman soruluyor.
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String? confirmLabel,
    String? cancelLabel,
    bool destructive = false,
    bool optional = false,
  }) async {
    if (optional && !SettingsService.instance.askConfirmations) return true;
    final scheme = Theme.of(context).colorScheme;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(cancelLabel ?? t('common.giveUp')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: destructive
                ? ElevatedButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                  )
                : null,
            child: Text(confirmLabel ?? t('common.ok')),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// İlerleme diyalogunun geniş ekranda alacağı genişlik.
  static const double _progressWidth = 420;

  /// İlerleme çubuğunun kalınlığı.
  ///
  /// Varsayılan dört piksellik çubuk masaüstünde bir çizgi gibi duruyor;
  /// yükleme sürerken bakılan tek şey o olduğu için görünür olmalı.
  static const double _progressHeight = 12;

  /// Uzun süren bir işi ilerleme çubuğuyla çalıştırır.
  ///
  /// [task]'a verilen geri çağırım 0-1 arası ilerlemeyi bildirir; iş bitince
  /// diyalog kapanır ve sonuç döner.
  static Future<T> runWithProgress<T>(
    BuildContext context, {
    required String message,
    required Future<T> Function(void Function(double progress) report) task,
  }) async {
    final progress = ValueNotifier<double>(0);
    final navigator = Navigator.of(context, rootNavigator: true);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          // Diyalog içeriğine göre daralıyordu: masaüstünde iki satır
          // metnin altında avuç içi kadar bir çubuk kalıyordu. Genişlik
          // burada veriliyor, dar ekranda pencereye göre kısılıyor.
          content: SizedBox(
            width: math.min(
              _progressWidth,
              MediaQuery.sizeOf(dialogContext).width - 96,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message),
                const SizedBox(height: 18),
                ValueListenableBuilder<double>(
                  valueListenable: progress,
                  builder: (context, value, _) {
                    final scheme = Theme.of(context).colorScheme;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(_progressHeight),
                          child: LinearProgressIndicator(
                            value: value == 0 ? null : value,
                            minHeight: _progressHeight,
                            backgroundColor: scheme.surfaceContainerHighest,
                          ),
                        ),
                        if (value > 0) ...[
                          const SizedBox(height: 8),
                          Text(
                            '%${(value * 100).round()}',
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      return await task((value) => progress.value = value);
    } finally {
      if (navigator.canPop()) navigator.pop();
      // `progress.dispose()` bilerek çağrılmıyor: diyalog kapanma
      // animasyonu boyunca ekranda kalıyor ve bu bildiriciyi dinlemeyi
      // sürdürüyor; hemen atılınca ayrılırken "disposed" hatası
      // veriyordu. Bildirici bu çağrıya özel, dışarıda tutulmuyor:
      // diyalog gidince çöp toplayıcıya kalıyor.
    }
  }

  static void snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
