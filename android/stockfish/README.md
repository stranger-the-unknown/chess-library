# Stockfish (Android)

Chess Library 7.0 hibrit motoru: inceleme/analiz için ayrı UCI süreci.

- İnceleme / canlı analiz / oyun incelemesi → Stockfish (ayrı process)
- Motora karşı oyun + bulmaca cevap/ipucu → Dart motoru
- `flutter_stockfish` **KULLANILMAZ**

İkili dosyalar GPLv3 ve büyüktür; **git'e girmez**.

## İndirme (sf_19)

```bash
cd android/stockfish

curl -L -o sf-arm64.tar.gz \
  https://github.com/official-stockfish/Stockfish/releases/download/sf_19/stockfish-android-arm64-universal.tar.gz
tar -xzf sf-arm64.tar.gz
cp stockfish/stockfish-android-arm64-universal ./stockfish-arm64-v8a

curl -L -o sf-armv7.tar.gz \
  https://github.com/official-stockfish/Stockfish/releases/download/sf_19/stockfish-android-armv7-neon.tar.gz
tar -xzf sf-armv7.tar.gz
cp stockfish/stockfish-android-armv7-neon ./stockfish-armeabi-v7a
```

## Flutter asset'e kopyala (APK'ya girsin)

```bash
mkdir -p ../../assets/stockfish
cp stockfish-arm64-v8a ../../assets/stockfish/arm64-v8a
cp stockfish-armeabi-v7a ../../assets/stockfish/armeabi-v7a
# İsteğe bağlı: yalnızca hedef ABI'yi kopyalayarak APK boyutunu küçült.
```

Uygulama ilk çalıştırmada asset'ten `getApplicationSupportDirectory()/stockfish`
yoluna çıkarır ve `chmod 755` uygular.

Alternatif: `STOCKFISH_PATH` ortam değişkeni (test / özel derleme).

Stockfish GPLv3 — https://stockfishchess.org/
