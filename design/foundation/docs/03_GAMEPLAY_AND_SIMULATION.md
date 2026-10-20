# 03 — Oynanış çekirdeği ve simülasyon beklentisi

## Oyuncunun yapacağı ana iş

**Döngü:** Bir şehir ihtiyacını/fırsatını fiziksel dünyada gör → yerel proje, imar, bütçe veya politika kararı al → ilgili kamu kurumları, özel aktörler ve vatandaşlar tepki versin → şehir ekonomik/mekânsal olarak değişsin → ortaya çıkan kazanç, maliyet ve siyasi sonuçlardan yeni gündem doğsun.

Bu döngü yalnızca göstergelerde değil, **oyunun 3D şehrinde** anlaşılmalıdır.

## Üç etkileşim modu (oynanış yönü; nihai UI değil)

**1. Doğrudan belediye inşası:** Yollar, bulvarlar, kavşaklar, meydanlar, parklar, belediye tesisleri, belediyenin yetki alanındaki altyapı ve ulaşım yatırımları. Oyuncu harita üzerinde gerçek çizim/yerleşim eylemleri yapar. Yer seçimi, bağlantı ve fiziksel biçim önemlidir.

**2. Planlama ve imar:** Arazi kullanımı (konut/ticaret/karma/sanayi/tarım/koruma vb.), yoğunluk, yükseklik ve gelişme koşulları belirlenir. Belediye her özel apartman, dükkân veya fabrikayı doğrudan var etmez.

**3. Siyasi ve ekonomik yönetim:** Bütçe, yatırım önceliği, hizmet kapasitesi, yasal yetki, meclis desteği, teşvikler, çıkar çatışmaları, seçimler, bölgesel ortak projeler. Bürokrasi oyunun yaratıcı inşa hissini boğmamalı.

## Yaşayan kentin en küçük anlamlı modeli

**Hanehalkları:** Barınma, gelir/istihdam, erişim, hizmet ve çevre koşullarına tepki verir; taşınır, talep yaratır.  
**İşletmeler / yatırımcılar:** Talep, işgücü, imar, erişim, maliyet, piyasa ve finansman koşullarına göre yatırım, faaliyet, büyüme, küçülme veya kapanma kararı alır.  
**Arsalar / yapılar:** Konum, mülkiyet, imar, yapı kapasitesi, erişim ve mevcut kullanımla tanımlıdır; gelişme kademelidir.  
**Altyapı ağları:** Yeni konut/üretim bölgelerinin koşullarını mümkün kılar veya kısıtlar; bakım ve kapasite maliyeti doğurur.  
**Yerel yönetimler / siyasi aktörler:** Hizmet ve yatırım kararları alır; toplumsal ve ekonomik etkiler siyasi geri bildirim üretir.  
**Makroekonomi ve diğer bölgeler:** Ülke ekonomisi, faiz/finansman, fiyat, taşımacılık, turizm ve mevzuat çevresel koşulları değiştirir; diğer altı metropol soyut biçimde simüle edilir.

Bunlar bağımsız, sonsuz karmaşık simülatörler zorunluluğu **değildir**. Oyuncunun gözlemleyebildiği, tutarlı nedensellik kuracak kadar modellenmeleri gerekir. Kesin veri şemaları, algoritmalar ve simülasyon sıklıkları açıklanmış değildir.

## Somut bir mahalle inşası örneği

Oyuncu seçtiği ilçede yeni karma kullanımlı bir mahalle planlar:

1. Ovanın/topoğrafyanın, mülkiyetin ve yol erişiminin durumunu görür.
2. Ana cadde ve ara sokakları çizer; parsel veya gelişme alanları ortaya çıkar.
3. Konut/ticaret yoğunluğunu ve park/kamu alanlarını belirler.
4. Su, atık, elektrik ve toplu ulaşım kapasitesini planlar; bütçe ve süre ayırır.
5. Talep uygunsa özel geliştiriciler yatırım kararı verir; inşaat süreci ve yeni binalar görünür.
6. Mahalle doldukça trafik, kira, işyeri talebi, hizmet ihtiyacı ve yerel siyasi gündem değişir.

**Kritik:** Altyapı kurmak otomatik ve sihirli biçimde doğru binayı spawn etmek demek değildir. Hiç yatırım olmayabilir, yanlış yoğunluk seçimi belediye bütçesini zorlayabilir; aşırı talep spekülasyon yaratabilir.

## Şehir kurmanın özgürlüğü

