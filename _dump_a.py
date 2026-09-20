from pathlib import Path
import re

p = Path('lib/services/engine/stockfish_android.dart')
t = p.read_text(encoding='utf-8')
print(t)
