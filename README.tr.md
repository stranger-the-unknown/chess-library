# Chess Library

*[English](README.md) · **Türkçe***

Satranç oyunlarını okumak, bulmaca çözmek, açılış çalışmak ve **tamamen
cihazda çalışan** bir motora karşı oynamak için bir uygulama. İnternet
bağlantısı gerekmez; hiçbir veri dışarı gönderilmez.

**Android** ve **Windows** üzerinde çalışır. Arayüz pencere genişliğine uyum
sağlar: telefonda alt gezinme çubuğu, masaüstünde soldaki gezinme şeridi
kullanılır. Geniş pencerede oyun ekranı iki sütuna ayrılır — solda tahta,
sağda hamle listesi ve düğmeler. Aynı yerleşim bulmaca çözerken ve
açılış çalışırken de kullanılır. Masaüstünde tahtanın boyutu ayarlardan
seçilir (küçük / orta / büyük): üçü de pencerenin verebildiği en büyük
tahtanın oranıdır, yani seçim her ekranda gözle ayırt edilir.

Android'de boyut sorulmaz, tahta sığdığının tamamı kadardır. Telefon
dikey, tablet yatay çalışır ve ekran dönmez: tablette yatay, yan panelin
sığdığı tek yönelimdir.

Diller: Türkçe ve İngilizce. Ayarlardan değiştirilir; varsayılan sistem
dilidir.

---

## Motor (Stockfish)

- **Tüm motor hamleleri** → resmi Stockfish, ayrı UCI OS süreci (Dart motoru yok)
- **Motora karşı** → altı UI seviyesi için güç sınırı (`Skill Level` / `UCI_LimitStrength`+`UCI_Elo`). Usta = tam güç.
- **Bulmaca ve canlı analiz** → tam güç Stockfish
- **Çekirdek**: motor *hamlesi* telefonda da bilgisayarda da tek
  çekirdekle üretilir, böylece bir kademe her cihazda aynı anlama gelir.
  *Analiz* masaüstünde çekirdeklerin yarısını (en çok dördünü) ve daha
  büyük bir hash kullanır; orada motor rakip değil, araçtır.
- **Tempo**: motorun cevabı, senin hamlenden en erken 0,70 saniye sonra
  görünür. Alt kademelerde arama neredeyse anında bitiyor ve hamle,
  neyin alındığı görülmeden tahtada beliriyordu.
- `flutter_stockfish` **kullanılmaz**
- İkili dosyalar **gitignore**'dadır; indirme:
  - Windows: [`windows/stockfish/README.md`](windows/stockfish/README.md)
  - Android: [`android/stockfish/README.md`](android/stockfish/README.md)
- Stockfish yoksa veya çökerse: boş sonuç, takılma yok; UCI süreci yeniden başlatılabilir. Dart yedek yok.
- Arama iptali süreci **yeniden kurmaz**: motora `stop` yazılır ve kendi
  `bestmove` satırı beklenir (bir saniyelik emniyetle).

---

## Oyna

**Motora karşı oyna** — Zorluğu altı kademeden seçersin: acemiden ustaya,
her kademenin ne kadar hata yaptığı kısaca yazıyor. Rengini beyaz, siyah ya da **rastgele** belirleyebilirsin. İstersen
normal diziliş yerine **kendi kurduğun pozisyondan** başlarsın.

**PGN yükle** — Bir dosyadan ya da panodan yapıştırarak. Bir dosyada
istediğin kadar oyun olabilir: oyunlar listelenir, seçtiklerini **yeni bir
liste olarak kaydedersin** ya da **var olan bir listeye eklersin**.
Başlıklar ve `[FEN]` ile başlayan oyunlar okunur. Yorumlar, varyantlar ve
NAG işaretleri ana hattı bozmadan ayıklanır: dosya sorunsuz açılır, ama bu
bilgiler saklanmaz ve uygulamada görünmez. Hamlesi olmayan, yalnızca
pozisyon taşıyan oyunlar listeye alınmaz. Uzun dosyalarda ilerleme çubuğu
görünür, uygulama donmaz.

