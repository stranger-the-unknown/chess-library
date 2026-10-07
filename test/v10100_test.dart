import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/models/opening.dart';
import 'package:chess_pgn_reader/screens/game_screen.dart';
import 'package:chess_pgn_reader/screens/openings/opening_study_screen.dart';
import 'package:chess_pgn_reader/services/screen_recording.dart';
import 'package:chess_pgn_reader/widgets/move_list.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/widgets/chess_board_widget.dart';

/// 10.10.0: Instagram'a ekran kaydıyla paylaşılan oyunlar için —
/// sonucun sonda görünmesi ve uygulamanın kendi aldığı ekran kaydı.

final _settings = SettingsService.instance;

void _silencePlugins() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final channel in const [
    MethodChannel('com.ryanheise.just_audio.methods'),
    MethodChannel('dev.fluttercommunity.plus/wakelock'),
  ]) {
    messenger.setMockMethodCallHandler(channel, (call) async => null);
  }
}

Future<void> _pump(
  WidgetTester tester,
  Widget screen, {
  Size size = const Size(412, 915),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pumpAndSettle();
}

const _italian = ['e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1c4', 'f8c5'];

const _game = GameScreen(
  uciMoves: _italian,
  title: 'Fischer - Spassky',
  initialResult: '1-0',
);

int _cursor(WidgetTester tester) =>
    tester.widget<MoveList>(find.byType(MoveList)).currentIndex;

/// Kaydın kendisi yerine olayları yazan sahte kaydedici (Linux yolu;
/// testler Linux'ta koşuyor).
class _FakeRecorder extends LinuxScreenRecorder {
  final events = <String>[];
  String? prepareError;
  String? saved = 'Videolar/Chess Library/oyun.mp4';
  void Function(String?)? exit;

  @override
  Future<String?> prepare() async {
    events.add('prepare');
    return prepareError;
  }

  @override
  Future<String?> begin(String name, {void Function(String?)? onExit}) async {
    events.add('begin $name');
    exit = onExit;
    return null;
  }

  @override
  Future<String?> stop() async {
    events.add('stop');
    return saved;
  }
}

Future<void> _openMenuItem(WidgetTester tester, String text) async {
  await tester.tap(find.descendant(
    of: find.byType(AppBar),
    matching: find.byType(PopupMenuButton<String>),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text(text));
  await tester.pump();
}

bool _locked(WidgetTester tester) => tester
    .widgetList<AbsorbPointer>(find.byType(AbsorbPointer))
    .any((w) => w.absorbing);

bool _resultVisible(WidgetTester tester) => tester
    .widget<Visibility>(find.ancestor(
      of: find.textContaining(t('game.whiteWon')),
      matching: find.byType(Visibility),
    ))
    .visible;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    _silencePlugins();
    SharedPreferences.setMockInitialValues({
      'flutter.soundEnabled': false,
      'flutter.soundDefaultsRestored': true,
    });
    await _settings.load();
    Strings.language = AppLanguage.turkish;
  });

  tearDown(() => Strings.language = AppLanguage.system);

  group('Sonucu oyunun sonunda göster', () {
    test('varsayılan açık (10.10.1)', () {
      expect(_settings.resultAtEnd, isTrue);
    });

    testWidgets('kapalıyken sonuç baştan görünüyor', (tester) async {
      _settings.resultAtEnd = false;
      await _pump(tester, _game);
      expect(_resultVisible(tester), isTrue);
    });

    for (final size in const [Size(412, 915), Size(1400, 900)]) {
      testWidgets('açıkken yalnızca son hamlede; tahta kaymıyor '
          '(${size.width.toInt()})', (tester) async {
        _settings.resultAtEnd = true;
        await _pump(tester, _game, size: size);
        final board = tester.getRect(find.byType(ChessBoardWidget));
        expect(_resultVisible(tester), isFalse, reason: 'başlangıçta gizli');

        await tester.tap(find.byTooltip(t('game.forward')));
        await tester.pumpAndSettle();
        expect(_resultVisible(tester), isFalse, reason: 'oyun sürerken gizli');

        await tester.tap(find.byTooltip(t('game.toEnd')));
        await tester.pumpAndSettle();
        expect(_resultVisible(tester), isTrue, reason: 'son hamlede görünüyor');
        expect(tester.getRect(find.byType(ChessBoardWidget)), board,
            reason: 'kart çıkınca tahta kaymıyor');

        await tester.tap(find.byTooltip(t('game.toStart')));
        await tester.pumpAndSettle();
        expect(_resultVisible(tester), isFalse);
      });
    }
  });

  group('Ekran kaydı: akış', () {
    late _FakeRecorder recorder;
    setUp(() {
      recorder = _FakeRecorder();
      ScreenRecording.linux = recorder;
      _settings.gameWatchSpeed = WatchSpeed.veryFast;
      _settings.openingWatchSpeed = WatchSpeed.veryFast;
    });
    tearDown(() => ScreenRecording.linux = LinuxScreenRecorder());

    testWidgets('oyun: pencereler kapanınca başlıyor, 1 sn başlangıç, '
        'izleme, 2 sn son, kaydediliyor', (tester) async {
      await _pump(tester, _game);
      await tester.tap(find.byTooltip(t('game.toEnd')));
      await tester.pumpAndSettle();

      await _openMenuItem(tester, t('record.menu'));
      expect(recorder.events, ['prepare']);
      expect(_cursor(tester), -1, reason: 'önce başa sarıldı');
      expect(_locked(tester), isTrue, reason: 'kayıt sürerken dokunuş yok');

      await tester.pump(const Duration(milliseconds: 500));
      expect(recorder.events, ['prepare'],
          reason: 'onay penceresi kapanırken kayıt başlamıyor');
      await tester.pump(const Duration(milliseconds: 150));
      expect(recorder.events.last, startsWith('begin Fischer - Spassky '));

      await tester.pump(const Duration(milliseconds: 900));
      expect(_cursor(tester), -1, reason: '1 sn başlangıç konumu');
      for (var i = 0; i < 7; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(_cursor(tester), 5);
      expect(recorder.events.last, isNot('stop'), reason: 'sonda 2 sn');
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pump();
      expect(recorder.events.last, 'stop');
      await tester.pump();
      expect(_locked(tester), isFalse);
      expect(
        find.text(t('record.saved',
            {'path': 'Videolar/Chess Library/oyun.mp4'})),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('kayıt sırasında dokunmak izlemeyi bozmuyor', (tester) async {
      await _pump(tester, _game);
      await _openMenuItem(tester, t('record.menu'));
      await tester.pump(const Duration(milliseconds: 2200));
      expect(_cursor(tester), 0);
      await tester.tap(find.byType(ChessBoardWidget), warnIfMissed: false);
      await tester.tap(find.byTooltip(t('common.pause')), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 500));
      expect(_cursor(tester), 1, reason: 'izleme sürüyor');
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      await tester.pump();
      expect(recorder.events.last, 'stop');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('dışarıdan durdurulunca o ana kadarki kısım kaydediliyor',
        (tester) async {
      await _pump(tester, _game);
      await _openMenuItem(tester, t('record.menu'));
      await tester.pump(const Duration(milliseconds: 2200));
      recorder.exit!('Videolar/Chess Library/yarım.mp4');
      await tester.pump();
      await tester.pump();
      expect(recorder.events.where((e) => e == 'stop'), isEmpty,
          reason: 'zaten durdu');
      expect(_locked(tester), isFalse);
      expect(
        find.text(t('record.saved',
            {'path': 'Videolar/Chess Library/yarım.mp4'})),
        findsOneWidget,
      );
      final at = _cursor(tester);
      await tester.pump(const Duration(seconds: 2));
      expect(_cursor(tester), at, reason: 'izleme de durdu');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('eksik parça varsa kayıt başlamıyor ve söyleniyor',
        (tester) async {
      recorder.prepareError = 'GStreamer: x264enc';
      await _pump(tester, _game);
      await _openMenuItem(tester, t('record.menu'));
      await tester.pump();
      expect(recorder.events, ['prepare']);
      expect(_locked(tester), isFalse);
      expect(find.text(t('record.linuxMissing', {'missing': 'x264enc'})),
          findsOneWidget);
    });

    testWidgets('açılış: alıştırmadan izle kipine geçip kaydediyor',
        (tester) async {
      final line = Opening(
        id: 'o',
        eco: 'C50',
        family: 'İtalyan',
        variation: 'Giuoco Piano',
        uciMoves: _italian,
        sanMoves: const ['e4', 'e5', 'Nf3', 'Nc6', 'Bc4', 'Bc5'],
        custom: true,
      );
      await _pump(tester, OpeningStudyScreen(opening: line));
      await tester.tap(find.text(t('openings.practice')));
      await tester.pumpAndSettle();
      await _openMenuItem(tester, t('record.menu'));
      final segmented = tester.widget<SegmentedButton<StudyMode>>(
          find.byType(SegmentedButton<StudyMode>));
      expect(segmented.selected, {StudyMode.watch});
      for (var i = 0; i < 14; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      await tester.pump();
      expect(recorder.events.first, 'prepare');
      expect(recorder.events[1], startsWith('begin İtalyan - Giuoco Piano '));
      expect(recorder.events.last, 'stop');
      expect(_cursor(tester), 5);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('motora karşı oyunda seçenek yok', (tester) async {
      await _pump(tester, const GameScreen(uciMoves: [], title: 'x'));
      await tester.tap(find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(PopupMenuButton<String>),
      ));
      await tester.pumpAndSettle();
      expect(find.text(t('record.menu')), findsNothing,
          reason: 'hamlesi olmayan tahtada da yok');
    });
  });

  group('Ekran kaydı: Linux komutu', () {
    test('gerekenler varsa pencere ve ses çıkışıyla MP4 kaydı', () async {
      final folder = Directory.systemTemp.createTempSync('cl_record_');
      addTearDown(() => folder.deleteSync(recursive: true));
      final recorder = LinuxScreenRecorder();
      final commands = <String>[];
      recorder.run = (command, arguments) async {
        commands.add('$command ${arguments.join(' ')}');
        if (command == 'pactl') return ProcessResult(0, 0, 'hoparlor\n', '');
        if (command == 'xdg-user-dir') {
          return ProcessResult(0, 0, '${folder.path}\n', '');
        }
        return ProcessResult(0, 0, '', '');
      };
      recorder.captureTarget = () async => {'xid': 42, 'width': 1001, 'height': 700};
      late List<String> launched;
      late _FakeProcess process;
      recorder.start = (command, arguments) async {
        launched = [command, ...arguments];
        process = _FakeProcess(onInterrupt: () {
          final location =
              arguments.firstWhere((a) => a.startsWith('location='));
          File(location.substring(9)).writeAsStringSync('mp4');
        });
        return process;
      };

      expect(await recorder.prepare(), isNull);
      expect(await recorder.begin('Fischer - Spassky'), isNull);
      expect(launched.first, 'gst-launch-1.0');
      expect(launched, contains('xid=42'));
      expect(launched, contains('video/x-raw,format=I420,width=1000,height=700'),
          reason: 'x264 çift kenar istiyor');
      expect(launched, contains('device=hoparlor.monitor'));
      expect(launched, contains('avenc_aac'));
      expect(launched,
          contains('location=${folder.path}/Chess Library/Fischer - Spassky.mp4'));

      final saved = await recorder.stop();
      expect(process.signals, [ProcessSignal.sigint],
          reason: 'kesme sinyali: dosya düzgün kapanıyor');
      expect(saved, endsWith('Chess Library/Fischer - Spassky.mp4'));
    });

    test('eksik GStreamer parçaları sayılıyor', () async {
      final recorder = LinuxScreenRecorder();
      recorder.run = (command, arguments) async => ProcessResult(
          0,
          command == 'gst-inspect-1.0' &&
                  ['x264enc', 'avenc_aac', 'voaacenc'].contains(arguments.single)
              ? 1
              : 0,
          '',
          '');
      expect(await recorder.prepare(),
          'GStreamer: x264enc, avenc_aac / voaacenc');
    });

    test('X11 değilse söyleniyor', () async {
      final recorder = LinuxScreenRecorder();
      recorder.run = (command, arguments) async => ProcessResult(0, 0, '', '');
      recorder.captureTarget = () async => null;
      expect(await recorder.prepare(), 'x11');
    });
  });
}

/// `gst-launch-1.0` yerine: başlayınca "PLAYING" yazar, kesme sinyaliyle
/// biter.
class _FakeProcess implements Process {
  _FakeProcess({required this.onInterrupt}) {
    _out.add(utf8.encode('Setting pipeline to PLAYING ...\n'));
  }

  final void Function() onInterrupt;
  final signals = <ProcessSignal>[];
  final _out = StreamController<List<int>>();
  final _exit = Completer<int>();

  @override
  Stream<List<int>> get stdout => _out.stream;

  @override
  Stream<List<int>> get stderr => const Stream.empty();

  @override
  Future<int> get exitCode => _exit.future;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    signals.add(signal);
    if (signal == ProcessSignal.sigint) onInterrupt();
    if (!_exit.isCompleted) _exit.complete(0);
    _out.close();
    return true;
  }

  @override
  int get pid => 1;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
