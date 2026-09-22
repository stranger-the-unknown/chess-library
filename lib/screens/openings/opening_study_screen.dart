import 'dart:async';

import 'package:flutter/material.dart';

import '../../widgets/responsive.dart';

import '../../l10n/app_strings.dart';
import '../../models/chess_engine.dart' as engine;
import '../../models/opening.dart';
import '../../services/opening_service.dart';
import '../../services/sound_service.dart';
import '../../theme/app_theme.dart';
import '../../services/board_image_service.dart';
import '../../services/settings_service.dart';
import '../../widgets/app_dialogs.dart';
import '../../models/move_entry.dart';
import '../../widgets/chess_board_widget.dart';
import '../../widgets/move_list.dart';
import '../game_screen.dart';

enum StudyMode {
  /// Varyantı adım adım izle.
  watch,

  /// Hamleleri sen oyna; yanlışta uyarı al.
  practice,
}

/// Tek bir açılış varyantını çalışma ekranı.
class OpeningStudyScreen extends StatefulWidget {
  final Opening opening;

  const OpeningStudyScreen({super.key, required this.opening});

  @override
  State<OpeningStudyScreen> createState() => _OpeningStudyScreenState();
}

class _OpeningStudyScreenState extends State<OpeningStudyScreen> {
  final OpeningService _service = OpeningService.instance;

  /// Hamle şeridini seçili hamlede tutar; kural tahtanın altındaki
  /// şeritle aynı yerde duruyor.
  final GlobalKey _boardImageKey = GlobalKey();

  late engine.ChessGame _game;
  int _cursor = -1;
  StudyMode _mode = StudyMode.watch;
  bool _flipped = false;
  bool _autoPlaying = false;
  bool _mistakeMade = false;
  String? _message;
  bool _messageIsError = false;
  bool _favorite = false;
  bool _learned = false;
  Timer? _autoTimer;

  /// Hamleler, ortak listenin beklediği biçimde.
  late final List<MoveEntry> _entries;

  @override
  void initState() {
    super.initState();
    _game = engine.ChessGame();
    // Hamle listesi uygulamanın her yerinde aynı widget: oyun ve bulmaca
    // ekranlarıyla aynı hizalama, aynı yazı stili. Eskiden bu ekran kendi
    // şeridini çiziyordu ve hamleler sola yaslı, numaralar farklı
    // puntodaydı.
    _entries = MoveEntry.fromUciList(widget.opening.uciMoves);
    _loadProgress();
  }