**Serbest tahta** — İki tarafı da senin oynadığın analiz tahtası.

**Pozisyon kur** — Taş paleti, hamle sırası, rok hakları ve geçerken alma
karesiyle tam bir pozisyon düzenleyici. FEN alanına doğrudan yazabilir ya da
panodan yapıştırabilirsin. Kurduğun pozisyonu analiz eder ya da motora karşı
oynarsın; menüden tahtayı PNG olarak kaydedebilirsin.

---

## Tahta ekranı

Taşları sürükleyerek ya da önce taşa, sonra hedef kareye dokunarak
oynarsın. Terfi ederken hangi taşı istediğin sorulur.

**Motor analizi** — Sağ üstteki grafik simgesiyle açılır. Tahtanın
altındaki satırda skor, ana varyant ve arama derinliği görünür; en iyi
hamle de tahtada ok olarak çizilir. Motor ayrı bir süreçte çalışır, tahta
akıcı kalır. Motora karşı oyunda ok yalnızca senin sıranda çizilir.

**Gezinme** — Hamle listesindeki herhangi bir hamleye dokunarak o konuma
gidersin; alttaki düğmelerle bir ileri, bir geri, başa ya da sona gidersin.

**İşaretleme (fare ile)** — Bir kareye **sağ tıklamak** o kareyi işaretler;
**sağ tuşu basılı tutup sürüklemek** iki kare arasına ok çizer. Aynı yere
yeniden sağ tıklamak işareti kaldırır, sol tık hepsini siler. İşaret rengi
seçili tahtadan türetilir, bu yüzden her tahtada seçilir.

**Deneme hamleleri** — Kayıtlı bir oyuna bakarken tahtaya istediğin hamleyi
oynayıp motorun değerlendirmesinin nasıl değiştiğini görebilirsin. Bu
hamleler oyunun kendisine yazılmaz: hamle listesinde görünmez, PGN'e girmez,
kaydedilmez ve ekrandan çıkınca kaybolur. Şeritteki düğmelerle son denemeyi
geri alır ya da oyuna dönersin.

**Motor okları** — Analiz açıkken motorun önerisi ok olarak çizilir.
Tahtanın kendi vurgu rengini kullanır ama senin çizdiğin oktan daha ince
ve daha sönüktür: seninki kasıtlı bir not, motorunki her hamlede değişen
bir öneridir. Oklar Ayarlar'dan kapatılabilir.

**Tahta başındayken ekran kapanmaz**, düşünürken sönmesin diye. Hamle
yapılmadan yarım saat geçerse ve oyun bittiğinde bırakılır.

Menüden ayrıca: **tahtayı görsel olarak kaydetme**, PGN kopyalama, FEN
kopyalama/yapıştırma, listeye kaydetme, tahtayı çevirme ve **pes etme**.

**Sesler** — Hamle türüne göre farklı ses çalar (kendi hamlen, rakibin
hamlesi, alma, rok, terfi, şah). Kural dışı hamle uyarısı yalnızca **şah
altındayken** duyulur; oradaki anlamı "bu hamle şahı kurtarmıyor"dur.
Şah yokken geçersiz bir kareye tıklamak sessizdir.

---

## Bulmacalar

Uygulama hazır bulmaca ile gelmez; listeleri kendin oluşturursun.

**Liste oluşturma** — Sağ üstteki **+** ile yeni bir liste açarsın. Adı
verirken listeyi **oyun sonu listesi** olarak da işaretleyebilirsin; bu
işaret sonuç filtrelerini açar (aşağıda). Sonradan da liste menüsünden
değiştirilebilir. Listeyi üç yolla doldurabilirsin:

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

**Numaralar** — Her bulmacanın numarası **listedeki asıl sırasıdır**
(kaynak dosyada numara verilmişse o kullanılır). Süzgeç açıkken de,
sıralama ters çevrilmişken de aynı numara görünür; satırda, bulmaca
başlığında ve üstteki bilgi satırında hep aynı sayıyı okursun.

