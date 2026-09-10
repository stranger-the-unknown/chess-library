# Chess Library

Satranç oyunlarını okumak, bulmaca çözmek, açılış çalışmak ve **tamamen
cihazda çalışan** bir motora karşı oynamak için bir uygulama. İnternet
bağlantısı gerekmez; hiçbir veri dışarı gönderilmez.

**Android** ve **Windows** üzerinde çalışır. Arayüz pencere genişliğine uyum
sağlar: telefonda alt gezinme çubuğu, masaüstünde soldaki gezinme şeridi
kullanılır.

Diller: Türkçe, İngilizce, İspanyolca, Almanca, Fransızca. Ayarlardan
değiştirilir; varsayılan sistem dilidir.

---

## Oyna

**Motora karşı oyna** — Zorluğu altı kademeden seçersin (yaklaşık 600–2300
Elo). Rengini beyaz, siyah ya da **rastgele** belirleyebilirsin. İstersen
normal diziliş yerine **kendi kurduğun pozisyondan** başlarsın.

**PGN yükle** — Bir dosyadan ya da panodan yapıştırarak. Bir dosyada
istediğin kadar oyun olabilir: oyunlar listelenir, seçtiklerini **yeni bir
liste olarak kaydedersin** ya da **var olan bir listeye eklersin**.
Başlıklar, yorumlar, varyantlar, NAG işaretleri ve `[FEN]` ile başlayan
oyunlar okunur. Uzun dosyalarda ilerleme çubuğu görünür, uygulama donmaz.

**Serbest tahta** — İki tarafı da senin oynadığın analiz tahtası.

**Pozisyon kur** — Taş paleti, hamle sırası, rok hakları ve geçerken alma
karesiyle tam bir pozisyon düzenleyici. FEN alanına doğrudan yazabilir ya da
panodan yapıştırabilirsin. Kurduğun pozisyonu analiz eder ya da motora karşı
oynarsın; menüden tahtayı PNG olarak kaydedebilirsin.

---

## Tahta ekranı

Taşları sürükleyerek ya da önce taşa, sonra hedef kareye dokunarak
oynarsın. Terfi ederken hangi taşı istediğin sorulur.

**Motor analizi** — Sağ üstteki grafik simgesiyle açılır. Değerlendirme
çubuğu, en iyi hamle oku, ana varyant ve arama derinliği görünür. Analiz
ayrı bir iş parçacığında çalışır, tahta akıcı kalır.

**Gezinme** — Hamle listesindeki herhangi bir hamleye dokunarak o konuma
gidersin; alttaki düğmelerle bir ileri, bir geri, başa ya da sona gidersin.

**Deneme hamleleri** — Kayıtlı bir oyuna bakarken tahtaya istediğin hamleyi
oynayıp motorun değerlendirmesinin nasıl değiştiğini görebilirsin. Bu
hamleler oyunun kendisine yazılmaz: hamle listesinde görünmez, PGN'e girmez,
kaydedilmez ve ekrandan çıkınca kaybolur. Şeritteki düğmelerle son denemeyi
geri alır ya da oyuna dönersin.

**Oyun incelemesi** — Oyun bitince motor bütün hamleleri değerlendirir.
Taraf başına doğruluk yüzdesi, her hamlenin niteliği (en iyi / çok iyi /
iyi / yanlışlık / hata / ciddi hata), değerlendirme grafiği ve oyunun dönüm
noktaları listelenir. Grafiğe dokunarak hamleler arasında atlarsın.

Menüden ayrıca: PGN kopyalama, FEN kopyalama/yapıştırma, listeye kaydetme,
tahtayı çevirme ve **pes etme**.

**Sesler** — Hamle türüne göre farklı ses çalar (kendi hamlen, rakibin
hamlesi, alma, rok, terfi, şah). Kural dışı hamle uyarısı yalnızca **şah
altındayken** duyulur; oradaki anlamı "bu hamle şahı kurtarmıyor"dur.
Şah yokken geçersiz bir kareye tıklamak sessizdir.

---

## Bulmacalar

Uygulama hazır bulmaca ile gelmez; listeleri kendin oluşturursun.

**Liste oluşturma** — Sağ üstteki **+** ile yeni bir liste açarsın. Listeyi
üç yolla doldurabilirsin:

1. **Tek tek ekleme** — Menüden "Bulmaca ekle", pozisyonu tahtada kurarsın.
2. **FEN listesi yapıştırma** — Menüden "FEN listesi yapıştır", her satıra
   bir FEN.
3. **Metin dosyasından alma** — Menüden "Metin dosyasından al" ve bir `.txt`
   seçersin.

**Dosya biçimi** — Her satırda bir FEN. Şu üç yazım da tanınır:

```
7k/8/5K2/8/8/8/8/6Q1 w - - 0 1
12	7k/8/5K2/8/8/8/8/6Q1 w - - 0 1
7k/8/5K2/8/8/8/8/6Q1 w - - 0 1|mat-1,az-tas|g1g7|12
```

Yani yalnızca FEN, ya da `numara<sekme>FEN`, ya da
`FEN|etiketler|çözüm|numara`. `#` ile başlayan satırlar ve boş satırlar
atlanır. Kurallara uymayan pozisyonlar sessizce elenir. Binlerce satırlık
dosyalarda ilerleme çubuğu görünür.

