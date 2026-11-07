# 2026-11-07 · Teknik direktör: M3 "Yaşayan metropol" mimari ön değerlendirmesi

Yalnız doküman. `src/`, veri, test, ADR, kanon değişmedi; Godot çalıştırılmadı. Kaynak: D-029, `production/ROADMAP.md` M3 satırı, ADR-0001/0002/0004/0005/0009/0010/0011, `src/sim/**`, `src/game/playable.gd`, `src/app/tick_driver.gd`, `production/log/2026-10-31-tick-maliyeti-yol-ay.md`.
Etiketler: **[okundu]** kod/belge okundu · **[kayıt]** eski ölçüm kaydı, bu oturumda koşulmadı · **[hesap]** · **[varsayım]**.

## Karar özeti (önce bu)

1. **Temel M3'ü taşır; yeniden başlangıç gerekmez.** Saf sim, sabit tick, sistem başına RNG akışı, "takılmazsa sıfır bayt" deseni, sürümlü bölümler sağlam.
2. **"Toplu ilçe modeli" yeni bir durum modeli olarak KURULMASIN.** Ismeral'in 6 ilçesi zaten parsel düzeyinde, tek ekonomide simüle ediliyor (40 493 parsel). İlçeleri donduran şey tick bütçesi değil, D-010 kuralı: oyuncu planı olmayan boş parsele yatırımcı yapmıyor. Eksik olan **karar veren aktörler** (diğer belediyeler, makro), toplu durum değil. Toplu (kohort) durum yalnız diğer altı metropol için (SIM-06).
3. **"Oyuncu bakmıyor" = oyuncunun yetki alanı dışı (oyun durumu), kamera DEĞİL.** Kameraya bağlı sim tekrar oynatmayı ve masaüstü/iPad eşitliğini bozar (ADR-0004 gerilim 1).
4. **En büyük teknik açık: tick karenin içinde, ana iş parçacığında koşuyor** ve dilimleme yok. M3 sistemleri eklenmeden önce tick bütçesi kuralı yazılmalı.
5. **İlk iş üç küçük temel görev** (aşağıda §4 Faz 0); paralel hatlar ondan sonra açılır.

## 1 · Mevcut yapı: hazır olan / olmayan

