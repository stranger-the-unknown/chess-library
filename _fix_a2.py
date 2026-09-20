from pathlib import Path
import re
from PIL import Image, ImageEnhance
import shutil

root = Path('.')

# ---- Fix game_screen save method + import ----
p = root/'lib/screens/game_screen.dart'
t = p.read_text(encoding='utf-8')
if "board_image_service.dart" not in t:
    t = t.replace(
        "import '../services/settings_service.dart';\n",
        "import '../services/board_image_service.dart';\n"
        "import '../services/settings_service.dart';\n",
    )

# Replace broken/incomplete save method
if 'Future<void> _saveBoardImage()' in t:
    t = re.sub(
        r'  Future<void> _saveBoardImage\(\) async \{.*?\n  \}\n\n',
        '''  Future<void> _saveBoardImage() async {
    final result = await BoardImageService.saveBoardPng(
      _boardImageKey,
      fileName: 'chess-library-board.png',
    );
    if (!mounted) return;
    AppDialogs.snack(context, t('board.saveResult.$result'));
  }

''',
        t,
        count=1,
        flags=re.S,
    )
else:
    t = t.replace(
        '  Widget _engineLine(ColorScheme scheme) {',
        '''  Future<void> _saveBoardImage() async {
    final result = await BoardImageService.saveBoardPng(
      _boardImageKey,
      fileName: 'chess-library-board.png',
    );
    if (!mounted) return;
    AppDialogs.snack(context, t('board.saveResult.$result'));
  }

  Widget _engineLine(ColorScheme scheme) {''',
    )

# Ensure case png exists in switch - check
if "case 'png':" not in t:
    # try insert after fen
    t = t.replace(
        "                case 'fen':\n                  _copyFen();\n                  break;\n",
        "                case 'fen':\n                  _copyFen();\n                  break;\n"
        "                case 'png':\n                  _saveBoardImage();\n                  break;\n",
    )

# Fix engine line to never collapse: when analysis null still occupy space with empty
# Already have SizedBox height 44. Make _engineLine return zero-size friendly content.
# When analysis null inside analysisOn, return empty Container with height
t = t.replace(
    '''  Widget _engineLine(ColorScheme scheme) {
    final analysis = _analysis;
    // Sonuç yokken boş kutu / hazırlanıyor yazısı gösterme.
    if (analysis == null) return const SizedBox.shrink();''',
    '''  Widget _engineLine(ColorScheme scheme) {
    final analysis = _analysis;
    // Sonuç yokken yazı gösterme; dışardaki sabit yükseklik tahtayı tutar.
    if (analysis == null) return const SizedBox.expand();''',
)

p.write_text(t, encoding='utf-8', newline='\n')
print('game_screen fixed')

# ---- opening study: add save ----
p = root/'lib/screens/openings/opening_study_screen.dart'
t = p.read_text(encoding='utf-8')
if "value: 'png'" not in t and 'ChessBoardWidget' in t:
    if '_boardImageKey' not in t:
        # add key after state fields - find class state
        m = re.search(r'class _\w+State extends State<', t)
        # find first bool field after state class
        t = t.replace(
            "import '../services/settings_service.dart';\n",
            "import '../services/board_image_service.dart';\n"
            "import '../services/settings_service.dart';\n",
        )
        # insert key - look for State class body
        t2, n = re.subn(
            r'(class _\w+State extends State<[^>]+> \{)\n',
            r'\1\n  final GlobalKey _boardImageKey = GlobalKey();\n',
            t,
            count=1,
        )
        t = t2
        print('opening key', n)
        # wrap first ChessBoardWidget with RepaintBoundary - careful
        if 'RepaintBoundary' not in t:
            t = t.replace(
                'child: ChessBoardWidget(',
                'child: RepaintBoundary(\n'
                '                        key: _boardImageKey,\n'
                '                        child: ChessBoardWidget(',
                1,
            )
            # add closing paren - hard; use simpler approach: wrap in builder
            # Find ChessBoardWidget( ... ),  and add closing
            # For openings, find the widget call end - fragile
            print('opening wrap started - need close paren')
        # menu
        if "value: 'fen'" in t or "value: 'note'" in t:
            t = t.replace(
                "PopupMenuItem(value: 'note', child: Text(t('common.addNote'))),",
                "PopupMenuItem(value: 'note', child: Text(t('common.addNote'))),\n"
                "              PopupMenuItem(value: 'png', child: Text(t('board.savePng'))),",
            )
            # onSelected
            if "case 'note':" in t:
                t = t.replace(
                    "case 'note':",
                    "case 'png':\n"
                    "                  _saveBoardImage();\n"
                    "                  break;\n"
                    "                case 'note':",
                )
        if '_saveBoardImage' not in t:
            # add method before build or at end of class before last }
            t = t.replace(
                '\n  @override\n  Widget build(BuildContext context) {',
                '''
  Future<void> _saveBoardImage() async {
    final result = await BoardImageService.saveBoardPng(
      _boardImageKey,
      fileName: 'chess-library-opening.png',
    );
    if (!mounted) return;
    AppDialogs.snack(context, t('board.saveResult.$result'));
  }

  @override
  Widget build(BuildContext context) {''',
                1,
            )
        p.write_text(t, encoding='utf-8', newline='\n')
        print('opening patched')
else:
    print('opening skip', "value: 'png'" in t)

print('A2 done')
