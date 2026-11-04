# Low-poly yapı kiti v1 — sanat hedefi spesifikasyonu (T-051 ölçüt 1)

- Statü: **ÇALIŞMA MODELİ** (art-director, 2026-10-25). Kanon değildir; kanonla çelişirse kanon kazanır (`design/CANON.md`). `building-kit-v0.md`'nin yerine geçmez, onu **genişletir**: v0'daki ölçek tablosu (§2), saat kulesi kuralı (§4), malzeme mimarisi (§6: tek surface, UV0 parça kimliği, palet satırı örnek verisinden) aynen geçerlidir. Bu belge yalnız v0'da değişen/eklenen kuralları verir.
- REQ: VIS-01, VIS-02, VIS-04, WLD-07 (ayrıca VIS-03, VIS-05, WLD-01, WLD-04).
- Tüketenler: `technical-artist` (üreteçler `art/blender/generators/`, `assets/kit/kit_palette.json`), `world-engineer` (`data/world/ismeral/settlement.json` bölge/zon ağırlıkları), `godot-engineer` (palet satır sayısı, gölgelendirici), `qa-engineer` (§10 ölçümü).
- İşaretler: **[K]** kanondan · **[ÇM]** art-director çalışma değeri (veri; ölçümle veya kullanıcı kararıyla değişir) · **[AÇIK]** kullanıcı kararı gerekir.
- Kıyas paketi (bu belgeyle birlikte): `design/specs/art/building-kit-v1-compare/01_district_vs_ref.png`, `02_street_port_vs_ref.png`, `03_metro_vs_ref.png`, `04_palette_v0_vs_v1.png` (Tur 1 palet şeridi).

> Referanslar (`02_*` seçili T0/olgun kıyas, `03_*` mimari yön) **konsept sanattır**: sinematik ışık, fotogerçekçi doku, kart/etiket hedef değildir [K, VIS-01, VIS-07]. Alınan: **renk ilişkisi, çatı karakteri, kütle hiyerarşisi, doku ritmi, bölge kimliği**. Birebir bina/konum kopyası yok (F05-C).

---

## 0. Fark analizi — referans ile bugünkü oyun (gözlem / ölçüm / çıkarım ayrı)

### 0.1 İncelenen görüntüler
| Görüntü | Ne | Not |
|---|---|---|
| `artifacts/screenshots/captures/20261025-135758-roads-district.png` | ilçe preset'i, tek yerleşim | **Hangi bölge olduğu kayıtta yok** (argüman dosyası yok); D1 olduğu doğrulanmadı |
| `artifacts/screenshots/captures/20261025-135852-roads-street.png` | `street:port` (D3 liman sanayisi) | D1 sokak yakalaması yok (aşağıya bkz.) |
| `artifacts/screenshots/captures/20261025-135945-roads-metro.png` | metro, 3360×1890 | |
| `artifacts/screenshots/captures/20261024-172142-playable-smoke-k8-lod0.png` | sanayi avlusu ızgarası (yakın-orta) | |
| `design/foundation/visual-references/02_*` (T0 üst yarı + D1/D3/D6 kesitleri), `03_*` (genel, ZOOM 2/3/4) | referans | |

**D1 sokak/ilçe yakalaması alınamadı:** 2026-10-25 14:07'de `tools/capture.sh … --preset=street:D1` ve `district:D1` düz gri kare üretti; `artifacts/verify/capture.err.log`: `Could not find type "TerrainLook"` (paralel T-049B çalışmasının commit'lenmemiş `src/view/terrain/terrain_look.gd` dosyası, sınıf önbelleği güncel değil). Bozuk kareler silindi. **Kit v1 "önce" taban çizgisi D1 için T-049B derlenir hâle gelince alınmalıdır** (§10.1).

### 0.2 Ölçülen renk sınıfı payları (yapı alanı kırpıntısı, HSV eşikleri §10.3)
| Kırpıntı | Kiremit | Sıcak/kahve cephe ("diğer"+"sıcak") | Gri + mavi-gri | Yeşil (yapılar arası) |
|---|---|---|---|---|
| REF 03 ZOOM3 tarihî çarşı (700,640–1140,800) | **%37** | %22 | %19 | %1 |
| REF 03 genel D1 (430,330–700,420) | %21 | %22 | %9 | %1 |
| REF 02 T0 D1 (470,300–760,400) | %19 | %17 | %15 | %3 |
| OYUN ilçe (640,380–960,560) | **%3** | %16 | **%57** | **%21** |
| OYUN sokak port (0,230–1600,600) | %3 | %5 | %38 (+%14 açık) | %39 |
| OYUN metro yerleşim lekesi | %1 | %8 | %24 | %66 |

Referans pikselleri sinematik ışıkla karartılmış (koyu sınıfı %15–26); bu yüzden mutlak değerler değil **oranlar** kıyaslanır. Sonuç tersine dönmüş bir dağılım: referansta sıcak (kiremit + krem/okra) ≈ %40–60, gri ≈ %10–20; oyunda sıcak ≈ %19, gri ≈ %57.

