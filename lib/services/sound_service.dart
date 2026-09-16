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

  /// Her ses kendi hazırlık Future'ını taşır.
  ///
  /// Eskiden on iki dosya sırayla yükleniyor ve "hazır" bayrağı ancak
  /// hepsi bitince kalkıyordu; uygulamanın ilk açılışında ilk hamle bu
  /// pencereye denk geldiğinde ses duyulmuyordu. Artık her ses bağımsız
  /// hazırlanır ve `play()` yalnızca **kendi** dosyasını bekler, hepsini
  /// değil. Aynı ses için ikinci bir yükleme de başlamaz.
  final Map<String, Future<AudioPlayer?>> _players = {};

  Future<AudioPlayer?> _playerFor(String name) {
    return _players.putIfAbsent(name, () async {
      try {
        // Ses odağı istenmiyor.
        //
        // Varsayılan davranışta just_audio **kalıcı** ses odağı alıyor;
        // bu, çalan müziğe "artık sus" demek oluyor ve müzik uygulaması
        // hamle sesi bitince geri dönmüyor. Hamle sesleri kısa arayüz
        // sesleri: müziğin üstüne karışmaları gerekiyor, onu
        // durdurmaları değil.
        final player = AudioPlayer(handleAudioSessionActivation: false);
        await player.setAsset('assets/sounds/$name.mp3');
        return player;
      } catch (_) {
        // Ses dosyası yüklenemezse o ses sessiz kalır, uygulama sürer.
        return null;
      }
    });
  }

  /// Bütün sesleri önceden hazırlar (uygulama açılışında çağrılır).
  ///
  /// Paralel yüklenir: sırayla yüklemek ilk hamleye kadar geçen süreyi
  /// gereksiz yere uzatıyordu.
  Future<void> init() => Future.wait(_names.map(_playerFor));

  /// Testler için: çalınan her sesin adını bildirir.
  ///
  /// Ses donanımı olmayan ortamda hangi sesin çalındığını (ya da
  /// çalınmadığını) doğrulamayı sağlar.
  @visibleForTesting
  void Function(String name)? debugOnPlay;

  Future<void> play(String name) async {
    if (!SettingsService.instance.soundEnabled) return;
    debugOnPlay?.call(name);

    // Yalnızca bu sesin hazır olmasını bekler; diğerleri hâlâ
    // yükleniyor olabilir.
    final player = await _playerFor(name);
    if (player == null) return;

    try {
      // Başa sarma yalnızca gerektiğinde yapılır. Yeni yüklenmiş bir
      // oynatıcı zaten başta durur; oradaki gereksiz `seek` bazı
      // platformlarda ilk çalmayı yutuyordu.
      if (player.playing) await player.pause();
      if (player.position > Duration.zero) {
        await player.seek(Duration.zero);
      }
      unawaited(player.play());
    } catch (_) {
      // Oynatma hatası oyun akışını bölmemeli.
    }
  }

  static void unawaited(Future<void> future) {
    future.catchError((_) {});
  }

  /// Dokunsal geri bildirim.
  ///
  /// Kendi ayarı var ama sese bağımlı: ses kapatılınca titreşim de
  /// kapanıyor (bkz. [SettingsService.soundEnabled]), o yüzden burada
  /// tek bir denetim yetiyor.
  void _vibrate({bool strong = false}) {
    if (!SettingsService.instance.vibrationEnabled) return;
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

  Future<void> dispose() async {
    // Hazırlığı süren oynatıcılar da kapatılmalı; yoksa yükleme bitince
    // ortada sahipsiz bir oynatıcı kalır.
    final pending = _players.values.toList();
    _players.clear();
    for (final future in pending) {
      try {
        (await future)?.dispose();
      } catch (_) {
        // Kapatma hatası önemsiz.
      }
    }
  }
}
