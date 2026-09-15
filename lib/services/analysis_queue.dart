import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/chess_engine.dart' as engine;
import '../models/move_entry.dart';
import '../models/playlist.dart';
import '../models/stored_review.dart';
import 'game_review.dart';
import 'storage_service.dart';

/// Sırayla çalışan toplu analiz.
///
/// Kullanıcı bir listeden istediği oyunları seçip "hızlı" ya da "derin"
/// diyor; kuyruk onları teker teker inceleyip sonuçları analiz
/// listelerine yazıyor. Amaç kullanıcının başında beklememesi.
///
/// **Her oyun bitince kaydediliyor**, hepsi bitince değil. Uygulama
/// yarıda kapanırsa o ana kadar bitenler duruyor; yalnızca kalanlar
/// yapılmamış oluyor. Sonda tek seferde kaydetmek, yüz oyunluk bir işin
/// doksan dokuzuncuda kesilmesi hâlinde her şeyi çöpe atardı.
///
/// Sınır: iş uygulama açıkken sürüyor. Telefon uykuya geçerse Android
/// uygulamayı askıya alabilir ve kuyruk orada durur; uygulama yeniden
/// açıldığında kalanlar yeniden başlatılabilir.
/// Ekranı açık tutma; testlerde yerine sahtesi konabilsin diye ayrı.
abstract class ScreenLock {
  Future<void> enable();
  Future<void> disable();
}

class _WakelockScreenLock implements ScreenLock {
  const _WakelockScreenLock();

  @override
  Future<void> enable() => WakelockPlus.enable();

  @override
  Future<void> disable() => WakelockPlus.disable();
}

class AnalysisQueue extends ChangeNotifier {
  static final AnalysisQueue instance = AnalysisQueue._();
  AnalysisQueue._();

  /// Analiz sürerken ekranı açık tutar.
  ///
  /// Telefon uykuya geçerse Android uygulamayı askıya alır ve kuyruk
  /// orada durur; kullanıcı da "telefonu bırakıp gel" diyemez. Kilit
  /// **her durumda** bırakılmalı — bırakılmazsa ekran sonsuza kadar
  /// açık kalır, bu eklentiyi kullanan uygulamaların en sık hatası
  /// budur. Bu yüzden `finally` içinde bırakılıyor ve testle
  /// denetleniyor.
  @visibleForTesting
  ScreenLock screenLock = const _WakelockScreenLock();

  final List<_Job> _jobs = <_Job>[];
  bool _running = false;
  bool _cancelled = false;
  int _done = 0;
  int _total = 0;
  String? _current;

  /// Kuyruk çalışıyor mu?
  bool get isRunning => _running;

  /// Biten oyun sayısı.
  int get done => _done;

  /// Kuyruktaki toplam oyun sayısı.
  int get total => _total;

  /// Şu an incelenen oyunun adı.
  String? get current => _current;

  /// Kuyruktaki işler derin inceleme mi?
  bool get deep => _jobs.isNotEmpty ? _jobs.first.deep : _lastDeep;
  bool _lastDeep = false;

  /// Oyunları kuyruğa ekler ve gerekiyorsa çalışmayı başlatır.
  ///
  /// Kuyruk zaten çalışıyorsa yeni işler sonuna eklenir; iki toplu analiz
  /// aynı anda çalışmaz, çünkü motor tek ve sıraya girmeleri gerekiyor.
  Future<void> enqueue({
    required String playlistId,
    required List<SavedGame> games,
    required bool deep,
  }) async {
    if (games.isEmpty) return;
    _lastDeep = deep;
    for (final game in games) {
      _jobs.add(_Job(playlistId: playlistId, game: game, deep: deep));
    }
    _total += games.length;
    notifyListeners();
    if (!_running) await _run();
  }

  /// Kalan işleri iptal eder; biten analizler kalır.
  void cancel() {
    _cancelled = true;
    _jobs.clear();
    notifyListeners();
  }

  Future<void> _run() async {
    _running = true;
    _cancelled = false;
    notifyListeners();
    try {
      await screenLock.enable();
    } catch (error) {
      // Ekran kilidi kurulamazsa analiz yine de yapılsın.
      debugPrint('Ekran açık tutulamadı: $error');
    }

    try {
      await _process();
    } finally {
      try {
        await screenLock.disable();
      } catch (error) {
        debugPrint('Ekran kilidi bırakılamadı: $error');
      }
      _running = false;
      _current = null;
      if (_jobs.isEmpty) {
        _done = 0;
        _total = 0;
      }
      notifyListeners();
    }
  }

  Future<void> _process() async {
    while (_jobs.isNotEmpty && !_cancelled) {
      final job = _jobs.removeAt(0);
      _current = job.game.name;
      notifyListeners();

      try {
        final review = await GameReviewer().review(
          _historyOf(job.game),
          startFen: job.game.startFen,
          deep: job.deep,
        );
        await StorageService.instance.addAnalysis(
          source: job.game,
          sourcePlaylistId: job.playlistId,
          review: toStoredReview(review, deep: job.deep),
        );
      } catch (error) {
        // Tek bir oyun çözümlenemezse kuyruk durmamalı; yüz oyunluk bir
        // iş tek bozuk kayıt yüzünden yarıda kalmasın.
        debugPrint('Analiz atlandı (${job.game.name}): $error');
      }

      _done++;
      notifyListeners();
    }
  }

  /// Kayıtlı hamlelerden inceleme için gereken geçmişi kurar.
  List<MoveEntry> _historyOf(SavedGame game) {
    final position = game.startFen == null
        ? engine.ChessGame()
        : engine.ChessGame.fromFen(game.startFen!);
    final history = <MoveEntry>[];
    for (final uci in game.uciMoves) {
      final move = position.moveFromUci(uci);
      if (move == null) break;
      final san = position.sanFor(move);
      position.makeMove(move);
      history.add(
        MoveEntry(move: move, san: san, fenAfter: position.fen),
      );
    }
    return history;
  }
}

/// İncelemeyi saklanabilir biçime çevirir.
///
/// Hamlelerin kendisi oyunda duruyor; burada yalnızca motorun söyledikleri
/// saklanıyor.
StoredReview toStoredReview(GameReview review, {required bool deep}) {
  return StoredReview(
    deep: deep,
    at: DateTime.now(),
    whiteAccuracy: review.whiteAccuracy,
    blackAccuracy: review.blackAccuracy,
    moves: [
      for (final move in review.moves)
        StoredReviewMove(
          bestScoreCp: move.bestScoreCp,
          playedScoreCp: move.playedScoreCp,
          bestMoveUci: move.bestMoveUci,
          quality: move.quality.index,
          accuracy: move.accuracy,
        ),
    ],
  );
}

class _Job {
  final String playlistId;
  final SavedGame game;
  final bool deep;

  const _Job({
    required this.playlistId,
    required this.game,
    required this.deep,
  });
}
