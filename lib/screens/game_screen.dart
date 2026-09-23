import 'dart:async';

import 'package:flutter/material.dart';

import '../widgets/responsive.dart';

import 'package:flutter/services.dart';

import '../l10n/app_strings.dart';
import '../models/chess_engine.dart' as engine;
import '../models/move_entry.dart';
import '../models/repetition.dart';
import '../models/pgn_parser.dart';
import '../models/playlist.dart';
import '../services/board_image_service.dart';
import '../services/engine/engine_service.dart';
import '../services/unsaved_work.dart';
import '../services/settings_service.dart';
import '../services/screen_awake.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/captured_pieces.dart';
import '../widgets/chess_board_widget.dart';
import '../widgets/move_list.dart';
import 'board_editor_screen.dart';
import '../widgets/cursors.dart';

enum GameMode {
  /// PGN okuma / serbest analiz.
  analysis,

  /// Cihazdaki motora karşı oyun.
  versusEngine,
}

/// Tahta ekranı: PGN okuma, serbest oynama, analiz ve motora karşı oyun.
class GameScreen extends StatefulWidget {
  final GameMode mode;
  final String? pgnContent;
  final List<String>? uciMoves;
  final String? startFen;
  final String? title;
  final String? initialResult;

  /// Motora karşı oyunda kullanıcının rengi.
  final engine.Color playerColor;

  /// Motora karşı oyunda seviye (yoksa ayarlardaki seviye).
  final int? engineLevelIndex;

  /// Oyuncuların adları (PGN'den). Tahtanın üstünde ve altında
  /// gösterilir; tahta döndüğünde yer değiştirirler.
  final String? whiteName;
  final String? blackName;

  const GameScreen({
    super.key,
    this.mode = GameMode.analysis,
    this.pgnContent,
    this.uciMoves,
    this.startFen,
    this.title,
    this.initialResult,
    this.playerColor = engine.Color.white,
    this.engineLevelIndex,
    this.whiteName,
    this.blackName,
    this.initialWarning,
  });

  /// Açılışta gösterilecek uyarı (ör. eksik okunan PGN).
  ///
  /// Tek oyunluk bir PGN dosyası ayrıştırıldıktan sonra buraya hamle
  /// listesi olarak geliyor; atlanan hamle, okunamayan FEN ya da
  /// kapanmamış yorum bilgisi yolda kayboluyordu.
  final String? initialWarning;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late String _startFen;
  late engine.ChessGame _game;

  final List<MoveEntry> _history = [];
  int _cursor = -1;

  bool _flipped = false;
  String? _resultText;
  String? _warning;

  /// Pes edildi mi? (Oyun bitmiş sayılır, tahta kilitlenir.)
  bool _resigned = false;

  /// Oyun bir listeye kaydedildi mi?
  ///
  /// Kaydedilmemiş bir oyunda geri tuşu hamleleri sessizce siliyordu.
  bool _savedToList = false;

  /// Motor hamlesi aramalarının nesil sayacı.
  ///
  /// Motor düşünürken hamle listesinde gezinmek konumu değiştiriyor;
  /// dönen sonuç artık geçersiz. Eskiden yalnızca FEN'e bakılıyordu:
  /// aynı konuma geri dönüldüğünde (ya da yeniden başlatıp aynı
  /// başlangıca gelince) iki arama birden geçerli sayılıp çift hamle
  /// oynanabiliyordu. Sayaç, yalnızca en son aramanın hamlesini kabul
  /// ediyor.
  int _engineToken = 0;

  /// Motor cevap veremedi mi?
  ///
  /// Motora karşı oyunda tahta yalnızca senin rengine açık. Motor boş
  /// cevap dönerse sıra motorda kalıyor ve hiç hamle yapamıyordun: tek
  /// çıkış oyunu yeniden başlatmaktı. Bu bayrak açıkken tahta iki tarafa
  /// da açılıyor, oyuna elle devam edebiliyorsun.
  bool _engineStalled = false;

  /// Başlangıç konumunda sıra siyahta mı? (Hamle listesi numarası.)
  bool _blackFirst = false;

  /// Son hamle canlandırılsın mı? Geri giderken ve uzağa atlarken
  /// kapatılıyor: taşın ileri doğru kayması geriye gidişte yanıltıyor.
  bool _animateBoard = true;

  /// Kayıtlı bir oyunu incelerken denenen hamleler.
  ///
  /// Bu hamleler oyunun kendisine yazılmaz: hamle listesinde görünmezler,
  /// PGN'e girmezler ve ekrandan çıkınca kaybolurlar. Amaç "şu hamle
  /// oynansaydı motor ne derdi?" sorusunu tahtada denemektir.
  final List<MoveEntry> _explore = [];

  /// Ekran hazır bir oyunu (PGN ya da kayıtlı oyun) gösteriyor mu?
  ///
  /// Böyle bir oyunda tahtaya oynanan hamleler oyunu değiştirmez, deneme
  /// sayılır. Serbest tahtada ise hamleler oyunun kendisidir. Okunamayan
  /// bir PGN hamle üretmediyse ekran yine serbest tahta gibi davranır.
  /// Kaybolacak bir şey var mı? (Kayıtlı bir oyunu okurken yok: oradaki
  /// hamleler deneme sayılıyor ve oyunun kendisine yazılmıyor.)
  bool get _unsaved =>
      !_replayMode && _history.isNotEmpty && !_savedToList;

  Future<void> _onPopInvoked(bool didPop, Object? result) async {
    if (didPop || !mounted) return;
    final leave = await AppDialogs.confirm(
      context,
      title: t('game.exitTitle'),
      message: t('game.exitMessage'),
      confirmLabel: t('game.exitConfirm'),
      destructive: true,
      optional: true,
    );
    if (leave && mounted) Navigator.of(context).pop();
  }

  /// Serbest tahta: kayıtlı bir oyunu okumuyoruz, hamleler oyunun
  /// kendisi.
  ///
  /// Böyle bir tahtada geçmişe gidip başka bir hamle denemek mümkün
  /// olmalı — "analiz tahtası" bunun için var. Eskiden tahta yalnızca
  /// canlı uçta açıktı; `_onBoardMove` içindeki "sonrasını sil" kodu bu
  /// yüzden hiç çalışmıyordu.
  bool get _freeBoard =>
      widget.mode == GameMode.analysis && !_replayMode;

  bool get _replayMode =>
      widget.mode == GameMode.analysis &&
      (widget.pgnContent != null || widget.uciMoves != null) &&
      _history.isNotEmpty;

  // Motor
  bool _analysisOn = false;
  final GlobalKey _boardImageKey = GlobalKey();
  bool _thinking = false;
  SearchResult? _analysis;
  /// Beyaz bakisi; hamle degisse bile yeni sonuc gelene kadar sabit.
  int? _evalScoreCp;
  Timer? _analysisDebounce;
  int _analysisToken = 0;

  late EngineLevel _level;

  /// Düşünürken ekran sönmesin; sayaç her hamlede sıfırlanıyor, oyun
  /// bitince bırakılıyor.
  final ScreenAwake _awake = ScreenAwake();

