import '../../services/settings_service.dart';
import 'package:flutter/material.dart';

import '../../widgets/responsive.dart';

import 'package:flutter/services.dart';

import '../../l10n/app_strings.dart';
import '../../models/chess_engine.dart' as engine;
import '../../models/move_entry.dart';
import '../../models/puzzle.dart';
import '../../services/board_image_service.dart';
import '../../services/engine/engine_service.dart';
import '../../services/screen_awake.dart';
import '../../services/puzzle_service.dart';
import '../../services/sound_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_dialogs.dart';
import '../../widgets/chess_board_widget.dart';
import '../../widgets/move_list.dart';
import '../board_editor_screen.dart';
import '../game_screen.dart';

/// Geri bildirim kartının durumu.
///
/// [info]: yalnızca bilgi (ör. motor bu hamleyi yargılayamadı); tahta
/// açık kalır, kullanıcı yeniden deneyebilir.
enum _Feedback { none, thinking, correct, wrong, finished, info }

/// Bulmaca çözme ekranı.
///
/// Bu listelerde hazır çözüm anahtarı yoktur; bu yüzden doğruluk, cihazdaki
/// motorun değerlendirmesiyle ölçülür: kullanıcının hamlesi pozisyonun
/// değerini en iyi hamleye göre belirgin biçimde düşürmüyorsa doğru sayılır.
/// Böylece tek bir "kabul edilen" hamle yerine eşdeğer iyi hamleler de
/// kabul edilir.
class PuzzleSolveScreen extends StatefulWidget {
  final PuzzleCollection collection;
  final List<Puzzle> puzzles;
  final int initialIndex;

  /// Bulmaca kimliği -> listedeki asıl numara.
  ///
  /// Ekrandaki liste süzülmüş ya da ters çevrilmiş olabilir; başlıkta ve
  /// bilgi satırında ise her zaman bu numara görünür, böylece kullanıcının
  /// gördüğü numara kitaptaki/listedeki numarayla aynı kalır.
  final Map<String, int> numbers;

  /// Süzgeçsiz listedeki toplam bulmaca sayısı.
  final int totalInCollection;

  const PuzzleSolveScreen({
    super.key,
    required this.collection,
    required this.puzzles,
    required this.initialIndex,
    this.numbers = const {},
    this.totalInCollection = 0,
  });

  /// Testlerde motorun yerine geçer.
  @visibleForTesting
  static Future<SearchResult> Function(
    String fen, {
    required int depth,
    required int movetimeMs,
  })? debugAnalyze;

  @override
  State<PuzzleSolveScreen> createState() => _PuzzleSolveScreenState();
}

class _PuzzleSolveScreenState extends State<PuzzleSolveScreen> {
  /// Çözüm gösteriminde iki hamle arası.
  ///
  /// Hamle sesi 209 ms, şah 470 ms, terfi 653 ms sürüyor; adımlar arka
  /// arkaya aktığı için buradaki bekleme ötekilerden uzun.
  static const Duration _solutionPace = Duration(milliseconds: 900);

  /// Rakibin cevabının ekrana gelme temposu.
  ///
  /// Kayıtlı çözüm dizisinde arama yapılmıyor, yani cevap anında
  /// geliyordu: hangi taşın nereye gittiği görülmüyordu. Çözümün
  /// baştan sona gösterilmesi ayrı ve bilerek daha yavaş (700 ms).
  static const Duration _movePace = Duration(milliseconds: 700);

  /// Çözümü kayıtlı olmayan bulmacalarda kabul edilen sapma.
  ///
  /// 80 santipiyon fazla gevşekti: kazanan bir konumda beraberliğe düşen
  /// hamle bile "doğru" sayılabiliyordu. Aşağıdaki [_keepsTheWin] kuralı
  /// da bunun için var.
  static const int _toleranceCp = 30;

  /// Kazanılmış konumu elden kaçıran hamle kabul edilmiyor.
  ///
  /// Motor ölçüsünde "kazanıyor" (+2.00 ve üstü) bir konumdan sonra
  /// kullanıcının hamlesi eşitliğe yakınsa (+1.00 altı) tolerans ne
  /// olursa olsun bu hamle doğru değildir.
  static bool _keepsTheWin(int baselineCp, int userCp) {
    if (baselineCp < 200) return true;
    return userCp >= 100;
  }

  final PuzzleService _service = PuzzleService.instance;

  late int _index;
  late Puzzle _puzzle;
  late engine.ChessGame _game;
  late engine.Color _solverColor;

  final List<MoveEntry> _moves = [];

  /// Motorla yargılanan bulmacada **başlangıç konumunun** analizi.
  ///
  /// "Baştan" tahtayı sıfırlarken ölçütü de buna döndürüyor. Eskiden
  /// döndürmüyordu: ölçüt sonraki bir konumda kalıyor, ipucu ve çözüm
  /// başlangıç konumunda o konumun hamlesini oynamaya çalışıp hiçbir şey
  /// göstermiyor, hamleler de yanlış ölçüte göre yargılanıyordu.
  SearchResult? _startBaseline;

  /// O anki ölçüt ve **ait olduğu konum**.
  ///
  /// Ölçüt her rakip cevabından sonra yeni konum için yeniden
  /// hesaplanıyor; iptal olursa eskisi duruyordu. Konumu yanında tutmak,
  /// başka bir konumun ölçütünün yanlışlıkla kullanılmasını engelliyor
  /// (bkz. [_currentBaseline]).
  SearchResult? _baseline;
  String? _baselineFen;

  /// Hamle listesinde dokunulan geçmiş konum; `null` ise canlı konum.
  int? _viewIndex;

