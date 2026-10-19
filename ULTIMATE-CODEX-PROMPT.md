# BAŞLANGIÇ GÖREVİ — İzmir esintili belediyecilik tycoon (iPad)

Bu, boş bir repoda sıfırdan başlayacak **oynanabilir bir oyun prototipi geliştirme görevi**. Yalnızca doküman, HTML mockup, konsept çizim veya statik 3D diorama istemiyorum. Çalışan Godot projesi, ilk gerçek oyun döngüsü, doğrulanmış kontroller ve gerçek çalışma görüntüleri istiyorum.

## 0. Üst düzey rolün ve çalışma şeklin

Deneyimli bir game director, simulation designer, Godot 3D engineer ve interaction designer gibi karar ver. Teknik ayrıntıları bağımsız çöz; ancak belirttiğim yaratıcı yönü yeniden yorumlayarak başka oyuna çevirme. **Bu projede doğru ilk temel, mümkün olan en çok özelliği çıkarmaktan önemlidir.**

ÖNEMLİ: Projeyi "başlangıç için jenerik şehir kurma oyunu"na dönüştürme. Önce referans görüntüleri gerçekten incele. Görsellerin ve simülasyonun aynı ürüne ait olduğunu hissettiren, küçük fakat bütünlüklü bir vertical slice kur. Planlama aşamasında takılı kalma; planın ardından kodla, çalıştır ve doğrula. Adım adım uygula, sorun çıktığında erken raporla; başarısız temelin üzerine yeni özellik yığma.

## 1. Oyunun vazgeçilmez kimliği

Tür: **Belediye başkanlığı perspektifinden oynanan, otonom özel sektörlü, politik katmanlı, yerel belediyecilik / şehir ekonomisi tycoon'u.**

Ortam: Türkiye'nin Ege kıyılarından, özellikle İzmir'in gündelik kent yaşamından esinlenen KURGUSAL bir ilçe. Gerçek siyasetçileri veya kurumsal logoları taklit etme. Mahalle ölçeğinde Türk kent dokusu, yerel işletmeler, apartmanlar, ulaşım ve belediye hizmetleri.

Oyuncunun rolü: İlçenin belediye başkanı. Oyuncu her binayı kendisi doğrudan inşa edemez. İmar koşullarını, kamusal yatırımları, bütçe önceliklerini ve yerel politikaları belirler. Arazi sahipleri, yatırımcılar, işletmeler ve vatandaşlar **kendi** hedefleriyle tepki verir. Şehir bu kararların etkileşiminden gelişir. Siyaset, ekonomiden ayrı kart oyunu değil; kararların şehre ve halka yansıdığı bir katmandır.

Temel oyun fantazisi: "Bir imar kararını değiştiriyorum, yatırımcının davranışı farklılaşıyor, gerçek bir inşaat başlıyor, mahalle değişiyor, ekonomide ve halk tepkisinde yeni bir sonuç ortaya çıkıyor." Bunun nedenselliği görülebilir ve sorgulanabilir olmalı.

Bütünleşik ilke: **Mayor influences the city; the city lives independently.** Oyuncu tanrı-modunda bireysel konut veya market spawn etmez. Minecraft tarzında serbest blok yerleştirme oyunu da değildir.

## 2. Sanat yönetimi: ekran görüntülerinden başlamalısın

`references/` klasöründe 8 görsel var. Bunlar çizim isteği değil, şu ana kadar kullanıcı tarafından onaylanan oyunun görsel yönünü anlatan **referanslar**. Her birini tek tek görsel olarak incele; görselleri sahne arka planına yapıştırma ve render edilmiş illüstrasyonları oyunmuş gibi sunma.

