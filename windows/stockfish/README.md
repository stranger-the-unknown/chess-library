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

## Sağlama toplamı

9.0.7 ile yayımlanan `stockfish.exe`:

```text
45bc8e4969147db9c2eb533810637994619bff0eacc81ccfd9854394901bcbd0
```

İndirdiğiniz arşivi resmi sürüm sayfasındaki SHA-256 ile karşılaştırın:

```bash
sha256sum stockfish-windows-x86-64-universal.zip
```
