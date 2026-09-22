import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/app_strings.dart';
import 'widgets/responsive.dart';
import 'screens/home_shell.dart';
import 'services/backup_service.dart';
import 'services/corrupt_data.dart';
import 'services/prefs_recovery.dart';
import 'services/prefs_write.dart';
import 'services/settings_service.dart';
import 'services/sound_service.dart';
import 'services/unsaved_work.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await _lockOrientation();
  try {
    await SettingsService.instance.load();
  } catch (_) {
    // Tercih dosyası okunamadı. Windows'ta bu, yarıda kalmış bir yazma
    // demek: eskiden uygulama `runApp`'e ulaşamıyor ve bir daha hiç
    // açılmıyordu. Dosya gerçekten bozuksa kenara alınıp boş başlanıyor;
    // değilse hata başka bir sebepten, eski davranış korunuyor.
    final moved = await PrefsRecovery.recover();
    if (moved == null) rethrow;
    await SettingsService.instance.load();
    PrefsRecovery.quarantined.value = moved;
  }
  // Önceki geri yükleme yarıda kaldıysa (pencere kapatıldı, sistem
  // uygulamayı öldürdü) veri geri yüklemeden önceki hâline dönüyor.
  try {
    _restoreRolledBack =
        await BackupService.instance.recoverInterruptedRestore();
  } catch (_) {
    // Toparlanamadıysa kopya yerinde kalır, sonraki açılışta denenir.
  }
  if (_restoreRolledBack) {
    // Tercih dosyası da kenara alındıysa "boş açıldı" artık doğru
    // değil: veri kopyadan geri geldi.
    PrefsRecovery.quarantined.value = null;
  }
  // Sesler arka planda yüklensin; ilk kare için beklemeye gerek yok.
  unawaited(SoundService.instance.init());

  runApp(const ChessApp());
}

/// Açılışta yarım kalmış bir geri yükleme geri alındı mı?
bool _restoreRolledBack = false;

/// Telefon dikey, tablet yatay; ekran dönmüyor.
///
/// Ekran döndükçe yerleşim değişiyor, tahta yeniden ölçülüyor ve elde
/// tutulan telefonda bu istemeden oluyordu. Tablette ise tek sebep var:
/// yan panelin sığdığı tek yönelim yatay.
///
/// Sınıflandırma **ekranın kendi ölçüsüne** bakıyor, pencereninkine
/// değil: uygulama o anda hangi yönelimde olursa olsun sonuç aynı.
Future<void> _lockOrientation() async {
  if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
  final display = WidgetsBinding.instance.platformDispatcher.views.first.display;
  final logical = display.size / display.devicePixelRatio;
  await SystemChrome.setPreferredOrientations(
    Layout.isTabletScreen(logical)
        ? const [
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]
        : const [DeviceOrientation.portraitUp],
  );
}

/// `dart:async` yalnızca bunun için içe aktarılmasın diye küçük yardımcı.
void unawaited(Future<void> future) {
  future.catchError((_) {});
}

class ChessApp extends StatefulWidget {
  const ChessApp({super.key});

  @override
  State<ChessApp> createState() => _ChessAppState();
}

class _ChessAppState extends State<ChessApp> {
  /// Diske yazma hatasını tek yerden duyurmak için.
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  /// Pencere kapatılırken onay penceresini gösterebilmek için.
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  /// Windows'ta pencere kapatma isteği (bkz. windows/runner/flutter_window.cpp).
  ///
  /// Eskiden kaydedilmemiş bir oyun X'e basınca onay sorulmadan
  /// kayboluyordu (Android'de aynı şeyi geri tuşu soruyor). Flutter'ın
  /// kendi çıkış isteği bu uygulamada hiç gelmiyor: motor onu yalnızca
  /// sürecin son penceresi kapanırken iletiyor, ses eklentisinin gizli
  /// pencereleri de bunu engelliyor. Runner isteği kendisi yakalayıp bu
  /// kanaldan soruyor.
  static const MethodChannel _windowChannel =
      MethodChannel('chess_library/window');

