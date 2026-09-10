import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import 'settings_service.dart';

/// Hamle sesleri ve titreşim.
///
/// Ses kümesi ve öncelik sırası chess.com ile aynıdır: şah çekilen hamle
/// "move-check", rok "castle", terfi "promote", alma "capture", kendi
/// hamlen "move-self", rakibin hamlesi "move-opponent".
///
/// "illegal" sesi yalnızca **şah altındayken** kural dışı bir hamle
/// denendiğinde çalar; bkz. [playIllegalMove].
///
/// Her ses için ayrı bir oynatıcı önceden hazırlanır; çalmak yalnızca başa
/// sarıp `play()` demektir. (Tek oynatıcıya her seferinde `setAsset`
/// çağırmak ilk hamlede belirgin gecikmeye yol açıyordu.)
class SoundService {
  static final SoundService instance = SoundService._();
  SoundService._();

  static const String moveSelf = 'move-self';
  static const String moveOpponent = 'move-opponent';
  static const String capture = 'capture';
  static const String castle = 'castle';
  static const String promote = 'promote';
  static const String check = 'move-check';
  static const String illegal = 'illegal';
  static const String gameStart = 'game-start';
  static const String gameEnd = 'game-end';
  static const String notify = 'notify';
  static const String premove = 'premove';
  static const String tenSeconds = 'tenseconds';

  static const List<String> _names = [
    moveSelf,
    moveOpponent,
    capture,
    castle,
    promote,
    check,
    illegal,
    gameStart,
    gameEnd,
    notify,
    premove,
    tenSeconds,
  ];

  final Map<String, AudioPlayer> _players = {};

  /// Yükleme bitene kadar bekleyenler bu Future'a bağlanır; böylece
  /// hazırlık sırasında gelen ilk hamle sesi kaybolmaz ve aynı anda iki
  /// yükleme başlamaz.
  Future<void>? _loading;
  bool _ready = false;

  Future<void> init() {
    if (_ready) return Future<void>.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    for (final name in _names) {
      try {
        final player = AudioPlayer();
        await player.setAsset('assets/sounds/$name.mp3');
        _players[name] = player;
      } catch (_) {
        // Ses dosyası yüklenemezse uygulama sessiz çalışmaya devam eder.
      }
    }
    _ready = true;
    _loading = null;
  }

  /// Testler için: çalınan her sesin adını bildirir.
  ///
  /// Ses donanımı olmayan ortamda hangi sesin çalındığını (ya da
  /// çalınmadığını) doğrulamayı sağlar.
  @visibleForTesting
  void Function(String name)? debugOnPlay;

  Future<void> play(String name) async {
    if (!SettingsService.instance.soundEnabled) return;
    debugOnPlay?.call(name);
    if (!_ready) {
      await init();
      // Yükleme uzun sürdüyse ses artık güncel değildir; yine de çal.
    }
    final player = _players[name];
    if (player == null) return;
    try {
      // Aynı ses üst üste gelirse baştan başlat.
      if (player.playing) await player.pause();
      await player.seek(Duration.zero);
      unawaited(player.play());
    } catch (_) {
      // Oynatma hatası oyun akışını bölmemeli.
    }
  }

  static void unawaited(Future<void> future) {
    future.catchError((_) {});
  }

  void _vibrate({bool strong = false}) {
    if (!SettingsService.instance.hapticsEnabled) return;
    if (strong) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.selectionClick();
    }
  }

  /// Oynanan hamlenin türüne göre uygun sesi çalar.
  ///
  /// [opponent] rakibin (ya da motorun) hamlesi için farklı bir ses çalar.
  void playMoveSound({
    bool isCapture = false,
    bool isCastle = false,
    bool isPromotion = false,
    bool isCheck = false,
    bool gameOver = false,
    bool opponent = false,
  }) {
    if (gameOver) {
      play(gameEnd);
      _vibrate(strong: true);
      return;
    }
    if (isCheck) {
      play(check);
      _vibrate(strong: true);
      return;
    }
    if (isPromotion) {
      play(promote);
    } else if (isCastle) {
      play(castle);
    } else if (isCapture) {
      play(capture);
    } else {
      play(opponent ? moveOpponent : moveSelf);
    }
    _vibrate();
  }

  /// SAN gösteriminden hamle türünü çıkararak sesi çalar.
  void playForSan(String san, {bool opponent = false}) {
    playMoveSound(
      isCapture: san.contains('x'),
      isCastle: san.startsWith('O-O'),
      isPromotion: san.contains('='),
      isCheck: san.endsWith('+'),
      gameOver: san.endsWith('#'),
      opponent: opponent,
    );
  }

  /// Tahtada kural dışı bir hamle denemesi.
  ///
  /// Ses yalnızca hamle sırası olan taraf **şah altındayken** çalar:
  /// oradaki anlamı "bu hamle şahı kurtarmıyor" uyarısıdır. Şah yokken
  /// geçersiz bir kareye tıklamak sessizdir — kullanıcı tahtada
  /// dolaşırken, taş seçip vazgeçerken sürekli uyarı sesi duymamalı.
  /// (chess.com'un davranışı da böyledir.)
  void playIllegalMove({required bool inCheck}) {
    if (!inCheck) return;
    play(illegal);
    _vibrate(strong: true);
  }

  /// Kurallara uygun ama **yanlış** hamle: bulmacada çözüm değil,
  /// açılış alıştırmasında beklenen hamle değil.
  ///
  /// Bu bir kural dışılık uyarısı değil, "yanlış cevap" geri bildirimidir;
  /// bu yüzden şah durumundan bağımsız olarak her zaman çalar.
  void playWrong() {
    play(illegal);
    _vibrate(strong: true);
  }

  void playGameStart() => play(gameStart);

  void playGameEnd() {
    play(gameEnd);
    _vibrate(strong: true);
  }

  /// Bulmaca doğru çözüldüğünde / bildirim.
  void playNotify() {
    play(notify);
    _vibrate();
  }

  void playPremove() => play(premove);

  /// Süre uyarısı (zamanlı bulmaca modu).
  void playTenSeconds() => play(tenSeconds);

  void dispose() {
    for (final player in _players.values) {
      player.dispose();
    }
    _players.clear();
    _ready = false;
  }
}