  Future<void> _saveBoardImage() async {
    final result = await BoardImageService.saveBoardPng(
      _boardImageKey,
      fileName: 'chess-library-opening.png',
    );
    if (!mounted) return;
    AppDialogs.snack(context, t('board.saveResult.$result'));
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadProgress() async {
    final progress = await _service.progressOf(widget.opening.id);
    if (!mounted) return;
    setState(() {
      _favorite = progress.favorite;
      _learned = progress.learned;
    });
  }

  // -------------------------------------------------------------------------
  // Konum yönetimi
  // -------------------------------------------------------------------------

  engine.ChessGame _positionAt(int index) {
    final position = engine.ChessGame();
    for (int i = 0; i <= index && i < widget.opening.uciMoves.length; i++) {
      final move = position.moveFromUci(widget.opening.uciMoves[i]);
      if (move == null) break;
      position.makeMove(move);
    }
    return position;
  }

  engine.ChessMove? get _currentMove {
    if (_cursor < 0 || _cursor >= widget.opening.uciMoves.length) return null;
    return _positionAt(_cursor - 1)
        .moveFromUci(widget.opening.uciMoves[_cursor]);
  }

  /// Hamlenin SAN metni; kayıt bozuksa boş metin.
  ///
  /// `sanMoves` ile `uciMoves` birlikte yazılıyor, ama elle düzenlenmiş
  /// bir yedekte uzunlukları tutmayabilir: indis `uciMoves`'a göre
  /// sınırlandığı için kısa olan listede RangeError çıkıyordu.
  String _san(int index) =>
      index >= 0 && index < widget.opening.sanMoves.length
          ? widget.opening.sanMoves[index]
          : '';

  void _goTo(int index, {bool silent = false}) {
    final clamped = index.clamp(-1, widget.opening.uciMoves.length - 1);
    final forward = clamped > _cursor;
    setState(() {
      _cursor = clamped;
      _game = _positionAt(clamped);
    });
    if (forward && clamped >= 0 && !silent) {
      SoundService.instance.playForSan(
        _san(clamped),
        opponent: clamped.isOdd,
      );
    }
  }

  /// Bekleyen otomatik hamleleri geçersiz kılan jeton.
  ///
  /// Rakibin cevabı bir gecikmeyle oynanıyor; başa sarma ya da kip
  /// değiştirme o gecikmeyi iptal etmiyordu ve bekleyen hamle sıfırlanan
  /// tahtada yine oynanıyordu. Bulmacada aynı sınıf hata `_loadToken`
  /// ile kapatılmıştı, burası atlanmıştı.
  int _token = 0;

  void _reset() {
    _token++;
    _autoTimer?.cancel();
    setState(() {
      _autoPlaying = false;
      _mistakeMade = false;
      _message = null;
    });
    _goTo(-1, silent: true);
  }

  /// Rakip cevabının en erken görünme süresi (motora karşı oyunla aynı).
  static const Duration _replyPace = Duration(milliseconds: 700);

  /// Siyahı çalışırken tahtanın oynadığı ilk hamle.
  static const Duration _openingPace = Duration(milliseconds: 500);

  /// "Göster": beklenen hamleyi oynar, ardından rakibin cevabını da.
  ///
  /// Eskiden yalnızca bir yarım hamle ilerletiyordu: senin hamlen
  /// oynanıyor, tahta rakibin hamlesini bekler hâlde kalıyordu. Çalıştığın
  /// tarafı sen oynadığın için ilerleyemiyor, ikinci kez basmak
  /// gerekiyordu. Rakibin cevabı doğru hamle yaptığındakiyle aynı
  /// tempoda ve aynı jetona bağlı.
  Future<void> _showNextMove() async {
    // Jeton **ilerletiliyor**: doğru hamleden sonra beklemede olan rakip
    // cevabı iptal olsun. Eskiden yalnızca okunuyordu ve "Göster"e
    // basınca iki yarım hamle üst üste geliyordu.
    final token = ++_token;
    // Hamleyi tahta oynuyor: bu hat "hatasız bitirildi" sayılmamalı,
    // yoksa "Göster" ile geçilen varyant öğrenilmiş gibi kaydediliyordu.
    _mistakeMade = true;
    _goTo(_cursor + 1);
    if (_mode != StudyMode.practice) return;
    if (_cursor >= widget.opening.uciMoves.length - 1) return;

    await Future<void>.delayed(_replyPace);
    if (!mounted || token != _token || _mode != StudyMode.practice) return;
    _goTo(_cursor + 1);
  }

  void _toggleAutoPlay() {
    if (_autoPlaying) {
      _autoTimer?.cancel();
      setState(() => _autoPlaying = false);
      return;
    }
    setState(() => _autoPlaying = true);
    _autoTimer = Timer.periodic(const Duration(milliseconds: 900), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_cursor >= widget.opening.uciMoves.length - 1) {
        timer.cancel();
        setState(() => _autoPlaying = false);
        return;
      }
      _goTo(_cursor + 1);
    });
  }

  // -------------------------------------------------------------------------
  // Alıştırma
  // -------------------------------------------------------------------------

  Future<void> _onUserMove(engine.ChessMove move) async {
    if (_mode != StudyMode.practice) return;
    final expectedIndex = _cursor + 1;
    if (expectedIndex >= widget.opening.uciMoves.length) return;

    final expected = widget.opening.uciMoves[expectedIndex];
    if (move.uci != expected) {
      SoundService.instance.playWrong();
      setState(() {
        _mistakeMade = true;
        _messageIsError = true;
        _message = t('openings.wrongMove');
      });
      await _service.registerFailure(widget.opening.id);
      return;
    }

    _goTo(expectedIndex);
    setState(() {
      _messageIsError = false;
      _message = t('openings.rightMove', {
        'move': _san(expectedIndex),
      });
    });

    // Rakip hamlesini otomatik oynat ki kullanıcı hep aynı tarafı
    // çalışsın. Tempo motora karşı oyunla aynı: hamlenin görülmesi için
    // en az bu kadar bekleniyor.
    if (_cursor < widget.opening.uciMoves.length - 1) {
      final token = _token;
      await Future<void>.delayed(_replyPace);
      if (!mounted || token != _token || _mode != StudyMode.practice) return;
      _goTo(_cursor + 1);
    }

    if (_cursor >= widget.opening.uciMoves.length - 1) {
      SoundService.instance.playNotify();
      if (!_mistakeMade) {
        await _service.registerSuccess(widget.opening.id);
      }
      final progress = await _service.progressOf(widget.opening.id);
      if (!mounted) return;
      setState(() {
        _learned = progress.learned;
        _messageIsError = false;
        _message = _mistakeMade
            ? t('openings.finishedWithMistake')
            : t('openings.finishedClean');
      });
    }
  }

  void _setMode(StudyMode mode) {
    _token++;
    _autoTimer?.cancel();
    setState(() {
      _mode = mode;
      _autoPlaying = false;
      _message = null;
      _mistakeMade = false;
    });
    _goTo(-1, silent: true);

    // Alıştırmada siyahı çalışıyorsan ilk hamleyi tahta oynasın.
    if (mode == StudyMode.practice && _flipped) {
      final token = _token;
      Future<void>.delayed(_openingPace, () {
        if (mounted && token == _token && _cursor == -1) _goTo(0);
      });
    }
  }

  // -------------------------------------------------------------------------

  /// Varyantın notunu siler.
  ///
  /// Servis boş metni "not yok" olarak ele alır; ayrı bir silme yolu
  /// tutmaya gerek yok.
  Future<void> _deleteNote(Opening opening) async {
    await _service.setNote(opening.id, '');
    if (!mounted) return;
    // Not ekrandan zaten kalkıyor; ayrıca "not silindi" demek
    // kullanıcının gördüğü şeyi tekrar etmek olurdu.
    setState(() => opening.note = null);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final opening = widget.opening;

    // İpucu oku kaldırıldı: "Göster" zaten sıradaki hamleyi oynuyor ve
    // bu ekranda hiçbir şeyi bitirmiyor, yani ikisi neredeyse aynı işi
    // yapıyordu. (Bulmacada durum farklı: orada "Çözüm" bulmacayı
    // bitirdiği için ipucu ayrı bir işe yarıyor.)
    final arrows = <BoardArrow>[];

    // Alıştırmada kullanıcı yalnızca sırası gelen tarafı oynar.
    final practiceSide = _flipped ? engine.Color.black : engine.Color.white;

    return Scaffold(
      appBar: AppBar(
        title: Text(opening.variation),
        actions: [
          IconButton(
            tooltip: _favorite
                ? t('common.favoriteRemove')
                : t('common.favoriteAdd'),
            icon: Icon(
              _favorite ? Icons.star_rounded : Icons.star_border_rounded,
              color: _favorite ? scheme.warning : null,
            ),
            onPressed: () async {
              final value = await _service.toggleFavorite(opening.id);
              if (mounted) setState(() => _favorite = value);
            },
          ),
          IconButton(
            tooltip: t('common.flipBoard'),
            icon: const Icon(Icons.swap_vert_rounded),
            onPressed: () {
              setState(() => _flipped = !_flipped);
              // Alıştırmada çevirmek yalnızca bakışı değil, **hangi
              // tarafı çalıştığını** da değiştiriyor. Hat ortasındayken
              // sıra karşı tarafa geçtiği için tahta kilitleniyor ve tek
              // çıkış tekrar çevirmek ya da baştan başlamak oluyordu.
              // Taraf değişince alıştırma yeniden kuruluyor.
              if (_mode == StudyMode.practice) _setMode(StudyMode.practice);
            },
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              switch (value) {
                case 'png':
                  _saveBoardImage();
                  break;
                case 'note':
                  final note = await AppDialogs.prompt(
                    context,
                    title: t('common.note'),
                    label: t('openings.noteLabel'),
                    initialValue: opening.note ?? '',
                    maxLines: 4,
                  );
                  if (note == null) return;
                  await _service.setNote(opening.id, note);
                  if (mounted) setState(() => opening.note = note);
                  break;
                case 'deleteNote':
                  await _deleteNote(opening);
                  break;
                case 'learned':
                  await _service.markLearned(opening.id, learned: !_learned);
                  if (mounted) setState(() => _learned = !_learned);
                  break;
                case 'play':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GameScreen(
                        mode: GameMode.versusEngine,
                        startFen: _game.fen,
                        playerColor: _game.sideToMove,
                        title: t('openings.continueVsEngine'),
                      ),
                    ),
                  );
                  break;
                case 'analyze':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GameScreen(
                        startFen: _game.fen,
                        title: opening.variation,
                      ),
                    ),
                  );
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'png', child: Text(t('board.savePng'))),
              PopupMenuItem(value: 'note', child: Text(t('common.addNote'))),
              if (opening.note != null && opening.note!.isNotEmpty)
                PopupMenuItem(
                  value: 'deleteNote',
                  child: Text(t('common.deleteNote')),
                ),
              PopupMenuItem(
                value: 'learned',
                child: Text(
                  _learned
                      ? t('openings.markNotLearned')
                      : t('openings.markLearned'),
                ),
              ),
              PopupMenuItem(
                value: 'play',
                child: Text(t('common.playFromHere')),
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
            ? _wideBody(scheme, opening, practiceSide, arrows)
            : ContentWidth(
                child: _narrowBody(scheme, opening, practiceSide, arrows),
              ),
      ),
    );
  }

  /// Tahtanın üstünde duran başlık ve tahtanın kendi dikey boşluğu.
  static const double _wideChromeHeight = 48;

  /// Tahtanın yatay boşluğu ([_boardArea] içindeki dolgu), iki yan.
  static const double _boardGutter = 20;

  /// Tahta; kalan alana sığan en büyük kare, üst sınır [cap].
  Widget _boardArea(
    engine.Color? practiceSide,
    List<BoardArrow> arrows,
    double cap,
  ) {
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
              return SizedBox(
                width: side,
                height: side,
                child: RepaintBoundary(
                  key: _boardImageKey,
                  child: ChessBoardWidget(
                    game: _game,
                    flipped: _flipped,
                    interactive: _mode == StudyMode.practice,
                    movableSide: practiceSide,
                    lastMove: _currentMove,
                    onMove: _onUserMove,
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
  Widget _narrowBody(
    ColorScheme scheme,
    Opening opening,
    engine.Color? practiceSide,
    List<BoardArrow> arrows,
  ) {
    return Column(
      children: [
        _header(scheme),
        _boardArea(practiceSide, arrows, Layout.narrowBoardCap),
        if (opening.note != null && opening.note!.isNotEmpty)
          _noteCard(scheme, opening.note!),
        if (_message != null) _messageCard(scheme),
        _moveStrip(scheme, vertical: false),
        _controls(scheme),
      ],
    );
  }

  /// Geniş pencere ve tablet: solda tahta, sağda hamleler ve düğmeler.
  ///
  /// Oyun ve bulmaca ekranlarıyla aynı geometri. Eskiden bu ekran geniş
  /// pencerede de telefon düzenindeydi: tahta 520'de kalıyordu.
  Widget _wideBody(
    ColorScheme scheme,
    Opening opening,
    engine.Color? practiceSide,
    List<BoardArrow> arrows,
  ) {
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
                      _boardArea(practiceSide, arrows, side),
                    ],
                  ),
                ),
                SizedBox(width: gap),
                SizedBox(
                  width: Layout.sidePanelWidth,
                  child: _sidePanel(scheme, opening),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Sağ sütun: not, uyarı, hamle listesi ve düğmeler.
  Widget _sidePanel(ColorScheme scheme, Opening opening) {
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 8, 12, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          if (opening.note != null && opening.note!.isNotEmpty)
            _noteCard(scheme, opening.note!),
          if (_message != null) _messageCard(scheme),
          Divider(height: 1, color: scheme.outlineVariant),
          Expanded(child: _moveStrip(scheme, vertical: true)),
          Divider(height: 1, color: scheme.outlineVariant),
          _controls(scheme, panel: true),
        ],
      ),
    );
  }

  Widget _header(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              widget.opening.eco,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.opening.family,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          if (_learned)
            Icon(Icons.check_circle_rounded, size: 16, color: scheme.success),
        ],
      ),
    );
  }

  Widget _noteCard(ColorScheme scheme, String note) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        note,
        style: TextStyle(fontSize: 12.5, color: scheme.onSecondaryContainer),
      ),
    );
  }

  Widget _messageCard(ColorScheme scheme) {
    final color = _messageIsError ? scheme.wrong : scheme.correct;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            _messageIsError
                ? Icons.error_outline_rounded
                : Icons.check_circle_outline_rounded,
            size: 17,
            color: color,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              _message!,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _moveStrip(ColorScheme scheme, {required bool vertical}) {
    // Uygulamanın her yerindeki hamle listesiyle aynı widget: aynı
    // hizalama, aynı yazı stili, aynı numara biçimi. Bu ekran eskiden
    // kendi şeridini çiziyordu ve hamleler sola yaslı, numaralar farklı
    // puntoda kalıyordu.
    final list = MoveList(
      moves: _entries,
      currentIndex: _cursor,
      // Hamleye dokunup o konuma gitmek yalnızca izleme kipinde anlamlı.
      onMoveTap: _mode == StudyMode.watch ? _goTo : (_) {},
      vertical: vertical,
      // Alıştırmada henüz gelmemiş hamleler gizleniyor.
      revealedCount:
          _mode == StudyMode.practice ? _cursor + 1 : _entries.length,
    );
    if (vertical) return list;
    return Container(
      height: 46,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: list,
    );
  }

  Widget _controls(ColorScheme scheme, {bool panel = false}) {
    final atEnd = _cursor >= widget.opening.uciMoves.length - 1;

    // Yan panelde kendi kartı yok.
    //
    // Panelin zaten bir yüzeyi var; içine ikinci bir kart koymak kenar
    // boşluğu yüzünden bloğu panelin ayraçlarıyla hizasız bırakıyor ve
    // üst payı (8) alt paydan (12) ince olduğu için aşağı itiyordu.
    final content = Column(
      children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SegmentedButton<StudyMode>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: StudyMode.watch,
                  label: Text(t('openings.watch')),
                  icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
                ),
                ButtonSegment(
                  value: StudyMode.practice,
                  label: Text(t('openings.practice')),
                  icon: const Icon(Icons.school_outlined, size: 18),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (selection) => _setMode(selection.first),
            ),
          ),
          const SizedBox(height: 4),
          if (_mode == StudyMode.watch)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: const Icon(Icons.first_page_rounded),
                  onPressed: _cursor >= 0 ? () => _goTo(-1) : null,
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded),
                  iconSize: 28,
                  onPressed: _cursor >= 0 ? () => _goTo(_cursor - 1) : null,
                ),
                IconButton(
                  icon: Icon(
                    _autoPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                  iconSize: 30,
                  onPressed: atEnd ? null : _toggleAutoPlay,
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded),
                  iconSize: 28,
                  onPressed: atEnd ? null : () => _goTo(_cursor + 1),
                ),
                IconButton(
                  icon: const Icon(Icons.last_page_rounded),
                  onPressed: atEnd
                      ? null
                      : () => _goTo(widget.opening.uciMoves.length - 1),
                ),
              ],
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton.icon(
                  onPressed: _reset,
                  icon: const Icon(Icons.refresh_rounded, size: 19),
                  label: Text(t('common.restart')),
                ),
                TextButton.icon(
                  onPressed: atEnd ? null : _showNextMove,
                  icon: const Icon(Icons.skip_next_rounded, size: 19),
                  label: Text(t('openings.show')),
                ),
              ],
            ),
      ],
    );

    if (panel) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: content,
      );
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: content,
    );
  }
}