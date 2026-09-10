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
flutter build apk --release --split-per-abi
```

Çıktı: `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` (~21 MB).

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

- Motor `lib/services/engine/` altında ve Flutter'dan bağımsız, saf
  Dart'tır; `engine_service.dart` onu bir `Isolate` içinde çalıştırır.
- Masaüstü yerleşim sınırları tek yerde toplanmıştır:
  `lib/widgets/responsive.dart` (tahta en fazla 520, içerik en fazla 760,
  geniş pencere eşiği 900).

---

## F-Droid

Uygulama F-Droid ölçütlerine uygundur: tüm bağımlılıklar özgür lisanslı
(MIT / BSD), Google Play hizmetleri kullanılmaz, ağ erişimi yoktur.

F-Droid **sizin APK'nızı kabul etmez**; kaynaktan kendisi derler ve kendi
anahtarıyla imzalar. Bu yüzden F-Droid'den kurulan sürümle buradaki
sürüm farklı imzalara sahiptir: kullanıcı birinden diğerine geçmek
isterse uygulamayı silip yeniden kurmak zorundadır.

Mağaza sayfasında görünen metinler `fastlane/metadata/android/` altındadır
(başlık, kısa/uzun açıklama, sürüm notu, simge). Yeni sürümde
`changelogs/<versionCode>.txt` dosyası eklenmelidir.

### Gönderim

[fdroiddata](https://gitlab.com/fdroid/fdroiddata) deposunu GitLab'de
çatallayıp `metadata/io.github.strangertheunknown.chesslibrary.yml`
dosyasını ekleyin ve birleştirme isteği açın:

```yaml
Categories:
  - Games
License: MIT
AuthorName: stranger-the-unknown
SourceCode: https://github.com/stranger-the-unknown/chess-library
IssueTracker: https://github.com/stranger-the-unknown/chess-library/issues
Changelog: https://github.com/stranger-the-unknown/chess-library/releases

AutoName: Chess Library

RepoType: git
Repo: https://github.com/stranger-the-unknown/chess-library.git

Builds:
  - versionName: 2.0.0
    versionCode: 2
    commit: v2.0.0
    output: build/app/outputs/flutter-apk/app-release.apk
    srclibs:
      - flutter@3.47.2
    rm:
      - ios
      - linux
      - macos
      - web
    build:
      - $$flutter$$/bin/flutter config --no-analytics
      - $$flutter$$/bin/flutter pub get
      - $$flutter$$/bin/flutter build apk

AutoUpdateMode: Version
UpdateCheckMode: Tags
UpdateCheckData: pubspec.yaml|version:\s.+\+(\d+)|.|version:\s(.+)\+
CurrentVersion: 2.0.0
CurrentVersionCode: 2
```

`key.properties` derleme sunucusunda bulunmadığı için imzalama hata
ayıklama anahtarına düşer; F-Droid bu imzayı zaten atıp kendi anahtarıyla
imzaladığı için sorun olmaz.

Ekran görüntüleri isteğe bağlıdır ama sayfayı belirgin biçimde
iyileştirir: `fastlane/metadata/android/<dil>/images/phoneScreenshots/`
altına telefondan alınmış PNG'ler koyun.
