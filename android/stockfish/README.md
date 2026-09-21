# Stockfish (Android)

Chess Library 8+: inceleme / canlı analiz / motora karşı oyun — yalnızca
Stockfish UCI (ayrı süreç). `flutter_stockfish` **KULLANILMAZ**.

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

## x86_64 (emülatör / Chromebook)

Resmi sürümlerde Android **x86_64** yapısı yok; NDK ile kendimiz
derliyoruz. Gereken her şey Android SDK ile zaten geliyor
(`D:\Android\Sdk\ndk\<sürüm>`), ayrıca bir şey kurmak gerekmiyor.

```bash
curl -L -o sf19.tar.gz   https://github.com/official-stockfish/Stockfish/archive/refs/tags/sf_19.tar.gz
tar -xzf sf19.tar.gz && cd Stockfish-sf_19/src

NDK=/d/Android/Sdk/ndk/28.2.13676358
export PATH="$NDK/toolchains/llvm/prebuilt/windows-x86_64/bin:$NDK/prebuilt/windows-x86_64/bin:$PATH"

make net                                   # NNUE ağı (~98 MB), ikiliye gömülüyor
make -j4 build ARCH=x86-64-sse41-popcnt COMP=ndk      CXX=x86_64-linux-android29-clang++
llvm-strip stockfish

cp stockfish ../../stockfish-x86_64
cp stockfish ../../../app/src/main/jniLibs/x86_64/libstockfish.so
```

`ARCH` neden `sse41-popcnt`: AVX2 daha hızlı olurdu ama desteklemeyen bir
işlemcide ikili SIGILL ile ölür. x86_64 Android çoğunlukla emülatör
demek; orada hız değil, çalışması önemli.

Doğrulama: `file stockfish` çıktısı
`ELF 64-bit LSB pie executable, x86-64 ... interpreter /system/bin/linker64`
demeli.

## APK'ya paketleme (iki yol)

### 1) Tercih edilen: jniLibs → nativeLibraryDir

Android 10+ W^X / SELinux, uygulama veri dizininden çalıştırmayı
engeller; `chmod` yetmez. Paket yöneticisinin çıkardığı
`nativeLibraryDir/libstockfish.so` yürütülebilir.

```bash
mkdir -p ../app/src/main/jniLibs/arm64-v8a ../app/src/main/jniLibs/armeabi-v7a
cp stockfish-arm64-v8a ../app/src/main/jniLibs/arm64-v8a/libstockfish.so
cp stockfish-armeabi-v7a ../app/src/main/jniLibs/armeabi-v7a/libstockfish.so
```

### 2) Yedek: Flutter assets + runtime extract

```bash
mkdir -p ../../assets/stockfish
cp stockfish-arm64-v8a ../../assets/stockfish/arm64-v8a
cp stockfish-armeabi-v7a ../../assets/stockfish/armeabi-v7a
```

Çalışma zamanında önce `libstockfish.so` (nativeLibraryDir) aranır;
yoksa asset'ten `getApplicationSupportDirectory()/stockfish` çıkarılır
ve `chmod 755` denenir.

Alternatif: `STOCKFISH_PATH` ortam değişkeni (test / özel derleme).

## Sağlama toplamları

İndirilen ya da derlenen ikilinin doğruluğu elle denetlenmeli: resmi
sürüm sayfasındaki dosya için yayımlanan SHA-256 ile karşılaştırın.

```bash
sha256sum sf-arm64.tar.gz
```

9.0.7 ile yayımlanan APK'daki ikililer:

| Dosya | SHA-256 |
|---|---|
| `jniLibs/arm64-v8a/libstockfish.so` | `ffd8fc2004d3d19f9fdab95d84c92709aea92e8d3af405eda0b281b23cf1daf8` |
| `jniLibs/armeabi-v7a/libstockfish.so` | `993a3e8bce85a503abc900056019691057a83e13ae92c1a2cbb089b9680593f3` |
| `jniLibs/x86_64/libstockfish.so` | `26f2a8204575ea9b4f889a87014d4d912b265ec6fb5f8a1624425c6fae31ca24` |

Kendi derlemenizin aynı çıkması beklenmez (derleyici sürümü ve bayraklar
değişir); bu tablo yayımlanan dosyanın ne olduğunu belgeler.

Stockfish GPLv3 — https://stockfishchess.org/
