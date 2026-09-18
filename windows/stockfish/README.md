# Stockfish (Windows)

Chess Library 7.0 hibrit motoru: inceleme icin ayri UCI sureci.

- Inceleme/analiz -> Stockfish (ayri process)
- Motora karsi oyun -> Dart motoru
- flutter_stockfish KULLANILMAZ

## Indirme

`powershell
cd windows\stockfish
curl.exe -L -o sf.zip https://github.com/official-stockfish/Stockfish/releases/download/sf_19/stockfish-windows-x86-64-universal.zip
Expand-Archive sf.zip -DestinationPath _extract -Force
Copy-Item _extract\stockfish\stockfish-windows-x86-64-universal.exe .\stockfish.exe -Force
`

Veya STOCKFISH_PATH ortam degiskeni.

Stockfish GPLv3.