### 0.3 En önemli farklar (öncelik sırasıyla)
1. **Çatı alanı soğuk gri; kiremit yok denecek kadar az (gözlem + ölçüm).** İlçe görüntüsünde kent "gri-beyaz kumlanma + seyrek turuncu nokta"; referansta baskın okuma "kiremit kırmızısı + krem cephe yaması". Nedenler (koddan, çıkarım değil): `settlement.json` `tile_cap` center 0,38 / historic 0,50; `res_mid` ve `res_late_a/c` yalnız düz teras (R1 #A8A49C soğuk gri, R2 bitüm); evlerde R6 sac %17; kiremit tonları R4/R5 soluk ve kahve-gri olduğundan uzakta griye kayıyor. v0 §3.2 bu payı bilinçli kısmıştı (VIS-05 "tüm çatılar kiremit" reddi); sonuç referansın çok uzağına düştü.
2. **Yapılar çimin üstüne serpilmiş (gözlem).** İlçe kırpıntısının %21'i, sokak kesitinin %39'u yapı aralarındaki **çim yeşili**. Referansta kent zemini taş/asfalt/avlu; yeşil yalnız ağaç lekesi. Bu, "maket/oyuncak" okumasının bina kitinden bile güçlü nedeni. (Arazi işi: T-049B'ye bağımlılık, §8.4.)
3. **Kütle hiyerarşisi yok; her şey aynı 1–3 kat ölçeğinde okunuyor (gözlem).** Referans: alçak sık tarihî çekirdek (3–4 kat, kırma kiremit) ↔ kıyıda 6–8 katlı apartman şeridi ↔ yatay sanayi ↔ (olgunda) seyrek kule kümesi. Oyunda ilçe görüntüsü tekdüze doku; sokak (port) görüntüsünde sanayi hangarları ev gibi beşik çatılı, aynı boyda, avlusuz.
4. **Cephe ritmi okunmuyor (gözlem).** Referansta en güçlü cephe işareti düzenli koyu pencere ızgarası + saçak gölge çizgisi + zemin kat tente bandı. Oyunda pencere yalnız birkaç modülde (ör. port'taki taş bina); hangarların çoğu boş düz yüzey; saçak taşması yok; tente/kepenk bandı uzaktan görünmüyor.
5. **Yeşillik ve bölge kimliği yok (gözlem).** Referansta palmiyeli kıyı/meydan, avlu ağaçları, yamaçta çam/zeytin lekeleri D1/D5/D6'yı ayırır. Oyunda kentte ağaç yok; bölgeler (yerleşim lekeleri) metroda aynı gri daireler; D1+D6'nın "çekirdek" olduğu metroda okunmuyor (lekeler küçük ve eşit — yerleşim şekli T-049A kapsamı, bu belge değil).
6. Ek: metroda yerleşim lekeleri araziden yalnız parlaklıkla ayrılıyor, renk karakteriyle değil (HLOD renk taşıyor ama taşıdığı renk gri). Liman sanayisi (D3) "3 konteyner" değil ama "bir sürü ev biçimli hangar" — avlu, istif, vinç/baca silueti yok (VIS-04).

### 0.4 Kit v0'ın envanteri (manifest, 36 modül)
Aileler: `res_old` a–d (+gf), `res_mid` a–d (+gf), `res_late` a–c (+gf), `res_house` a–e, `ind_shed` a–c, `ind_heritage` a–b, `civ_hall` a–c, `lmk_clocktower`, `prop_chimney`, `prop_human`, `veh_car`, `veg_plane`. LOD0 96–698 üçgen, LOD1 22–84, PROXY 10–14. **Eksik:** v0 §1'deki `com_bazaar`, `off_mid`, `ind_workshop`, `civ_school`, `civ_pier`, `res_new`, `off_tower`, palmiye/çam/zeytin; ayrıca 3–4 katlı kırma kiremitli eski kent yapısı (referansın asıl dokusu) hiç yok — `res_old` 2–3 kat ve dar.

**Teşhis:** Sorun kozmetik değil; renk dağılımı (veri), kütle aileleri (geometri) ve kent zemini (arazi) birlikte yanlış. Yalnız palet düzeltmek kenti "turuncu kumlanma"ya çevirir; yalnız mesh eklemek gri halıyı korur. Tur 1 üçünü birden ele alır (§11).

---

## 1. Kurallar özeti (v0 §0'a ek)
1. **Uzaktan okunan üç şey:** çatı rengi alanı, kütle yüksekliği sırası, yapı arası zemin. Yakından okunan üç şey: çatı formu + saçak, pencere ritmi, zemin kat bandı. Kit bu altı şeyi korumak zorunda; gerisi süs.
2. **Sıcak Ege paleti, kısık doygunluk:** kiremit hue 14–24°, S ≤ 0,66; cephe S ≤ 0,42; soğuk mavi-gri yalnız sanayi sacında ve yeni/olgun yapılarda.
3. **Kiremit baskın ama her yerde değil** (§3.3 payları); her kiremit alanında ≥ 3 ton; düz teraslar sıcak gri ve çatı ekipmanlı.
4. **Kent zemini kenttir:** yapılı bloklarda yapı arası zemin döşeme/avlu rengi; çim yalnız park/bahçe/kırsal.
5. Tek dünya: her preset aynı örnek verisinden (WLD-01); LOD/HLOD yalnız sadeleştirir, rengi ve kütle sırasını korur.

---

## 2. Palet v1 [ÇM]

Hedef değerler sRGB. Referans piksellerinden alınan **ton (hue) ve doygunluk ilişkisi** korunmuş, parlaklık oyun ışığına (v0 §5, gündüz) göre yükseltilmiştir (referans koyu sınıfı sinematik). Referans baskın renkleri (ZOOM3 kırpıntısı, 10 renk niceleme): #9A6043 kiremit %17, #6D4D40/#583C33 gölgeli kiremit %19, #A28571 kum taşı %10, #C4B19F krem %8, #E2D3BF kırık beyaz %6.

### 2.1 Tur 1 — mevcut 32 satıra sığar (`assets/kit/kit_palette.json`, satır dizini aynı)
Satır kimlikleri v0 ile aynı tutuldu (kod/veri anahtarları kırılmasın); değişen satırlar **kalın**. X1/X2 rezervleri kullanıldı.

| Satır | Kimlik | Ad | v0 hex | **v1 hex** | Kullanım |
|---|---|---|---|---|---|
| 0 | W1 | sıcak kireç beyazı | #D9D2C3 | **#DED3BF** | her dönem konut, yaygın |
| 1 | W2 | krem | #D6C6A3 | **#D9C49E** | eski/orta konut, kamu |
| 2 | W3 | okra | #C9A978 | **#CBA675** | eski konut, çarşı (≤ %15) |
| 3 | W4 | şeftali sıva | #C79A80 | **#CF9F82** | eski/orta konut (≤ %12) |
| 4 | W5 | sıcak açık beton | #B5B1A8 | **#BCB4A6** | orta/geç apartman, ofis |
| 5 | W6 | soluk sarı (v0: adaçayı) | #A9B09A | **#D6C58E** | orta dönem pastel (≤ %10) |
| 6 | W7 | soluk mavi-gri | #A3AEB3 | **#AAB3B5** | yalnız geç/yeni (≤ %6) |
| 7 | W8 | kum taşı | #BFA88A | **#C2A57E** | eski/kamu/çarşı |
| 8 | W9 | eski beton | #8F8B83 | **#9A948A** | geç konut, sanayi |
| 9 | W10 | tuğla | #9A5C44 | **#9A5A40** | eski sanayi, işçi konutu aksanı |
| 10 | W11 | kesme taş | #A89C86 | **#B2A386** | kamu, kule, eski sanayi |
| 11 | W12 | sanayi krem metal | #C2BBA6 | **#CCC6B2** | hangar |
| 12 | W13 | sanayi mavi-gri metal | #7E8C96 | #7E8C96 | hangar (≤ %30 sanayide) |
| 13 | R1 | teras açık (sıcak) | #A8A49C | **#B8AE9F** | düz çatı |
| 14 | R2 | teras koyu/bitüm (sıcak) | #6E6B66 | **#756D66** | düz çatı (teras alanının ≤ %30'u) |
| 15 | R3 | kiremit | #A8644C | **#B05E3D** | kiremit ana ton (kiremit alanının %35–45'i) |
| 16 | R4 | açık kiremit | #B07A5E | **#C27A52** | kiremit (%20–30) |
| 17 | R5 | eski kiremit | #7E5E4E | **#8C4F37** | kiremit (%15–25) |
| 18 | R6 | açık sac | #9EA3A6 | **#AAACA8** | sanayi |
| 19 | R7 | koyu sac | #5F6B73 | **#65707A** | sanayi |
| 20 | R8 | kurşun gri | #7D8288 | #7D8288 | kule, kamu tepesi |
| 21 | G1 | cam/oyuk/pencere | #3A4148 | **#2F353B** | pencere, dükkân camı (daha koyu = ritim okunur) |
| 22 | A1 | tente kiremit-kahve | #7A4E3A | **#8A4E3A** | tente/kepenk |
| 23 | A2 | tente petrol | #3F5E6A | #3F5E6A | tente/kepenk |
| 24 | A3 | tente hardal | #8A7A4A | **#A08A52** | tente/kepenk |
| 25 | P1 | gövde | #6B5A48 | #6B5A48 | ağaç gövdesi |
| 26 | P2 | yaprak zeytin-yeşil | #6F7A4A | **#5F7442** | çınar, zeytin |
| 27 | P3 | yaprak koyu | #5F7048 | **#4A6236** | çam, servi, palmiye |
| 28 | P4 | yaprak kuru | #7E8350 | #7E8350 | kuru/yaz |
| 29 | P5 | ten | #B58E73 | #B58E73 | insan |
| 30 | X1→**R9** | solmuş kiremit | #8A8A8A | **#B98B70** | kiremit (%10–20; eski/kırsal) |
| 31 | X2→**A4** | panjur yeşili | #8A8A8A | **#56664A** | eski ev panjuru, kapı |

Doğrulama sınırları: kiremit (R3/R4/R5/R9) hue 14–24°, S 0,38–0,66, V 0,55–0,76; cephe S ≤ 0,42 (tuğla ≤ 0,60), V 0,58–0,87; teras R1/R2 hue 20–35° (sıcak gri, mavi değil). "Oyuncak" sınırı: S > 0,70 hiçbir satırda yok [VIS-05].

### 2.2 Tur 2 — 64 satıra genişleme [ÇM; teknik onay: technical-director]
`assets/kit/kit_material.gd` `ROW_COUNT`/`INSTANCE_SCALE` = 32 ve HLOD önbellek anahtarı 32 tabanlı; 64'e çıkış godot-engineer işi (custom data kesinliği Compatibility'de ölçülmeli). Eklenecek satırlar:

| Kimlik | Ad | Hex | Kullanım |
|---|---|---|---|
| W14 | yeni beyaz | #E4E1DA | 2000+ konut/ofis |
| W15 | açık modern gri | #C6C5BF | yeni/ofis |
| W16 | grafit aksan | #5E6266 | yeni cephe düşey bandı |
| W17 | geç dönem bej | #CDBDA2 | 1980–2000 apartman |
| W18 | soluk terra sıva | #C59A80 | geç dönem |
| W19 | beyaz sac | #D3D1CA | modern depo/lojistik |
| G2 | mat cam mavi-gri | #6E8594 | ofis/kule cam bandı (yansımasız) |
| R10 | paslı sac | #8C6A55 | eski hangar, köy ambarı |
| R11 | tonoz açık | #BFC0BB | tonoz depo |
| R12 | güneş kollektörü | #3E4A58 | teras ekipmanı |
| R13 | su deposu | #D8D4CC | teras ekipmanı |
| R14 | sera örtüsü (mat) | #D5DAD0 | D4 sera |
| A5 | tente kırmızı (kısık) | #9A4A3C | çarşı/cadde |
| A6 | tente krem | #D2C29A | kıyı/kafe |
| A7 | tente yeşil | #4E6A52 | çarşı |
| A8 | kepenk metal | #8E9294 | kapalı dükkân |
| P6 | palmiye yaprağı | #6B7D3E | palmiye |
| P7 | servi/çam koyu | #3F5634 | yamaç |
| U1 | kent döşemesi (açık) | #B9AE9C | meydan/avlu/kaldırım (arazi/yol işi, kit değil) |
| U2 | asfalt sıcak | #5F5D5A | yol (T-048 stil verisi) |

### 2.3 Dönem başına cephe/çatı aileleri (veri tablosu; `wall_rows`/`roof_rows` manifest alanlarına geçer)
| Dönem | Cephe satırları (ağırlık) | Çatı satırları | Aksan |
|---|---|---|---|
| **Eski** (1950 öncesi: `res_old*`, `com_bazaar`, `com_han`, `res_old_town`) | W2 .26, W1 .22, W8 .16, W3 .14, W4 .12, W6 .05, W11 .05 | kiremit: R3 .38, R4 .24, R5 .20, R9 .18 · teras: R1 | A4 panjur, A1/A3 tente |
| **Orta** (1950–1980: `res_mid*`) | W1 .30, W2 .20, W5 .16, W6 .10, W4 .08, W3 .06, W7 .04, W9 .06 | teras R1 .70/R2 .30 · kiremit (kırma varyant): R3/R4/R5/R9 | A1/A2/A3 |
| **Geç** (1980–2000: `res_late*`) | W1 .28, W5 .24, W9 .14, W17 .12*, W18 .10*, W7 .06, W2 .06 | teras R1/R2 · alçak kırma: R4/R5/R9 | A2, A1 |
| **Yeni** (2000+: `res_new`, `off_*`) | W14* .35, W15* .25, W5 .20, W16* .10, G2* .10 | teras R1 + ekipman | G2 |
| **Sanayi** (`ind_*`) | W12 .30, W13 .22, W9 .20, W19* .14, W10 (yalnız heritage) | R6 .45, R7 .30, R10* .10, R11* (tonoz), R8 | A3 kapı |
| **Kırsal** (`res_house`, `agr_*`) | W1 .34, W2 .26, W8 .14, W3 .10, W4 .08, W11 .08 | R3/R4/R5/R9 (.90), R10* .10 | A4 |

`*` = Tur 2 satırı; Tur 1'de en yakın Tur 1 satırıyla (W17→W2, W18→W4, W14→W1, W15→W5, W16→W9, G2→W7, W19→W12, R10→R5, R11→R6) temsil edilir.

---

## 3. Çatı türleri ve payları

### 3.1 Çatı türü kataloğu
| Kod | Tür | Geometri (low-poly) | Nerede | LOD1/HLOD'da |
|---|---|---|---|---|
| RK-K | **kiremit kırma** (referansın baskın formu) | 4 yüz, eğim 20–26°, **saçak taşması 0,5–0,7 m** (alt yüz koyu: duvar × 0,6) | eski kent, orta dönem apartman %35–45'i, ev | 4 yüz kalır (≤ 8 üçgen); HLOD: kiremit renkli tepe |
| RK-B | kiremit beşik | 2 yüz + 2 alınlık, eğim 22–30°, saçak 0,4–0,6 m | sıra ev, işçi konutu, köy | 2 yüz kalır |
| RK-A | alçak kırma (geç dönem) | eğim 12–18°, saçak 0,4 m | geç apartman | 4 yüz |
| RT | **teras + parapet + ekipman** | parapet 0,9 m; üstte 1–3 kutu: su deposu (Ø1,2 silindir 6 kenar veya kutu 1,2×2×1,1, R13), güneş kollektörü (2,0×1,0 eğik plaka, R12, 1–4 adet), merdiven kutusu (2,5×3×2,6) | orta/geç/yeni apartman | kutular LOD1'de 1 birleşik kutu; HLOD'da yok |
| RS | sanayi sac beşik | eğim 8–12°, saçak 0,3 m | hangar | 2 yüz |
| RN | **tonoz** (barrel) | 6–8 segment yay, uçlar dikey alınlık | depo, liman antreposu, eski pazar halleri | LOD1: 3 segment |
| RD | testere dişi | diş 4–5 m, cam yüz G1 | eski/yeni fabrika | LOD1: 2–3 diş |
| RM | tek eğim | 6–10° | atölye, dükkân sırası arkası | 1 yüz |
| RX | özel (kule/kamu) | kurşun R8 kırma/kubbesiz tepelik | saat kulesi, kamu | kendi proxy'si |

Yasak: dik alp çatısı (> 35°), sivri kampanil külahı, kubbe (S1 AÇIK), tüm kenti tek ton kiremit [K, VIS-05].

### 3.2 Neden v0 payları değişiyor
v0 §3.2 kiremidi metro genelinde ≤ %35, merkezde ≤ %55 ile sınırlamıştı; uygulamada (`tile_cap` center 0,38) ilçe görüntüsünde kiremit piksel payı **%3**'e düştü (ölçüm §0.2). Kanonun reddettiği "**bütün** çatılarda **aynı** kırmızı kiremit" ve "eski mahallelerin **tümü** Adriyatik kartpostalı"dır [K, F02, F04]; kiremidin baskın ama karışık olması reddedilmez ve seçili referans (02) bunu gösterir. v1 payları bu ikisi arasındadır. **Bu değerler [ÇM] ve S2 (kiremit payı) hâlâ kullanıcı sorusudur** (`production/QUESTIONS.md` Q-005…Q-013 / v0 §11 S2): değerler veri dosyasında; kullanıcı daha az/çok kiremit isterse yalnız `tile_cap` değişir.

### 3.3 Çatı alanı payı hedefi (zon başına; `settlement.json` `zones.*.tile_cap` ve aile seçimine geçer) [ÇM]
| Zon (settlement) | Bölge | Kiremit (RK-*) | Teras (RT) | Sac/tonoz/testere (RS/RN/RD) | Diğer |
|---|---|---|---|---|---|
| `historic` | D1, D6 çekirdek halkası | **%60–72** | %22–35 | ≤ %5 | kamu R8 ≤ %5 |
| `center` | D1, D6 merkez | %40–55 | %40–55 | ≤ %5 | ≤ %8 |
| `dense` | D1/D6 dış halka | %38–52 | %42–58 | ≤ %6 | — |
| `town_center` | D2, D3 merkez | %50–62 | %30–45 | ≤ %8 | — |
| `town` | D2, D3 konut | %58–70 | %20–35 | ≤ %10 | — |
| `harbor` / `yard` | D3 liman, sanayi avlusu | ≤ %12 (yalnız eski sanayi + işçi evi) | %10–20 | **%65–80** | — |
| `hill_center` / `hillside` | D5 | %62–78 | %18–32 | ≤ %6 | — |
| `village` / `farm` | D4 | %65–80 | %8–20 | %10–20 (ambar/depo/sera) | — |

Kesin sınırlar (ölçülebilir, yerleşim verisinden sayılır): herhangi 500 × 500 m kentsel pencerede kiremit çatı alanı **≤ %72** ve **≥ %25** (sanayi zonları hariç); metro genelinde kiremit **%40–55**. Q-013 ek çelişkisi bu tabloyla kapanır: 500 m tavanı (%72) tüm zonlara uygulanır, zon payları yukarıdaki gibidir.

---

## 4. Kütle aileleri (dönem × tür × kat) [ÇM]

Ölçek sabitleri v0 §2.1 (konut katı 3,0 m, dükkân zemin 4,2 m, parapet 0,9 m). Üçgen bütçesi: LOD0 / LOD1 / PROXY. "Yeni" = v1'de üretilecek; "v0" = mevcut, yalnız varyant/çatı eklenir.

| Kimlik | Dönem / tür | Kat | Ayak izi (cephe × derinlik, m) | Görsel tarif (uzakta / yakında) | LOD0 / LOD1 / PROXY | T0'da | Durum |
|---|---|---|---|---|---|---|---|
| `res_old_row` (=v0 `res_old`) | eski sıra ev | 2–3 | 6–9 × 10–13 | uzak: kiremit sırası; yakın: dar dikey cephe, cumba, panjur, saçak | 150–380 / 22–30 / 10–14 | çok | v0 + RK-K/RK-B oranı artar |
| **`res_old_town`** | eski kent yapısı / kagir apartman ("ZOOM3 krem bina") | **3, 4** (ayrı mesh) | 12–18 × 12–16 | uzak: krem kütle + kırma kiremit; yakın: **2,8–3,2 m aks düzenli dikey pencere ızgarası**, taş kat silmesi, saçak 0,6 m, köşe vurgusu, `_gf` dükkân | 320–650 / 26–40 / 10–14 | **D1/D6 çekirdeğin ana dokusu** | **yeni, Tur 1** |
| **`com_han`** | avlulu han/çarşı bloğu | 2 | 24–36 kare, iç avlu 10–16 | kiremit kırma halka + avlu boşluğu (uzaktan "delik" okunur) | 500–900 / 40–60 / 14 | D1 | yeni, Tur 2 |
| `com_bazaar` | çarşı dükkân sırası | 1–2 | birim 4–6, sıra 20–48 × 8–12 | sürekli tente bandı (A1/A3/A5/A7 karışık), tek eğim/düz | 300–700 / 24–40 / 10–14 | D1, D6, D2 | yeni (v0 listede vardı), Tur 1 |
| `res_mid_4` (`res_mid` a/c) | orta dönem apartman | 4 | 12–16 × 10–12 | yatay balkon bantları; **%40 RK-K varyant**, %60 RT+ekipman | 220–480 / 28–40 / 10–14 | çok | v0 + kırma varyant |
| `res_mid_5_6` (`res_mid` b/d) | orta dönem apartman | 5–6 | 14–20 × 11–14 | aynı; köşe parselde iki cepheli | 300–600 / 30–40 / 10–14 | çok | v0 + kırma varyant |
| **`res_mid_slab`** | orta dönem kıyı apartmanı (Kordon/karşı yaka şeridi) | **7–8** | 18–26 × 12–14 | uzun yatay kütle, sürekli balkon, düz teras; kıyıda sıra hâlinde | 420–800 / 36–48 / 10–14 | D1/D6 kıyı şeridi | **yeni, Tur 1** |
| `res_late_5_6` | geç apartman | 5–6 | 16–20 × 12–16 | köşe balkon, üst kat geri çekme, RK-A veya RT | 320–600 / 32–44 / 10–14 | var | v0 (`res_late` a/c) |
| `res_late_8_10` | geç apartman / site bloğu | 8–10 | 18–26 × 14–18 | düşey merdiven kulesi bandı, RT | 450–900 / 36–52 / 10–14 | dış halka, D6 | v0 `res_late_b` (7) + yeni 9–10, Tur 2 |
| `res_new_12_16` | yeni konut kulesi | 12–16 | 20–26 × 18–22 | yalın, açık beyaz/gri, tepede teknik hacim | 450–900 / 36–52 / 10–14 | **yok/çok az (S3 AÇIK)** | Tur 2 (olgun büyüme için) |
| `res_house` | müstakil/ikiz ev | 1–2 | 7–11 × 8–10 | RK-K/RK-B, bahçe payı | 100–260 / 22 / 10–14 | D2–D5 | v0 |
| **`res_hill`** | yamaç evi (basamaklı) | 2–3 (yokuş aşağı +1) | 8–11 × 9–11 | yokuşa bakan cephede açık temel/kat; kiremit; beyaz/krem/pastel | 180–360 / 24–30 / 10–14 | D5, D1 yamaç | yeni, Tur 2 |
| `res_village` | köy evi + avlu duvarı | 1–2 | 8–12 × 7–10 (+avlu 12×12) | kiremit beşik, alçak avlu duvarı (koyu çizgi) | 150–300 / 22–30 / 10–14 | D4 | yeni, Tur 2 |
| `off_mid` | ofis/otel/banka | 6–10 | 20–30 × 16–24 | düzgün kat bantları, yüksek giriş katı, G2 bant | 450–900 / 36–52 / 10–14 | D1 merkez az | Tur 2 |
| `off_tower` | iş kulesi | 15–30 | 24–34 kare | olgun durum; kademe/tepelik | 600–1.200 / 48–64 / 12–14 | **T0 yok** (S3) | sonraki dalga |
| `ind_shed` | sac hangar | 1 (iç 7–10 m) | 30–60 × 20–40 | RS; **açık krem/beyaz sac baskın**, kapı ve şerit pencere bandı zorunlu (boş yüzey yok) | 150–400 / 22–44 / 10–14 | D3, D4 | v0 + cephe bandı |
| **`ind_vault`** | tonozlu depo / antrepo | 1–2 | 24–48 × 15–30 | RN tonoz, beton/sac, uzun ve yatay | 260–520 / 30–40 / 12–14 | D3 liman | **yeni, Tur 1** |
| `ind_sawtooth` | testere dişi fabrika | 1–2 | 30–60 × 24–40 | RD, cam şeritleri | 250–600 / 26–46 / 10–14 | D3, D1 eski sanayi | v0 (`ind_shed_b`, `ind_heritage_b`) |
| `ind_heritage` | tuğla/taş eski fabrika + baca | 2–3 | 25–50 × 15–25 | W10/W11, yüksek beşik veya RD, ayrı baca 25–35 m | 300–900 / 22–50 / 10–14 | D1, D3 | v0 |
| `ind_workshop` | atölye | 1–2 | 12–20 × 10–15 | RM, kepenk A8, avlu | 150–320 / 20–30 / 10 | her bölge az | Tur 2 |
| `ind_port_warehouse` | liman antreposu (çok katlı) | 3–4 | 40–80 × 18–24 | uzun beton blok, düzenli pencere, düz çatı | 350–700 / 30–40 / 10–14 | D3 | Tur 2 |
| `agr_silo` | silo / ambar | — | Ø 6–10, h 18–28 | 6–8 kenar silindir kümeleri (2–4), yanında sac ambar | 120–300 / 24 / 12 | D4 gıda işleme | Tur 2 |
| `agr_greenhouse` | sera | 1 | 30–60 × 8–12 (dizi) | alçak tonoz/beşik, R14 açık mat; sıra hâlinde | 60–160 / 10–20 / 6–10 | D4 | Tur 2 |
| `civ_hall` | kamu | 2–4 | 30–60 × 20–40 | v0 | 500–1.000 / 32–54 / 10–14 | var | v0 |
| `civ_school` | okul/üniversite kanadı | 2–4 | 40–80 × 12–16 | uzun kanat, avlu | 300–700 / 28–40 / 10–14 | var | Tur 2 |
| `civ_pier` | iskele/feribot binası | 1–2 | 20–40 × 10–20 | alçak saçaklı, suya uzanan platform | 250–600 / 24–40 / 10–14 | D1, D6, D2 | Tur 2 |
| `lmk_clocktower` | saat kulesi | — | v0 §4 | **korunur, değiştirilmez** (23 m, oran 1,3–1,8) | ≤ 1.200 / ≤ 120 / kendi proxy | D1 | v0 |
| `prop_container_stack` | konteyner istifi | 1–3 kat | 12,2 × 2,44 × 2,59 birim; 2×4…3×6 istif | kısık renkler (A1/A2/A3/W13/R7) | 60–200 / 12 / 6 | D3 liman (az) | Tur 1 |
| `prop_crane` | liman vinci | — | 30–45 m | olgun; T0'da 0–2 küçük | 120–250 / 24 / — | D3 | Tur 2 |

**Kat sayısı farklı → ayrı mesh** (v0 §3.3; Y ölçeğiyle kat uydurulmaz). "3 dönem × apartman 3 yükseklik" (T-051 ölçüt 2) karşılığı: eski {3, 4, (2 = row)}, orta {4, 5–6, 7–8}, geç {5–6, 7, 8–10}.

### 4.1 Varyasyon (MultiMesh uyumlu; v0 §3.3 kuralları geçerli, ek olarak)
- Aile başına en az: `res_old_town` 3 (+`_gf` 2), `res_mid_*` 4 + 2 kırma varyant (+gf), `res_mid_slab` 2, `ind_vault` 2, `com_bazaar` 2.
- **Alt modüller mesh içinde, seçenek seed ile değil varyantla**: cumba / balkon düzeni / köşe işlemi / teras ekipmanı düzeni varyant farkıdır. Ayrı MultiMesh'e bölünmez (draw call).
- Örnek verisi: duvar, çatı, aksan satırı + parlaklık ±%6 (v0). Ek kural: **aynı blok cephesinde komşu iki yapının çatı satırı farklı** (kiremit tonları arasında da).

---

## 5. Cephe motifleri [ÇM]

| Motif | Kural | Low-poly uygulama | Görünürlük |
|---|---|---|---|
| Pencere ritmi (eski) | dikey 1,0–1,1 × 1,8–2,0 m, aks 2,8–3,2 m, kat başına hizalı | 0,15–0,25 m içe gömülü kutu (G1), 8–10 üçgen/pencere; LOD0'da ön + bir yan cephe | sokak + ilçe yakın |
| Pencere ritmi (orta/geç) | yatay 1,6–2,4 × 1,4 m veya sürekli balkon bandı arkası koyu şerit | balkon oyuğu içinde tek koyu şerit (G1 × 0,9) — pencere tek tek değil | sokak + ilçe |
| Pencere ritmi (yeni/ofis) | düşey şerit bantları | G2/W16 düşey bant yüzleri | ilçe + metro yakın |
| Balkon | orta dönemde sürekli bant 0,9–1,2 m derin; geç dönemde köşe balkonu | v0 `balcony()`; alt yüz duvar × 0,72 | sokak + ilçe (gölge çizgisi) |
| Cumba | eski kentte 1. kat ve üstü, 0,6–0,9 m çıkma, 3–4 m genişlik | tek kutu çıkma | sokak |
| Panjur | eski evde pencere yanlarında A4 levha (2 üçgen/kanat) | yalnız `res_old_*`, `res_house`; LOD0 | sokak |
| Zemin kat dükkân bandı (`_gf`) | 4,2 m; koyu vitrin (G1) + 3–5 birimde bir kepenk (A8/R6) + tente | v0 `shop_front()`; **tente rengi aksan satırından, aynı cephede ≥ 2 renk** | sokak + ilçe yakın (tente rengi şerit olarak okunmalı) |
| Saçak | kiremit çatıda 0,5–0,7 m taşma, alt yüz koyu | çatı yüzü kenarından 2–4 ek üçgen | sokak + ilçe (koyu çizgi kütleyi ayırır) |
| Kat silmesi / parapet kapağı | eski kentte zemin üstünde taş bant (W11), apartmanda parapet kapağı (duvar × 0,85) | v0 PART_TRIM | sokak |
| Sanayi cephe bandı | hangarda en az: 1 büyük kapı (A3/R7) + üst şerit pencere (G1 bant) | boş düz yüzey yasak (bugünkü port görüntüsünün ana kusuru) | sokak + ilçe |

**Gölgelendiricide pencere ritmi (Tur 2 deneyi, hipotez):** LOD1'de pencere geometrisi yok; duvar parçasında model uzayı yüksekliği (3 m kat) ve cephe ekseni (3 m aks) üzerinden koyu ızgara boyamak (UV/doku yok, yalnız `fract()` ile) LOD1 mesafesinde ritmi geri getirebilir. Kesin kenarlı, mat; uzaklıkla sönümlenmeli (moiré yok). Uygulanabilirliği ve maliyeti technical-artist ölçer; başarısızsa geometri pencereleri LOD0'da kalır.

---

## 6. Bölge karakter tablosu (D1–D6) [kanon tanımı F02 tablosu; aile/palet/yoğunluk değerleri ÇM]

Not: D2 kanonda tek fonksiyonlu "marina ilçesi" **değildir**; D6 "kıyı turizm" değil **karşı yaka kent çekirdeğinin ikinci ayağıdır** (konut, çarşı/meydan, feribot, hizmet; turizm ikincil) [K, F02, F04 "karşı yaka yalnızca birkaç turist evi değil"]. Her ilçe karma ekonomi taşır (WLD-06).

| Bölge | Okunması gereken karakter | Baskın aileler (pay) | Palet vurgusu | Kat dağılımı | Yoğunluk / doku | Yeşillik |
|---|---|---|---|---|---|---|
| **D1** merkez / tarihî çekirdek | alçak-sık kiremitli tarihî çekirdek + meydan/saat kulesi + kıyıda apartman şeridi + eski sanayi izi | historic: `res_old_town` .40, `res_old_row` .25, `com_bazaar`/`com_han` .15, `res_mid_4` .12, `ind_heritage`/kamu .08 · center/dense: `res_mid_*` .40, `res_old_town` .20, `res_late_5_6` .20, `res_mid_slab` (kıyı) .10, `civ_hall`/`off_mid` .10 | krem/kireç/okra/şeftali + R3/R4/R5/R9 | historic 2–4; center 4–6; kıyı şeridi 6–8; saat kulesi çerçevesi 4–5 | bitişik nizam, dar sokak, iç avlular; yapı arası zemin döşeme | meydan/kıyı palmiyesi, avlu çınarı; blok alanının %4–8'i |
| **D6** karşı yaka çekirdeği | kıyı boyunca 6–8 katlı beyaz/krem apartman bandı, arkasında 3–5 kat karışık kiremit, kendi çarşı/meydanı, feribot iskelesi | kıyı bandı `res_mid_slab` .40 + `res_late_8_10` .15; iç: `res_mid_*` .30, `res_old_town` .15, `com_bazaar`, `civ_pier` | W1/W2/W5 ağırlıklı, kiremit arkada | kıyı 6–8 (geç 8–10 az); iç 3–5 | kıyıda sürekli cephe, içeride bitişik/ayrık karışık | kıyı palmiye sırası, iç sokak ağaçları |
| **D2** Orven (doğu kıyısı, karma) | yaşayan ilçe merkezi; konut + gündelik ticaret + küçük atölye + marina bakım/balıkçı işleri | town_center: `res_mid_4` .35, `res_old_row` .25, `com_bazaar` .15, `ind_workshop` .10, `res_house` .15; town: `res_house` .45, `res_old_row` .25, `res_mid_4` .20, `ind_workshop` .10 | kireç beyazı + pastel (W6, W4), kiremit | merkez 3–5, çevre 1–3 | merkezde bitişik, çevrede bahçeli | bahçe ağaçları, kıyı palmiyesi az |
| **D3** batı liman / üretim (ana kara) | yatay sanayi: hangar, tonoz antrepo, testere dişi, tuğla fabrika + baca, konteyner istifi; arkada işçi mahalleleri | harbor/yard: `ind_shed` .30, `ind_vault` .20, `ind_sawtooth` .15, `ind_heritage` .10, `ind_port_warehouse` .10, `prop_container_stack` avlu başına 1–3; town (işçi): `res_old_row` .40, `res_mid_4` .35, `res_house` .25 | sanayi: açık krem/beyaz sac + mavi-gri + tuğla; işçi: kiremit | sanayi 1 (7–10 m), antrepo 3–4; işçi 2–4 | **avlu içinde 2–6 hacim + istif** (v0 §3.1 I); yollar geniş | avlu kenarı ağaç sırası seyrek |
| **D4** iç/kuzey ova | tarım + küçük merkezler + gıda işleme + depo | village/farm: `res_village` .40, `res_house` .25, `agr_greenhouse` .15, `ind_shed` .10, `agr_silo` .05, `ind_workshop` .05; town: `res_house` .40, `res_mid_4` .25, `res_old_row` .20, `ind_shed` .15 | kırsal paleti, kiremit + paslı sac | 1–2 (merkez 3–4) | dağınık, tarla parsellerine oturan; köy kümeleri | zeytin/kavak sıraları tarla kenarında |
| **D5** doğu/güneydoğu yamaçları | eğimli mahalleler, küçük merkez, orman/doğal alan; (olgunda üniversite) | hill_center: `res_mid_4` .35, `res_hill` .35, `res_old_row` .15, `com_bazaar` .05, `civ_school` .10; hillside: `res_hill` .55, `res_house` .35, `res_mid_4` .10 | beyaz/krem/pastel + kiremit | 2–3 (merkez 3–5) | yokuşa basamaklı, kot farkı görünür, aralarda yeşil | çam/zeytin lekeleri, yapı arası %15–30 doğal yeşil |

Tablo `settlement.json` `zones.*.family_weights` alanına geçecek biçimdedir; yeni aile kimlikleri manifestte var olana kadar en yakın v0 ailesi kullanılır (`res_old_town`→`res_old`, `res_mid_slab`→`res_late_b`, `ind_vault`→`ind_shed`).

---

## 7. Bitki ve ince ayrıntı (minimal) [ÇM]

| Nesne | Ölçü | Üçgen LOD0 / LOD1 | Nerede | Kural |
|---|---|---|---|---|
| `veg_palm` | boy 8–11 m, taç Ø 5 | 40–70 / 8–12 | D1/D6 meydan + kıyı promenadı, D2 kıyı | **yalnız kıyı/meydan sırası**; 8–12 m aralık; konut sokağında yok (tatil köyü hissi, VIS-05) |
| `veg_plane` (çınar, v0) | 14 boy, taç Ø 10 | 72 / 32 | meydan, avlu, cadde | avlu başına 0–2 |
| `veg_pine` | 10–14 | 40–60 / 10 | D5 yamaç, kent kenarı | kümeler (5–20) |
| `veg_olive` | 5, taç Ø 5 | 30–50 / 8 | D4, D5 | tarla kenarı sıraları |
| `veg_cypress` | 10, taç Ø 2 | 16–24 / 6 | mezarlık/kamu/yamaç | seyrek vurgu |
| `veg_hedge` | 1,2 yük., uzun kutu | 12 / 4 | ev bahçe sınırı | isteğe bağlı |

Uzaklık kuralı: LOD1'den sonra ağaçlar tek tek çizilmez; HLOD'da **ağaç lekesi** (koyu yeşil P3 düşük kutu/disk, hücre başına birleşik) veya arazi tonu ile temsil edilir. Ağaç ölçeği: çınar 14 m ≈ 4–5 kat apartmanın yarısı-üçte ikisi; palmiye saat kulesinin (23 m) yarısını geçmez (VIS-03).

İnce ayrıntı (yalnız LOD0): teras su deposu/güneş kollektörü, tente, panjur, cumba, baca. Sokak mobilyası, araç, insan bu kapsamda değil (T-050).

---

## 8. Ölçek ve LOD kuralları [ÇM; mesafeler mevcut chunk/LOD sistemine göre technical-artist/godot-engineer ölçer]

### 8.1 Seviyeler ve korunacak karakter
| Seviye | Yaklaşık mesafe | Ne kalır | Ne gider | Renk |
|---|---|---|---|---|
| LOD0 | < 250–350 m | tam silüet, saçak, pencere, `_gf` tente, cumba, teras ekipmanı | — | tüm parçalar |
| LOD1 | 350 m – ~1,2 km | ayak izi, kat yüksekliği, **çatı formu (kırma/beşik/tonoz/testere geometri olarak)**, saçak çizgisi (≤ 4 üçgen), balkon bandı yerine koyu bant yüzü | pencereler (Tur 2: gölgelendirici ritmi), ekipman | duvar + çatı + koyu bant |
| PROXY / HLOD1 | > 1,2 km | kutu + **çatı renkli tepe** (kiremitli yapıda tepe kiremit satırı; kırma çatı ≤ 4 üçgenlik alçak piramit olarak kalabilir, PROXY ≤ 14) | tüm cephe detayı | duvar satırı + çatı satırı (mevcut `template_colors` bunu yapıyor; doğru) |
| Metro | tüm Ismeral | yerleşim lekeleri: **sıcak kiremit/krem yama + gri sanayi yaması + koyu yeşil ağaç beneği**; kütle sırası (merkez yüksek) | — | HLOD + arazi kent tonu |

### 8.2 Kurallar
1. **Çatı rengi her seviyede aynı satırdan** (WLD-01). HLOD parlaklık kovası (8) kiremit tonlarını birbirine kaynatmamalı: 3 kiremit tonu HLOD'da da ayırt edilir (ΔE ≥ 6 satırlar arası; v1 tablosu bunu sağlar: R3/R4/R5/R9).
2. **Kat sırası korunur:** LOD geçişinde yükseklik değişimi ≤ %5; v0 K8 (visual-diff ≤ %5) geçerli.
3. **Proxy tepesi çatı rengidir**, duvar rengi değil (metroda görünen yüzey tepedir).
4. **Kent zemini:** yapılı blok içinde yapı arası zemin döşeme tonu (U1 #B9AE9C) — çim değil. Bu arazi/yol katmanının işidir (T-049B arazi görünümü veya parsel/blok zemini); kit yalnız bağımlılığı bildirir. Bu yapılmadan §10 kapısı D1'de geçmez.
5. Saat kulesi kendi proxy'sini HLOD'da korur (v0 §4).

### 8.3 Ölçek sabitleri
v0 §2 aynen. Kontrol nesneleri: insan 1,75 m, otomobil 4,4 m, çınar 14 m, palmiye 9 m, saat kulesi 23 m ve çerçevesi 4–5 kat (oran 1,3–1,8). `res_mid_slab` 7–8 kat (≈ 22–25 m + parapet) **saat kulesinin 150 m çevresine yerleşmez** (oran kuralını bozar; yerleşim kuralı).

### 8.4 Bağımlılıklar (kit dışı)
- Kent zemini tonu (8.2/4): T-049B/arazi veya yol katmanı.
- Yerleşim lekesinin biçimi/büyüklüğü, D1+D6 baskınlığı, kıyıya yaslanma: T-049A (bu belge yerleşim biçimi önermez; Q-015 coğrafyası değişmez).

---

## 9. Bütçe [ÇM; gevşetme yok — T-051 ölçüt 5]

| Kalem | Sınır |
|---|---|
| Yerel evre toplam görünür üçgen | **≤ 900.000** (arazi + yol + yapı + bitki) |
| Kare | ort ≤ 8 ms, P95 ≤ 16,6 ms (`tools/smoke_playable.sh` SMOKE_OK) |
| Modül LOD0 | konut ≤ 900, kamu/ofis ≤ 1.200, landmark ≤ 1.500 (manifest `max_lod0_tris` 1.500 korunur); **kent ortalaması ≤ 450** (ağırlıklı, yerleşim payına göre) |
| Modül LOD1 | ≤ 64 (konut ortalaması ≤ 40) |
| PROXY | ≤ 14 (değişmez) |
| Bitki | LOD0 ≤ 72, LOD1 ≤ 12, HLOD birleşik leke |
| Kit mesh sayısı (LOD0) | v0: ≤ 40 → v1: **≤ 64** (Tur 1 sonunda ≤ 52). Her yeni mesh varyantı chunk başına olası +1 draw call → artış technical-director onayı ve önce/sonra draw call ölçümüyle |
| Malzeme | tek `mat_kit`, mesh başına tek surface (v0 §6) — değişmez |

Kaba hesap (çıkarım, ölçülmedi): sokak preset'inde LOD0 ~400 yapı × 450 ≈ 180k, LOD1 ~4.000 × 40 ≈ 160k, HLOD ~20.000 × 12 ≈ 240k, arazi ≈ 300k → ≈ 880k. **Pay dar**: yeni ayrıntı LOD0 ortalamasını 450'nin üstüne çıkarırsa LOD0 mesafesi kısaltılır, ayrıntı kesilmez değil. Önce/sonra ölçüm zorunlu.

---

## 10. Kabul kapısı (art-director bağımsız görsel kapısı; T-051 ölçüt 6)

### 10.1 Yakalamalar (önce = v0 kit, sonra = v1; aynı seed, aynı preset, 1600×900, `--frames 220`, HUD açık bırakılabilir ama kıyas kırpıntısı HUD dışından)
| # | Preset (playable.tscn) | Kıyas referans kesiti (bu klasörde) | Bakılan |
|---|---|---|---|
| C1 | `--preset=metro` | REF 02 T0 üst yarı (`03_metro_vs_ref.png` sağ) | yerleşim lekelerinin renk karakteri, D1/D6 okunurluğu |
| C2 | `--preset=district:D1` | REF 02 T0 D1+D6 + REF 03 ZOOM 2/3 (`01_district_vs_ref.png`) | çatı alanı, kütle hiyerarşisi, sokak/zemin, yeşil |
| C3 | `--preset=street:D1` (meydan/saat kulesi çevresi) | REF 03 ZOOM 3 (tarihî çarşı/meydan) | çatı formu+saçak, pencere ritmi, dükkân bandı, palmiye, kule oranı |
| C4 | `--preset=street:port` | REF 02 D3 T0 kesiti (`02_street_port_vs_ref.png`) | sanayi kütle çeşitliliği, avlu/istif, işçi konutu |
| C5 | `--preset=district:D6` | REF 02 D6 T0 kesiti | kıyı apartman bandı + arka kiremit dokusu |
| C6 | `--preset=district:D5` veya `d5_slopes` | REF 03 genel (yamaç) | yamaç evi, yeşil ara doku |

Önce yakalamaları C2/C3/C5/C6 için henüz yok (§0.1; T-049B derleme hatası). v1 teslimi önce/sonra çiftini aynı ağaçtan üretmelidir.

### 10.2 PASS ölçütleri (her biri: görüntü yolu + gözlem)
**C2 ilçe D1** — hepsi gerekli:
1. Çatı alanı **sıcak baskın**: kiremit piksel payı (§10.3) yapı kırpıntısında **%18–45** (referans 19–37); gri + mavi-gri **≤ %30** (bugün %57).
2. "Tek kırmızı halı" yok: kiremit alanı içinde en az 3 ton gözle seçilir; düz teraslar ve kamu tepeleri kiremit içinde yamalar hâlinde görünür; kiremit payı **> %55 ise FAIL** (VIS-05).
3. Yapı arası çim yeşili kentsel kırpıntıda **≤ %8** (bugün %21); sokaklar koyu çizgi olarak blokları ayırır.
4. Kütle hiyerarşisi görünür: alçak sık çekirdek, 4–6 katlı halka, kıyıda daha yüksek şerit; tek kot "halı" değil.
5. Yeşil benekler (avlu/meydan ağaçları) görünür ama doku boğulmaz.

**C3 sokak D1** — hepsi gerekli:
1. Görüş alanındaki yapıların çoğunda saçaklı kırma/beşik kiremit **veya** ekipmanlı teras; mavi-gri çatı konut üstünde yok.
2. Her konut cephesinde pencere ritmi okunur (düzenli koyu ızgara veya balkon bandı); boş düz cephe yok (yan sağır duvar hariç).
3. Ana cadde cephesinde zemin kat dükkân bandı + ≥ 2 tente rengi.
4. Saat kulesi : çerçeve oranı 1,3–1,8 (v0 K2); meydanda ≥ 50×50 m açıklık, palmiye/çınar ölçeği makul.
5. Yan yana iki aynı yapı yok (varyant + duvar + çatı üçlüsü).

**C4 sokak port** — hepsi gerekli: hangarlar ev gibi değil (yatay H/W ≤ 0,3, sac/tonoz/testere karışımı, kapı + şerit pencere bandı); ≥ 1 tuğla eski fabrika + baca veya tonoz antrepo görüş alanında; konteyner istifi var ama alanı doldurmuyor; arkada kiremitli işçi konutu okunur.

**C1 metro** — yerleşim lekeleri arazinin olive tonundan **renk karakteriyle** (sıcak kiremit/krem) ayrılır, sanayi lekesi (D3) gri-beyaz olarak ayrı okunur; aynı yerleşimler C2/C4'teki renkle tutarlı (WLD-01). (Leke büyüklüğü/şekli T-049A; burada yalnız renk/doku değerlendirilir.)

**C5/C6** — D6 kıyı bandı D1 çekirdeğinden kütle olarak farklı (daha yüksek, beyaz/krem, düz teras); D5'te yapılar arası doğal yeşil ve yokuşa basamaklanma okunur.

**Genel FAIL koşulları (herhangi biri):** gri/mavi-gri çatı halısı (C2 gri ≥ %45); tek ton kırmızı halı veya kiremit > %55 (C2); oyuncak doygunluk (geniş alanlarda S > 0,70); Adriyatik/Venedik/kampanil silüeti; aynı modülün komşu tekrarı belirgin; çim üstüne serpilmiş kent (C2 yeşil > %15); bütçe aşımı (§9). Siyah/boş/kısmi kare = yakalama başarısız, görsel sonuç değil.

Sonuç biçimi: v0 §9.3 (F04 Q1–Q6) + bu ölçütler; `PASS` / `PASS WITH FIXES` / `FAIL`. **Kullanıcı kabulü ayrıca AÇIK** (art-director PASS'i kullanıcı onayı değildir).

### 10.3 Renk sınıfı ölçümü (QA aracına girdi; kırpıntı = HUD dışı yapı alanı)
Piksel başına HSV (h derece, s, v 0–1), sırayla ilk eşleşen sınıf:
```
v < 0.25                                   -> koyu
(h < 32 or h > 345) and s > 0.30 and v > 0.35 -> kiremit
s < 0.16 and v >= 0.62                     -> açık
185 <= h <= 235 and s > 0.45               -> su
185 <= h <= 250 and s <= 0.45              -> mavi-gri
s < 0.16                                   -> gri
32 <= h < 50 and s < 0.6                   -> sıcak cephe
50 <= h <= 160                             -> yeşil
diğer                                      -> diğer (çoğunlukla kahve/sıcak gölge)
```
Kırpıntı koordinatları önce/sonra aynı olmalı ve görev dosyasına yazılmalı. Ölçüm yardımcıdır; karar görüntüye bakılarak verilir.

---

## 11. Önceliklendirme ve üretim sırası

**Kullanıcının en çok gördüğü:** oyun ilçe/metro kamerasında açılıyor; orada okunan **çatı rengi alanı + yapı arası zemin + kütle sırası**. Sokak ayrıntısı ikinci sırada.

### Tur 1 — "uzaktan referansa benzesin" (en büyük algı farkı, en az risk)
1. **Palet v1 Tur 1 satırları** (`kit_palette.json`, 32 satır, kod değişikliği yok) + dönem ağırlıkları (§2.3) — technical-artist.
2. **Çatı payı verisi** (§3.3) `settlement.json` `tile_cap`/`roof_row_weights`; ev ve işçi konutunda R6 sacı kaldır — world-engineer.
3. **Kırma kiremit varyantları**: `res_mid` 2 varyant (4 ve 5–6 kat) RK-K + saçak; tüm kiremitli modüllere saçak taşması — technical-artist.
4. **`res_old_town` 3/4 kat** (3 varyant + 2 `_gf`): referansın asıl dokusu — technical-artist.
5. **Teras ekipmanı** (su deposu, güneş kollektörü) `res_mid`/`res_late` düz çatılarına mesh içi — technical-artist.
6. **Kent zemini tonu** (yapılı blok altında döşeme) — arazi/yol sahibi (T-049B ile koordineli; kit dışı).
7. **Sanayi okunurluğu**: `ind_shed` cephe bandı (kapı + şerit pencere), `ind_vault`, `prop_container_stack` — technical-artist.
8. **`res_mid_slab` 7–8 kat** (D1/D6 kıyı şeridi) + `com_bazaar` 2 varyant.
9. **Bitki**: `veg_palm`, `veg_pine`, `veg_olive` + mevcut `veg_plane`; meydan/kıyı/avlu yerleşimi.
→ Tur 1 sonunda §10 C1, C2, C4 kapısı.

### Tur 2 — "yakından karakter ve bölge kimliği"
`com_han`, `res_hill` (D5), `res_village` + `agr_greenhouse` + `agr_silo` (D4), `res_late_8_10`, `ind_port_warehouse`, `ind_workshop`, `civ_school`, `civ_pier`, `off_mid`; palet 64 satır (§2.2); LOD1 gölgelendirici pencere ritmi deneyi; tente renk çeşitliliği. → §10 C3, C5, C6.

### Sonraki dalga (olgun büyüme; T0 dışı)
`res_new_12_16`, `off_tower`, `prop_crane`, `lmk_stadium` — S3 ve stadyum konumu AÇIK.

---

## 12. Yapılacak / yapılmayacak

**Yapılacak:** sıcak Ege paleti (veri); karışık kiremit + ekipmanlı teras; dönem başına ayrı kütle aileleri ve kat başına ayrı mesh; saçak, pencere ritmi, dükkân bandı; sanayi kütle çeşitliliği ve avlu; kıyı/meydan palmiyesi, yamaçta çam/zeytin; tek dünya renk sürekliliği (HLOD dahil); önce/sonra aynı preset ölçümü.

**Yapılmayacak:** fotogerçekçilik, doku/normal map, yansıma, altın saat/bloom [VIS-01]; tek ton kırmızı halı veya Adriyatik kartpostalı, kampanil, Venedik köprüsü, parlak tatil köyü, oyuncak doygunluk [VIS-05]; konsept görsellerdeki binaların/konumların kopyası, "Kemeraltı/Bayraklı/Kadifekale" gibi gerçek adların oyuna konması [VIS-07, F05-C]; dini yapı (S1 AÇIK); T0'da kule kümesi (S3 AÇIK); yeni coğrafya/yerleşim biçimi (T-049A, Q-015); kanon veya AÇIK karar üretimi; bütçe gevşetme.

### 12.1 Low-poly ile dürüstçe YAPILAMAYACAKLAR
- Referansın **sinematik derinliği** (atmosferik pus, sıcak gün batımı, yoğun gölge kontrastı) — oyun düz gündüz ışığında daha açık ve daha düz görünecek; birebir "aynı his" beklenmemeli.
- Referanstaki **ölçülemez yoğunluk** (her yapının ayrı pencere/balkon/kiremit dokusu, binlerce ayrıntılı bina): metroda ve ilçe uzağında yapılar renk yaması olarak okunur; tekil kiremit dokusu, pencere sayısı, korkuluk yoktur.
- **Tek tek kiremit, sıva lekesi, yıpranma**: doku yok; karakter yalnız renk satırı + form + ritimle.
- **Organik tarihî sokak dokusu** (çarşı içi labirent): yol ağı ve parsel üretimi işidir (T-048/T-049A); kit yalnız uygun kütleleri verir.
- **Kalabalık ve araç yoğunluğu** referanstaki gibi değil (T-050, bütçe).
- Olgun görseldeki **kule kümesi ve büyük liman** T0'da yoktur; bu bir eksik değil, kanonun T0 tanımıdır (F02).

---

## 13. Doğrulanmamış / açık
- D1 sokak ve ilçe "önce" yakalamaları alınamadı (T-049B commit'lenmemiş `TerrainLook` derleme hatası); `roads-district` görüntüsünün hangi bölge olduğu kayıtlı değil.
- Bütçe kaba hesabı (§9) ölçülmedi; LOD mesafeleri mevcut sistemden okunmadı (yaklaşık).
- Palet v1 hex'leri Godot ışığında render edilmedi; oyun içi görünür doygunluk kit_lab/playable yakalamasında doğrulanmalı.
- Gölgelendirici pencere ritmi yalnız hipotez.
- Kiremit payı (S2) ve T0 yüksek bina (S3), dini yapı (S1) kullanıcıda AÇIK; v1 değerleri veri, kullanıcı değiştirebilir.