- `01-world-direction.jpg` — referans geometri, mat yüzeyler, sade yapı kütleleri, Ege kıyısı ve izometrik görüş.
- `02-neighborhood-zoom.jpg` — yakın mahalle ölçeği, apartman, sokak köşesi ve yerel işletme.
- `03-game-hud.jpg` — genel oyun HUD'ı için örnek; BİREBİR kopyalama (özellikle doğrudan Residential build araçlarını).
- `04-mayor-local-decision.jpg` — zoomlu mahalle kararı, esnaf ve vatandaş görüşü.
- `05-council-perspective.jpg` — belediye başkanı/yerel meclis karakterleri ve politik layer için ileriye dönük örnek.
- `06-rain-and-traffic.jpg` — şehirde sorunlar ve hava koşulları var; yalnızca kartpostal şehri değil.
- `07-on-site-crisis.jpg` — zoomlu, yerel belediye kriz ve müdahale senaryosu.
- `08-policy-conflict.jpg` — imar, özel yatırım ve mahalle taleplerinin çatışması.

GÖRSEL KURALLAR:

1. **Basitleştirilmiş blok/prizma tabanlı low-poly 3D**: Minecraft'ın geometrik sadeliği ile Roblox'un canlı, modern ve dinamik sahne hissi arasında. Tam voxel/tüm nesneler küp değil; pürüzsüz fotogerçekçi değil. İyi ayarlanmış oranlar, faceted ağaçlar, sade araçlar ve stilize NPC'ler.
2. **İzometrik/ortografik oyun kamerası**; yukarıdan mahalleyi ve imar parsellerini okunur kıl. Yatay/dikey pan, yumuşak zoom ve açıyı koruyarak dönüş. Uzak şehir görünümü İLE yakından sokak incelemesi **aynı gerçek 3D dünyada** çalışsın. Tek sabit sahil-bulvarı kamerasına kilitlenme.
3. **İzmir hissi ikonik landmark kopyalamakla değil, sıradan kent dokusuyla gelsin**: 4–7 katlı balkonlu apartmanlar, zemin kat bakkal/kafe/fırın, küçük tenteler, düz çatılar, birkaç güneş enerjisi deposu/klima, dar sokak ve yer yer sahil/tramvay. Bunların her birini her binaya uygulama. İşaretleyici özellikler az ve yerinde olsun.
4. Son konsept resimlerindeki yoğunluk bile nihai runtime için **üst sınır**. Tekrarlayan ayrıntıları azalt. Dekorasyon, saksı, korkuluk, çiçek, insan, otomobil, sokak mobilyası ile her santimetreyi doldurma. Basit blok kütleler ve güçlü kentsel siluet; oyun ölçeğinde okunabilirlik öncelikli.
5. Gösterişli altın saat/gün batımı render'ı tek varsayılan olmasın. Başlangıçta sade gün ışığı, atmosferik gölgeler; ayrıca bulutlu/yağmurlu alternatif durum gösterebilen tasarım. Mevsim ve afet simülasyonunu ilk sürümde tam kurmaya çalışma.
6. Ton: modern, yerel, hafif nükteli, sakin, karakterli. Jenerik ABD downtown'u, steril Akdeniz tatil köyü, aşırı renkli çocuk oyunu, çizgi film platformer'ı, fotogerçekçi şehir posteri veya hazır asset marketplace estetiği değil.
7. **Ekranda gerçek geometri, gerçek dünya koordinatları ve gerçek etkileşim** olsun. Yapay zekâ görsellerini gameplay texture'ı veya fake screenshot olarak kullanma.

## 3. İlk oyunun kapsamı — küçük fakat gerçek vertical slice

Yalnızca **tek bir kurgusal Ege mahallesi** oluştur: kabaca 3–5 yol adası, 24–40 seçilebilir parsel; bunun bir kısmı apartman, zemin kat iş yeri, küçük meydan, yeşil alan, boş/eskiden sanayi kullanımlı arsa ve kamusal hizmet alanı olsun. Bu sayılar üst hedef, ihtiyaç halinde daha küçük ama **ikna edici** bir sahne oluştur. Görsel olarak tutarlı bir mahalle olmalı; grid üzerinde rastgele kutular dizisi olmasın.

