# Görünüm modları ve tasarım sistemi v0

- Statü: **ÇALIŞMA MODELİ / ÖNERİ** (design-director, 2026-10-28). Kanon değildir; hiçbir sayı, ad, renk, yerleşim kesinleşmiş sayılmaz. Bu belgedeki tüm mesafeler **ÇALIŞMA DEĞERİ**dir (kodun sabitlerinden **hesaplanmış**, runtime'da **ölçülmemiş**).
- Tetikleyen: Creative Director'ın iki itirazı (sohbette, Studio Director aktardı; `design/decisions/` kaydı **henüz yok**): (1) "bu kadar zoom out yapamamalısın; o başka bir mod olabilir"; (2) token tabanlı, anlamları indekslenmiş, nesne tabanlı, atomic bir tasarım sistemi eksik.
- REQ: WLD-01, WLD-10, TEK-03, TEK-04, TEK-05, VIS-01, VIS-03, VIS-04, VIS-07, CAN-03, CAN-04, CAN-05, CAN-07, CAN-08, SIM-09, SIM-12, PLT-02, PLT-03, PLT-05, D-002.
- Ana belgeler: `ux-ia-v0.md` §5 (zoom ↔ UI) ve §8.4 (kamera akışı AÇIK) bu belgeyle **ayrıntılanır**, geçersiz kılınmaz. `ux-layout-v0.md` (profiller), `ux-states-a11y-v0.md` (renk tek başına anlam taşımaz), `ux-text-system.md` (gömülü metin yok, enum→anahtar veriyle).
- Kaynak kod/veri (okundu): `src/view/camera/camera_math.gd`, `camera_presets.gd`, `camera_sweep.gd`, `src/view/buildings/building_lod.gd`, `src/view/vegetation/vegetation_lod.gd`, `data/world/ismeral/{world,regions}.json`, `data/ui/ui_tokens.json`, `src/ui/**`, `src/contracts/*.gd`, `src/world/topology_map/*`, `scenes/dev/world_preview.gd`.

Kanıt dili: **[ölçüldü]** gerçek koşu/test çıktısı · **[hesap]** sabitlerden aritmetik · **[varsayım]** doğrulanmamış çıkarım · **[test edilmedi]**.

---

## 0. Canon kontrolü (özet)

```
CANON CHECK — Görünüm modları + tasarım sistemi
Verdict: CLEAR WITH CONDITIONS (+ Q-019 kullanıcı kararı; hiçbir görevi engellemez)
Touches: WLD-01, WLD-10, TEK-03, VIS-01, VIS-04, VIS-07, CAN-04, CAN-05, CAN-07, CAN-08, SIM-09, SIM-12, PLT-02/03/05
- [KANONİK] Ülke-metropol-ilçe-sokak-insan tek fiziksel 3D coğrafya; zoom'a göre farklı kıyı/yol/bina yok — F01 sütun 5, F02 "Alt ölçek sözleşmesi", F05-A — koşul: harita modu AYNI WorldData'nın temsili olmalı (§A.2.2)
- [KANONİK] Anderva kesintisiz ana kara — F01 "Dünya: Anderva", WLD-10 — bulgu: bugünkü 58 km açılış görüntüsü 40 km Ismeral kutusunu boşlukta yüzen bir ada gibi gösteriyor; bu, ana karanın sürekliliğini görsel olarak yalanlıyor (§A.1.1)
- [OY] Ülke ve ilçede aynı sanat grameri; Ref A "stilize, okunabilir kuşbakışı dünya" — F04 Ref A + "Görsel dil", VIS-01 — koşul: ülke ölçeği düz infografik değil, aynı gramerde kuşbakışı (§A.2.4)
- [OY] Uzak ölçekte metropol geniş ve çeşitli kütleli okunur — F04 "Uzak ölçekte", VIS-04 — 58 km'de bir insan 0,0 px, metropol ekran genişliğinin ~%53'ü [hesap]: VIS-04'ü de zayıflatıyor
- [OY] Yakında sokak, arsa, taşıt, insan, işyeri okunur — F01 "Oyuncu fantezisi", F02 ölçek 4 — koşul: alt sınır insan ölçeğini OKUNUR bırakmalı; göz hizası şart değil (§A.1.3)
- [KANONİK/kalite hedefi] Oyuncu yol/imar/kamu alanı kararını fiziksel 3D dünyada uygular — F03 "Oyun hissi için kabul ölçütleri" — sonuç: harita modu inşa/imar komutunun YERİ değildir (§A.2.3)
- [AÇIK] Kamera ve UX akışı, HUD, istatistik tabloları — F05-D; Q-011 madde "zoom akışı" — bu belge yalnız öneri + tunable veri; kullanıcıya Q-019
- [AÇIK] Anderva ülke haritasının UI/kartografik ayrıntısı — F05-B — uydurulmaz; ülke ölçeği M2 sonrası ve önce veri (§A.2.4)
- [TEKNİK] Kamera/LOD/streaming yöntemi, render yolu — F02 son paragraf, F05-D — technical-director ADR'ı (T-063)
- [KANONİK] Özel bina yerleştirme yok — CAN-03 — tasarım sistemi hiçbir modda "özel bina" aracı/ikonu tanımlamaz
- [OY] Tek popülerlik skoru yok — SIM-09 — nesne indeksinde grup başına ayrı tepki; toplam "memnuniyet" çipi yok
- [KANONİK] Konsept UI/ölçek okları kopyalanmaz — VIS-07 — ölçek göstergesi metin, ok/çubuk değil
Resolutions: (a) "Ayrı harita modu WLD-01 ihlali mi?" → Hayır, şu koşullarla: aynı WorldData geometrisi, aynı koordinat, ayrı el çizimi içerik yok, geçişte aynı odak korunur. Dayanak: TEK-03 ("LOD yalnızca temsil değiştirir") + F01 sütun 5 ("aynı fiziksel dünyanın farklı AYRINTI SEVİYELERİ") + F04 kaçınılacaklar ("her zoom'da farklı kıyı ... icat etmek"). Sembolik katman temsil değişikliğidir, coğrafya değişikliği değil. Belirsiz kalan: haritanın 3D'nin tepeden görünümü mü yoksa 2D kartografi mi olacağı → Q-019.2.
(b) "Harita modunda yol çizilebilir mi?" → F03 kabul ölçütü kararın 3D dünyada uygulanmasını ister; harita modu seçim/okuma/gezinme yapar, komut 3D'de verilir. Stüdyo varsayılanı; kanon tarafından çözülür, soru değildir.
Questions added: Q-019 (gruplu, 5 madde)
Safe to proceed with: kamera zarfının VERİ olarak tanımlanması ve test edilmesi, token v2 göçü (değerleri değiştirmeden), nesne indeksi v0, eksik atom/moleküller, T-045/T-046. Q-019 yanıtı yalnız veri değerlerini ve harita görünümünü değiştirir.
```

Yan bulgu (bu belgenin kapsamı dışı, izlenmeli): `production/STATE.md` T-062 kararı "saat kulesi yok (T0 landmarksız)". WLD-07 (OY) ve F02 D1 satırı saat kulesinin kentte görünmesini ister; hero modeli D-005'te reddedildiği için geçici boşluk kabul edilebilir ama **tasarım kararı değil, eksik varlık** olarak kayıtlı kalmalı (T-062 "Kullanıcı kararı: landmark" satırı zaten bunu taşıyor).

---

## A. Görünüm modları

### A.0 Mevcut durum [ölçüldü: kod okundu; runtime görüntüsü bu belgede alınmadı]

| Öğe | Değer | Kaynak |
|---|---|---|
| Dünya | 40 × 40 km, hücre 100 m | `data/world/ismeral/world.json` |
| Kamera uzaklık sınırı | 25 m – 90 000 m | `CameraMath.MIN/MAX_DISTANCE_M` |
| Eğim (pitch) | 8° – 88°, uzaklıktan bağımsız | `CameraMath.MIN/MAX_PITCH_DEG` |
| Dikey FOV | 40° (KEEP_HEIGHT) | `CameraPresets.FOV_DEG` |
| Açılış görüntüsü | `metro` = dünya genişliği × 1,45 = **58 km**, pitch 50° | `CameraPresets.metro`; `world_preview.gd:131` varsayılanı, `playable` bunu devralır; Home tuşu da `metro`'ya döner |
| Bölge preset'leri | yarıçap × 2,2, alt sınır 3 km → D1 9,2 km … D5 18,7 km | `CameraPresets.district` + `regions.json` [hesap] |
| Bina kademeleri | LOD0 (hero LOD1) < 1,45 km · LOD1 (PROXY) < 2,85 km · HLOD1 < 13 km · HLOD2 ötesi | `building_lod.gd` |
| Bitki kademeleri | LOD0 < 120 m · LOD1 < 400 m · sonra hücre lekesi | `vegetation_lod.gd` |
| Ölçüm aşamaları | metro ≥ 20 km · district ≥ 3 km · local ≥ 300 m · street | `camera_sweep.gd` (yalnız perf etiketi; oyuncuya ölçek olayı YOK) |

Görünür zemin ayak izi, 1920×1080, düz zemin yaklaşımı [hesap; runtime'da doğrulanmadı]:

| Uzaklık / pitch | Göz yüksekliği | Odakta görünen genişlik | Odağın ötesindeki zemin erişimi | 1,75 m insan | 4,3 m araç |
|---|---|---|---|---|---|
| 58 km / 50° (bugünkü açılış) | 44 km | 75 km | 39,7 km | 0,0 px | 0,1 px |
| 31 km / 50° | 24 km | 40 km | 21 km | 0,1 px | 0,2 px |
| 20 km / 40° | 12,9 km | 25,9 km | 20 km | 0,1 px | 0,3 px |
| 18 km / 45° | 12,7 km | 23,3 km | 14,6 km | 0,1 px | 0,4 px |
| 3 km / 40° | 1,9 km | 3,9 km | 3 km | 0,9 px | 2,1 px |
| 1,45 km / 35° | 830 m | 1,9 km | 1,9 km | 1,8 px | 4,4 px |
| 300 m / 25° | 127 m | 390 m | 1,2 km | 8,7 px | 21 px |
| 60 m / 12° (bugünkü `street`) | 12 m | 78 m | ufuk | 43 px | 106 px |
| 25 m / 8° (bugünkü alt sınır) | 3,5 m | 32 m | ufuk | 104 px | 255 px |

Sonuçlar:
- 58 km'de 40 km'lik dünya ekran genişliğinin ~%53'ünü kaplar ve **dört kenarı da kadrajdadır** → "uzayda ada" görüntüsü. Bu yalnız estetik değil: Ismeral'in doğusu kesintisiz ana karadır (F01, WLD-10), kutu kenarı bir kıyı değildir.
- Sorun yalnız uzaklık değil, **eğimdir**: bugünkü `district:D4` preset'i bile (17,6 km, 40°, kuzeye bakış) zemini odağın ~20 km ötesine kadar gösterir ve D4 çapası z = 8 km'de olduğundan **dünyanın kuzey kenarı kadraja girer** [hesap]. Üst sınır tek bir sayı olamaz; bir **kadraj kuralı** olmalıdır.

### A.1 3D dünya görünümü (serbest kamera)

#### A.1.1 Üst sınır: "kadraj dünya içinde kalır" kuralı + tavan uzaklığı

**Kural K1 (TEKNİK; ADR'a girer):** Sokak bandı dışındaki her kamera durumunda, görüş hacminin zemin düzlemiyle kesiştiği dörtgen (dört köşe ışını) `dünya sınırı − kenar payı` içinde kalır. Üst kenar ışını zemini kesmiyorsa (pitch ≤ FOV/2 + ε, ufuk görünür) durum sokak bandı dışında **geçersizdir**.
Çözüm sırası (deterministik, saf `CameraMath`): (1) pitch'i artır, (2) gerekirse uzaklığı azalt, (3) gerekirse odağı içeri kaydır. Kullanıcıya "duvar" hissi vermemek için yumuşak (sönümlü) uygulanır.

**Tavan uzaklığı D_max (ÇALIŞMA DEĞERİ): 18 km.** Gerekçe:
- En geniş bölge preset'ini (D5, 18,7 km) karşılar [hesap]; preset çarpanı 2,2 → ~2,1 ile hepsi tavanın altına girer.
- 18 km / 45°'de odakta ~23 km genişlik [hesap] = dünya genişliğinin ~%58'i: körfez, D1+D6 çekirdeği ve komşu bölgelerin kenarları birlikte okunur ("metropol çekirdeği"). **Dünyanın tamamı tek kadraja sığmaz**; bu bilinçli: altı bölgenin bütün ilişkisi (F02 ölçek 2) strateji haritasının işidir (A.2).
- K1 ile birlikte kenar her zaman kadraj dışında kalır; batı/kuzey kenarına yakın odaklarda (D3, D4) K1 pitch'i yükseltir.
- Seçenekler Q-019.1'de: (A) 18 km çekirdek tavanı (öneri), (B) ~31 km "metropol sığar" tavanı + K1 (dünya kenarı yine kadraj dışında olamaz; çünkü 31 km'de 40 km genişlik ancak kenar dahil sığar [hesap] → B fiilen K1 ile çelişir, kenar payı küçültülürse ada etkisi geri gelir), (C) yalnız açılış görüntüsünü değiştir, tavanı koru (önerilmez: kullanıcı itirazını karşılamaz).

**Uzaklığa bağlı alt eğim (ÇALIŞMA DEĞERİ):** `pitch_min(d)` log-uzaklıkta doğrusal: 50 m'de 12°, 1,5 km'de 25°, D_max'ta 40°. K1 asıl güvencedir; bu eğri yalnız K1'in sık devreye girmemesi için konfor eğrisidir.

**Kenar payı (ÇALIŞMA DEĞERİ):** 1,5 km. **Sokak bandında ufuk:** sokakta ufuk görünür ve 60 km uzak düzlem kenara erişebilir; kenar sis/pus ile kapanır (sis TEKNİK, coğrafya değildir). Kutunun dışında **arazi uydurulmaz**: doğuya "ana kara devamı" ancak Anderva makro verisi olduğunda (A.2.4) gösterilebilir; o güne kadar yalnız pus.

**Açılış görüntüsü:** `metro` değil, **başlangıç ilçesinin** `district` görünümü (`start_district_id` verisinden; D-002/CAN-08: kodda sabit ilçe yok, Orven zorunlu değil). Home tuşu "başlangıç ilçesine dön" olur; "tüm metropol" isteği strateji haritasını açar.

**Perf sürekliliği (TEKNİK):** T-062 A5 ve önceki perf tabanları `metro` preset'ine bağlıdır. Eski 58 km durumu yalnız geliştirici preset'i `metro_legacy_bench` olarak (oyuncuya erişilmez, `scenes/dev` ve `tools/perf.sh` için) korunur; yeni tavan için ayrı taban alınır. Aksi halde perf karşılaştırmaları kırılır.

#### A.1.2 Ölçek bantları (oyuncuya ölçek olayı) — ÇALIŞMA DEĞERİ

ux-ia §5'teki ölçekler tek dünyanın ayrıntı seviyeleridir; kamera uzaklığından türeyen **ölçek bandı olayı** üst şeritteki ölçek göstergesini (`zoom.*`, `TopBar` bugün bu olayı bekliyor) ve araç kapılarını (`zoom.locked_here`) besler. Bantlar mevcut LOD eşiklerine hizalanır ki "bantta görünen" ile "çizilen" tutarlı olsun:

| Bant (`zoom.*`) | Uzaklık [ÇD] | Dünyada okunan [hesap + LOD tablosu] | Araçlar (ux-ia §5) | Ne GÖRÜNMEZ |
|---|---|---|---|---|
| Sokak (`zoom.street`) | 50 m – 300 m | cephe, kaldırım, bitki LOD0/LOD1, donatı, insan ~9–40 px, araç ~20–100 px | kavşak/kesit ayarı, yerel inceleme | — |
| Mahalle (`zoom.neighborhood`) | 300 m – 1,5 km | parsel sınırları, bina hero LOD1 (LOD0 kademesi), yol kesiti farkı; insan ≤ 9 px → anlamsız | tüm araçlar, hassas düzenleme | insan/donatı tekil |
| İlçe (`zoom.district`) | 1,5 km – 8 km | bloklar, ana yollar, bina PROXY/HLOD1, bitki lekesi | İnşa (yol, bulvar, meydan), İmar (çokgen), Yönetim | parsel ayrıntısı, araç |
| Metropol çekirdeği (`zoom.metro`) | 8 km – D_max (18 km) | körfez, D1+D6 çekirdeği, ova/yamaç geçişi, HLOD1/HLOD2 kent kütlesi | Yönetim, katman okuma; çizim → `zoom.locked_here` | tekil bina, parsel |
| Metropol bütünü / Ülke | — (serbest kamerada YOK) | strateji haritası (A.2) | okuma, seçim, gezinme | — |

Histerezis (ÇALIŞMA DEĞERİ): bant sınırında ±%10 (gösterge titremesin). Bant olayı VIEW katmanında üretilir; sim bant okumaz (TEK-01, ADR-0004 "sim profili okumaz" ile aynı ilke).

#### A.1.3 Alt sınır: 50 m, pitch ≥ 12° (ÇALIŞMA DEĞERİ)

Bugün 25 m / 8° (göz yüksekliği ~3,5 m, fiilen göz hizası). Öneri: **50 m, alt eğim 12°** (göz ~10 m, "balkon/ikinci kat" bakışı). Kanon sınırı: F01 fantezisi ve F02 ölçek 4 insan ölçeğinin **okunmasını** ister; göz hizası/birinci şahıs bakış istemez. 50 m'de 1,75 m insan ~50 px, araç ~120 px, bank ~13 px [hesap] → sokak hayatı, taşıt ve işyeri okunur kalır.

Neden: göz hizası, low-poly varlıkların en zayıf olduğu ve en pahalı kademelerin (hero LOD0, insan LOD0, donatı LOD0) ancak orada gerektiği mesafedir. Bugünkü street perf tabanı p95 16,43 ms, bütçe 16,6 ms (`production/STATE.md`) [ölçüldü, önceki koşu] → en yakın kameranın maliyeti zaten sınırda.

İş paketlerine etkisi (hepsi **[varsayım]**: art-director'un 50 m'de gerçek yakalamayla LOD1 yeterliliğini onaylaması gerekir):

| Paket | Etki | M2'de mi? |
|---|---|---|
| T-062 "A-near" (hero LOD0 yakın kademesi) | Zaten koşullu; 50 m alt sınırla hero LOD1 yakın kademesi büyük olasılıkla yeterli → **M2 sonrası**, yalnız art-director 50 m yakalamasında LOD1'i FAIL ederse açılır | Hayır |
| T-059 insan (öneri teslimi bitti) | Oyun entegrasyonu zaten sim kaynağı (T-050) ve Q-018 stil seçimine bağlı; 50 m'de LOD1 (≤100 üçgen) yeterli olabilir, insan LOD0 (≤900) gereksizleşir | Entegrasyon **M2 sonrası** |
| T-058 donatı (öneri teslimi bitti; T-062 C aşaması) | 50 m'de bank ~13 px: görünür ama ayrıntı LOD1 yeter. C aşaması M2'nin geç ve isteğe bağlı kısmı; VIS-03 için değerli ama M2 nedensel döngüsü buna bağlı değil | M2-geç, isteğe bağlı |
| T-060 araç | M2'de trafik/araç sim kaynağı yok (T-050 M2→M3 köprüsü); kütüphane önerisi sürebilir, oyun entegrasyonu **M2 sonrası** | Hayır (yalnız kütüphane) |
| T-061 yol kesiti | **Gereksizleşmez**: sokak bandında 15 m'lik cadde ~75 px (300 m) ile ~450 px (50 m) arası [hesap]; kesit okunurluğu T-042 yol çizimi (CAN-04) için gereklidir. Ancak T-042'nin MANTIĞI T-061'e bağlı değildir (mevcut `road_style` ile çalışır) | Kütüphane önerisi M2; sınıf seçimi Q-018.5 |
| T-062 B (bitki) | Değişmez (LOD0 < 120 m sokak bandında görünür) | Evet |

Seçenekler Q-019.4'te.

### A.2 Strateji haritası modu

#### A.2.1 Amaç
- Metropol bütününü (F02 ölçek 2: altı çalışma bölgesinin ilişkisi, liman, ova, dağ etekleri, ulaşım, büyüme alanları) tek bakışta okumak; serbest kameranın tavanı yüzünden 3D'de artık görünmeyen ölçek.
- Uzak bir yeri seçip oraya gitmek ("Haritada göster"in tersi: "3D'de göster").
- Veri katmanlarını okumak (ux-ia §8.3 öneri C: katman + tablo; Q-011 madde 4).
- İleride (M2 sonrası) Anderva ülke ölçeği ve ulusal kariyer dönemi için tek giriş noktası.

#### A.2.2 Hangi veriden türer (tek kaynak; yeni coğrafi içerik yok)
| Harita öğesi | Kaynak | Not |
|---|---|---|
| Kıyı, su, adalar | `coast.json` → `WorldData` | 3D'deki kıyıyla aynı poligon; ada adı yok (CAN-01) |
| Rölyef / yükselti | `terrain.json` → `WorldData.height_at` | gölgeli rölyef ya da kontur (T-028 `TopologyContour` yeniden kullanılabilir) |
| Bölgeler D1..Dn | `regions.json` (çapa, yarıçap, atama) | etiket D-kodu; yalnız D2 "Orven" adı; sınırlar **"çalışma bölgesi, yaklaşık"** (F02, F05-B: resmî ilçe değil) |
| Yol/ray/feribot | `WorldNetwork` (+ T-042 deltası) | 3D yollarla aynı kenarlar |
| Liman/sanayi sahası | `sites.json` | T0 liman ana karada (WLD-03); veriden gelir, harita yerini "düzeltmez" |
| Kent kütlesi | yerleşim + `ParcelView.development` | HLOD2 kütlesi ya da parsel gelişim yoğunluğu |
| Veri katmanları | yalnız `SimFacade` (ParcelView, EconomyRegionOutcome, GroupReactionView, SimEvent) | sahte sayı yok; DTO'su olmayan katman listelenmez |

T-028 topoloji haritası (`src/world/topology_map/`) bu ilkeyi zaten uygulayan bir **geliştirici aracıdır** (izdüşüm, etiket yerleştirme, kontur); oyuncu haritasının yeniden kullanabileceği kod tabanıdır. Ama renkleri `TopologyStyle`'da gömülüdür (token'a göç gerekir, B.1) ve "ONAYSIZ (Q-015)" damgası taşır.

#### A.2.3 Ne gösterir / ne göstermez
**Gösterir:** coğrafya, bölge kapsamları, ağ hiyerarşisi, kent kütlesi, seçili nesne, oyuncunun yetki alanı (sim'den okunduğunda; bugün DTO yok → gösterilmez), olay kümeleri (sayılı), veri katmanları (imar, gelişim aşaması, arsa değeri, yatırım kararı olumlu/olumsuz, **grup başına** tepki), ölçek çubuğu (km, metin).
**Göstermez:** uydurma ad, parti/kurum rengi, tek "memnuniyet/popülerlik" katmanı (SIM-09), oynanabilir olmayan ilçeyi oynanabilir gibi (CAN-08), diğer altı metropolün ayrıntısı (M2'de hiç), konsept görsellerindeki UI/ok/istatistik (VIS-07), Q-015 onaylanmadan "onaylı" damgası.
**Eylemler:** seç, incele (L2 denetçi aynı panel), katman aç/kapat, "3D'de göster". İnşa ve imar komutları **3D'de** verilir (F03 kabul ölçütü). Haritada bir çizim aracı seçilirse dürüst kapı: `zoom.locked_here` + tek dokunuşla ilgili noktada 3D ilçe bandına iniş.
**Siyaset haritada kopuk bir kart oyununa dönüşmez** (F05-E son madde): meclis/bütçe panelleri harita modunda da aynı L2 panelleridir, ayrı ekran değildir.

#### A.2.4 Anderva ülke ölçeği
- Ülke ölçeği **yalnız strateji modunda** erişilir (serbest 3D tavanı metropol çekirdeğidir). Öneri; Q-019.5.
- **M2'de yok.** Önkoşul: Ismeral'i **aynı koordinatlarla içeren** bir Anderva makro dünya verisi + iç içe dünya ADR'ı (technical-director). Ismeral kıyısı ülke görünümünde `coast.json` ile birebir olmalı (WLD-01); Ref A bir görsel yöndür, koordinat değildir (CANON.md çelişki kuralı 3).
- Görünüm yönü onaylı: Ref A "stilize, okunabilir kuşbakışı dünya", aynı sanat grameri (VIS-01). UI ve kartografik ayrıntı AÇIK (F05-B) → uydurulmaz. Yedi metropol anlamlı kent kütlesi (WLD-10); hazır olmayan bölgeler oynanabilir gösterilmez (F01). Metropol adları (Varnis, Karvet…) kesin değil → etiket yok ya da nötr kod.
- Ülke yönetimi oynanmaz (CAN-07): ulusal dönemde ülke ölçeği kampanya/siyaset okuması içindir, devlet yönetim aracı değildir.

#### A.2.5 3D ↔ harita geçişi (öneri; ayrıntısı Q-019.3)
- Giriş: görünür düğme (iki profilde; dokunmatikte ≥ 56 pt birincil hedef) + masaüstü kısayolu (ÇD: `M`) + tavan sınırında uzaklaştırma sürdürülürse **ipucu** ("Tüm metropol için haritayı aç", tek dokunuş). Otomatik geçiş varsayılan değil (Q-019.3).
- Animasyon: aynı odak noktası korunarak kamera tepeye döner ve uzaklaşır, 3D ayrıntı HLOD2'ye iner, sembol katmanı belirir (≤ 0,6 s ÇD; "hareketi azalt" ayarında anlık). Dönüşte odak = haritada seçilen nokta, kamera ilçe bandına iner.
- Korunan durum: seçim, açık L2 paneli (ux-ia §5 kuralı), zaman hızı, çizim taslağı (L3 "taslak bekliyor").
- Harita kenarı: dünya kutusunun dışı **harita çerçevesidir** (nötr UI zemini), deniz/kara değildir; böylece kutu kenarı "dünyanın sonu" değil "haritanın sonu" okunur.
- Teknik yol (TEKNİK, T-063 ADR'ı seçer): (a) aynı 3D sahnenin tepeden ortografik/dik görünümü + harita malzeme takımı + sembol katmanı, ya da (b) aynı veriden 2D tuval (T-028 hattı). Tasarım tercihi (a)'dır: kıyı/yol geometrisinin birebir aynılığını yapı gereği garanti eder ve geçiş kesintisizdir. Kabul testi her iki yolda da: aynı dünya noktası 3D seçimde ve harita seçiminde aynı `ref`'e çözülür (seçim tutarlılığı testi).

---

## B. Tasarım sistemi (token + nesne indeksi + atomic)

Kapsam sınırı: bu sistem **bilgi katmanını** (HUD, paneller, dünya içi işaretler: seçim halkası, çizim önizlemesi, olay ikonları, harita sembolleri) yönetir. Dünyanın **malzemesi** (arazi, yol, bina, bitki görünümü) art-director'un alanıdır ve `data/library/`, `terrain_look.json`, `road_style.json` ile yönetilir (T-052 "varlık kütüphanesi"). İki sistem tek noktada buluşur: nesne indeksindeki 3D temsil sütunu katalog/LOD kademesine **atıf yapar**, onu tanımlamaz.

### B.1 Token katmanları ve göç

| Katman | İçerik | Örnek ad | Kim değiştirir |
|---|---|---|---|
| **Primitive** | ham değerler: nötr rampa, birkaç ton rampası, boşluk ölçeği, yazı ölçeği, yarıçap, süre | `color.neutral.850`, `color.blue.300`, `space.2`, `type.14`, `radius.s`, `duration.fast` | tema (Q-011 yanıtı yalnız bunu değiştirir) |
| **Semantic** | anlam: yüzey, metin, durum, veri yönü, dünya işareti, harita | `surface.panel`, `text.muted`, `status.mock`, `data.favor`, `data.against`, `data.estimate`, `world.selection`, `world.preview.valid/invalid`, `map.water`, `map.network.arterial`, `map.layer.<ad>.ramp` | ui-engineer (+ art-director dünya işaretleri için) |
| **Component** | bileşen bağları | `button.bg.hover`, `panel.width`, `bar.top.height`, `chip.height`, `meter.height`, `map.symbol.size`, `map.symbol.hit_min` | ui-engineer |
| **Profile** | profil sınırları (bugünkü `floors`, `limits`) | `profile.touch.floor.target` = 44, `profile.desktop.limit.panel_frac_side` = 0,28 | ui-engineer; değerler `ux-layout-v0` ile aynı kalır |

Kurallar: semantic yalnız primitive'e, component yalnız semantic/primitive'e başvurur (`"{color.neutral.850}"` + isteğe bağlı alfa); döngü ve kırık başvuru test hatasıdır. `src/ui/`, `src/game/` (HUD/overlay), `src/world/topology_map/` içinde ham `Color(...)` yasaktır (statik tarama; bugün `src/ui` içinde 1 adet `reason_glyph.gd:47`, `playable.gd:372,376` HUD durum etiketi, `TopologyStyle` tamamı [ölçüldü: grep]). Dünya malzeme renkleri (`terrain_palette`, `road_style`, `building_kit`) bu yasağın **dışındadır** (sanat verisi).

**Göç yolu (değer değişmeden):**
1. `ui_tokens.json` → `version: 2`, dört blok. Eski 18 renk + 17 boyut anahtarı **takma ad tablosu** ile yeni adlara bağlanır; `UiTokens.color("hud_bg")` çalışmaya devam eder (geçiş dönemi), yeni kod yeni adı kullanır.
2. Eşleme (öneri): `hud_bg→surface.hud`, `panel_bg→surface.panel`, `panel_bg_alt→surface.panel_alt`, `scrim→surface.scrim`, `text→text.primary`, `text_muted→text.muted`, `text_disabled→text.disabled`, `text_on_accent→text.on_accent`, `border→border.default`, `accent→accent.primary`, `focus→focus.ring`, `mock→status.mock`, `danger→status.danger`, `ok→status.ok`, `button_*→button.bg.*`; `body/small/title/heading→type.*`; `spacing→space.2`; `radius→radius.s`; `focus_width→focus.width`; `target_*→target.*`; `bar_*`, `panel_width`, `notif_width`, `toolbar_max_width`, `sheet_max_height`, `map_margin` → component; `floors/limits/safe_area_extra` → profile.
3. Kabul: göç öncesi/sonrası `ui_lab` ve `playable` yakalamaları piksel eşit (`tools/visual-diff.sh`), tüm takma adlar çözülür, ham renk taraması temiz.
4. Takma adlar bir sonraki minör sürümde kaldırılır (tüketiciler taşındıktan sonra).

Eksik semantic token'lar (bugün yok, ihtiyaç doğunca eklenir; değerleri nötr): `status.warning`, `data.favor/against/neutral/estimate` (bugün `ok/danger` ile karışık), `world.selection`, `world.preview.*`, `map.*`.

### B.2 Nesne-anlam indeksi (tek kaynak tablo)

Öneri dosya: `data/ui/entity_index.json` (ui-engineer sahibi; technical-director sözleşme uyumu incelemesi). Her tür için: kimlik/ref biçimi, kaynak DTO, durum alanları ve değerleri (**sözleşme sabitlerinden**, elle yazılmaz), nedensellik alanları, metin anahtarı ön eki, ikon kimliği, semantic token'lar ve **her modda temsil**. UI `match` yazmaz; temsil bu tablodan okunur (`ux-text-system` §5 kuralının genellemesi). DTO'su olmayan tür `sim_source: none` taşır ve UI onun için sim verisi gösteremez (sahte satır yok).

Durum sütunu yalnız mevcut sözleşmedeki değerlerdir [ölçüldü: `src/contracts/*.gd` okundu]:

| Tür | Kimlik / ref | Kaynak | Durumlar | Nedensellik alanları | 3D (bant) | Harita | HUD çipi | Panel |
|---|---|---|---|---|---|---|---|---|
| **parsel** | `parcel.<id>` (`REF_PARCEL`) | `ParcelView` | `development`: vacant · planned · under_construction · built · stalled; `decision`: "" · approved · declined; `zone`/`pending_zone`: `zone.*` (ui_config); `use`: residential · commercial | `decision_reason_id`, `reason_ids`, `owner` (ActorRef), `decision_code`, `progress_pm` | mahalle/sokak: sınır çizgisi + seçim halkası + imar önizleme boyası; ilçe: yalnız seçiliyse; metro: yok | imar/gelişim katmanında hücre rengi (toplulaşmış) | "Parsel · <imar> · <aşama>" | `ParcelInspector` + `ReasonPanel` (var) |
| **yapı** | ref YOK (sözleşmede yapı varlığı yok) | parselin `development/use/units` + T0 yerleşimi (görünüm verisi) | parselden türer | parselinki | hero kademeleri: LOD0(hero LOD1) < 1,45 km · PROXY < 2,85 km · HLOD1 < 13 km · HLOD2 | kent kütlesi | parsel çipine düşer | parsel denetçisi "Yapı" bölümü | 
| **yol** | ref YOK (T-042 `road.<edge_id>` ekler, ADR-0005 notu) | `WorldNetwork` kenarı (+ delta) | sınıf (ağ verisi); T-042 sonrası: taslak · uygulandı | T-042: altyapı kapasitesi etkeni gerekçede | `road_view` (sanat); seçimde vurgu; çizimde `world.preview.*` | sınıf hiyerarşisine göre çizgi | "Yol · <sınıf>" | T-042'de yol özellik paneli (L2/L3) |
| **ilçe/bölge** | `region_code` (D1..Dn; REF sabiti yok) | `WorldRegion` + `EconomyRegionOutcome` + `GroupReactionView` | oynanabilir mi (v1.1 isteği `ux-data-needs` §4c, **DTO yok**); yetki (DTO yok) | households, housed_households, units, pipeline, demand_*_pm, infrastructure_load_pm; grup tepkileri | ilçe/metro: isteğe bağlı sınır + D-kodu etiketi | sınır + etiket + özet | ölçek göstergesinde bağlam | T-041 bölge denetçisi (eksik) |
| **yatırımcı (aktör)** | `actor.investor.<n>` (`ActorRef`, ad yalnız `name_key` yer tutucu) | `ReasonRecord.actor` | karar sonucu: positive · negative | `factors` (ad, değer, ağırlık, tahmin, kaynak), `threshold`, `parent_ids` | fiziksel değil; sonucu parselde | olumlu/olumsuz karar işareti parselde | bildirim "Yatırımcı vazgeçti/başladı" | `ReasonPanel` |
| **grup** | `actor.<tür>.<n>` (group) | `GroupReactionView` | reaction: neutral · support · oppose · protest; stance, intensity | `cause_refs`, `reason_ids`, `stance_delta` | olay ikonu (protesto) — bantla toplulaşır | grup başına katman (toplam yok, SIM-09) | bildirim | `ReasonPanel` |
| **hane** | bireysel ref YOK | yalnız toplu: `EconomyRegionOutcome.households/housed_households` | — | bölge metrikleri | M2'de yok (insan = T-050, sim kaynağı gerekir) | bölge katmanı | yok | bölge denetçisi satırı |
| **bütçe kalemi** | `budget.<id>`, kalem `line_key` | `BudgetView`, `BudgetLineView` | bütçe: draft · proposed · approved · rejected | `reason_ids`, `pending_vote_id`; kalem amount/proposed/actual | yok (ileride proje sahası) | yok | üst şeritte bakiye (var, `¤` Q-003) | `BudgetPanel` (var) |
| **karar: meclis oyu** | `vote.<id>` | `CouncilVoteView` | pending · passed · failed; yes/no/abstain | `subject_ref`, `reason_ids`, blok pozisyonları | konusu fiziksel ise konu nesnesinde işaret | aynı | gündem rozeti (AgendaItemView yok → gizli) | `CouncilPanel` (var) |
| **karar: oyuncu komutu** | `command.<id>` | `CommandResult`, `SimEvent` | queued · rejected · applied | ret anahtarı `command.reject.*` | taslak/önizleme | — | bildirim | akış panelleri (var) |
| **karar kaydı (gerekçe)** | `reason.<id>` | `ReasonRecord` | positive · negative | tamamı | konu nesnesinde | — | "Neden?" bağlantısı | `ReasonPanel` |
| **olay** | `event.<seq>` | `SimEvent` | tür: command.applied/rejected · actor.decided · group.reacted · parcel.changed · budget.changed · council.vote_opened/resolved | `subjects`, `reason_ids`, `actor` | dünya içi ikon; sokak: tekil, ilçe: küme, metro: sayılı küme (ux-ia §5) | sayılı küme | `NotificationStrip` (var) | "Nedenini gör" → `ReasonPanel` |

Bilinen açıklar (dürüst kayıt): yapı ve yol için sözleşme ref'i yok; T0 yapısına tıklamanın hangi parsele çözüldüğü **doğrulanmadı**; bölge "oynanabilir" ve "yetki" alanları DTO'da yok (ux-data-needs §4c). Bunlar yeni görev değil, ilgili görevin (T-041, T-042, T-043) sözleşme notudur.

Doğrulama (T-066): indeksteki durum listeleri DTO sabitleriyle eşit (yansıma testi; sözleşme değişince test kırılır), her metin anahtarı `strings.tr.json`'da, her token `ui_tokens.json` v2'de, her panel sınıfı mevcut; indekste olmayan tür UI'da çizilmez (negatif test).

### B.3 Atomic hiyerarşi

| Seviye | Var (`src/ui/**`) | Eksik (öneri) |
|---|---|---|
| **Atom** | `ReasonGlyph` (çizilen simge), `MockBadge`, `MeterBar`, `ReasonFactorBar`, `ReasonMeter`; tema üzerinden Label/Button (`UiFactory`, `UiTheme`) | `Icon` (semantic ikon kimliği → çizilen glif; `ReasonGlyph`'in genellemesi, font bağımsız), `StateBadge` (aşama/durum: biçim + metin, yalnız renk değil), `NumberText` (birim/`¤`/tahmin işareti, `ux-text-system` §3), `LegendSwatch` |
| **Molekül** | `ActionButton` (düğme + devre dışı gerekçesi), `StateView`, `AgendaBadge`, `TimeControls` | `EntityChip` (ikon + etiket + StateBadge; tık → seç, "Haritada/3D'de göster"), `KeyValueRow` (etiket + değer + kaynak/MOCK + "Neden?"), `ScaleGateHint` (`zoom.locked_here` + tek dokunuş iniş), `HoverCard` (yalnız masaüstü, 3 satır; dokunmatikte eşdeğeri seçim), `LegendRow` |
| **Organizma** | `PanelShell`, `TopBar`, `ModeToolbar`, `NotificationStrip`, `ParcelInspector`, `ReasonPanel`, `BudgetPanel`, `CouncilPanel`, `AgendaPanel`, `ZoningFlowPanel`, `M2ResultPanel` | `DistrictInspector` (T-041), `ScaleIndicator` (bant olayı → metin), `ViewModeSwitch` (3D ↔ Harita), `MapLegend` / `LayerPicker`, `EntityHeader` (indeksten başlık) |
| **Şablon** | `HudLayout` (masaüstü yan panel / dokunmatik alt sayfa), `FlowPanel` | `InspectorTemplate` (başlık + KeyValueRow listesi + nedensellik zinciri + eylemler; satırlar indeksten), `MapModeLayout` (harita + lejant + aynı L2 panel) |
| **Sayfa** | `playable` (3D + HUD), `ui_lab` (geliştirici), `topology_map` (geliştirici) | Strateji haritası durumu (`playable` içinde mod, ayrı sahne değil), **bileşen galerisi** sayfası `ui_lab` içinde (her atom/molekül iki profilde, tüm durumlarıyla — tasarım sisteminin bakılabilir kanıtı) |

İlke: bir organizma veri biçimini bilmez; indeks + DTO → şablon → organizma. Yeni nesne türü eklemek = indeks satırı + metin anahtarları (+ gerekirse ikon), yeni panel kodu değil.

### B.4 Masaüstü + iPad dokunmatik profil kuralları (mevcut değerlerle uyumlu)

- Değerler değişmez: hedef ≥ 44 pt, birincil ≥ 56 pt, gövde ≥ 17 / yardımcı ≥ 13 pt, kenar payı ≥ 16 pt, aralık ≥ 8 pt, yan panel ≤ %28 (masaüstü) / ≤ %38 (dokunmatik yatay), alt sayfa ≤ %45, harita merkezinin ≥ %50'si görünür (`ui_tokens.json floors/limits`, `ux-layout-v0` §3.2).
- **Harita sembolleri ve dünya içi ikonlar:** görsel boyut küçük olabilir, **dokunma alanı** profil tabanından küçük olamaz (`map.symbol.hit_min` = `profile.touch.floor.target`); çakışan dokunma alanları kümeye toplanır (dokunmatikte küme tıklaması yakınlaştırır).
- **Kamera sınırları iki profilde aynıdır** (pinch ve tekerlek aynı zarfa çarpar; PLT-03: işlev eksilmez). Sınırda dokunmatikte titreşim yok, görsel geri esneme (ÇD).
- **Mod geçişi:** dokunmatikte görünür `ViewModeSwitch` zorunlu (kısayol yok); masaüstünde düğme + kısayol.
- **Hover:** `HoverCard` yalnız masaüstü; aynı bilgi dokunmatikte seçim → denetçi ile (ux-ia §7).
- `center_visible_min` harita modunda da geçerli; lejant + panel birlikte merkezi örtemez.
- iPad cihaz doğrulaması **AÇIK** (kullanıcı/cihaz); başsız boyut simülasyonu kanıt sayılır ama "iPad'de çalışır" denmez (TEK-04, PLT-06).

### B.5 Görsel dil sözlüğü (nötr, değiştirilebilir; Q-011 açık)

| Anlam | Semantic token | Bugünkü nötr değer | Renk dışı taşıyıcı (zorunlu) |
|---|---|---|---|
| Lehte / olumlu etken | `data.favor` | `ok` 8fd6a0 | ▲ glif + "Lehte" metni + çubuğun sağa uzanması |
| Aleyhte / olumsuz etken | `data.against` | `danger` ff9a90 | ▼ glif + "Aleyhte" + sola uzanma |
| Tahmin | `data.estimate` | (yok → çerçeve) | kesikli çerçeve + "tahmin" metni |
| MOCK / gerçek sim değil | `status.mock` | f2b84b | "MOCK" rozeti metni |
| Hata | `status.danger` | ff9a90 | ikon + tek cümle neden |
| Devre dışı | `text.disabled` | 8c96a2 | gerekçe satırı (ActionButton) |
| Odak | `focus.ring` | ffd666 | kalın halka (2 px) |
| Seçim (dünya) | `world.selection` | — (tanımlanacak, `accent` tonundan) | halka + panel başlığı |
| Çizim geçerli / geçersiz | `world.preview.valid/invalid` | — | düz / kesikli çizgi + L3 metni |
| İnşaat sürüyor / durdu | `StateBadge` | — | ikon biçimi (iskele / durdu) + metin |
| Grup tepkisi | `data.reaction.*` | — | ikon + grup adı anahtarı + yoğunluk sayısı; **toplam yok** |

İkon kimlikleri (semantic, çizim nötr geometrik glif, yazı tipine bağlı değil): `icon.parcel`, `icon.building`, `icon.road`, `icon.district`, `icon.investor`, `icon.group`, `icon.budget`, `icon.vote`, `icon.command`, `icon.event.protest`, `icon.event.construction`, `icon.event.declined`, `icon.favor`, `icon.against`, `icon.estimate`, `icon.mock`, `icon.scale_locked`, `icon.view.map`, `icon.view.world`.
Yasaklar: parti/kurum/bayrak rengi ya da logosu (Q-006, Q-009 açık), kırmızı-yeşil tek başına anlam, konsept görsellerinden ikon/ok (VIS-07), uydurma yer adı (CAN-01; etiketler yalnız D-kodu, Orven, Ismeral, Anderva), "özel bina" ikonu (CAN-03). Harita katman rampaları CVD-güvenli (`settings.colorblind_safe`, `ux-states-a11y` §1).

---

## C. İş paketleri ve sıralama

### C.1 T-041..T-046 üzerindeki etki ve önerilen sıra

| Sıra | Görev | Bu spec'e göre değişiklik |
|---|---|---|
| 1 (paralel) | **T-045** ölçüt 5 (projector/HUD yeni sorguya geçiş) | Etki yok; bağımsız sürer. |
| 1 (paralel) | **T-046** dokunmatik güvenli alan | Etki küçük: ölçüt 3'teki 480 px kipine düşüş `profile.*` token'larına yazılır. T-065'ten **önce** bitmesi önerilir (aynı `hud_layout`/token dosyalarına iki yazıcı olmasın). |
| 1 (paralel, yalnız belge) | **T-063** ADR-0007 (yeni) | T-064 ve T-068'in önkoşulu. |
| 2 | **T-064** kamera zarfı (yeni) | T-041 ölçüt 3 ve T-043 ölçüt 2'nin önkoşulu. |
| 2 | **T-065** token v2 göçü (yeni) | T-046 sonrası. |
| 3 | **T-066** nesne indeksi v0 (yeni) + **T-067** eksik atom/moleküller (yeni) | T-041'in panel satırları buradan gelir. |
| 4 | **T-041** denetçi | Ölçüt 3 "metro/ilçe/sokak" → "**metropol çekirdeği / ilçe / mahalle / sokak bantları** (T-064 bant olayı) + harita modu varsa orada aynı seçim". Ölçüt 1 bölge özeti `DistrictInspector` + `InspectorTemplate` ile. Ölçüt 7 yakalamaları bant adlarıyla. |
| 4 | **T-043** başlangıç ilçesi | Açılış kamerası T-064'ün `start_view(start_district_id)` işlevinden; T-043 kendi kamera kodunu yazmaz. Ölçüt 2'ye ekle: "açılış görüntüsünde dünya kenarı kadraj dışı (K1 testi)". |
| 5 | **T-042** yol çizimi | Çizim yalnız ilçe/mahalle/sokak bandında; metro bandında ve haritada `ScaleGateHint`. Önizleme renkleri `world.preview.*` token'larından. Yeni `road.<edge_id>` ref'i ve indeks satırı bu görevde. |
| 6 | **T-068** strateji haritası v0 (yeni) | T-041 ve T-063 sonrası; M2'nin son UI işi ya da M3 başı (Studio Director kararı). |
| 7 | **T-044** M2 kapı raporu | Eşleme tablosuna ekle: "3D'de tüm dünyayı ada gibi gösteren kadraj yok (K1 testi)", "harita aynı WorldData'dan (seçim tutarlılığı testi)", "token taraması temiz". |

Kimin neyi aldığı: technical-director → T-063 (ADR) + T-066 sözleşme incelemesi; godot-engineer → T-064, T-068 render/geçiş; world-engineer → T-068 harita veri katmanları (kıyı/ağ/bölge türetimi, T-028 kodunun yeniden kullanımı); ui-engineer → T-065, T-066, T-067, T-068 lejant/mod düğmesi, T-041 panel; art-director → T-064 50 m yakalaması LOD1 değerlendirmesi, T-068 harita görünüm kapısı; qa-engineer → her görevde bağımsız doğrulama; design-director → T-064/T-068 sadakat incelemesi.

### C.2 Yeni görev taslakları (TASLAK — dosya açılmadı; Studio Director görev başlarken `production/tasks/` altına açar)

Numaralar: bu dalda, `main`, `integration` ve `agent/handover-t048-roads-*` dallarında `T-063`+ yok [ölçüldü: `git ls-tree`].

```
# T-063 · ADR-0007: görünüm modları, kamera zarfı ve harita render yolu
- Durum: TASLAK · Milestone: M2 · Sahip: technical-director · İnceleyenler: design-director + godot-engineer
- Bağımlılıklar: — · Paralel grup: A
- REQ: WLD-01, TEK-03, TEK-04, TEK-05, PLT-05
- Dosya alanı: docs/adr/
## Amaç
Serbest kameranın üst/alt sınırını ve harita modunu, tek dünya ilkesini bozmadan, veri güdümlü ve test edilebilir biçimde sabitlemek.
## Kabul ölçütleri
1. K1 kadraj kuralının matematiği (düz-zemin yaklaşımı ve hata payı dahil), çözüm sırası (pitch → uzaklık → odak), sokak bandı istisnası ve sis rolü yazılı.
2. Kamera zarfı veri dosyası biçimi (öneri `data/view/camera_envelope.json`: D_max, D_min, pitch_min eğrisi, kenar payı, bant eşikleri, histerezis); değerlerin dünya boyutundan türetilme kuralı; kodda sayı gömülmez.
3. Harita render yolu seçimi (aynı 3D sahne tepeden + harita malzeme takımı vs 2D tuval), gerekçe + maliyet tahmini (hesap/ölçüm ayrı).
4. Perf sürekliliği: `metro_legacy_bench` dev preset'i ve yeni taban planı (T-062 A5 ile uyum).
5. Anderva iç içe dünya önkoşulu (ülke verisi Ismeral'i aynı koordinatla içerir) — yalnız ilke, uygulama yok.
6. Olumsuz: ADR, Q-019 yanıtını gerektiren hiçbir değeri kesinleştirmez; ÇD olarak işaretler.
## Kanıt planı
| Ölçüt | Kanıt | Komut / yol |
| 1–6 | ADR + design-director sadakat notu | docs/adr/0007-*.md |
## Kapsam dışı
Uygulama, ülke verisi üretimi, harita görsel tasarımı (Q-019.2, Q-011).
```

```
# T-064 · Kamera zarfı: kadraj dünya içinde, ölçek bandı olayı, başlangıç ilçesinden açılış
- Durum: TASLAK · Milestone: M2 · Sahip: godot-engineer · İnceleyenler: qa-engineer + design-director + art-director (50 m yakalaması)
- Bağımlılıklar: T-063 · Paralel grup: B
- REQ: WLD-01, WLD-10, VIS-04, TEK-03, TEK-04, CAN-08, D-002, PLT-03
- Dosya alanı: src/view/camera/, data/view/, scenes/dev/world_preview.gd, src/ui/hud/top_bar.gd (yalnız ölçek göstergesi bağlantısı), tests/view/, production/
## Amaç
Oyuncu serbest 3D kamerada dünyayı hiçbir zaman "uzayda ada" olarak görmez; ölçeği okur; oyun kendi seçtiği ilçeden açılır.
## Kabul ölçütleri
1. Sınırlar `camera_envelope.json`'dan; `CameraMath` sabitleri kaldırılır ya da yalnız güvenlik tabanı kalır; statik tarama: sayı gömülmez.
2. K1: başsız testte ≥ 10 000 rastgele durum (tüm bantlar dışı sokak) için zemin dörtgeni ⊂ sınır − pay; olumsuz: 90 km / 8° istek → zarfa kenetlenir, dörtgen içerde kalır; D3/D4 kenar odaklarında pitch yükselir.
3. Tekerlek, trackpad pinch ve dokunmatik pinch aynı zarfa çarpar (iki profil testi).
4. Bant olayı (sokak/mahalle/ilçe/metro) histerezisle yayılır; üst şerit ölçek göstergesi gerçek kameradan (`zoom.*` metni); sim bant okumaz (tarama).
5. Açılış ve Home = `district(start_district_id)`; kodda ilçe kimliği yok (tarama); `metro_legacy_bench` yalnız dev/perf.
6. Bölge preset'leri D_max altında; mevcut kamera testleri (90 000/58 000 sabitli) yeni zarfa göre yeniden tabanlanır, gerekçe raporda.
7. Gerçek pencereli yakalamalar: her bant + açılış + 4 kenar odağı (`m2-t064-*`); dünya kenarı yalnız sokak bandında sis arkasında. Art-director 50 m alt sınırda hero LOD1 yeterliliğini değerlendirir (PASS/FAIL A-near'ı belirler).
8. Perf: yeni taban + `metro_legacy_bench` karşılaştırması; kare maliyeti artmaz (ölçüm, iPad ölçülmedi diye yazılır).
## Kanıt planı
| 1–6 | GdUnit | tests/view/camera_envelope_test.gd, camera_math_*_test.gd |
| 7 | yakalama | tools/capture.sh … |
| 8 | perf | tools/perf.sh |
## Kapsam dışı
Strateji haritası (T-068), Q-019 değerleri (ÇD kalır), iPad cihaz testi (AÇIK).
```

```
# T-065 · Tasarım belirteçleri v2: primitive → semantic → component (+profile), değer değişmeden göç
- Durum: TASLAK · Milestone: M2 · Sahip: ui-engineer · İnceleyenler: qa-engineer + art-director
- Bağımlılıklar: T-046 · Paralel grup: B
- REQ: TEK-04, PLT-05, VIS-07, SIM-09 (renk tek başına anlam taşımaz)
- Dosya alanı: data/ui/ui_tokens.json, src/ui/core/ui_tokens.gd, ui_theme.gd, ui_context.gd, src/ui/** (yalnız ad göçü), src/game/playable.gd (yalnız HUD durum etiketi renkleri), tests/ui/
## Kabul ölçütleri
1. Dört blok + başvuru çözümleyici; döngü/kırık başvuru/bilinmeyen anahtar test hatası (olumsuz testler).
2. Eski anahtarlar takma adla çalışır; tüm tüketiciler yeni adlara taşınır.
3. `src/ui`, HUD/overlay kodunda ham renk yok (statik tarama; dünya malzeme kodu kapsam dışı).
4. `ui_lab` ve `playable` yakalamaları göç öncesi/sonrası piksel eşit.
5. Profil tabanları (`floors/limits`) değer olarak aynı; HudLayout testleri yeşil.
## Kapsam dışı
Yeni görsel kimlik (Q-011), TopologyStyle göçü (T-068'de).
```

```
# T-066 · Nesne-anlam indeksi v0 (entity_index.json) ve doğrulayıcı
- Durum: TASLAK · Milestone: M2 · Sahip: ui-engineer · İnceleyenler: technical-director (sözleşme uyumu) + qa-engineer + design-director
- Bağımlılıklar: T-065 · Paralel grup: C
- REQ: SIM-12, SIM-09, CAN-03, TEK-03
- Dosya alanı: data/ui/entity_index.json, src/ui/core/, tests/ui/
## Kabul ölçütleri
1. Türler: parsel, yapı, yol, bölge, yatırımcı, grup, hane (toplu), bütçe/kalem, meclis oyu, komut, gerekçe, olay; her biri B.2 sütunlarıyla.
2. Durum listeleri DTO sabitlerinden doğrulanır (yansıma testi); sözleşmede olmayan değer test hatası.
3. Metin anahtarı, token, ikon, panel sınıfı varlık testleri; eksik anahtar ham görünmez.
4. `sim_source: none` türü için UI sim alanı çizmez (olumsuz test); indekste olmayan tür çizilmez.
5. "özel bina yerleştir" eylemi hiçbir türde yok (CAN-03 taraması).
## Kapsam dışı
Yeni DTO (yalnız açıklar not edilir: yapı/yol ref'i, bölge oynanabilirlik/yetki).
```

```
# T-067 · Eksik atom/moleküller ve bileşen galerisi
- Durum: TASLAK · Milestone: M2 · Sahip: ui-engineer · İnceleyenler: qa-engineer + art-director
- Bağımlılıklar: T-065, T-066 · Paralel grup: C
- REQ: SIM-12, TEK-04, PLT-02, PLT-05
- Dosya alanı: src/ui/components/, src/ui/panels/, scenes/dev/ui_lab*, data/ui/strings.tr.json, tests/ui/
## Kabul ölçütleri
1. Icon, StateBadge, NumberText, LegendSwatch, EntityChip, KeyValueRow, ScaleGateHint, HoverCard (yalnız masaüstü), InspectorTemplate.
2. Her bileşen tüm durumlarıyla (normal/yükleme/boş/hata/kurulmamış/devre dışı) `ui_lab` galerisinde, iki profilde; gerçek yakalamalar.
3. Renk tek başına anlam taşımaz (her durum biçim + metin; test).
4. Dokunmatikte hit alanı ≥ 44 pt (birincil 56) ölçülür; 480–1600 px metin çakışması yok.
5. Gömülü metin yok (tarama).
```

```
# T-068 · Strateji haritası modu v0 (metropol bütünü; ülke yok)
- Durum: TASLAK · Milestone: M2-son / M3-baş (Studio Director) · Sahip: godot-engineer + world-engineer + ui-engineer · İnceleyenler: qa-engineer + design-director + art-director
- Bağımlılıklar: T-063, T-064, T-066, T-067 · Paralel grup: D
- REQ: WLD-01, TEK-03, VIS-01, VIS-07, CAN-04, CAN-08, SIM-09, SIM-12
- Dosya alanı: src/view/ (harita görünümü), src/world/topology_map/ (yeniden kullanım, token göçü), src/ui/, data/view/, data/ui/, tests/
## Kabul ölçütleri
1. Harita yalnız WorldData/WorldNetwork/regions/sites + SimFacade'den; ayrı harita içeriği/görseli yok (tarama + seçim tutarlılığı testi: aynı noktalar 3D ve haritada aynı ref'e çözülür; kıyı köşeleri birebir).
2. Bölgeler D-kodu, yalnız D2 "Orven"; "çalışma bölgesi, yaklaşık" notu; Q-015 onaysızlığı görünür.
3. Katmanlar yalnız DTO'su olanlar (imar, gelişim aşaması, arsa değeri, yatırım kararı, grup başına tepki); tek toplam skor yok (olumsuz test).
4. Geçiş: odak, seçim, açık panel, hız, taslak korunur; hareketi azalt ayarında anlık; iki profilde görünür mod düğmesi.
5. Haritada inşa/imar aracı seçilince ScaleGateHint → 3D ilçe bandına iniş (ölü düğme yok).
6. Dünya kutusu dışı harita çerçevesidir; uydurma kara/kıyı yok.
7. Gerçek yakalamalar (masaüstü + dokunmatik boyut), perf ölçümü; iPad cihazı AÇIK.
## Kapsam dışı
Anderva ülke ölçeği (T-069), harita görsel kimliği (Q-019.2/Q-011 yanıtına kadar nötr).
```

```
# T-069 · Anderva ülke ölçeği önkoşulu (PARK EDİLDİ — M2 sonrası)
- Durum: TASLAK / parked · Sahip: technical-director (ADR) → world-engineer · İnceleyenler: design-director + art-director
- Bağımlılıklar: T-063, Q-019.5, Q-015
- REQ: WLD-01, WLD-10, CAN-07, CAN-09, VIS-01
## Amaç
Ismeral'i aynı koordinatlarla içeren Anderva makro verisi ve strateji modunda ülke görünümü; Ref A yönünde stilize kuşbakışı, aynı gramer.
## Kabul ölçütleri (taslak)
1. Ismeral kıyısı ülke görünümünde `coast.json` ile birebir (test). 2. Yedi metropol anlamlı kütle, kesin olmayan adlar etiketlenmez. 3. Hazır olmayan bölgeler oynanabilir gösterilmez. 4. Ülke yönetimi aracı yok (CAN-07).
```

---

## D. Kullanıcı kararları

`production/QUESTIONS.md` → **Q-019** (gruplu; hiçbir görevi engellemez). Özet ve öneriler:

1. **Serbest 3D kameranın tavanı.** A) metropol çekirdeği, ~18 km, dünya kenarı asla kadrajda değil, metropol bütünü yalnız haritada · B) ~31 km "metropol sığar" (kenar payı küçülür, ada etkisi kısmen geri gelir) · C) yalnız açılış görüntüsü değişir. **Öneri A**: itirazınızı doğrudan karşılıyor; kanondaki "kesintisiz ana kara" ile çelişen ada görüntüsünü yapı gereği engelliyor.
2. **Strateji haritasının görünümü.** A) aynı 3D dünyanın tepeden, sadeleştirilmiş görünümü + sembol katmanı · B) aynı veriden 2D kartografik harita (T-028 tarzı, "kâğıt harita") · C) metropol A, ileride ülke Ref A yönünde. **Öneri A**: aynı kıyıyı/yolu yapı gereği garanti ediyor, aynı sanat gramerini koruyor (VIS-01), geçiş kesintisiz.
3. **3D → harita geçişi.** A) yalnız düğme/kısayol · B) tavanda uzaklaştırmayı sürdürünce otomatik geçiş · C) düğme + tavanda tek dokunuşluk ipucu, otomatik değil. **Öneri C**: istem dışı mod değişimi yok, keşfedilebilir. (Q-011'in "zoom akışı: sürekli mi, ölçek kapısı mı" maddesini bu soru ayrıntılandırır.)
4. **En yakın bakış.** A) ~50 m, "balkon" bakışı, göz hizası yok · B) bugünkü göz hizası (25 m) · C) A + ileride ayrı "yakından bak/fotoğraf" modu. **Öneri A** (C'ye açık): sokak hayatı okunur kalıyor, en pahalı yakın kademeler M2'den çıkıyor; street perf zaten bütçe sınırında.
5. **Anderva ülke ölçeği nerede?** A) yalnız strateji modunda, M2 sonrası, önce ülke verisi · B) serbest 3D'den de erişilsin (tavan çok yükselir, 1. soruyla çelişir). **Öneri A.**

