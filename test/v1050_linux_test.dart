import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/screens/settings_screen.dart';
import 'package:chess_pgn_reader/services/linux_sound.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/services/sound_service.dart';

/// 10.5.0: Linux'ta sesler (sistem komutuyla çalınıyor; burada komutlar
/// sahte, testler her platformda koşuyor).

const _names = ['move-self', 'capture'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late List<(String, List<String>)> started;
  late Set<String> installed;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'flutter.soundEnabled': true,
      'flutter.soundDefaultsRestored': true,
    });
    await SettingsService.instance.load();
    Strings.language = AppLanguage.turkish;
    dir = await Directory.systemTemp.createTemp('cl_linux_sound_');
    started = [];
    installed = {};
    LinuxSound.directory = () async => dir;
    LinuxSound.commandExists = (command) async => installed.contains(command);
    LinuxSound.start = (command, arguments) async {
      started.add((command, arguments));
    };
    LinuxSound.instance.reset();
  });

  tearDown(() async {
    Strings.language = AppLanguage.system;
    // Testlerde varsayılan kapalı (bkz. flutter_test_config.dart).
    SoundService.useSystemPlayer = false;
    LinuxSound.instance.reset();
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  test('paplay varsa o seçiliyor, WAV geçici klasöre yazılıyor', () async {
    installed = {'paplay', 'aplay'};
    await LinuxSound.instance.play('capture', _names);
    expect(LinuxSound.instance.player, 'paplay');
    expect(started, hasLength(1));
    final (command, args) = started.single;
    expect(command, 'paplay');
    expect(args.single, endsWith('capture.wav'));
    final file = File(args.single);
    expect(file.existsSync(), isTrue);
    // Gerçek bir WAV (RIFF başlığı).
    expect(String.fromCharCodes(file.readAsBytesSync().take(4)), 'RIFF');
  });

  test('yalnız aplay varsa sessiz kipte çağrılıyor', () async {
    installed = {'aplay'};
    await LinuxSound.instance.play('move-self', _names);
    final (command, args) = started.single;
    expect(command, 'aplay');
    expect(args.first, '-q');
  });

  test('hiçbiri yoksa çalmıyor ve bunu bildiriyor', () async {
    await LinuxSound.instance.play('move-self', _names);
    expect(started, isEmpty);
    expect(LinuxSound.instance.unavailable, isTrue);
  });

  test('ses servisi Linux kipinde sistem komutuna gidiyor', () async {
    installed = {'pw-play'};
    SoundService.useSystemPlayer = true;
    await SoundService.instance.play(SoundService.castle);
    expect(started.single.$1, 'pw-play');
    expect(started.single.$2.single, endsWith('castle.wav'));
  });

  testWidgets('ayarlarda eksik komut yazıyor', (tester) async {
    SoundService.useSystemPlayer = true;
    await tester.runAsync(() => LinuxSound.instance.init(_names));
    expect(LinuxSound.instance.unavailable, isTrue);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dev.fluttercommunity.plus/wakelock'),
            (c) async => null);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1600);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();
    expect(find.textContaining('paplay, pw-play, aplay'), findsOneWidget);
  });
}
