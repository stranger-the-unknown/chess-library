# Kaynaktan derleme

Flutter 3.47 veya üzeri gerekir.

```bash
flutter pub get
flutter test          # 73 test
```

## Android

Yayın derlemesi imza anahtarı ister. `android/key.properties.example`
dosyasını `android/key.properties` adıyla kopyalayıp kendi anahtarınızın
bilgilerini yazın (bu dosya `.gitignore` içindedir, depoya girmez).
Anahtarınız yoksa:

```bash
keytool -genkey -v -keystore chess-library.jks -keyalg RSA \
        -keysize 2048 -validity 10000 -alias chesslibrary
```

`key.properties` yoksa derleme hata ayıklama anahtarına düşer; o çıktı
Play'e yüklenemez ve sonradan güncellenemez.

```bash
flutter build apk --release
```

Çıktı: `build/app/outputs/flutter-apk/app-release.apk` (~56 MB). Bu dosya
üç mimariyi de (arm64, arm32, x86_64) taşır; hangi telefona verilirse
verilsin kurulur. Yayınlanan dosya budur: karşı tarafın kendi işlemcisini
bilmesi gerekmez.

Yalnızca 64 bit ARM için yaklaşık 21 MB'lık ayrı bir dosya isterseniz:

```bash
flutter build apk --release --split-per-abi
```

Çıktı: `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`. Bugünkü
telefonların hemen hepsi bunu kurar ama eski 32 bit cihazlar kuramaz.

İmzayı doğrulamak için:

```bash
apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
```

## Windows

Visual Studio'nun "Desktop development with C++" iş yükü gerekir.

```bash
flutter build windows --release
```

Çıktı: `build/windows/x64/runner/Release/` klasörü. Dağıtırken klasörün
tamamını kopyalayın: `ChessLibrary.exe` yanındaki DLL'ler ve `data`
klasörü olmadan çalışmaz.

### Kurulum dosyası

[Inno Setup 6](https://jrsoftware.org/isinfo.php) gerekir.

```bash
ISCC.exe windows\installer\chess_library.iss
```

Çıktı: `windows/installer/output/ChessLibrary-Kurulum-<sürüm>.exe`.
Sürüm numarası betiğin başındaki `AppVersion` satırındadır; `pubspec.yaml`
ile birlikte güncellenmelidir.

## Uygulama simgesi

```bash
python tools/make_icon.py && dart run flutter_launcher_icons
```

Ses, taş ve tahta varlıklarının üretimi için `ASSETS.md` dosyasına bakın.

---

## Bu depodaki geçici çözümler

Üçü de bir hata değil, bağımlılıkların bugünkü durumundan doğuyor;
ilgili paket güncellenirse kaldırılabilirler.

- **`android/build.gradle.kts` → `subprojects` bloğu.** Eklenti
  modüllerinin `compileSdk` sürümünü 36'ya çeker. `file_picker` hâlâ 34 ile
  derlendiği için bu olmadan yayın derlemesi başarısız oluyor. Blok,
  `evaluationDependsOn` çağrısından **önce** durmalıdır.

- **`windows/CMakeLists.txt` → `_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS`.**
  Ses için kullanılan `just_audio_windows` hâlâ `<experimental/coroutine>`
  başlığını kullanıyor; yeni MSVC sürümleri bu tanım olmadan derlemeyi
  reddediyor.

- **`android/gradle.properties` → `kotlin.incremental=false`.** Kotlin
  artımlı derleme önbelleğinin bozulmasına karşı eklendi. Sorun
  yaşamıyorsanız kaldırabilirsiniz.

## Kod düzeni üzerine iki not

- Motor **Stockfish 17**'dir ve `stockfish_chess_engine` paketiyle
  uygulamanın içine derlenir; ağ bağlantısı gerektirmez.
  `lib/services/engine/stockfish_engine.dart` onu UCI üzerinden
  konuşturur, `engine_service.dart` ise uygulamanın geri kalanına tek bir
  yüz gösterir — motor bir gün yine değişirse değişecek yer orasıdır.
- **Derleme sırasında internet gerekir**: NNUE değerlendirme ağları
  (`nn-*.nnue`) derleme sırasında indirilir. Windows'ta ağ dosyaları
  çalıştırılabilir dosyanın yanına konur ve kurulum paketine girer;
  Android'de küçük ağ doğrudan `.so` içine gömülür.
- Kural motoru (`lib/models/chess_engine.dart`) ayrı bir şeydir ve
  yerinde durur: hamle üretimi, yasallık, SAN ve FEN ondan gelir. Ayrıca
  Stockfish'e giden her pozisyonu doğrular; paket kural dışı pozisyonda
  çöküyor.
- Masaüstü yerleşim sınırları tek yerde toplanmıştır:
  `lib/widgets/responsive.dart` (tahta en fazla 520, içerik en fazla 760,
  geniş pencere eşiği 900).

---

## Sürüm notları

Her sürümün notu `fastlane/metadata/android/<dil>/changelogs/<sürüm
kodu>.txt` dosyasındadır (Türkçe ve İngilizce). GitHub'daki yayın
açıklaması da buradan yazılır; tek yerde tutulur ki ikisi birbirinden
ayrılmasın.

Mağaza metinleri (başlık, kısa ve uzun açıklama) aynı klasördedir.