  @override
  void initState() {
    super.initState();
    _awake.keep();
    _level = EngineLevel.all[
        (widget.engineLevelIndex ?? SettingsService.instance.engineLevel)
            .clamp(0, EngineLevel.all.length - 1)];
    _flipped = widget.playerColor == engine.Color.black &&
        widget.mode == GameMode.versusEngine;
    _resultText = widget.initialResult;
    _loadInitialPosition();
    // Pencere kapatılırken (Windows) kaydedilmemiş hamle var mı diye
    // uygulama düzeyinde sorulabilsin.
    UnsavedWork.register(_hasUnsavedWork);
  }

  bool _hasUnsavedWork() => _unsaved;

  @override
  void dispose() {
    UnsavedWork.unregister(_hasUnsavedWork);
    _awake.release();
    _analysisDebounce?.cancel();
    _analysisToken++;
    // Ekran kapanıyor: motorun hamlesi de dahil bekleyen her şey iptal.
    EngineService.instance.stopAll();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Kurulum
  // -------------------------------------------------------------------------

  void _loadInitialPosition() {
    _startFen = widget.startFen ?? engine.ChessGame().fen;
    // Bozuk bir kayıttan gelen FEN ekranı düşürüyordu: `fromFen`
    // FormatException atıyor, hata da initState içinde olduğu için ekran
    // hiç açılmıyor, kullanıcı kırmızı hata sayfası görüyordu. Artık
    // başlangıç konumuna dönülüyor ve durum yazıyla söyleniyor.
    if (engine.ChessGame.validateFen(_startFen) != null) {
      _startFen = engine.ChessGame().fen;
      _warning = t('game.fenCorrupt');
    }

    if (widget.pgnContent != null) {
      final parser = PgnParser();
      if (parser.parse(widget.pgnContent!)) {
        _startFen = parser.startFen ?? _startFen;
        _history
          ..clear()
          ..addAll(MoveEntry.fromUciList(parser.moves, startFen: _startFen));
        _resultText ??= parser.gameResult;
        if (parser.skippedTokens.isNotEmpty) {
          _warning = t('game.pgnSkipped', {
            'count': parser.skippedTokens.length,
            'tokens': parser.skippedTokens.take(4).join(', '),
          });
        }
        // Birden fazla uyarı olabilir; eskiden yalnızca sonuncusu
        // görünüyordu (atlanan hamle + bozuk FEN aynı anda olabiliyor).
        final notes = <String>[
          if (_warning != null) _warning!,
          if (parser.startFenRejected) t('game.pgnFenIgnored'),
          if (parser.unclosedAnnotation) t('pgn.unclosed'),
          if (parser.moves.isEmpty) t('game.pgnNoMoves'),
        ];
        if (notes.isNotEmpty) _warning = notes.join('  ·  ');
      } else {
        _warning = t('game.pgnUnreadable');
      }
    } else if (widget.uciMoves != null) {
      _history
        ..clear()
        ..addAll(MoveEntry.fromUciList(widget.uciMoves!, startFen: _startFen));
    }
    final initialWarning = widget.initialWarning;
    if (initialWarning != null) {
      _warning = _warning == null
          ? initialWarning
          : '$_warning  ·  $initialWarning';
    }

    _cursor = -1;
    _game = engine.ChessGame.fromFen(_startFen);
    _blackFirst = _game.sideToMove == engine.Color.black;

    if (widget.mode == GameMode.versusEngine) {
      SoundService.instance.playGameStart();
      // Kullanıcı siyahsa motor ilk hamleyi yapar.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _maybePlayEngineMove(),
      );
    }
  }

  /// Konumu [_startFen] üzerinden [index] hamleye kadar yeniden kurar.
  engine.ChessGame _positionAt(int index) {
    final position = engine.ChessGame.fromFen(_startFen);
    for (int i = 0; i <= index && i < _history.length; i++) {
      position.makeMove(_history[i].move);
    }
    return position;
  }

  // -------------------------------------------------------------------------
  // Hamleler
  // -------------------------------------------------------------------------

  void _onBoardMove(engine.ChessMove move) {
    // Kayıtlı oyunda tahtaya oynamak oyunu değiştirmez, denemedir.
    if (_replayMode) {
      _exploreMove(move);
      return;
    }

    // Geçmişin ortasındayken oynanan hamle sonrasını siler.
    if (_cursor < _history.length - 1) {
      _history.removeRange(_cursor + 1, _history.length);
    }

    final entry = MoveEntry.play(_game, move);
    setState(() {
      _animateBoard = true;
      _history.add(entry);
      _cursor = _history.length - 1;
      _resultText = null;
      _savedToList = false;
    });

    _announce(entry);
    _afterPositionChanged();

    if (widget.mode == GameMode.versusEngine) _maybePlayEngineMove();
  }

  /// Deneme hamlesi oynar; oyunun kendisine dokunmaz.
  void _exploreMove(engine.ChessMove move) {
    final entry = MoveEntry.play(_game, move);
    setState(() {
      _explore.add(entry);
      // Denemenin amacı değerlendirmeyi görmek; analiz kapalıysa açılır.
      _analysisOn = true;
    });
    SoundService.instance.playForSan(entry.san);
    _afterPositionChanged();
  }

  /// Son deneme hamlesini geri alır.
  void _undoExplore() {
    if (_explore.isEmpty) return;
    setState(() {
      _explore.removeLast();
      _game = _positionWithExplore();
    });
    _afterPositionChanged();
  }

  /// Tüm denemeleri atıp oyunun kendisine döner.
  void _clearExplore() {
    if (_explore.isEmpty) return;
    setState(() {
      _explore.clear();
      _game = _positionAt(_cursor);
    });
    _afterPositionChanged();
  }

  /// Ana hattın üzerine deneme hamleleri uygulanmış konum.
  engine.ChessGame _positionWithExplore() {
    final position = _positionAt(_cursor);
    for (final entry in _explore) {
      position.makeMove(entry.move);
    }
    return position;
  }

  void _goTo(int index) {
    final clamped = index.clamp(-1, _history.length - 1);
    final forward = clamped > _cursor;
    // Yalnızca tek adım ileri giderken canlandırılıyor; geri dönüşte ve
    // başa/sona atlarken taşın kayması olan biteni anlatmıyor.
    _animateBoard = clamped == _cursor + 1;
    final position = _positionAt(clamped);

    setState(() {
      // Oyunda gezinmek denemeleri sonlandırır.
      _explore.clear();
      _cursor = clamped;
      _game = position;
    });

    if (forward && clamped >= 0) {
      _announce(_history[clamped], replay: true);
    }
    _afterPositionChanged();

    // Motor düşünürken gezinmek aramayı geçersiz kılıyor; canlı konuma
    // dönüldüğünde kimse motoru yeniden çağırmıyordu ve sıra motorda
    // olduğu için tahta kilitli kalıyordu. Tek çıkış yeniden başlatmaktı.
    if (widget.mode == GameMode.versusEngine && !_thinking) {
      _maybePlayEngineMove();
    }
  }

