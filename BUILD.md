# Kaynaktan derleme

Flutter 3.47 veya üzeri gerekir.

```bash
flutter pub get
flutter test          # 381 test
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

`key.properties` yoksa **release derlemesi durur**: imzasız ya da hata
ayıklama anahtarıyla imzalanmış bir "yayın" dosyası üretilmesin diye.
Hata ayıklama derlemeleri anahtarsız çalışmayı sürdürür.

```bash
flutter build apk --release
```

Çıktı: `build/app/outputs/flutter-apk/app-release.apk` (~257 MB). Bu
dosya üç mimariyi de (arm64, arm32, x86_64) taşır; hangi telefona
verilirse verilsin kurulur. Yayınlanan dosya budur: karşı tarafın kendi
işlemcisini bilmesi gerekmez.

Boyutun tamamı Stockfish'ten geliyor: her mimarinin ikilisi kendi NNUE
ağını gömüyor (~95 MB) ve üçü birden pakete giriyor.

Yalnızca tek bir mimari için daha küçük bir dosya isterseniz:

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

## Kod düzeni üzerine notlar

- Motor `lib/services/engine/` altındadır. Stockfish **ayrı bir işletim
  sistemi süreci** olarak çalışır (Isolate değil); `engine_coordinator.dart`
  o tek sürecin sahibidir ve analiz / ipucu / oyun hamlesi isteklerini tek
  sıraya sokar.
- Masaüstü yerleşim sınırları tek yerde toplanmıştır:
  `lib/widgets/responsive.dart` (tahta en fazla 520, içerik en fazla 760,
  geniş pencere eşiği 900).
- **Analiz kayıtları ayrı bir anahtarda** tutulur
  (`analysis_lists_v1`). İki sebeple: yedeğe girmemeleri gerekiyor ve
  "tüm verileri sıfırla" onları da götürmeli. Ayrı anahtar ikisini de
  kendiliğinden sağlıyor. `StorageService.loadPlaylists()` yalnızca
  kullanıcı listelerini döndürür; analiz listeleri `loadAnalysisLists()`
  ile okunur, kimliğe göre arama `playlistById()` ile yapılır.
- **Sürüm tek yerde**: `lib/services/settings_service.dart` içindeki
  `appVersionName`. `pubspec.yaml`, kurulum betiği ve uygulama içindeki
  "Hakkında" metni bununla karşılaştırılır ve `test/l10n_test.dart`
  üçünün tutarlılığını zorunlu kılar.
- **Ekran kilidi** yalnızca toplu analiz sürerken alınır ve her durumda
  (`finally`) bırakılır. Bırakılmazsa ekran sonsuza kadar açık kalır.

---

## Sürüm notları

Her sürümün notu `fastlane/metadata/android/<dil>/changelogs/<sürüm
kodu>.txt` dosyasındadır (Türkçe ve İngilizce). GitHub'daki yayın
açıklaması da buradan yazılır; tek yerde tutulur ki ikisi birbirinden
ayrılmasın.

Mağaza metinleri (başlık, kısa ve uzun açıklama) aynı klasördedir.
