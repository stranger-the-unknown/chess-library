import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/models/chess_engine.dart' as engine;
import 'package:chess_pgn_reader/models/move_entry.dart';
import 'package:chess_pgn_reader/models/playlist.dart';
import 'package:chess_pgn_reader/models/stored_review.dart';
import 'package:chess_pgn_reader/screens/game_review_screen.dart';
import 'package:chess_pgn_reader/screens/game_screen.dart';
import 'package:chess_pgn_reader/screens/playlist_detail_screen.dart';
import 'package:chess_pgn_reader/services/analysis_queue.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/services/storage_service.dart';

/// Tahta ekranından başlatılan incelemenin kaydedilmesi.
///
/// Eskiden yalnızca listeden oyun seçerek başlatılan toplu analizler
/// kaydediliyordu; tek bir oyunu inceleyip geri çıkınca sonuç kayboluyordu.
/// Analiz motoru gerçekten çalıştığı için testler kısa oyunlarla yapılıyor.

const _timeout = Timeout(Duration(minutes: 5));

List<MoveEntry> _history(List<String> uciMoves) {
  final position = engine.ChessGame();
  final history = <MoveEntry>[];
  for (final uci in uciMoves) {
    final move = position.moveFromUci(uci)!;
    final san = position.sanFor(move);
    position.makeMove(move);
    history.add(MoveEntry(move: move, san: san, fenAfter: position.fen));
  }
  return history;
}

SavedGame _game(String name, {String? id}) => SavedGame(
      id: id,
      name: name,
      uciMoves: const ['e2e4', 'e7e5'],
      createdAt: DateTime.now(),
      white: 'Beyaz',
      black: 'Siyah',
    );

Future<void> _reset() async {
  SharedPreferences.setMockInitialValues({});
  StorageService.instance.resetCache();
  await SettingsService.instance.load();
  Strings.language = AppLanguage.turkish;
}

