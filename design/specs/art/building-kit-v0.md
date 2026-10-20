# Low-poly yapı kiti v0 — sanat spesifikasyonu

- Statü: **ÇALIŞMA MODELİ** (art-director, T-025). Kanon değildir; kanonla çelişirse kanon kazanır (`design/CANON.md`).
- REQ: VIS-01, VIS-02, VIS-03, VIS-04, VIS-05, VIS-06, VIS-07; ilgili WLD-07 (saat kulesi ölçeği), CAN-03 (oyuncu özel bina koymaz → kit yalnız dünya/sim'in seçtiği yapıları çizer).
- Açar: **T-004** (technical-artist, low-poly yapı kiti v0 + HLOD proxy'leri). Tüketen: T-005 (yerleşim, world), T-012 (MultiMesh + HLOD render).
- Kaynaklar: `design/foundation/docs/04_*` ve `02_*` (§ D1, "kentte görünmesi gereken karakterler"), `05_*` §C/§D/§E; referans görseller `02_ismeral_t0_vs_mature_SELECTED.jpg` (T0 dokusu) ve `03_ismeral_mature_architecture_DIRECTION.png` (olgun mimari) — **yön, piksel hedefi değil**; ADR-0001 (bütçe), ADR-0002 (chunk/HLOD), ADR-0004 (profiller); `experiments/scale-bench/RESULTS.md`; T-001 kanıtı (terrain metro 152 draw call, 326.585 üçgen).
- İşaretler: **[K]** kanondan aynen türetilen kural · **[ÇM]** art-director çalışma değeri (sayı/oran; ölçümle veya kullanıcı kararıyla değişebilir) · **[AÇIK]** kullanıcı kararı gerekir (§11).

> Bu belge **kural** verir; tekil bina tasarımı, landmark'ların konumu veya mimari kopya vermez (F05-C: "tek tek yapıların tasarımı ve kesin konumları onaylanmadı"). Konsept görsellerdeki UI kartları, sayılar, ölçek okları kanon değildir ve kopyalanmaz [K, VIS-07].

## 0. Gramer özeti (her modül için geçerli)
1. **Silüet > detay.** Bir yapı türü 3 şeyle tanınır: kütle oranı, çatı formu, zemin kat bandı. Cephe detayı yalnız *oyuk* (balkon/şerit girintisi) ve *renk bandı* ile verilir; pencere tek tek modellenmez, doku yok.
2. **Mat, düz gölgeli, low-key.** Roughness 1, metalik 0, speküler kapalı; yüz başına tek renk (üçgen içi gradyan yok). Parlak/doygun "oyuncak" renk yok [K, VIS-05].
3. **Gerçek ölçek.** 1 birim = 1 m; kat yükseklikleri sabit (§2). Ölçek, örnek dönüşümüyle "uydurulmaz" (Y ölçeği yalnız ±%5).
4. **Çeşitlilik veriden.** Varyasyon önce örnek verisiyle (renk/çatı rengi/ölçek/yön), sonra az sayıda mesh varyantıyla gelir; benzersiz bina mesh'i yok (landmark hariç).
5. **Tek dünya grameri.** Sokakta görülen yapı, ilçe ve metro uzaklığında aynı ayak izi, yükseklik sırası, çatı rengi ve duvar rengini korur (LOD/HLOD yalnız sadeleştirir, değiştirmez) [K, WLD-01, VIS-01].

## 1. Modül listesi (aileler)
Kimlik biçimi: `bld_<aile>_<tip>_<varyant>` (ör. `bld_res_mid_a`). Zemin kat dükkân bandı ayrı bina değil, mesh varyant son ekidir: `_gf` (ör. `bld_res_mid_a_gf`).

| # | Kimlik (aile_tip) | Ne | Dönem/rol (VIS-02) | T0'da | Varyant (mesh) en az |
|---|---|---|---|---|---|
| A | `res_old` | Tarihî çekirdek az katlı kagir sıra ev / küçük apartman, ön cephede cumba (çıkma) seçenekli | eski/tarihî katman (çarşı çevresi, yamaç mahalleleri) | var | 4 (+`_gf` 2) |
| B | `res_mid` | Orta dönem apartman (1950–80 hissi): düz teras çatı + parapet, sürekli balkon bantları | kentin baskın dokusu | çok | 4 (+`_gf` 3) |
| C | `res_late` | Geç dönem apartman (1980–2000): daha geniş ayak izi, köşe balkonları, alçak eğimli kırma veya düz çatı | genişleme halkası | var | 3 (+`_gf` 2) |
| D | `res_new` | Yeni konut bloğu / site (2000+): yüksek, yalın kütle, çatı üstü teknik hacim | yeni stok | az [ÇM] | 2 |
| E | `res_house` | Müstakil/ikiz ev, köy-kasaba evi | D2–D5 küçük merkezleri, D4 köyleri | var | 3 |
| F | `com_bazaar` | Çarşı/han sırası: dar dükkân birimleri, 1–2 kat, sıra halinde | tarihî ticaret | var | 2 |
| G | `off_mid` | Ofis / orta yükseklik (iş merkezi, otel, banka) | hizmet merkezi | az | 2 |
| H | `off_tower` | Yüksek ofis kulesi | olgun durum; T0'da yok/çok az [AÇIK S3] | yok/az | 2 |
| I | `ind_shed` | Depo/sanayi hangarı: tek hacim, alçak beşik veya testere dişi çatı | küçük sanayi, lojistik | var | 3 |
| J | `ind_workshop` | Atölye/küçük üretim, tek eğimli veya düz çatı | küçük sanayi | var | 2 |
| K | `ind_heritage` | Tuğla/taş eski sanayi yapısı + ayrı baca parçası | eski sanayi izi (D1/D3) | var | 2 + `prop_chimney` |
| L | `civ_hall` | Sivil kamu yapısı (belediye, adliye, hastane, kütüphane): simetrik, avlulu/kademeli | kamusal altyapı | var | 3 |
| M | `civ_school` | Okul/üniversite bloğu: uzun alçak kanat(lar) | eğitim | var | 2 |
| N | `civ_pier` | İskele/feribot binası (kıyı) | yürünebilir kıyı, feribot | var | 1 |
| O | `lmk_clocktower` | **İnsan ölçeğinde saat kulesi** (tek landmark mesh, §4) | meydan simgesi | 1 adet | 1 |
| P | `lmk_stadium` | Stadyum kasesi (sonraki dalga) | spor | konumu AÇIK | 1 |
| — | `prop_*`, `veh_*`, `veg_*` | Ölçek referansları: insan, otomobil, otobüs/tramvay, ağaç türleri, konteyner | VIS-03 ölçek testi | — | §2.3 |

Kit v0'da **bulunmayacaklar:** kilise çan kulesi/kampanil, Venedik taş köprüsü, kanal kenarı sıra evleri, tatil köyü bungalovları, cam giydirme parlak kuleler [K, VIS-05]. Dini yapılar (cami vb.) v0 kapsamı dışı → [AÇIK S1].

## 2. Ölçek tablosu (metre) [ÇM — İzmir ölçeğinden türetilmiş çalışma değerleri]

### 2.1 Kat ve ölçü sabitleri
| Sabit | Değer |
|---|---|
| Konut katı | 3,0 m |
| Zemin kat dükkân (`_gf`) | 4,2 m (cam bandı 0,3 m içeride; tente plakası 3,0 m'de, 1,2 m dışarı, 0,15 m kalın) |
| Ofis katı | 3,6 m (zemin 4,5 m) |
| Sivil yapı katı | 4,0 m |
| Parapet | 0,9 m (kalınlık 0,3 m) |
| Balkon/şerit oyuğu | derinlik 0,6–1,2 m, yükseklik 1,6 m, korkuluk payı 0,9 m |
| Temel eteği (eğimli arazi) | taban 0 m'nin altına 2,5 m uzanan dikey etek (yamaçta havada kalma yok) |
| Ayak izi ızgarası | 0,5 m'ye yuvarlanır |

### 2.2 Modül ölçüleri (taban ölçüsü genişlik × derinlik; yükseklik = saçak, çatı hariç)
| Modül | Kat | Genişlik (cephe) | Derinlik | Saçak yüksekliği | Çatı payı | Oran kuralı (H/W cephe) |
|---|---|---|---|---|---|---|
| A `res_old` | 2–3 | 6–10 | 10–14 | 6,5–10,5 | kırma +1,5–2,5 / teras +0,9 | 0,8–1,4 (dar ve dikey) |
| B `res_mid` | 4–6 | 12–20 | 10–16 | 12–18 (`_gf` +1,2) | düz +0,9 (+çatı kutusu 2,6) | 0,8–1,5 |
| C `res_late` | 5–8 | 16–24 | 12–18 | 15–24 | düz +0,9 / alçak kırma +2 | 0,8–1,4 |
| D `res_new` | 9–16 | 18–26 | 16–22 | 27–48 | düz + teknik hacim 3,5 | 1,4–2,6 |
| E `res_house` | 1–2 | 7–10 | 8–10 | 3–6 | kırma +2–2,5 (eğim 22–28°) | 0,4–0,8 |
| F `com_bazaar` | 1–2 | birim 4–6, sıra 20–60 | 8–12 | 4,2–7,2 | düz/alçak tek eğim +0,6–1,2 | sıra uzun ve alçak |
| G `off_mid` | 6–12 | 20–30 | 16–24 | 22–44 | düz + teknik hacim 3,5 | 1,0–2,0 |
| H `off_tower` | 15–30 | 24–34 | 24–34 | 55–110 | düz/kademeli | 2,5–4,0 |
| I `ind_shed` | 1 (iç 7–10 m) | 30–60 | 20–40 | 7–10 | beşik 8–12° / testere dişi diş 4–5 m | yatay; H/W 0,15–0,3 |
| J `ind_workshop` | 1–2 | 12–20 | 10–15 | 5–8 | tek eğim 6–10° / düz | 0,3–0,6 |
| K `ind_heritage` | 2–3 (yüksek kat 5 m) | 25–50 | 15–25 | 10–15 | testere dişi / beşik 20–25° | 0,3–0,6; baca 25–35 m, çap 1,8–2,5 m |
| L `civ_hall` | 2–4 | 30–60 | 20–40 | 8–16 | düz + kademeli giriş / alçak kırma | simetrik; 0,25–0,5 |
| M `civ_school` | 2–4 | 40–80 (kanat) | 12–16 | 8–16 | düz / alçak kırma | uzun kanat |
| N `civ_pier` | 1–2 | 20–40 | 10–20 | 5–9 | alçak kırma/düz saçaklı | yatay |
| O `lmk_clocktower` | — | 4,5 × 4,5 gövde | — | toplam 23 (§4) | — | ince; H/W ≈ 5 |
| P `lmk_stadium` | — | dış 190–230 | 140–180 | tribün 18–28 | — | sonraki dalga |

### 2.3 Ölçek referans nesneleri (kitle birlikte teslim; VIS-03 ölçek testi için zorunlu)
| Nesne | Ölçü (m) | Not |
|---|---|---|
| `prop_human` | 1,75 boy, 0,5 omuz | ≤ 40 üçgen, tek renk |
| `veh_car` | 4,4 × 1,8 × 1,5 | ≤ 60 üçgen |
| `veh_bus` / `veh_tram` | 12 × 2,55 × 3,2 / 32 × 2,65 × 3,4 | sonraki dalga |
| `prop_container` | 12,2 × 2,44 × 2,59 | sanayi/liman ölçeği |
| `veg_plane` (çınar) | 14 boy, taç çapı 10 | |
| `veg_palm` | 9 boy, taç 5 | kıyı/meydan; her yere değil |
| `veg_olive` | 5 boy, taç 5 | ova/yamaç |
| `veg_pine` / `veg_cypress` | 12 / 10 boy (servi taç 2) | yamaç |
| Sokak kesiti (yön, T-011'e bilgi) | yerel sokak 10–14, cadde 20–30, bulvar 30–45; şerit 3,25; kaldırım 2–4 | ölçek kontrolü için |

## 3. Silüet, oran ve çatı kuralları

### 3.1 Aile başına silüet kuralı
| Modül | Tanınma işareti (zorunlu) | Yasak |
|---|---|---|
| A | dar dikey cephe, cumba çıkması (0,6–0,9 m dışarı, 1. kat ve üstü) veya kırma çatı saçağı; yan yana sıra halinde dizilmeye uygun (yan cepheler sağır) | turistik "kartpostal" renk dizisi (her ev farklı canlı renk) |
| B | yatay balkon bantları (en az ön cephede, kat başına 1 oyuk bandı), parapetli düz teras, çatıda 0–2 kutu (merdiven/su deposu 2,5×3×2,6) | sivri/dik çatı; simetrik "kutu + piramit" |
| C | köşe balkonu veya kademeli üst kat (en üst kat 1,5–2,5 m geri çekilmiş) | B ile aynı silüet (C, B'den en az ayak izi ve köşe işlemiyle ayrılmalı) |
| D | yalın, yüksek; tepe teknik hacmi; cephede düşey bant | cam giydirme, parlak/yansımalı malzeme |
| E | kırma çatı + bahçe payı; tek/iki kat | dağ evi/alp çatısı (eğim > 35°) |
| F | tekrar eden dar birimler + sürekli tente/saçak bandı | AVM kutusu |
| G | düzgün kat bantları, zemin katta yüksek giriş | gökdelen silüeti (G ≤ 12 kat) |
| I | büyük yatay hacim, alçak çatı; testere dişi varyantı en az 1 | "3 konteyner" etkisi: hangar tekil değil, avlu içinde 2–6 hacim + konteyner/istif (yerleşimci T-005 ile) [K, VIS-04] |
| K | tuğla (W10) veya taş (W11) duvar, testere dişi ya da yüksek beşik, ayrı baca | parlak kırmızı; tüm sanayiyi K yapmak (K yalnız eski sanayi izi) |
| L | simetri + vurgulu giriş (kademe/sütun bloğu/üçgen alınlık YOK — kilise/antik tapınak çağrışımı), avlu veya U plan seçeneği | kubbe/kule (landmark'a ayrılır) |
| O | §4 | §4 |

### 3.2 Çatı çeşitliliği (VIS-05: "tüm çatılar kırmızı kiremit" REDDEDİLDİ [K])
Çatı tipi mesh varyantından, çatı **rengi** örnek verisinden gelir (§5). Bölge karakterine göre çatı alanı payı [ÇM, AÇIK S2 onayı istenir]:

| Doku karakteri | Düz teras (R1/R2) | Kiremit (R3/R4/R5 karışık) | Metal sac (R6/R7) | Diğer (testere dişi, kurşun R8) |
|---|---|---|---|---|
| Yoğun merkez (B/C/G ağırlıklı) | %55–70 | %20–35 | ≤ %5 | ≤ %10 |
| Tarihî çekirdek (A/F ağırlıklı) | %30–45 | %40–55 | ≤ %5 | ≤ %10 |
| Küçük merkez / köy (E ağırlıklı) | %15–30 | %55–70 | %5–15 | — |
| Sanayi/lojistik (I/J/K) | %10–20 | ≤ %10 (yalnız K) | %55–75 | testere dişi %10–20 |

- Kiremit kullanılan her yerde **en az 2 kiremit tonu** (R3/R4/R5) karışır; tek ton kırmızı halı yok. R3 (en doygun) toplam kiremit alanının ≤ %40'ı.
- Ölçülebilir kural (T-005/T-012 örnek verisinden sayılır): **herhangi bir 500 × 500 m kentsel pencerede kiremit çatı alanı ≤ %55; metro genelinde ≤ %35.**
- Referans görseller (02/03) çatıları büyük ölçüde kiremit gösterir; yazılı kural görselin pikselinden üstündür [K, CANON çelişki kuralı 2].

### 3.3 "Tekrar eden 4 bloklu maket" önleme (VIS-05 [K])
Üç katmanlı varyasyon; hepsi MultiMesh ile uyumlu (mesh başına tek surface, §6):
1. **Mesh varyantı (geometri):** aile başına §1 tablosundaki en az varyant; varyantlar şunlarda ayrışmalı: ayak izi oranı (≥ %20 fark), çatı tipi, balkon düzeni, köşe işlemi, üst kat geri çekilmesi. Kat sayısı farklı → ayrı mesh (Y ölçeğiyle kat uydurulmaz).
2. **Örnek verisi (MultiMesh custom data):** duvar paleti satırı, çatı paleti satırı, aksan (dükkân bandı/kepenk) satırı, parlaklık sapması ±%6; dönüşüm: yön = parsel cephesine hizalı (+0°/180°; rastgele açı YOK), XZ ölçeği 0,90–1,15 (eksen başına bağımsız), Y ölçeği 0,95–1,05. Negatif ölçek (ayna) YOK (Compatibility'de yüz yönü/gölge sorunu).
3. **Kompozisyon kuralı (T-005 yerleşimci için, ölçülebilir):**
   - Komşu iki yapı aynı (mesh varyantı + duvar rengi) olamaz.
   - Bir sokak cephesinde aynı (varyant + kat + duvar rengi) üçlüsü art arda en çok 2 kez.
   - Herhangi 9 komşu yapıda ≥ 3 mesh varyantı ve ≥ 3 duvar rengi.
   - Orta yoğun blokta kat sayısı standart sapması ≥ 1 kat (düz "tek kot" blok yok).
   - 200 × 200 m pencerede benzersiz (varyant, kat, duvar rengi) kombinasyonu ≥ yapı sayısının %60'ı.
   - Bloklar arası boşluk: tüm yapılar arasında eşit boşluk ızgarası yok — A/B/F bitişik nizam (yan cephe paylaşımı) olabilir; E ayrık nizam (bahçe payı 3–5 m).

## 4. Saat kulesi — insan ölçeği kuralı [K: WLD-07, F02 "4–5 katlı yapılardan fantastik yüksek değil", F05-E ret]
- **Toplam yükseklik 23 m [ÇM]** (kabul aralığı 21–25 m; mutlak üst sınır 26 m). Örnek dönüşümünde Y ölçeği **1,0 sabit**.
- Kademeler [ÇM]: kaide/çeşme platformu 1,2 m (taban 8–10 m kare/sekizgen) → gövde alt 6 m (4,5 × 4,5) → gövde üst 9 m (4,0 × 4,0) → saat katı 3,5 m (4 yüzde saat diski çapı 1,6–1,8 m) → tepelik 3,3 m. Gövde H/W ≈ 5.
- **Oran kuralı (yerleşim için ölçülebilir):** H_s = kulenin 150 m çevresindeki en yüksek çerçeve yapının parapet üstü yüksekliği; **1,3 ≤ 23 / H_s ≤ 1,8** → çerçeve 4–5 katlı B (parapetle 12,9–15,9 m; `_gf` ile 14,1–17,1 m): oran 1,35–1,78. Çevresi 8+ katlı olursa kule ezilir; 1–2 katlı olursa dev görünür → yerleşimci (T-005) çerçeveyi bu aralıkta tutar.
- Okunurluk yükseklikle değil **meydan boşluğu ve silüetle** sağlanır: çevresinde ≥ 50 × 50 m açık meydan; tepelik kademeli/kemerli taş karakter (renk W11/W2, çatı R8).
- Yasak silüet: kilise kampanili (tuğla şaft + sivri piramit külah), Venedik kulesi, gökdelen/anten oranı. İzmir saat kulesinin birebir kopyası da değil (yön, kopya değil).
- Üçgen: LOD0 ≤ 1.200, LOD1 ≤ 120; HLOD'da kendi proxy'si korunur (silüet kaybolmaz).
- Konumu, tekil tasarımı ve sayısı onaylı değil (F05-C) → kit yalnız bir parametrik mesh verir; nereye konacağı veri (T-005) ve kullanıcı kararıdır.

## 5. Palet ve ışık (bina) [ÇM]
Değerler sRGB (Godot `Color(r, g, b)` ve `source_color` uniform). Hedefler: duvar HSV S ≤ 0,40 (tuğla W10 istisna ≤ 0,56), V 0,55–0,86; çatı S ≤ 0,55. Binalar araziden (V 0,32–0,64, `terrain-palette-v0.md`) **daha açık** → kent kütlesi metroda olive araziden ayrışır.

| Satır | Ad | Hex | Color(r,g,b) | Kullanım |
|---|---|---|---|---|
| W1 | kireç beyazı | #D9D2C3 | 0.85, 0.82, 0.76 | B/C/E yaygın |
| W2 | krem | #D6C6A3 | 0.84, 0.78, 0.64 | A/B/L |
| W3 | açık okra | #C9A978 | 0.79, 0.66, 0.47 | A/B (≤ %15) |
| W4 | soluk somon sıva | #C79A80 | 0.78, 0.60, 0.50 | A/B (≤ %10) |
| W5 | açık beton gri | #B5B1A8 | 0.71, 0.69, 0.66 | C/D/G |
| W6 | soluk adaçayı | #A9B09A | 0.66, 0.69, 0.60 | B/C (≤ %10) |
| W7 | soluk mavi-gri | #A3AEB3 | 0.64, 0.68, 0.70 | B/C/G (≤ %10) |
| W8 | kum taşı | #BFA88A | 0.75, 0.66, 0.54 | A/F/L |
| W9 | eski beton | #8F8B83 | 0.56, 0.55, 0.51 | C/I/J |
| W10 | tuğla | #9A5C44 | 0.60, 0.36, 0.27 | yalnız K |
| W11 | kesme taş | #A89C86 | 0.66, 0.61, 0.53 | K/L/O |
| W12 | sanayi krem metal | #C2BBA6 | 0.76, 0.73, 0.65 | I/J |
| W13 | sanayi mavi-gri metal | #7E8C96 | 0.49, 0.55, 0.59 | I/J |
| R1 | teras açık | #A8A49C | 0.66, 0.64, 0.61 | düz çatı |
| R2 | teras koyu/bitüm | #6E6B66 | 0.43, 0.42, 0.40 | düz çatı (≤ %35'i) |
| R3 | kiremit | #A8644C | 0.66, 0.39, 0.30 | kiremit (≤ %40'ı) |
| R4 | soluk kiremit | #B07A5E | 0.69, 0.48, 0.37 | kiremit |
| R5 | kahve-gri kiremit | #7E5E4E | 0.49, 0.37, 0.31 | kiremit |
| R6 | açık sac | #9EA3A6 | 0.62, 0.64, 0.65 | sanayi |
| R7 | koyu mavi-gri sac | #5F6B73 | 0.37, 0.42, 0.45 | sanayi |
| R8 | kurşun gri | #7D8288 | 0.49, 0.51, 0.53 | kule/sivil tepe |
| G1 | cam/oyuk koyusu | #3A4148 | 0.23, 0.25, 0.28 | dükkân camı, derin oyuk |
| A1–A3 | tente/kepenk (soluk) | #7A4E3A, #3F5E6A, #8A7A4A | 0.48,0.31,0.23 · 0.25,0.37,0.42 · 0.54,0.48,0.29 | `_gf` bandı |

- Balkon oyuğu ve gölgeli şerit rengi = duvar rengi × 0,72 (gölge "siyah" değil).
- **Işık (T-001 ile aynı tek gramer):** gündüz varsayılan — güneş yükseklik 35–50° (T-001: 38°), renk (1.0, 0.97, 0.90), enerji ≈ 0,7; ortam ışığı soğuk gri-mavi (0.60, 0.65, 0.74) ≈ 0,85; yumuşak gölge. Gölgedeki cephenin parlaklığı güneşli cephenin **≥ %40'ı** (siyah cephe yok). Altın saat/sinematik bloom/renk derecelendirme YOK [K, VIS-01]. Kapalı hava alternatifi [ÇM]: güneş 0,25, ortam 1,1 nötr gri, gölge kapalı/çok yumuşak.

## 6. Malzeme ve renk mimarisi (Compatibility + MultiMesh) [ÇM; Compatibility'de T-004 kit_lab'ında doğrulanacak]
- **Mesh başına tek surface, tek ortak malzeme** (`mat_kit`). Birden fazla malzeme = MultiMesh başına birden fazla draw call → yasak. (Mevcut `lowpoly_block.py` 2 malzeme kullanıyor; T-004 tek malzemeye çevirir.)
- Parça kimliği mesh'te: **UV0.x = parça kimliği** (`(id + 0.5) / 16`), **UV0.y = sabit gölge çarpanı** (oyuk 0,72, düz 1,0). Parçalar: 0 duvar (örnek rengi), 1 çatı (örnek rengi), 2 aksan/dükkân bandı (örnek rengi), 3 cam/derin oyuk (G1 sabit), 4 sabit taş/tuğla (W10/W11), 5 trim/parapet kapağı (duvar × 0,85), 6–15 rezerv. Doku/atlas yok; vertex color isteğe bağlı (yalnız HLOD proxy'lerinde zorunlu, aşağıda).
- **Örnek verisi:** `MultiMesh.use_custom_data = true`, `INSTANCE_CUSTOM` = (duvar satırı, çatı satırı, aksan satırı, parlaklık) / 32. `use_colors` kullanılmaz (çarpımsal renk çatıyı da boyar).
- **Palet = küçük doku** `kit_palette.png` 32 × 1 (sRGB, filtre `nearest`, mipmap yok) veya `uniform vec3 palette[32]`; satır sırası §5 tablosu. Tek kaynak: palet T-004'te bir veri dosyasından (`assets/materials/kit/kit_palette.json`) üretilir; elle iki yerde tutulmaz.
- Shader (`shader_type spatial; render_mode diffuse_lambert, specular_disabled;`): albedo = palet[parça→satır] × UV0.y × parlaklık; ROUGHNESS 1; normal map/şeffaflık/emisyon yok. Düz gölgeleme: glTF'te bölünmüş normaller (yüz başına) **veya** fragment'te `normalize(cross(dFdx(VERTEX), dFdy(VERTEX)))` — hangisi daha az köşe/daha net faset veriyorsa T-004 ölçer.
- HLOD1/HLOD2 birleştirilmiş proxy'ler ayrı ikinci malzeme kullanır: `mat_kit_proxy` (vertex color = albedo, aynı lambert/speküler kapalı/roughness 1); renkler aynı paletten pişirilir → LOD1↔HLOD geçişinde ton kayması olmaz.
- Yasak (Compatibility/perf): şeffaf cam, `visibility_range_fade_mode = self` ile alfa geçişi (önce ölçüm), örnek başına `instance uniform` (MultiMesh'te yok), çok surface'li mesh, gerçek zamanlı yansıma.

## 7. Geometri / draw call / LOD / HLOD bütçesi (ADR-0001'den türetilmiş) [ÇM]
### 7.1 Draw call (masaüstü referans profili, Compatibility)
ADR-0001: metro ≤ 600 (hedef ≤ 400). T-001 ölçümü: arazi+su metro **152**. Kalan ≈ **448** tüm diğer katmanlar içindir; binaya hepsi verilmez:

| Katman (metro preset) | Pay |
|---|---|
| Arazi + su (ölçülen) | ≤ 160 |
| **Yapılar (HLOD2 + seçili HLOD1 + landmark proxy)** | **≤ 150 (tavan 220)** |
| Yol/ağ, kıyı, köprü | ≤ 80 |
| Bitki örtüsü (ağaç HLOD) | ≤ 60 |
| Seçim/overlay/UI | ≤ 60 |
| Rezerv | ≥ 70 |

| Yapı draw call (preset) | Bütçe |
|---|---|
| street (~200 m) | ≤ 260 |
| district (~2 km) | ≤ 300 |
| metro (tüm Ismeral) | ≤ 150 |

Sonuç kuralı: MultiMesh = (1 km chunk × mesh varyantı). Bir chunk'ta kullanılan farklı mesh varyantı **≤ 12** (yerleşimci sınırı); kitin toplam LOD0 mesh sayısı v0'da **≤ 40**. Çeşitlilik mesh sayısından değil §3.3 örnek verisinden gelir.

### 7.2 Üçgen ve LOD seviyeleri
| Seviye | Ne | Görünürlük (masaüstü) | Üçgen | Draw call |
|---|---|---|---|---|
| LOD0 | tam modül (oyuk, dükkân bandı, çatı formu) | 0–700 m | konut A/B/E 150–450; C/D/F/G 250–700; I/J 60–250; K 300–800 (+baca ≤ 60); L/M/N 300–900; O ≤ 1.200; hiçbir modül > 1.500 (landmark dahil, stadyum hariç ≤ 3.000) | chunk × varyant |
| LOD1 | aynı ayak izi + saçak + çatı formu (≤ 2 düzlem/eğim yüzü), oyuk yok, `_gf` bandı renk olarak | 600–3.000 m | 16–60 (O ≤ 120) | chunk × varyant |
| HLOD1 | 1 km chunk başına **birleştirilmiş tek mesh**; her yapı = tabanı açık kutu (10) veya çatı prizması (≤ 14); renk **vertex color**'a pişirilir (yan = duvar satırı, üst = çatı satırı) | 2.700–15.000 m | chunk ≤ 30.000 | 1 / chunk |
| HLOD2 | 4 × 4 km süper-chunk; **kent bloğu kütleleri** (T-011 blokları) 2–3 yükseklik kademesiyle; landmark ve en yüksek %10 yapı ayrı kutu olarak korunur | > 12.000 m | süper-chunk ≤ 8.000 | 1 / süper-chunk |

- Görünürlük aralığı sınırlarında **histerezis zorunlu** (`visibility_range_*_margin` ≈ aralığın %10'u; sert "pop" scale-bench'te görüldü). Değerler ADR-0004 profil ayarıdır; iPad profili T-008/T-010 ölçümüyle yazılır.
- Preset başına yapı üçgeni (gölge hariç) [ÇM]: street ≤ 900 k, district ≤ 900 k, metro ≤ 500 k. Gölge: LOD0/LOD1 gölge düşürür; HLOD1/HLOD2 `cast_shadow = off`.
- **HLOD kuralları (ret ölçütleri):** (1) düz "slab" proxy yok — her yapı ya da blok kendi yükseklik kademesini taşır (scale-bench'te slab proxy ilçede kötü okundu); (2) renk ortalaması tek gri/kahveye inmez: blok rengi = alan ağırlıklı **baskın** duvar/çatı rengi (ortalama değil); (3) yükseklik sıralaması ve landmark silüeti (kule, baca, stadyum) korunur; (4) geçiş anında aynı kamera ile ±%5 mesafede alınan iki kare arasında `tools/visual-diff.sh` değişen piksel ≤ %5 [ÇM, T-012 ölçer].
- Godot import'ta otomatik mesh LOD (`meshes/generate_lods`) **kapalı**; LOD'lar elle/üreteçle yazılır (otomatik sadeleştirme düz yüzlü silüeti bozar).

## 8. Import / isimlendirme / pivot / ölçek konvansiyonu (`blender-asset` skill + `art/blender/README.md` ile uyumlu)
- Üreteç: `art/blender/generators/<aile>.py` (bpy, deterministik; aynı argüman → aynı sha256, 2 koşu ile doğrulanır). MCP'den çıkan sahne gönderilmez.
- Çıktı: `assets/models/buildings/<aile>/bld_<aile>_<tip>_<varyant>[_gf].glb`. Bir `.glb` içinde nesneler: `<kimlik>_LOD0`, `<kimlik>_LOD1` (HLOD1/HLOD2 runtime'da veriden birleştirilir; kit yalnız yapı başına HLOD kutu/prizma şablonunu `<kimlik>_PROXY` olarak verir, ≤ 14 üçgen).
- Malzeme adı tek: `mat_kit`. Nesne/mesh adları `bld_*`, `prop_*`, `veh_*`, `veg_*` (küçük harf, `_` ayraç, ASCII).
- Birim: metre, `scale_length = 1.0`; dönüşümler uygulanmış (konum 0, dönüş 0, ölçek 1); glTF `export_yup=True`, `export_apply=True`, normaller açık, doku yok, UV0 = parça kimliği (§6), tanjant yok.
- **Pivot:** ayak izi merkezi, y = 0 zemin (saçak değil). Ön cephe (sokak) glTF **+Z** yönüne bakar (Blender −Y), cephe düzlemi z = +derinlik/2. Temel eteği y < 0'a 2,5 m iner. Alt yüz yok.
- Ayak izi 0,5 m ızgarasında; yükseklikler §2.1 sabitlerinden.
- Godot import ayarı: `nodes/root_scale = 1.0`, `meshes/generate_lods = false`, `meshes/ensure_tangents = false`, `meshes/light_baking = disabled`; mesh'ler `.res` olarak kaydedilir (T-012 MultiMesh'e doğrudan verir).
- **Kit manifestosu** (teslimat): `assets/models/buildings/kit_manifest.json` — kimlik başına aile, varyant, kat, ayak izi (w, d), saçak ve toplam yükseklik, çatı tipi (`flat|hip|gable|mono|sawtooth|special`), `gf` var/yok, LOD üçgen sayıları, izinli duvar/çatı palet satırları, dönem etiketi (`old|mid|late|new`), sha256. T-005 ve T-012 bina bilgisini **yalnız buradan** okur (koda gömülmez).
- Doğrulama betiği (T-004): import sonrası üçgen sayısı, AABB (m), surface = 1, malzeme adı, pivot (AABB min y = −2,5 / taban merkezi x,z ≈ 0) manifestoyla karşılaştırılır (desen: `experiments/asset-pipeline-smoke/check_import.gd`).

## 9. Kit kabul listesi (art-director kapısı)
### 9.1 Capture preset'leri (kit_lab sahnesi; aynı ışık §5; 1600 × 900; argümanlar kaydedilir, önce/sonra aynı preset)
| Preset | Kamera | Ne gösterir |
|---|---|---|
| `kit_lineup` | ortografik yan görünüş, tüm modüller + `prop_human`, `veh_car`, `veg_plane` 1 m ızgara zemin üstünde yan yana | ölçek tablosu (§2), saat kulesi oranı (§4) |
| `kit_street` (yakın) | göz/drone: yükseklik 12 m, mesafe 60 m, eğim 12°, FOV 50° | LOD0, dükkân bandı, insan/araç ölçeği |
| `kit_block` (orta) | mesafe 400 m, eğim 40° | ~60–120 yapılık test mahallesi; varyasyon; LOD0↔LOD1 sınırı |
| `kit_district` (uzak) | mesafe 2.500 m, eğim 50° | ~1.500+ yapı; LOD1↔HLOD1; tekrar/maket hissi |
| `kit_roofs` | tepeden 90°, 600 m | çatı payı (§3.2) |
| `kit_square` | meydan + saat kulesi + 4–5 katlı çerçeve, mesafe 150 m, eğim 25° | §4 oran kuralı |
Test mahallesi sabit tohumlu, §3.3 kurallarıyla üretilir (gerçek WorldData gerekmez; coğrafyadan bağımsız). Metro HLOD2 kanıtı T-012'nin `metro` preset'indedir.

### 9.2 Kit ölçütleri (her biri kanıt görseli + gözlem ile)
K1 ölçek tablosu `kit_lineup`'ta ±%5 içinde · K2 saat kulesi 21–25 m ve `kit_square`'de 1,3 ≤ oran ≤ 1,8 · K3 dönemler (A/B/C/E + K) yan yana ayırt edilir · K4 `kit_roofs`'ta kiremit payı §3.2 tablosunda, ≥ 2 kiremit tonu · K5 `kit_district`'te tekrar birimi seçilemiyor, §3.3 sayaçları geçer · K6 surface = 1, mesh sayısı ≤ 40, üçgenler §7.2 içinde (betik çıktısı) · K7 draw call/üçgen preset bütçeleri (perf probe) · K8 LOD/HLOD geçişinde renk/yükseklik korunur, visual-diff ≤ %5 · K9 gölgedeki cephe ≥ %40 parlaklık, siyah cephe yok · K10 reddedilenler yok (Adriyatik, tek kırmızı halı, oyuncak doygunluk, hiperreal) · K11 determinizm (2 koşu aynı sha256) · K12 manifest ↔ import eşleşiyor.

### 9.3 VIS-06 yanıt biçimi (F04 soru 1–6; her büyük görsel teslimde, görev dosyasına)
```
Q<n> <sorunun kısa adı>: EVET | KISMİ | HAYIR | KAPSAM DIŞI (gerekçe)
  Kanıt: artifacts/screenshots/captures/<dosya>.png [preset, argümanlar]
  Görülen: <yalnız görüntüde görülen>
  Çıkarım: <görülmeyen ama varsayılan; ayrı yazılır>
  Kural: VIS-0x / WLD-0x · Düzeltme (HAYIR/KISMİ ise): <somut iş + sahip>
```
Kit teslimi (T-004) için beklenen: Q1 (çağdaş karma metropol dokusu) ve Q4 (eski/orta/yeni stok, sanayi, konut, ticaret, kamu) **EVET** olmalı (`kit_block`, `kit_district`, `kit_lineup`); Q2, Q3, Q5 yerleşim olmadığı için **KAPSAM DIŞI** (T-005/T-006); Q6 en çok **KISMİ** (yalnız kit_lab; aynı gramer — §5 ışık + T-001 arazi paleti üzerinde bir `kit_block` karesi).

## 10. Referans yönü (kopya değil)
- 02 (T0): kentsel kütle açık renkli, sıkı, kıyıya yaslı; çatı/duvar sıcak-açık tonlar; yükseklik çoğunlukla 2–6 kat; yeşil-okra yamaçla net ayrışma. **Alınan:** yoğunluk ve renk ilişkisi. **Alınmayan:** çatıların neredeyse tamamının kiremit olması, sinematik ışık, kart/etiketler.
- 03 (olgun): tarihî çarşı dokusu (sık, alçak), modern küme (yüksek, seyrek), sanayi/liman yatay hacimleri, palmiyeli kıyı bandı. **Alınan:** ölçek hiyerarşisi (alçak tarihî çekirdek ↔ yüksek modern küme ↔ yatay sanayi). **Alınmayan:** ZOOM kartlarındaki ölçek/etiketler, "Bayraklı/Kadifekale" adları, kule konumları, fotogerçekçi doku.

## 11. Açık sorular (kullanıcı kararı; iş bloklanmaz, değerler veri/yapılandırma)
- **S1** Dini yapılar (cami kubbesi/minare, kilise) kitte yer alacak mı, hangi ölçekte? F04 kilise kulelerini Adriyatik çağrışımı olarak reddediyor; 03 görseli bir kubbe gösteriyor. v0: hiçbiri yok.
- **S2** Çatı payı tablosu (§3.2): metro genelinde kiremit ≤ %35, merkez penceresinde ≤ %55 — onaylanıyor mu? (Referans görseller daha kiremitli.)
- **S3** T0'da yüksek bina (≥ 12 kat) var mı? v0 varsayımı: T0'da `off_tower` yok, `res_new`/`off_mid` az ve D1 çekirdeğinde sınırlı (oran T-005 veri parametresi).
- **S4** Saat kulesi hedef yüksekliği 23 m (21–25) — onaylanıyor mu?

## 12. T-004 üretim sırası (öncelik)
1. `bld_res_mid` (B) a–d + `_gf` — kentin baskın dokusu; üreteç `lowpoly_block.py`'den türetilir (tek malzeme + UV0 parça kimliği).
2. `bld_res_old` (A) a–d + `_gf` — tarihî çekirdek, cumba/kırma çatı.
3. `bld_res_late` (C) a–c + `_gf` — geç dönem; B'den silüetle ayrışmalı.
4. `bld_res_house` (E) a–c — küçük merkezler/köyler (T0'da D2–D5 için gerekli).
5. `bld_ind_shed` (I) a–c — depo/sanayi (testere dişi varyantı dahil).
6. `bld_ind_heritage` (K) a–b + `prop_chimney` — tuğla/taş eski sanayi izi.
7. `bld_civ_hall` (L) a–c — sivil yapı.
8. `bld_lmk_clocktower` (O) + ölçek nesneleri `prop_human`, `veh_car`, `veg_plane` — ölçek kapısı (K1/K2) bunlarsız açılmaz.
Her modül LOD0 + LOD1 + PROXY; kit_palette (json → png), `mat_kit` shader, `mat_kit_proxy`, `kit_manifest.json`, import doğrulama betiği aynı teslimdedir. Sonraki dalga: `off_mid`, `ind_workshop`, `com_bazaar`, `civ_school`, `res_new`, `civ_pier`, `off_tower`, `lmk_stadium`.

## 13. T-004 uygulama notları (technical-artist; çelişki/netleştirme, kararı art-director verir)
Bu bölüm spec'i değiştirmez; T-004 uygularken bulunan çelişki/belirsizlikleri ve v0'da seçilen çözümü kaydeder.
1. **A (res_old) 2 kat saçak 6,5 m ↔ konut katı 3,0 m (§2.1/§2.2):** 2 × 3,0 = 6,0 m. v0 çözümü: 2 katlı A varyantlarına **0,5 m yüksek kagir kaide** (`plinth`) → saçak 6,5 m, kat 3,0 m sabit kalır. Alternatif: tabloyu 6,0 m'ye çekmek.
2. **Parça tablosu (§6):** brick (W10) için rezerv parça 6 kullanıldı (K sabit tuğla), 8 = gövde, 9 = ten; palet satırları 25–29 (ağaç gövdesi, 3 yaprak tonu, ten) prop'lar için eklendi (satır 0–24 spec §5 aynen).
3. **Compatibility renk hattı:** `source_color` uniform'u ve `ALBEDO` çıktısı bu projede doğrusal→sRGB dönüşümü yapılmadan gösteriliyor gibi davranıyor (palet sRGB değeri aynen girildi, `source_color` ile). Aydınlatma gama uzayında toplanır; **güneşi gölgeli açmak (`shadow_enabled = true`) aynı malzemede yüzey parlaklığını ≈ ×1,4 artırdı** (düz gri 0,5 albedo: gölgesiz 0,43, gölgeli 0,61; T-001 ışık tabanı 0,7/0,85 ile). Sonuç: güneşli duvar W1 → neredeyse beyaz (247), brick W10 turuncu-kırmızıya kayar. Öneri (AD kararı): kit görsel kapısında güneş 0,5 / ortam 0,7 denensin (`--sun-energy=0.5 --ambient=0.7`); metro'da gölge kapalı olması terrain parlaklığını da değiştirir (godot-engineer'a not).
4. **§3.3(5) 200 × 200 m'de ≥ %60 benzersiz kombinasyon:** E/A ağırlıklı yoğun küçük yapı bölgelerinde (mesh varyantı 5–6 × duvar rengi 5) matematiksel olarak sağlanamaz (≈ 45 kombinasyon / 150 yapı). Lab'da yapı yoğunluğu ve ek varyantlarla (E: 5, A: 6 mesh) sağlandı; T-005 için not: kural varyant sayısına ve yoğunluğa bağlıdır.
5. **Ayak izi ölçüleri ek parçaları içerir:** E c (yan ek), I c (ek hacim), K b (kule), L a (portiko basamakları) için manifest `footprint_m` = ek hacimli sınır kutusudur; tente/portiko çıkıntıları (`_gf` tente 1,2 m, L a basamak 6,4 m) AABB'ye girer, ayak izine girmez.
6. **Kiremit payı sınıfı:** testere dişi çatı malzemesi ne olursa olsun "diğer" sayıldı (§3.2 tablosu "Diğer (testere dişi, kurşun R8)").
7. **Işık varsayılanı (art-director T-004 kapısı B1):** kit_lab artık güneş **0,5 / ortam 0,7** ile açılır (not 3'ün önerisi uygulandı; §5'teki 0,7/0,85 T-001 tabanıdır, kit için geçerli değildir). K9: gölge/ışık cephe parlaklık oranı ölçülen **0,52** (yalnız-ortam en kötü durum; eşik ≥ 0,40). Kırpılan piksel (herhangi kanal = 255): kit_street_close **%3,34** (tek yakın W1 cephe, yalnız R kanalı; eşik ≤ %1 AŞILDI), diğer tüm presetler ≤ %0,11. Kanıt: `artifacts/kit/render-k9.json`.
8. **LOD/yığın chunk'ı ve draw call (B2):** kit_lab varsayılanı **--chunk=1000** (§7.1). 250 m chunk bütçeyi aşıyor: district **601** (bütçe ≤ 300), block 434, street 214; 1 km chunk ile district **121**, block 115, street 88 (art-director 1 km'yi onayladı). Bedeli: street/block'ta üçgen ≈ 0,76–0,77 M (LOD seçimi chunk başına olduğundan yakın chunk'ta uzak yapılar da LOD0 kalır); T-012 HLOD birleştirmesi bunu çözecek. Ölçüm: `artifacts/kit/render-k9.json`, `artifacts/perf/*-k-kit_*`.
9. **--terrain (B4-hazırlık, §9.3 Q6):** `kit_lab --terrain` gerçek WorldData arazisini (TerrainView, yalnız okunur) kurar, kit alanını en düz (yükseklik aralığı 1 m) kara dilimine oturtur, arazi 0,6 m aşağıda. Kareler: `artifacts/screenshots/captures/*-d-terrain-block.png`, `*-d-terrain-wide.png`.
