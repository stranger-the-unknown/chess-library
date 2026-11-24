import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/models/opening.dart';
import 'package:chess_pgn_reader/models/playlist.dart';
import 'package:chess_pgn_reader/screens/list_game_screen.dart';
import 'package:chess_pgn_reader/screens/game_screen.dart';
import 'package:chess_pgn_reader/screens/openings/opening_study_screen.dart';
import 'package:chess_pgn_reader/services/engine/search_result.dart';
import 'package:chess_pgn_reader/services/recording_session.dart';
import 'package:chess_pgn_reader/services/screen_recording.dart';
import 'package:chess_pgn_reader/widgets/move_list.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/widgets/chess_board_widget.dart';

/// 10.10.0: Instagram'a ekran kaydıyla paylaşılan oyunlar için —
/// sonucun sonda görünmesi ve uygulamanın kendi aldığı ekran kaydı.

final _settings = SettingsService.instance;

/// Ekran kaydı yalnızca Android ve Linux'ta var; başka yerde (Windows)
/// menüde seçenek hiç görünmüyor, akış testlerinin basacağı bir şey yok.
final _noRecordMenu = !ScreenRecording.platformSupported;

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

  /// Android'deki "kaydın sonu eksik olabilir" durumunun yerine.
  bool incomplete = false;

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
    if (incomplete) ScreenRecording.instance.lastIncomplete = true;
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
    // Sistem çubuklarına yapılan her çağrı ve o anda kaydedicinin
    // gördükleri (sıra doğrulansın diye).
    late List<(bool, List<String>)> bars;
    final originalBars = RecordingSession.systemBars;
    setUp(() {
      recorder = _FakeRecorder();
      ScreenRecording.linux = recorder;
      bars = [];
      RecordingSession.systemBars =
          (hidden) async => bars.add((hidden, List.of(recorder.events)));
      _settings.gameWatchSpeed = WatchSpeed.veryFast;
      _settings.openingWatchSpeed = WatchSpeed.veryFast;
    });
    tearDown(() {
      ScreenRecording.linux = LinuxScreenRecorder();
      RecordingSession.systemBars = originalBars;
      // Yarıda düşen bir test kaydı "sürüyor" bırakmasın; yoksa sonraki
      // testlerde kayıt hiç başlamıyor ve onlar da düşüyor.
      RecordingSession.active = false;
    });

    testWidgets('oyun: pencereler kapanınca başlıyor, 1 sn başlangıç, '
        'izleme, 2 sn son, kaydediliyor', (tester) async {
      await _pump(tester, _game);
      await tester.tap(find.byTooltip(t('game.toEnd')));
      await tester.pumpAndSettle();

      await _openMenuItem(tester, t('record.menu'));
      expect(recorder.events, ['prepare']);
      expect(_cursor(tester), -1, reason: 'önce başa sarıldı');
      expect(_locked(tester), isTrue, reason: 'kayıt sürerken dokunuş yok');
      expect(find.byType(AppBar), findsNothing,
          reason: 'üst çubuk kayıt başlamadan kalktı (24 Kasım 2026)');

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
      expect(find.byType(AppBar), findsOneWidget, reason: 'geri geldi');
      expect(
        find.text(t('record.saved',
            {'path': 'Videolar/Chess Library/oyun.mp4'})),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    }, skip: _noRecordMenu);

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
    }, skip: _noRecordMenu);

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
    }, skip: _noRecordMenu);

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
      expect(bars, isEmpty, reason: 'kayıt başlamadı, çubuklara dokunulmadı');
    }, skip: _noRecordMenu);

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
      expect(find.byType(AppBar), findsNothing,
          reason: 'açılışta da üst çubuk kayıtta yok');
      expect(find.text('İtalyan · Giuoco Piano'), findsOneWidget,
          reason: 'varyantın adı tahtanın üstündeki satıra geçti');
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
      await tester.pump();
      expect(find.byType(AppBar), findsOneWidget, reason: 'geri geldi');
      expect(find.text('İtalyan · Giuoco Piano'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    }, skip: _noRecordMenu);

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

    // 24 Kasım 2026: kayıtta tahtanın üstündeki "Oyun 1 / 2" satırı ve
    // önceki / sonraki okları da yok (üst çubuk gibi; kullanıcının isteği).
    testWidgets('listedeki oyunda sıra satırı kayıtta yok, sonra geri geliyor',
        (tester) async {
      SavedGame game(String white) => SavedGame(
            name: '$white - Rakip',
            uciMoves: _italian,
            createdAt: DateTime(2026, 11, 24),
            white: white,
            black: 'Rakip',
          );
      await _pump(
        tester,
        ListGameScreen(games: [game('Birinci'), game('İkinci')], initialIndex: 0),
      );
      final position = t('lists.gamePosition', {'n': 1, 'total': 2});
      expect(find.text(position), findsOneWidget);
      expect(find.byTooltip(t('lists.nextGame')), findsOneWidget);

      await _openMenuItem(tester, t('record.menu'));
      expect(find.text(position), findsNothing);
      expect(find.byTooltip(t('lists.nextGame')), findsNothing);
      expect(find.byTooltip(t('lists.previousGame')), findsNothing);
      expect(find.text('Birinci'), findsOneWidget, reason: 'oyuncu satırı');

      for (var i = 0; i < 14; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      await tester.pump();
      expect(recorder.events.last, 'stop');
      await tester.pump();
      expect(find.text(position), findsOneWidget, reason: 'geri geldi');
      expect(find.byTooltip(t('lists.nextGame')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    }, skip: _noRecordMenu);

    // Kullanıcının sorusu (24 Kasım 2026): üst çubuk kalkmışken son hamlede
    // sonuç kartı çıkınca yazılar bozuluyor mu? Kartın yeri baştan ayrılı:
    // tahta ve adlar yerinde kalmalı, kart adlarla çakışmamalı.
    testWidgets('kayıtta sonuç kartı çıkınca tahta ve adlar kaymıyor',
        (tester) async {
      expect(_settings.resultAtEnd, isTrue, reason: 'varsayılan (10.10.1)');
      SavedGame game(String white) => SavedGame(
            name: '$white - Rakip',
            uciMoves: _italian,
            createdAt: DateTime(2026, 11, 24),
            result: '1-0',
            white: white,
            black: 'Maxime Vachier-Lagrave',
          );
      await _pump(
        tester,
        ListGameScreen(
          games: [game('Ian Nepomniachtchi'), game('Magnus Carlsen')],
          initialIndex: 0,
        ),
      );
      await _openMenuItem(tester, t('record.menu'));
      await tester.pump(const Duration(milliseconds: 650));
      expect(recorder.events.last, startsWith('begin '));
      expect(find.byType(AppBar), findsNothing);
      expect(_resultVisible(tester), isFalse, reason: 'başta sonuç gizli');

      Rect rectOf(Finder f) => tester.getRect(f);
      final board = rectOf(find.byType(ChessBoardWidget));
      final top = rectOf(find.text('Maxime Vachier-Lagrave'));
      final bottom = rectOf(find.text('Ian Nepomniachtchi'));

      for (var i = 0; i < 9; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(_cursor(tester), 5, reason: 'son hamle');
      expect(recorder.events.last, isNot('stop'), reason: 'sondaki 2 sn');
      expect(_resultVisible(tester), isTrue, reason: 'kart çıktı');
      expect(rectOf(find.byType(ChessBoardWidget)), board,
          reason: 'tahta kaymadı');
      expect(rectOf(find.text('Maxime Vachier-Lagrave')), top);
      expect(rectOf(find.text('Ian Nepomniachtchi')), bottom);
      // Kayıtta (üst çubuk ve sıra satırı yokken) de adlar tahtaya bitişik.
      expect(board.top - top.bottom, lessThan(24), reason: 'üst ad bitişik');
      expect(bottom.top - board.bottom, lessThan(24), reason: 'alt ad bitişik');
      final card = rectOf(find.textContaining(t('game.whiteWon')));
      expect(card.overlaps(bottom), isFalse, reason: 'adla çakışmıyor');
      expect(card.overlaps(board), isFalse, reason: 'tahtayla çakışmıyor');
      expect(card.top, greaterThan(bottom.bottom), reason: 'altta duruyor');
      expect(tester.takeException(), isNull, reason: 'taşma yok');

      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      await tester.pump();
      expect(recorder.events.last, 'stop');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    }, skip: _noRecordMenu);

    // 24 Kasım 2026: Android'de kaydı yazan iş parçacığı zamanında
    // bitmeyince uygulama düşüyordu. Artık video kaydediliyor; sonu eksik
    // olabilirse bu söyleniyor (sessizce geçilmiyor).
    testWidgets('kaydın sonu eksik olabilirse söyleniyor', (tester) async {
      recorder.incomplete = true;
      await _pump(tester, _game);
      await _openMenuItem(tester, t('record.menu'));
      for (var i = 0; i < 18; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      await tester.pump();
      expect(recorder.events.last, 'stop');
      await tester.pump();
      expect(
        find.text(t('record.savedIncomplete',
            {'path': 'Videolar/Chess Library/oyun.mp4'})),
        findsOneWidget,
      );
      expect(find.text(t('record.saved',
          {'path': 'Videolar/Chess Library/oyun.mp4'})), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    }, skip: _noRecordMenu);

    // 10.13.0 (inceleme): motor açıkken kayıt alınınca başlangıç konumunda
    // ve sondaki bekleyişte motor satırı ve ok videoya giriyordu.
    testWidgets('kayıt boyunca motor kapalı, bitince geri açılıyor',
        (tester) async {
      final asked = <String>[];
      GameScreen.debugAnalyze = (fen) async {
        asked.add(fen);
        return const SearchResult(
          bestMoveUci: 'e2e4',
          scoreCp: 20,
          depth: 10,
          nodes: 1,
          pvUci: ['e2e4'],
        );
      };
      addTearDown(() => GameScreen.debugAnalyze = null);
      await _pump(
        tester,
        const GameScreen(
          uciMoves: _italian,
          title: 'Fischer - Spassky',
          startWithAnalysis: true,
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(asked, isNotEmpty, reason: 'motor açık başladı');

      await _openMenuItem(tester, t('record.menu'));
      asked.clear();
      // Son hamleden sonraki 2 saniyelik bekleyişin içine kadar.
      for (var i = 0; i < 11; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(_cursor(tester), 5, reason: 'son hamle oynandı');
      expect(recorder.events.last, isNot('stop'), reason: 'kayıt sürüyor');
      expect(asked, isEmpty, reason: 'kayıt sürerken motora sorulmadı');

      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      await tester.pump();
      expect(recorder.events.last, 'stop');
      await tester.pump(const Duration(seconds: 2));
      expect(find.byTooltip(t('game.analysisOff')), findsOneWidget,
          reason: 'kayıt bitince motor yeniden açık');
      expect(asked, isNotEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    }, skip: _noRecordMenu);

    testWidgets('açılışta varyant okları kayıtta yok, sonra geri geliyor',
        (tester) async {
      Opening line(String id, String variation) => Opening(
            id: id,
            eco: 'C50',
            family: 'İtalyan',
            variation: variation,
            uciMoves: _italian,
            sanMoves: const ['e4', 'e5', 'Nf3', 'Nc6', 'Bc4', 'Bc5'],
            custom: true,
          );
      final first = line('o1', 'Giuoco Piano');
      await _pump(
        tester,
        OpeningStudyScreen(
          opening: first,
          sequence: [first, line('o2', 'Evans Gambiti')],
        ),
      );
      expect(find.byTooltip(t('openings.nextVariation')), findsOneWidget);

      await _openMenuItem(tester, t('record.menu'));
      expect(find.byTooltip(t('openings.nextVariation')), findsNothing);
      expect(find.byTooltip(t('openings.previousVariation')), findsNothing);
      expect(find.text('İtalyan · Giuoco Piano'), findsOneWidget,
          reason: 'satır duruyor, varyantın adıyla');

      for (var i = 0; i < 14; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      await tester.pump();
      expect(recorder.events.last, 'stop');
      await tester.pump();
      expect(find.byTooltip(t('openings.nextVariation')), findsOneWidget,
          reason: 'geri geldi');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    }, skip: _noRecordMenu);

    // 24 Kasım 2026: Android'de kayıt ekranın tamamını alıyor; telefonun
    // durum ve gezinme çubukları YouTube videolarında görünüyordu.
    testWidgets('çubuklar kayıt başlamadan gizleniyor, bitince geri geliyor',
        (tester) async {
      await _pump(tester, _game);
      await _openMenuItem(tester, t('record.menu'));
      expect(bars, hasLength(1));
      expect(bars[0].$1, isTrue, reason: 'gizlendi');
      expect(bars[0].$2, ['prepare'],
          reason: 'onaydan sonra, kayıt başlamadan (kayma videoya girmesin)');

      await tester.pump(const Duration(milliseconds: 650));
      expect(recorder.events.last, startsWith('begin '));
      expect(bars, hasLength(1), reason: 'kayıt boyunca gizli');

      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      await tester.pump();
      expect(recorder.events.last, 'stop');
      expect(bars, hasLength(2));
      expect(bars[1].$1, isFalse, reason: 'geri geldi');
      expect(bars[1].$2.last, 'stop', reason: 'kayıt bittikten sonra');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    }, skip: _noRecordMenu);

    testWidgets('dışarıdan durdurulunca da çubuklar geri geliyor',
        (tester) async {
      await _pump(tester, _game);
      await _openMenuItem(tester, t('record.menu'));
      await tester.pump(const Duration(milliseconds: 2200));
      recorder.exit!('Videolar/Chess Library/yarım.mp4');
      await tester.pump();
      await tester.pump();
      expect([for (final b in bars) b.$1], [true, false]);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    }, skip: _noRecordMenu);
  });

  group('Ekran kaydı: Android kanalının sonucu', () {
    test('yol ve "sonu eksik olabilir" ayrıştırılıyor', () {
      final parse = ScreenRecording.parseStopResult;
      expect(parse({'path': 'Movies/Chess Library/a.mp4', 'incomplete': false}),
          (path: 'Movies/Chess Library/a.mp4', incomplete: false));
      expect(parse({'path': 'Movies/Chess Library/a.mp4', 'incomplete': true}),
          (path: 'Movies/Chess Library/a.mp4', incomplete: true));
      expect(parse({'path': null, 'incomplete': true}),
          (path: null, incomplete: true));
      expect(parse('Movies/Chess Library/a.mp4'),
          (path: 'Movies/Chess Library/a.mp4', incomplete: false),
          reason: 'eski biçim');
      expect(parse(null), (path: null, incomplete: false));
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
