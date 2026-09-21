import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'l10n/app_strings.dart';
import 'screens/home_shell.dart';
import 'services/corrupt_data.dart';
import 'services/prefs_write.dart';
import 'services/settings_service.dart';
import 'services/sound_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SettingsService.instance.load();
  // Sesler arka planda yüklensin; ilk kare için beklemeye gerek yok.
  unawaited(SoundService.instance.init());

  runApp(const ChessApp());
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
          title: t('app.title'),
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: mode,
          home: const HomeShell(),
        );
      },
    );
  }
}
