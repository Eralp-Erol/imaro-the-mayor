# Kare sıçramaları · kök neden (2026-10-31)

Belirti (kullanıcının `playable.tscn --demo` günlüğü, PLAYABLE_SMOKE, 120 karelik pencereler): normal ortalama ~8-9 ms ama her ~4-5 sim gününde
(= her pencerede; "hızlı" hız 4 gün/sn) pencere maks karesi 50-75 ms; gün ~820'den sonra ortalama 15-19 ms, maks 60-140 ms.
Taban: `cef1e2c`. Kod değişmedi (yalnız iki ölçüm probu genişledi, aşağıda). Donanım: MacBookPro15,1, i7-8850H (12 iş parçacığı), AMD Radeon Pro 560X,
OpenGL Compatibility. **iPad sayısı DEĞİL.** Ölçümler pencereli (gerçek çizim) ve başsız (yalnız sim) koşulardır.

## Sonuç (kısa)

Tek bir kod hatası yok. Üç ayrı etken, büyüklük sırasıyla:

1. **Makinenin kendisi (baskın).** `pmset -g therm` koşular sırasında `CPU_Speed_Limit` 48-100 arası gezdi (48, 58, 62, 65-74, 81, 88; boştayken 100);
   yük ortalaması 3,5-11,4. Aynı sabit CPU işi (kalibrasyon döngüsü, nominal 0,35 ms) koşu içinde 0,35 ile 1,04 ms arasında oynadı (x1,0-x3,0).
   Aynı sim/tick işi kare ortalamasını doğrudan bu çarpanla büyüttü. Kullanıcının "gün ~820 sonrası ort 15-19, maks 60-140" penceresi, bizim
   koşularda aynı tick aralığında makine hızı x2-x3 yavaşladığında birebir çıktı (tablo B); aynı tick aralığı sakin makinede ort 10-11 çıktı.
   Gün sayısıyla ilişki YOK (düzeltilmiş ortalamanın tick ile korelasyonu 0,02; makine yavaşlamasının kare ortalamasıyla korelasyonu 0,97).
2. **Tick'li karede üst üste binen üç gerçek, kod kaynaklı sıçrama** (sakin makinede toplam 25-55 ms; makine x1,5-x2 yavaşken 50-110 ms; bu "her 4-5
   günde 50-75" imzasıdır):
   - **Haftalık siyaset taraması** (`PoliticsSystem.on_daily`, `tick % 7 == 0`: `BlocEngine.scan` + `EventEngine.scan`): ort 2,2 -> 3,7 ms, maks 9-20 ms.
     En yavaş 8 tick'in hepsi 7'nin katı (başsız ölçüm). 4 gün/sn'de her ~1,75 sn'de bir.
   - **HUD `refreshed` sinyalinde M2 sonuç panelinin yapısal yeniden çizimi**: sakin makinede tick'li karede `hud.poll` ort 4 ms iken seyrek 22-27 ms.
   - **Günlük gündem türetmesi** (`DecisionPanels._update_agenda`, her tick): seyrek 5-6 ms.
3. **Yaşam görünümü (`src/view/life`) neden DEĞİL.** Sıçrama üretmiyor (aşağıda). Sürekli maliyeti ~0,5 ms/kare (ana iş parçacığı) + çizimde ~0,6 ms.

Kök neden net ama tek-küçük-düzeltmeli değil: (1) makine, kod ile düzelmez; (2) üç sıçramanın her biri farklı sahibin (sim / UI) kodunda ve ya sim saflığına
(GOLDEN) ya UI akışına dokunur. Bu yüzden **düzeltme yapılmadı**; öneri en altta.

## Yöntem

