# Maia-3 weights

The human-like opponent needs `maia3-5m.bin` in this folder before
`flutter build`. It is generated from the original Maia-3 weights
(CSSLab, AGPL-3.0):

1. Download `maia3-5m.pt` from https://huggingface.co/UofTCSSLab/Maia3-5M
   (model code: https://github.com/CSSLab/maia3).
2. With PyTorch and NumPy installed:
   `python tools/maia_export.py maia3-5m.pt assets/maia/maia3-5m.bin`

The output is ~10 MB (fp16). It is gitignored. Without it the app still
builds and runs, but a game at a human-like level reports that Maia could
not be started (it does not switch to Stockfish); the release script
refuses to build without it.
