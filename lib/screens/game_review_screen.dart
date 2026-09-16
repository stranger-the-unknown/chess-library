import 'package:flutter/material.dart';

import '../widgets/responsive.dart';

import '../l10n/app_strings.dart';
import '../models/chess_engine.dart' as engine;
import '../models/move_entry.dart';
import '../models/stored_review.dart';
import '../services/analysis_queue.dart';
import '../services/game_review.dart';
import '../services/sound_service.dart';
import '../theme/app_theme.dart';
import '../widgets/chess_board_widget.dart';
import '../widgets/cursors.dart';

/// Biten bir oyunu cihazdaki motorla inceler ve sonuçları gösterir.
class GameReviewScreen extends StatefulWidget {
  final List<MoveEntry> history;
  final String? startFen;
  final String title;

  /// Daha önce yapılmış ve kaydedilmiş analiz.
  ///
  /// Varsa motor hiç çalıştırılmıyor; kullanıcı analiz listesindeki bir
  /// kaydı açtığında beklemesin diye. Kayıt oyunun hamleleriyle
  /// uyuşmuyorsa yeniden analiz edilir.
  final StoredReview? saved;

  const GameReviewScreen({
    super.key,
    required this.history,
    this.startFen,
    this.title = '',
    this.saved,
  });

  @override
  State<GameReviewScreen> createState() => _GameReviewScreenState();
}

class _GameReviewScreenState extends State<GameReviewScreen> {
  GameReview? _review;
  int _done = 0;
  int _total = 0;
  bool _deep = false;
  bool _running = false;

  /// Kullanıcı kayıtlı analizi görmezden gelip yeniden analiz
  /// istedi mi?
  bool _reanalysed = false;
  bool _flipped = false;
  int _cursor = 0;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final saved = widget.saved;
    if (saved != null && !_reanalysed) {
      final restored = fromStoredReview(
        saved,
        widget.history,
        startFen: widget.startFen,
      );
      if (restored != null) {
        setState(() {
          _review = restored;
          _running = false;
          _deep = saved.deep;
        });
        return;
      }
    }

    setState(() {
      _running = true;
      _review = null;
      _done = 0;
      _total = widget.history.length + 1;
    });

    final review = await GameReviewer().review(
      widget.history,
      startFen: widget.startFen,
      deep: _deep,
      onProgress: (done, total) {
        if (!mounted) return;
        setState(() {
          _done = done;
          _total = total;
        });
      },
    );