  /// Hamlenin sesini çalar ve oyun bittiyse sonucu yazar.
  void _announce(
    MoveEntry entry, {
    bool opponent = false,
    bool replay = false,
  }) {
    // Elli hamle, yetersiz materyal ve üç tekrar da oyunu bitiriyor;
    // eskiden `_autoResult()` bunları biliyordu ama kimse sormuyordu,
    // yani şah ve piyon kalmayan oyun sonsuza kadar sürüyordu.
    //
    // Kayıtlı oyunda gezinirken (replay) yalnızca mat ve pat bitiş
    // sayılıyor: gerçek oyuncular üç tekrardan sonra oynamaya devam
    // etmiş olabilir — beraberlik talep edilir, kendiliğinden olmaz.
    // Orada bitiş sesi çalmak yanlış olurdu.
    final result = _autoResult();
    final gameOver =
        replay ? (_game.isCheckmate || _game.isStalemate) : result != null;

    if (gameOver) {
      SoundService.instance.playGameEnd();
    } else {
      SoundService.instance.playForSan(entry.san, opponent: opponent);
    }

    // Oyun sürerken ekran açık kalsın, bitince bıraksın.
    if (!replay) {
      if (gameOver) {
        _awake.release();
      } else {
        _awake.keep();
      }
    }

    if (!replay && gameOver) {
      setState(() => _resultText = result);
    }
  }

  /// Oyun bitince incelemeyi teklif eder.
  /// Aynı konum üçüncü kez mi tekrarlandı?
  ///
  /// Anahtar, FEN'in ilk dört alanı: taş dizilimi, sıra, rok hakları ve
  /// geçerken alma karesi. Son iki alan (yarım hamle sayacı ve hamle
  /// numarası) tekrarı bozmamalı. Geçmiş zaten hamle hamle tutuluyor,
  /// başlangıç konumu da sayıma giriyor.
  bool get _isThreefold => isThreefold(
        [
          _positionAt(-1).fen,
          for (var i = 0; i <= _cursor && i < _history.length; i++)
            _history[i].fenAfter,
        ],
        _game.fen,
      );

  String? _autoResult() {
    if (_game.isCheckmate) {
      return _game.sideToMove == engine.Color.white ? '0-1' : '1-0';
    }
    if (_game.isStalemate) return '1/2-1/2';
    // Üç tekrar kendiliğinden beraberlik: uygulamada saat ve "beraberlik
    // iste" yok, mat/pat gibi doğrudan bitiriliyor.
    if (_isThreefold) return '1/2-1/2';
    if (_game.fiftyMoveRule) return '1/2-1/2';
    if (_game.insufficientMaterial) return '1/2-1/2';
    return null;
  }

  void _afterPositionChanged() {
    if (!_analysisOn) return;
    _analysisDebounce?.cancel();
    _analysisToken++;
    EngineService.instance.stopAnalysis();

    // Konuma bağlı olan her şey hemen gidiyor: en iyi hamle oku, ana
    // varyant ve derinlik. Eskiden bunlar yeni sonuç gelene kadar
    // duruyordu, yani bir buçuk saniye boyunca **önceki konumun**
    // hamlesi tahtada ok olarak çiziliyordu.
    //
    // Skor (`_evalScoreCp`) bilerek duruyor: sayının her hamlede
    // kaybolup gelmesi şeridi titretiyordu ve eski skor yeni konum için
    // de kaba bir tahmin. İşaret ters dönmesin diye beyaz bakışında
    // saklanıyor.
    setState(() {
      _analysis = null;
      _thinking = false;
    });

    // Motora karşı oyunda sıra motordayken canlı analiz başlatılmıyor:
    // motorun hamlesini beklerken analiz göstermenin anlamı yok ve ok
    // rakibe akıl verirdi. (Artık motoru kesme sakıncası yok; kuyruk
    // bunu engelliyor. Kalan sebep bu ikisi.)
    //
    // Oyun bittiyse kural işlemiyor: orada artık inceleme yapılıyor ve
    // motorun oynayacağı bir hamle yok. Eskiden mat olduktan sonra geri
    // sarınca motorun hamlelerinde analiz şeridi boş kalıyordu.
    if (widget.mode == GameMode.versusEngine &&
        _resultText == null &&
        _game.sideToMove != widget.playerColor) {
      return;
    }

    _analysisDebounce = Timer(const Duration(milliseconds: 700), _runAnalysis);
  }

  // -------------------------------------------------------------------------
  // Motor
  // -------------------------------------------------------------------------

  Future<void> _runAnalysis() async {
    if (!_analysisOn) return;
    final fen = _game.fen;
    final side = _game.sideToMove;
    final token = ++_analysisToken;
    // Ara skor / spinner yok; sadece nihai sonuc.
    final result = await EngineService.instance.analyze(
      fen,
      depth: 22,
      movetimeMs: 800,
    );
    if (!mounted || token != _analysisToken) return;
    // Başka bir istek (motorun hamlesi, ipucu) bu aramayı düşürdüyse
    // ekranda bir şey değiştirmiyoruz: sonuç motorun sözü değil.
    if (result.cancelled) return;
    final sign = side == engine.Color.white ? 1 : -1;
    setState(() {
      _analysis = result;
      _evalScoreCp = result.scoreCp * sign;
      _thinking = false;
    });
  }

  /// Motor hamlesinin ekranda görünmesi için geçmesi gereken en kısa süre.
  static const Duration _minEngineThink = Duration(milliseconds: 700);

  Future<void> _maybePlayEngineMove() async {
    if (widget.mode != GameMode.versusEngine) return;
    if (!mounted || _resigned) return;
    if (_game.sideToMove == widget.playerColor) return;
    // Oyun bittiyse motor oynamıyor. Eskiden yalnızca mat ve pat
    // bakılıyordu: üç tekrar ya da elli hamleyle beraberlik yazısı
    // çıktıktan sonra motor oynamaya devam ediyordu.
    if (_autoResult() != null) return;
    if (_cursor != _history.length - 1) return;

    final token = ++_engineToken;
    setState(() {
      _thinking = true;
      _engineStalled = false;
    });
    final fen = _game.fen;
    final started = DateTime.now();
    var result = await EngineService.instance.bestMoveForLevel(fen, _level);
    // İsteği başka bir ekranın kapanışı düşürmüş olabilir: `stopAll()`
    // motordaki her işi iptal ediyor ve kapanan ekranın temizliği,
    // alttaki ekran çoktan canlıyken çalışıyor. Konum hâlâ motorun
    // sırasında, o yüzden bir kez daha soruyoruz. Tek tekrar: döngüye
    // dönmesin.
    if (result.cancelled) {
      result = await EngineService.instance.bestMoveForLevel(fen, _level);
    }
    // Alt kademelerde arama derinliği 1-2 olduğu için cevap neredeyse
    // anında geliyordu: taşın nereden nereye gittiği, bir taş alındıysa
    // neyin alındığı görülmüyor, hamle ekranda çakıyordu. Aşağıdaki
    // alt sınır hamleyi izlenebilir kılıyor; usta kademesi zaten daha
    // uzun düşündüğü için ona dokunmuyor.
    final thought = DateTime.now().difference(started);
    if (thought < _minEngineThink) {
      await Future<void>.delayed(_minEngineThink - thought);
    }
    if (!mounted || token != _engineToken) return;
    setState(() => _thinking = false);

    // Pes etmek konumu değiştirmediği için aşağıdaki FEN denetimi bunu
    // yakalamıyordu: motor düşünürken pes edersen hamle yine oynanıyor,
    // ekranda "pes ettin" yazarken tahta oynuyordu.
    if (_resigned || _resultText != null) return;

    // Konum denetimi önce: kullanıcı bu sırada geri aldıysa arama iptal
    // edilmiş olabilir ve boş dönen sonuç "motor cevap vermedi" değil,
    // "bu arama artık geçersiz" demektir. Sıra tersken yanlış uyarı
    // çıkıyor ve tahta gereksiz yere iki tarafa açılıyordu.
    if (_game.fen != fen) return;
    // İkinci deneme de düştüyse sonuç boş kalıyor ve aşağıdaki denetim
    // "motor cevap vermedi" yazısını çıkarıp tahtayı iki tarafa açıyor.
    // Eskiden burada sessizce çıkılıyordu: motor hiç oynamıyor, uyarı da
    // yok, tahta yalnızca kullanıcının rengine açık olduğu için hiçbir
    // taş tutmuyordu.

    if (result.bestMoveUci.isEmpty) {
      setState(() {
        _engineStalled = true;
        _warning = t('game.engineStalled');
      });
      return;
    }

    final move = _game.moveFromUci(result.bestMoveUci);
    if (move == null) {
      setState(() {
        _engineStalled = true;
        _warning = t('game.engineStalled');
      });
      return;
    }

    final entry = MoveEntry.play(_game, move);
    setState(() {
      _animateBoard = true;
      _history.add(entry);
      _cursor = _history.length - 1;
    });
    _announce(entry, opponent: true);
    // Sıra kullanıcıya geçti: analiz artık güvenle çalışabilir.
    _afterPositionChanged();
  }