Minimum gerekli öğeler:
- Birkaç farklı apartman kütlesi, balkon ve giriş detayları; iki ayrı zemin kat işletmesi (ör. bakkal ve kafe) ve tek küçük kamusal alan.
- Parsellerde kimlik, koordinat, mevcut kullanım, mülk sahibi, imar hakkı, yaklaşık arazi değeri, doluluk ve gelişim durumu.
- Oyuncunun seçebildiği parsel/bölge ve **imar değiştirme** eylemi (konut, karma kullanım, ticaret, yeşil/kamu alanı gibi ufak ama anlamlı küme).
- En az **iki davranışı farklı özel yatırımcı profili** (ör. konut geliştiricisi ve ticari geliştirici). Bu aktörler başkanın direkt kontrolünde değil; koşullar elverişliyse fırsatı değerlendirir.
- Oyunda akan zaman (duraklat / 1x / hızlandır), buna bağlı yatırım değerlendirmesi ve inşaatın görünür safhaları: boş arsa → şantiye → tamamlanmış bina.
- Basitleştirilmiş ama nedensel ekonomi: arazi maliyeti, geliştirme gideri, talep, erişilebilirlik, beklenen getiri gibi az sayıda açıklanabilir değişken. Tüm kararlar deterministik/seed'lenebilir biçimde test edilebilir olsun. Tam makroekonomik model veya her bireyi simüle eden AI gerekmez.
- Belediye bütçesi ve belediye politikasına bağlı gelir-gider değişimi; iki ya da üç farklı kesimin (ör. mahalle sakinleri, esnaf, yatırımcılar) farklı tepkileri. Tek ve sihirli "Happiness %" metriğiyle tüm toplumu temsil etme.
- Belediye başkanı deneyimini hissettiren **bir gerçek karar akışı**: imar teklifi → varsa basit meclis onayı/karar süreci → yatırımcı değerlendirmesi → zaman içinde fiziksel ve ekonomik sonuç → mahalle tepkisi. Meclis tarafını ilk iterasyonda çok küçük ama tutarlı kurabilirsin; sahte veya dekoratif oylama yapma.

**Kanıtlanması gereken ilk oyun döngüsü:**
1. Başlangıçta mevcut kullanımı kısıtlı/boş bir özel parseli seçerim.
2. Belediye başkanı olarak imar değişikliği teklif ederim. Gerekli karar/onay görünebilir.
3. Zaman ilerlerken yatırımcı koşulları kontrol eder. Koşullar uygunsa arsaya ilgi gösterir ve bir proje başlatır; değilse neden yatırım yapmadığını görürüm.
4. Yatırım olduğunda sahnede yeni inşaat ilerler ve bina tamamlanır. Bu oyun mantığının sonucudur; önden hazırlanmış zamanlayıcılı animasyon numarası değildir.
5. Konut/iş yeri kapasitesi ve belediye bütçesi gibi değerler değişir; bazı sakinler/işletmeler olumlu, bazıları olumsuz etkilenebilir.
6. Mahalleye zoom yapıp tekil parselin ve belediye kararının sonuçlarını inceleyebilirim.

Sistem rastgele her talebe olumlu cevap vermemeli. Parametreleri görünür kıl ve en az bir olumlu ve bir olumsuz senaryo üret.

## 4. Oynanış ve iPad UX

Hedef **iPad landscape, touch-first**, desktop geliştirmeye elverişli. Başta temel mouse/trackpad eşlemelerini de uygula.

