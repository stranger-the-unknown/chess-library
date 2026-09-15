import 'dart:async';

import '../../l10n/app_strings.dart';
import 'search_result.dart';
import 'stockfish_engine.dart';

export 'search_result.dart';

/// Motora karşı oynarken seçilen güç.
///
/// Stockfish'in kendi zayıflatma düzeneği kullanılıyor. İki ayrı yol var
/// ve ikisi de gerekli:
///
///  * `UCI_Elo` motoru doğrudan bir dereceye sabitliyor ama **alt sınırı
///    1320**. Onun üstündeki seviyelerde bu kullanılıyor, yani ekranda
///    yazan rakam motorun gerçekten hedeflediği derece.
///  * Daha zayıf iki seviyede `Skill Level` ve sığ arama kullanılıyor;
///    oradaki derece rakamı yaklaşık bir karşılıktır.
class EngineLevel {
  /// Çeviri tablosundaki sıra numarası (`level.<index>.name`).
  final int index;
  final int depth;
  final int movetimeMs;

  /// Stockfish'in `Skill Level` değeri (0-20).
  final int skill;

  /// `UCI_Elo` ile sabitlenecek derece; null ise [skill] kullanılır.
  final int? elo;

  /// Ekranda gösterilen yaklaşık derece.
  final int approximateElo;

  const EngineLevel({
    required this.index,
    required this.depth,
    required this.movetimeMs,
    required this.skill,
    required this.approximateElo,
    this.elo,
  });

  String get name => t('level.$index.name');

  String get description => t('level.$index.desc');

  static const List<EngineLevel> all = [
    // Skill 0 ve tek yarım hamlelik arama: motor gerçekten hata yapsın.
    EngineLevel(
      index: 0,
      depth: 1,
      movetimeMs: 150,
      skill: 0,
      approximateElo: 800,
    ),
    EngineLevel(
      index: 1,
      depth: 3,
      movetimeMs: 300,
      skill: 3,
      approximateElo: 1100,
    ),
    // Buradan sonrası UCI_Elo; rakamlar motorun hedefi.
    EngineLevel(
      index: 2,
      depth: 20,
      movetimeMs: 700,
      skill: 20,
      elo: 1400,
      approximateElo: 1400,
    ),
    EngineLevel(
      index: 3,
      depth: 20,
      movetimeMs: 1000,
      skill: 20,
      elo: 1800,
      approximateElo: 1800,
    ),
    EngineLevel(
      index: 4,
      depth: 22,
      movetimeMs: 1500,
      skill: 20,
      elo: 2300,
      approximateElo: 2300,
    ),
    EngineLevel(
      index: 5,
      depth: 24,
      movetimeMs: 2500,
      skill: 20,
      elo: 2850,
      approximateElo: 2850,
    ),
  ];
}

/// Uygulamanın motorla tek temas noktası.
///
/// Arkasında Stockfish çalışıyor; ekranlar ve inceleme kodu bunu
/// bilmiyor, yalnızca [analyze] ve [bestMoveForLevel] görüyor. Motor bir
/// gün yine değişirse değişecek yer burası.
class EngineService {
  static final EngineService instance = EngineService._();
  EngineService._();

  StockfishEngine get _engine => StockfishEngine.instance;

  Future<SearchResult> analyze(
    String fen, {
    int depth = 12,
    int movetimeMs = 1000,
    int skill = 20,
    List<String> moves = const <String>[],
    void Function(SearchResult partial)? onProgress,
  }) {
    return _engine.analyze(
      fen,
      depth: depth,
      movetimeMs: movetimeMs,
      skill: skill,
      moves: moves,
      onProgress: onProgress,
    );
  }

  /// Belirli bir seviyeye göre hamle üretir.
  Future<SearchResult> bestMoveForLevel(String fen, EngineLevel level) {
    return _engine.analyze(
      fen,
      depth: level.depth,
      movetimeMs: level.movetimeMs,
      skill: level.skill,
      elo: level.elo,
    );
  }

  /// Süren aramayı keser.
  Future<void> cancel() async => _engine.stop();
}
