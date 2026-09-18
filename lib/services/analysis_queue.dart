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
/// Kullanıcı bir listeden istediği oyunları seçip "Analiz" diyor; kuyruk
/// onları teker teker inceleyip sonuçları "Son Analizler" listesine
/// yazıyor. Amaç kullanıcının başında beklememesi.
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

  /// Kuyruğun dışında süren tek oyunluk inceleme sayısı.
  ///
  /// Tahta ekranından başlatılan inceleme kuyruğa girmiyor — sonucu
  /// ekranda anında görmek isteniyor. Ama kullanıcı ekrandan çıkarsa iş
  /// sürüyor; şeritte görünmesi için burada sayılıyor.
  int _external = 0;
  String? _externalName;

  /// Kuyruk ya da tek oyunluk bir inceleme sürüyor mu?
  bool get isRunning => _running || _external > 0;

  /// Yalnızca tek oyunluk bir inceleme mi sürüyor?
  ///
  /// Şerit buna göre değişiyor: tek incelemenin ilerleme sayısı ve iptali
  /// yok (motorun durdurma yolu yok), yalnızca adı gösteriliyor.
  bool get isSingleReview => !_running && _external > 0;

  /// Biten oyun sayısı.
  int get done => _done;

  /// Kuyruktaki toplam oyun sayısı.
  int get total => _total;

  /// Şu an incelenen oyunun adı.
  String? get current => _current ?? _externalName;

  /// Tahta ekranındaki incelemeyi şeride bildirir.
  ///
  /// İş kuyruğa girmiyor, yalnızca "sürüyor" diye görünüyor. Sayaç
  /// [Future] hata verse de `finally` içinde düşüyor; düşmezse şerit
  /// sonsuza kadar ekranda kalırdı.
  ///
  /// Ekran kilidi bilerek alınmıyor: tek oyunluk inceleme kısa sürüyor ve
  /// kilit burada da alınırsa, aynı anda süren bir toplu analiz varken
  /// inceleme bitince kilit erkenden bırakılırdı.
  Future<T> trackExternal<T>(String name, Future<T> Function() task) async {
    _external++;
    _externalName = name;
    notifyListeners();
    try {
      return await task();
    } finally {
      _external--;
      if (_external == 0) _externalName = null;
      notifyListeners();
    }
  }

  /// Oyunları kuyruğa ekler ve gerekiyorsa çalışmayı başlatır.
  ///
  /// Kuyruk zaten çalışıyorsa yeni işler sonuna eklenir; iki toplu analiz
  /// aynı anda çalışmaz, çünkü motor tek ve sıraya girmeleri gerekiyor.
  Future<void> enqueue({
    required String playlistId,
    required List<SavedGame> games,
  }) async {
    if (games.isEmpty) return;
    for (final game in games) {
      _jobs.add(_Job(playlistId: playlistId, game: game));
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
        );
        await StorageService.instance.addAnalysis(
          source: job.game,
          sourcePlaylistId: job.playlistId,
          review: toStoredReview(review),
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

/// Seçilen oyunları analiz sırasına dizer: **numarası büyük olan önce**.
///
/// Analiz listesine her yeni kayıt başa ekleniyor. Oyunlar düz sırayla
/// işlenseydi liste tersine dönerdi: 1., 2., 3. oyunu seçen kullanıcı
/// analiz listesinde 3., 2., 1. görürdü. Sondan başlayınca listedeki
/// sıra kaynak listedekiyle aynı oluyor.
///
/// [numbers] oyunun kimliğinden listedeki sıra numarasına eşleme;
/// numarası olmayan oyun sıfır sayılır ve sona düşer.
List<SavedGame> analysisOrder(
  List<SavedGame> games,
  Map<String, int> numbers,
) {
  return [...games]
    ..sort((a, b) => (numbers[b.id] ?? 0).compareTo(numbers[a.id] ?? 0));
}

/// İncelemeyi saklanabilir biçime çevirir.
///
/// Hamlelerin kendisi oyunda duruyor; burada yalnızca motorun söyledikleri
/// saklanıyor.
StoredReview toStoredReview(GameReview review, {bool deep = true}) {
  return StoredReview(
    deep: true, // tek profil; alan uyumluluk için true
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

/// Kaydedilmiş incelemeyi yeniden kurar.
///
/// Hamlelerin kendisi oyunda duruyor; kayıtta yalnızca motorun
/// söyledikleri var. Motorun önerdiği hamlenin SAN karşılığı da
/// kaydedilmiyor, pozisyondan yeniden üretiliyor — aynı bilgiyi iki kez
/// saklamak yerine.
///
/// Kayıt ile oyunun hamleleri uyuşmuyorsa (kayıt bozulmuşsa) null döner;
/// çağıran yeniden analiz eder.
GameReview? fromStoredReview(
  StoredReview stored,
  List<MoveEntry> history, {
  String? startFen,
}) {
  if (stored.moves.length != history.length) return null;

  final position = startFen == null
      ? engine.ChessGame()
      : engine.ChessGame.fromFen(startFen);
  final moves = <ReviewedMove>[];

  for (int i = 0; i < history.length; i++) {
    final saved = stored.moves[i];
    final mover = position.sideToMove;

    String bestSan = saved.bestMoveUci;
    final best = position.moveFromUci(saved.bestMoveUci);
    if (best != null) bestSan = position.sanFor(best);

    moves.add(
      ReviewedMove(
        index: i,
        entry: history[i],
        mover: mover,
        bestScoreCp: saved.bestScoreCp,
        playedScoreCp: saved.playedScoreCp,
        bestMoveUci: saved.bestMoveUci,
        bestMoveSan: bestSan,
        quality: MoveQuality.values[
            saved.quality.clamp(0, MoveQuality.values.length - 1)],
        accuracy: saved.accuracy,
      ),
    );

    final played = position.moveFromUci(history[i].move.uci);
    if (played == null) return null;
    position.makeMove(played);
  }

  return GameReview(
    moves: moves,
    whiteAccuracy: stored.whiteAccuracy,
    blackAccuracy: stored.blackAccuracy,
    startFen: startFen ?? engine.ChessGame().fen,
  );
}

class _Job {
  final String playlistId;
  final SavedGame game;

  const _Job({
    required this.playlistId,
    required this.game,
  });
}
