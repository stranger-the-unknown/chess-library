import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../models/chess_engine.dart' as engine;
import '../services/settings_service.dart';
import '../widgets/board_background.dart';
import '../widgets/cursors.dart';
import '../widgets/piece_widget.dart';
import '../widgets/responsive.dart';

/// Hangi karenin rengi seçiliyor?
enum _Target { light, dark }

/// Tahtanın açık ve koyu kare rengini seçtiren ekran.
///
/// Hazır tahta yoktur: kullanıcı iki rengi de kendisi seçer, tahta da o
/// iki renkten çizilir. Üstteki önizleme gerçek tahtanın aynısıdır —
/// kare adları ve taşlar dâhil — çünkü iki renk birbirine çok yakın
/// seçildiğinde bunu ancak orada görmek mümkün.
class BoardColorsScreen extends StatefulWidget {
  const BoardColorsScreen({super.key});

  @override
  State<BoardColorsScreen> createState() => _BoardColorsScreenState();
}

class _BoardColorsScreenState extends State<BoardColorsScreen> {
  final SettingsService _settings = SettingsService.instance;
  _Target _target = _Target.light;

  void _pick(int color) {
    setState(() {
      if (_target == _Target.light) {
        _settings.boardLight = color;
      } else {
        _settings.boardDark = color;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(t('board.colorsTitle')),
        actions: [
          TextButton(
            onPressed: () => setState(_settings.resetBoardColors),
            child: Text(t('common.reset')),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _settings,
        builder: (context, _) => ContentWidth(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              const _BoardPreview(),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.forest_outlined),
                title: Text(t('board.wood')),
                subtitle: Text(t('board.woodSub')),
                value: _settings.boardWood,
                onChanged: (value) => _settings.boardWood = value,
              ),
              const SizedBox(height: 8),
              SegmentedButton<_Target>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: _Target.light,
                    label: Text(t('board.lightSquare')),
                    icon: _dot(_settings.boardLight, scheme),
                  ),
                  ButtonSegment(
                    value: _Target.dark,
                    label: Text(t('board.darkSquare')),
                    icon: _dot(_settings.boardDark, scheme),
                  ),
                ],
                selected: {_target},
                onSelectionChanged: (value) =>
                    setState(() => _target = value.first),
              ),
              const SizedBox(height: 14),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 10,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                ),
                itemCount: BoardAssets.palette.length,
                itemBuilder: (context, index) {
                  final color = BoardAssets.palette[index];
                  final selected = color ==
                      (_target == _Target.light
                          ? _settings.boardLight
                          : _settings.boardDark);
                  return _Swatch(
                    color: color,
                    selected: selected,
                    onTap: () => _pick(color),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dot(int color, ColorScheme scheme) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: Color(color),
        shape: BoxShape.circle,
        border: Border.all(color: scheme.outlineVariant),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  final int color;
  final bool selected;
  final VoidCallback onTap;

  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      mouseCursor: kClickable,
      borderRadius: BorderRadius.circular(7),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Color(color),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 3 : 1,
          ),
        ),
        child: selected
            ? Center(
                child: Icon(
                  Icons.check_rounded,
                  size: 15,
                  // Onay işareti seçilen rengin üstünde durur; hangisinin
                  // okunacağı rengin kendi parlaklığına bağlı.
                  color: Color(
                    BoardAssets.coordinateColor(
                      light: color,
                      dark: color,
                      onLightSquare: true,
                    ),
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

/// Seçilen renklerle gerçek tahtanın küçültülmüş hâli.
class _BoardPreview extends StatelessWidget {
  const _BoardPreview();

  /// İtalyan açılışından tanıdık bir kuruluş; her iki rengin üstünde de
  /// açık ve koyu taş bulunsun diye seçildi.
  static const String _fen =
      'r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R';

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService.instance;
    final board = engine.ChessGame.fromFen('$_fen w KQkq - 0 1');

    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest.shortestSide;
          final square = size / 8;
          const files = 'abcdefgh';

          TextStyle styleFor(bool onLightSquare) => TextStyle(
                fontSize: square * 0.20,
                fontWeight: FontWeight.w700,
                color: Color(
                  BoardAssets.coordinateColor(
                    light: settings.boardLight,
                    dark: settings.boardDark,
                    onLightSquare: onLightSquare,
                  ),
                ),
              );

          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              children: [
                const Positioned.fill(child: BoardBackground()),
                for (int i = 0; i < 64; i++)
                  if (board.board[i] != null)
                    Positioned(
                      left: (i % 8) * square,
                      top: (i ~/ 8) * square,
                      width: square,
                      height: square,
                      child: PieceWidget(piece: board.board[i]!, size: square),
                    ),
                // Kare adları: gerçek tahtadaki yerleşimin aynısı.
                for (int i = 0; i < 8; i++) ...[
                  Positioned(
                    left: i * square + square * 0.06,
                    top: 7 * square + square * 0.72,
                    child: Text(files[i], style: styleFor((i + 7).isEven)),
                  ),
                  Positioned(
                    left: 7 * square + square * 0.80,
                    top: i * square + square * 0.05,
                    child: Text('${8 - i}', style: styleFor((7 + i).isEven)),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
