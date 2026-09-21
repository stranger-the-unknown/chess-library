import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

import '../../l10n/app_strings.dart';
import 'search_result.dart';
import 'stockfish_android.dart';
import 'stockfish_uci.dart';

export 'search_result.dart' show SearchResult;

/// Motorun oyun gücü kademeleri.
///
/// [skill] değeri Stockfish `Skill Level` (0–20) ile birebir eşlenir.
/// Usta (20) tam güçtür (`UCI_LimitStrength` kapalı). Daha düşük
/// kademelerde Skill Level + LimitStrength/Elo uygulanır; arayüzde Elo
/// metni gösterilmez.
class EngineLevel {
  /// Çeviri tablosundaki sıra numarası (`level.<index>.name`).
  final int index;
  final int depth;
  final int movetimeMs;
  final int skill;

  const EngineLevel({
    required this.index,
    required this.depth,
    required this.movetimeMs,
    required this.skill,
  });

  String get name => t('level.$index.name');

  String get description => t('level.$index.desc');

  /// Tam güç (Usta): Skill 20, LimitStrength kapalı.
  bool get isFullStrength => skill >= 20;

  static const List<EngineLevel> all = [
    EngineLevel(
      index: 0,
      depth: 1,
      movetimeMs: 150,
      skill: 2,
    ),
    EngineLevel(
      index: 1,
      depth: 2,
      movetimeMs: 300,
      skill: 5,
    ),
    EngineLevel(
      index: 2,
      depth: 4,
      movetimeMs: 700,
      skill: 9,
    ),
    EngineLevel(
      index: 3,
      depth: 6,
      movetimeMs: 1400,
      skill: 13,
    ),
    EngineLevel(
      index: 4,
      depth: 9,
      movetimeMs: 2500,
      skill: 17,
    ),
    EngineLevel(
      index: 5,
      depth: 20,
      movetimeMs: 5000,
      skill: 20,
    ),
  ];
}

/// Tüm motor hamleleri resmi Stockfish UCI sürecinden gelir.
///
/// Dart motoru / Isolate yoktur. SF yoksa veya çökerse boş [SearchResult]
/// döner; arayüz asılı kalmaz.
class EngineService {
  static final EngineService instance = EngineService._();
  EngineService._();

  StockfishUci? _stockfish;
  /// İkili bulunamadığında tekrar tekrar denemeyi keser; dispose ile sıfırlanır.
  bool _binaryMissing = false;

  /// İnceleme / canlı analiz / bulmaca: tam güç Stockfish.
  Future<SearchResult> analyze(
    String fen, {
    int depth = 12,
    int movetimeMs = 1500,
    int skill = 20,
    List<int> repetitionHashes = const [],
    void Function(SearchResult partial)? onProgress,
  }) async {
    // skill / repetitionHashes API uyumu için duruyor; SF yolu tam güç kullanır.
    final sf = await _ensureStockfish();
    if (sf == null) return SearchResult.empty;

    final result = await sf.analyze(
      fen,
      depth: depth,
      movetimeMs: movetimeMs,
      skillLevel: 20,
      limitStrength: false,
      threads: analysisThreads,
      hashMb: analysisHashMb,
      onProgress: onProgress,
    );
    if (result == null) {
      // Çöküş / timeout: bir kez yeniden başlatmayı dene (sonraki çağrı için).
      await _recoverStockfish();
      return SearchResult.empty;
    }
    return result;
  }

  /// Analizde kullanılacak çekirdek sayısı.
  ///
  /// Telefonda tek çekirdek (pil); masaüstünde çekirdeklerin yarısı, en
  /// çok dört. Oyun hamlesi bundan etkilenmiyor — orası her platformda
  /// tek çekirdek, ki kademelerin anlamı cihazdan cihaza değişmesin.
  static int get analysisThreads {
    if (kIsWeb) return 1;
    if (Platform.isAndroid || Platform.isIOS) return 1;
    return (Platform.numberOfProcessors / 2).floor().clamp(1, 4);
  }

  /// Analizde kullanılacak hash boyutu (MB). Telefonda küçük kalıyor.
  static int get analysisHashMb {
    if (kIsWeb) return 64;
    if (Platform.isAndroid || Platform.isIOS) return 64;
    return 128;
  }

  /// Motora karşı oyun: seviye → Skill Level (+ LimitStrength/Elo).
  Future<SearchResult> bestMoveForLevel(String fen, EngineLevel level) async {
    final sf = await _ensureStockfish();
    if (sf == null) return SearchResult.empty;

    final full = level.isFullStrength;
    final result = await sf.analyze(
      fen,
      depth: level.depth,
      movetimeMs: level.movetimeMs,
      skillLevel: level.skill.clamp(0, 20),
      limitStrength: !full,
      elo: full ? null : StockfishUci.eloForSkill(level.skill),
    );
    if (result == null) {
      await _recoverStockfish();
      return SearchResult.empty;
    }
    return result;
  }

  Future<StockfishUci?> _ensureStockfish() async {
    if (kIsWeb) return null;
    final envPath = Platform.environment['STOCKFISH_PATH'];
    final forceViaEnv = envPath != null && envPath.isNotEmpty;
    // Windows/Android üretim; STOCKFISH_PATH ile test/CI (Linux dahil).
    if (!(Platform.isWindows || Platform.isAndroid || forceViaEnv)) {
      // Diğer masaüstü: yine de yerel aday yolları dene.
      if (!Platform.isLinux && !Platform.isMacOS) return null;
    }
    if (_stockfish != null && _stockfish!.isRunning) return _stockfish;

    // Android: her denemede ensure + başarılıysa kalıcı "missing" bayrağını aç.
    // Geçici çıkartma/exec hatası sonrasında motorun sonsuza kilitlenmesini önler.
    if (Platform.isAndroid) {
      final ensured = await ensureAndroidStockfishBinary();
      if (ensured != null) {
        _binaryMissing = false;
      }
    }

    if (_binaryMissing) return null;

    final resolved = await StockfishUci.resolveBinaryPath();
    if (resolved == null && !forceViaEnv) {
      _binaryMissing = true;
      return null;
    }

    final engine = StockfishUci();
    if (await engine.start()) {
      _stockfish = engine;
      _binaryMissing = false;
      return engine;
    }
    await engine.dispose();
    _stockfish = null;
    // İkili vardı ama start başarısız: bayrağı kilitleme; sonraki çağrıda tekrar dene.
    return null;
  }

  Future<void> _recoverStockfish() async {
    final sf = _stockfish;
    // Bu arada yeni bir arama başladıysa süreci öldürme: eski aramanın
    // hatası yüzünden yenisini kesmiş olurduk.
    if (sf != null && sf.hasActiveSearch) return;
    try {
      await sf?.dispose();
    } catch (_) {}
    _stockfish = null;
    // binaryMissing'i açma — ikili yoksa zaten true kalır.
  }

  /// Canlı analiz / inceleme iptali: SF `stop` (UI asılı kalmasın).
  Future<void> stopAnalysis() async {
    await _stockfish?.stopSearch();
  }

  /// Süren aramayı iptal eder.
  Future<void> cancel() async {
    await stopAnalysis();
    await dispose();
  }

  Future<void> dispose() async {
    await _stockfish?.dispose();
    _stockfish = null;
    _binaryMissing = false;
  }
}
