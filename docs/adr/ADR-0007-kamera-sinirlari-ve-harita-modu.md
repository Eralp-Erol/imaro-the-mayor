# ADR-0007 · Kamera sınırları (zarf + K1 kadraj kuralı) ve strateji haritası modu

- Durum: önerildi · Tarih: 2026-10-28 · Karar veren: technical-director (T-063). Yaratıcı yön kullanıcının: D-006. Bu ADR D-006'yı değiştirmez; AÇIK kalanları (Q-019.2 harita görünüşü, Q-019.3 geçiş biçimi, Q-019.5 Anderva) **ÇALIŞMA MODELİ** olarak taşır.
- Karşıladığı gereksinimler: WLD-01, WLD-10, TEK-01, TEK-03, TEK-04, TEK-05, VIS-01, VIS-04, CAN-04, CAN-08, PLT-03, PLT-05, SIM-12
- Dayanak: D-006, D-002, `design/specs/ux/VIEW-MODES-AND-DESIGN-SYSTEM.md` §A/§C (ÇM), ADR-0001 (bütçe), ADR-0004/0005 (tek InputProfile, sim profili/görünümü okumaz), ADR-0006 §3.1 (bina kademeleri).
- Kısaltma: **ÇD** = ÇALIŞMA DEĞERİ (hesaplandı veya önerildi, çalışan oyunda ölçülmedi). Kanıt etiketi: [okundu] kod/veri okundu · [hesap] sabitlerden aritmetik (`k1.py`, düz zemin) · [ölçülmedi].

## Bağlam
- [okundu] `CameraMath`: uzaklık 25–90 000 m, eğim 8–88° (uzaklıktan bağımsız), odak yalnız `world.bounds()` içine kenetlenir (`camera_math.gd:13-16,307-311`, `camera_rig.gd:282-290`). `CameraPresets.metro` = dünya genişliği × 1,45 = 58 km / 50° (`camera_presets.gd:19-20,86-88`); `world_preview.gd:131` varsayılanı, `playable.gd:1` bunu devralır; `M` ve `1` tuşu `metro`'ya döner (`world_preview.gd:197-200`). Kapılı zoom basamakları 58 km'ye kadar (`camera_rig.gd:27`). Oyunda `Home`/başlangıç ilçesi kodu yok; `start_district_id` veride henüz yok (yalnız D-002 ilkesi + `strings.tr.json` metni).
- [okundu] Perf serileri `metro` adına bağlı: `tools/smoke_playable.sh:63` (kabul = metro/district:D1/street:port en kötüsü), `CameraSweep` metro'dan başlar ve `metro` etiketi ≥ 20 km'dir (`camera_sweep.gd:9,30`).
- D-006: serbest 3D kamera uzaydan görünmez; ~18 km tavan, ~50 m en yakın bakış (ÇD); tüm dünya/ülke ayrı harita modu, aynı dünya verisinden; insan/araç/donatı/hero LOD0 M2 sonrası.
- [hesap] K1 (aşağıda) uygulanınca tavan konuma bağlıdır; 1,5 km pay, FOV 40°, düz deniz düzlemi:

| Odak (bölge çapası) | Bugünkü preset (uzaklık, yön) | K1 için gereken min. eğim, 16:9 | Çapada K1'li en büyük uzaklık 16:9 / 4:3 | İçe bakışla (bölge→merkez) |
|---|---|---|---|---|
| Dünya merkezi | — | 18 km'de 44,5° (4:3: 39,5°) | 28,2 km / 37,6 km | — |
| D1 | 9,2 km, 0° | 30,7° (preset 40° → değişmez) | 27,9 / 37,2 km | aynı |
| D2 | 8,8 km, 65° (dışa) | 84,6° | 9,0 / 10,2 km | 28,0°, ≤ 10,2 km |
| D3 | 11,9 km, 315° | 81,8° | 12,4 / 14,8 km | 30,8°, ≤ 15,1 km |
| D4 | 17,6 km, 25° | çözümsüz | 10,7 / 12,0 km | ≤ 12,1 km |
| D5 | 18,7 km, 121° | çözümsüz | 5,4 / 6,1 km | ≤ 6,2 km |
| D6 | 9,9 km, 169° | 41,8° | 22,6 / 24,2 km | 30,0° |

