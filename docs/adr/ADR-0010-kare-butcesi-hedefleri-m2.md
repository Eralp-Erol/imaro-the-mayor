# ADR-0010 · Kare bütçesi hedefleri (masaüstü + iPad ön hedef), M1'den taşınan LOD/üçgen ölçütleri, yol onayı takılması

- Durum: kabul (teknik hedef tanımı) · Tarih: 2026-11-05 · Karar veren: technical-director. Etkileşim tavanının M2 kapanışını bekletip bekletmeyeceği **sahip kararıdır** (§Sahibe soru); bu ADR o kararı vermez.
- Ek olduğu kararlar: ADR-0001 (bütçe), ADR-0004 (platform profilleri), ADR-0008 (üçgen/kare bütçesi), D-007 (sahibin masaüstü eşiği). **D-007 değişmez**; bu ADR onun kapsamadığı ölçüleri (p99, etkileşim karesi, açılış, bellek, ısıl) ekler.
- Karşıladığı gereksinimler: TEK-01, TEK-03, TEK-05, PLT-03, PLT-05, PLT-06, PLT-07, VIS-03, VIS-04
- Etiketler: **[kayıt]** ölçüm kaydından okundu, bu oturumda yeniden koşulmadı · **[okundu]** kod okundu · **[hesap]** aritmetik · **[varsayım]** doğrulanmadı · **[ölçülmedi]**. Godot bu ADR için çalıştırılmadı.

## Bağlam

Dayanak ölçüm: `production/log/2026-11-05-perf-serisi.md` (dev Mac i7-8850H / Radeon Pro 560X, Compatibility, 1600x900, VSync kapalı, yük 2,3-5,0, `--demo` sabit `core` kamera, 4×6000 kare + 3 yol koşusu) [kayıt]:

| Ölçü | Değer |
|---|---|
| Tüm kareler ort / p95 / p99 | 7,13-7,21 / 8,81-8,86 / 11,12-11,35 ms |
| Kararlı (ölçüm başından 30 sn sonra) ort / p95 / p99 / maks | 6,03-6,05 / 8,73-8,86 / 11,40-11,59 / 18,0-19,6 ms |
| Tick'li kare (146/6000 = %2,4) ort / p95 / maks | 11,2-11,4 / 13,8-14,3 / 55-60 ms |
| Yol onayı: en kötü tek kare | 129,6 / 171,5 / 207,1 ms; ardından 3-4 kare 50-100 ms |
| Yol penceresi (63 kare) toplamı | 730 / 881 / 1114 ms (tick'siz tabana göre ~0,38-0,73 sn fazla [hesap]) |
| Draw call ort / maks | 315 / 343 |
| Üçgen (`RENDER_TOTAL_PRIMITIVES_IN_FRAME`) ort / tek kare tepe | 431k / 1,00M (tepe karesinin nedeni bilinmiyor [ölçülmedi]) |
| Açılış | sahne kurulumu 31-35 sn; kare 1: 3,9-4,1 sn; kare 6: 0,7 sn (ViewWarmup); kare 60: 1,6-1,8 sn (B-028, yalnız `--demo`) |
| Bellek | RSS tepe 1463-1479 MB; static 532 MB |
| iPad | **hiçbir sayı yok**; yalnız açıldı (sahip bildirimi, `production/log/2026-11-04-ipad-gercek-cihaz.md`) |

Yoğun çekirdek sokak bakışı (`street:20200,18700`, T-070, sim duraklatılmış): sayaç 2,87M üçgen, ort 10,99 / p95 13,15 ms [kayıt]; %76,6'sı hero LOD1 yuvası (yakın bina).

## Karar 1 · Ölçüm tanımı (iki platform için aynı)

- **Kararlı evre:** ısınma örtüsü kalktıktan sonraki kareler. Örtü kalkış işareti probe'da yokken vekil: ölçüm başından 30 sn sonrası.
- **Tüm kareler** (render + sim birlikte) temel alınır; tick'siz dilim ayrıca yazılır (D-007 tick'siz p95'i ister).
- **Etkileşim penceresi:** oyuncu eyleminin gönderildiği kareden, görünüm yenileme raporundan 120 kare sonrasına kadar. Ölçü: penceredeki en uzun tek kare + >33,3 ms kare sayısı. Eylemler: yol onayı, imar, yıkım, geri al, kamulaştırma (bugün yalnız yol ölçüldü).
- **Açılış:** süreç başından ilk etkileşimli kareye (örtü kalktı, girdi açık) duvar süresi + pencere göründükten sonra örtüsüz tek kare bloğu.
- Koşu kuralı: 3 koşu medyanı, her koşuda `uptime` önce/sonra, yük > 8 olan koşu atılır (perf serisi kuralı).

## Karar 2 · Masaüstü hedefleri (referans: dev Mac; ölçüme dayalı)

| Ölçü | Kabul / hedef | Tavan (aşılırsa kapı FAIL) | Ölçülen | Durum |
|---|---|---|---|---|
| Kararlı ort | **≤ 14 ms (D-007, sahip)** | — | 6,04 ms | Geçer |
| Tick'siz p95 | **≤ 20 ms (D-007, sahip)** | — | yol koşularında 8,35-8,68 ms | Geçer |
| Kararlı p95 (tüm kareler) | ≤ 16,6 ms (ADR-0001) | 20 ms | 8,73-8,86 ms | Geçer |
| Kararlı p99 (tüm kareler) | ≤ 25 ms | 33,3 ms (iki kare @60 Hz) | 11,40-11,59 ms | Geçer |
| Eylemsiz kararlı tek kare maks | ≤ 33,3 ms | 66,6 ms | 18,0-19,6 ms | Geçer |
| **En kötü etkileşim karesi** | ≤ 50 ms; >33,3 ms kare ≤ 3 | **100 ms** | **129,6-207,1 ms**; 4-5 kare > 50 ms | **FAIL** |
| Açılış: ilk etkileşimli kare | ≤ 20 sn | 45 sn | uçtan uca ölçülmedi; parçalar ≥ ~36-40 sn [hesap] | Açık |
| Açılış: örtüsüz tek blok | ≤ 1 sn | 2 sn | kare 1 = 3,9-4,1 sn (örtünün görünüp görünmediği görülmedi) | Açık |
| Draw call | ≤ 400 (ADR-0008) | 600 (ADR-0001) | ort 315 / maks 343 | Geçer |
| Üçgen | tanı ölçüsü; standart preset/demo kararlı ort ≤ 900k | bağlayıcı değil (ms bağlar, D-007) | ort 431k; çekirdek sokak 2,87M | Standart geçer; çekirdek D-007 ile kabul |
| Bellek RSS | gerileme alarmı > 1,8 GB | — | 1,46-1,48 GB | Geçer |

- **Gerileme alarmı** (kapı değil, inceleme tetikler): kararlı ort, p95 ya da p99 bu tabandan > %20 kötüleşirse. Gerekçe: 4 koşu arası yayılım < %2 [hesap]; %20 gürültü değil sinyaldir.
- 100 ms tavanı: 60 Hz'de ~6 düşen kare; doğrudan tıklama sonrası takılmanın fark edildiği büyüklük [varsayım, genel UX bilgisi]. 50 ms hedefi kare dilimli kurulumun (4 ms bütçe) gerçekçi sonucudur.

## Karar 3 · iPad ön hedefleri — **ÖN HEDEF, CİHAZDA DOĞRULANMADI**

Cihaz: iPad Pro 12,9" (6. nesil; M2 yonga [genel bilgi]), iPadOS 26.5.2. Hiçbir satırın ölçülen değeri yok. Hedefler D-007 madde 2'nin "katı bütçe iPad hedefidir" kararından ve masaüstü ölçümünden türetildi.

| Ölçü | Ön hedef | Tavan | Dayanak |
|---|---|---|---|
| Kararlı ort | ≤ 8 ms | 14 ms | D-007 md. 2 / ADR-0008; ısıl pay için 60 Hz bütçesinin yarısı |
| Kararlı p95 | ≤ 16,6 ms | 20 ms | aynı |
| Kararlı p99 | ≤ 25 ms | 33,3 ms | Karar 2 ile aynı |
| En kötü etkileşim karesi | ≤ 50 ms | 100 ms | Karar 2 ile aynı; dokunmatikte takılma pan/pinch'i zıplatır (aşağı) |
| Açılış: ilk etkileşimli kare | ≤ 30 sn | 60 sn | masaüstü + mobil pay [varsayım] |
| Açılış: örtüsüz tek blok | ≤ 1 sn | 2 sn | aynı; hata ayıklayıcısız soğuk açılış ayrıca denenir (iOS yanıt vermeyen uygulamayı sonlandırabilir [varsayım, süre doğrulanmadı]) |
| Draw call / üçgen | ≤ 400 / ≤ 900k | — (ms bağlar) | ADR-0008 / D-007 |
| Bellek | masaüstü RSS'den kötü değil (≤ ~1,5 GB), bellek uyarısı/sonlandırma yok | sonlandırma = FAIL | masaüstü ölçümü; iOS uygulama bellek sınırı cihazda bilinmiyor [ölçülmedi] |
| Isıl | 15 dk sürekli oyunda son 2 dk p95 ≤ ilk 2 dk p95 × 1,25 | — | mobil ısıl kısma [varsayım] |

- Ölçüm koşulu: release dışa aktarma (debug ayrı etiketlenir), Düşük Güç Modu kapalı, şarj durumu ve ekran yenileme hızı (60/120 Hz) kayda yazılır [Godot'un iOS'ta varsayılan kare tavanı doğrulanmadı]. GPU süresi Compatibility'de 0 dönüyor; cihazda Xcode Instruments ile ayrıca bakılır [varsayım: aracın GL/Compatibility yolunda anlamlı veri verdiği doğrulanmadı].
- Beklenen gerilim [hesap + varsayım]: yoğun çekirdek sokak bakışı (2,87M) iPad'in 900k çizgisini aşar. ADR-0004 izin verir: iPad grafik profili yakın bina mesafesini kısaltabilir. **Ama bu K8'i (LOD geçiş sıçraması) geri getirir** (Karar 4). Bu takas iPad ölçümünden sonra art-director + sahibe gider; şimdi seçilmez.

## Karar 4 · M1'den taşınan ölçütler (T-012 K8 ve üçgen) — teknik görüş

**Kayıttaki "%9,5" ve "~1,27M" sayıları BAYAT.** `production/M2-CLOSURE.md:9`, `production/ROADMAP.md:62`, `docs/agent-handoff/IMARO_CHECKPOINT.md:97` hâlâ bunları yazıyor; ama `production/tasks/T-012.md` aynı gün (2026-10-21) düzeltmeyi kaydetmiş [okundu]:

| Ölçüt | M1 değeri | Sonraki ölçümler [kayıt] | Bugünkü durum |
|---|---|---|---|
| K8 LOD0↔LOD1 ≤ %5 | %9,54 / %10,42 (650 m geçiş) | LOD0 bitişi 1.450 m'ye alındı → %2,5851 (3/3 aynı piksel); smoke'larda %2,59 (T-040), %2,63 (T-049, 2026-10-25). Bir smoke'ta açıklanmamış %40,03 (`docs/agent-handoff/M01_OPEN_ITEMS.md:22`) | Sayısal olarak geçiyor; 2026-10-25'ten sonra ölçülmedi |
| Yerel evre üçgen ≤ 900k | ~1,27M tepe | 466k (T-012 son), 471k (T-040), 544k (T-049), D1 478k / port 316k (T-070), demo `core` ort 431k (2026-11-05) | Standart presetlerde geçiyor; yoğun çekirdek sokakta 2,87M (T-070) aşıyor |

**İki ölçüt birbirine bağlı (kök neden).** K8, geçiş 650 m'den 1.450 m'ye itilerek düzeldi. Bu, hücre-merkezli LOD yüzünden yakın bina modelini gerçek ~2,2 km'ye kadar çizdirir (ADR-0008 K-3) ve çekirdekteki 2,09M üçgenin (%76,6) kaynağı budur (T-070). Yani üçgen aşımı, K8 düzeltmesinin bedelidir. Birini mesafeyle düzeltmek ötekini bozar. Yapısal çözüm hâlâ ADR-0008 Karar 3 (örnek başına yakın halka, T-071); D-007 gereği askıda.

**K8 ölçüsünün geçerliliği sınırlı (teknik bulgu).** K8 tüm karedeki piksel farkıdır, tek kamera (`street:port`, seyrek bölge). Geçiş uzaklaştıkça binalar karede daha az piksel kaplar, oran kendiliğinden düşer: 650 m'de %10,42, 1.500 m'de %3,66, aynı yöntem [kayıt]. Düşüşün bir kısmı sadakat değil, kapsama etkisidir [hesap/çıkarım]. K8 ≤ %5 bu yüzden gerileme bekçisi olarak anlamlıdır, görsel kabul kanıtı değildir.

**Öneriler (teknik taraf; görsel karar art-director + sahibin):**
1. **K8 → KABUL (teknik), sayı düzeltilsin.** M2'yi bekletmez. Bugünkü 1,5 km geçişte gerileme bekçisi olarak `tools/smoke_playable.sh` içinde kalır. Geçiş mesafesi değişirse (T-071, iPad profili) K8 bina pikseline göre normalize edilmiş biçimde ve en az iki kamerada (port + çekirdek) yeniden tanımlanır. Pop'un gözle kabulü art-director kapısıdır, sayı onun yerine geçmez.
2. **Üçgen 900k → ERTELEME (D-007 gereği), tanım netleşsin.** Masaüstünde bağlayıcı olan ms; standart presetler 900k içinde. Yoğun çekirdek 2,87M masaüstünde D-007 ms eşiği içinde kabul. 900k, iPad profil ölçümünde bağlayıcı aday olur (Karar 3).
3. **DÜZELTME önerilmez.** İki ölçüt için şimdi kod değişikliği yok. Tetikleyiciler: iPad ölçümü 900k/ms'i aşar; art-director 1,5 km geçişi ya da yakın bina yoğunluğunu FAIL eder; D-007 eşiği aşılır.
4. 2026-11-05 serisindeki 1,00M tek kare tepesi açıklanmadı. Masaüstünde kapı değil; iPad ölçümünde tepe karesinin kare numarası ve kaynağı yazılır.

## Karar 5 · Yol onayı takılması (130-207 ms): kök neden yönü

**Ölçümden çıkan [kayıt + hesap]:** en kötü tek kare, yol görünüm yenilemesinin duvar süresinin %83-92'si (129,6/141,4; 171,5/188,2; 207,1/248,8 ms). Yani takılma, yenileme penceresinin içinde. Sim komutu ucuz (0,93-1,35 ms gönderim); tam yeniden kurma olmadı (`full=false`, 1 chunk). Bu bir "tek büyük iş" değil; pencerede ardışık 4-5 ağır kare var.

**Koddan çıkan [okundu]:** Yol değişimi tek bir dünya değişimidir, ama aynı birkaç karede **beş ayrı tüketici** ana iş parçacığında çalışır. Her biri kendi bütçesiyle dilimlenmiş, ama ortak kare bütçesi yok:
- `RoadEditSync.begin_async` → `_prepare` → `RoadChunkPlan.apply_changes`, ana iş parçacığında (`src/view/roads/road_edit_sync.gd:72-87,162-168`); süresi pencereli koşuda ölçülmedi.
- `RoadView.step_install`: 4 ms bütçe ama **en az bir chunk** (2 km chunk = iki ArrayMesh; GL tampon yüklemesi sonraki çizimde) (`src/view/roads/road_view.gd:282-303`). `step_far` uzak yol meshini aynı karelerde dilimli yeniler (`:312-343`).
- `PlayableExpropriation.poll`: `reconcile` + `BuildingView.pump_pending` (4 ms, en az bir birim; yarım hücre) + kent zemini `step_urban_update` + bitki taraması (en az 1,5 ms) (`src/game/playable_expropriation.gd:106-124`).
- `VegetationView._write_channel` → `_join_blob_jobs()`: leke işçilerini **ana iş parçacığında bekleyerek** birleştirir, sonra pencereyi zorlar (`src/view/vegetation/vegetation_view.gd:220-249`).
- İki kare sonra `_refresh_vegetation_corridors` (yorumda 7-30 ms) (`src/game/playable.gd:563-571, 733-737`).

**Hipotez (doğrulanmadı):** takılma, (a) bölünemeyen birimlerin ("en az bir" kuralı, zemin dokusu yüklemesi, chunk mesh GL yüklemesi, bekleyen işçi birleştirmesi) bütçeyi aşması ve (b) beş tüketicinin aynı karelere üst üste binmesidir. Pencerede kare başına alt sistem dökümü yok, o yüzden hangisinin baskın olduğu **bilinmiyor**. Mevcut istatistikler (`pump_max_ms`, `ground_finish_ms`, `veg_apply_max_ms`, `reconcile_max_ms`, `poll_max_ms`, `veg_corridor_ms`, `road_sync_ms`) zaten toplanıyor; ilk adım bunları kare serisine yazmaktır, `src/` değişikliği gerekmez.

**Mimari değerlendirme:** Temel doğru. Sim ayrı (TEK-01), ağ salt okunur işçiye gider, `world_busy` veri yarışını kapatır (B-020). Eksik olan, görünüm tarafında ortak bir **kare iş bütçesi** (tüm tüketiciler tek sırada, kare başına toplam ~6 ms) ve bölünemez birimlerin ölçülüp bölünmesi. Bu bir yama değil, var olan dilimleme deseninin tamamlanmasıdır. Yeniden başlangıç gerekmez.

**iPad riski [varsayım, ölçülmedi]:**
- İş ana iş parçacığında, çoğu GDScript. M2'nin tek çekirdek hızı i7-8850H'den yüksek olabilir; bu CPU payını küçültebilir.
- GL tampon/doku yüklemesinin iOS'taki Compatibility yolunda maliyeti bilinmiyor. Isıl kısma uzun oturumda payı büyütür.
- 120 Hz ekranda 100 ms = 12 düşen kare. Takılma, onaydan hemen sonraki parmak hareketini zıplatır; doğrudan dokunmada fareden daha belirgin.
- Pencere boyunca `world_busy()` yeni yol komutunu `busy` ile reddeder (`src/game/playable_roads.gd:55,70-71`). Yavaş cihazda pencere uzarsa ardışık yol çizen oyuncu daha sık ret alır. Retin oyuncuya nasıl gösterildiği bu inceleme için okunmadı.
- Sonuç: iPad'de takılmanın masaüstünden **daha iyi ya da daha kötü** olacağı söylenemez. Ölçülmeden karar verilmez (PLT-06).

## Karar 6 · B-028 ve açılış donmaları

- **B-028 (kare 60, 1,6-1,8 sn) → DÜZELT, küçük iş.** Kayıt/yükleme doğrulama kancası sahibe gösterilen `--demo` oturumunda çalışmamalı. Neden: canlı oturumu `import_save` ile yeniden yükler; bir yükleme hatası sahibin gördüğü durumu değiştirirdi. Karar: kanca açıkça istenince çalışır (`--smoke-save-load`). `tools/smoke_playable.sh` başsız çağrısı bu bayrağı geçer; `PLAYABLE_SAVE_LOAD` denetimi aynen kalır. Örtüye taşıma ya da karelere yayma reddedildi: doğrulama kancası oynanış yolunda yer almaz.
- **Kare 1 (3,9-4,1 sn), nedeni bilinmiyor:** önce oyuncuya görünüp görünmediği yakalanır (pencereli, kare 1 öncesi ve sonrası). Örtüsüz görünüyorsa Karar 2 "örtüsüz tek blok ≤ 1 sn" ihlalidir, ayrı hata açılır. Hipotez: ilk çizimde gölgelendirici/doku yükü (kanıtsız).
- **Kare 6 (0,7 sn, ViewWarmup):** örtü altındaysa kabul; değilse aynı kural.

## Alternatifler ve neden reddedildi

| Seçenek | Artı | Eksi / ret nedeni |
|---|---|---|
| iPad hedefini cihaz ölçümüne kadar hiç yazmamak (ADR-0001/0008 tutumu) | Uydurma riski yok | M2 kapanışı ölçülecek bir çizgi istiyor; "ön hedef" etiketi aynı dürüstlüğü korur |
| Masaüstü hedefini ölçüme yaklaştırmak (ör. ort ≤ 8 ms kapı) | Sıkı | D-007'yi (sahip kararı) dolaylı değiştirir. Gerileme alarmı aynı korumayı kapı yapmadan verir |
| Etkileşim karesini p99'a gömmek | Tek ölçü | Yol takılması ~10-11k karede 4-5 kare (> 50 ms); p99'u kıpırdatmaz (yol koşusu p99 12-19 ms). Görünür sorun ölçüden kaybolur |
| K8 için geçişi 1,5 km'de sabitlemek ve ölçütü kapatmak | Basit | iPad profili ve T-071 mesafeyi değiştirecek; bekçi gerekli |
| Yol takılması için hemen yerel yama (bütçe sayısını küçültmek) | Hızlı | Hangi birimin baskın olduğu bilinmiyor; "en az bir birim" kuralı bütçe küçültmeyle değişmez |

## Sonuçlar ve riskler

- M2 perf satırı artık ölçülebilir: masaüstünde etkileşim karesi dışında tüm satırlar geçiyor [kayıt]; açılış uçtan uca ölçülmemiş; iPad tamamen açık.
- R1: kararlı evre vekili (30 sn) örtü kalkışıyla örtüşmeyebilir; örtü işareti probe'a eklenince tanım ona bağlanır.
- R2: yük 2,3-5,0 ile ölçüldü, "tam sakin" (yük < 2) koşu yok. Taban sayıları ± birkaç yüzde oynayabilir.
- R3: tek eylem türü (yol) ölçüldü; imar/yıkım/geri al pencereleri bilinmiyor.
- R4: bellek RSS 1,47 GB; iPad'de iOS bellek sınırı ölçülmedi. Takılmadan daha büyük iPad riski olabilir [varsayım].
- Yeniden açma tetikleyicileri: iPad cihaz ölçümü; D-007'nin değişmesi; renderer profilinin (T-010) değişmesi; Karar 2'de herhangi bir tavanın aşılması.

## Önerilen görevler (kimlikleri Studio Director atar; uygulama bu ADR'de yapılmadı)

1. **T-075 (öneri) · Yol onayı takılması** (godot-engineer; ölçüm qa-engineer). REQ: TEK-01, TEK-05, PLT-06.
   - Adım 1, yalnız ölçüm: yol probe'u pencere içinde kare başına alt sistem süresini yazar. Kalemler: `_prepare`, `step_install`, `step_far`, bina pompası, zemin, bitki maskesi/birleştirme, koridor, tick sürüşü. 3 koşu. Kabul: alt sistem toplamı en kötü karenin ±%15'i içinde kapanır.
   - Adım 2: görünüm tüketicileri için ortak kare iş bütçesi; baskın bölünemez birim bölünür ya da işçiye taşınır; `_join_blob_jobs` ana iş parçacığında beklemez.
   - Kabul: en kötü etkileşim karesi ≤ 100 ms (hedef ≤ 50); pencerede >33,3 ms kare ≤ 3; `src/sim` diff'i boş, iki koşuda `state_hash` eşit; yol görünümü en geç 1 sn içinde tamamlanır (yakalama).
2. **T-076 (öneri) · iPad cihaz perf ölçümü** (qa-engineer + godot-engineer): Karar 3 tablosu, release kurulum, `--frames-out` eşdeğeri cihazdan alınır [cihaza argüman geçirme ve dosya çekme yolu doğrulanmadı]. M2 satırındaki "ölçüm" açığını kapatır.
3. **B-028 düzeltmesi** (godot-engineer, küçük): Karar 6.
4. **Açılış uçtan uca ölçümü + kare 1 görünürlüğü** (qa-engineer): süreç başından örtü kalkışına süre ve kare 1 yakalaması.
5. **Bayat sayıların düzeltilmesi** (Studio Director): `production/M2-CLOSURE.md:9`, `production/ROADMAP.md:62`, `docs/agent-handoff/IMARO_CHECKPOINT.md:97` → Karar 4 tablosu.

## Sahibe soru (karar uydurulmadı)

> "Yol onaylanınca oyun bir an (0,1-0,2 sn) takılıyor. M2'yi kapatmadan önce düzeltelim mi?"
- **A (Önerilen)** · M2'yi bu takılmayı "bilinen açık" diye yazarak kapat. iPad ölçümü (zaten M2'de açık) yapılsın. iPad'de 100 ms'yi aşarsa düzeltme M2'ye girer, aşmazsa M3'ün ilk işi olur. D-007'deki "perf işi iPad ölçümüne kadar bekler" kuralıyla uyumlu.
- **B** · Şimdi düzelt (T-075); M2 kapanışı bir görev kadar bekler.
- **C** · Dokunma; sen fark edersen açılır.