| Konu | Durum | Kanıt |
|---|---|---|
| Sim saflığı, sabit tick, takvim (gün/ay/çeyrek) | HAZIR | `src/sim/core/simulation.gd` (komut → tick+1 → daily → monthly → quarterly) [okundu] |
| Sistem başına RNG akışı, platformdan bağımsız türetim | HAZIR | `src/sim/core/rng_streams.gd` [okundu] |
| İsteğe bağlı sistem takma (yoksa hash/kayıt aynı) | HAZIR, M3'ün ana deseni | `SimFacadeImpl.attach_public_works/attach_budget` (`src/sim/facade/sim_facade_impl.gd:108-140`) [okundu] |
| Bölge (ilçe) sütunları: `latent_hh`, `infra_cap`, `access_pm`, `service_pm`… | KISMEN HAZIR: SIM-04 kapasite var, **bakım maliyeti yok** | `economy_state.gd` REGION_COLUMNS; `data/sim/budget/` içinde bakım yok [okundu] |
| Tüm Ismeral parsel düzeyinde | HAZIR (ADR-0002 §3'ten farklı: orası "diğer ilçeler toplu" diyordu) | `playable.gd:357-385` tüm `WorldParcel`leri kaynağa verir; `sim_parcels=40493` [kayıt] |
| Tick maliyeti (gerçek Ismeral, başsız, dev Mac) | ort 3,24 ms/gün, ay sınırı ≤ 8,2 ms, ilk tick 109-119 ms | `2026-10-31-tick-maliyeti-yol-ay.md` [kayıt, ESKİ yapı; yeniden ölçülmeli] |
| **Tick karenin içinde** | HAZIR DEĞİL. ADR-0001 Karar 4 ("tick kare içinde çalıştırılmaz") uygulanmamış | `playable.gd:748` `_facade.drive_usec(...)` → `TickDriver.advance_usec` → `Simulation.advance` senkron [okundu]; tick'li kare ort 11,2 / maks 55-60 ms (ADR-0010 bağlam) [kayıt] |
| Platform profili `tick_slicing` | TANIMLI ama hiçbir yerde OKUNMUYOR | `grep tick_slicing src` yalnız `platform_profile.gd` [okundu] |
| Yatırımcı değerlendirme bütçesi | **Şehir geneli tek bütçe** (`max_reviews_per_tick` = 8, tek imleç) | `economy_system.gd:462-489`, `data/game/playable_economy.json` [okundu]. Diğer ilçeler canlanınca oyuncunun ilçesi daha yavaş gelişir (D-008 döngüsü geriler) [hesap] |
| Gerekçe/olay saklama | Kapasite 1000 / 1000 | `data/sim/core_config.json` [okundu]. M2'de 13-16 günde dönüyordu (ADR-0005 Ek D); 6 ilçe karar üretince ufuk kısalır, HUD "neden" boşalır (B-001 sınıfı) [hesap] |
| Kampanya tohumu | YOK: sim RNG'si dünya tohumundan | `GameState.create(world_seed…)`, `PoliticsBootstrap.create(_world.world_seed…)` [okundu]. Ismeral coğrafyası sabitse her kampanya aynı komutlarla aynı hikâyeyi üretir → **SIM-11 riski** |
| Oyuncu yetki alanı | Sim durumunda değil; dünya verisinde (`network.json` `jurisdiction_regions: ["D2"]`, yol kuralı) | [okundu]. M3'te "bakılmayan ilçe" ve M5'te makam değişimi bunu sim durumu ister |
| Kayıt | `SimSave.VERSION = 2`, taşıma yok; yeni bölümler "yoksa geçerli" kalıbıyla `GameState.validate_dict` zincirine elle ekleniyor | `sim_save.gd`, `game_state.gd:150-183` [okundu]. Zincir her M3 sim görevinin dokunacağı **çakışma noktası** |
| GOLDEN_A/B/X | Küçük fixture (F1/F2) + takılı sistemler; M3 sistemleri takılmadıkça bit-eşit kalır | `tests/sim/m2_query_test.gd`, `golden_expropriation_undo_test.gd` [okundu]. Gerçek Ismeral'de kilitli hash YOK (yalnız probe) |
| Dosya boyu | `economy_system.gd` 998 satır, gdlint sınırı 1000 | [okundu]. Ekonomiye dokunan her M3 işi önce bölme ister |

## 2 · Önerilen mimari: bakılmayan ilçelerin evrimi

**İlke:** tek durum modeli (açık parsel) + ilçe düzeyinde **karar katmanı**. "Toplu" olan karar ve dış koşuldur, parsel durumu değil. Böylece ADR-0002'nin en zor riski (toplu ↔ açık model geçiş tutarlılığı, WLD-09/CAN-11) M3'te hiç doğmaz; oyuncu M5'te o ilçeye geçtiğinde dünya zaten parsel düzeyinde oradadır.

| Katman | Ne | Sıklık | Durum yeri (öneri) |
|---|---|---|---|
| Parsel ekonomisi (mevcut) | Yatırımcı, inşaat, kira; tüm ilçeler | günlük; **değerlendirme bütçesi ilçe başına** (veri anahtarı, varsayılan = bugünkü şehir geneli davranış → GOLDEN aynı) | `systems.economy` |
| Diğer ilçe belediyeleri (WLD-11) | Kendi ilçesinde imar planı açar (oyuncuyla aynı imar kuralı ve aynı örtü, farklı yazar), küçük yol/altyapı kararı; her karar gerekçeli (SIM-12). CAN-03 korunur: belediye bina yapmaz, yalnız koşul değiştirir | aylık karar, çeyreklik bütçe/öncelik güncellemesi | yeni `systems.districts` |
| Bölge değiştirici kapısı | Dış sistemler ekonomiye **tek arayüzle** girer: `access_pm`, `service_pm`, talep çarpanı, göç (latent_hh) | ekonomi aylık okur | ekonomi içinde tek fonksiyon; diğer sistemler ekonomi dosyasına yazmaz |
| Ulaşım/trafik | Bölge/blok zonlarından O-D, `WorldNetwork` kenarlarına atama, tamsayı seyahat süresi, sıkışık bağlantı; sonuç → `access_pm` | aylık sonuç, iş **günlere dilimli** (imleç durumda) | yeni `systems.traffic` |
| Altyapı bakımı (SIM-04) | Yol metre/kapasite birimi başına aylık bakım gideri; birikmiş bakım açığı kapasiteyi düşürür (etki büyüklüğü veride) | aylık | `systems.budget` + `systems.economy.regions` |
| Makro (SIM-06) | Faiz/talep/inşaat maliyeti endeksleri (‰, tamsayı), kendi RNG akışı + senaryo verisi | çeyreklik | yeni `systems.macro` |
| Diğer altı metropol (SIM-06) | Saf toplu durum: nüfus, iş, çekicilik; Ismeral ile göç akışı | çeyreklik | `systems.macro.metros` (kimlik `metro.1..6`, **ad yok**, F05-D AÇIK) |
| Hava | Günlük hava kodu (yağmur vb.), kendi RNG akışı; etkileri (trafik hızı, inşaat gecikmesi) veride, varsayılan 0 | günlük | yeni `systems.weather` (birkaç bayt) |
| Hikâyeler (SIM-11) | Yeni mimari yok: mevcut olay motoruna (PE-xx, `data/politics/events`) yeni kaynaklar: sıkışıklık, bakım açığı, komşu ilçe büyümesi, makro şoku | haftalık tarama (mevcut) | `systems.politics` |
| Ortam sesi | Yalnız görünüm/uygulama: snapshot'tan hava, yoğunluk, trafik düzeyi, kamera yüksekliği okur; sim'e dokunmaz | kare | `src/view/audio/` (öneri) |

Notlar:
- Hava ve trafik **sim durumudur**, görünüm değil: araç/yaya yoğunluğu ve yağmur ekranda görünüyorsa sim'den gelmeli (sahte sayı yok kuralının görsel karşılığı; T-050 araçları bugün dekor).
- Belirleyicilik: trafik ve sıkışma formüllerinde `pow/exp` yok (ADR-0004 §2); sıkışma eğrisi tamsayı tablo.
- Kampanya tohumu: RNG tabanı `campaign_seed`'den, coğrafya `world_seed`'den. Varsayılan `campaign_seed = world_seed` ile GOLDEN bit-eşit kalabilir. Yöntem ADR'de (state'e yeni anahtar eklemek hash'i değiştirir; seçenekler orada tartılmalı).
- Yedek yol (yalnız ölçüm başarısızsa): bakılmayan ilçede parsel değerlendirmesini seyreltmek (ör. 7 günde bir toplu geçiş). Tetikleyici: §5 tick tavanının aşılması.

## 3 · Gerekecek ADR'ler (yalnız başlık; yazılmadı)

- **ADR-0012** · Simülasyon kapsamı: tüm Ismeral açık parsel; "bakılmayan" = yetki alanı (sim durumu); toplu durum yalnız diğer metropoller (ADR-0002 §3 güncellemesi)
- **ADR-0013** · Tick bütçesi ve zamanlama: sistem başına tick tavanı, ağır aylık işlerin oyun günlerine dilimlenmesi, sürücüde kare başına tick sınırı (`tick_slicing`), iş parçacığına taşıma tetikleyicisi (ADR-0001 Karar 4'ün uygulanması)
- **ADR-0014** · Kampanya tohumu ile dünya tohumunun ayrılması (SIM-10/11)
- **ADR-0015** · Diğer ilçe belediyeleri aktörü ve bölge değiştirici kapısı (ekonomiye dış girdi tek yerden)
- **ADR-0016** · Makro + diğer altı metropol soyut modeli (kimlik yer tutucu)
- **ADR-0017** · Ulaşım/trafik modeli: zon, O-D, dilimli atama, tamsayı süre, `access_pm` geri beslemesi (deney sonucuna bağlı)
- **ADR-0018** · Hava durumu (sim) + yağmur görünümü + ortam sesi katmanı (iOS ses oturumu dahil)
- **ADR-0019** · Gerekçe/olay saklama ölçeklemesi (kapsam başına saklama: oyuncu ilçesinin "neden"i budanmaz)
- **ADR-0020** · M3 kayıt ve GOLDEN politikası: bölüm doğrulayıcı kaydı, `SimSave.VERSION`, gerçek dünyalı `GOLDEN_M`
- Sözleşme değişiklikleri yeni ADR değil, ADR-0005 Ek N… (1.11+)

**Riskler**
- R1 · Değerlendirme bütçesi paylaşımı: diğer ilçeler canlanınca oyuncunun ilçesi yavaşlar (görünür gerileme). İlk sim işiyle birlikte ilçe başına bütçe.
- R2 · Tick karede: ay sınırı + yeni sistemler 120 Hz'de (8,33 ms) her ay görünür takılma üretir; en yüksek hızda (16 gün/sn) ay ~2 sn'de bir [hesap].
- R3 · Gerekçe ufku kısalır → HUD "neden"i boşalır (SIM-12).
- R4 · Kampanya tohumu yoksa SIM-11 "her kampanyada aynı şehir çıkmaz" sağlanamaz.
- R5 · Trafik maliyeti bilinmiyor: GDScript'te 4 267 düğüm / 7 366 kenarda en kısa yol [kayıt: ağ boyu] ölçülmedi. Önce deney.
- R6 · Görünüm yükü şehir geneline yayılır: uzak ilçelerde de bina belirir → `SimBuildingPump`, HLOD/chunk yeniden kurma, yükleme sonrası eşitleme (B-052) sim-yapılı parsel sayısıyla büyür [varsayım].
- R7 · Yaratıcı AÇIK: komşu belediyelerin tutumu/hızı, diğer metropol adları (F05-D), yıkım/dönüşüm kuralı (Q-017). SIM-10 ayrışması Q-017 olmadan yalnız boş arazide olur. Hepsi veri odaklı yapılır; soru kartı Studio Director'da (aşağıda).
- R8 · iPad ses: cihazda "Audio interruption began" sonrası süreç sonlandı (`2026-11-06-ipad-olcum.md`, nedeni doğrulanmadı). Godot 4.7.2 iOS ses oturumu ayarı `docs/engine-reference/godot/` içinde YOK → **doğrulanmamış API**.
- R9 · GOLDEN gürültüsü: her M3 sistemi gerçek Ismeral davranışını değiştirir; fixture GOLDEN'ları "takılmazsa sıfır bayt" ile korunur, gerçek dünya için ayrı kilit gerekir.

## 4 · Görevlere bölme: sıra ve paralellik

**Faz 0 · temel (sıralı, küçük, hepsi GOLDEN_A/B/X bit-eşit kalmalı)**
1. Tick ölçüm tabanı: gerçek Ismeral, başsız, sistem başına ms, 3 tohum × 1000 gün, ay/çeyrek sınırı ayrı (qa-engineer + simulation-engineer). Bugünkü 3,24 ms ESKİ yapıdandır.
2. Çakışma kırıcı yeniden düzenleme (simulation-engineer): `GameState.validate_dict` için bölüm doğrulayıcı kaydı; facade'a genel `attach_system`; `economy_system.gd` bölünmesi + bölge değiştirici kapısı (boş). Davranış değişmez.
3. ADR-0012/0013/0014 kararları + kampanya tohumu uygulaması (varsayılan bit-eşit).
- Paralel ve bağımsız: **T-075 yol onayı takılması** (görünüm; ADR-0010 seçenek A'ya göre "M3'ün ilk işi"), **trafik atama deneyi** (`experiments/traffic-assign-bench/`, üretime girmez).

**Faz 1 · paralel hatlar (Faz 0 sonrası)**
| Hat | İş | Dosya alanı | Bağımlı |
|---|---|---|---|
| A sim | Diğer ilçe belediyeleri + ilçe başına değerlendirme bütçesi (WLD-11) | yeni `src/sim/districts/`, ekonomi yalnız kapı üzerinden | Faz 0 |
| B sim | Makro + diğer metropoller (SIM-06) | yeni `src/sim/macro/` | Faz 0 |
| C sim+world | Trafik modeli (deney → ADR-0017 → uygulama); zon bölümlemesi world-engineer | yeni `src/sim/traffic/`, `src/world/network/` yalnız okuma | deney |
| D sim | Altyapı bakımı (SIM-04) | `src/sim/budget/`, `data/sim/budget/` | Faz 0 |
| E view/art | Hava sim bölümü (küçük, sim) → yağmur görünümü + ortam sesi | `src/sim/weather/` (yeni), `src/view/weather/`, `src/view/audio/` | sözleşme 1.11 |
| F ui | İlçe evrimi, trafik, bakım yüzeyleri (yalnız gerçek sim verisi) | `src/ui/` | ilgili sim hattı + sözleşme |

**Faz 2:** SIM-11 olay kaynakları (A-D sonrası; `data/politics/events`, `politics_config.gd`); SIM-10 ayrışma koşumu (qa: aynı T0, iki betikli politika, 10 oyun yılı başsız, yoğunluk/sektör/ulaşım ölçüleri farklı; A+C sonrası); `GOLDEN_M` kilidi.

**Çakışan dosyalar (aynı anda iki yazıcı olmasın):**
- `src/sim/core/game_state.gd` (doğrulama zinciri; Faz 0'da kayda çevrilince çakışma biter)
- `src/sim/facade/sim_facade_impl.gd` (676 satır, `attach_*`)
- `src/sim/economy/economy_system.gd` (998/1000 satır) ve `economy_config.gd`, `data/game/playable_economy.json`
- `src/contracts/sim_contract.gd` + `VERSION` kilitli testler + ADR-0005 ekleri: **sürüm artışı tek hattan, sırayla** (contracts hattı)
- `src/game/playable.gd` (`_start_sim`, `_process` tick sürüşü)
- `src/app/tick_driver.gd`, `src/app/platform_profile.gd` (ADR-0013 işi)
- `src/sim/politics/politics_config.gd` (900 satır), `data/politics/events/`
- GOLDEN test dosyaları (yenileme her zaman ayrı commit, gerekçeli), `tools/verify-areas.tsv` (yeni `src/sim/*` dizinleri eşlenmeli)

## 5 · Performans bütçesi uyarıları (ADR-0010 iPad ön hedefleri)

- iPad maliyet `is_ms` en kötü koşu ort 2,43 / p95 3,26 ms; ön hedef ≤ 8 / ≤ 16,6 [kayıt]. **Tick bu ölçüye bugün yalnız demo hızında girdi**; en yüksek hızda ve ay sınırında iPad'de ölçülmedi.
- 120 Hz'de kare aralığı 8,33 ms. Masaüstünde tick'li kare zaten ort 11,2 ms [kayıt] → iPad'de her tick'li kare büyük olasılıkla aralığı aşar [varsayım]. M3 ön hedefi önerisi (ADR-0013'te kesinleşir): günlük tick p95 ≤ 4 ms, tek tick maks ≤ 8 ms (ilk kurulum tick'i örtü altında hariç), ay/çeyrek işleri günlere dilimli; iPad'de kare başına en çok 1 tick.
- Kare başına tick sınırı oyun hızını kare hızına bağlar; 16 gün/sn için ≥ 16 kare/sn yeter [hesap], ama kare düşerse oyun yavaşlar. Bu bir ürün takası değil teknik sınırdır; aşılırsa ölçümle sahibe gelir (ADR-0004: sim kısılmaz).
- Bellek: masaüstü RSS 1,46-1,48 GB, iOS sınırı ölçülmedi [kayıt/ölçülmedi]. Ses akışları önceden yüklenmez (stream), yağmur parçacıkları Compatibility/iPad'de ölçülmeden kabul edilmez.
- Görünüm: uzak ilçede beliren binalar etkileşimsiz karelerde de pompa/HLOD işi üretir; ADR-0010 "ortak kare iş bütçesi" (T-075 Adım 2) M3 görünüm işlerinden ÖNCE gelmeli.
- Etkileşim karesi ve soğuk açılış iPad'de hâlâ ölçülmedi (M2 sahip adımı); M3 yükü bunları kötüleştirirse ayrım yapılamaz. M3 görünüm işleri birleşmeden önce bir iPad taban koşusu alınmalı.

## Studio Director'a

- `production/QUESTIONS.md` için önerilen kart (canon-check ile): "Komşu ilçeler kendi kendine ne kadar hızlı büyüsün; sizinle yarışsınlar mı?" (A Önerilen: yavaş ve sakin, sizin ilçeniz öne çıkar · B: sizinle aynı hızda · C: hızlı, rekabetçi). Q-017 (yıkım/dönüşüm) SIM-10 için yeniden sorulmalı. Hava etkisi: "Yağmur yalnız görünsün mü, trafiği de yavaşlatsın mı?"
- Bu not ADR değildir; Faz 0 madde 3 ADR'leri yazar.

## Doğrulanmamış

- Tick maliyetleri eski yapıdan (2026-10-31); bugünkü yapıda koşulmadı.
- Trafik atama maliyeti, yağmur görünüm maliyeti, iOS ses oturumu davranışı: ölçülmedi / API doğrulanmadı.
- Diğer ilçe belediyelerinin karar hızına göre gerekçe ufku hesabı kaba tahmindir.