Sonuç [hesap]: 18 km tavan yalnız merkez çevresinde erişilir; kenar bölgelerinde (D2, D4, D5) etkin tavan 5–12 km'dir. Bu D-006'nın "dünyanın tamamı görünmez" kuralıyla tutarlıdır ama kenar ilçelerinin açılış kadrajını etkiler (Risk R1).

## Karar
1. **Kamera zarfı veridir.** `data/view/camera_envelope.json` (sahip: godot-engineer) → `CameraEnvelope` (RefCounted, saf). Alanlar (hepsi ÇD): `d_min_m` 50 · `d_max_m` 18000 · `pitch_max_deg` 88 · `pitch_min_curve` log-uzaklıkta parçalı doğrusal [[50,12],[300,22],[1500,25],[18000,40]] · `edge_margin_m` 1500 · `k1_epsilon_deg` 1 · `k1_min_distance_m` 300 · `bands` + `hysteresis` 0,10 · `zoom_gates_m` [50,150,800,4000,18000] · `solve_order` {`default`: [pitch, distance, focus], `pan`: [pitch, focus]} · `map_exit_distance_m` 6000. `CameraMath` sabitleri yalnız NaN/sonsuz güvenlik tabanı olarak kalır; oyun sınırı hep zarftan gelir. Spec'teki 300 m → 18,9° değeri 22°'ye çekildi: K1'e girişte (300 m) eğim sıçramasın diye `pitch_min(k1_min_distance) ≥ FOV/2 + ε` doğrulama kuralı [hesap].
2. **K1 kadraj kuralı** (saf `CameraEnvelope.resolve(state, aspect, ground) -> CameraState`, deterministik, girdi/kareden bağımsız). `distance ≥ k1_min_distance_m` iken: gerçek göz konumundan (zemin açıklığı dahil) dört köşe ışını `y = sea_level_m` düzlemiyle kesişir ve dört nokta `bounds − edge_margin` içinde olmalıdır. Üst ışının kesmesi için `pitch > FOV/2 + ε` gerekir; bu eşik en-boy oranından bağımsızdır, yatay yayılım ise oranla büyür (KEEP_HEIGHT: geniş ekran daha katıdır). Düzlem en alçak görünür yüzeydir; arazi ışını daha önce keser → kural muhafazakârdır. Çözüm (`solve_order`): (1) eğimi ikiye bölmeyle en küçük geçerli değere yükselt, (2) gerekirse uzaklığı azalt, (3) gerekirse odağı merkeze doğru kaydır. **Pan istisnası:** pan uzaklığı asla değiştirmez (kullanıcı zoom istemedi): eğim → odak durur. Zarf hem `_target`'a hem yumuşatılmış ara poza uygulanır (iki geçerli durumun aradeğeri geçerli olmayabilir). Sert duvar: v0'da sönüm mevcut `SMOOTH_RATE_PER_S`; dokunmatikte geri esneme ÇM.
3. **Sokak bandı** (`distance < k1_min_distance_m`): ufuk görünür; yalnız odak `bounds − edge_margin` içinde. Kutu kenarı render tarafında **kenar pusuyla** (dünya-uzayı, kutu kenarına uzaklıkla artan sis; kameraya uzaklık sisi değil) kapanır. Kutu dışına arazi uydurulmaz (WLD-10: ana kara ancak Anderva verisiyle). Godot sis API'si (`Environment` fog modları, Compatibility desteği) **doğrulanmadı** (`docs/engine-reference/godot/` içinde yok); shader tabanlı pus yedek yoldur.
4. **Ölçek bantları** (ÇD; view katmanı üretir, sim okumaz — TEK-01): `street` 50–300 m · `neighborhood` 300–1500 m · `district` 1,5–8 km · `metro` 8–18 km; sınırda ±%10 histerezis. `CameraRig.scale_band_changed(band: StringName)` sinyali; TopBar `zoom.<band>` metnini yalnız bundan gösterir. Bantlar odak-göz uzaklığıdır, bina kademeleri (ADR-0006: hücre merkezine göre 1450/2850/13000 m) değil; ikisi yaklaşık hizalıdır, testler eşdeğerlik varsaymaz. `CameraSweep.phase_of` eşikleri (20 km/3 km/300 m) yalnız eski perf etiketi olarak donar.
5. **Açılış ve Home:** `CameraPresets.start_view(world, district_code)` = `district(code)` + `resolve`. Kod `start_district_id`'yi veriden/oturumdan alır (T-043); kodda ilçe kimliği yok. Değer yoksa yedek `core`. `camera_home` InputMap eylemi (masaüstü `Home` ÇD; dokunmatikte HUD düğmesi, ui-engineer) → `start_view`. `district` preset'inin yönü **içe** (çapa → dünya merkezi) olur: K1 altında dışa bakış D2'de 84,6° ister, içe bakış 28° [hesap]; kompozisyon design-director incelemesine gider.
6. **Preset'ler:** `metro` adı **emekliye ayrılır**: `resolve("metro")` açık hata verir ("metro kaldırıldı: core | metro_legacy_bench"), sessiz takma ad yok (eski adın anlamı değişip perf serisini yalan söyletmesin). Yeni oyuncu preset'i `core` = dünya merkezi, `d_max`, K1 çözülmüş eğim. Geçersiz preset yedeği `core`. `metro_legacy_bench` = eski 58 km/50° durumu **birebir**; yalnız `--envelope=legacy` (90 km/25 m/8°, K1 yok) ile çalışır, aksi halde hata. Bu bayrak yalnız `scenes/dev`, `tools/perf.sh`, `tools/smoke_playable.sh`, `tools/capture.sh` tarafından verilir; `playable` oyuncu yolunda kabul edilmez (demo modunda dahi bayrak yoksa zarf geçerli). T-001 preset'leri (`bay_west`, `plain_east` 24 km …) zarfsız eski görüntüyü yalnız `--envelope=legacy` ile verir; tuş sırası `KEY_ORDER[0] = core`.
7. **Perf sürekliliği:** `smoke_playable.sh` eski `metro` koşusunu `metro_legacy_bench --envelope=legacy` olarak sürdürür (seri kırılmaz, bilgi amaçlı) ve `core` koşusu eklenir; kabul = oyuncu görünümlerinin (`core`, `district:D1`, `street:port`) en kötüsü. `district:D1` (40° ≥ 30,7°) ve `street:port` (odak 9,2 km batıda, pay içinde) K1'den etkilenmez [hesap] → bu iki taban karşılaştırılabilir kalır. `street` preset'i 60 m'de kalır (≥ 50 m): T-062 street tabanı (p95 16,43 ms) geçerli.
8. **Harita modu mimarisi** (Q-019.2 ve Q-019.3 AÇIK → ÇM, değiştirilebilir):
   - **Aynı sahne, aynı veri.** Harita `playable` içinde bir moddur (ayrı sahne değil): aynı `WorldData`, `WorldNetwork`, `SimFacade` örnekleri, aynı `World3D`. Yeni coğrafi içerik/harita görseli yok. Sim modu bilmez.
   - `ViewModeController` (`src/view/map/`) değişmezleri taşır: `ViewFocus {x, z (64-bit), heading, selected_ref}`, mod, girdi yönlendirmesi (tek InputProfile; haritadayken CameraRig girdisi kapalı). Çizim `MapRenderer` arayüzünün arkasındadır.
   - **v0 renderer = `MapRenderer3D`**: aynı 3D dünyayı tepeden **ortografik** ikinci `Camera3D`; harita modunda LOD0/LOD1/HLOD1 bina, bitki ve akış (vegetation iş parçacığı, bina penceresi) **açıkça** gizlenir/durdurulur (ortografide `visibility_range`'e güvenilmez); HLOD2 + FarLod arazi/yol + sembol katmanı (`cull_mask` ayrı katman) + UI CanvasLayer etiket/lejant. Gerekçe: kıyı/yol geometrisi yapı gereği birebir, VIS-01 grameri korunur. Q-019.2 "2D kartografi" seçilirse yalnız `MapRenderer2D` (T-028 `topology_map` hattı, token göçüyle) eklenir; controller ve testleri değişmez. `PROJECTION_ORTHOGONAL`/`size`/`cull_mask` 4.7'de **doğrulanmadı**.
   - **Odak korunumu:** 3D→harita: harita merkezi = 3D odak (harita pan sınırına kenetli); harita→3D: odak = seçilen nokta yoksa harita merkezi, uzaklık `map_exit_distance_m`, yön = girişteki yön, sonra K1 `resolve`. Etkileşimsiz gidiş-dönüş durumu korur (ε içinde).
   - **Seçim tutarlılığı:** iki mod aynı `x,z → ref` çözücüsünü çağırır (ayrı çözücü yazılmaz). Harita inşa/imar komutu vermez (F03, CAN-04): araç seçimi `zoom.locked_here` + 3D ilçe bandına iniş.
   - **Harita kamerası K1'e tabi değildir**: kutu dışı nötr UI "harita çerçevesi"dir (ÇM); kuzey yukarı, döndürme yok (ÇM). Geçiş v0: anlık kesme (+ ≤ 0,6 s solma ÇD); "hareketi azalt"ta anlık; uçuşlu animasyon Q-019.3'e kadar yok.
   - **Bütçe:** harita modu ADR-0001'in preset bütçesine tabidir (dev Mac ort. ≤ 8 ms, p95 ≤ 16,6 ms, draw call ≤ 400); dönüş sonrası 120 kare p95 da aynı bütçe (akış yeniden ısınması). Hipotez [ölçülmedi]: harita, `metro_legacy_bench`'in alt kümesini çizdiği için ondan ucuzdur.
   - **Anderva (ÇM, M2 dışı):** ülke ölçeği yalnız harita modunda; önkoşul Ismeral'i aynı metre koordinatlarıyla alt dikdörtgen olarak içeren makro veri + ayrı ADR (T-069). Bu ADR yalnız ilkeyi koyar.

## Ek (2026-10-29): istenen eğim ile fiili eğim ayrıdır; eğim fiili `camera_tilt` (sahip geri bildirimi)
- **Sorun:** K1'in yükselttiği eğim `_target`a yazılıp kalıcı oluyordu; zoom-out sınırında kuş bakışına geçen kamera zoom-in'de eski açıya dönemiyordu, ayrıca eğimi kontrol eden kalıcı bir girdi yoktu (yalnız geçici R/F).
- **Karar:** `CameraRig` oyuncunun **istenen eğimini** (`desired_pitch_deg`) ayrı tutar. Her hedef güncellemesi (pan/zoom/döndür/eğ) pozu üretir, eğimi `istenen` yapıp `CameraEnvelope.resolve`'a verir; K1 yalnız fiili eğimi `max(istenen, gereken)` yapar, istenene dokunmaz. Zoom-in gereken eğimi düşürünce fiili eğim mevcut yumuşatmayla tercihe iner (sıçrama yok). Çözüm sırası, pan'da uzaklığın değişmemesi ve K1 garantisi (dört köşe `sınır − pay` içinde) DEĞİŞMEZ; `resolve` aynı.
- **Tercihi değiştirenler:** yalnız oyuncunun eğim fiili (dikleştirme görünen eğimden, alçaltma tercihten başlar; fiili aralık `pitch_min(d)..pitch_max`; tercih tabanı eğrinin en düşüğü), preset/Home (ham başlangıç eğimi, `raw_pitch_deg`) ve `apply_state` ile açıkça verilen eğim.
- **Girdi sözleşmesi (iki profile birden, ADR-0004):** `camera_tilt_requested(delta_deg)` (+ = dik) ve `held_tilt_axis()`. Masaüstü: R/F; Option(Alt)+sol sürükle ve orta tuş sürükle = yörünge (dikey eğ, yatay döndür; aşağı = dikleş); trackpad Option + iki parmak kaydırma aynı yörünge. Dokunmatik: üç parmakla dikey sürükle (iki parmak jesti pan/zoom/döndür kalır, çakışmaz). Gerekçe: Option+sürükle orta tuşsuz trackpad'de de çalışır ve mevcut sol-sürükle pan'ı ile çakışmaz; üç parmak iki parmaklı jestlerle karışmaz. Gerçek trackpad/iPad hissi DOĞRULANMADI.

## Ek (2026-10-29, b): eğim tabanı sokak ve komşulukta neredeyse yatay (sahip geri bildirimi: F ile inilen sınır ~sıfır derece)
- **Karar (ÇD, veri):** `pitch_min_curve` = [[50,3],[600,3],[1500,25],[18000,40]]; `k1_min_distance_m` 300 → **1500**; kenar pusu `full_below_m` 1500 / `gone_above_m` 2250. Taban 600 m'ye kadar 3° (ufuk görünür), 600→1500 m log-doğrusal 3°→25° (sıçrama yok), K1 girişinde 25° ≥ FOV/2 + ε = 21° (doğrulama kuralı aynı, yeni veriyle sağlanır). `CameraMath.SAFETY_MIN_PITCH_DEG` 8 → 1 (yalnız NaN tabanı; oyuncu tabanını gizlemesin).
- **Gerekçe [hesap]:** K1 ufku kadraja almaz (üst ışın zemini kesmeli, eğim > FOV/2); yani ufuk/kenar görünür olan her uzaklık K1 DIŞINDA olmalı. Yatay serbest bölge = K1 dışı bölge. 1500 m = komşuluk bandının üst sınırı = kenar payı (1500 m): odak payın içinde kaldığı için kutu kenarı odaktan ≥ 1500 m uzaktadır ve pus yalnız bu payı kaplar; sokak (<300) + komşuluk (300-1500) birlikte serbest, 600 m'den sonra taban yükselir. 1500 m'nin ötesinde K1 aynen sürer (dört kenar testi yeni eşikle).
- **Bedel:** K1'in uzaklık adımı artık en az 1500 m'ye iner (eskiden 300): kenar payına 550 m yaklaşan odaklar zoom-out'ta (eskiden ~110 m) odağı içeri kaydırır. Kenar pusu 1500 m'ye kadar çizilir (tam ekran dörtgen, maliyeti ölçülmedi).
- **Değişmeyenler:** tercih/fiili eğim ayrımı, R/F ve diğer girdiler; `street` preset eğimi 12° (perf tabanı `street:port`) kalır. iPad ve gerçek elle his DOĞRULANMADI.

## Ek (2026-10-29, c): bina farkında göz açıklığı (art-director T-062 madde 3)
- **Sorun:** 3° eğim tabanında 50-60 m uzaklıkta göz yerden ~3 m yüksekte kalıyordu; göz açıklığı yalnız araziye göre hesaplandığı için (`CameraMath.clearance_m`) yoğun çekirdekte göz bir yapının içine giriyordu (kiremit bulanık, pencere gerilmiş).
- **Karar (veri: `camera_envelope.json` `player.eye_roof_clearance`, ÇALIŞMA DEĞERİ):** göz, çevresindeki **15 m** (`radius_m`, ayak izi bu daireye değen yapılar) içindeki en yüksek çatı tepesinin en az **2 m** (`margin_m`) üstünde kalır. Yalnız gözün y'si itilir: kamera dönüşü, odak, uzaklık, istenen ve fiili eğim, K1 ve eğim tabanı AYNI (pitch tabanı davranışı değişmez). Etki `active_below_m` = 600 m'ye kadar tam, 900 m'ye (`fade_to_m`) doğru doğrusal söner; üstünde 0. Kaldırma üstel yumuşar (`smooth_rate_per_s` = 8/s, kare hızından bağımsız; yükselme ve alçalma aynı hız): kare başı sıçrama yok. Legacy zarfta kapalı.
- **Çatı kaynağı:** simülasyon başlangıç durumu `BuildingColumns` (konum, yaw, modül) + onaylı kit boyutları (`BuildingKit.footprint_*`, `height_m`) + `WorldData.height_at`; `RoofClearance` (`src/view/camera/roof_clearance.gd`) ızgara dizinli saf sorgudur (fizik/raycast/düğüm okumaz; aynı sütunlar aynı sonuç). `BuildingView` bunu `set_columns`ta yeniler ve `roof_clearance()` ile verir. `CameraRig.roof_clearance` enjekte edilebilir; boşsa rig sahnedeki `BuildingView.ROOF_SOURCE_GROUP` grubundan 0,5 sn aralıkla kendisi bulur (host sahne kodu değişmeden çalışır). Tepe = merkez zemini + modül yüksekliği (yamaçta tutucu).
- **Bilinen sınırlar:** (1) Seçim/pan/zoom matematiği HAM yörünge gözünü kullanır (arazi açıklığıyla aynı yaklaşım); göz çatı yüzünden belirgin yükseldiğinde (~15 m) imleç-altı nokta ile ekrandaki nokta kayabilir: gerçek elle pan/zoom hissi DOĞRULANMADI. (2) Hızlı pan'da (>~25 m/s) 15 m önbakış, 8/s yumuşatmadan kısa kalabilir; gözün geçici olarak çatıya girmesi mümkündür, dururken garanti sağlanır (test). (3) Yalnız yapı çatıları; ağaç/direk yok. (4) 32 bin yapılık çekirdekte dizin kurulumu ~230 ms (başsız, dev Mac, tek seferlik) ve sorgu ~20-50 us/kare: iPad ölçülmedi.

## Yeniden tabanlanacak testler (T-064 içinde; gerekçe raporda)
| Dosya:satır | Bugün | Yeni taban |
|---|---|---|
| `tests/view/camera_math_test.gd:39-43` | `clamp_*` ↔ `MIN/MAX_DISTANCE_M`, `MIN/MAX_PITCH_DEG` | zarf `d_min/d_max`, `pitch_min(d)`; güvenlik tabanı (NaN) ayrı test |
| `tests/view/camera_math_safety_test.gd:16-17` | rastgele uzaklık 25 m–90 km, eğim 8–88° | oyuncu zarfı aralığı + ayrıca legacy zarf (göz zemin üstünde her ikisinde) |
| `tests/view/camera_math_safety_test.gd:44,54-56` | 58/90 km derinlik çözünürlüğü | saf matematik: kalır, "legacy zarf" diye adlandırılır; 18 km noktası eklenir |
| `tests/view/camera_math_gestures_test.gd:34-56` | 58 km'den `MIN_DISTANCE_M`'e kesintisiz zoom; `≤ MAX_DISTANCE_M` | `d_max`'tan `d_min`'e; `≤ d_max`; kenarda zoom-out durur (K1) |
| `tests/view/camera_presets_test.gd:20-30` | `metro` = genişlik × 1,45 | `metro_legacy_bench` (legacy zarf) birebir 58 km; `metro` → hata; `core` testi |
| `tests/view/camera_presets_test.gd:61-68,129` | yedek `metro`; yön merkezden dışa; `KEY_ORDER[0]=metro` | yedek `core`; yön içe; `KEY_ORDER[0]=core` |
| `tests/view/camera_sweep_test.gd:14-26,57` | tarama metro (≥ 20 km) aşamasına ulaşır | oyuncu taraması bant adlarıyla (`street..metro`); legacy tarama eski 4 aşamayla ayrı test |
| `tests/view/camera_rig_input_test.gd:120,147,151,204` | `"metro"` rig; eğim sınırı sabit | `core`; `pitch_min(d)` / 88° |
| `tests/view/camera_rig_pose_test.gd:48-80,176-226` | `"metro"` rig, `MIN_PITCH/MIN_DISTANCE` | `core` + zarf değerleri; 176'daki metro→sokak rebase uçuşu `d_max`'tan |

## T-064 kabul ölçütleri (godot-engineer) ve kanıt
1. Zarf `camera_envelope.json`'dan; doğrulayıcı olumsuz testleri: eğri monoton değil, `pitch_min(k1_min) ≤ FOV/2+ε`, `d_min ≥ d_max`, bant aralığı boşluklu → yükleme hatası. Statik tarama: `src/view/camera/` ve `src/game/` içinde sınır sayısı gömülü değil.
2. K1 özellik testi: 16:9, 4:3, 21:9 için ≥ 10 000 tohumlu rastgele durum (`d ≥ k1_min`) → `resolve` sonrası dört köşe ⊂ `bounds − pay`; olumsuz: 90 km/8° istek zarfa kenetlenir; çözümsüz uç durum (D5 çapası, 18 km) uzaklık/odak adımına düşer; aynı girdi → bit-eşit çıktı (determinizm).
3. Pan kenara doğru: uzaklık değişmez, odak durur; zoom-out kenarda durur; rotate kenarda eğim yükselir. Tekerlek, trackpad pinch, dokunmatik pinch aynı zarfa çarpar (iki profil testi).
4. Yumuşatılmış ara pozlar da K1'li (kare kare test, preset geçişi D1→D5).
5. Bant sinyali histerezisli (sınırda ±%5 salınım tek olay üretir); TopBar metni bant sinyalinden; `src/sim` bant/zarf okumaz (tarama).
6. `start_view` + `camera_home`; kodda ilçe kimliği yok (tarama); başlangıç değeri yoksa `core`.
7. `metro` → hata; `metro_legacy_bench` yalnız `--envelope=legacy` ile; bayraksız `playable` 58 km'ye ulaşamaz (olumsuz test). §"Yeniden tabanlanacak testler" tablosunun tamamı.
8. Gerçek pencereli yakalamalar `m2-t064-*`: dört bant, açılış (en az D1 ve D5 başlangıcı), dört kenar odağı, 50 m alt sınır; sokak bandında kenara bakışta kutu kenarı görünmez (pus). Art-director 50 m'de hero LOD1'i değerlendirir (ADR-0006 A2'nin değerlendirme noktası 60 m → 50 m; D-006 gereği hero LOD0 yine M2 sonrası). Design-director içe bakış kompozisyonunu inceler.
9. Perf: `smoke_playable.sh` yeni biçimi (§Karar 7) koşar; `core` ≤ eski `metro` p95, `district:D1`/`street:port` eski tabana göre gerilemez; `resolve` maliyeti kare başına ölçülür (hipotez < 0,05 ms). iPad ölçülmedi diye yazılır.

Kanıt planı: 1–7 GdUnit `tests/view/camera_envelope_test.gd`, `tests/view/camera_k1_test.gd` + tablodaki dosyalar, `tools/verify.sh full` · 8 `tools/capture.sh` + `production/qa/` notları · 9 `tools/smoke_playable.sh`, `tools/perf.sh` JSON'ları `artifacts/perf/`.

## T-068 kabul ölçütleri (harita v0) ve kanıt
1. Kaynak tarama: harita kodu yalnız `WorldData`/`WorldNetwork`/regions/sites/`SimFacade` okur; harita için ayrı geometri/doku dosyası yok.
2. Geometri eşitliği: haritada çizilen kıyı ve ağ kenarları 3D'dekiyle aynı köşe dizileri (birebir, aynı mesh kaynağı).
3. Seçim tutarlılığı: ≥ 500 tohumlu dünya noktası 3D çözücüde ve harita izdüşümü→çözücüde aynı `ref` (fark 0).
4. Odak korunumu: etkileşimsiz 3D→harita→3D gidiş-dönüş `CameraState` farkı ε içinde; harita seçimiyle dönüşte odak = seçilen nokta, sonuç K1'li.
5. Haritada inşa/imar aracı → `zoom.locked_here` + iniş (ölü düğme yok); sim mod bilgisini okumaz (tarama).
6. Harita modunda bina LOD0–HLOD1, bitki ve akış düğümleri görünmez/duraklı (sahne ağacı testi); dönüşte geri gelir.
7. Perf: `tools/perf.sh … --map` + dönüş sonrası 120 kare; ADR-0001 bütçesi; `metro_legacy_bench` ile yan yana rapor. Yakalamalar masaüstü + dokunmatik boyut; iPad cihazı AÇIK.

## Alternatifler ve neden reddedildi
| Seçenek | Artı | Eksi |
|---|---|---|
| Tek sayı tavan (yalnız `MAX_DISTANCE`) | basit | Kenar odaklarında 18 km'de bile dünya kenarı kadraja girer [hesap]; itirazı karşılamaz |
| `metro` adını yeni anlamla korumak | araç/test düzenlemesi az | Perf serisi sessizce anlam değiştirir; geçmiş karşılaştırmalar yalan olur |
| Harita = ayrı sahne | izolasyon | Odak/seçim/panel durumu sahneler arası taşınır; WorldData iki kez yüklenir (bellek, iPad) |
| Harita v0 = 2D tuval | T-028 kodu hazır | Geometri ayrı hatla üretilir (eşitlik test yükü), VIS-01 grameri zayıflar; Q-019.2'ye kadar ikinci tercih, arayüz açık |
| Kenar için kameraya-uzaklık sisi | motor özelliği | Kenara yakın sokakta yakın planı da boğar; dünya-uzayı kenar pusu kenarı hedefler |

## Sonuçlar ve riskler
- R1 [hesap]: K1 kenar ilçelerini çapadan bütün kadrajlamayı engeller (D5 ≤ ~6 km, D4 ≤ ~12 km). Başlangıç ilçesi D5 olabilir (D-002). Yeniden açma tetikleyicisi: T-064 yakalamalarında design-director/art-director kenar ilçe açılışını FAIL ederse → `solve_order.preset = [pitch, focus, distance]` (veri), pay küçültme + kenar pusu genişletme, ya da kullanıcıya Q-019.1 alternatifi.
- R2: düz düzlem varsayımı dağlık kenarda aşırı muhafazakâr olabilir (gereksiz eğim artışı). Tetikleyici: yakalamada "gereksiz dik" geri bildirimi → düzlem yerine yükseklik alanı örneklemesi.
- R3: `resolve` her karede iki kez (hedef + poz); maliyet ölçülmedi. Tetikleyici: > 0,1 ms/kare.
- R4: Ortografik kamera + `visibility_range` + gölge davranışı Compatibility'de doğrulanmadı; harita modunda gölge kapalı varsayılır.
- R5: `--envelope=legacy` bayrağının oyuncu yoluna sızması D-006 ihlalidir; olumsuz test (T-064 ölçüt 7) ve export'ta bayrağın yok sayılması bunu kapatır.
- Bu ADR yeniden açılır: kullanıcı Q-019.1/.2/.3/.5'i farklı yanıtlarsa (yalnız veri ve `MapRenderer` uygulaması değişmeli; değişmiyorsa mimari yanlıştır), Anderva makro verisi geldiğinde (T-069), ya da iPad ölçümü bütçeyi aşarsa.

## Kanıt
- **Doğrulandı (okundu, çalıştırılmadı):** §Bağlam satır referanslı tüm kod/veri; test satırları `grep` ile bulundu. Godot bu görevde **çalıştırılmadı**; hiçbir test koşulmadı.
- **Hesap:** §Bağlam tablosu ve §Karar 7 K1 sonuçları — düz deniz düzlemi, FOV 40° dikey, pay 1,5 km, `regions.json` çapaları; betik oturum geçici dizininde, ürün kodu değil. T-064 aynı tabloyu `CameraEnvelope` ile yeniden üretmelidir (ölçüt 2).
- **Ölçülmemiş varsayımlar (ayrı):** harita modunun legacy bench'ten ucuz olduğu; `resolve` < 0,05 ms; 50 m'de hero LOD1 yeterliliği (art-director); kenar pusunun Compatibility'de istenen görünümü vermesi; `Environment` sis modları, `PROJECTION_ORTHOGONAL`, `cull_mask` davranışı (engine-reference'ta yok); su yüzeyinin tüm kutuyu opak örttüğü (düzlem = en alçak görünür yüzey varsayımı); T0 yapısına tıklamanın parsele çözüldüğü (spec'te de doğrulanmamış). iPad cihazında hiçbir şey ölçülmedi (PLT-06).