## Kanıt

- **Okundu:** `production/M2-CLOSURE.md`, `production/log/2026-11-05-perf-serisi.md`, `production/bugs/B-028.md`, `production/log/2026-11-03-devam.md`, `production/log/2026-10-28-T-070-ucgen-dagilimi.md`, `production/log/2026-11-04-ipad-gercek-cihaz.md`, `production/tasks/T-012.md`, T-040/T-049 smoke satırları, `docs/agent-handoff/M01_OPEN_ITEMS.md`, D-007, ADR-0001/0004/0008. Kod: `src/game/playable_roads.gd`, `src/view/roads/road_edit_sync.gd`, `src/view/roads/road_view.gd:1-400`, `src/game/playable_expropriation.gd:1-240`, `src/game/playable.gd:563-571,724-779,947-959`, `src/view/vegetation/vegetation_view.gd:170-250`, `src/view/vegetation/vegetation_corridor.gd`, `src/view/buildings/building_view.gd:286-316`, `tools/smoke_playable.sh` (`--demo` + `PLAYABLE_SAVE_LOAD`).
- **Hesap:** en kötü kare / yenileme süresi oranı; pencere fazlası; koşular arası yayılım; 60/120 Hz düşen kare sayıları.
- **Varsayım:** 100 ms algı eşiği; M2 tek çekirdek hızı; iOS watchdog ve bellek sınırı; Instruments'ın Compatibility yolunda veri vermesi; iOS varsayılan kare tavanı; K8 düşüşünün kapsama etkisi payı.
- **Ölçülmedi:** iPad'in tüm satırları; açılış uçtan uca; yol penceresinde alt sistem dökümü; diğer eylemlerin pencereleri; 1,00M tepe karesinin kaynağı; K8 2026-10-25 sonrası.
- Ham perf JSON'ları (`artifacts/perf/`) bu oturumda bulunamadı; sayılar kayıttan alındı.

## Ek A · M2 kapanış durumu (2026-11-05, technical-director; ayrıntı `production/log/2026-11-05-teknik-direktor-m2-kapanis.md`)
- Karar 2 "Ölçülen" sütunu `121ff46` yapısındandır; B-040/B-081/B-042/B-052 ve çekmece sonrası kararlı evre **yeniden ölçülmedi**.
- Etkileşim karesi: B-040 sonrası (B-042 öncesi, HUD dahil) en kötü 47-57 ms, >33,3 ms kare 5-54 [kayıt, B-041]. **Tavan (100 ms) geçiyor, hedef (≤ 50 ms, ≤ 3 kare) geçmiyor**; B-042 sonrası ölçülmedi. Karar 2 tablosundaki "FAIL" artık geçerli değil.
- Kararlı p99 riski: en hızlı hızda güven şeridi (B-042, 7 tick'te bir ~22 ms) karelerin ~%4'üne biner -> p99 ~28-30 ms olabilir [hesap, ölçülmedi].
- Masaüstü yeniden ölçümü T-076 ile aynı yapıda yapılır (iPad karşılaştırması aynı yapıyı ister); ayrı görev açılmaz.
