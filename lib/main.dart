import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/app_strings.dart';
import 'widgets/responsive.dart';
import 'screens/home_shell.dart';
import 'services/corrupt_data.dart';
import 'services/prefs_write.dart';
import 'services/settings_service.dart';
import 'services/sound_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await _lockOrientation();
  await SettingsService.instance.load();
  // Sesler arka planda yüklensin; ilk kare için beklemeye gerek yok.
  unawaited(SoundService.instance.init());

  runApp(const ChessApp());
}

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

  @override
  void initState() {
    super.initState();
    diskWriteFailures.addListener(_onWriteFailure);
    corruptRecords.addListener(_onCorruptRecord);
  }

  @override
  void dispose() {
    diskWriteFailures.removeListener(_onWriteFailure);
    corruptRecords.removeListener(_onCorruptRecord);
    super.dispose();
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
