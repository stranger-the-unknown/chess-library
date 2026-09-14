# Varlıkların kaynağı ve lisansları

Bu depodaki varlıklar iki gruba ayrılır:

1. **Taş takımları** — dışarıdan alınmıştır, izin veren lisanslarla gelir.
   Aşağıdaki atıf listesi projeyle birlikte dağıtılmalıdır.
2. **Sesler, ahşap tahta dokuları ve uygulama simgesi** — bu proje için
   üretilmiştir; hiçbir yükümlülüğü yoktur.

Hiçbir varlık ticari bir üründen kopyalanmamıştır.

---

## Taş takımları — `assets/pieces/`

Dokuz takımın tamamı [Lichess](https://github.com/lichess-org/lila)
deposundan alınmıştır. Hepsi **ticari kullanıma da izin veren** ve
"bulaşıcı" olmayan (projenizin lisansını belirlemeyen) lisanslardadır.

| Takım | Çizen | Lisans |
|---|---|---|
| `chessnut` | [Alexis Luengas](https://github.com/LexLuengas/chessnut-pieces) | [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0) |
| `rhosgfx` | [RhosGFX](https://rhosgfx.itch.io/) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) (kamu malı) |
| `fantasy` | [Maurizio Monge](https://github.com/maurimo/chess-art) | [MIT](https://github.com/maurimo/chess-art/blob/main/LICENSE) |
| `spatial` | [Maurizio Monge](https://github.com/maurimo/chess-art) | [MIT](https://github.com/maurimo/chess-art/blob/main/LICENSE) |
| `celtic` | [Maurizio Monge](https://github.com/maurimo/chess-art) | [MIT](https://github.com/maurimo/chess-art/blob/main/LICENSE) |
| `kiwen-suwi` | [neverRare](https://github.com/neverRare) | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |
| `firi` | [James Faure](https://github.com/jfaure/Firi-pieceset) | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |
| `totoy` | Kosal Sen | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |
| `papercut` | [Nikolay Anzarov](https://nikoichu.itch.io/) | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |

**Yükümlülük:** `rhosgfx` kamu malıdır, hiçbir şey gerektirmez. Diğerleri
yalnızca **atıf** ister — yani bu tablonun uygulamayla birlikte
dağıtılması yeterlidir. Hiçbiri projenin kendi lisansını kısıtlamaz ve
hiçbiri ticari kullanımı yasaklamaz.

Dosyalar SVG'dir; uygulama bunları `flutter_svg` ile çizer, bu yüzden her
ölçüde net görünürler.

### İndirdikten sonra yapılan tek işlem

Bu takımların bir kısmı biçimlendirmeyi CSS sınıflarıyla verir
(`<style>.stroke-color{stroke:#000}</style>` gibi). `flutter_svg`
`<style>` öğesini desteklemez; dosyalar olduğu gibi kullanılırsa
konturlar sessizce kaybolur ve taşlar düz siluete döner.

`tools/assets/inline_svg_styles.py` bu kuralları çözüp her öğeye
doğrudan sunum özniteliği olarak yazar ve `<style>` ile `class`
niteliklerini kaldırır. CSS öncelik sırası korunur
(sunum özniteliği < sınıf kuralı < satır içi `style`). Çizimin kendisi
değişmez; yalnızca aynı biçimlendirme başka bir sözdizimiyle yazılır.

    python tools/assets/inline_svg_styles.py assets/pieces

### Bilerek alınmayanlar

Bu proje açık kaynak (MIT) olduğu hâlde aşağıdakiler **yine de**
alınamaz; engel açık kaynak olup olmamak değil, lisansların birbiriyle
bağdaşmaması:

- **cburnett, merida, mono** (GPLv2+) ve **letter, pirouetti, pixel,
  mpchess** (AGPLv3+): "bulaşıcı" lisanslar. Bir tanesini bile koymak
  uygulamanın tamamının GPL/AGPL ile yayımlanmasını gerektirir; MIT
  olarak kalamaz.
- **maestro, staunty, cardinal, california, caliente, horsey, cooke,
  monarchy, xkcd** ve benzerleri (CC BY-NC-SA): ticari kullanıma kapalı.
  MIT "dilediğiniz gibi kullanın" der; bu ikisi bir arada tutarlı
  değildir. Ayrıca "SA" koşulu aynı bulaşma sorununu getirir.
- **shahi-ivory-brown**: türetme ve değiştirme yasak.
- **Lichess tahta görselleri** (AGPLv3+): aynı sebeple alınmadı; ahşap
  tahtalar bu proje için üretildi, düz renkli tahtalar ise doğrudan
  çizilir.

---

## Sesler — `assets/sounds/` (12 dosya, ~89 KB)

`tools/assets/make_sounds.py` ile sentezlenir; kayıt kullanılmaz.

Tahta bir taşın tahtaya vuruşu, inharmonik sönümlü modların üst üste
binmesiyle modellenir; en tepede bant geçirgen süzülmüş kısa bir gürültü
patlaması vuruş transiyentini verir. Çan benzeri sesler (terfi, bildirim,
oyun başı/sonu) birkaç kısmi harmonikli tonlardan kurulur.

## Tahtalar — `assets/boards/`

Uygulamada on beş tahta vardır: on iki düz renk ve üç ahşap.

**Düz renkli tahtaların görsel dosyası yoktur.** Uygulama onları
`BoardAssets` içindeki iki renkten doğrudan tuvale çizer: her ölçüde
kusursuz keskin çıkarlar, ölçekleme bulanıklığı ya da sıkıştırma izi
olmaz ve hiç yer kaplamazlar. İki renkli dama deseni zaten kimsenin
telifinde değildir.

Ahşap görünümlü üç tahta (`dark_wood`, `walnut`, `oak`)
`tools/assets/make_boards.py` ile üretilir. Damar bilerek çok hafif
tutulmuştur — parlaklığı yalnızca ±%6 dolayında oynatır — böylece ahşap
hissi verir ama taşların okunmasını zorlaştırmaz.

Her tahtanın açık ve koyu kare rengi `BoardAssets` içinde kayıtlıdır; kare
adlarının rengi de buradan türetilir (yazı, üzerinde durduğu karenin
karşıt rengini alır).

## Uygulama simgesi — `assets/icon/`

Düz çokgenlerden oluşan bir at silueti; bu proje için çizilmiştir
(`tools/make_icon.py`).

---

## Üretimi yinelemek

```bash
python -m pip install numpy pillow lameenc
python tools/assets/make_sounds.py assets/sounds
python tools/assets/make_boards.py assets/boards
```

Rastgelelik sabit tohumlarla beslendiği için çıktı her çalıştırmada
aynıdır.