- Probe: `tests/sim/perf/demo_frame_probe.gd` (gerçek `playable.tscn`, sabit dt 1/60, tick sayısı deterministik; pencereli). Bu görevde genişledi:
  `--engine` (motor gerçek delta ile sürer), `--split` (alt düğümlerin `_process`'i düğüm başına zamanlanır), `--spike-ms=N` (eşiği aşan kare satırı),
  `--why-poll-ms=N` (ağır HUD yoklamasında o karenin olay anahtarları), `--calls-at=a;b;c` (o tick'lerde bileşen çağrı süreleri), `--plan-n/--plan-radius`
  (şehir büyümesi), kare başına izleme (düğüm/obje/bellek/draw call/TIME_PROCESS) ve **kalibrasyon**: her karede sabit ~0,35 ms'lik bir CPU işi
  (`cal_ms`) — makine hızı göstergesi; yavaş pencerelerin makine mi kod mu olduğunu ayırmanın tek ölçütü bu oldu. `pmset -g therm` ayrıca elle örneklendi.
- Probe: `tests/sim/perf/t043b_real_world_probe.gd` (başsız, 40 493 parsellik gerçek Ismeral): `--bands` (sistem başına tick süresi, 300 günlük bantlar x
  {haftalık gün, diğer} + bant başına kalibrasyon) ve `--no-stop`.
- Yaşam görünümü A/B: `--no-life` (mevcut anahtar) ile iki çift koşu + sokak kamerası (`--preset=street:port --split`) ile düğüm başına süre.
- Geçici süreler için `PoliticsSystem`, `HudRoot.refresh`, `DecisionPanels`, `AgendaModel`, `M2Results` içine zamanlayıcı konup ölçüm sonrası
  `git checkout --` ile GERİ ALINDI (bu görevde kaynak değişikliği yok; `git status`: yalnız iki probe dosyası).
- Aynı anda tek Godot süreci; başka ajanların işleri makinede çalışıyordu (gdUnit başsız koşular, vb.): bu yüzden her tablo makine hızıyla birlikte verilir.

## Ölçümler

### A. Sakin makine (kalibrasyon 0,37 ms = nominalin x1,05), pencereli, `--demo`, hız 16 gün/sn, 1500 tick (47 pencere), yaşam açık

Not: bu ölçümde pencere başı tick 32; kullanıcının 4/sn hızında 4-5. Bantlarda pencere = 120 kare.

| tick bandı | kare ort (ms) | pencere maks medyanı (ms) | HUD yoklaması / kare | sim sürüşü / kare | projector / kare |
|---|---|---|---|---|---|
| 300-600 | 9,8 | 24 | 0,90 | 0,73 | 0,57 |
| 600-820 | 10,3 | 37 | 1,06 | 0,78 | 0,58 |
| 820-1100 | 10,7 | 33 | 1,12 | 0,82 | 0,58 |
| 1100-1400 | 11,0 | 36 | 1,40 | 0,83 | 0,58 |
| 1400+ | 10,7 | 36 | 1,36 | 0,83 | 0,60 |

Gün ~820'de bir kırılma YOK; yavaş büyüme var: ort +12% (300 -> 1100), HUD yoklaması +56%, sim sürüşü +14%. Sakin makinede en yüksek tek kareler 40-53 ms
(`L2` koşusu: tick 1134/1190 haftalık sim 11 ms + HUD 25 ms üst üste; tick 1386 sim 10 + HUD 7).
Doğrulama koşuları: `L2` ve `W1` aynı sonucu verdi (ort 9,5-10,6).

### B. Makine hızı kare süresini belirliyor (doğal deney, `N1`; yaşam kapalı, yük ağırdı)

| tick bandı | makine yavaşlaması (kalibrasyon) | kare ort | pencere maks medyanı | maks | yavaşlamaya bölünmüş ort |
|---|---|---|---|---|---|
| 0-300 | x1,35 | 11,6 | 34 | - (açılış kareleri hariç) | 8,6 |
| 300-600 | x1,98 | 14,7 | 35 | 100 | 7,4 |
| 600-820 | **x2,96** | **23,5** | **126** | **157** | 7,9 |
| 820-1100 | x2,37 | 18,0 | 80 | 124 | 7,6 |
| 1100-1400 | x1,66 | 13,7 | 54 | 65 | 8,3 |
| 1400+ | x1,49 | 12,9 | 50 | 50 | 8,6 |

Korelasyon (47 pencere): yavaşlama-kare ort 0,97; yavaşlama-pencere maks 0,85; tick-yavaşlamaya bölünmüş ort 0,02. Aynı koşuda 600-820 bandı ort 23,5/maks 157
iken 1100+ bandı ort 13/maks 50: kod aynı, yalnız makine. Yapay yük (6 `yes` süreci, `B6`): yavaşlama x1,6-2,0, tick'li iş süreleri ~x1,8, pencere maks medyanı 27-56,
maks 58-75 (sakin 24-37) — yani "maks 50-75" yük altında yeniden üretildi; kare ortalaması bu koşuda yükselmedi (7,7; çizim tarafı CPU'ya bağlı değil), yani kullanıcının
ort 15-19'u daha ağır bir throttle penceresine (x2-3) denk gelir (B tablosu 600-820).

### C. Başsız sim (yalnız sim; kalibrasyon x1,0-1,1; `--bands`, 1532 tick, 40 493 parsel)

| sistem (tick başına ms) | gün 0-300 | gün 600-900 | gün 1200+ | en yüksek tek tick |
|---|---|---|---|---|
| economy.daily (her gün) | 1,9-2,0 | 2,1-2,2 | 2,1-2,5 | 9-15 |
| economy.monthly (30 günde bir) | 3,2 | 3,3 | 3,3-3,7 | 6 |
| budget.monthly | 0,5-0,9 | 0,7 | 0,7-0,8 | 1,2 |
| politics.daily, YALNIZ haftalık günler | 2,2-2,6 | 3,3-3,7 | 3,5-5,9 (son bantta 4 örnek) | **10-20** |
| politics.daily, diğer günler | < 0,2 | < 0,2 | < 0,2 | - |
| actors.daily (haftalık) | 0,1 | 0,15 | 0,2-0,27 | 0,4 |

Haftalık taramanın içi (geçici zamanlayıcı): `BlocEngine.scan` ort 1,38 (tick 700'e kadar) -> 1,93 (tick 1500'e kadar), maks 9,0 (tick 798);
`EventEngine.scan` ort 1,04, maks 14,4 (tick 532); `MediaEngine.scan` 0,02; `ReactionAgenda.scan` 0,01. En yavaş 8 tick: 1442, 910, 1470, 1498, 1505, 630, 1050, 721 —
HEPSİ 7'nin katı. Tick ort 3,3 ms, p95 6,8, maks 21,2; 16,6 ms'yi aşan 5 tick. Sim sonucu bu görevde değişmedi (kod aynı).

### D. Tick'li karedeki HUD yoklaması (pencereli, sakin)

`hud.poll` tick'li karede ort 4,1 ms. 22-27 ms'ye çıkan yoklamalar (tick 686, 719, 774, 884, 1002, 1023, 1110, 1138, 1192, 1220, 1277, 1331, 1417...): `HudRoot.refresh`
içinde süre `refreshed.emit()`te (8-27 ms; snapshot 0,6-1,0, top bar 0,2-0,3, events_since 0,3-2,3, şerit 0,1-1,1, relayout 0,4-0,6). O karelerdeki olaylar sıradan
(8 x `investor.declined`): olay sayısıyla ilgisi yok. `refreshed` dinleyicileri: `M2Results`, `DecisionPanels`, `InspectorHost`, `RoadDrawController`.
`DecisionPanels._on_refreshed` -> `_update_agenda` seyrek 5,0-5,7 ms (`facade.agenda_items()` 0,24-0,43 ms; kalan `displaced_cause` + sıralama). `M2Results.follow` hiç 3 ms'yi
aşmadı. Geriye kalan 15-25 ms'nin sahibi: **M2 sonuç paneli** (probe 12 parsel izler; `M2ResultPanel.refresh` yapı imzası değişince — bir izlenen parselin yeni kararı/gerekçesi —
tüm düğümleri yeniden kurar; sinyal 250 ms ile sınırlı). Bu atama önce ELEME ile yapıldı, sonra `--panel=none` koşusuyla (P0) doğrulandı: panel kapalıyken ağır yoklama 0, `hud_poll_max` 6,57 ms,
pencere max 24-30 ms (41 pencere, kalibrasyon 0,36). Kullanıcıya yakın durum (U1: `--demo --plan-n=1 --speed=3`, 1300 tick, kalibrasyon 0,36, yük 3,4): yalnız 1 izlenen parselle
ağır (>=12 ms) yoklama 1300 tick'te 5 kez (tick 2, 6, 143, 550, 772; 14-18 ms), `hud_poll` ort 3,1 ms / max 18,4 ms, pencere max medyanı 26-33 ms, en yüksek pencere 52 ms
(1100-1400 bandı). Yani 12 parselde sık görülen panel yeniden kurulumu 1 parselde seyrek; 50-75 ms'lik pencereler tek başına panelden değil, haftalık siyaset taraması + panel + makine
yavaşlaması toplamından (A-C). İlk kare/ilk birkaç kare (0,8-1,4 sn) başlangıç yüklemesidir, sıçrama sayılmadı.

### E. Yaşam görünümü (A/B ve düğüm başına)

- Varsayılan açılış kamerasında menzilde hücre yok (`cells 0, cars 0`): bu ölçekte yaşam maliyeti ~0 (A tablosu yaşam açık; `N2` yaşam kapalı: düzeltilmiş ort 9,1-9,7, açık 9,2-10,2; fark gürültü içinde).
- Sokak kamerası (`street:port`, 36 hücre, 75 araç, 100 yaya): `Life` düğümü ort **0,5 ms/kare**, maks 2-3,6 ms; hücre kurulumu 61 kez, tek hücre maks **0,93 ms**, toplam 31,8 ms;
  başlangıç `_start` ilk karede ~100 ms (tek seferlik, ısınma örtüsü altında). Kare ortalaması: yaşam açık `S1` 6,9-7,2 ms, kapalı `S2` 10,2-12,0 ms (S2 makine x1,15-1,4 yavaşken koştu): kapalıyken YAVAŞ çıkması farkın yaşamdan değil makineden geldiğini gösterir; yaşamın kendi payı yukarıdaki düğüm süresi + çizim (T-050 logu: +0,6 ms) kadardır.
- `mark_data_changed` (doluluk değişimi -> tüm hücreler yeniden kurulur) bu senaryoda yalnız 1 kez tetiklendi (`occupancy_updates 1`); sıçrama üretmedi. Kamera sürekli hareket ettiğinde veya
  çok bina bitince bu yol tekrar tetiklenebilir: **ölçülmedi** (aşağıda).
- Sonuç: kullanıcının sıçramaları yaşam görünümünden gelmiyor.

### F. Bellek / sayaçlar (şüphe: sızıntı?)

Düğüm 5 654 ve obje 148 312 tick 400'den sonra SABİT; draw call 311, üçgen 430 bin sabit (düğüm/obje sızıntısı YOK). Statik bellek yavaş artıyor: 527 MB (açılış) -> ~562 MB (tick 1500, sabit-dt, 5 600 kare)
ve ~612 MB (tick 1300, motor kipi, 29 475 kare); kaynağı (sim günlükleri mi, kare başı mı) belirlenmedi ve kare maliyetinde ölçülebilir bir kırılma üretmedi.

## Kök neden dökümü ve öneri (sahip, beklenen etki)

| # | etken | kanıt | sahip | öneri | beklenen etki |
|---|---|---|---|---|---|
| 1 | CPU hız sınırı + yük | kalibrasyon x1,0-3,0; r=0,97 | süreç | Perf kabul koşularını `pmset -g therm` = `CPU_Speed_Limit 100` ve yük < 4 iken al; probe `cal_ms` kalibrasyonunu rapora ekle; kullanıcı demosunu yan ajan koşuları sırasında değerlendirme | sıçramaların büyük bölümü (x1,5-3) |
| 2 | Haftalık siyaset taraması 3-20 ms | başsız bantlar; en yavaş 8 tick = 7'nin katı | `simulation-engineer` | Tarama içini (özellikle `BlocEngine.scan`, `EventEngine.scan`) profille; ya hesabı bit-bit aynı tutup hızlandır ya da taramayı haftanın günlerine böl (GOLDEN'ı değiştirir: onay gerekir) | tick'li kare -5..-15 ms |
| 3 | M2 paneli yapısal yeniden çizim 15-25 ms | `refreshed` 8-27 ms; diğer dinleyiciler elendi | `ui-engineer` | `M2ResultPanel.refresh`'te yapı değişince yalnız değişen satırı güncelle (tüm düğümleri yeniden kurma) ya da en çok kareye 1 yeniden çizim | tick'li kare -15..-20 ms (panel açıkken) |
| 4 | Gündem türetmesi her tick | `_update_agenda` seyrek 5-6 ms | `ui-engineer` | `derive_all`'u olay/gündem imzası değişince çalıştır | -5 ms (seyrek) |
| 5 | İki tüketici aynı 8 parselin `parcel_views`ini her tick okur (projector 8 okuma/tick, `LifeSimReader` ~8/tick); her çağrı gerekçe günlüğünü tarar | projector `read_ms` 4,3 sn / 10 400 okuma; `sync` ort 1,9 ms/tick; Life 0,5 ms/kare | `simulation-engineer` + `godot-engineer` | Facade'e gerekçesiz hafif okuma (`parcel_views` sözleşmesine dokunur: ADR gerekir) | ~-2 ms/tick sürekli |
| 6 | Zamanla büyüme | A tablosu | - | Sürdür: 1-4 bitince bu sayı gözlemde ikinci planda | küçük |

Neden düzeltme yapmadım: 1 kodla düzelmez; 2 sim saflığına (GOLDEN_A/B) dokunur ve hesabı `simulation-engineer` bilir; 3-4 UI akışıdır (`ui-engineer`); 5 sözleşme/ADR işi.
`playable.gd` 1000 satırda ve bu görevin sebebi orada değil.

## Yapılanlar

- `tests/sim/perf/demo_frame_probe.gd`, `tests/sim/perf/t043b_real_world_probe.gd`: yukarıdaki bayraklar (ölçüm aracı; oyun/sim davranışı ve hash değişmez). gdlint temiz.
- Ham koşular `/private/tmp/claude-501/.../scratchpad/fs/` altında (ab1-ab5, prof_h1/h2); repoya konmadı.

## DOĞRULANDI / VARSAYILDI / TEST EDİLMEDİ

**Doğrulandı (ölçüldü):** A-E tabloları, kalibrasyon-kare ort korelasyonu (0,97), başsız haftalık maliyetler, en yavaş tick'lerin 7'nin katı olması, `refreshed.emit()`in HUD yoklamasının ağır
kısmı olması, yaşam görünümünün hücre kurulum ve düğüm maliyeti, `playable.gd` = 1000 satır, probe'ların gdlint'i, `no_rejected_reference_scan_test` 5/5.

**Varsayıldı:** (a) M2 panelinin İÇ süresi ayrıca zamanlanmadı; atama eleme + `--panel=none` karşılaştırmasıyla (ağır yoklama 0, hud_poll_max 6,57 ms) yapıldı; (b) kullanıcı makinesinde de `CPU_Speed_Limit` düşüyor (kullanıcının günlüğünde kalibrasyon yok; benim makinemde ölçtüm);
(c) kullanıcının "her pencerede 50-75" imzası haftalık tick x HUD x yavaşlama toplamıdır (sayılar tutarlı, kullanıcı günlüğüyle yan yana kıyas yok: günlük elimde değildi).

**Test edilmedi:** gerçek motor döngüsünde (`--engine`) 1300 tick'lik tek koşu yapıldı (yük ağır, kalibrasyon yoktu; yalnız yön olarak yük-bağımlılığı gösterdi); kamera sürekli hareket ederken yaşam hücre
yeniden kurulumu ve çok binalı şehir (100+ bina) ile yaşam/projector yükü; kayıt yükleme sonrası uzun oturum; iPad; sakin ve soğuk makinede ikinci tam seri; `tools/verify.sh` (talimat: koşulmadı).