Future<void> _pumpReview(
  WidgetTester tester, {
  SavedGame? source,
  String? sourcePlaylistId,
  StoredReview? saved,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(500, 1000);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final screen = MaterialApp(
    home: KeyedSubtree(
      key: UniqueKey(),
      child: GameReviewScreen(
        history: _history(const ['e2e4', 'e7e5']),
        title: 'Deneme',
        source: source,
        sourcePlaylistId: sourcePlaylistId,
        saved: saved,
      ),
    ),
  );

  // Ekran `runAsync` içinde kuruluyor: motor işi `initState` içinde
  // başlıyor ve widget testinin sahte saatinde hiç ilerlemiyor. Gerçek
  // zamanlı bölgede başlatılınca normal hızında çalışıyor.
  var finished = false;
  await tester.runAsync(() async {
    await tester.pumpWidget(screen);
    final deadline = DateTime.now().add(const Duration(minutes: 2));
    while (AnalysisQueue.instance.isRunning) {
      if (DateTime.now().isAfter(deadline)) return;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    finished = true;
  });
  if (!finished) fail('inceleme bitmedi');
  await tester.pumpAndSettle();
}

Future<List<SavedGame>> _analysisRecords() async =>
    (await StorageService.instance.loadAnalysisLists()).first.games;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(_reset);
  tearDown(() => Strings.language = AppLanguage.system);

  group('Tek oyunluk inceleme kaydediliyor', () {
    testWidgets('listeden açılan oyun asıl oyuna bağlanıyor', (tester) async {
      final playlist = await StorageService.instance.createPlaylist('Tal');
      final game = _game('Tal - Botvinnik');
      await StorageService.instance.addGames(playlist.id, [game]);

      await _pumpReview(tester, source: game, sourcePlaylistId: playlist.id);

      final records = await _analysisRecords();
      expect(records, hasLength(1), reason: 'inceleme kaydedilmedi');
      expect(records.first.name, 'Tal - Botvinnik');
      expect(records.first.sourceGameId, game.id);
      expect(records.first.sourcePlaylistId, playlist.id);
      expect(records.first.review, isNotNull);
    }, timeout: _timeout);

    testWidgets('listesi olmayan oyun da kaydediliyor', (tester) async {
      // Serbest tahta, motora karşı oyun, PGN önizlemesi: kayıt kendi
      // başına duruyor, asıl oyuna bağ kurulmuyor.
      await _pumpReview(tester, source: _game('Serbest oyun'));

      final records = await _analysisRecords();
      expect(records, hasLength(1));
      expect(records.first.name, 'Serbest oyun');
      expect(records.first.sourceGameId, isNull);
      expect(records.first.sourcePlaylistId, isNull);
    }, timeout: _timeout);

    testWidgets('kaydedilmiş analiz açılınca yeni kayıt eklenmiyor',
        (tester) async {
      final game = _game('Zaten analiz edilmiş');
      final saved = StoredReview(
        deep: false,
        at: DateTime.now(),
        whiteAccuracy: 90,
        blackAccuracy: 80,
        moves: const [
          StoredReviewMove(
            bestScoreCp: 20,
            playedScoreCp: 10,
            bestMoveUci: 'e2e4',
            quality: 1,
            accuracy: 95,
          ),
          StoredReviewMove(
            bestScoreCp: 15,
            playedScoreCp: 5,
            bestMoveUci: 'e7e5',
            quality: 1,
            accuracy: 92,
          ),
        ],
      );

      await _pumpReview(tester, source: game, saved: saved);

      expect(
        await _analysisRecords(),
        isEmpty,
        reason: 'motor çalışmadı, kaydedilecek yeni bir analiz yok',
      );
    }, timeout: _timeout);

    testWidgets('kaynak verilmezse kaydedilmiyor', (tester) async {
      await _pumpReview(tester);
      expect(await _analysisRecords(), isEmpty);
    }, timeout: _timeout);
  });

  group('Analiz kaydından yeniden analiz', () {
    testWidgets('bağ kaydın kendisine değil asıl oyuna kuruluyor',
        (tester) async {
      final playlist = await StorageService.instance.createPlaylist('Tal');
      final game = _game('Tal - Botvinnik');
      await StorageService.instance.addGames(playlist.id, [game]);
      await StorageService.instance.addAnalysis(
        source: game,
        sourcePlaylistId: playlist.id,
        review: StoredReview(
          deep: false,
          at: DateTime.now(),
          whiteAccuracy: 80,
          blackAccuracy: 70,
          moves: const [],
        ),
      );

      final analysis = (await StorageService.instance.loadAnalysisLists()).first;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(500, 1200);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: KeyedSubtree(
            key: UniqueKey(),
            child: PlaylistDetailScreen(playlistId: analysis.id),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Kartta oyun adı değil, iki oyuncunun adı yazıyor.
      await tester.tap(find.text('Beyaz').first);
      await tester.pumpAndSettle();

      final board = tester.widget<GameScreen>(find.byType(GameScreen));
      expect(
        board.sourceGameId,
        game.id,
        reason: 'bağ analiz kaydına kurulursa kaydın analizi birikir',
      );
      expect(board.sourcePlaylistId, playlist.id);
    }, timeout: _timeout);
  });

  group('Şerit', () {
    test('tek inceleme sürerken şerit görünüyor', () async {
      final queue = AnalysisQueue.instance;
      expect(queue.isRunning, isFalse);

      final gate = Completer<void>();
      final job = queue.trackExternal('Deneme', () => gate.future);

      expect(queue.isRunning, isTrue);
      expect(queue.isSingleReview, isTrue);
      expect(queue.current, 'Deneme');

      gate.complete();
      await job;

      expect(queue.isRunning, isFalse);
      expect(queue.current, isNull);
    });

    test('inceleme hata verse de şerit kalkıyor', () async {
      final queue = AnalysisQueue.instance;
      await expectLater(
        queue.trackExternal<void>('Bozuk', () async => throw StateError('x')),
        throwsStateError,
      );
      expect(queue.isRunning, isFalse,
          reason: 'şerit sonsuza kadar ekranda kalırdı');
    });
  });

  group('Kaynaksız kayıtta işaretleme', () {
    test('okundu ve favori çökmeden çalışıyor', () async {
      // Kaynak kimlikleri null; aynalama yolu bunu sessizce geçmeli.
      await StorageService.instance.addAnalysis(
        source: _game('Serbest oyun'),
        review: StoredReview(
          deep: false,
          at: DateTime.now(),
          whiteAccuracy: 70,
          blackAccuracy: 60,
          moves: const [],
        ),
      );
      final list = (await StorageService.instance.loadAnalysisLists()).first;
      final record = list.games.first;
      expect(record.sourcePlaylistId, isNull);

      final read =
          await StorageService.instance.toggleGameRead(list.id, record.id);
      expect(read, isTrue);
      final favorite =
          await StorageService.instance.toggleGameFavorite(list.id, record.id);
      expect(favorite, isTrue);

      final again = (await StorageService.instance.loadAnalysisLists()).first;
      expect(again.games.first.read, isTrue);
      expect(again.games.first.favorite, isTrue);
    });
  });
}
