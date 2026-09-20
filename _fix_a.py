from pathlib import Path
import re

root = Path('.')

# ========== game_screen: RepaintBoundary, save, fixed engine strip ==========
p = root/'lib/screens/game_screen.dart'
t = p.read_text(encoding='utf-8')

if "import '../services/board_image_service.dart';" not in t:
    t = t.replace(
        "import '../services/engine/engine_service.dart';\n",
        "import '../services/board_image_service.dart';\n"
        "import '../services/engine/engine_service.dart';\n",
    )

# Add GlobalKey field near other fields
if '_boardImageKey' not in t:
    t = t.replace(
        '  bool _analysisOn = false;\n',
        '  bool _analysisOn = false;\n'
        '  final GlobalKey _boardImageKey = GlobalKey();\n',
    )

# Wrap board in RepaintBoundary
if 'key: _boardImageKey' not in t:
    t = t.replace(
        '''                        return SizedBox(
                          width: side,
                          height: side,
                          child: ChessBoardWidget(''',
        '''                        return RepaintBoundary(
                          key: _boardImageKey,
                          child: SizedBox(
                          width: side,
                          height: side,
                          child: ChessBoardWidget(''',
    )
    # close extra paren after ChessBoardWidget sizedbox
    # Find the closing of SizedBox after arrows
    old_close = '''                                arrows: arrows,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              _playerRow(scheme, top: false),'''
    new_close = '''                                arrows: arrows,
                          ),
                        ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              _playerRow(scheme, top: false),'''
    if old_close in t:
        t = t.replace(old_close, new_close, 1)
        print('repaint wrap ok')
    else:
        print('WARN close not found for repaint')

# Fixed height engine strip - no board jump
t = t.replace(
    '              if (_analysisOn) _engineLine(scheme),\n',
    '              // Motor şeridi için sabit yükseklik: aç/kapa tahtayı kaydırmaz.\n'
    '              SizedBox(\n'
    '                height: 44,\n'
    '                child: _analysisOn ? _engineLine(scheme) : null,\n'
    '              ),\n',
)

# Menu item png
if "case 'png':" not in t:
    t = t.replace(
        "                case 'fen':\n"
        "                  _copyFen();\n"
        "                  break;\n",
        "                case 'fen':\n"
        "                  _copyFen();\n"
        "                  break;\n"
        "                case 'png':\n"
        "                  _saveBoardImage();\n"
        "                  break;\n",
    )
    t = t.replace(
        '''              PopupMenuItem(
                value: 'fen',
                child: ListTile(
                  leading: const Icon(Icons.copy_rounded),
                  title: Text(t('common.copyFen')),
                ),
              ),
              PopupMenuItem(
                value: 'paste',''',
        '''              PopupMenuItem(
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
                value: 'paste',''',
    )

# save method before _engineLine
if '_saveBoardImage' not in t:
    method = '''
  Future<void> _saveBoardImage() async {
    final result = await BoardImageService.saveBoardPng(
      _boardImageKey,
      fileName: 'chess-library-board.png',
    );
    if (!mounted) return;
    AppDialogs.snack(context, t('board.saveResult.$result'));
  }

'''
    t = t.replace('  Widget _engineLine(ColorScheme scheme) {', method + '  Widget _engineLine(ColorScheme scheme) {')

# engine line: don't return shrink with zero height when in fixed box - return empty sized box filling parent
# Actually when analysis null and analysisOn, return empty - SizedBox height 44 already reserved. OK if shrink inside.

p.write_text(t, encoding='utf-8', newline='\n')
print('game_screen save+strip done')

# ========== opening study + game review: add save similarly (lighter) ==========
for rel, insert_after_fen in [
    ('lib/screens/openings/opening_study_screen.dart', True),
    ('lib/screens/game_review_screen.dart', True),
]:
    p = root/rel
    if not p.exists():
        print('skip', rel)
        continue
    t = p.read_text(encoding='utf-8')
    if 'board.savePng' in t or "value: 'png'" in t:
        print('already png', rel)
        continue
    # Only add menu if PopupMenu exists and board widget exists - complex; try game_review actions
    print('TODO manual', rel, 'PopupMenu' in t, 'ChessBoardWidget' in t)

p.write_text  # noop
print('batch A done')