Stüdyonun kendisinin önerip yürüteceği teknik kararlar (soru değil): K1 kadraj kuralı ve çözüm sırası, kenar payı, bant eşikleri ve histerezis, `metro_legacy_bench`, harita render yolu (ADR-0007), token dosya biçimi, nesne indeksi biçimi, ikon kimlikleri. Görsel kimlik (renk, ikon stili) **Q-011** altında açık kalır; sistem nötr değerlerle kurulur, yanıt yalnız primitive katmanını değiştirir.

Kayıt notu: Creative Director'ın sohbetteki sözü ("bu kadar zoom out yapamamalısın; o başka bir mod olabilir") bir **yön**dür. Studio Director bunu kullanıcının tam sözleriyle `design/decisions/D-006-*.md` olarak kaydedebilir (yalnız sohbette gerçekten söylendiyse; ajanlar karar yazmaz). Sayılar ve harita görünümü Q-019 yanıtına kadar ÇALIŞMA DEĞERİ kalır.

## Doğrulanmamış / bilinmeyen
- Tüm mesafe/piksel değerleri **hesaptır** (düz zemin, 1920×1080, FOV 40°); runtime yakalaması bu belgede alınmadı (Godot bu görevde çalıştırılmadı).
- 50 m'de hero LOD1 / insan LOD1 / donatı LOD1 yeterliliği **varsayımdır**; art-director'un gerçek yakalamasıyla karar verilir.
- Harita modunun perf maliyeti ölçülmedi; bugünkü 58 km açılış tüm dünyayı zaten çiziyor, bu yüzden haritanın daha pahalı olmayacağı **varsayımdır**.
- T0 yapısına tıklamanın parsele çözümü doğrulanmadı.
- iPad cihazında hiçbir şey doğrulanmadı (AÇIK).
