# Stockfish (Linux)

The Linux build runs Stockfish as a separate process, like on Windows.
Before `flutter build linux`, place the binary here as `stockfish`
(executable). CMake copies it next to the app executable in the bundle.
It is gitignored.

```bash
cd linux/stockfish
curl -L -o sf.tar.gz https://github.com/official-stockfish/Stockfish/releases/download/sf_19/stockfish-linux-x86-64-universal.tar.gz
echo "9defc0d4e55d49c65a6d042f3e571a39fcea499ade6dbe741b53b8c65e03611f  sf.tar.gz" | sha256sum -c
mkdir -p _extract && tar -xzf sf.tar.gz -C _extract
cp _extract/stockfish/stockfish-linux-x86-64-universal stockfish
chmod +x stockfish
```

Without it the app still runs, but analysis, puzzles judged by the engine
and the two Stockfish levels have no engine. A system Stockfish
(`/usr/games/stockfish`, `/usr/bin/stockfish`) or `STOCKFISH_PATH` is used
if the bundled binary is missing.

Stockfish is GPLv3.
