# Telif ve lisans

Chess Library
Copyright (C) 2026 stranger-the-unknown

Bu program özgür yazılımdır: Özgür Yazılım Vakfı'nın yayımladığı GNU
Affero Genel Kamu Lisansı'nın 3. sürümü ya da (tercihinize bağlı olarak)
daha sonraki bir sürümü koşullarında yeniden dağıtabilir ve/veya
değiştirebilirsiniz.

Bu program yararlı olacağı umuduyla dağıtılmaktadır, ancak **hiçbir
garanti verilmez**; SATILABİLİRLİK ya da BELİRLİ BİR AMACA UYGUNLUK zımni
garantisi dahi yoktur. Ayrıntılar için GNU Affero Genel Kamu Lisansı'na
bakın.

Lisansın tam metni [LICENSE](LICENSE) dosyasındadır; ayrıca
<https://www.gnu.org/licenses/agpl-3.0.txt> adresinden edinilebilir.

---

## Neden AGPLv3?

Uygulama 3.0'a kadar MIT lisanslıydı. Taş takımlarının bir bölümü
GPLv2+ ve AGPLv3+ lisanslıdır; bunlar "bulaşıcı" lisanslardır, yani
içeren bütün eseri aynı koşullarla dağıtmayı gerektirirler. Bu
takımların uygulamaya katılabilmesi için lisans AGPLv3'e çevrildi.

AGPLv3, GPLv3'ün üstüne yalnızca bir şart ekler (§13): yazılım bir ağ
üzerinden kullanıcılarla etkileşiyorsa kaynak kodunun onlara sunulması
gerekir. Chess Library tümüyle cihazda çalışır, ağ erişimi yoktur; bu
şart pratikte hiç işlemez. GPLv3 yerine AGPLv3 seçilmesinin tek nedeni
AGPLv3+ lisanslı taş takımlarını da kapsayabilmektir.

**Değişmeyenler:** uygulama açık kaynak olmayı sürdürür, isteyen satabilir
(GPL ailesi ticari kullanımı yasaklamaz), isteyen değiştirebilir.

**Değişen:** uygulamayı alan herkes kaynak kodunu da isteyebilir ve
değiştirilmiş bir sürümü dağıtan kişi onu da AGPLv3 ile dağıtmak
zorundadır.

2.x sürümleri MIT olarak yayımlanmıştı; o sürümleri alanların hakları
değişmez. Lisans değişikliği 3.0.0 ve sonrası için geçerlidir.

---

## Satranç motoru

Uygulama **Stockfish 17**'yi içinde taşır ve motora karşı oyun ile oyun
incelemesini onunla yapar. Stockfish'in telif hakkı Stockfish
geliştiricilerine aittir ve **GPLv3** ile dağıtılır:
<https://github.com/official-stockfish/Stockfish>

GPLv3 ile AGPLv3 bir arada kullanılabilir; bu yüzden Stockfish'i
uygulamanın içinde dağıtmak lisans açısından sorun yaratmaz. Bu, birleşik
eserin özgür yazılım olarak kalmasını gerektirir — zaten öyle.

Stockfish'in NNUE değerlendirme ağları (`nn-*.nnue`) derleme sırasında
Stockfish projesinin sunucusundan indirilir ve aynı lisans altındadır.

Motor 3.0.0'a kadar bu proje için sıfırdan Dart ile yazılmıştı; o kod
depo geçmişinde duruyor.

## Varlıklar

Taş takımlarının çizeni ve lisansı [ASSETS.md](ASSETS.md) içinde tek tek
listelenmiştir. Sesler, uygulama simgesi ve tahta çizimi bu proje için
üretilmiştir ve uygulamanın lisansı altındadır.
