from pathlib import Path
import re

# Read current android to preserve exact function name + asset paths
p = Path('lib/services/engine/stockfish_android.dart')
t = p.read_text(encoding='utf-8')
print('FN', re.findall(r'Future<String\?> (\w+)', t))
print('ASSETS', re.findall(r"assets/stockfish/[^'\"]+", t))
print('IMPORTS', [l for l in t.splitlines() if l.startswith('import')])