**Sıralama** — Liste baştan sona gelir; kitaptaki sıra neyse o. Başlık
çubuğundaki okla ters çevirip en son eklediklerini üste alabilirsin.
Süzgeci değiştirdiğinde sıralama baştan sonaya döner: ters sıralama
çoğunlukla tek bir bakış için açılıyor, filtre değişince o iş bitmiş
oluyor.

**Arama ve filtreler** — Tümü / çözülmemiş / çözülen / favoriler.
Liste oyun sonu listesi olarak işaretliyse ayrıca **beyaz
kazanır / beraberlik / siyah kazanır** filtreleri görünür; bir bulmacanın
sonucu satır menüsünden işaretlenir ya da alınan dosyada etiket olarak
verilir (`beyaz-kazanir`, `beraberlik`, `siyah-kazanir`; İngilizce yazımı
da tanınır).

Arama kutusu sıra numarası (`#128`), etiketler, ad, not ve FEN üzerinde
çalışır; Türkçe harflere duyarsızdır.

**Aralık işaretleme** — Menüdeki "Aralığı işaretle" ile iki numara arası
bulmacayı tek seferde çözüldü ya da çözülmedi yaparsın. Numaralar
filtreden bağımsızdır: ekranda gördüğün numarayı yazarsın.

**Bugün çözülen** — Gece yarısından beri kaç bulmaca çözdüğün, bulmaca
listeleri ekranındaki liste kartlarında görünür. Ayarlardan
kapatılabilir.

Menüden **tahtayı PNG olarak kaydedebilirsin**; dosya
`board-<liste adı>-<numara>.png` olarak kaydedilir. Her bulmaca yeniden
adlandırılabilir, pozisyonu düzenlenebilir, notu silinebilir ya da
tamamen kaldırılabilir.

---

## Açılışlar

Liste boş başlar; çalışmak istediğin varyantları kendin eklersin.

**Varyant ekleme** — Aile adı (ör. "İspanyol Açılışı"), varyant adı (ör.
"Breyer Varyantı") ve hamleler (SAN ya da PGN olarak yapıştırılabilir).
Her hamle kurallara göre doğrulanır; hatalı bir hamle varsa uyarı alırsın.
Eklediklerin aileye göre gruplanır: aynı aile adını yazarak bir ailenin
altına istediğin kadar varyant koyabilirsin. Varyant adını boş
bırakırsan o ailede sıradaki numarayı alır.

**Düzenleme** — Eklediğin bir varyantın adını, ailesini ve hamlelerini
satır menüsünden değiştirebilir, notunu silebilir ya da varyantı
kaldırabilirsin.

**Başlığı silme** — Bir açılış başlığının yanındaki menüden o başlığın
altındaki bütün varyantlar tek seferde silinir; kaç varyant gideceği
sorulur. Bir dosyadan yüzlerce varyant aldıysan tek tek silmek iş
görmüyor. Silinen varyantların ilerlemesi ve notu da temizlenir.

**Gizleme** — Başlık menüsündeki **gizli açılışlar** ekranından, şu an
çalışmadığın başlıklar listeden kaldırılır; ana ekranda yalnızca
çalıştıkların kalır, gizlenenler silinmez. Satırın sonundaki göz o
başlığı tek başına gizler. Kutucuklar seçim içindir: birkaç başlık
seçip **seçilenler hariç hepsini gizle** dersen geriye yalnızca onlar
kalır, **seçilenler hariç hepsini göster** ise tersini yapar. Hiçbir şey
seçili değilken aynı iki komut *hepsini gizle* ve *hepsini göster* olur.
Gizlilik aile adına bağlıdır, açılış kimliğine değil; dosyayı yeniden
alsan da yerinde kalır.

**Hepsini silme** — Başlık menüsündeki **tüm açılışları sil**, varyantlarla
birlikte ilerlemeni ve notlarını da siler. Geri alınamaz, kaç varyantın
gideceği sorulur.

**Tüm verileri sıfırla** — Ayarlar → Yedekleme altında, kırmızı yazılı.
Listeler, bulmacalar, açılışlar, ilerleme ve ayarların hepsini siler ve
onay ister; geri alınamaz. Android uygulamayı kaldırıp yeniden kurunca
eski veriyi Drive'dan geri getirdiği için sıfırdan başlamanın yolu bu.