  Future<void> _takeBack() async {
    if (_history.isEmpty) return;
    // Motora karşı oyunda kendi hamlemize dönmek için iki hamle geri al.
    final steps = widget.mode == GameMode.versusEngine ? 2 : 1;
    final target = (_history.length - steps).clamp(0, _history.length);
    setState(() {
      _animateBoard = false;
      _history.removeRange(target, _history.length);
      _cursor = _history.length - 1;
      _game = _positionAt(_cursor);
      _resultText = null;
      // Pes edip geri alınca tahta kilitli kalıyordu: sonuç siliniyor
      // ama "pes edildi" bayrağı duruyordu. Tahta kapalı (`atLive`
      // false), motor da oynamıyor (`_maybePlayEngineMove` ilk satırda
      // bu bayrağa bakıyor); tek çıkış oyunu baştan başlatmaktı.
      _resigned = false;
    });
    _afterPositionChanged();
    // Geri alınca sıra motora geçmiş olabilir (siyah oynarken ilk
    // hamleden sonra geri almak gibi). Eskiden kimse oynamıyordu:
    // tahta kilitli kalıyor, menüden yeniden başlatmak gerekiyordu.
    if (widget.mode == GameMode.versusEngine) _maybePlayEngineMove();
  }

  // -------------------------------------------------------------------------
  // Menü işlemleri
  // -------------------------------------------------------------------------

  String _buildPgn() {
    return PgnParser.buildPgn(
      uciMoves: _history.map((e) => e.uci).toList(),
      startFen: _startFen == engine.ChessGame().fen ? null : _startFen,
      result: _resultText,
      tags: {'Event': widget.title ?? t('app.title')},
    );
  }

  Future<void> _copyPgn() async {
    await Clipboard.setData(ClipboardData(text: _buildPgn()));
    if (mounted) AppDialogs.snack(context, t('game.pgnCopied'));
  }

  Future<void> _copyFen() async {
    await Clipboard.setData(ClipboardData(text: _game.fen));
    if (mounted) AppDialogs.snack(context, t('game.fenCopiedToClipboard'));
  }

  /// Tahtaya yeni bir başlangıç konumu kurar (yapıştırma, düzenleyici).
  ///
  /// Eskiden iki yol da kendi içinde yalnızca geçmişi ve sonucu
  /// siliyordu; "pes edildi", "motor tıkandı", "kaydedildi" bayrakları
  /// ve hamle listesi numarası olduğu gibi kalıyordu. Pes ettikten sonra
  /// bir FEN yapıştırmak tahtayı kilitli bırakıyor, sıra motordaysa da
  /// kimse oynamıyordu. 9.0.6'da geri alma için kapatılan kilit buradan
  /// geri geliyordu.
  void _applyNewPosition(String fen) {
    // Pano okuması ya da düzenleyici beklenirken ekrandan çıkılmış
    // olabilir; kapanmış ekrana yazmak hata veriyordu.
    if (!mounted) return;
    setState(() {
      _startFen = fen;
      _history.clear();
      _explore.clear();
      _cursor = -1;
      _game = engine.ChessGame.fromFen(fen);
      _blackFirst = _game.sideToMove == engine.Color.black;
      _resultText = null;
      _resigned = false;
      _engineStalled = false;
      _savedToList = false;
      _warning = null;
    });
    _afterPositionChanged();
    // Kurulan konumda sıra motordaysa motor oynasın.
    if (widget.mode == GameMode.versusEngine) _maybePlayEngineMove();
  }

