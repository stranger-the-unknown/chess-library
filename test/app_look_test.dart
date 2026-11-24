import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/screens/settings_screen.dart';
import 'package:chess_pgn_reader/services/app_icon.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/theme/app_look.dart';
import 'package:chess_pgn_reader/theme/app_theme.dart';
import 'package:chess_pgn_reader/widgets/app_logo.dart';

/// 10.13.0: uygulama görünümleri (vurgu rengi + zemin tonu + simge).
///
/// Renkler tablodan türetiliyor; her görünümde, iki kipte de yazıların
/// okunur kaldığı burada ölçülüyor. Yeni bir görünüm eklenince ya da bir
/// renk değişince bu testler karşıtlığı düşük olanı yakalar.
void main() {
  double ratio(Color a, Color b) => AppTheme.contrast(a, b);

  test('adlar benzersiz; bilinmeyen ad varsayılana düşüyor', () {
    final ids = [for (final look in AppLook.values) look.id];
    expect(ids.toSet().length, ids.length);
    expect(ids.first, 'yesil', reason: 'varsayılan başta');
    for (final look in AppLook.values) {
      expect(AppLook.byId(look.id), same(look));
    }
    expect(AppLook.byId(null), same(AppLook.yesil));
    expect(AppLook.byId('yok'), same(AppLook.yesil));
  });

  test('yeşil bugüne kadarki temanın aynısı', () {
    expect(AppTheme.schemeFor(AppLook.yesil, Brightness.dark),
        AppTheme.dark.colorScheme);
    expect(AppTheme.schemeFor(AppLook.yesil, Brightness.light),
        AppTheme.light.colorScheme);
  });

  for (final look in AppLook.values) {
    for (final brightness in Brightness.values) {
      test('${look.id} / ${brightness.name}: yazılar okunuyor', () {
        final s = AppTheme.schemeFor(look, brightness);
        expect(s.brightness, brightness);

        // Vurgu renkli düğmenin yazısı.
        expect(ratio(s.onPrimary, s.primary), greaterThanOrEqualTo(4.5),
            reason: 'düğme yazısı');
        // Yeşil bugüne kadarki tema: bazı değerleri 4,5'in biraz altında
        // (koyu kipte vurgu kabı 4,2; açık kipte vurgu 4,3). Ona
        // dokunulmuyor; yeni görünümler 4,5'i tutmalı.
        final floor = look == AppLook.yesil ? 4.0 : 4.5;
        expect(ratio(s.onPrimaryContainer, s.primaryContainer),
            greaterThanOrEqualTo(floor),
            reason: 'vurgu kabındaki yazı');

        // Vurgu renginin kendisi yazı ve simge olarak (seçili sekme,
        // bağlantı, anahtar): zeminde ve kartlarda.
        expect(ratio(s.primary, s.surface), greaterThanOrEqualTo(floor),
            reason: 'vurgu zeminde');
        expect(ratio(s.primary, s.surfaceContainerHigh),
            greaterThanOrEqualTo(look == AppLook.yesil ? 3.5 : 3.9),
            reason: 'vurgu kartta');

        // Sıradan yazılar.
        expect(ratio(s.onSurface, s.surface), greaterThanOrEqualTo(12),
            reason: 'yazı zeminde');
        expect(ratio(s.onSurface, s.surfaceContainerHighest),
            greaterThanOrEqualTo(10),
            reason: 'yazı en koyu kartta');
        expect(ratio(s.onSurfaceVariant, s.surfaceContainerHigh),
            greaterThanOrEqualTo(4.5),
            reason: 'soluk yazı kartta');
        expect(ratio(s.onInverseSurface, s.inverseSurface),
            greaterThanOrEqualTo(10),
            reason: 'bildirim çubuğu');

        // Zeminlerin açıklık sırası bozulmadı (kartlar zeminden ayrılıyor).
        final levels = [
          s.surfaceContainerLow,
          s.surfaceContainer,
          s.surfaceContainerHigh,
          s.surfaceContainerHighest,
        ].map((c) => c.computeLuminance()).toList();
        for (var i = 1; i < levels.length; i++) {
          expect(
            brightness == Brightness.dark
                ? levels[i] > levels[i - 1]
                : levels[i] < levels[i - 1],
            isTrue,
            reason: 'kart tonları sıralı',
          );
        }
      });
    }
  }

  test('simgedeki at zeminden ayrılıyor', () {
    for (final look in AppLook.values) {
      final middle = Color.lerp(look.iconTop, look.iconBottom, 0.5)!;
      expect(ratio(look.knight, middle), greaterThanOrEqualTo(3),
          reason: look.id);
    }
  });

  test('her görünümün Android simgesi var (tools/make_look_icons.py)', () {
    const res = 'android/app/src/main/res';
    final colors = File('$res/values/look_colors.xml').readAsStringSync();
    for (final look in AppLook.values) {
      if (look == AppLook.yesil) continue;
      for (final path in [
        '$res/drawable-xxxhdpi/ic_look_${look.id}_fg.png',
        '$res/mipmap-xxxhdpi/ic_look_${look.id}.png',
        '$res/mipmap-anydpi-v26/ic_look_${look.id}.xml',
      ]) {
        expect(File(path).existsSync(), isTrue, reason: path);
      }
      expect(colors, contains('ic_look_${look.id}_bg'));
    }
  });

  test('her görünümün başlatıcı girdisi var; yalnızca varsayılan açık', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final kotlin = File('android/app/src/main/kotlin/io/github/'
            'strangertheunknown/chesslibrary/AppIcon.kt')
        .readAsStringSync();
    final aliases = RegExp(r'<activity-alias(.*?)</activity-alias>', dotAll: true)
        .allMatches(manifest)
        .map((m) => m[1]!)
        .toList();
    expect(aliases, hasLength(AppLook.values.length));
    for (final look in AppLook.values) {
      final name = look == AppLook.yesil
          ? '.MainActivity'
          : '.Icon${look.id[0].toUpperCase()}${look.id.substring(1)}';
      final icon =
          look == AppLook.yesil ? 'ic_launcher' : 'ic_look_${look.id}';
      final alias = aliases.singleWhere(
        (a) => a.contains('android:name="$name"'),
        orElse: () => '',
      );
      expect(alias, isNotEmpty, reason: 'girdi yok: $name');
      expect(alias, contains('android:icon="@mipmap/$icon"'));
      expect(alias, contains('android:targetActivity=".ChessActivity"'));
      // Yalnızca varsayılan açık: iki açık girdi iki simge demek.
      expect(alias,
          contains('android:enabled="${look == AppLook.yesil}"'));
      // Flutter bu bilgiyi girdiden okuyor.
      expect(alias, contains('io.flutter.embedding.android.NormalTheme'));
      expect(alias, contains('android.intent.category.LAUNCHER'));
    }
    // Yerel koddaki liste aynı adları, aynı sırayla taşıyor.
    final listed = RegExp(r'val looks = listOf\((.*?)\)', dotAll: true)
        .firstMatch(kotlin)![1]!;
    expect(
      RegExp(r'"(\w+)"').allMatches(listed).map((m) => m[1]).toList(),
      [for (final look in AppLook.values) look.id],
    );
    // Etkinliğin kendisinde başlatıcı süzgeci yok (yoksa bir simge fazla).
    final activity = RegExp(r'<activity\s(.*?)</activity>', dotAll: true)
        .firstMatch(manifest)![1]!;
    expect(activity, isNot(contains('category.LAUNCHER')));
  });

  test('yerel kod girdi adlarını sınıftan okumuyor (sürüm derlemesi)', () {
    // Sürüm derlemesinde kod küçültülüyor: sınıfların adı ve paketi
    // değişiyor. Girdinin adı `AppIcon::class.java.package` ile kurulunca
    // deneme derlemesi çalışıyor, sürüm APK'sı açılırken çöküyordu
    // (öykünücüde yakalandı, 24 Kasım 2026).
    final dir = Directory('android/app/src/main/kotlin/io/github/'
        'strangertheunknown/chesslibrary');
    for (final file in dir.listSync().whereType<File>()) {
      // Yorumlar dışında: sınıfın adına ya da paketine bakan çağrılar.
      final code = file
          .readAsLinesSync()
          .where((line) {
            final text = line.trimLeft();
            return !text.startsWith('*') && !text.startsWith('//');
          })
          .join('\n');
      for (final risky in const [
        '.`package`',
        '.simpleName',
        '.qualifiedName',
        '.canonicalName',
        'Class.forName',
      ]) {
        expect(code, isNot(contains(risky)),
            reason: '${file.path}: $risky sürüm derlemesinde güvenilmez');
      }
    }
    final kotlin = File('${dir.path}/AppIcon.kt').readAsStringSync();
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final namespace =
        RegExp(r'namespace = "([\w.]+)"').firstMatch(gradle)![1]!;
    expect(kotlin, contains('const val NAMESPACE = "$namespace"'),
        reason: 'girdi adları manifestteki ad alanıyla kurulmalı');
  });

  group('ayar ve seçme penceresi', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.instance.load();
      Strings.language = AppLanguage.turkish;
    });
    tearDown(() => Strings.language = AppLanguage.system);

    test('görünüm saklanıyor; bilinmeyen değer varsayılana düşüyor', () async {
      final settings = SettingsService.instance;
      expect(settings.appLook, same(AppLook.yesil));
      settings.appLook = AppLook.gece;
      await pumpEventQueue();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('appLook'), 'gece');

      SharedPreferences.setMockInitialValues({'flutter.appLook': 'mor'});
      await settings.load();
      expect(settings.appLook, same(AppLook.mor));
      for (final Object bad in ['yok', 7]) {
        SharedPreferences.setMockInitialValues({'flutter.appLook': bad});
        await settings.load();
        expect(settings.appLook, same(AppLook.yesil), reason: '$bad');
      }
    });

    testWidgets('görünüm seçilince tema ve ayar satırı değişiyor',
        (tester) async {
      final settings = SettingsService.instance;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(412, 915);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(AnimatedBuilder(
        animation: settings,
        builder: (context, _) => MaterialApp(
          theme: AppTheme.lightFor(settings.appLook),
          home: const SettingsScreen(),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text(t('look.yesil')), findsOneWidget);

      await tester.tap(find.text(t('settings.look')));
      await tester.pumpAndSettle();
      for (final look in AppLook.values) {
        expect(find.byKey(ValueKey('look-${look.id}')), findsOneWidget);
      }
      await tester.tap(find.byKey(const ValueKey('look-mor')));
      await tester.pumpAndSettle();

      expect(settings.appLook, same(AppLook.mor));
      expect(find.text(t('look.mor')), findsOneWidget, reason: 'ayar satırı');
      final theme = Theme.of(tester.element(find.byType(SettingsScreen)));
      expect(theme.colorScheme.primary, AppLook.mor.accentLight);
      expect(tester.takeException(), isNull);
    });

    testWidgets('logo görünümün renklerini kullanıyor', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Center(child: AppLogo(look: AppLook.gece, size: 54)),
      ));
      final box = tester.widget<Container>(find.descendant(
        of: find.byType(AppLogo),
        matching: find.byType(Container),
      ));
      final gradient =
          (box.decoration! as BoxDecoration).gradient! as LinearGradient;
      expect(gradient.colors, [AppLook.gece.iconTop, AppLook.gece.iconBottom]);
      expect(tester.widget<Text>(find.text('♞')).style!.color,
          AppLook.gece.knight);
    });

    test('simge Android kanalından isteniyor; hata metni dönüyor', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      AppIcon.debugAndroid = true;
      addTearDown(() {
        AppIcon.debugAndroid = null;
        messenger.setMockMethodCallHandler(AppIcon.channel, null);
      });
      messenger.setMockMethodCallHandler(AppIcon.channel, (call) async {
        calls.add(call);
        return 'changed';
      });
      expect(await AppIcon.apply(AppLook.gece), isNull);
      expect(calls.single.method, 'set');
      expect(calls.single.arguments, 'gece');

      messenger.setMockMethodCallHandler(AppIcon.channel, (call) async {
        throw PlatformException(code: 'icon', message: 'olmadı');
      });
      expect(await AppIcon.apply(AppLook.mor), 'olmadı');

      // Android dışında simgeye dokunulmuyor.
      AppIcon.debugAndroid = false;
      calls.clear();
      expect(await AppIcon.apply(AppLook.mor), isNull);
      expect(calls, isEmpty);
    });
  });
}
