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

enum _Feedback { none, thinking, correct, wrong, finished }

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

  static const int _toleranceCp = 80;

  final PuzzleService _service = PuzzleService.instance;

  late int _index;
  late Puzzle _puzzle;
  late engine.ChessGame _game;
  late engine.Color _solverColor;

  final List<MoveEntry> _moves = [];
  SearchResult? _baseline;

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
    _index = widget.initialIndex.clamp(0, widget.puzzles.length - 1);
    _loadPuzzle();
  }

  @override
  void dispose() {
    _awake.release();
    // Ekrandan çıkarken süren aramayı bırak: sonucunu kimse beklemiyor,
    // boşuna işlemci ve pil harcıyordu. Tahta ekranında bu zaten yapılıyor.
    EngineService.instance.stopAnalysis();
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
    _puzzle = widget.puzzles[_index];

    setState(() {
      _game = _freshGame();
      _solverColor = _game.sideToMove;
      if (!_manualFlip) _flipped = _solverColor == engine.Color.black;
      _moves.clear();
      _onSolutionLine = _puzzle.hasSolution;
      _baseline = null;
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

    final baseline = await EngineService.instance.analyze(
      _puzzle.fen,
      depth: 14,
      movetimeMs: 1800,
    );
    if (token != _loadToken || !mounted) return;

    // Motor yoksa (ya da çöktüyse) sonuç boş geliyor: skor 0, en iyi
    // hamle yok. Eskiden bu, 80 santipiyonluk toleransla **her hamlenin
    // doğru sayılması** demekti. Yargılayamıyorsak yargılamıyoruz.
    final unavailable = baseline.bestMoveUci.isEmpty;
    setState(() {
      _baseline = unavailable ? null : baseline;
      _busy = false;
      _feedback = unavailable ? _Feedback.finished : _Feedback.none;
      _feedbackText = unavailable ? t('puzzles.engineUnavailable') : '';
    });
  }

  /// Çözüm dizisinde sırada beklenen hamle (UCI); yoksa `null`.
  String? get _expectedMove {
    if (!_onSolutionLine || !_puzzle.hasSolution) return null;
    if (_moves.length >= _puzzle.solution.length) return null;
    return _puzzle.solution[_moves.length];
  }

  /// İpucu ya da çözüm gösterilebilir mi?
  bool get _hasAnswer => _puzzle.hasSolution || _baseline != null;


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
  Future<bool> _isCorrect(engine.ChessMove move, engine.ChessGame after) async {
    if (after.isCheckmate) return true;

    final expected = _expectedMove;
    if (expected != null) {
      if (move.uci == expected) return true;

      // Kayıtlı çözümden ayrıldı: aynı hızda mat eden bir alternatif mi?
      final remaining = _puzzle.solution.length - _moves.length;
      final allowedMoves = (remaining + 1) ~/ 2;
      final reply = await EngineService.instance.analyze(
        after.fen,
        depth: 12,
        movetimeMs: 1200,
      );
      final userMate = reply.mateIn == null ? null : -reply.mateIn!;
      if (userMate != null && userMate > 0 && userMate <= allowedMoves) {
        _onSolutionLine = false;
        return true;
      }
      return false;
    }

    final baseline = _baseline;
    if (baseline == null) return false;
    if (move.uci == baseline.bestMoveUci) return true;

    final reply = await EngineService.instance.analyze(
      after.fen,
      depth: 13,
      movetimeMs: 1400,
    );

    // Sonuç rakibin bakış açısındandır; kullanıcıya çevir.
    final userScore = -reply.scoreCp;
    final userMate = reply.mateIn == null ? null : -reply.mateIn!;

    if (baseline.mateIn != null && baseline.mateIn! > 0) {
      return userMate != null &&
          userMate > 0 &&
          userMate <= baseline.mateIn! + 1;
    }
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
      final result = await EngineService.instance.analyze(
        fen,
        depth: 10,
        movetimeMs: 900,
      );
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
    final result = await EngineService.instance.analyze(
      fen,
      depth: 13,
      movetimeMs: 1200,
    );
    if (!mounted || token != _loadToken || _game.fen != fen) return;
    setState(() => _baseline = result.bestMoveUci.isEmpty ? null : result);
  }

  /// Bulmacayı başa sarar ve **bekleyen işleri iptal eder**.
  ///
  /// Eskiden yalnızca tahtayı sıfırlıyordu: rakip cevabı beklenirken
  /// basıldığında bekleyen iş konumun değiştiğini görüp `_busy`'yi
  /// indirmeden çıkıyor, tahta ve ileri/geri düğmeleri kilitli kalıyordu.
  /// Tek çıkış ekrandan çıkıp geri dönmekti.
  void _retry() {
    _loadToken++;
    setState(() {
      _busy = false;
      _game = _freshGame();
      _onSolutionLine = _puzzle.hasSolution;
      _moves.clear();
      _feedback = _Feedback.none;
      _feedbackText = '';
      _showHint = false;
    });
  }

  Future<void> _revealSolution() async {
    final line = _puzzle.hasSolution
        ? _puzzle.solution
        : (_baseline?.pvUci ?? const <String>[]);
    if (line.isEmpty) return;
    _retry();
    // Jeton `_retry`'den sonra alınıyor: o çağrı bekleyen işleri iptal
    // etmek için jetonu ilerletiyor.
    final token = _loadToken;
    // Çözüm oynanırken tahta kapalı. Eskiden açık kalıyordu: 700 ms'lik
    // adımlar arasında kullanıcı hamle yapabiliyor ve tahta karışıyordu.
    setState(() => _busy = true);

    // Çözümü adım adım oyna.
    for (final uci in line) {
      if (!mounted) return;
      final move = _game.moveFromUci(uci);
      if (move == null) break;
      final solverMove = _game.sideToMove == _solverColor;
      final entry = MoveEntry.play(_game, move);
      setState(() => _moves.add(entry));
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
      _busy = false;
      _feedback = _Feedback.finished;
      _feedbackText = t('puzzles.solutionShown');
    });
  }

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
    if (_showHint) {
      final best =
          _expectedMove ?? (_moves.isEmpty ? _baseline?.bestMoveUci : null);
      if (SettingsService.instance.showEngineArrows &&
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
        child: ContentWidth(
          child: Column(
            children: [
              _header(scheme),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final side = Layout.boardSide(
                          constraints.maxWidth,
                          constraints.maxHeight,
                        );
                        return RepaintBoundary(
                          key: _boardKey,
                          child: SizedBox(
                            width: side,
                            height: side,
                            child: ChessBoardWidget(
                              game: _game,
                              flipped: _flipped,
                              interactive:
                                  !_busy && _feedback != _Feedback.finished,
                              movableSide: _solverColor,
                              lastMove:
                                  _moves.isEmpty ? null : _moves.last.move,
                              onMove: _onMove,
                              arrows: arrows,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              if (_puzzle.note != null && _puzzle.note!.isNotEmpty)
                _noteCard(scheme),
              _feedbackCard(scheme),
              // Şeridin yeri boşken de duruyor: ilk hamlede tahta
              // yukarı kaymasın (geri bildirim kartında da aynısı var).
              SizedBox(
                height: 46,
                child: _moves.isEmpty
                    ? null
                    : MoveList(
                        moves: _moves,
                        currentIndex: _moves.length - 1,
                        onMoveTap: (_) {},
                        // Bulmacanın ilk hamlesi çözen tarafındır.
                        blackFirst: _solverColor == engine.Color.black,
                      ),
              ),
              _actions(scheme),
            ],
          ),
        ),
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

  Widget _actions(ColorScheme scheme) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _action(
                Icons.lightbulb_outline_rounded,
                t('common.hint'),
                // Yanlışlıkla basıldıysa aynı tuş ipucunu kapatıyor.
                _hasAnswer
                    ? () => setState(() => _showHint = !_showHint)
                    : null,
              ),
              _action(
                Icons.visibility_outlined,
                t('puzzles.solution'),
                _hasAnswer && !_busy ? _revealSolution : null,
              ),
              _action(
                Icons.refresh_rounded,
                t('common.restart'),
                _moves.isEmpty ? null : _retry,
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
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback? onPressed) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 19),
      label: Text(label, style: const TextStyle(fontSize: 13)),
    );
  }
}
