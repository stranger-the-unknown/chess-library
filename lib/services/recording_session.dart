import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../widgets/app_dialogs.dart';
import 'screen_recording.dart';

/// "Ekran kaydı al"ın akışı: oyunun ya da açılışın kaydını uygulama
/// başlatıp bitiriyor (10.10.0).
///
/// 1. Tahta başa sarılıyor, izin ve onay penceresi açılıyor.
/// 2. Kayıt, pencereler tamamen kapandıktan sonra başlıyor: uygulama öne
///    döndükten sonra [settle] kadar bekleniyor. (Kullanıcının isteği:
///    kapanmakta olan pencere videoya girmesin.)
/// 3. [lead] boyunca başlangıç konumu, sonra izleme hızıyla oynatma.
/// 4. Bitince [tail] kadar son konum, sonra kayıt duruyor ve kaydediliyor.
///
/// Kayıt sürerken ekran dokunuşlara kapalı ([RecordingSession.active]):
/// yanlışlıkla bir dokunuş izlemeyi ve kaydı bozmasın. Erken bitirmek için
/// Android'de bildirimdeki "Durdur" ya da sistemin durdurma düğmesi var;
/// uygulamadan çıkmak da kaydı bitiriyor. O ana kadarki kısım kaydediliyor.
class RecordingSession {
  RecordingSession._();

  static const Duration settle = Duration(milliseconds: 600);
  static const Duration lead = Duration(seconds: 1);
  static const Duration tail = Duration(seconds: 2);

  /// Bir kayıt sürüyor mu? (Aynı anda ikincisi başlamasın.)
  static bool active = false;

  /// Testler için: beklemeler.
  @visibleForTesting
  static Future<void> Function(Duration) wait = Future<void>.delayed;

  /// Kaydı yürütür.
  ///
  /// [rewind]: izlemeyi durdurup başa sarar (açılışta izle kipine geçer).
  /// [watch]: izlemeyi başlatır; izleme bitince ya da durunca tamamlanır.
  /// [stopWatch]: izlemeyi keser (kayıt dışarıdan bittiğinde).
  /// [setLocked]: ekranı dokunuşlara kapatır / açar.
  static Future<void> run({
    required BuildContext context,
    required String title,
    required VoidCallback rewind,
    required Future<void> Function() watch,
    required VoidCallback stopWatch,
    required ValueChanged<bool> setLocked,
  }) async {
    if (active) return;
    active = true;
    final recorder = ScreenRecording.instance;
    var stoppedOutside = false;
    String? savedOutside;
    AppLifecycleListener? lifecycle;
    OverlayEntry? heartbeat;
    try {
      rewind();
      final start = await recorder.prepare();
      if (!context.mounted) {
        await recorder.stop();
        return;
      }
      switch (start) {
        case RecordStart.ok:
          break;
        case RecordStart.cancelled:
          return;
        case RecordStart.noAudioPermission:
          AppDialogs.snack(context, t('record.noAudioPermission'));
          return;
        case RecordStart.unsupported:
          AppDialogs.snack(context, _unsupportedText(recorder.lastError));
          return;
        case RecordStart.failed:
          AppDialogs.snack(
              context, t('record.failed', {'error': recorder.lastError ?? '?'}));
          return;
      }

      setLocked(true);
      // Onay penceresi tamamen kapansın, uygulama öne dönsün.
      await _untilResumed();
      await wait(settle);
      if (!context.mounted) {
        await recorder.stop();
        return;
      }

      // Kayıt boyunca ekran hiç "durmasın" (bkz. [_Heartbeat]).
      heartbeat = OverlayEntry(builder: (_) => const _Heartbeat());
      Overlay.of(context, rootOverlay: true).insert(heartbeat);

      final error = await recorder.begin(_fileName(title));
      if (error != null) {
        if (context.mounted) {
          AppDialogs.snack(context, t('record.failed', {'error': error}));
        }
        return;
      }
      final outside = Completer<void>();
      recorder.onStoppedOutside = (saved) {
        stoppedOutside = true;
        savedOutside = saved;
        stopWatch();
        if (!outside.isCompleted) outside.complete();
      };
      // Uygulamadan çıkmak kaydı bitiriyor.
      lifecycle = AppLifecycleListener(onHide: () {
        stopWatch();
        if (!outside.isCompleted) outside.complete();
      });

      Future<void> step(Future<void> work) =>
          Future.any([work, outside.future]);
      await step(wait(lead));
      if (!outside.isCompleted) await step(watch());
      if (!outside.isCompleted) await step(wait(tail));

      final saved = stoppedOutside ? savedOutside : await recorder.stop();
      if (!context.mounted) return;
      AppDialogs.snack(
        context,
        saved == null
            ? t('record.notSaved')
            : t('record.saved', {'path': saved}),
      );
    } finally {
      heartbeat?.remove();
      lifecycle?.dispose();
      recorder.onStoppedOutside = null;
      setLocked(false);
      active = false;
    }
  }

  static Future<void> _untilResumed() async {
    final binding = WidgetsBinding.instance;
    if (binding.lifecycleState == AppLifecycleState.resumed ||
        binding.lifecycleState == null) {
      return;
    }
    final resumed = Completer<void>();
    final listener = AppLifecycleListener(onResume: () {
      if (!resumed.isCompleted) resumed.complete();
    });
    await resumed.future.timeout(const Duration(seconds: 10), onTimeout: () {});
    listener.dispose();
  }

  static String _unsupportedText(String? reason) {
    if (reason == null) return t('record.unsupported');
    if (reason == 'x11') return t('record.linuxX11');
    if (reason == 'pactl') return t('record.linuxMissing', {'missing': 'pactl'});
    if (reason.startsWith('GStreamer: ')) {
      return t('record.linuxMissing', {'missing': reason.substring(11)});
    }
    return t('record.failed', {'error': reason});
  }

  /// "Chess Library — Fischer - Spassky — 2026-10-07 14.05"; dosya adına
  /// uymayan işaretler atılıyor.
  static String _fileName(String title) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${now.year}-${two(now.month)}-${two(now.day)} '
        '${two(now.hour)}.${two(now.minute)}.${two(now.second)}';
    final clean = title
        .replaceAll(RegExp(r'[\\/:*?"<>|\n\r\t]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final short = clean.length > 60 ? clean.substring(0, 60).trim() : clean;
    return short.isEmpty ? 'Chess Library $stamp' : '$short $stamp';
  }
}

/// Kayıt sürerken ekranın köşesinde gözle görülmeyen bir nokta (siyah,
/// 1/255 saydamlık) her karede yenileniyor.
///
/// Android'in ekran kaydı yalnızca ekran değiştiğinde kare üretiyor;
/// kodlayıcının "önceki kareyi tekrarla" ayarı her cihazda düzenli
/// çalışmıyor (öykünücüde 0,7 sn'ye varan boşluklar). Sondaki 2 saniyelik
/// durgun bekleyiş bu yüzden videoya girmiyordu: video son hamleden hemen
/// sonra bitiyordu. Nokta ekranı sürekli "canlı" tutuyor.
class _Heartbeat extends StatefulWidget {
  const _Heartbeat();

  @override
  State<_Heartbeat> createState() => _HeartbeatState();
}

class _HeartbeatState extends State<_Heartbeat>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 66),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      top: 0,
      width: 1,
      height: 1,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _ticker,
          builder: (context, _) => ColoredBox(
            color: Color.fromARGB(_ticker.value < 0.5 ? 0 : 1, 0, 0, 0),
          ),
        ),
      ),
    );
  }
}