    if (!mounted) return;
    setState(() {
      _review = review;
      _running = false;
      _cursor = 0;
    });
  }

  /// İmleci taşır ve o hamlenin sesini çalar.
  ///
  /// İncelemede de tahtadaki hamleler duyulsun diye ses, oyun ekranındaki
  /// ile aynı kurallara göre (alma / rok / şah / mat) seçilir.
  void _goToMove(int index, {bool silent = false}) {
    final review = _review;
    if (review == null || review.moves.isEmpty) return;

    final target = index.clamp(0, review.moves.length - 1);
    final forward = target > _cursor;
    setState(() => _cursor = target);

    // Yalnızca ileri giderken ses çalar; geri sarmak sessizdir.
    if (!silent && forward) {
      final move = review.moves[target];
      SoundService.instance.playForSan(
        move.entry.san,
        opponent: move.mover == engine.Color.black,
      );
    }
  }

  /// [_cursor] hamlesinden sonraki pozisyon.
  engine.ChessGame _positionAt(int index) {
    final position = engine.ChessGame.fromFen(
      widget.startFen ?? engine.ChessGame().fen,
    );
    for (int i = 0; i <= index && i < widget.history.length; i++) {
      position.makeMove(widget.history[i].move);
    }
    return position;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final review = _review;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title.isEmpty ? t('review.title') : widget.title),
        actions: [
          IconButton(
            tooltip: t('common.flipBoard'),
            icon: const Icon(Icons.swap_vert_rounded),
            onPressed: () => setState(() => _flipped = !_flipped),
          ),
          if (!_running)
            IconButton(
              tooltip: _deep ? t('review.quick') : t('review.deep'),
              icon: Icon(
                _deep ? Icons.flash_on_rounded : Icons.travel_explore_rounded,
              ),
              onPressed: () {
                // Kullanıcı derinliği değiştirdiyse kayıtlı analiz artık
                // istediği şey değil; motor yeniden çalışır.
                setState(() {
                  _deep = !_deep;
                  _reanalysed = true;
                });
                _run();
              },
            ),
        ],
      ),
      body: review == null
          ? ContentWidth(child: _progressView(scheme))
          : _resultView(review, scheme),
    );
  }

  Widget _progressView(ColorScheme scheme) {
    final ratio = _total == 0 ? 0.0 : _done / _total;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.memory_rounded, size: 42, color: scheme.primary),
            const SizedBox(height: 18),
            Text(
              _deep ? t('review.runningDeep') : t('review.running'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              t('review.offlineNote'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 22),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: ratio, minHeight: 8),
            ),
            const SizedBox(height: 10),
            Text(
              t('review.progress', {'done': _done, 'total': _total}),
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultView(GameReview review, ColorScheme scheme) {
    if (review.moves.isEmpty) {
      return Center(
        child: Text(
          t('game.nothingToReview'),
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }

    final current = review.moves[_cursor.clamp(0, review.moves.length - 1)];

    return ContentInset(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      builder: (context, padding) => ListView(
        padding: padding,
        children: [
          _accuracyCard(review, scheme),
          const SizedBox(height: 14),
          _chartCard(review, scheme),
          const SizedBox(height: 14),
          _moveCard(current, scheme),
          const SizedBox(height: 14),
          _breakdownCard(review, scheme),
          if (review.turningPoints.isNotEmpty) ...[
            const SizedBox(height: 14),
            _turningPointsCard(review, scheme),
          ],
        ],
      ),
    );
  }

  Widget _card(Widget child, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: child,
    );
  }

  Widget _accuracyCard(GameReview review, ColorScheme scheme) {
    Widget side(String label, double value, Color color) {
      return Expanded(
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Text(
              value.toStringAsFixed(1),
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            Text(
              t('review.accuracy'),
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return _card(
      Row(
        children: [
          side(t('common.white'), review.whiteAccuracy, scheme.onSurface),
          Container(width: 1, height: 46, color: scheme.outlineVariant),
          side(
            t('common.black'),
            review.blackAccuracy,
            scheme.onSurfaceVariant,
          ),
        ],
      ),
      scheme,
    );
  }

  Widget _chartCard(GameReview review, ColorScheme scheme) {
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t('review.evalFlow'),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 110,
            child: LayoutBuilder(
              builder: (context, constraints) => MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTapDown: (details) {
                    final ratio =
                        details.localPosition.dx / constraints.maxWidth;
                    final index = (ratio * review.moves.length).floor().clamp(
                          0,
                          review.moves.length - 1,
                        );
                    _goToMove(index);
                  },
                  child: CustomPaint(
                    size: Size(constraints.maxWidth, 110),
                    painter: _EvalChartPainter(
                      scores: review.moves.map((m) => m.whiteScoreCp).toList(),
                      cursor: _cursor,
                      lineColor: scheme.primary,
                      gridColor: scheme.outlineVariant,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            t('review.chartHint'),
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
      scheme,
    );
  }

  Widget _moveCard(ReviewedMove move, ColorScheme scheme) {
    final position = _positionAt(move.index);
    final color = _qualityColor(move.quality, scheme);
    final beforePosition = engine.ChessGame.fromFen(
      widget.startFen ?? engine.ChessGame().fen,
    );
    for (int i = 0; i < move.index; i++) {
      beforePosition.makeMove(widget.history[i].move);
    }
    final bestMove = beforePosition.moveFromUci(move.bestMoveUci);

    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _qualityLabel(move.quality),
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${(move.index ~/ 2) + 1}'
                '${move.mover == engine.Color.white ? "." : "..."} '
                '${move.entry.san}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                (move.playedScoreCp / 100).toStringAsFixed(2),
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: SizedBox(
              width: Layout.maxBoardSide,
              child: ChessBoardWidget(
                game: position,
                flipped: _flipped,
                interactive: false,
                lastMove: move.entry.move,
                arrows: [
                  if (bestMove != null && !move.playedBest)
                    BoardArrow(
                      bestMove.from,
                      bestMove.to,
                      scheme.success.withValues(alpha: 0.8),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (!move.playedBest)
            Text(
              t('review.engineSuggests', {
                'move': move.bestMoveSan,
                'loss': (move.lossCp / 100).toStringAsFixed(2),
              }),
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            )
          else
            Text(
              t('review.playedBest'),
              style: TextStyle(fontSize: 12.5, color: scheme.success),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: _cursor > 0 ? () => _goToMove(_cursor - 1) : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                  label: Text(t('common.previous')),
                ),
              ),
              Text(
                '${move.index + 1} / ${widget.history.length}',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              Expanded(
                child: TextButton.icon(
                  onPressed: _cursor < widget.history.length - 1
                      ? () => _goToMove(_cursor + 1)
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
      scheme,
    );
  }

  Widget _breakdownCard(GameReview review, ColorScheme scheme) {
    Widget row(MoveQuality quality) {
      final white = review.countFor(engine.Color.white, quality);
      final black = review.countFor(engine.Color.black, quality);
      if (white == 0 && black == 0) return const SizedBox.shrink();
      final color = _qualityColor(quality, scheme);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '$white',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _qualityLabel(quality),
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 28,
              child: Text(
                '$black',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
    }

    return _card(
      Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 28,
                child: Text(
                  t('common.whiteShort'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: 28,
                child: Text(
                  t('common.blackShort'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final quality in MoveQuality.values) row(quality),
        ],
      ),
      scheme,
    );
  }

  Widget _turningPointsCard(GameReview review, ColorScheme scheme) {
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t('review.turningPoints'),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          for (final move in review.turningPoints)
            InkWell(
              mouseCursor: kClickable,
              borderRadius: BorderRadius.circular(8),
              onTap: () => _goToMove(move.index),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _qualityColor(move.quality, scheme),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${(move.index ~/ 2) + 1}'
                      '${move.mover == engine.Color.white ? "." : "..."} '
                      '${move.entry.san}',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        t('review.insteadOf', {'move': move.bestMoveSan}),
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Text(
                      '-${(move.lossCp / 100).toStringAsFixed(1)}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: scheme.error,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      scheme,
    );
  }

  static String _qualityLabel(MoveQuality quality) =>
      t('quality.${quality.key}');

  static Color _qualityColor(MoveQuality quality, ColorScheme scheme) =>
      switch (quality) {
        MoveQuality.best => scheme.success,
        MoveQuality.excellent => scheme.success,
        MoveQuality.good => scheme.primary,
        MoveQuality.inaccuracy => scheme.warning,
        MoveQuality.mistake => const Color(0xFFE07A3A),
        MoveQuality.blunder => scheme.error,
        MoveQuality.forced => scheme.onSurfaceVariant,
      };
}

/// Değerlendirme akışını çizen basit alan grafiği.
class _EvalChartPainter extends CustomPainter {
  final List<int> scores;
  final int cursor;
  final Color lineColor;
  final Color gridColor;

  _EvalChartPainter({
    required this.scores,
    required this.cursor,
    required this.lineColor,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (scores.isEmpty) return;

    const maxCp = 800.0;
    double yFor(int cp) {
      final clamped = cp.clamp(-maxCp.toInt(), maxCp.toInt()) / maxCp;
      return size.height / 2 - clamped * (size.height / 2 - 2);
    }

    double xFor(int index) =>
        scores.length == 1 ? 0 : index * size.width / (scores.length - 1);

    // Orta çizgi
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      Paint()
        ..color = gridColor
        ..strokeWidth = 1,
    );

    final path = Path()..moveTo(xFor(0), yFor(scores.first));
    for (int i = 1; i < scores.length; i++) {
      path.lineTo(xFor(i), yFor(scores[i]));
    }

    // Beyaz üstünlüğü alanı
    final fill = Path.from(path)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(0, size.height / 2)
      ..close();
    canvas.drawPath(fill, Paint()..color = lineColor.withValues(alpha: 0.20));

    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );

    // İmleç
    if (cursor >= 0 && cursor < scores.length) {
      final x = xFor(cursor);
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = lineColor.withValues(alpha: 0.6)
          ..strokeWidth = 1.5,
      );
      canvas.drawCircle(
        Offset(x, yFor(scores[cursor])),
        4,
        Paint()..color = lineColor,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EvalChartPainter old) =>
      old.cursor != cursor || old.scores != scores;
}
