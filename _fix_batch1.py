# -*- coding: utf-8 -*-
"""Apply UX fixes: save image everywhere, 2x puzzle, no board jump, accent picker, icons."""
from pathlib import Path
import re, json, shutil
from PIL import Image, ImageEnhance, ImageFilter

root = Path(r'D:\chess_app\chess_library_free')

# ---------- 1) Puzzle delay 630 -> 840 (2x of original 420) ----------
p = root/'lib/screens/puzzles/puzzle_solve_screen.dart'
t = p.read_text(encoding='utf-8')
t = t.replace('Duration(milliseconds: 630)', 'Duration(milliseconds: 840)')
t = t.replace('Duration(milliseconds: 420)', 'Duration(milliseconds: 840)')
p.write_text(t, encoding='utf-8', newline='\n')
print('puzzle 840ms')

# ---------- 2) Settings: board accent overrides ----------
p = root/'lib/services/settings_service.dart'
t = p.read_text(encoding='utf-8')
if '_boardAccentColors' not in t:
    t = t.replace(
        '  bool _showEngineArrows = true;\n',
        '  bool _showEngineArrows = true;\n'
        '  /// Tahta teması -> seçim/ok rengi (0xAARRGGBB).\n'
        '  final Map<String, int> _boardAccentColors = {};\n',
    )
    # load
    t = t.replace(
        "    _showEngineArrows = prefs.getBool('showEngineArrows') ?? true;\n",
        "    _showEngineArrows = prefs.getBool('showEngineArrows') ?? true;\n"
        "    final accentJson = prefs.getString('boardAccentColors');\n"
        "    if (accentJson != null) {\n"
        "      try {\n"
        "        final map = jsonDecode(accentJson) as Map<String, dynamic>;\n"
        "        _boardAccentColors\n"
        "          ..clear()\n"
        "          ..addAll({\n"
        "            for (final e in map.entries) e.key: (e.value as num).toInt(),\n"
        "          });\n"
        "      } catch (_) {}\n"
        "    }\n",
    )
    # ensure dart:convert import
    if "import 'dart:convert';" not in t:
        t = "import 'dart:convert';\n" + t
    # methods before class BoardAssets or after showEngineArrows setter
    method = '''
  /// Bu tahta için seçim/ok rengi (kullanıcı seçimi veya varsayılan).
  int accentColorFor(String board) =>
      _boardAccentColors[board] ?? BoardAssets.defaultMarkColor(board);

  void setBoardAccent(String board, int color) {
    _boardAccentColors[board] = color;
    _set('boardAccentColors', jsonEncode(_boardAccentColors));
    notifyListeners();
  }

  List<int> get accentPalette => BoardAssets.accentPalette;

'''
    if 'accentColorFor' not in t:
        t = t.replace(
            '  set showEngineArrows(bool value) {\n'
            '    _showEngineArrows = value;\n'
            "    _set('showEngineArrows', value);\n"
            '    notifyListeners();\n'
            '  }\n',
            '  set showEngineArrows(bool value) {\n'
            '    _showEngineArrows = value;\n'
            "    _set('showEngineArrows', value);\n"
            '    notifyListeners();\n'
            '  }\n' + method,
        )
    # rename markColor to defaultMarkColor and add palette
    t = t.replace(
        '  /// Seçim ve motor oku rengi — her tahta için uyumlu vurgu.\n'
        '  static int markColor(String board) {',
        '  static const List<int> accentPalette = <int>[\n'
        '    0xFFE8A317, // altın\n'
        '    0xFFE2571E, // turuncu\n'
        '    0xFF2E9E3F, // yeşil\n'
        '    0xFF1E6FD9, // mavi\n'
        '    0xFF9B27B0, // mor\n'
        '    0xFF2A8F7A, // teal\n'
        '    0xFFC45C6A, // gül\n'
        '  ];\n\n'
        '  /// Seçim ve motor oku rengi — her tahta için uyumlu vurgu.\n'
        '  static int defaultMarkColor(String board) {',
    )
    # replace markColor( calls that should go through settings - in BoardAssets itself keep defaultMarkColor
    # Keep markColor as alias for backwards compat that checks settings? Circular. Better update call sites.
    if 'static int markColor(' in t and 'defaultMarkColor' in t:
        # add thin wrapper
        if 'static int markColor(String board) =>' not in t:
            t = t.replace(
                '  static int defaultMarkColor(String board) {',
                '  static int markColor(String board) =>\n'
                '      SettingsService.instance.accentColorFor(board);\n\n'
                '  static int defaultMarkColor(String board) {',
            )
    p.write_text(t, encoding='utf-8', newline='\n')
    print('settings accents ok')
else:
    print('accents already')

# Fix circular: BoardAssets.markColor -> SettingsService -> BoardAssets.defaultMarkColor is OK
# But SettingsService.accentColorFor calls BoardAssets.defaultMarkColor - good
# BoardAssets.markColor calls SettingsService.instance - BoardAssets is in same file after SettingsService - OK

print('step1-2 done')