**Metin dosyası** — Açılış listesi başlık menüsünden dosyaya verilir ve
dosyadan alınır. Aynı dosya ikinci kez alındığında listede zaten bulunan
hamle dizileri atlanır, hiçbir şey ikiye katlanmaz; kaç tanesinin
atlandığı da söylenir. Farklı hamle sırasıyla aynı pozisyona varan iki
hat ayrı varyant sayılır. Biçim satır başına bir varyanttır:

```
C95|İspanyol Açılışı|Breyer Varyantı|1. e4 e5 2. Nf3 Nc6 3. Bb5 a6
İspanyol Açılışı|Breyer Varyantı|1. e4 e5 2. Nf3 Nc6 3. Bb5 a6
```

Yani `ECO|aile|varyant|hamleler` ya da ECO'suz üç alan.

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
- **Okundu işareti**: tek tek, tümü birden ya da **numara aralığı vererek**
  işaretleme; "okunmamış / okunan" filtresi. Okunan sayısı listeye girmeden
  kartta görünür.
- **Favoriler**: satırdaki yıldızla işaretlenir, kendi filtresi vardır.
- **Oyun filtrele** — başlık menüsünden. Beyaz oyuncu, siyah oyuncu ya da
  ikisi; biri boş bırakılabilir. **Renk fark etmesin** işaretlenirse tek
  ad o oyuncunun bütün oyunlarını, iki ad da o iki kişinin birbirine
  karşı oynadığı oyunları getirir. Yıl alanı PGN tarihine bakar. Sonuç
  beyaz kazanır, beraberlik, siyah kazanır ya da adı yazılan oyuncunun
  iki renkle de kazandığı oyunlar olabilir. Adlar gevşek eşleşir:
  büyük-küçük harf, Türkçe harfler ve kelime sırası fark etmez, adın
  bir parçası yeter ("carl" ile "Magnus Carlsen" bulunur). Açıkken
  üstteki şerit neyin filtrelendiğini ve kaç oyun kaldığını yazar.
- **Sıralama** başlıktaki okla tersine çevrilir; filtre değişince
  varsayılana döner.
- **Aralık göster**: listeyi belirli bir numara aralığına daraltır, üstteki
  şeritten kapatılır.
- Kartta oyuncuların soyadları görünür (çevrimiçi kullanıcı adları
  olduğu gibi kalır); asıl adlar kayıtta durur, arama ve filtre onlara
  bakar. Beyaz üstte, siyah altta; beyazın kaç hamle yaptığı yazar;
  PGN'de tarih varsa o da yazılır (tam tarih yoksa yalnızca yıl, yıl
  da yoksa hiçbir şey).
- Satır menüsündeki **oyun bilgileri** PGN başlıklarını gösterir: turnuva,
  yer, tur, ECO, derece.
- Oyunlara not düşebilir, notu sonradan silebilirsin.

## Yedekleme ve cihaz değiştirme

**Ayarlar → Veri → Tüm veriyi yedekle** uygulamanın sakladığı her şeyi tek
bir `.json` dosyasına yazar: oyun listeleri ve içindeki oyunlar (okundu,
favori, not), bulmaca listeleri ve ilerlemen (çözüldü, favori, deneme
sayısı, çözüm tarihi), eklediğin açılışlar ve açılış ilerlemen, bütün
ayarlar.

Dosya düz metindir ve platforma özgü hiçbir şey içermez; telefonda
alınan yedek bilgisayarda, bilgisayarda alınan yedek telefonda olduğu
gibi açılır.

**Ayarlar → Veri → Yedekten geri yükle** ile dosyayı seçersin. Önce
dosyanın içindekiler özetlenir (kaç liste, kaç oyun, kaç bulmaca, kaç
açılış) — yanlış dosyayı seçtiysen veri silinmeden fark edersin. Sonra
iki seçenek sunulur:

- **Birleştir** — Yedektekiler var olanın üstüne eklenir. Aynı kayıt iki
  tarafta da varsa yedekteki geçerli olur, cihazın ayarlarına
  dokunulmaz.