- Bir parmak/drag pan, pinch zoom, iki parmak veya açık bir kontrol ile rotate; desktop'ta sezgisel alternatifleri. Gesture çakışmalarını önle.
- Makro şehir görünümü, yakın mahalle inceleme, parsel seçimi ve başkan kararı arasında kesintisiz geçiş.
- Menü hiyerarşisi yönetim odaklı: **İmar, Belediye, Bütçe, Mahalle** gibi. Oyuncu "Residential" butonuyla doğrudan apartman çizemez; bunu özellikle reddediyorum.
- UI yerleşimi gerçek iPad çözünürlüklerine ve güvenli alanlara uysun. Dock ve paneller şehri gereksiz kapatmasın. Dokunma hedefleri en az yaklaşık 44pt; düzgün font ölçekleri ve kontrast.
- Başlangıç dili **Türkçe** ve para birimi **₺**. Referanslarda yanlışlıkla görünen € işaretlerini, İngilizce HUD etiketlerini veya alakasız gerçek kurum markalarını kopyalama.
- HUD sadece gerçek simülasyon datasını göstersin. Fonksiyonsuz buton, gösteriş için rakamlar ve çalışmayan seçim kartları koyma. Henüz var olmayan alt sistemleri sakla veya açıkça geliştirme dışı tut.
- Mahalle sakinleri, esnaf ve yatırımcıları yalnızca emoji/çok genel barlar olarak düşünme; bir kararın niçin desteklendiğine veya karşı çıkıldığına dair kısa, nedensel açıklamalar göster.

## 5. Teknik kalite ve mimari

Motor: bilgisayarda kurulu veya kurulabilir **güncel kararlı Godot 4**, GDScript. Başlangıçtan itibaren iPadOS export hedefle, fakat ilk doğrulamayı desktop ortamında yap. Renderer'ı bilgisayarın GPU/OS desteğine göre tespit edip seç; en ağır renderer'ı körlemesine açma. 2019 Intel MacBook Pro'da geliştirme, daha sonra fiziksel iPad'de test düşünülerek sınırlı draw call ve sade shader kullan. Ücretli asset, lisanslı 3D paket, backend, bulut hizmeti ya da API anahtarı gerektirme.

Özellikle:
- Simülasyon kuralları **rendering ve input'tan ayrı**. Game time tick üzerinden yürüsün; frame rate'e bağlı yatırım kararı olmasın.
- `GameState` / `Parcel` / `Owner` / `Investor` / `Development` / `Municipality` / `CitizenGroup` gibi küçük ve gerekçeli veri yapıları kur. Bunları başlangıç için bir framework fabrikasına dönüştürme.
- Referanslı test senaryosu ve seed ile tekrarlanabilir ekonomi; tasarımı sebep-sonuç testine açık tut.
- Tek dosyada dev Godot script'i veya tüm sahnenin tek bir anlık mesh olarak donması olmasın. Ama aşırı component/ECS altyapısı da kurma.
- Üretilen mahalle yeniden açıldığında aynı kimliğe sahip olsun. Basit save/load mümkünse ekle; fakat görsel ve ilk ekonomik döngüyü bitirmeden buna odaklanma.
- Oyuncuya görünen öğelerde *placeholders* ancak bilinçli ve dürüst olmalı. Sahte dinamik veri ve sahte oynanış yok.

## 6. Teslim beklentileri ve kalite kapıları

**A. Önce referansları incele:** Başlamadan önce kısa bir `docs/ART-DIRECTION.md` yaz: 7–10 olumlu kural, 7–10 yasak, iki zoom seviyesi ve ekran kompozisyonu. Kaynak görüntü adlarını somut biçimde eşleştir. Bu dosya bir sayfayı geçmesin.

**B. Kısa mimari:** `docs/TECH-DIRECTION.md` içinde önemli teknik seçimler, ilk oyun döngüsü, veri modeli ve performans riski. Bir sayfalık plan yeterli. Bu belgeler üretimi ERTELEMEK için değil, yanlış başlangıcı önlemek için.

**C. Önce görsel kalite kapısı:** İlk sahneyi/3D haritayı kur, Godot'ta çalıştır, mümkünse ekran görüntüsü al. Aynı sahneden en az genel görünüm ve yakın mahalle görünümünü kaydet. Gerçek ekran görüntülerini `artifacts/screenshots/` içine koy. İkisi de jenerik kutu prototipi gibi görünüyorsa makyaj yaparak sürdürme: geometri/dünya kompozisyonunu erken yeniden kur. Referanslara yaklaşmıyorsa sorunu net raporlayıp kalan büyük özelliklere geçme.

