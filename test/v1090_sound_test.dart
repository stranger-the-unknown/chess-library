import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/screens/settings_screen.dart';
import 'package:chess_pgn_reader/services/android_sound.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/services/sound_service.dart';

/// 10.9.0: Android'de hamle sesleri SoundPool'la (`GameSounds.kt`).
///
/// Ekran kaydında bazı hamlelerde cızırtı vardı (aynı kayıtla YouTube
/// temizdi); her ses ayrı bir just_audio oynatıcısıyla, her çalışta
/// yeniden başlatılarak çalıyordu. Burada Dart tarafı sınanıyor: kanala
/// doğru istekler gidiyor mu, yüklenemeyen ses görünüyor mu. SoundPool'un
/// kendisi öykünücüde denendi (bkz. sürüm notu).

const _names = [
  'move-self',
  'move-opponent',
  'capture',
  'castle',
  'promote',
  'move-check',
  'illegal',
  'game-start',
  'game-end',
  'notify',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <MethodCall>[];
  List<String> missing = const [];
  bool playResult = true;
  List<String> failures = const [];

  setUp(() async {
    calls.clear();
    missing = const [];
    playResult = true;
    failures = const [];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(AndroidSound.channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'load':
          return missing;
        case 'play':
          return playResult;
        case 'failures':
          return failures;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/wakelock'),
        (call) async => null);
    SharedPreferences.setMockInitialValues({
      'flutter.soundEnabled': true,
      'flutter.vibrationEnabled': false,
      'flutter.soundDefaultsRestored': true,
    });
    await SettingsService.instance.load();
    Strings.language = AppLanguage.turkish;
    SoundService.useSoundPool = true;
    AndroidSound.instance.reset();
  });

  tearDown(() {
    SoundService.useSoundPool = false;
    AndroidSound.instance.reset();
    Strings.language = AppLanguage.system;
  });

  test('açılışta on ses WAV kopyalarından bir kez yükleniyor', () async {
    await SoundService.instance.init();
    await SoundService.instance.init();
    expect(calls.map((c) => c.method), ['load'],
        reason: 'ikinci init yeniden yüklemiyor');
    final sounds = Map<String, String>.from(
        (calls.single.arguments as Map)['sounds'] as Map);
    expect(sounds.keys.toSet(), _names.toSet());
    expect(sounds['move-self'], 'assets/sounds/wav/move-self.wav');
    expect(AndroidSound.instance.unavailable, isFalse);
  });

  test('hamle sesi SoundPool kanalından çalıyor', () async {
    await SoundService.instance.init();
    calls.clear();
    SoundService.instance.playForSan('Nxe5');
    SoundService.instance.playForSan('e4', opponent: true);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(calls.map((c) => '${c.method} ${(c.arguments as Map)['name']}'),
        ['play capture', 'play move-opponent']);
  });

  test('init beklenmeden çalınan ilk ses de yüklemeyi başlatıyor', () async {
    await SoundService.instance.play('move-self');
    expect(calls.map((c) => c.method), ['load', 'play']);
  });

  test('ses kapalıyken kanala hiçbir şey gitmiyor', () async {
    SettingsService.instance.soundEnabled = false;
    await SoundService.instance.play('move-self');
    expect(calls, isEmpty);
  });

  test('açılamayan ya da çözülemeyen ses sessizce geçmiyor', () async {
    missing = const ['castle'];
    await SoundService.instance.init();
    expect(AndroidSound.instance.failure, 'castle');

    AndroidSound.instance.reset();
    missing = const [];
    playResult = false;
    failures = const ['promote'];
    await SoundService.instance.play('promote');
    expect(AndroidSound.instance.failure, 'promote');
  });

  testWidgets('ayarlarda yüklenemeyen sesler yazıyor', (tester) async {
    AndroidSound.instance.failure = 'castle, promote';
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 915);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();
    final text = find.text(
        t('settings.soundLoadFailed', {'error': 'castle, promote'}));
    await tester.scrollUntilVisible(text, 200,
        scrollable: find.byType(Scrollable).first);
    expect(text, findsOneWidget);
  });
}