  /// Son gösterilen çözümün başlangıçtan itibaren tamamı; çözüm düğmesine
  /// yeniden basılınca baştan bu oynanır.
  List<String>? _shownLine;

  /// Kullanıcı kayıtlı çözüm dizisini takip ediyor mu?
  bool _onSolutionLine = false;
  _Feedback _feedback = _Feedback.none;
  String _feedbackText = '';
  bool _busy = false;

  /// Bulmacanın konumu okunamıyorsa hata metni; okunuyorsa `null`.
  String? _fenError;
  bool _showHint = false;
  bool _solved = false;
  bool _favorite = false;
  bool _flipped = false;

  /// Kullanıcı tahtayı el ile çevirdiyse, sonraki bulmacalarda da o yön
  /// korunur; aksi hâlde çözen tarafa göre otomatik ayarlanır.
  bool _manualFlip = false;
  int _loadToken = 0;

  /// Tahtanın PNG olarak kaydedilebilmesi için çizim sınırı.
  final GlobalKey _boardKey = GlobalKey();

  /// Düşünürken ekran sönmesin; sayaç her hamlede sıfırlanıyor.
  final ScreenAwake _awake = ScreenAwake();

  @override
  void initState() {
    super.initState();
    _awake.keep();
    // Boş listede `clamp(0, -1)` hata fırlatıyor. Arayüz bu ekranı boş
    // listeyle açmıyor ama kapı açık kalmasın.
    _index = widget.puzzles.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, widget.puzzles.length - 1);
    _loadPuzzle();
  }

  @override
  void dispose() {
    _awake.release();
    // Ekrandan çıkarken süren aramayı bırak: sonucunu kimse beklemiyor,
    // boşuna işlemci ve pil harcıyordu. Tahta ekranında bu zaten yapılıyor.
    EngineService.instance.stopAll();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Yükleme
  // -------------------------------------------------------------------------

  /// Bulmacanın konumundan yeni bir oyun kurar.
  ///
  /// Bozuk FEN'de `fromFen` FormatException atıyor ve ekran hiç
  /// açılmıyordu (elle düzenlenmiş yedek, yarım yazılmış kayıt). Böyle
  /// bir kayıtta başlangıç konumu kuruluyor, tahta kapalı kalıyor ve
  /// durum yazıyla söyleniyor; diğer bulmacalara geçiş açık.
  engine.ChessGame _freshGame() {
    _fenError = engine.ChessGame.validateFen(_puzzle.fen);
    return _fenError == null
        ? engine.ChessGame.fromFen(_puzzle.fen)
        : engine.ChessGame();
  }

  Future<void> _loadPuzzle() async {
    final token = ++_loadToken;
    // Boş listede ekran yine de kurulur: yordamın geri kalanı bütün
    // alanları dolduruyor. Erken çıkmak `late` alanları atanmamış
    // bırakıyor ve ekran çizilirken hata veriyordu.
    _puzzle = widget.puzzles.isEmpty
        ? Puzzle(id: '', fen: engine.ChessGame().fen)
        : widget.puzzles[_index];

    setState(() {
      _game = _freshGame();
      _solverColor = _game.sideToMove;
      if (!_manualFlip) _flipped = _solverColor == engine.Color.black;
      _moves.clear();
      _onSolutionLine = _puzzle.hasSolution;
      _startBaseline = null;
      _baseline = null;
      _baselineFen = null;
      _viewIndex = null;
      _shownLine = null;
      _showHint = false;
      // Çözümü bilinen bulmacalarda motoru beklemeye gerek yok.
      _busy = _fenError == null && !_puzzle.hasSolution;
      _feedback = _fenError != null
          ? _Feedback.finished
          : (_puzzle.hasSolution ? _Feedback.none : _Feedback.thinking);
      _feedbackText = _fenError != null
          ? t('puzzles.fenCorrupt')
          : (_puzzle.hasSolution ? '' : t('puzzles.analysing'));
    });

    final progress = await _service.progressOf(_puzzle.id);
    if (token != _loadToken || !mounted) return;
    setState(() {
      _solved = progress.solved;
      _favorite = progress.favorite;
    });

    if (_fenError != null) return;
    if (_puzzle.hasSolution) return;

    final baseline = await _ask(_puzzle.fen, depth: 14, movetimeMs: 1800);
    if (token != _loadToken || !mounted) return;
    // İptal edilen arama burada **erken çıkmıyor**: eskiden çıkıyordu ve
    // tahtayı kilitleyen `_busy` sonsuza kadar açık kalıyordu. Boş sonuç
    // aşağıdaki "motor kullanılamıyor" yoluna giriyor; ekran serbest.

    // Motor yoksa (ya da çöktüyse) sonuç boş geliyor: skor 0, en iyi
    // hamle yok. Eskiden bu, 80 santipiyonluk toleransla **her hamlenin
    // doğru sayılması** demekti. Yargılayamıyorsak yargılamıyoruz.
    final unavailable = baseline.bestMoveUci.isEmpty;
    setState(() {
      _startBaseline = unavailable ? null : baseline;
      _baseline = _startBaseline;
      _baselineFen = unavailable ? null : _game.fen;
      _busy = false;
      _feedback = unavailable ? _Feedback.finished : _Feedback.none;
      _feedbackText = unavailable ? t('puzzles.engineUnavailable') : '';
    });
  }

  /// Motora sorar; isteği **başka bir ekranın kapanışı** düşürürse bir
  /// kez daha sorar.
  ///
  /// Motor tek ve `stopAll()` motordaki *her* işi iptal ediyor, yalnızca
  /// çağıranınkini değil. Kapanan ekranın temizliği de Flutter'da hemen
  /// değil, çıkış animasyonu bitince çalışıyor — yani alttaki ekran
  /// çoktan canlıyken. O aralıkta bu ekranın isteği düşebiliyor.
  ///
  /// Böyle bir iptal "motor cevap veremedi" demek değil: konum aynı,
  /// cevaba hâlâ ihtiyacımız var. Tekrar bilerek **tek**: döngüye
  /// dönmesin. İkincisi de düşerse sonuç boş kalır ve çağıran taraf
  /// zaten bildiği "motor yok" yoluna girer.
  Future<SearchResult> _ask(
    String fen, {
    required int depth,
    required int movetimeMs,
  }) async {
    final analyze = PuzzleSolveScreen.debugAnalyze ??
        (String fen, {required int depth, required int movetimeMs}) =>
            EngineService.instance
                .analyze(fen, depth: depth, movetimeMs: movetimeMs);
    final first = await analyze(fen, depth: depth, movetimeMs: movetimeMs);
    if (!first.cancelled) return first;
    return analyze(fen, depth: depth, movetimeMs: movetimeMs);
  }

  /// Çözüm dizisinde sırada beklenen hamle (UCI); yoksa `null`.
  String? get _expectedMove {
    if (!_onSolutionLine || !_puzzle.hasSolution) return null;
    if (_moves.length >= _puzzle.solution.length) return null;
    return _puzzle.solution[_moves.length];
  }

  /// Ölçüt **tahtadaki konuma** aitse o; değilse `null`.
  SearchResult? get _currentBaseline {
    final baseline = _baseline;
    if (baseline == null || _baselineFen != _game.fen) return null;
    return baseline.bestMoveUci.length >= 4 ? baseline : null;
  }

  /// Tahtadaki konumda oynanması gereken hamle (ipucu); bilinmiyorsa
  /// `null`.
  ///
  /// Eskiden motorla yargılanan bulmacalarda yalnızca ilk hamlede
  /// vardı: ikinci hamlede ipucu düğmesi hiçbir şey göstermiyordu.
  String? get _hintUci => _expectedMove ?? _currentBaseline?.bestMoveUci;

  /// Çözüm gösterilebilir mi?
  bool get _canReveal =>
      _fenError == null &&
      (_puzzle.hasSolution ||
          _startBaseline != null ||
          _currentBaseline != null);


  // -------------------------------------------------------------------------
  // Hamle değerlendirme
  // -------------------------------------------------------------------------

  Future<void> _onMove(engine.ChessMove move) async {
    if (_busy) return;
    _awake.keep();
    // Değerlendirme sürerken kullanıcı sonraki bulmacaya geçebiliyor;
    // jeton değişmişse bu hamlenin sonucu artık başka bir tahtaya
    // yazılmamalı (yanlış "çözüldü" ve bozuk tahta oluyordu).
    final token = _loadToken;
    if (!_puzzle.hasSolution && _baseline == null) return;

    setState(() {
      _busy = true;
      // İpucu tek hamlelik: basınca o anki hamlenin oku çıkıyor, hamle
      // oynanınca sönüyor. Açık kalsaydı bir kez basmak çözümün geri
      // kalanını da hamle hamle gösterirdi.
      _showHint = false;
      _feedback = _Feedback.thinking;
      _feedbackText = t('puzzles.evaluating');
    });

    final probe = _game.copy();
    final san = probe.sanFor(move);
    probe.makeMove(move);

    final correct = await _isCorrect(move, probe);
    if (!mounted || token != _loadToken) return;

    if (correct == null) {
      // Motor bu hamleyi yargılayamadı. Eskiden skor 0 sayılıyordu: ölçüt
      // sıfıra yakın bulmacalarda (savunma) zayıf bir hamle "doğru"
      // kabul ediliyordu. Hamle oynanmıyor, deneme sayılmıyor.
      setState(() {
        _busy = false;
        _feedback = _Feedback.info;
        _feedbackText = t('puzzles.engineUnavailable');
      });
      return;
    }

    await _service.registerAttempt(_puzzle.id);
    // Disk yazımı sürerken kullanıcı ekrandan çıkmış ya da bulmaca
    // değiştirmiş olabilir; silinmiş ekranda setState çağırmak hata
    // veriyordu.
    if (!mounted || token != _loadToken) return;

    if (!correct) {
      SoundService.instance.playWrong();
      setState(() {
        _busy = false;
        _feedback = _Feedback.wrong;
        _feedbackText = t('puzzles.wrong', {'move': san});
      });
      return;
    }

    // Doğru hamle: tahtaya uygula.
    final entry = MoveEntry.play(_game, move);
    setState(() {
      _moves.add(entry);
      _viewIndex = null;
      _feedback = _Feedback.correct;
      _feedbackText = t('puzzles.correct', {'move': san});
    });
    SoundService.instance.playForSan(san);

    // "Çözüldü" yalnızca hat bittiğinde yazılıyor.
    //
    // Çözümü kayıtlı bir bulmacada (mat-2 gibi) ilk doğru hamleyi bulup
    // ikincisini batıran biri çözmüş sayılmamalı; eskiden sayılıyordu ve
    // liste yalan söylüyordu. Çözümü olmayan bulmacalarda ise tek doğru
    // hamle zaten alıştırmanın tamamı, orada davranış değişmiyor.
    final lineComplete = !_puzzle.hasSolution ||
        _game.isCheckmate ||
        (_onSolutionLine && _moves.length >= _puzzle.solution.length);
    if (lineComplete && !_solved) {
      await _service.markSolved(_puzzle.id);
      if (!mounted || token != _loadToken) return;
      setState(() => _solved = true);
    }

    if (_game.isCheckmate || _game.isStalemate) {
      if (_game.isCheckmate) SoundService.instance.playNotify();
      setState(() {
        _busy = false;
        _feedback = _Feedback.finished;
        _feedbackText =
            _game.isCheckmate ? t('puzzles.mateDone') : t('puzzles.stalemate');
      });
      return;
    }

    await _playOpponentReply();
  }

  /// Oynanan hamlenin kabul edilip edilmeyeceğine karar verir.
  ///
  /// Çözümü kayıtlı bulmacalarda önce kayıtlı hamleye bakılır; farklı ama
  /// yine aynı sürede mat eden hamleler de motora danışılarak kabul edilir.
  ///
  /// Motor yargılayamadıysa (sonuç boş ya da iptal) `null` döner.
  Future<bool?> _isCorrect(engine.ChessMove move, engine.ChessGame after) async {
    if (after.isCheckmate) return true;

    final expected = _expectedMove;
    if (expected != null) {
      if (move.uci == expected) return true;

      // Kayıtlı çözümden ayrıldı: aynı hızda mat eden bir alternatif mi?
      final remaining = _puzzle.solution.length - _moves.length;
      final allowedMoves = (remaining + 1) ~/ 2;
      final reply = await _ask(after.fen, depth: 12, movetimeMs: 1200);
      final userMate = reply.mateIn == null ? null : -reply.mateIn!;
      if (userMate != null && userMate > 0 && userMate <= allowedMoves) {
        _onSolutionLine = false;
        return true;
      }
      return false;
    }

    // Ölçüt tahtadaki konuma ait olmalı. Rakip cevabından sonraki analiz
    // iptal olduysa eskiden önceki konumun ölçütü kullanılıyordu: hamle
    // başka bir konumun skoruyla karşılaştırılıyor, kazancı kaçıran bir
    // hamle bile kabul edilebiliyordu. Şimdi bu konum için soruluyor.
    var baseline = _currentBaseline;
    if (baseline == null) {
      final fen = _game.fen;
      final fresh = await _ask(fen, depth: 13, movetimeMs: 1200);
      if (fresh.cancelled || fresh.bestMoveUci.isEmpty) return null;
      _baseline = fresh;
      _baselineFen = fen;
      baseline = fresh;
    }
    if (move.uci == baseline.bestMoveUci) return true;

    final int userScore;
    final int? userMate;
    if (after.isStalemate) {
      // Pat: beraberlik. Motora sorulacak bir şey yok.
      userScore = 0;
      userMate = null;
    } else {
      final reply = await _ask(after.fen, depth: 13, movetimeMs: 1400);
      // İptal edilen ya da boş dönen aramanın skoru sıfırdır; tolerans
      // yüzünden zayıf bir hamle "doğru" sayılabilirdi.
      if (reply.cancelled || reply.bestMoveUci.isEmpty) return null;
      // Sonuç rakibin bakış açısındandır; kullanıcıya çevir.
      userScore = -reply.scoreCp;
      userMate = reply.mateIn == null ? null : -reply.mateIn!;
    }

    if (baseline.mateIn != null && baseline.mateIn! > 0) {
      return userMate != null &&
          userMate > 0 &&
          userMate <= baseline.mateIn! + 1;
    }
    if (!_keepsTheWin(baseline.scoreCp, userScore)) return false;
    return userScore >= baseline.scoreCp - _toleranceCp;
  }

  Future<void> _playOpponentReply() async {
    final fen = _game.fen;
    final token = _loadToken;
    final started = DateTime.now();

    // Kayıtlı çözüm dizisi varsa rakip o diziyi oynar.
    final scripted = _expectedMove;
    String? uci = scripted;
    if (uci == null) {
      final result = await _ask(fen, depth: 10, movetimeMs: 900);
      // İptalde erken çıkılmıyordu diye değil — çıkılıyordu ve `_busy`
      // açık kalıyordu. Boş hamle aşağıdaki denetime düşüyor, o da
      // ekranı serbest bırakıp durumu yazıyor.
      uci = result.bestMoveUci;
    }
    // Kayıtlı dizide arama yok, cevap anında gelirdi.
    final thought = DateTime.now().difference(started);
    if (thought < _movePace) {
      await Future<void>.delayed(_movePace - thought);
    }
    if (!mounted || token != _loadToken || _game.fen != fen) return;

    final move = _game.moveFromUci(uci);
    if (move == null) {
      setState(() {
        _busy = false;
        _feedback = _Feedback.finished;
        _feedbackText = t('puzzles.opponentStuck');
      });
      return;
    }

    final entry = MoveEntry.play(_game, move);
    setState(() {
      _moves.add(entry);
      _viewIndex = null;
      if (_game.isCheckmate) {
        _feedback = _Feedback.finished;
        _feedbackText = t('puzzles.opponentMated');
      } else {
        _feedback = _Feedback.correct;
        _feedbackText = t('puzzles.opponentPlayed', {'move': entry.san});
      }
    });
    SoundService.instance.playForSan(entry.san, opponent: true);

    // Motorla yargılanan bulmacalarda ölçüt yeni konuma göre kuruluyor.
    //
    // Eskiden başlangıç konumunun skoru sabit kalıyordu: çok hamleli bir
    // alıştırmada sonraki hamleler yanlış ölçülüyordu. Kayıtlı çözümden
    // ayrılıp eşdeğer bir mat bulan kullanıcıda ise ölçüt hiç yoktu ve
    // sonraki her hamle "yanlış" sayılıyordu.
    if (!_onSolutionLine || !_puzzle.hasSolution) {
      await _refreshBaseline(token);
      if (!mounted || token != _loadToken) return;
    }
    setState(() => _busy = false);
  }

  /// Ölçüt konumu değişince yeniden hesaplanır.
  Future<void> _refreshBaseline(int token) async {
    final fen = _game.fen;
    final result = await _ask(fen, depth: 13, movetimeMs: 1200);
    if (!mounted || token != _loadToken || _game.fen != fen) return;
    // İptal edilen arama eldeki ölçütü silmemeli. Eldeki ölçüt artık bu
    // konuma ait değil; [_currentBaseline] onu kullanmıyor, sıradaki
    // hamlede bu konum yeniden soruluyor.
    if (result.cancelled) return;
    setState(() {
      _baseline = result.bestMoveUci.isEmpty ? null : result;
      _baselineFen = fen;
    });
  }

  /// Bulmacayı başa sarar ve **bekleyen işleri iptal eder**.
  ///
  /// Eskiden yalnızca tahtayı sıfırlıyordu: rakip cevabı beklenirken
  /// basıldığında bekleyen iş konumun değiştiğini görüp `_busy`'yi
  /// indirmeden çıkıyor, tahta ve ileri/geri düğmeleri kilitli kalıyordu.
  /// Tek çıkış ekrandan çıkıp geri dönmekti.
  void _retry() {
    // Ölçüt yoksa hafif sıfırlama yetmez: tahta açılır ama hamleler
    // yargılanamadığı için `_onMove` onları sessizce yok sayar, yani
    // tahta yine ölü görünür. Böyle bir durumda bulmacayı baştan
    // yüklüyoruz; `_loadPuzzle` jetonu kendi ilerletiyor.
    if (!_puzzle.hasSolution && _startBaseline == null) {
      _loadPuzzle();
      return;
    }
    _loadToken++;
    setState(() {
      _busy = false;
      _game = _freshGame();
      _onSolutionLine = _puzzle.hasSolution;
      _moves.clear();
      _viewIndex = null;
      // Ölçüt de başlangıç konumuna dönüyor (bkz. [_startBaseline]).
      _baseline = _startBaseline;
      _baselineFen = _startBaseline == null ? null : _game.fen;
      _feedback = _Feedback.none;
      _feedbackText = '';
      _showHint = false;
    });
  }

  /// Çözümü gösterir.
  ///
  /// Bulmaca sürüyorsa **kaldığı yerden** devam eder: kayıtlı çözümde
  /// sıradaki hamlelerden, motorla yargılanan bulmacada tahtadaki konumun
  /// en iyi hattından. Eskiden her zaman başa dönüp başlangıç ölçütünün
  /// hattını oynuyordu; bir hamleden sonra ölçüt yeni konuma ait olduğu
  /// için hiçbir hamle oynanmıyor, ekran "çözüm gösterildi" deyip
  /// kilitleniyordu.
  ///
  /// Bulmaca bittiyse (çözüm gösterildi ya da mat edildi) çözümü baştan
  /// oynar; düğme böylece her zaman bir şey yapar.
  Future<void> _revealSolution() async {
    if (!_canReveal) return;
    final finished = _feedback == _Feedback.finished;
    final current = _currentBaseline;

    List<String> line;
    var fromStart = false;
    if (!finished && _onSolutionLine && _puzzle.hasSolution &&
        _moves.length < _puzzle.solution.length) {
      line = _puzzle.solution.sublist(_moves.length);
    } else if (!finished && current != null && current.pvUci.isNotEmpty) {
      line = current.pvUci;
    } else {
      fromStart = true;
      line = _shownLine ??
          (_puzzle.hasSolution
              ? _puzzle.solution
              : (_startBaseline?.pvUci ?? const <String>[]));
    }
    if (line.isEmpty) return;

    if (fromStart) {
      _retry();
    } else {
      // Bekleyen bir iş kalmışsa (olmamalı: düğme meşgulken kapalı)
      // gösterimle çakışmasın.
      _loadToken++;
    }
    // Jeton `_retry`'den sonra alınıyor: o çağrı bekleyen işleri iptal
    // etmek için jetonu ilerletiyor.
    final token = _loadToken;
    final prefix = [for (final m in _moves) m.move.uci];
    // Çözüm oynanırken tahta kapalı. Eskiden açık kalıyordu: 700 ms'lik
    // adımlar arasında kullanıcı hamle yapabiliyor ve tahta karışıyordu.
    setState(() {
      _busy = true;
      _showHint = false;
      _viewIndex = null;
    });

    // Çözümü adım adım oyna.
    final played = <String>[];
    for (final uci in line) {
      if (!mounted) return;
      final move = _game.moveFromUci(uci);
      if (move == null) break;
      final solverMove = _game.sideToMove == _solverColor;
      final entry = MoveEntry.play(_game, move);
      played.add(uci);
      setState(() {
        _moves.add(entry);
        _viewIndex = null;
      });
      // Gösterim sessizdi: hamleler akıyor ama hiçbir ses çıkmıyordu.
      // Çözen tarafın hamlesi kendi sesiyle, rakibinki rakip sesiyle.
      SoundService.instance.playForSan(entry.san, opponent: !solverMove);
      // Çözüm gösterimi bilerek daha yavaş: izlenerek takip ediliyor.
      await Future<void>.delayed(_solutionPace);
      // Gösterim sürerken başka bulmacaya geçilmiş olabilir.
      if (!mounted || token != _loadToken) return;
    }
    if (!mounted) return;
    setState(() {
      _shownLine = [...prefix, ...played];
      _busy = false;
      _feedback = _Feedback.finished;
      _feedbackText = t('puzzles.solutionShown');
    });
  }

  /// Hamle listesinde dokunulan hamleden sonraki konumu gösterir.
  ///
  /// Eskiden listedeki hamlelere dokunmak hiçbir şey yapmıyordu. Son
  /// hamleye dokunmak canlı konuma döndürüyor; yeni bir hamle geldiğinde
  /// de canlı konuma dönülüyor.
  void _viewMove(int index) {
    if (index < 0 || index >= _moves.length) return;
    setState(() => _viewIndex = index == _moves.length - 1 ? null : index);
  }

  /// Geçmiş konuma bakılıyorsa o konumun tahtası; değilse `null`.
  engine.ChessGame? get _viewGame {
    final index = _viewIndex;
    if (index == null || index >= _moves.length) return null;
    final fen = _moves[index].fenAfter;
    final cached = _viewCache;
    if (cached != null && cached.fen == fen) return cached;
    return _viewCache = engine.ChessGame.fromFen(fen);
  }

  /// Aynı konum için her çizimde yeni bir tahta kurulmasın.
  engine.ChessGame? _viewCache;

  void _goToPuzzle(int index) {
    if (index < 0 || index >= widget.puzzles.length) return;
    setState(() => _index = index);
    _loadPuzzle();
  }

  Future<void> _toggleFavorite() async {
    final value = await _service.toggleFavorite(_puzzle.id);
    if (mounted) setState(() => _favorite = value);
  }

  Future<void> _editPuzzle() async {
    // Arayüz boş listeyle bu ekranı açmıyor; açılırsa menü yine duruyor
    // ve aşağıdaki `widget.puzzles[_index]` atamasi listeyi taşardı.
    if (widget.puzzles.isEmpty) return;
    final fen = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => BoardEditorScreen(
          initialFen: _puzzle.fen,
          title: t('puzzles.editPuzzle'),
        ),
      ),
    );
    if (fen == null || !mounted) return;
    await _service.updatePuzzle(
      widget.collection,
      _puzzle,
      fen: fen,
      title: _puzzle.title,
      note: _puzzle.note,
      tags: _puzzle.tags,
    );
    _puzzle.fen = fen;
    widget.puzzles[_index] = _puzzle;
    _loadPuzzle();
  }

  /// Bulmacanın süzgeçten bağımsız numarası.
  int get _absoluteNumber =>
      widget.numbers[_puzzle.id] ?? _puzzle.number ?? _index + 1;

  /// Tahtanın o anki görüntüsünü PNG olarak kaydeder.
  ///
  /// Dosya adı `board-<liste>-<numara>.png` olur: kaydedilen görüntüler
  /// hangi listenin kaçıncı bulmacası olduğu belli olacak şekilde
  /// birikir.
  Future<void> _saveBoardImage() async {
    final list = widget.collection.name
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .trim();
    final result = await BoardImageService.saveBoardPng(
      _boardKey,
      fileName: 'board-${list.isEmpty ? 'liste' : list}-$_absoluteNumber.png',
    );
    if (!mounted) return;
    AppDialogs.snack(context, t('board.saveResult.$result'));
  }

  Future<void> _addNote() async {
    final note = await AppDialogs.prompt(
      context,
      title: t('common.note'),
      label: t('puzzles.noteLabel'),
      initialValue: _puzzle.note ?? '',
      maxLines: 4,
    );
    if (note == null || !mounted) return;
    await _service.updatePuzzle(
      widget.collection,
      _puzzle,
      fen: _puzzle.fen,
      title: _puzzle.title,
      note: note,
      tags: _puzzle.tags,
    );
    // Yazma sürerken ekrandan çıkılmış olabilir.
    if (!mounted) return;
    setState(() => _puzzle.note = note);
  }

  /// Bulmacanın notunu siler.
  Future<void> _deleteNote() async {
    await _service.updatePuzzle(
      widget.collection,
      _puzzle,
      fen: _puzzle.fen,
      title: _puzzle.title,
      note: null,
      tags: _puzzle.tags,
    );
    if (!mounted) return;
    // Not ekrandan zaten kalkıyor; ayrıca bildirim göstermiyoruz.
    setState(() => _puzzle.note = null);
  }

  // -------------------------------------------------------------------------
  // Arayüz
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final arrows = <BoardArrow>[];
    // İpucu bizzat istenen bir şey: "motor okları" ayarına bağlı değil.
    // Eskiden bağlıydı ve ayar kapalıyken düğme hiçbir şey yapmıyordu.
    // Geçmiş bir konuma bakılırken gösterilmiyor (başka bir tahtaya ait).
    if (_showHint && _viewIndex == null) {
      final best = _hintUci;
      if (best != null && best.length >= 4) {
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
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _puzzle.title ?? t('puzzles.puzzleTitle', {'n': _absoluteNumber}),
        ),
        actions: [
          IconButton(
            tooltip: _favorite
                ? t('common.favoriteRemove')
                : t('common.favoriteAdd'),
            icon: Icon(
              _favorite ? Icons.star_rounded : Icons.star_border_rounded,
              color: _favorite ? scheme.warning : null,
            ),
            onPressed: _toggleFavorite,
          ),
          IconButton(
            tooltip: t('common.flipBoard'),
            icon: const Icon(Icons.swap_vert_rounded),
            onPressed: () => setState(() {
              _flipped = !_flipped;
              _manualFlip = true;
            }),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'edit':
                  _editPuzzle();
                  break;
                case 'note':
                  _addNote();
                  break;
                case 'deleteNote':
                  _deleteNote();
                  break;
                case 'fen':
                  Clipboard.setData(ClipboardData(text: _puzzle.fen));
                  AppDialogs.snack(context, t('common.fenCopied'));
                  break;
                case 'png':
                  _saveBoardImage();
                  break;
                case 'play':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GameScreen(
                        mode: GameMode.versusEngine,
                        // "Devam" tahtadaki konumdan başlar; eskiden
                        // bulmacanın ilk konumuna dönüyordu, yani
                        // bulduğun hamleler siliniyordu.
                        startFen: _game.fen,
                        playerColor: _solverColor,
                        title: t('puzzles.continueVsEngine'),
                      ),
                    ),
                  );
                  break;
                case 'analyze':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GameScreen(
                        startFen: _puzzle.fen,
                        title: t('puzzles.analysisTitle'),
                      ),
                    ),
                  );
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'edit',
                child: Text(t('common.editPosition')),
              ),
              PopupMenuItem(value: 'note', child: Text(t('common.addNote'))),
              if (_puzzle.note != null && _puzzle.note!.isNotEmpty)
                PopupMenuItem(
                  value: 'deleteNote',
                  child: Text(t('common.deleteNote')),
                ),
              PopupMenuItem(value: 'fen', child: Text(t('common.copyFen'))),
              PopupMenuItem(value: 'png', child: Text(t('board.savePng'))),
              PopupMenuItem(
                value: 'play',
                child: Text(t('puzzles.playVsEngine')),
              ),
              PopupMenuItem(
                value: 'analyze',
                child: Text(t('common.openInAnalysis')),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Layout.isTwoColumn(context)
            ? _wideBody(scheme, arrows)
            : ContentWidth(child: _narrowBody(scheme, arrows)),
      ),
    );
  }

  /// Tahtanın üstünde duran başlık ve tahtanın kendi dikey boşluğu.
  static const double _wideChromeHeight = 48;

  /// Tahtanın yatay boşluğu ([_boardArea] içindeki dolgu), iki yan.
  static const double _boardGutter = 20;

  /// Tahta; kalan alana sığan en büyük kare, üst sınır [cap].
  Widget _boardArea(List<BoardArrow> arrows, double cap) {
    return Expanded(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final side = Layout.boardSide(
                constraints.maxWidth,
                constraints.maxHeight,
                cap,
              );
              return RepaintBoundary(
                key: _boardKey,
                child: SizedBox(
                  width: side,
                  height: side,
                  child: ChessBoardWidget(
                    game: _viewGame ?? _game,
                    flipped: _flipped,
                    // Geçmiş bir konuma bakılırken hamle yapılamaz.
                    interactive: !_busy &&
                        _feedback != _Feedback.finished &&
                        _viewIndex == null,
                    movableSide: _solverColor,
                    lastMove: _moves.isEmpty
                        ? null
                        : _moves[_viewIndex ?? _moves.length - 1].move,
                    onMove: _onMove,
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

  /// Hamle şeridi. Yeri boşken de duruyor: ilk hamlede tahta yukarı
  /// kaymasın (geri bildirim kartında da aynısı var).
  Widget _moveStrip({required bool vertical}) {
    if (_moves.isEmpty) return const SizedBox();
    return MoveList(
      moves: _moves,
      currentIndex: _viewIndex ?? _moves.length - 1,
      onMoveTap: _viewMove,
      vertical: vertical,
      // Bulmacanın ilk hamlesi çözen tarafındır.
      blackFirst: _solverColor == engine.Color.black,
    );
  }

  /// Telefon ve dar pencere: her şey alt alta.
  Widget _narrowBody(ColorScheme scheme, List<BoardArrow> arrows) {
    return Column(
      children: [
        _header(scheme),
        _boardArea(arrows, Layout.narrowBoardCap),
        if (_puzzle.note != null && _puzzle.note!.isNotEmpty)
          _noteCard(scheme),
        _feedbackCard(scheme),
        SizedBox(height: 46, child: _moveStrip(vertical: false)),
        _actions(scheme),
      ],
    );
  }

  /// Geniş pencere ve tablet: solda tahta, sağda hamleler ve düğmeler.
  ///
  /// Oyun ekranıyla aynı geometri: kenar önce hesaplanıyor, grup ona
  /// göre kurulup birlikte ortalanıyor. Eskiden bulmaca ekranı geniş
  /// pencerede de telefon düzenindeydi; tahta 520'de kalıyor, altındaki
  /// şeritler yüzünden daha da küçülüyordu.
  Widget _wideBody(ColorScheme scheme, List<BoardArrow> arrows) {
    final cap = Layout.maxWideBoardSide;
    final scale = Layout.isDesktop
        ? Layout.boardScales[SettingsService.instance.boardSize]
        : 1.0;
    return LayoutBuilder(
      builder: (context, constraints) {
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
                      _header(scheme),
                      _boardArea(arrows, side),
                    ],
                  ),
                ),
                SizedBox(width: gap),
                SizedBox(
                  width: Layout.sidePanelWidth,
                  child: _sidePanel(scheme),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Sağ sütun: not, geri bildirim, hamle listesi ve düğmeler.
  Widget _sidePanel(ColorScheme scheme) {
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 8, 12, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          if (_puzzle.note != null && _puzzle.note!.isNotEmpty)
            _noteCard(scheme),
          _feedbackCard(scheme),
          Divider(height: 1, color: scheme.outlineVariant),
          Expanded(child: _moveStrip(vertical: true)),
          Divider(height: 1, color: scheme.outlineVariant),
          _actions(scheme, panel: true),
        ],
      ),
    );
  }

  Widget _header(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _solverColor == engine.Color.white
                  ? const Color(0xFFF2EEE7)
                  : const Color(0xFF3B3630),
              border: Border.all(color: scheme.outlineVariant),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              t('puzzles.header', {
                'side': _puzzle.sideToMoveLabel,
                'index': _absoluteNumber,
                'total': widget.totalInCollection == 0
                    ? widget.puzzles.length
                    : widget.totalInCollection,
              }),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          if (_solved)
            Row(
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  size: 15,
                  color: scheme.success,
                ),
                const SizedBox(width: 4),
                Text(
                  t('puzzles.solved'),
                  style: TextStyle(fontSize: 12, color: scheme.success),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _noteCard(ColorScheme scheme) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _puzzle.note!,
        style: TextStyle(fontSize: 12.5, color: scheme.onSecondaryContainer),
      ),
    );
  }

  Widget _feedbackCard(ColorScheme scheme) {
    // Hedef kartı kaldırıldı: "En iyi hamleyi bul", "Mat var: 2
    // hamlede" gibi satırlar bulmacayı çözmeye bir şey katmıyor,
    // üstelik ilkini okuyan çözümü baştan biliyordu. Doğru/yanlış/
    // bitti/düşünüyor geri bildirimleri duruyor.
    // Kartın yeri boşken de duruyor: kart gelip gidince tahta aşağı
    // yukarı kaymasın. Motor şeridindeki çözümün aynısı (game_screen).
    if (_feedback == _Feedback.none) return const SizedBox(height: 50);
    final (color, icon, text) = switch (_feedback) {
      _Feedback.correct => (
          scheme.correct,
          Icons.check_circle_rounded,
          _feedbackText,
        ),
      _Feedback.wrong => (scheme.wrong, Icons.cancel_rounded, _feedbackText),
      _Feedback.finished => (
          scheme.secondary,
          Icons.flag_rounded,
          _feedbackText,
        ),
      _Feedback.thinking => (
          scheme.onSurfaceVariant,
          Icons.hourglass_top_rounded,
          _feedbackText,
        ),
      _Feedback.info => (
          scheme.onSurfaceVariant,
          Icons.info_outline_rounded,
          _feedbackText,
        ),
      // Ulaşılmaz: none durumunda kart yukarıda çizilmeden dönüyor.
      _Feedback.none => (scheme.onSurfaceVariant, Icons.info_outline, ''),
    };

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
          if (_busy)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }

  Widget _actions(ColorScheme scheme, {bool panel = false}) {
    // Yan panelde kendi kartı yok.
    //
    // Panelin zaten bir yüzeyi var; içine ikinci bir kart koymak iki
    // şeyi bozuyordu. Kartın 12'şer piksellik kenar boşluğu içerideki
    // ayracı da içeri kaçırıyor, yani panelin tamamı boyunca uzayan
    // üstteki ayraçla hizalanmıyordu. Üst payın (4) alt paydan (12)
    // ince olması da bloğu aşağı itiyordu.
    final content = Column(
      children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _action(
                Icons.lightbulb_outline_rounded,
                t('common.hint'),
                // Yanlışlıkla basıldıysa aynı tuş ipucunu kapatıyor.
                // Geçmiş bir konuma bakılıyorsa canlı konuma dönüyor.
                _hintUci != null &&
                        !_busy &&
                        _feedback != _Feedback.finished
                    ? () => setState(() {
                          _viewIndex = null;
                          _showHint = !_showHint;
                        })
                    : null,
              ),
              _action(
                Icons.visibility_outlined,
                t('puzzles.solution'),
                _canReveal && !_busy ? _revealSolution : null,
              ),
              _action(
                Icons.refresh_rounded,
                t('common.restart'),
                // Meşgulken de açık: bu düğme **kaçış kapısı**. Motor
                // isteği düşerse tahta, ileri/geri ve "Çözüm" kapanıyor;
                // "Yeniden" de kapalı olsaydı ekrandan çıkmaktan başka
                // yol kalmazdı. Sebebini öngöremediğimiz kilitlenmelerde
                // de kullanıcı burada sıkışmaz.
                _moves.isEmpty && !_busy ? null : _retry,
              ),
            ],
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  // Değerlendirme ya da çözüm gösterimi sürerken
                  // bulmaca değiştirmek yarışa yol açıyordu.
                  onPressed: _index > 0 && !_busy
                      ? () => _goToPuzzle(_index - 1)
                      : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                  label: Text(t('common.previous')),
                ),
              ),
              Container(width: 1, height: 24, color: scheme.outlineVariant),
              Expanded(
                child: TextButton.icon(
                  onPressed: _index < widget.puzzles.length - 1 && !_busy
                      ? () => _goToPuzzle(_index + 1)
                      : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                  iconAlignment: IconAlignment.end,
                  label: Text(t('common.next')),
                ),
              ),
          ],
        ),
      ],
    );

    // Panelde dikey pay yok: satır iki ayracın arasına tam oturuyor.
    // 4 piksellik pay varken düğmenin üstüne gelince çıkan vurgu alttaki
    // çizgiye değiyor ama üsttekine değmiyordu; düğme hizasız duruyor
    // gibi görünüyordu.
    if (panel) return content;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: content,
    );
  }

  Widget _action(IconData icon, String label, VoidCallback? onPressed) {
    // Esnek: bu satır telefonun tam genişliğine göre kurulmuştu, yan
    // panelde 340 piksele giriyor. Sabit kalsaydı üç düğme taşardı
    // (masaüstü yazı ölçeğiyle daha da çok).
    return Flexible(
      child: TextButton.icon(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          visualDensity: VisualDensity.compact,
        ),
        icon: Icon(icon, size: 19),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13),
        ),
      ),
    );
  }
}