  Future<void> _pasteFen() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      if (mounted) AppDialogs.snack(context, t('common.noClipboardText'));
      return;
    }
    final error = engine.ChessGame.validateFen(text);
    if (error != null) {
      if (mounted) {
        AppDialogs.snack(context, t('common.invalidFen', {'error': error}));
      }
      return;
    }
    _applyNewPosition(text);
  }

  Future<void> _editPosition() async {
    final fen = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => BoardEditorScreen(initialFen: _game.fen),
      ),
    );
    if (fen == null || !mounted) return;
    _applyNewPosition(fen);
  }

  /// Kullanıcı pes eder; oyun rakibin kazancıyla biter.
  /// "Pes et" gösterilsin mi?
  ///
  /// Yalnızca kullanıcının kendi oynadığı bir oyunda anlamlı: motora
  /// karşı oyunda ya da serbest tahtada. Dışarıdan yüklenmiş bir oyunu
  /// (PGN, kayıtlı liste, analiz kaydı) okurken pes etmek anlamsızdı —
  /// menüde duruyor ama başkasının oyununa sonuç yazmaktan başka bir şey
  /// yapmıyordu.
  bool get _canResign {
    if (_history.isEmpty || _resultText != null) return false;
    if (widget.mode == GameMode.versusEngine) return true;
    return widget.uciMoves == null && widget.pgnContent == null;
  }

  Future<void> _resign() async {
    final confirmed = await AppDialogs.confirm(
      context,
      title: t('game.resign'),
      message: t('game.resignMessage'),
      confirmLabel: t('game.resign'),
      destructive: true,
      optional: true,
    );
    if (!confirmed || !mounted) return;

    // Motora karşı oyunda kullanıcının rengi, serbest tahtada sırası gelen
    // taraf pes etmiş sayılır.
    final loser = widget.mode == GameMode.versusEngine
        ? widget.playerColor
        : _game.sideToMove;

    setState(() {
      _resigned = true;
      _resultText = loser == engine.Color.white ? '0-1' : '1-0';
    });
    SoundService.instance.playGameEnd();
    // review removed
  }

  Future<void> _restart() async {
    // Kayıtlı bir oyunu okurken "yeniden başlat" oyunu **silmiyor**:
    // hamleler yeniden kuruluyor ve başa dönülüyor. Eskiden geçmiş
    // boşaltılıyor, incelenen parti geri alınamayacak şekilde gidiyordu.
    final replay = _replayMode;
    final confirmed = await AppDialogs.confirm(
      context,
      title: t('game.restart'),
      message: replay ? t('game.restartReplayMessage') : t('game.restartMessage'),
      // Düğme "Sil" yazıyordu; yaptığı iş bu değil.
      confirmLabel: t('game.restart'),
      destructive: !replay,
      optional: true,
    );
    if (!confirmed || !mounted) return;

    // Uçan analiz yeni konuma yazılmasın: jeton ilerletiliyor ve
    // bekleyen istek iptal ediliyor. Eskiden eski konumun oku/skoru
    // sıfırlanan tahtaya düşebiliyordu.
    _analysisToken++;
    _analysisDebounce?.cancel();
    EngineService.instance.stopAnalysis();

    if (replay) {
      setState(() {
        _explore.clear();
        _warning = null;
        _resigned = false;
        _engineStalled = false;
        _analysis = null;
        _evalScoreCp = null;
        _loadInitialPosition();
      });
      _afterPositionChanged();
      return;
    }

    setState(() {
      _analysis = null;
      _evalScoreCp = null;
      _history.clear();
      _cursor = -1;
      _game = engine.ChessGame.fromFen(_startFen);
      _resultText = null;
      _analysis = null;
      _evalScoreCp = null;
      _resigned = false;
      _engineStalled = false;
      _savedToList = false;
    });
    if (widget.mode == GameMode.versusEngine) _maybePlayEngineMove();
  }

  Future<void> _saveGame() async {
    if (_history.isEmpty) {
      AppDialogs.snack(context, t('game.nothingToSave'));
      return;
    }

    final storage = StorageService.instance;
    var playlists = await storage.loadPlaylists();
    if (!mounted) return;

    if (playlists.isEmpty) {
      final name = await AppDialogs.prompt(
        context,
        title: t('game.newList'),
        label: t('game.listName'),
        initialValue: t('game.defaultListName'),
      );
      if (name == null || !mounted) return;
      try {
        await storage.createPlaylist(name);
      } catch (_) {
        if (mounted) AppDialogs.snack(context, t('lists.saveFailed'));
        return;
      }
      playlists = await storage.loadPlaylists();
      if (!mounted) return;
    }

    String selectedId = playlists.first.id;
    final nameController = TextEditingController(
      text: widget.title ??
          t('game.defaultGameName', {
            'date': DateTime.now().toString().substring(0, 16),
          }),
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text(t('game.saveGame')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                mouseCursor: kClickable,
                initialValue: selectedId,
                decoration: InputDecoration(labelText: t('game.list')),
                items: playlists
                    .map(
                      (p) => DropdownMenuItem(
                        value: p.id,
                        child: Text(p.name, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setLocalState(() => selectedId = value ?? selectedId),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                decoration: InputDecoration(labelText: t('game.gameName')),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(t('common.cancel')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(t('common.save')),
            ),
          ],
        ),
      ),
    );

    if (saved != true || !mounted) return;

    final saveName = nameController.text.trim().isEmpty
        ? t('game.defaultSaveName')
        : nameController.text.trim();
    // PGN'den gelen oyuncu adları; yoksa "Beyaz - Siyah" biçimindeki
    // başlıktan ayırmayı dene (tek oyun yapıştırıp kaydetme yolu).
    String? white = _meaningfulName(widget.whiteName);
    String? black = _meaningfulName(widget.blackName);
    if (white == null && black == null) {
      final fromTitle = _splitPlayerTitle(widget.title ?? saveName);
      if (fromTitle != null) {
        white = fromTitle.$1;
        black = fromTitle.$2;
      }
    }
    // Diske yazma başarısız olabilir: cihazda yer kalmamışsa
    // `StorageService` hata fırlatıyor. Eskiden bu hata yakalanmıyordu,
    // yani ne kayıt oluyor ne de kullanıcıya bir şey söyleniyordu. PGN
    // içe aktarma tarafı 9.0.4'te düzeltilmişti, tahta tarafı açık
    // kalmıştı.
    try {
      await storage.addGame(
        selectedId,
        SavedGame(
          name: saveName,
          uciMoves: _history.map((e) => e.uci).toList(),
          createdAt: DateTime.now(),
          result: _resultText,
          startFen: _startFen == engine.ChessGame().fen ? null : _startFen,
          white: white,
          black: black,
        ),
      );
    } catch (_) {
      if (mounted) AppDialogs.snack(context, t('lists.saveFailed'));
      return;
    }
    // `setState` gerekiyor: çıkış onayı bu bayrağa bakıyor ve yazı
    // tek başına yeniden çizim tetiklemiyordu.
    if (mounted) {
      setState(() => _savedToList = true);
      AppDialogs.snack(context, t('game.saved'));
    }
  }


  static String? _meaningfulName(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == '?' || trimmed == '-') return null;
    return trimmed;
  }

  /// "Magnus Carlsen - Hikaru" gibi başlıklardan oyuncu çiftini çıkarır.
  static (String, String)? _splitPlayerTitle(String? title) {
    if (title == null) return null;
    final raw = title.trim();
    const sep = ' - ';
    final index = raw.indexOf(sep);
    if (index <= 0) return null;
    final left = raw.substring(0, index).trim();
    final right = raw.substring(index + sep.length).trim();
    if (left.isEmpty || right.isEmpty) return null;
    if ((left == '?' || left == '-') && (right == '?' || right == '-')) {
      return null;
    }
    return (left, right);
  }

  // -------------------------------------------------------------------------
  // Arayüz
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final atLive = _cursor == _history.length - 1 && !_resigned;
    // Motora karşı oyun bittiyse tahta da kapanıyor; yoksa hamle yapıp
    // beraberlik yazısını silmek mümkündü. Analiz/PGN kipinde tahta açık
    // kalıyor: orada oyunun devamını denemek isteyebilirsin.
    final finished =
        widget.mode == GameMode.versusEngine && _resultText != null;

    final arrows = <BoardArrow>[];
    final best = _analysis?.bestMoveUci;
    // Motora karşı oyunda ok yalnızca senin sıranda çiziliyor: gösterilen
    // konumda sıra motordaysa o ok motorun hamlesini önerir, yani rakibe
    // akıl verir. Analiz/PGN okuma kipinde iki taraf için de anlamlı.
    final arrowAllowed = widget.mode != GameMode.versusEngine ||
        _game.sideToMove == widget.playerColor;
    if (_analysisOn &&
        arrowAllowed &&
        SettingsService.instance.showEngineArrows &&
        best != null &&
        best.length >= 4) {
      final move = _game.moveFromUci(best);
      if (move != null) {
        arrows.add(
          BoardArrow(
            move.from,
            move.to,
            // Motor önerisi: senin çizdiğin oktan daha sönük ve ince.
            Color(BoardAssets.markColor(SettingsService.instance.boardTheme))
                .withValues(alpha: 0.7),
            faint: true,
          ),
        );
      }
    }

    // Geniş pencerede hamle listesi tahtanın yanına geçiyor. Ayar
    // yalnızca yerleşimin gerçekten sığdığı genişlikte gösteriliyor;
    // pencere küçülürse kendiliğinden alt şeride dönülüyor.
    final settings = SettingsService.instance;
    // Yerleşim seçeneği kaldırıldı: geniş pencerede hamleler her zaman
    // yanda. Tek karar pencerenin bunu taşıyıp taşımadığı.
    final twoColumn = Layout.isTwoColumn(context);
    final wideEnough = twoColumn;
    // Boyut tercihi yalnızca "Yanda" yerleşiminde geçerli; ayar da
    // yalnızca orada gösteriliyor.
    //
    // Alt şeritte tahtayı sınırlayan şey seçim değil **yükseklik**:
    // altındaki motor satırı, hamle şeridi ve gezinme düğmeleri ~300
    // piksel yiyor, tahtaya 509 kalıyordu ve üç seçenek de aynı sonucu
    // veriyordu. Oranlı bir ölçek üçünü ayırırdı ama ikisini bugünkünden
    // **küçük** yapardı; kullanıcıya daha kötü bir tahta seçtirmenin
    // anlamı yok. Alt şeritte tahta artık sığdığı kadar büyük.
    final cap =
        wideEnough ? Layout.maxWideBoardSide : Layout.narrowBoardCap;

    final screen = Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title ??
              (widget.mode == GameMode.versusEngine
                  // Düzey burada yazmıyor: dar ekranda başlığa sığmayıp
                  // üç noktaya iniyordu ve zaten tahtanın yanındaki
                  // oyuncu satırında yazıyor.
                  ? t('game.vsEngine')
                  : t('game.board')),
        ),
        actions: [
          IconButton(
            tooltip: t('common.flipBoard'),
            icon: const Icon(Icons.swap_vert_rounded),
            onPressed: () => setState(() => _flipped = !_flipped),
          ),
          IconButton(
            tooltip: _analysisOn ? t('game.analysisOff') : t('game.analysisOn'),
            icon: Icon(
              Icons.insights_rounded,
              color: _analysisOn ? scheme.primary : null,
            ),
            onPressed: () {
              setState(() => _analysisOn = !_analysisOn);
              if (_analysisOn) {
                // Sıra motordayken analiz başlatmak motorun aramasını
                // keser ve motor daha zayıf bir hamle oynar. Motor
                // oynayınca analiz kendiliğinden başlıyor.
                final engineTurn = widget.mode == GameMode.versusEngine &&
                    _game.sideToMove != widget.playerColor;
                if (!engineTurn) _runAnalysis();
              } else {
                _analysisToken++;
                // `stopAnalysis` artık yalnızca analiz/ipucu isteklerini
                // iptal ediyor; motorun hamlesine dokunamıyor (bkz.
                // EngineCoordinator). Eskiden burada "sıra motordaysa
                // çağırma" denetimi gerekiyordu.
                EngineService.instance.stopAnalysis();
                setState(() {
                  _analysis = null;
                  _evalScoreCp = null;
                  _thinking = false;
                });
              }
            },
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'save':
                  _saveGame();
                  break;
                case 'pgn':
                  _copyPgn();
                  break;
                case 'fen':
                  _copyFen();
                  break;
                case 'png':
                  _saveBoardImage();
                  break;
                case 'paste':
                  _pasteFen();
                  break;
                case 'edit':
                  _editPosition();
                  break;
                case 'resign':
                  _resign();
                  break;
                case 'restart':
                  _restart();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'save',
                child: ListTile(
                  leading: const Icon(Icons.bookmark_add_outlined),
                  title: Text(t('game.saveToList')),
                ),
              ),
              PopupMenuItem(
                value: 'pgn',
                child: ListTile(
                  leading: const Icon(Icons.copy_all_rounded),
                  title: Text(t('game.copyPgn')),
                ),
              ),
              PopupMenuItem(
                value: 'fen',
                child: ListTile(
                  leading: const Icon(Icons.copy_rounded),
                  title: Text(t('common.copyFen')),
                ),
              ),
              PopupMenuItem(
                value: 'png',
                child: ListTile(
                  leading: const Icon(Icons.image_outlined),
                  title: Text(t('board.savePng')),
                ),
              ),
              PopupMenuItem(
                value: 'paste',
                child: ListTile(
                  leading: const Icon(Icons.content_paste_rounded),
                  title: Text(t('common.pasteFen')),
                ),
              ),
              PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  leading: const Icon(Icons.dashboard_customize_outlined),
                  title: Text(t('common.editPosition')),
                ),
              ),
              if (_canResign)
                PopupMenuItem(
                  value: 'resign',
                  child: ListTile(
                    leading: const Icon(Icons.flag_outlined),
                    title: Text(t('game.resign')),
                  ),
                ),
              PopupMenuItem(
                value: 'restart',
                child: ListTile(
                  leading: const Icon(Icons.restart_alt_rounded),
                  title: Text(t('game.restart')),
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: twoColumn
            ? _wideBody(
                scheme,
                arrows: arrows,
                atLive: atLive,
                finished: finished,
                cap: cap,
                // Boyut yalnızca masaüstünde seçiliyor; telefon ve
                // tablette pencere sabit olduğu için tahta sığanın
                // tamamı kadar.
                scale: Layout.isDesktop
                    ? Layout.boardScales[settings.boardSize]
                    : 1.0,
              )
            : _narrowBody(
                scheme,
                _boardArea(
                  arrows: arrows,
                  atLive: atLive,
                  finished: finished,
                  cap: cap,
                ),
              ),
      ),
    );

    // Kaydedilmemiş oyunda geri tuşu hamleleri sessizce siliyordu:
    // yirmi hamlelik bir oyun sistem geri jestiyle yok oluyordu.
    // "Onay pencereleri" ayarı kapalıysa sorulmadan çıkılıyor.
    return PopScope(
      canPop: !_unsaved || !SettingsService.instance.askConfirmations,
      onPopInvokedWithResult: _onPopInvoked,
      child: screen,
    );
  }



  Widget _warningBanner(ColorScheme scheme) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: scheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _warning!,
              style: TextStyle(color: scheme.onErrorContainer, fontSize: 12),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: () => setState(() => _warning = null),
          ),
        ],
      ),
    );
  }

  Widget _playerRow(ColorScheme scheme, {required bool top}) {
    // Üst sıra her zaman tahtanın uzak tarafındaki oyuncudur.
    final isWhiteSide = top ? _flipped : !_flipped;
    final side = isWhiteSide ? engine.Color.white : engine.Color.black;
    final toMove = _game.sideToMove == side;

    String name;
    if (widget.mode == GameMode.versusEngine) {
      name = side == widget.playerColor
          ? t('game.you')
          : t('game.engine', {'level': _level.name});
    } else {
      // PGN'de adlar varsa onlar yazılır; listede kartta sığmayan adlar
      // burada tam görünüyor. Yoksa rengin adı.
      final given =
          side == engine.Color.white ? widget.whiteName : widget.blackName;
      name = (given != null && given.trim().isNotEmpty)
          ? given.trim()
          : (side == engine.Color.white
              ? t('common.white')
              : t('common.black'));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        // Açıkça ortalı: yuvarlak, ad ve alınan taşlar aynı eksende.
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Sıranın kimde olduğunu **bu yuvarlak** söylüyor: sırası gelen
          // tarafınki vurgu rengiyle halkalanıyor.
          //
          // Eskiden sırayı adın rengi söylüyordu (koyu/soluk) ve bu,
          // adlardan biri kalınmış gibi okunuyordu. Adlar artık birbirinin
          // tıpatıp aynısı.
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: side == engine.Color.white
                  ? const Color(0xFFF2EEE7)
                  : const Color(0xFF3B3630),
              border: Border.all(
                color: toMove ? scheme.primary : scheme.outlineVariant,
                width: toMove ? 2.5 : 1,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                // İki ad da aynı: ne kalınlık ne renk değişiyor. Sırayı
                // soldaki yuvarlağın halkası söylüyor.
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
                // 13 punto telefona göre seçilmişti; masaüstünde 600+
                // piksellik tahtanın yanında ufak kalıyordu.
                fontSize: 15,
                // Satır kutusu harflere otursun: yanındaki yuvarlak,
                // inişli harflerin bıraktığı boşluk yüzünden yazıya göre
                // aşağıda duruyor gibi görünüyordu.
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: CapturedPieces(side: side, game: _game, size: 16),
          ),
        ],
      ),
    );
  }

  /// Tahta ve çevresindeki boşluk; kalan alana sığan en büyük kare.
  Widget _boardArea({
    required List<BoardArrow> arrows,
    required bool atLive,
    required bool finished,
    required double cap,
  }) {
    return Expanded(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final side = Layout.boardSide(
                constraints.maxWidth,
                constraints.maxHeight,
                cap,
              );
              return RepaintBoundary(
                key: _boardImageKey,
                child: SizedBox(
                  width: side,
                  height: side,
                  child: ChessBoardWidget(
                    game: _game,
                    flipped: _flipped,
                    // Kayıtlı oyunda hamle oynamak oyunu değiştirmez;
                    // deneme olarak çalışır.
                    interactive:
                        (_replayMode || atLive || _freeBoard) && !finished,
                    animateLastMove: _animateBoard,
                    movableSide:
                        widget.mode == GameMode.versusEngine && !_engineStalled
                            ? widget.playerColor
                            : null,
                    lastMove: _explore.isNotEmpty
                        ? _explore.last.move
                        : (_cursor >= 0 ? _history[_cursor].move : null),
                    onMove: _onBoardMove,
                    arrows: arrows,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Telefon ve dar pencere: her şey alt alta.
  Widget _narrowBody(ColorScheme scheme, Widget board) {
    return ContentWidth(
      child: Column(
        children: [
          if (_warning != null) _warningBanner(scheme),
          _playerRow(scheme, top: true),
          board,
          _playerRow(scheme, top: false),
          if (_explore.isNotEmpty) _exploreCard(scheme),
          // Motor şeridi için sabit yükseklik: aç/kapa tahtayı kaydırmaz.
          SizedBox(
            height: _engineStripHeightFor(context, null),
            child: _analysisOn ? _engineLine(scheme) : null,
          ),
          // Deneme sırasında tahtadaki konum oyunun sonucunu yansıtmaz.
          if (_resultText != null && _explore.isEmpty) _resultBanner(scheme),
          _controls(scheme),
        ],
      ),
    );
  }

  /// Tahtanın üstünde ve altında duran sabit yükseklikler: iki oyuncu
  /// satırı ve tahtanın kendi dikey boşluğu.
  ///
  /// Değer **gerçeğine yakın** olmalı, cömert değil. 10.0.4'te 88'di:
  /// tahta o zaman genişlikten sınırlandığı için fazla pay zararsızdı.
  /// Artık kenar bu paydan çıkarılarak hesaplanıyor, yani her fazla
  /// piksel doğrudan tahtadan gidiyor — 88 ile tahta 690 yerine 672'ye
  /// düşüyordu. `game_layout_test` ölçüyor.
  static const double _wideChromeHeight = 70;

  /// Tahtanın yatay boşluğu ([_boardArea] içindeki dolgu), iki yan.
  static const double _boardGutter = 16;

  /// Geniş pencere: solda tahta, sağda hamleler ve motor.
  ///
  /// Eskiden masaüstünde de telefon düzeni kullanılıyordu: tahta 520
  /// pikselde kalıyor, hamleler altta ince bir şeritte yan yana diziliyor
  /// ve pencerenin iki yanı boş duruyordu.
  Widget _wideBody(
    ColorScheme scheme, {
    required List<BoardArrow> arrows,
    required bool atLive,
    required bool finished,
    required double cap,
    required double scale,
  }) {
    // Tahta ve panel **tek bir grup**: ikisi birlikte ortalanıyor.
    //
    // Eskiden sol sütun kalan genişliğin tamamını alıyor, tahta da onun
    // ortasına oturuyordu. 1920 piksellik pencerede tahtayla panel
    // arasında ~470 piksel boşluk kalıyor, oyuncu satırları da tahtadan
    // çok daha geniş duruyordu (isim en solda, alınan taşlar tahtanın
    // epey sağında).
    //
    // Dikeyde de aynısı: `stretch` yüzünden panel gövdenin tamamını
    // kaplıyor, tahta ortada yüzüyordu. Panelin dibindeki gezinme
    // düğmeleri böylece pencerenin en altına iniyor, tahtadan uzaklaşıyordu.
    return LayoutBuilder(
      builder: (context, constraints) {
        // Kenar **önce** hesaplanıyor; grubun eni ve boyu ona göre
        // kuruluyor. Doğrudan tavandan gidilseydi, tahta o tavana
        // ulaşamadığında (alçak pencerede yükseklik sınırlar) sol sütun
        // tahtadan geniş kalır ve kapatılan boşluk geri gelirdi.
        // Boşluk tahtanın oranı olduğu için kenar iki adımda
        // kesinleşiyor: önce boşluksuz hesap, sonra genişliğe sığdırma.
        final available =
            constraints.maxWidth - Layout.sidePanelWidth - _boardGutter;
        var side = Layout.boardSide(
              available,
              constraints.maxHeight -
                  _wideChromeHeight -
                  Layout.wideOuterMargin * 2,
              cap,
            ) *
            scale;
        final gap = Layout.panelGap(side);
        if (side > available - gap) {
          side = (available - gap).clamp(0.0, side);
        }
        final board = _boardArea(
          arrows: arrows,
          atLive: atLive,
          finished: finished,
          // Kenar kesinleşti; içeride bir daha sınırlanmasın.
          cap: side,
        );
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: side + _boardGutter + gap + Layout.sidePanelWidth,
              maxHeight: side + _wideChromeHeight,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      // Uyarı, deneme kartı ve sonuç afişi yan panelde:
                      // burada dursalardı grubun boyu değişken olurdu ve
                      // tahta onlar göründüğünde küçülürdü. Listeden
                      // açılan kayıtlı bir oyunda (sonuç afişi var)
                      // tahta 603 yerine 553 piksele iniyordu.
                      _playerRow(scheme, top: true),
                      board,
                      _playerRow(scheme, top: false),
                    ],
                  ),
                ),
                SizedBox(width: gap),
                SizedBox(
                  width: Layout.sidePanelWidth,
                  child: _sidePanel(scheme, side),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Sağ sütun: hamle listesi (dikey), motor satırı ve gezinme düğmeleri.
  Widget _sidePanel(ColorScheme scheme, double boardSide) {
    return Container(
      margin: const EdgeInsets.fromLTRB(4, 8, 12, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          if (_warning != null) _warningBanner(scheme),
          if (_explore.isNotEmpty) _exploreCard(scheme),
          if (_resultText != null && _explore.isEmpty) _resultBanner(scheme),
          Expanded(child: _moveList(vertical: true)),
          Divider(height: 1, color: scheme.outlineVariant),
          SizedBox(
            height: _engineStripHeightFor(context, boardSide),
            child: _analysisOn
                ? _engineLine(scheme, boardSide: boardSide)
                : null,
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          _navRow(scheme),
        ],
      ),
    );
  }

  Widget _moveList({required bool vertical}) => MoveList(
        moves: _history,
        currentIndex: _cursor,
        onMoveTap: _goTo,
        blackFirst: _blackFirst,
        vertical: vertical,
      );

  /// Denenen hamleleri ve bunların kaydedilmediğini gösteren şerit.
  Widget _exploreCard(ColorScheme scheme) {
    final sanMoves = _explore.map((e) => e.san).join(' ');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.alt_route_rounded,
            size: 17,
            color: scheme.onSecondaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sanMoves,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSecondaryContainer,
                  ),
                ),
                Text(
                  t('game.exploreHint'),
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSecondaryContainer.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: t('game.undoExplore'),
            icon: const Icon(Icons.undo_rounded, size: 20),
            color: scheme.onSecondaryContainer,
            onPressed: _undoExplore,
          ),
          IconButton(
            tooltip: t('game.backToGame'),
            icon: const Icon(Icons.close_rounded, size: 20),
            color: scheme.onSecondaryContainer,
            onPressed: _clearExplore,
          ),
        ],
      ),
    );
  }

  Future<void> _saveBoardImage() async {
    final result = await BoardImageService.saveBoardPng(
      _boardImageKey,
      fileName: 'chess-library-board.png',
    );
    if (!mounted) return;
    AppDialogs.snack(context, t('board.saveResult.$result'));
  }

  Widget _engineLine(ColorScheme scheme, {double? boardSide}) {
    final analysis = _analysis;
    final score = _evalScoreCp;
    // Yeni sonuç beklenirken yalnızca skor yazıyor: ana varyant ve
    // derinlik önceki konuma ait, onları göstermek yanlış olurdu.
    // Hiçbiri yoksa yazı yok; dışardaki sabit yükseklik tahtayı tutar.
    if (analysis == null && score == null) return const SizedBox.expand();
    final text =
        analysis == null ? _formatScoreCp(score!) : _describeAnalysis(analysis);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Simge yazıyla birlikte büyüyor; eskiden 16 pikselde sabitti
          // ve yanındaki yazının yanında iyice küçük kalıyordu.
          Icon(
            Icons.memory_rounded,
            size: Layout.engineFontSize(boardSide) * 1.45,
            color: scheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              // Şerit sabit yükseklikli: sığmayan metin kırpılıyor,
              // taşmıyor.
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: Layout.engineFontSize(boardSide),
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }


  /// Motor şeridinin yüksekliği.
  ///
  /// Sabit, çünkü aç/kapa tahtayı kaydırmasın — ama puntodan türüyor:
  /// yazı tahtayla büyüyünce şeridin de büyümesi gerekiyor, yoksa iki
  /// satırlık metin taşardı. İçinde: iki satır metin, dikey dolgu (16)
  /// ve kenar boşluğu (4).
  ///
  /// [MediaQuery.textScalerOf] hesaba katılıyor: masaüstü ölçeği ve
  /// kullanıcının kendi yazı büyütmesi de yüksekliğe yansısın.
  double _engineStripHeightFor(BuildContext context, double? boardSide) {
    final font = Layout.engineFontSize(boardSide);
    final scaled = MediaQuery.textScalerOf(context).scale(font);
    return scaled * 1.25 * 2 + 20;
  }

  /// Beyaz bakisi; pozitifte acik +.
  String _formatScoreCp(int cp) {
    final body = (cp.abs() / 100).toStringAsFixed(2);
    if (cp > 0) return '+$body';
    if (cp < 0) return '-$body';
    return '0.00';
  }

  String _describeAnalysis(SearchResult analysis) {
    // Kimin mat ettiği yazıyla söyleniyor. Eskiden yalnızca mutlak
    // değer vardı (mat olurken de mat ederken de "Mat 3"), sonra işaretli
    // sayıya çevrildi ("Mat -3") — ikisi de okunaksızdı.
    final mate = analysis.mateIn;
    final String evaluation;
    if (mate != null) {
      // Motor mat sayısını sırası gelen tarafa göre veriyor; beyaz
      // bakışına çevirip kimin mat ettiğini yazıyoruz.
      final whiteMates =
          (_game.sideToMove == engine.Color.white ? mate : -mate) > 0;
      evaluation = t(
        whiteMates ? 'game.mateWhite' : 'game.mateBlack',
        {'n': mate.abs()},
      );
    } else {
      // Mat yoksa santipiyon skoru. Bu hesap eskiden mat **olmadığında
      // da** çalışıyordu ve `mateIn` null iken sıra beyazdayken null
      // denetimi patlıyordu: analiz açılan her konumda ekran kırmızıya
      // düşüyordu.
      evaluation = _formatScoreCp(_evalScoreCp ?? analysis.scoreCp);
    }

    // Ana varyantı SAN'a çevir.
    final position = _game.copy();
    final sanMoves = <String>[];
    for (final uci in analysis.pvUci.take(6)) {
      final move = position.moveFromUci(uci);
      if (move == null) break;
      sanMoves.add(position.sanFor(move));
      position.makeMove(move);
    }

    return '$evaluation  ·  ${sanMoves.isEmpty ? "—" : sanMoves.join(" ")}';
  }

  Widget _resultBanner(ColorScheme scheme) {
    final result = _resultText!;
    final label = switch (result) {
      '1-0' => t('game.whiteWon'),
      '0-1' => t('game.blackWon'),
      '1/2-1/2' => t('game.drawn'),
      _ => result,
    };
    final color = switch (result) {
      '1-0' => scheme.success,
      '0-1' => scheme.error,
      _ => scheme.drawColor,
    };

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _resigned
            ? '$label · ${t('game.resigned')}  ($result)'
            : '$label  ($result)',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
    );
  }

  Widget _controls(ColorScheme scheme) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          SizedBox(height: 52, child: _moveList(vertical: false)),
          Divider(height: 1, color: scheme.outlineVariant),
          _navRow(scheme),
        ],
      ),
    );
  }

  /// Gezinme düğmeleri; iki yerleşim de aynı satırı kullanıyor.
  Widget _navRow(ColorScheme scheme) {
    return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                if (widget.mode == GameMode.versusEngine)
                  _navButton(
                    Icons.undo_rounded,
                    // Motor düşünürken geri almak iki aramayı
                    // çakıştırıyordu.
                    _history.isEmpty || _thinking ? null : _takeBack,
                    t('game.takeBack'),
                  )
                else
                  _navButton(
                    Icons.first_page_rounded,
                    _cursor >= 0 ? () => _goTo(-1) : null,
                    t('game.toStart'),
                  ),
                _navButton(
                  Icons.chevron_left_rounded,
                  _cursor >= 0 ? () => _goTo(_cursor - 1) : null,
                  t('common.previous'),
                ),
                _navButton(
                  Icons.chevron_right_rounded,
                  _cursor < _history.length - 1
                      ? () => _goTo(_cursor + 1)
                      : null,
                  t('game.forward'),
                ),
                _navButton(
                  Icons.last_page_rounded,
                  _cursor < _history.length - 1
                      ? () => _goTo(_history.length - 1)
                      : null,
                  t('game.toEnd'),
                ),
              ],
            ),
    );
  }

  Widget _navButton(IconData icon, VoidCallback? onPressed, String tooltip) {
    return IconButton(
      icon: Icon(icon),
      iconSize: 26,
      tooltip: tooltip,
      onPressed: onPressed,
    );
  }
}