  Future<Object?> _onWindowCall(MethodCall call) async {
    if (call.method != 'requestClose') {
      throw MissingPluginException();
    }
    return UnsavedWork.confirmExit(_navigatorKey.currentContext);
  }

  @override
  void initState() {
    super.initState();
    _windowChannel.setMethodCallHandler(_onWindowCall);
    diskWriteFailures.addListener(_onWriteFailure);
    corruptRecords.addListener(_onCorruptRecord);
    // Açılışta veri toparlandıysa ilk karede söyle.
    if (PrefsRecovery.quarantined.value != null || _restoreRolledBack) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onDataRecovered());
    }
  }

  @override
  void dispose() {
    _windowChannel.setMethodCallHandler(null);
    diskWriteFailures.removeListener(_onWriteFailure);
    corruptRecords.removeListener(_onCorruptRecord);
    super.dispose();
  }

  /// Açılışta veri toparlandı: ya kayıtlı veriler okunamadı ve dosya
  /// kenara alındı (uygulama boş açıldı), ya da yarım kalmış bir geri
  /// yükleme geri alındı.
  ///
  /// Kullanıcının bunu fark etmesi şart (listeler boş ya da eski
  /// görünüyor); kendiliğinden kaybolmayan bir bildirim, kapatma
  /// düğmesiyle.
  void _onDataRecovered() {
    final moved = PrefsRecovery.quarantined.value;
    final String message;
    if (_restoreRolledBack) {
      message = t('backup.interruptedRestored');
    } else if (moved != null) {
      message = t('data.prefsRecovered', {'file': moved});
    } else {
      return;
    }
    _messengerKey.currentState?.showSnackBar(SnackBar(
      content: Text(message),
      duration: const Duration(days: 1),
      showCloseIcon: true,
    ));
  }

  /// Bir kayıt diske yazılamadı.
  ///
  /// Bulmaca, açılış ve ilerleme kayıtları onlarca ekrandan yazılıyor;
  /// her çağrıyı ayrı ayrı yakalamak yerine hata burada tek bir yerde
  /// söyleniyor. Eskiden ekran "kaydedildi" diyor, veri diske hiç
  /// ulaşmıyordu.
  void _onWriteFailure() {
    _messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(t('lists.saveFailed'))));
  }

  /// Bozuk bir kayıt bulundu ve bir kenara alındı.
  void _onCorruptRecord() {
    _messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(t('data.corruptFound'))));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SettingsService.instance,
      builder: (context, _) {
        final mode = SettingsService.instance.themeMode;
        final isDark = mode == ThemeMode.dark ||
            (mode == ThemeMode.system &&
                MediaQuery.platformBrightnessOf(context) == Brightness.dark);

        SystemChrome.setSystemUIOverlayStyle(
          SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness:
                isDark ? Brightness.light : Brightness.dark,
            systemNavigationBarColor: isDark
                ? AppTheme.dark.colorScheme.surface
                : AppTheme.light.colorScheme.surface,
            systemNavigationBarIconBrightness:
                isDark ? Brightness.light : Brightness.dark,
          ),
        );

        return MaterialApp(
          scaffoldMessengerKey: _messengerKey,
          navigatorKey: _navigatorKey,
          // Flutter'ın kendi metinleri de uygulamanın dilini izlesin.
          // Bunlar olmadan üç nokta menüsünün ipucu "Show menu", metin
          // kutusunun menüsü "Paste" diye çıkıyordu.
          locale: Locale(Strings.code),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('tr'), Locale('en')],
          title: t('app.title'),
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: mode,
          home: const HomeShell(),
      // Masaüstünde bütün yazılar aynı oranda büyüyor; telefon ve
      // tablet olduğu gibi kalıyor.
      builder: (context, child) {
        if (!Layout.isDesktop) return child!;
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: TextScaler.linear(Layout.desktopTextScale),
          ),
          child: child!,
        );
      },
        );
      },
    );
  }
}
