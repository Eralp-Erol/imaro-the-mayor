# Imaro varlık kütüphanesi — tasarım sistemi v0

- Statü: **ÇALIŞMA MODELİ** (art-director, T-052, 2026-10-25). Kanon değildir; kanonla çelişirse kanon kazanır (`design/CANON.md`). Bu belge **kural ve yön** verir; hiçbir varlığı onaylamaz. Onay yalnız kullanıcıdadır (Creative Director).
- REQ: VIS-01, VIS-02, VIS-03, VIS-04, VIS-05, VIS-07; ilgili WLD-01, WLD-07, CAN-03.
- Kaynaklar (çelişki yok; bu belge onları **özetler ve bağlar**, değiştirmez): `design/specs/art/building-kit-v0.md` (ölçek, saat kulesi, malzeme mimarisi, isimlendirme), `design/specs/art/building-kit-v1.md` (palet v1, çatı payları, kütle aileleri, bölge tablosu, bitki, LOD v1), `design/specs/art/terrain-palette-v0.md` (arazi sınıfları). Bina kuralı için ilk kaynak her zaman bu iki kit belgesidir; bu belge bina kuralı **eklemez**.
- Eşlik eden belge: `design/library/templates-v0.md` — kullanıcı onayına sunulacak insan / araç / yol kesiti / bitki / kent zemini / sokak donatısı şablon önerileri.
- Üretim ve araçlar (bu belgenin kapsamı dışı): `technical-artist` — `data/library/catalog.json` (katalog şeması onun), `tools/library/` (kontak sayfası üreteci), `design/library/sheets/` (PNG'ler). Onay kapısı kodu: `godot-engineer`.
- İşaretler: **[K]** kanondan aynen · **[ÇM]** art-director çalışma değeri (veri; kullanıcı kararı veya ölçümle değişir) · **[AÇIK]** kullanıcı kararı gerekir · **[DOĞRULANACAK]** kontak sayfası/oyun yakalaması olmadan iddia edilmeyen şey.

> **Kanıt durumu (2026-10-25):** Bu belge yazılırken kütüphanenin hiçbir kontak sayfası yoktu (`design/library/sheets/` boş). Aşağıdaki tüm görsel hedefler (okunurluk, ton ayrımı, ölçek hissi) **[DOĞRULANACAK]** niteliğindedir; bir kural ancak sayfada ve oyun yakalamasında görüldükten sonra "sağlanıyor" denebilir.

---

## 0. Kütüphanenin işi ve tek kuralı

**Dünyaya onaysız hiçbir şey girmez.** Her görünür varlık (bina, çatı ekipmanı, bitki, araç, insan, yol kesiti, kent zemini, sokak donatısı, işaret/çizgi) kataloğa kimlikle girer, kontak sayfasında çizilir, kullanıcı kimlik bazında karar verir. Onay durumları (T-052 ölçüt 1):

| Durum | Kim yazar | Oyunda kullanılabilir mi |
|---|---|---|
| `proposed` | ajan | **Hayır** (yalnız kontak sayfası / laboratuvar sahnesi) |
| `approved` | **yalnız kullanıcı** | Evet |
| `rejected` | **yalnız kullanıcı** | Hayır; kimlik yeniden kullanılmaz, yeni öneri yeni varyant harfi alır |
| `provisional-in-use` | ajan (yalnız mevcut v0/v1 kit için, bir kez) | Evet, ama **onaylı değil**; kullanıcının sırası geldiğinde `approved/rejected` olur |

Art-director önerisi (şema sahibi technical-artist; karar technical-director ile): **onay içeriğe bağlansın, kimliğe değil.** Katalog kaydı onaylanan dosyanın `sha256`'sını (`approved_sha256`) tutar; üreteç aynı kimliğin geometrisini/rengini değiştirirse sha uyuşmaz ve varlık kapı tarafından `proposed` sayılır. Aksi hâlde "onaylanmış kimlik, onaylanmamış görünüm" oyuna sızar.

Yol çizim aracı (T-042) yalnız `approved` yol kesitlerini; araç/insan yerleştirici (T-050) yalnız `approved` araç/insan şablonlarını sunar. `provisional-in-use` yalnız bugün oyunda olan v0/v1 kit içindir; **yeni kategori (insan, araç, yol kesiti, donatı) için `provisional-in-use` kullanılmaz** — onlar doğrudan `proposed` başlar.

---

## 1. İlkeler (referanslarla ilişki)

1. **Referans yöndür, hedef değil [K, F04, VIS-01].** `design/foundation/visual-references/` görselleri sinematik konsept sanattır. Kütüphane onlardan **renk ilişkisi, kütle hiyerarşisi, doku ritmi, bölge kimliği ve kent hayatı türlerini** alır (ör. 03 ZOOM 4: palmiyeli geniş kaldırım + orta hatlı tramvay + akan araç + yaya; 02 D6 kesiti: beyaz gövdeli vapur). Fotogerçekçi doku, atmosfer pusu, altın saat, kart/etiket, ölçek okları, gerçek yer adları **alınmaz** [K, VIS-07].
2. **Low-key low-poly, mat, düz gölgeli [K, VIS-01].** Yüz başına tek renk, doku/normal map/yansıma/emisyon yok, roughness 1. Karakter **renk satırı + silüet + ritim** ile verilir; ayrıntı modellemesiyle değil (kit v0 §0).
3. **Gerçek ölçek, tek dünya [K, WLD-01, VIS-03].** 1 birim = 1 m. Bir varlık sokakta, ilçede ve metroda **aynı** konum, ayak izi, yükseklik sırası ve renk satırıyla görünür; LOD yalnız sadeleştirir (siler), değiştirmez (yeni renk, yeni ölçek, yeni konum icat etmez).
4. **Yaşayan ama boğulmayan [K, VIS-04, VIS-05; F04 "yoğun ama okunabilir, göz yormayan"].** İnsan, araç, ağaç ve donatı kenti *yaşanmış* gösterir; oyunun okunması gereken bilgisini (parsel, yol, inşaat, sorun) örtmez. Her yüzeyi süslemek yasak; donatı yoğunluğu oyun verisinden (yol sınıfı, bölge, sim yoğunluğu) türer.
5. **Oyuncak değil, hiperreal değil [K, VIS-05].** Doygunluk tavanı (§2), orantı gerçekçi (büyük kafa / kısa bacak "chibi" yok), parlak tek renkli "Lego" araç yok; buna karşılık doku/yıpranma/pus ile gerçekçilik de aranmaz.
6. **Ege/İzmir'den beslenen özgün kent, kopya değil [K, F02, F04].** Gerçek marka, logo, kurum armaları, ulaşım şirketi renk düzenleri (livery), plaka metni ve gerçek yer adları kopyalanmaz (VIS-07, F05-C). "İzmir hissi" tür seçiminden (vapur, tramvay, dolmuş, simit arabası, palmiyeli kordon, çınarlı meydan) gelir; görünüm jeneriktir.
7. **Onay sayfası = oyun görünümü.** Kontak sayfası oyunun kendi render hattında (Godot, Compatibility, `mat_kit` gölgelendiricisi ve paleti) çizilir; Blender render'ı onay için geçmez. Kullanıcının onayladığı ton, oyunda gördüğü tondur.

---

## 2. Palet sistemi

### 2.1 Palet alanları (domain)
Her varlık rengini **adlı bir palet satırından** alır; hex değer koda/mesh'e gömülmez (kit v0 §6: tek kaynak JSON). Önerilen alanlar:

| Alan | Satır kimlikleri | Kim kullanır | Durum |
|---|---|---|---|
| Bina (kit) | W1–W13 cephe, R1–R9 çatı, G1 cam/oyuk, A1–A4 aksan/tente/panjur | binalar, çatı ekipmanı | **v1 Tur 1, oyunda** (`assets/kit/kit_palette.json`, 32 satır) — `provisional-in-use` |
| Bina Tur 2 | W14–W19, G2, R10–R14, A5–A8 | yeni/ofis/sanayi/sera | v1 §2.2 önerisi; 64 satıra genişleme technical-director onayı bekliyor |
| Bitki | P1–P4 (oyunda), P6–P7 (v1 Tur 2), P8–P11 (yeni öneri, templates §d) | ağaç, çalı, bahçe | P1–P4 `provisional-in-use` |
| İnsan | SK1–SK4 ten, HR1–HR4 saç, CL1–CL16 giyim | `hum_*` | **öneri** (templates §a) |
| Araç | VH1–VH16 | `veh_*` | **öneri** (templates §b) |
| Kent zemini | U1–U12 (U1/U2 v1 Tur 2 ile aynı kimlik ve hex) | yol yüzeyi, kaldırım, meydan, avlu, park, sanayi betonu | **öneri** (templates §c, §e) |
| İşaretleme | MK1–MK3 | şerit çizgisi, yaya geçidi, ray | **öneri** (templates §c) |
| Donatı | FN1–FN6 (+ bina/araç satırlarından ödünç) | direk, bank, durak, kiosk | **öneri** (templates §f) |

Teknik not (öneri, karar technical-director/godot-engineer): bina paleti 32 satırda dolu, Tur 2 ile 52 satıra çıkıyor. İnsan + araç + donatı (≈ 40 satır) için **ayrı ikinci bir palet dokusu** (`small` alanı, aynı satır mekanizması, ayrı malzeme) önerilir; insan/araç/donatı zaten ayrı MultiMesh olduğundan ek malzeme draw call maliyetini değiştirmez [DOĞRULANACAK]. Kent zemini ve işaretleme yol/arazi gölgelendiricisinin verisidir (`data/view/road_style.json`, `data/view/terrain_look.json`); hex'ler bu kütüphane kimlikleriyle eşlenmelidir.

Kimlik çakışması kuralı: palet satır kimlikleri v0/v1 ile çakışmaz. Bu nedenle yeni alanlar iki harfli önek kullanır (SK, HR, CL, VH, MK, FN); `C1–C6` (v1 §10 yakalama kimlikleri) ve `K1–K12` (v0 kit ölçütleri) ile karışmasın.

### 2.2 Ton/doygunluk/parlaklık sınırları (HSV; h derece, s ve v 0–1) [ÇM]
| Alan | Ton (h) | Doygunluk (s) | Parlaklık (v) | Gerekçe |
|---|---|---|---|---|
| Cephe (bina) | sıcak 20–50° (mavi-gri yalnız geç/yeni/sanayi) | ≤ 0,42 (tuğla ≤ 0,60) | 0,58–0,87 | v1 §2.1 aynen |
| Kiremit | 14–24° | 0,38–0,66 | 0,55–0,76 | v1 §2.1 aynen |
| Bitki yaprağı | 65–110° | ≤ 0,50 | 0,30–0,55 | binalardan koyu, araziden ayrışır; "zümrüt" yeşil yok |
| Ten (SK) | 18–30° | 0,25–0,52 | 0,40–0,88 | doğal aralık; gri/yeşil ten yok |
| Giyim (CL) | serbest | ≤ 0,63 (tek istisna: iş yeleği CL16 ≤ 0,67) | 0,22–0,90 | kalabalık "şeker kutusu" olmasın; saf siyah (v < 0,15) ve saf beyaz (v > 0,92) yok |
| Araç (VH) | serbest | ≤ 0,45 özel araç; kamu/taksi/feribot gövde ≤ 0,66 | 0,15–0,90 | gerçek trafik dağılımı nötr ağırlıklı; parlak "oyuncak araba" yok |
| Kent zemini (U) | sıcak nötr 30–55° (park çimi 60–75°) | ≤ 0,40 (asfalt ≤ 0,08) | asfalt 0,29–0,40; döşeme 0,54–0,74 | yollar bloklardan koyu çizgi olarak ayrılır (v1 §10.2 C2-3) |
| İşaretleme (MK) | beyaz / sarı | beyaz ≤ 0,06; sarı ≤ 0,62 | ≤ 0,86 | parlayan beyaz şerit yok |
| **Her alan** | — | **s > 0,70 hiçbir satırda yok** [VIS-05] | — | "oyuncak" sınırı |

Alan ilişkileri (okunurluk sırası, [DOĞRULANACAK]): **asfalt < bitki < arazi ≈ park < kent döşemesi < cephe**. İnsan/araç küçük nesnedir; ilçe uzaklığında görünmediği için (§5) kentin genel renk dağılımını değiştirmemelidir.

### 2.3 Dağılım kuralları (örnek verisi; yerleştirici uygular)
- Kalabalıkta hiçbir giyim satırı figürlerin %20'sini geçmez; "aksan" satırları (CL9–CL11, CL14) toplamda ≤ %25; iş yeleği (CL16) yalnız iş bağlamında (şantiye, liman, sanayi avlusu).
- Özel araç gövdesi: beyaz + gümüş + gri + koyu ≈ %70–80, renkli (mavi, kırmızı, yeşil, bej) ≈ %20–30 [ÇM; gerçek trafik gözlemine yakın].
- Komşu iki aynı nesne aynı satırı taşımaz (kit v0 §3.3 ile aynı ilke).

---

## 3. Ölçek ve ızgara [ÇM — kit v0 §2'den; değişen yok]

| Sabit | Değer | Kaynak |
|---|---|---|
| Birim | 1 birim = 1 m | v0 §2, §8 |
| **Ölçek insanı** | **1,75 m** boy, 0,5 m omuz (`prop_human`) — her kontak sayfasında zorunlu | v0 §2.3 |
| İnsan aralığı (şablon) | yetişkin 1,58–1,85; yaşlı 1,55–1,72; çocuk 1,05–1,40 | templates §a |
| Konut katı / dükkân zemin / ofis / sivil | 3,0 / 4,2 / 3,6 (zemin 4,5) / 4,0 m | v0 §2.1 |
| Parapet | 0,9 m | v0 §2.1 |
| Ayak izi ızgarası | 0,5 m | v0 §2.1 |
| Ağ yakalama (snap) | 3 m (`network.json` `geometry.snap_m`) | ağ verisi |
| Saat kulesi | 23 m (21–25), çerçeve 4–5 kat, oran 1,3–1,8 | v0 §4 [S4 AÇIK] |
| Taşıt şeridi | kent içi 3,0–3,25 m; ana arter / sanayi 3,25–3,75 m | templates §c |
| Park şeridi | 2,0–2,5 m (kamyon 3,0–3,5) | templates §c |
| Bisiklet yolu | tek yön 1,5–2,0; çift yön 2,5–3,0 m | templates §c |
| Kaldırım | en az 2,0 m (yamaç sokağı istisna 1,5); ticari 3–5 m; kıyı promenadı 8–15 m | templates §c |
| Tramvay | ray açıklığı 1,435 m; tek hat yatağı 3,1–3,3; çift hat 6,4–6,8 m | templates §c |
| Bordür | 0,15 m yükseklik | templates §c |
| Parsel (cephe genişliği × en çok derinlik) | çekirdek 18 × 34; kompakt 20 × 38; karma 22 × 42; sanayi 55 × 85; kırsal 230 × 250 m (± jitter) | `data/world/ismeral/network.json` `parcel_templates` |
| Yol sınıfı genişlikleri (bugünkü ağ verisi) | arterial 22, collector 15, local 10, field 6, rail 14 m | `network.json` `classes` — yol kesiti şablonları bu genişliklere eşlenir (templates §c) |

Ölçek kontrol nesneleri (her sayfa ve her yakalamada; VIS-03): insan 1,75 · otomobil 4,4 × 1,8 × 1,5 · çınar 14 · palmiye 9 · 3 katlı cephe 9 + parapet · saat kulesi 23 m.

---

## 4. Silüet, çatı ve cephe dili

### 4.1 Genel silüet dili
- **Her varlık 3 işaretle tanınır** (uzaktan → yakına): (1) kütle oranı / silüet, (2) baskın renk bloğu, (3) bir imza ayrıntısı. Dördüncü ayrıntı eklenmez; eklenirse LOD0 bütçesinden ve okunurluktan çalar.
- Faset açıları "kristal" değil: yuvarlak formlar 6–8 kenarlı (ağaç tacı 8–20 yüz, tekerlek 6 kenar), keskin kenarlı küp dünyası (voxel) değil [F04: Minecraft "okunabilir sade hacim mantığı; voxel zorunlu değil"].
- Orantı gerçek; karikatür abartısı yok (büyük kafa, kısa araç, şişkin ağaç yok).
- Kategori imza işaretleri (ayrıntı: templates):

| Kategori | Silüet | Baskın renk bloğu | İmza ayrıntısı |
|---|---|---|---|
| Bina | kütle oranı + çatı formu | cephe + çatı satırı | saçak / balkon bandı / dükkân tentesi (v1 §1) |
| İnsan | boy + gövde genişliği + (etek/palto/çanta) uç formu | üst giyim | baş-saç rengi / taşınan nesne |
| Araç | profil (hatchback / sedan / tek hacim / uzun kutu / bölümlü) | gövde rengi | cam bandı (koyu G1/VH13 şerit) / tekerlek |
| Bitki | taç biçimi (yuvarlak, şemsiye, yıldız, sütun, alçak geniş) | yaprak satırı | gövde (palmiye/çınar açık gövde) |
| Donatı | ince dikey (direk) / alçak yatay (bank) / küçük kutu (kiosk) | koyu metal FN1/FN2 | kol / çatı plakası |
| Yol kesiti | genişlik + bölümleme sırası | asfalt / döşeme tonu | şerit çizgisi / refüj / ağaç sırası |

### 4.2 Çatı ve cephe dili (özet; kural metni kit v1 §3–§5)
- Çatı: karışık kiremit kırma/beşik (≥ 3 ton) + ekipmanlı teras + sanayide sac/tonoz/testere dişi; "tek kırmızı halı" ve "gri halı" ikisi de FAIL; zon payları v1 §3.3 [S2 AÇIK].
- Cephe: eski = dikey pencere ızgarası + cumba + panjur; orta = yatay balkon bantları; geç = köşe balkonu + üst kat geri çekme; yeni = düşey şerit; sanayi = kapı + şerit pencere bandı (boş düz yüzey yasak).
- Zemin kat dükkân bandı (`_gf`) 4,2 m + tente; aynı cephede ≥ 2 tente rengi.
- Yasak: kampanil, kubbe [S1 AÇIK], Venedik köprüsü, kanal evi, cam giydirme parlak kule, alp çatısı [K, VIS-05].

---

## 5. Görünürlük, LOD ve üçgen bütçeleri [ÇM]

### 5.1 Ekranda kaç piksel? (hesap, ölçüm değil)
Perspektif kamera, dikey FOV 50°, 900 px yükseklik: 1 m ≈ 900 / (2 · d · tan 25°) px.

| Mesafe d | px / m | 1,75 m insan | 4,4 m otomobil | 14 m çınar |
|---|---|---|---|---|
| 60 m (sokak yakın) | ≈ 16 | ≈ 28 px | ≈ 71 px | ≈ 225 px |
| 200 m (sokak preset) | ≈ 4,8 | ≈ 8 px | ≈ 21 px | ≈ 68 px |
| 400 m (ilçe yakın) | ≈ 2,4 | ≈ 4 px | ≈ 11 px | ≈ 34 px |
| 2.000 m (ilçe) | ≈ 0,5 | < 1 px | ≈ 2 px | ≈ 7 px |

Sonuç: **insan 200 m'de yalnız renk beneğidir**; siluet tipi yalnız < ~100 m'de okunur. Bu yüzden insan şablonlarında önce **renk ve boy**, sonra silüet tasarlanır. 300 m ötesinde insan çizilmez; araç ~1 km ötesinde çizilmez (yol rengi taşır) [ÇM; mesafeler godot-engineer ölçümüyle ayarlanır].

### 5.2 Kategori başına bütçe
| Kategori | LOD0 üçgen | LOD1 üçgen | Görünürlük (masaüstü, yaklaşık) | Uzak temsil |
|---|---|---|---|---|
| Bina konut / kamu-ofis / landmark | ≤ 900 / ≤ 1.200 / ≤ 1.500; kent ortalaması ≤ 450 | ≤ 64 (konut ort. ≤ 40); PROXY ≤ 14 | LOD0 < 250–350 m | HLOD (v1 §8) |
| Çatı ekipmanı (mesh içi) | bina bütçesinin içinde | LOD1'de tek kutu | LOD0 | yok |
| Bitki (ağaç) | ≤ 72 | ≤ 12 | LOD1 ~1,2 km'ye kadar | ağaç lekesi (v1 §7) |
| Çalı / çit / bahçe yaması | ≤ 24 | ≤ 6 | ≤ 400 m | zemin tonu |
| İnsan | **≤ 120** (öneri; seçenek tablosu templates §a) | ≤ 16 | LOD0 < 80 m, LOD1 < 300 m | **çizilmez** |
| Bisiklet / motosiklet (+ sürücü) | ≤ 120 | ≤ 16 | < 300 m | çizilmez |
| Otomobil / kamyonet | ≤ 140 | ≤ 24 | LOD0 < 250 m, LOD1 < 1 km | çizilmez (yol rengi) |
| Minibüs / otobüs / kamyon | ≤ 220 | ≤ 32 | LOD1 < 1,5 km | çizilmez |
| Tramvay (bölümlü, tamamı) | ≤ 420 | ≤ 48 | LOD1 < 2 km | metroda hat çizgisi (ağ katmanı) |
| Vapur / feribot | ≤ 700 | ≤ 80 | LOD1 < 6 km; metroda PROXY ≤ 24 | **metroda görünür** (körfez ölçeği) |
| Balıkçı teknesi | ≤ 120 | ≤ 16 | < 1,5 km | çizilmez |
| Sokak donatısı (direk, bank, çöp) | ≤ 40 | — (LOD1 yok) | < 250 m | çizilmez |
| Durak / kiosk / tente / çeşme | ≤ 140 | ≤ 16 | < 400 m | çizilmez |
| Yol kesiti | şerit/kaldırım/refüj yüzleri + bordür; işaretleme ayrı ince şerit | işaretleme ve bordür yok | işaretleme < 300 m; bordür < 600 m | metroda tek renkli şerit (sınıf tonu) |

- Not: kit v0 §2.3'teki `prop_human` (≤ 40) ve `veh_car` (≤ 60) **ölçek referans nesneleri** olarak kalır (`provisional-in-use`). Yeni `hum_*`/`veh_*` şablonlarının bütçesi yukarıdaki tablodur; ikisi çelişmez — ölçek nesnesi sayfa/lab içindir, şablon oyun içindir.
- Toplam sınır değişmez: yerel evre görünür üçgen ≤ 900.000, kare ort ≤ 8 ms / P95 ≤ 16,6 ms (v1 §9). İnsan + araç + donatı için **street preset'te ≤ 80.000 üçgen ve ≤ 40 draw call** pay önerilir; ilçe/metro preset'inde ≈ 0 (vapur hariç). Bütçe gevşetilmez; aşılırsa görünürlük mesafesi kısalır [ÇM; technical-director onayı ve önce/sonra ölçümüyle].
- Godot otomatik mesh LOD kapalı; LOD'lar üreteçle yazılır (v0 §7.2). Hareketli nesneler (insan/araç) iskelet animasyonu kullanmaz; yürüme/teker dönüşü gerekiyorsa gölgelendiricide parça kimliğiyle basit salınım — uygulanabilirliği T-050'de ölçülür [hipotez].

---

## 6. Gölgelendirme ve kontak sayfası standart ışığı

### 6.1 Oyun içi kural (tüm kategoriler)
`mat_kit` ailesi: `diffuse_lambert`, `specular_disabled`, roughness 1, metalik 0, doku yok, palet satırı × parça gölge çarpanı (kit v0 §6). Oyuk/alt yüz = satır × 0,72; gölgedeki yüz güneşlinin ≥ %40'ı (siyah yüz yok). Cam yansımasız koyu satırdır (G1/VH13). Far/stop/sokak lambası **ışık yaymaz** (emisyon yok; gece/aydınlatma ayrı karar).

### 6.2 Kontak sayfası standart sahnesi (technical-artist uygular; her sayfa birebir aynı)
| Öğe | Değer |
|---|---|
| Render | Godot 4.7, Compatibility, oyunun `mat_kit`/palet hattı (Blender render'ı geçersiz) |
| Güneş | yükseklik 38°, azimut 305° (T-001 tabanı), renk (1.0, 0.97, 0.90), **enerji 0,5**, yumuşak gölge açık |
| Ortam | (0.60, 0.65, 0.74), **0,7** (kit_lab varsayılanı, v0 §13 not 7) |
| Ton eşleme / bloom / sis / SSAO | kapalı (oyunla aynı olmayan hiçbir efekt yok) |
| Zemin | U1 kent döşemesi tonu düzlem; 1 m ızgara çizgisi (U1 × 0,85), her 5 m'de koyu çizgi (U1 × 0,7) |
| Arka plan | düz orta nötr gri, v ≈ 0,65 (ör. #A6A9AA) — açık (W1, VH1, CL1) ve koyu (VH5, FN2) varlıklar ikisi de okunur |
| Ölçek | her hücrede **1,75 m `prop_human`** varlığın sağında; araç/bitki/donatı sayfalarında ayrıca 3 katlı (9 m + parapet) gri cephe silüeti arka şeritte |
| Açılar | ön (ortografik), yan (ortografik), 3/4 (35° yükseklik, perspektif FOV 30°), tepeden (ortografik 90°) |
| **Oyun mesafesi paneli** | aynı varlık oyun kamerasıyla (FOV 50°) 60 m ve 200 m'den, **ölçeklenmeden gerçek piksel boyutunda**; insan/araç için zorunlu, bina/bitki için 400 m ve 2 km de eklenir |
| Etiket | kimlik · ölçü (g × d × y m) · LOD0/LOD1 üçgen · palet satırları · onay durumu · sha256 ilk 8 hane |
| Varyant/palet | şablon başına ilk satır varsayılan renkte; ikinci satır izinli palet satırlarının tamamı (renk varyantları yan yana) |
| Çıktı | PNG, ≥ 2048 px genişlik, `design/library/sheets/<kategori>-<tarih>.png`; aynı argümanla yeniden üretilebilir (deterministik) |
| Kapalı hava alternatifi (yalnız gerekirse 2. sayfa) | güneş 0,25, ortam 1,1 nötr gri, gölge kapalı (v0 §5) |

---

## 7. Bölge karakteri (D1–D6) → aileler

Kanon tanımı F02 tablosundadır [K]; aile/pay değerleri kit v1 §6 tablosudur [ÇM]. Bu tablo yalnız **yeni kategorilerin** bölgeye eşlemesini ekler; her ilçe karma ekonomi taşır (WLD-06), eşleme dışlayıcı değil ağırlıktır.

| Bölge | Bina aileleri (v1 §6) | Yol kesitleri (öneri, templates §c) | Araç ağırlığı | İnsan / giyim ağırlığı | Bitki | Zemin / donatı |
|---|---|---|---|---|---|---|
| **D1** merkez / tarihî çekirdek | `res_old_town`, `res_old_row`, `com_bazaar`/`com_han`, `res_mid_*`, `res_mid_slab` (kıyı), `civ_hall`, `lmk_clocktower` | yaya çarşı sokağı, yerel 10, cadde 15, kıyı promenadı, (tramvaylı bulvar [AÇIK]) | otomobil, dolmuş/minibüs, otobüs, taksi [AÇIK], servis kamyoneti; vapur iskelede | en yoğun; karma (ofis, günlük, yaşlı, öğrenci, satıcı) | çınar (meydan/avlu), palmiye (kıyı/meydan) | meydan döşemesi, avlu; bank, direk, kiosk, durak, simit arabası, tente |
| **D6** karşı yaka çekirdeği | `res_mid_slab` kıyı bandı, `res_late_8_10`, `res_mid_*`, `res_old_town`, `com_bazaar`, `civ_pier` | kıyı promenadı + bisiklet yolu, cadde 15, yerel 10 | otomobil, otobüs, bisiklet; vapur | yoğun; aile, günlük, bisikletli | palmiye sırası (kıyı), çınar | promenad döşemesi, park çimi; bank, promenad direği |
| **D2** Orven | `res_mid_4`, `res_old_row`, `com_bazaar`, `ind_workshop`, `res_house` | yerel 10, cadde 15, kıyı yolu | otomobil, kamyonet, minibüs; balıkçı teknesi | orta; günlük, esnaf, iş | bahçe ağaçları, az palmiye | avlu, bahçe; durak, bank |
| **D3** liman / üretim | `ind_shed`, `ind_vault`, `ind_sawtooth`, `ind_heritage`, `ind_port_warehouse`, konteyner; işçi konutu | sanayi yolu, cadde 15, ray koridoru | kamyon, tır, kamyonet, forklift [sonraki dalga]; yük treni | az; iş kıyafeti ağırlıklı (yelek CL16 burada) | avlu kenarı seyrek | sanayi betonu, liman sahası; az donatı |
| **D4** ova | `res_village`, `res_house`, `agr_greenhouse`, `agr_silo`, `ind_shed` | tarla yolu 6, yerel 10, arter 22 | traktör [sonraki dalga], kamyonet, kamyon | seyrek; günlük + tarım işi | zeytin, kavak sırası, bahçe | toprak, avlu; çok az donatı |
| **D5** yamaçlar | `res_hill`, `res_house`, `res_mid_4`, `civ_school` | yamaç sokağı 8, yerel 10, (merdivenli sokak [sonraki dalga]) | otomobil, minibüs, motosiklet | orta-seyrek; günlük, öğrenci | çam, zeytin | toprak/döşeme karışık; direk, bank az |

---

## 8. İsimlendirme (kimlik şeması)

Biçim: **`<önek>_<aile>_<tip>_<varyant>[_sonek]`** — küçük harf, ASCII, `_` ayraç; varyant tek harf `a`–`z`. Kimlik bir kez verilir, değişmez; reddedilen kimlik yeniden kullanılmaz. Mesh nesneleri `<kimlik>_LOD0`, `<kimlik>_LOD1`, `<kimlik>_PROXY` (kit v0 §8).

| Önek | Kategori | Örnek | Not |
|---|---|---|---|
| `bld_` | bina | `bld_res_mid_a_gf` | kit v0 §1, v1 §4 aynen |
| `eqp_` | çatı/bina ekipmanı (ayrı varlık olursa) | `eqp_roof_tank_a` | bugün mesh içi; ayrı varlık yalnız gerekirse |
| `veg_` | bitki | `veg_pine_stone_a` | v0/v1 `veg_plane`, `veg_palm`, `veg_pine`, `veg_olive` korunur |
| `hum_` | insan | `hum_adult_m_a` | v0 `prop_human` ölçek nesnesi olarak kalır |
| `veh_` | araç | `veh_car_hatch_a` | v0 `veh_car` ölçek nesnesi olarak kalır |
| `rds_` | yol kesiti | `rds_coll_15_park_a` | `rds_<sınıf>_<genişlik m>_<kod>_<varyant>`; sınıf = ağ sınıfı (`art`, `coll`, `local`, `field`, `rail`) veya `ped`, `blvd`, `coast`, `ind`, `hill` |
| `gnd_` | kent zemini | `gnd_plaza_paving_a` | |
| `fur_` | sokak donatısı | `fur_lamp_street_a` | |
| `mrk_` | işaret / çizgi | `mrk_lane_dash_a` | |
| `prop_` | ölçek/yardımcı nesne, istif, baca | `prop_container_stack_a` | v0 aynen |
| `lmk_` | landmark | `lmk_clocktower` | tekil; varyant harfi yok |

Etiket alanları (katalog şeması technical-artist'in; art-director'ün sanat için istediği asgari alanlar): `id`, `category`, `family`, `era` (`old|mid|late|new|none`), `regions` (D1–D6 ağırlık veya liste), `size_m` (g, d, y), `tris` (LOD0, LOD1, PROXY), `palette_rows` (izinli satırlar), `silhouette` (kısa tarif), `ref_note` (referanstan ne alındı), `source` (üreteç + argüman), `approval` + `approved_sha256` + tarih + kullanıcı notu.

---

## 9. Yapılacak / yapılmayacak

**Yapılacak**
- Her varlık kontak sayfasında, ölçek insanıyla, standart ışıkta, oyun mesafesi paneliyle sunulur; kullanıcı kimlik bazında karar verir.
- Renk yalnız palet satırından; doygunluk tavanı s ≤ 0,70.
- Gerçek ölçek; LOD yalnız siler, değiştirmez; uzak ölçekte görünmeyecek nesne (insan, küçük araç, donatı) uzakta **çizilmez** (sahte "kalabalık lekesi" de çizilmez).
- İnsan/araç sayısı ve türü sim verisinden türer (T-050, CAN-03 ruhu: sahte yaşam dekoru yok).
- Jenerik, özgün görünüm: marka/logo/livery/plaka metni yok; İzmir hissi tür seçiminden.
- Bölge karakteri ağırlıklarla; her ilçede karma.

**Yapılmayacak**
- Onaysız (`proposed`/`rejected`) varlığın oyunda görünmesi; onaylı kimliğin görünümünü sessizce değiştirmek (sha kuralı).
- Fotogerçekçilik, doku/normal map, yansıma, emisyon, bloom, altın saat [VIS-01].
- Oyuncak doygunluk, chibi orantı, parlak tek renk araçlar, "4 bloklu maket" tekrarı [VIS-05].
- Adriyatik/Venedik (taş köprü, kanal, kampanil, gondol/tekne kalabalığı), tatil köyü palmiye ormanı (palmiye yalnız kıyı/meydan) [VIS-05].
- Konsept görsellerindeki bina, tramvay, vapur tasarımlarının veya UI kartlarının birebir kopyası; gerçek kurum/şirket adı, logo, livery [VIS-07, F05-C].
- Protagonist veya adlı NPC görünümü (Q-005, T-026 — kütüphanenin `hum_*` şablonları anonim kalabalıktır).
- Dini/etnik/siyasi kimlik işaretini (kıyafet, sembol, bayrak, slogan) kullanıcı kararı olmadan kalabalığa koymak (Q-010 AÇIK).
- Polis/jandarma/askerî araç ve üniforma (kurum ve yetki yapısı AÇIK, F05-D; Q-010).
- Bütçe gevşetme.

---

## 10. Kategori listesi ve onay sırası önerisi

Sıralama ölçütü: (1) hangi oyun işini bekletiyor, (2) diğer kategorilerin ölçeği/ışığı buna mı dayanıyor, (3) kullanıcının en çok gördüğü yüzey.

| Sıra | Kategori | Neden bu sırada | Bekleyen iş | İlk sayfa kapsamı |
|---|---|---|---|---|
| 0 | **Kontak sayfası standardı + palet alanları** | Diğer tüm onaylar bu sayfa biçimine ve ışığına dayanır; kullanıcı önce "nasıl göreceğini" onaylar | hepsi | mevcut `prop_human`, `veh_car`, `veg_plane`, `lmk_clocktower` ile örnek sayfa + palet alanı şeritleri (§2) |
| 1 | **Yol kesitleri + işaretleme** | Yol çizim aracı yalnız onaylı kesitleri sunacak; kentin "koyu çizgi" iskeleti; kullanıcının ilçe kamerasında en çok gördüğü katman | T-042 | templates §c tablosu: yerel, cadde, arter, sanayi, tarla, yaya, kıyı; kesit diyagramı + 3/4 görünüş + 400 m ve 2 km paneli |
| 2 | **Kent zemini** | Yol kesitiyle aynı sayfada okunur (kaldırım/meydan/avlu); v1 "çim üstüne serpilmiş kent" kusurunun çözümü | T-051 kent zemini, T-042 | templates §e |
| 3 | **Araç** | T-050'nin ilk yaşam belirtisi; ölçek hatası en kolay araçta görülür | T-050 | otomobil 3, minibüs, otobüs, kamyonet, kamyon, bisiklet, motosiklet; vapur ayrı sayfa |
| 4 | **İnsan** | T-050; önce **stilizasyon seviyesi** (templates §a seçenek A/B/C) onaylanır, sonra tipler | T-050 | 3 stilizasyon örneği aynı boyda yan yana → seçilen seviyede 6–8 tip |
| 5 | **Sokak donatısı** | Yol kesitine ve araç/insana bağlı; yoğunluk kuralı en son | T-042 sonrası, T-050 | direk, bank, durak, kiosk, tente, çöp, bariyer |
| 6 | **Bitki** | Bugün `provisional-in-use` (T-051); yeni türler (fıstık çamı, kavak, çalı) eklenir | T-051 Tur 1/2 | mevcut 4 tür + öneriler |
| 7 | **Bina kiti v0/v1** (`provisional-in-use` → karar) | Oyunda zaten var; kullanıcının ayrıca karar vermesi gereken S1–S4 (Q-013) ile birlikte | T-051 | aile başına sayfa (kit v1 §4 sırası) |
| — | Landmark, stadyum, dini yapı, gece aydınlatması, mevsim | Kanon/kullanıcı kararı AÇIK | — | soru olarak (`production/QUESTIONS.md` Q-013, Q-018) |

Her onay turunun çıktısı: kullanıcı kararları katalogda (`approved/rejected` + not), kullanıcının sözleri gerekiyorsa `design/decisions/` altına. Art-director PASS'i kullanıcı onayı **değildir**.

---

## 11. Doğrulanmamış / riskler
- Hiçbir kontak sayfası yok; §2.2 ton ilişkileri, §5.1 okunurluk eşikleri ve §6.2 arka plan tonu sayfa üretilince doğrulanmalı.
- `small` palet alanı ve 64 satır genişlemesi teknik onay bekliyor (technical-director); onaysız durumda insan/araç renkleri kit paletine sığmaz.
- Bugünkü yol görünümü (`data/view/road_style.json`: soğuk gri #626769–#777b7d, metroda genişlik × 0,55) bu belgenin asfalt aralığından (sıcak nötr, v 0,29–0,40) ayrılıyor; ayrıca metroda genişliğin daraltılması "LOD yalnız sadeleştirir" ilkesine sınırda. Yol kesitleri onaylanınca hizalanmalı (T-042/T-048 sahibi). Bugünkü yollar katalogda `provisional-in-use` olmalı.
- Onay içeriğe (sha256) bağlanmazsa onay kapısı delinebilir (§0).
