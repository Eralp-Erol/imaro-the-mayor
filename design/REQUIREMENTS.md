# Gereksinim izlenebilirliği

Kaynak: `design/foundation/` (F01–F06 = `docs/0N_*.md`). Statü sütunu foundation etiketidir: **K** kanonik · **OY** onaylanmış yön · **ÇM** çalışma modeli · **A** açık. **TEK** = kanon değil, ADR'dan gelen teknik gereksinim.
Kanıt sütunu yalnızca gerçek test/görüntü/oyun testi kanıtıyla doldurulur; "kod yazıldı" kanıt değildir. Her görev (`production/tasks/`) karşıladığı REQ kimliklerini listeler.

Kanıt seviyeleri: `—` yok · `T` otomatik test · `R` runtime ekran görüntüsü/video · `P` oyun testi (insan veya playtest-bot) · `U` kullanıcı onayı.

## Kimlik ve rol (CAN)

| ID | Gereksinim | Kaynak | Statü | Kanıt |
|---|---|---|---|---|
| CAN-01 | Adlar: Imaro: The Mayor, Anderva, Ismeral, Orven. Orven Ismeral'in ilçesidir; ayrı metropol veya zorunlu başlangıç değildir. Başka ad uydurulmaz. | F01, F05-A | K | — |
| CAN-02 | Tür: yaşayan city-builder + siyasi kariyer. Siyaset şehri oynanamaz tabloya çevirmez; city-building tek başına tatmin edici olmalı. | F01 sütun 1–2, F05-A | K | — |
| CAN-03 | Özel binalar (konut, dükkân, fabrika) yalnızca otonom ekonomik aktörlerin kararıyla oluşur. Oyuncu için god-mode özel bina yerleştirme yoktur. | F01, F03, F05-A | K | — |
| CAN-04 | Doğrudan belediye inşası: yol, bulvar, kavşak, meydan, park, belediye tesisi, yetki alanındaki altyapı ve ulaşım; harita üzerinde gerçek çizim/yerleşim, konum ve bağlantı önemli. | F03 mod 1 | OY | — |
| CAN-05 | Planlama/imar: arazi kullanımı, yoğunluk, yükseklik, gelişme koşulları. | F03 mod 2 | OY | — |
| CAN-06 | Siyasi/ekonomik yönetim: bütçe, yatırım önceliği, hizmet kapasitesi, yetki, meclis desteği, teşvik, çıkar çatışması, seçim, bölgesel projeler. Bürokrasi yaratıcı inşayı boğmaz. | F03 mod 3 | OY | — |
| CAN-07 | Ismeral kampanyasında aynı erkek protagonist: ilçe başkanı → metropol başkanı → ulusal mücadele → cumhurbaşkanlığı seçim zaferi = final. Ülke yönetimi oynanmaz. | F01, F05-A | K | — |
| CAN-08 | Oyuncu başlangıç ilçesini kendisi seçer; yalnızca gerçekten geliştirilmiş, oynanabilir ilçeler seçilebilir gösterilir. Orven zorunlu değildir; stüdyonun geliştirme test alanı seçimi oyuncu özgürlüğünü kısıtlamaz. | F01, F05-A, **D-002** | K | — |
| CAN-09 | Yedi bölge kampanyası ayrı protagonist/hikâye/kayıt; başarılar taşınmaz. Diğer bölgeler soyut ekonomi ve siyasetle etkindir. | F01, F05-A | K | — |
| CAN-10 | Kariyer seviye-puanı menüsü değildir: seçim, destek, itibar, müttefik, medya, sicil; kaybedilen seçim anlamlı sonuç doğurur. | F01, F03 | OY | — |
| CAN-11 | Makam değişiminde karakter ve dünya durumu sıfırlanmaz; aynı dünya daha geniş yetkiyle yönetilir. | F01, F03 | K | — |

## Dünya ve coğrafya (WLD)

