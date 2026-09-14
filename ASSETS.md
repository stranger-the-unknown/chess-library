# Varlıkların kaynağı ve lisansları

Bu depodaki varlıklar iki gruba ayrılır:

1. **Taş takımları** — dışarıdan alınmıştır. Aşağıdaki atıf listesi
   projeyle birlikte dağıtılmalıdır.
2. **Sesler ve uygulama simgesi** — bu proje için üretilmiştir;
   uygulamanın lisansı altındadır.

Hiçbir varlık ticari bir üründen kopyalanmamıştır.

Uygulamanın lisansı **AGPLv3**'tür; nedeni [COPYRIGHT.md](COPYRIGHT.md)
dosyasında anlatılmıştır.

---

## Taş takımları — `assets/pieces/`

On altı takımın tamamı [Lichess](https://github.com/lichess-org/lila)
deposundan alınmıştır. Hepsi ticari kullanıma izin verir. İlk dokuzu
"bulaşıcı" olmayan lisanslarla gelir; son yedisi GPL/AGPL ailesindendir
ve uygulamanın AGPLv3 olmasının nedeni onlardır.

### İzin veren lisanslar

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

### Bulaşıcı (copyleft) lisanslar

Bunlar uygulamanın tamamının aynı koşullarla dağıtılmasını gerektirir.
Uygulama bu yüzden AGPLv3'tür.

| Takım | Çizen | Lisans |
|---|---|---|
| `cburnett` | [Colin M.L. Burnett](https://en.wikipedia.org/wiki/User:Cburnett) | [GPLv2+](https://www.gnu.org/licenses/gpl-2.0.txt) |
| `merida` | Armando Hernandez Marroquin | [GPLv2+](https://www.gnu.org/licenses/gpl-2.0.txt) |
| `mono` | Thibault Duplessis ve [Colin M.L. Burnett](https://en.wikipedia.org/wiki/User:Cburnett) | [GPLv2+](https://www.gnu.org/licenses/gpl-2.0.txt) |
| `letter` | [usolando](https://lichess.org/@/usolando) | AGPLv3+ |
| `pirouetti` | [pirouetti](https://lichess.org/@/pirouetti) | AGPLv3+ |
| `pixel` | therealqtpi | AGPLv3+ |
| `mpchess` | [Maxime Chupin](https://github.com/chupinmaxime) | [GPLv3+](https://www.gnu.org/licenses/gpl-3.0.txt) |

**Yükümlülük:** `rhosgfx` kamu malıdır, hiçbir şey gerektirmez. İzin
veren lisanslardaki diğerleri yalnızca **atıf** ister — bu tabloların
uygulamayla birlikte dağıtılması yeterlidir. Copyleft olanlar ayrıca
uygulamanın kaynak koduyla birlikte, aynı lisansla dağıtılmasını
gerektirir; bu da AGPLv3 ile sağlanıyor. Hiçbiri ticari kullanımı
yasaklamaz.

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

`mono` takımı Lichess'te tek bir gri siluet olarak durur; beyaz ve siyah
ayrımı CSS ile yapılır. Bu depoda altı dosyadan on iki dosya üretildi:
dolgu ve kontur renkleri beyaz taşta açık/koyu, siyah taşta koyu/açık
olacak şekilde yazıldı. Çizimin kendisi değişmedi.

### Bilerek alınmayanlar

- **maestro, staunty, cardinal, california, caliente, horsey, cooke,
  monarchy, xkcd** ve benzerleri (CC BY-NC-SA): ticari kullanıma
  kapalıdır. Lisansı AGPLv3 yapmak bunu **çözmez**: GPL ailesi ticari
  kullanma hakkını güvence altına alır, "NC" ise yasaklar. İkisi bir
  arada tutarlı değildir. Bu takımlar ancak uygulama ticari kullanıma
  kapatılırsa kullanılabilir, o da uygulamanın özgür yazılım olmaktan
  çıkması demektir.
- **shahi-ivory-brown**: türetme ve değiştirme yasak.
- **Lichess tahta görselleri**: uygulamada tahta görseli yok; tahta
  kullanıcının seçtiği iki renkten çiziliyor.

---

## Sesler — `assets/sounds/` (12 dosya, ~89 KB)

`tools/assets/make_sounds.py` ile sentezlenir; kayıt kullanılmaz.

Tahta bir taşın tahtaya vuruşu, inharmonik sönümlü modların üst üste
binmesiyle modellenir; en tepede bant geçirgen süzülmüş kısa bir gürültü
patlaması vuruş transiyentini verir. Çan benzeri sesler (terfi, bildirim,
oyun başı/sonu) birkaç kısmi harmonikli tonlardan kurulur.

## Tahta

**Tahtanın görsel dosyası yoktur.** Hazır tahta da yoktur: kullanıcı açık
ve koyu kare rengini `BoardAssets.palette` içindeki yüz renkten kendisi
seçer, uygulama da kareleri o iki renkten doğrudan tuvale çizer. Her
ölçüde kusursuz keskin çıkar, ölçekleme bulanıklığı ya da sıkıştırma izi
olmaz, hiç yer kaplamaz. İki renkli dama deseni zaten kimsenin telifinde
değildir.

Palet 3.0 öncesindeki on beş hazır tahtanın bütün kare renklerini
içerir; eski görünümlerden hiçbiri kaybolmadı.

İsteğe bağlı **ahşap dokusu** de bir görselden gelmez: sabit tohumlu,
hafifçe dalgalı yatay çizgilerden çizilir ve seçilen renklerin üstüne
biner. Böylece damar üç sabit ahşaba değil, kullanıcının seçtiği her
renk çiftine uyar.

Kare adlarının rengi seçilen iki renkten türetilir: yazı, üzerinde
durduğu karenin karşıt kare rengini alır. İki renk birbirine çok yakın
seçilirse yazı kaybolacağı için karşıtlık ölçülür ve gerekirse siyah ya
da beyaza düşülür; paletten kurulabilecek on bin tahtanın hepsinde kare
adlarının okunur kaldığı testle denetlenir.

## Uygulama simgesi — `assets/icon/`

Düz çokgenlerden oluşan bir at silueti; bu proje için çizilmiştir
(`tools/make_icon.py`).

---

## Üretimi yinelemek

```bash
python -m pip install numpy lameenc
python tools/assets/make_sounds.py assets/sounds
```

Rastgelelik sabit tohumlarla beslendiği için çıktı her çalıştırmada
aynıdır.