**D. Sonra gerçek sistem:** İlk ekonomik-siyasi oyun döngüsünü kur. Veri üretimi ile render'ı bağla, gösterilecek değerleri hesapla; seed'li olumlu/olumsuz geliştirme senaryolarını test et. Ekonomik sistem yokken "Investors: 87%" gibi uyduruk gösterge çıkarma.

**E. Oyun içi doğrulama:** Godot import/parse/runtime hatalarını denetle. Simülasyon için otomatik test veya çalıştırılabilir smoke-test kur. Kamera, parsel seçimi, imar kararı ve inşaat akışını mümkünse manuel de test et. Öncesi/sonrası ekran görüntüleri ve test komutlarıyla ispatla. Görüntü alınamıyorsa üretildi diye iddia etme, nedenini yaz.

**F. Teslim:** `README.md` ile projeyi tek komut veya Godot editor'den açma adımları, kontroller, cihaz kısıtları ve neyin gerçekten çalıştığı. Kısa son raporda (1) tamamlananlar, (2) çalıştırma/test kanıtı, (3) görüntü yolu, (4) eksikler ve riskler, (5) ilk 10 dakikalık oynanışta kullanıcıdan alınacak geri bildirim. Repo değişikliklerini düzenli commit'lere ayır; izin/erişim yoksa remote'a push etme.

## 7. Kırmızı çizgiler / fail-fast

- **En önemli yanlış:** Güzel görünen ama oynanamayan diorama, render veya HTML imitasyonu.
- **İkinci önemli yanlış:** Jenerik SimCity klonu: oyuncunun tek tıkla özel bina yerleştirmesi.
- **Üçüncü önemli yanlış:** Politika ve ekonomiyle bağlantısı olmayan yalnızca değişen sayaçlar.
- **Dördüncü önemli yanlış:** Aşırı detaylı, pahalı, sürü gibi minik dekorasyonla dolu, tüm kadrajı kaplayan sahne. Kullanıcının daha önce reddettiği yön bu.
- **Beşinci önemli yanlış:** İlk etapta 12 mahalle, seçim kampanyası, tam trafik patikası, afet fizik simülasyonu, gerçek İzmir coğrafyası veya devasa senaryo motoru yapmaya kalkışmak.
- **Altıncı önemli yanlış:** Projenin hızını artırmak için doğrulamayı atlamak, test edilmiş gibi konuşmak.

İlk sahne görsel olarak yanlış temele oturursa bunu temiz bir başlangıç gerektiren kritik sorun olarak ele al; yama üstüne yama yaparak devam etme. Bütünü gören bir game director gibi kapsamı yönlendir.

## 8. Şimdi uygula

1. Ortamı incele (Godot, Git, mevcut repo, sistem özellikleri, asset dosyaları).
2. Referans görsellerini tek tek incele; kısa sanat/teknik yön belgelerini oluştur.
3. İyi görünen, farklı zoom seviyelerine sahip **gerçek 3D dünya ve input** üret. Test et.
4. Görsel kalite kapısını geçerse **ilk otonom yatırımcı + imar + belediye kararı + şehir değişimi** döngüsünü gerçekleştir. Test et.
5. Mümkünse gerçek desktop gameplay screenshot'ları oluştur ve çıktılarını raporla.

Senden "nasıl yapılır" açıklaması değil, **ilk günden doğru oyuna benzeyen, küçük ve gerçek çalışan bir başlangıç** istiyorum. Rutin seçimleri kendin yap; temel görsel vizyon veya oyuncu rolünü değiştirmeyi gerektiren bir belirsizlik varsa önce tek, somut soru sor. Diğer konularda başlamayı erteleme.