| ID | Gereksinim | Kaynak | Statü | Kanıt |
|---|---|---|---|---|
| WLD-01 | Ülke, metropol, ilçe, sokak, insan ölçeği **tek fiziksel 3D coğrafya**dır; zoom'a göre farklı kıyı/dağ/yol/bina icat edilmez, ayrı diorama yoktur. | F02, F04, F05-A | K | — |
| WLD-02 | Ismeral: batıda körfez/kıyı, doğuda iç ova, güneydoğuda yamaç/yükselti; içinde altı çalışma bölgesi D1–D6 (kodlar resmî ilçe değildir). | F02, F05-B | OY | — |
| WLD-03 | T0'da eski batı limanı ve ilk ana sanayi **D4'ün batısındaki ana kara kıyısında**; T0 adalarında büyük liman/ana sanayi yok. Ada genişlemesi yalnızca ileride oyuncu kararıyla, asla zorunlu değil. | F02, F05-A | K | — |
| WLD-04 | T0: D1+D6 kompakt, gelişmiş kentsel çekirdek; D2–D5 daha az gelişmiş ama gerçek merkez, çarşı, konut, işyeri ve sokaklara sahip; aralarında tarım, yeşil kuşak, dönüşüm potansiyeli. | F02, F05-B | OY | — |
| WLD-05 | D1 ve D6 fiziken tek mahalleye dönüşmez; karşı kıyı ilişkisi ulaşım/feribot/ekonomiyle tanımlanır. Körfezi yok eden düzleştirme veya doldurma projeleri sabit/zorunlu karar değildir. | F02 | OY | — |
| WLD-06 | Her ilçe karma ekonomi taşır; hiçbir ilçe "sadece turizm/sanayi/tarım" değildir. | F02, F05-A | K | — |
| WLD-07 | Kentte görünür öğeler: meydanlar ve insan ölçeğinde saat kulesi (çevresindeki 4–5 katlı yapılardan fantastik yüksek değil), stadyum, tarihî+modern sanayi izleri, antik kalıntılar (dağ tepelerine rastgele dekor değil), çarşı, iskele, toplu ulaşım, apartman blokları, sivil yapılar, üniversite/okul, lojistik avluları. | F02, F04 | OY | — |
| WLD-08 | T0 sahnesi yaşanacak kadar insan, iş ve yapı içerir; dekor olarak boş bırakılmaz. | F02 | OY | — |
| WLD-09 | Topolojik sabitler (körfez, yamaç/ova, ana kara–ada ilişkisi, tarihî şehir, miras odakları) korunur; kazanılmış mülkiyet ve geçmiş "sıfırla" ile silinmez. | F02 | OY | — |
| WLD-10 | Anderva: kesintisiz ana kara, kıyı/ova/yayla/orman/dağ kuşakları; yedi metropol ülke ölçeğinde anlamlı kent kütlesi (köy gibi değil). Varnis, Karvet vb. adlar kesin değil. | F01, F04, F05-A | K / OY | — |
| WLD-11 | Oyuncu bakmıyorken diğer ilçeler donmaz; diğer belediyeler, yatırımcılar, haneler ve makro koşullar onları değiştirir (soyutlama serbest). | F03 | OY | — |
| WLD-12 | Örnek/ilk ilçe gelecekteki tüm kampanyalar için zorunlu başlangıç hâline getirilmez. | F03 kabul ölçütleri | OY | — |

## Simülasyon (SIM)

| ID | Gereksinim | Kaynak | Statü | Kanıt |
|---|---|---|---|---|
| SIM-01 | Haneler barınma, gelir/istihdam, erişim, hizmet ve çevreye tepki verir; taşınır, talep yaratır. | F03 | ÇM | — |
| SIM-02 | İşletme/yatırımcılar talep, işgücü, imar, erişim, maliyet, piyasa, finansmana göre yatırım/faaliyet/büyüme/küçülme/kapanma kararı verir. | F03 | ÇM | — |
| SIM-03 | Arsa/yapı: konum, mülkiyet, imar, kapasite, erişim, mevcut kullanım; gelişme kademelidir. | F03 | ÇM | — |
| SIM-04 | Altyapı ağları gelişmeyi mümkün kılar/kısıtlar; bakım ve kapasite maliyeti doğurur. | F03 | ÇM | — |
| SIM-05 | Mekânsal/ekonomik kararlar toplumsal ve siyasi geri bildirim üretir; en az bir karar gerçek siyasi/toplumsal tepki oluşturur. | F01 sütun 2, F03 | K / ÇM | — |
| SIM-06 | Makroekonomi ve diğer altı metropol soyut simüle edilir. | F03 | ÇM | — |
| SIM-07 | Altyapı doğru binayı sihirle spawn etmez: yatırım hiç gelmeyebilir, yanlış yoğunluk bütçeyi zorlar, aşırı talep spekülasyon yaratır. | F03 | OY | — |
| SIM-08 | Durdurulabilir/hızlandırılabilir zaman; kararların etkisi zamana yayılır. Kesin oranlar açık. | F03 | ÇM | — |
| SIM-09 | Popülerlik tek skora indirgenmez (tek "Mutluluk %" yok). | F03 | OY | — |
| SIM-10 | Aynı T0'dan iki oyuncu yoğunluk, sektör ve ulaşımda anlamlı biçimde farklı şehirlere ulaşabilir; zorunlu late-game planı yok. | F01 sütun 4, F02, F03 | K / OY | — |
| SIM-11 | Hikâyeler sistemlerden doğar; her kampanyada aynı karar zinciri/aynı şehir çıkmaz. | F01 | OY | — |
| SIM-12 | Nedensellik görülebilir ve sorgulanabilir: oyuncu bir sonucun (yatırım gelmedi, protesto) nedenini dünyada ve panelde okuyabilir. | F01, F03 | OY | — |

## Görsel (VIS)