Aynı T0'dan iki oyuncu önemli ölçüde farklı bir şehre ulaşabilir: biri merkezi yüksek yoğunluklu ticaret/hizmet ekonomisi kurarken diğeri çok merkezli, orta yoğunluklu mahalleler ve raylı ulaşım planlayabilir; bir başkası liman üretimini modernize edip büyütebilir. Bu sınıflar veya tamamlanması gereken görev ağacı **değildir**. Sonuç, arazi ve ekonomik/politik sistemlerin karşılıklı etkileşiminden doğar.

**Oyuncu mimar değildir:** Özel binaların tüm mimari parçalarını yerleştirmek zorunda kalmaz. **Ama belediye başkanı olarak şehir formunda güçlü fiziksel ajansa sahip olmalıdır:** yol, imar, kamusal mekân, altyapı, yoğunluk ve dönüşüm.

## Politik gelişme ve yetki

**İlçe belediyesi:** Kendi seçim bölgesindeki hizmetler, fiziksel gelişme, yerel planlama ve kamu yatırımları. Diğer ilçeleri istediği gibi yönetemez.  
**Metropol yönetimi:** İlçeler arası yol ve toplu ulaşım, bölgesel ekonomi, büyük ölçekli projeler ve koordinasyon; alt belediyeler yine paydaştır.  
**Merkezi devlet:** Mevzuat, makroekonomi, ulusal yatırım/politika ve siyaseti etkiler. Oyunun içinde var ama cumhurbaşkanlığıyla ayrı oynanabilir devlet yönetimi aşamasına geçilmez.

Bu bir hukuki yetki tablosu değil; **oynanış sınırları**. Tam yetkiler, yerel yönetim modeli, meclis usulleri, siyasi partiler, seçim takvimi, mali ilişkiler henüz kararlaştırılmadı.

Siyasi ilerleme: popülerlik tek skora indirgenmez. İtibar, sicil, koalisyonlar, çıkar grupları, medya, halk desteği, seçim sonucu ve kaybetme ihtimali ilişkilidir. Oyuncunun başarısı sadece binaların sayısıyla ölçülmez.

## Kent oyuncu bakmıyorken de evrilir

Oyuncu Orven'deyken D1, D3, D4, D5, D6 **donup kalmaz**. Diğer belediyeler, yatırımcılar, hanehalkları ve makro koşullar buraları değiştirir. Oyuncu metropol yönetimini devraldığında yıllarca yaşanmış değişimleri, sorunları, başarılı ve başarısız yatırımları devralır. Ekonomik/politik etkileşimi gerektiği ölçüde soyutlamak serbesttir; her ilçenin tüm 3D sokağını aynı anda yüksek maliyetle çalıştırmak zorunlu değildir.

Bir kampanyada karakter ve dünya durumu makam değişiminde sıfırlanmaz. Diğer bölge kampanyaları bağımsızdır.

## Oyun temposu için önerilen yaklaşım

- Durdurulabilir / hızlandırılabilir şehir zamanı; gündelik yapı faaliyetleri ile aylar/yıllar süren büyüme birlikte anlaşılır.
- Uzun planlama seanslarını sürekli siyasi pop-up'larla kesmeyen **kesintisiz city-building akışı**.
- Kararın etkisini zamana yayan yatırım, inşaat, göç, iş yaratımı ve kamu bütçesi.
- Meclis, seçim ve büyük gündemleri anlamlı dönemsel olaylar olarak ele alma.

**Statü: çalışma önerisi.** Zamanın gerçek süresi, seçim sıklığı, ekonomik matematik, arayüz şemaları ve mikro yönetim sınırları kesinleşmedi.

## Oyun hissi için doğrulanması gereken kabul ölçütleri

Bir erken oynanabilir dilim, seçilen bir gerçek kentsel parçada şu bütünlüğü gösterebilmeli:

- Mevcut bir yerleşim dokusu ve doğal/topografik çevre hissedilir; boş grid üzerine 4 blok konmuş gibi görünmez.
- Oyuncu yol/imar/kamu alanı kararını **fiziksel 3D dünyada** uygular.
- Özel geliştirici ya da hane davranışı oyuncunun kararıyla ilişkili ama otomatik olmayan yanıt üretir.
- Yerel nüfus/iş/ulaşım/bütçe değişimleri anlamlı ve görünürdür.
- En az bir karar gerçek siyasi/toplumsal tepki oluşturur.
- Oyuncu aynı alanı farklı zoom'larda aynı dünya olarak görebilir.
- Örnek ilçe, gelecekteki bütün ilçeler için zorunlu başlangıç yeri haline getirilmez.

Bunlar **tasarım kalite hedefleri**; mevcut kodun geçtiği testler veya Claude için zorunlu geliştirme planı değildir.