- **Değiştir** — Cihazdaki veri silinir, yerine yedektekiler konur. İki
  cihazı birebir aynı yapmak içindir; ayrıca onay sorar.

Dosyanın içine bir sağlama damgası yazılır: yarım inen ya da bozulan bir
yedek yüklenmeden önce fark edilir. Yazma sırasında bir şey ters
giderse eski veri geri konur.

**Uygulama silinince verisi de gider.** Android'de veri buluta
yedeklenmez ve yeni telefona aktarılmaz, yeniden kurulunca uygulama boş
açılır. Windows'ta kaldırma sırasında kayıtlı oyunların, listelerinin ve
ayarlarının da silinip silinmeyeceği sorulur. Saklamanın yolu bu dosya:
silmeden önce yedek al.

---

## Ayarlar

- **Tema** — koyu, açık ya da sistemi izle. Varsayılan: sistemi izler.
- **Dil** — sistem, Türkçe, İngilizce.
- **Tahta görünümü** — 32 seçenek:
  - **12 düz renk** (kahve, yeşil, turnuva, mavi, gri, arduvaz, kum,
    mor, fildişi, gül, deniz yeşili, gece mavisi) — görsel dosyası
    yoktur, doğrudan çizilir, her ölçüde keskin çıkar.
  - **3 ahşap** (koyu ahşap, ceviz, meşe) — bu proje için üretildi.
  - **17 doku**: dört ahşap, iki akçaağaç, mermer, mavi mermer, taş,
    metal, deri, kanvas, zeytin, yeşil plastik, pembe piramit, mor
    çizgi ve horsey.
- **Taş takımı** — 16 seçenek: Cburnett (varsayılan), Chessnut, RhosGFX,
  Fantasy, Spatial, Celtic, Kiwen Suwi, Firi, Totoy, Papercut, Merida,
  Mono, Letter, Pirouetti, Pixel, MPChess.
- **Kare adlarını göster** — koordinatların rengi seçtiğin tahtadan
  gelir: yazı, üzerinde durduğu karenin karşıt rengini alır. Taş ve
  mermer gibi iki kare rengi birbirine yakın olan tahtalarda yazı
  kaybolmasın diye karşıtlık ölçülür ve gerekirse siyah ya da beyaza
  düşülür.
- Yasal hamle göstergeleri, son hamle vurgusu, hamle animasyonu,
  motor okları.
- **Bugün çözülen sayısı** — bulmaca listesi kartlarında günlük sayacı
  gösterir.
- **Hamle sesleri** ve **titreşim** — titreşim yalnızca telefonda
  bulunur; sesler kapatılınca titreşim de kapanır ve ses yeniden
  açılana kadar açılamaz.
- **Veri** — yedek alma ve geri yükleme (yukarıya bakın).

Seçtiğin tahta ve taş takımı yalnızca oyun tahtasında değil, bulmaca ve
oyun listelerindeki küçük önizlemelerde de kullanılır.

---

## Kurulum

**Android** — APK dosyasını telefona kopyalayıp açın. Bilinmeyen
kaynaklardan kuruluma izin vermeniz gerekebilir.

**Windows** — `Chess Library <sürüm> Kurulum.exe` dosyasını çalıştırın.
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

Proje [AGPLv3](LICENSE) lisanslıdır: özgür yazılımdır, isteyen satabilir,
isteyen değiştirebilir; ancak uygulamayı alan herkes kaynak koduna da
erişebilmeli ve değiştirilmiş sürümler aynı lisansla dağıtılmalıdır.
Nedeni ve ayrıntısı [COPYRIGHT.md](COPYRIGHT.md) dosyasındadır.

Taş takımları dışarıdan alınmıştır; çizenleri ve lisansları için
[ASSETS.md](ASSETS.md) dosyasına bakın.

---

Kaynaktan derlemek için [BUILD.md](BUILD.md), ses ve görsellerin nasıl
üretildiği için [ASSETS.md](ASSETS.md) dosyalarına bakın.

Her sürümle birlikte Türkçe ve İngilizce bir kullanım kılavuzu da PDF
olarak yayımlanır.
