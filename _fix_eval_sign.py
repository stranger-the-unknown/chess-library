from pathlib import Path
import re

p = Path("lib/screens/game_screen.dart")
t = p.read_text(encoding="utf-8")

new_after = """  void _afterPositionChanged() {
    if (!_analysisOn) return;
    _analysisDebounce?.cancel();
    _analysisToken++;
    EngineService.instance.stopAnalysis();
    // Eski skor yeni tarafa gore isaret cevirmesin: hemen temizle.
    // Yalnizca yeni sonuc gelince +/- ile goster.
    if (_analysis != null || _thinking) {
      setState(() {
        _analysis = null;
        _thinking = false;
      });
    }
    _analysisDebounce = Timer(const Duration(milliseconds: 700), _runAnalysis);
  }"""

m = re.search(r"  void _afterPositionChanged\(\) \{.*?\n  \}", t, re.S)
if not m:
    raise SystemExit("afterPositionChanged not found")
print("OLD AFTER:\n", m.group(0)[:300])
t = t[: m.start()] + new_after + t[m.end() :]

# Score format with explicit +
t2, n = re.subn(
    r": \(_whiteScore! / 100\)\.toStringAsFixed\(2\);",
    ": _formatScoreCp(_whiteScore!);",
    t,
    count=1,
)
print("score format replacements", n)
t = t2

if "_formatScoreCp" not in t:
    helper = """
  /// Beyaz bakisi; pozitifte acik `+`.
  String _formatScoreCp(int cp) {
    final body = (cp.abs() / 100).toStringAsFixed(2);
    if (cp > 0) return '+$body';
    if (cp < 0) return '-$body';
    return '0.00';
  }

"""
    t = t.replace(
        "  String _describeAnalysis(SearchResult analysis) {",
        helper + "  String _describeAnalysis(SearchResult analysis) {",
    )
    print("added helper")

p.write_text(t, encoding="utf-8")
print("game_screen ok")

# EvalBar: null -> em dash, not 0.0
eb = Path("lib/widgets/eval_bar.dart")
et = eb.read_text(encoding="utf-8")
et2 = et.replace("if (score == null) return '0.0';", "if (score == null) return '·';")
if et2 == et:
    et2 = et.replace('if (score == null) return "0.0";', 'if (score == null) return "·";')
eb.write_text(et2, encoding="utf-8")
print("eval_bar changed", et2 != et)