**Dosyaya verme** — Menüden "Metin dosyası olarak ver". Liste
`FEN|etiketler|çözüm|sıra` biçiminde yazılır ve aynı uygulamaya olduğu gibi
geri alınabilir. Yedeklemek ya da başka bir cihaza taşımak için kullan.

**Çözerken** — Kazandıran hamleyi tahtada oynarsın. Çözüm anahtarı olan
bulmacalarda kayıtlı varyant kullanılır; olmayanlarda doğruluğu motor
ölçer: hamlen en iyi hamleye göre değerlendirmeyi belirgin biçimde
düşürmüyorsa doğru sayılır, böylece eşdeğer iyi hamleler de kabul edilir.
Doğru hamleden sonra rakibin cevabını motor oynar.

İpucu alabilir, çözümü izleyebilir, baştan başlayabilir, favorilere
ekleyebilir, çözüldü olarak işaretleyebilir ve not düşebilirsin.

**Arama ve süzgeçler** — Çözülmemiş / çözülen / favoriler / mat var /
geçerken alma / eklediklerim. Arama kutusu sıra numarası (`#128`),
etiketler, ad, not ve FEN üzerinde çalışır; Türkçe harflere duyarsızdır.

Menüden **tahtayı PNG olarak kaydedebilirsin**. Her bulmaca yeniden
adlandırılabilir, pozisyonu düzenlenebilir ya da silinebilir.

---

## Açılışlar

Liste boş başlar; çalışmak istediğin varyantları kendin eklersin.

**Varyant ekleme** — Aile adı (ör. "İspanyol Açılışı"), varyant adı (ör.
"Breyer Varyantı") ve hamleler (SAN ya da PGN olarak yapıştırılabilir).
Her hamle kurallara göre doğrulanır; hatalı bir hamle varsa uyarı alırsın.
Eklediklerin aileye göre gruplanır.

**İzle** — Varyantı adım adım ya da otomatik oynatarak izlersin.

**Alıştırma** — Hamleleri sen oynarsın, yanlışta uyarı alırsın. Hatasız iki
tamamlamada varyant "öğrenildi" sayılır.

Her varyantta ipucu, not, favori, "bu konumdan motora karşı oyna" ve
"analiz tahtasında aç" seçenekleri vardır.

---

## Listelerim

Oyunlarını klasörler hâlinde saklarsın: yeniden adlandırma, listeler arası
taşıma, silme.

- **PGN dosyası içe aktar** ile bir listeye toplu oyun eklersin.
- **Listeyi PGN dosyası olarak ver** ile listenin tamamını dışarı alırsın.
- Listedeki oyunlar numaralandırılır; arama numara (`#42`), oyun adı,
  oyuncu, sonuç ve not üzerinde çalışır.
- **Okundu işareti**: tek tek ya da toplu işaretleme, "okunmamış / okunan"
  süzgeci ve başlıkta okunma oranı.
- Tüm verinin JSON yedeğini alıp geri yükleyebilirsin.

---

## Ayarlar

- **Tema** — koyu, açık ya da sistemi izle.
- **Dil** — sistem, Türkçe, İngilizce, İspanyolca, Almanca, Fransızca.
- **Tahta görünümü** — 12 seçenek: 9 düz renk (kahve, yeşil, turnuva,
  mavi, gri, arduvaz, kum, mor, fildişi) ve 3 ahşap (koyu ahşap, ceviz,
  meşe).
- **Taş takımı** — 6 seçenek: Chessnut, RhosGFX, Fantasy, Spatial,
  Celtic, Kiwen Suwi.
- **Kare adlarını göster** — koordinatların rengi seçtiğin tahtadan gelir:
  yazı, üzerinde durduğu karenin karşıt rengini alır, böylece her tahtada
  okunur kalır.
- Yasal hamle göstergeleri, son hamle vurgusu, hamle animasyonu,
  değerlendirme çubuğu.
- Hamle sesleri ve titreşim.
- Varsayılan motor zorluğu.

---

## Kurulum

**Android** — APK dosyasını telefona kopyalayıp açın. Bilinmeyen
kaynaklardan kuruluma izin vermeniz gerekebilir.

**Windows** — `ChessLibrary-Kurulum-<sürüm>.exe` dosyasını çalıştırın.
Yönetici hakkı istemez, kendi kullanıcı klasörünüze kurar; Başlat
menüsüne kısayol koyar ve Denetim Masası'ndan kaldırılabilir.

Kurulum istemiyorsanız taşınabilir sürümü de kullanabilirsiniz: verilen
klasörün **tamamını** kopyalayıp içindeki `ChessLibrary.exe` dosyasını
çalıştırın. Yanındaki DLL'ler ve `data` klasörü olmadan uygulama açılmaz.

> Windows ilk açılışta "Bilgisayarınızı korudu" uyarısı gösterebilir:
> uygulama kod imzalama sertifikasıyla imzalı değil. **Ek bilgi →
> Yine de çalıştır** ile geçebilirsiniz.

---

## Lisans

Proje [MIT](LICENSE) lisanslıdır. Taş takımları dışarıdan alınmıştır ve
kendi izin veren lisanslarıyla gelir; kaynakları ve atıfları için
[ASSETS.md](ASSETS.md) dosyasına bakın.

---

Kaynaktan derlemek için [BUILD.md](BUILD.md), ses ve görsellerin nasıl
üretildiği için [ASSETS.md](ASSETS.md) dosyalarına bakın.