| ID | Gereksinim | Kaynak | Statü | Kanıt |
|---|---|---|---|---|
| VIS-01 | Üretilebilir gerçek zamanlı low-key low-poly 3D; ülke ve ilçede aynı sanat grameri. Konseptlerdeki sinematik/fotogerçekçi efektler hedef değil. | F04 | OY | — |
| VIS-02 | Katmanlı Ege kent dokusu: farklı dönem apartmanları, ticari zemin katlar, küçük sanayi, depolar, eski sanayi tuğla/taş/beton izleri, ofis/yüksek bina kümeleri, kamusal altyapı, yürünebilir kıyı, tramvay/feribot, ova, yamaç. | F04 | OY | — |
| VIS-03 | Yakın ölçekte binalar ve yollar maket değil, kullanılabilir ölçekte; ağaç/araç/kule ölçek sapması yok. | F04 | OY | — |
| VIS-04 | Uzak ölçekte metropol geniş, çeşitli kütleli; tarım boş renk lekesi, sanayi "3 konteyner", karşı yaka "birkaç turist evi" değil. | F04 | OY | — |
| VIS-05 | Reddedilenler: Adriyatik/Venedik, tüm çatılarda kırmızı kiremit, parlak tatil köyü, oyuncak mobil city-builder, tekrar eden 4 bloklu maket, ağır hiperreal CGI, poster resimler. | F04, F05-E | K (ret) | — |
| VIS-06 | Görsel kabul soruları 1–6 (F04 sonu) her büyük görsel teslimde yanıtlanır. | F04 | OY | — |
| VIS-07 | Konseptlerdeki UI, istatistik, ölçek okları, kart metinleri kanon değildir; kopyalanmaz. | F04, F05-E | K | — |

## Teknik (TEK — ADR kaynaklı, kanon değil)

| ID | Gereksinim | Kaynak | Kanıt |
|---|---|---|---|
| TEK-01 | Simülasyon render/input'tan ayrı, sabit tick'li, kare hızından bağımsız ve seed ile deterministik; headless test edilebilir. | ADR-0002 | — |
| TEK-02 | Kayıt/yükleme: kaydet → yükle → N tick → durum hash'i eşit. | ADR-0002 | — |
| TEK-03 | Tek dünya verisi (arazi, kıyı, ağlar) tüm kamera ölçeklerinde aynı kaynaktan render edilir; LOD yalnızca temsil değiştirir. | ADR-0002 | — |
| TEK-04 | Platform girdi/UI profilleri: masaüstü (fare/klavye/trackpad) birincil, dokunmatik (iPad) ikincil ama ilk günden; aynı oyuncu fiilleri. Gerçek cihaz testi olmadan bir platformda "çalışır" denmez. | ADR-0004, D-003 | — |
| TEK-05 | Performans bütçesi ADR-0001'deki benchmark'a dayanır; bütçeyi aşan değişiklik kanıtla gerekçelendirilir. | ADR-0001 | — |

## Platform (PLT — kullanıcı kararı D-003)

| ID | Gereksinim | Kaynak | Statü | Kanıt |
|---|---|---|---|---|
| PLT-01 | Birincil hedef Windows ve macOS; ikincil hedef iPadOS. | D-003 | K | — |
| PLT-02 | iPadOS ilk günden mimari ve UX kapsamında; iPad'e özgü sorunlar sonraya ertelenmez. | D-003 | K | — |
| PLT-03 | Simülasyon derinliği, mekanikler ve sistemler iPad sınırlarına göre baştan kısılmaz; masaüstü kapsamı iPad için azaltılmaz. | D-003 | K | — |
| PLT-04 | Tek simülasyon çekirdeği ve ortak dünya verisi; simülasyon sonuçları platformdan bağımsızdır. | D-003, ADR-0004 | K / TEK | — |
| PLT-05 | Platforma uygun kontrol, etkileşim, UI ve grafik profilleri olabilir. | D-003 | OY | — |
| PLT-07 | iPad'de gerçek cihaz testleri ilk anlamlı grafik + girdi prototipinden itibaren yapılır (M2 sonuna ertelenmez); renderer ve kalite profilleri platform başına ölçümle seçilir, hiçbiri tüm platformlar için sabit değildir. Bunlar T-001'i bloklamaz. | D-004 | K | — |
| PLT-06 | Platform performansı varsayımla değil gerçek cihaz testleri ve benchmark'larla değerlendirilir; platformlar arası eşit kapasite varsayılmaz, farklar ölçümle raporlanır. | D-003 | K | — |

## Açık parametreler (kanon oluşturulmaz)

| Konu | Kural | Kaynak |
|---|---|---|
| Para birimi adı/simgesi | Yapılandırma parametresi; geçici gösterim `¤`; hiçbir yerde kanon gibi yazılmaz | Q-003 (kullanıcı: OPEN) |
| Başlangıç ilçesi | `start_district_id` verisi; kodda sabit ilçe yok | D-002 |
