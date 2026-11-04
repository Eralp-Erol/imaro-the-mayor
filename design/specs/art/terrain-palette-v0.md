# Arazi paleti v0 — sanat yönü (T-001d)

- Statü: **ÇALIŞMA MODELİ** (art-director, T-025). Kanon değildir.
- REQ: VIS-01, VIS-04, VIS-05, WLD-01, WLD-02; ilgili T-001 kararları (aşağıda "korunur").
- Uygulayıcı: godot-engineer (render hattı, T-001d / T-001a ile birlikte); ada tepesi ve kıyı geometrisi world hattı (T-001b/T-001c). Bu belge **yön verir; kodu değiştirmez**. Mevcut uygulama: `src/view/terrain/terrain_palette.gd`.
- Bina paletiyle ilişki: `building-kit-v0.md` §5 — binalar araziden daha açık (bina V 0,55–0,86; arazi V 0,32–0,64), kent kütlesi metroda araziden ayrışır.
- İşaretler: **[K]** kanondan · **[ÇM]** çalışma değeri · **[T-001]** T-001'in yazılı/onaylı kararı, korunur.

## 1. Dayanak: incelenen gerçek görüntüler (2026-10-20, T-001 final, 1600 × 900, aynı preset'ler)
| Görüntü (`artifacts/screenshots/captures/`) | Görülen |
|---|---|
| `20261020-164429-t001-final-metro.png` | Körfez/kıyı/ova/yamaç okunur (T-001 GEÇER). Ova tek parça olive-haki, içinde bulanık lekeler; orman koyu yeşil yumuşak kenarlı lekeler; kaya yalnız kuzey ve GD sırt tepelerinde (doğru). D4 tarlaları dönük, eşit boyutlu, yüksek kontrastlı **dama tahtası**. Adalar düz, ana karanın ova rengiyle aynı. Metroda faset neredeyse okunmuyor; kabartma "keçe" gibi. |
| `20261020-164459-t001-final-d5_slopes.png` | Yakında renk **piksel mozaiği** (≈ 50 m'lik parlaklık oynaması + köşe rengi interpolasyonu): faset yerine piksel-sanat/voksel izlenimi. Kaya bantları ızgara köşegeninde testere dişi. Sırt diplerinde siyah çatlak çizgileri (gölge; T-001a). |
| `20261020-164444-t001-final-plain_east.png` | Tarlalar testere dişli kenarlı lime/sarı karolar; kontrast yüksek, ova "yorgan" gibi; tarla yönü tüm ovada tek. |
| `20261020-164452-t001-final-harbor.png` | Kıyı 100 m hücre basamaklı; turkuaz sığ bant yumuşak ve geniş, adalar etrafında hale izlenimi hâlâ var; kıyıda kum çizgisi seçilmiyor. |
| `20261020-164436-t001-final-bay_west.png` | Adalar düz "krep", ana karayla aynı renk; turkuaz kenar bulanık; derin su lacivert okunur (iyi). |

Çıkarım (görülmeyen, kod okumasından): renk köşe başına hesaplanıyor ve üçgen içinde interpole ediliyor (`land_color(... sample ...)`), sürekli `lerp`/`smoothstep` karışımları sınıfları birbirine eritiyor; 8 tarla tonu V 0,34–0,72 aralığında.

## 2. Korunanlar [T-001]
- Su mantığı: sığ şerit **en yakın kıyıya**, orta→derin geçişi **yalnız ana karaya** uzaklığa bağlı; ada "balon halesi" yok; en koyu ton siyaha yaklaşmaz.
- Kaya kuralı: gri kaya yalnız **dik VE yüksek** yerde (`rock_weight`: eğim 24–36° × kot 590–710 m; zirve > ~800 m; uçurum > 44°). Eşikler korunur; yalnız renk ve sınır netliği bu belgeyle değişir.
- Tarla bölgesi veri odaklı (`FIELD_REGION_CODES` D4, D2); koordinat gömülmez.
- Işık tabanı (güneş 38° / 305°, enerji 0,7; ortam (0.60, 0.65, 0.74) × 0,85; metroda gölge kapalı, < 30 km açık).
- Determinizm: renk yalnız WorldData türevleri + dünya konumu + tohumdan.

## 3. Hedef: 5 ayrık biyom sınıfı (+ kum ve kentsel zemin) [ÇM]
Renk **sınıf olarak** seçilir; sınıflar birbirine sürekli `lerp` ile erimez. Sınıf içi oynama küçük, sınıflar arası adım belirgin.

| Sınıf | Ne (nerede) | Hex | Color(r,g,b) | Seçim kuralı (yön; eşikler godot-engineer'in ayarı) |
|---|---|---|---|---|
| T1 | Ova tarım tabanı (tarlaların arası) | #8C8450 | 0.55, 0.52, 0.31 | düz (< 5°) ve alçak (< 120 m), tarla bölgesi |
| T2 | Kuru çayır / kıyı ovası (tarlasız alçak) | #958A58 | 0.58, 0.54, 0.35 | düz-hafif eğim, alçak, tarla bölgesi dışı |
| T3 | Zeytinlik / alçak maki (gri-yeşil) | #6B7048 | 0.42, 0.44, 0.28 | 5–15° eğim veya 120–350 m; **adaların varsayılanı** |
| T4 | Çam ormanı | #3A5232 | 0.23, 0.32, 0.20 | 150–600 m, kuzeye/gölgeye bakan veya > 12° yamaçlar |
| T5 | Yüksek maki / garig (kuru okra) | #857A52 | 0.52, 0.48, 0.32 | > 450 m veya güneye bakan dik ve kuru yamaçlar; orman çizgisi üstü |
| (T6) | Kaya — yalnız dik+yüksek (§2) | #9C907C | 0.61, 0.56, 0.49 | `rock_weight` ≥ 0,5 → kaya, değilse yok (yarı karışım yok) |
| (TS) | Kum / kıyı şeridi | #B8A77F | 0.72, 0.65, 0.50 | yalnız ilk kıyı yüz sırası, eğim < 6°; dik kıyıda kum değil T6/T3 |
| (TU) | Kentsel zemin (gelecek: T-005 parsel/blok altında) | #A49C8A | 0.64, 0.61, 0.54 | şimdilik kullanılmaz; yer ayrılır |

Hedef değerler: HSV doygunluk ≤ 0,45 (su hariç), V 0,32–0,64; mevcut FOREST (0.19, 0.32, 0.17) biraz açılır (gölgeli yüz siyaha inmesin), MEADOW yeşilden saman-zeytine kayar (Ege kuru tonu; referans 02'nin ova/yamaç ilişkisi: kuru okra-zeytin zemin, koyu yeşil yalnız orman). **Metroda en az 3, en çok 5 sınıf ayrı ayrı seçilebilir olmalı** (kum/kaya hariç).

## 4. Faset netliği
1. **Üçgen başına tek renk:** üçgenin 3 köşesi aynı rengi taşır (sınıf, üçgen ağırlık merkezinde/çoğunluk kuralıyla seçilir). Üçgen içinde renk gradyanı yok → d5_slopes'taki piksel mozaiği ve bulanıklık biter. (Mesh zaten düz gölgeli; köşe çoğaltma maliyeti T-001a/T-001d ölçümünde raporlanır.)
2. **Sınıf içi oynama:** üçgen başına hash'li parlaklık ±%4 (mevcut 50 m'lik ızgara oynaması ±%3,5 yerine; hücreden küçük ızgara aliasing üretir). Ayrıca 1,5–3 km ölçekli çok düşük frekanslı ton kayması (kuru↔yeşil) ±%5.
3. **Sınıf sınırı:** sınır bir üçgen sırasında biter; sınır gürültüyle bükülür (düz kontur yok) ama renk karışımı yok. İstisna: T1↔T2 arası yumuşak olabilir (aynı tonda iki yakın sınıf).
4. **Işıkla faset:** aynı sınıfta güneşli/gölgeli yüz parlaklık oranı 1 : 0,55–0,75 (gölge yüzü güneşlinin ≥ %40'ı; siyah çatlak yok — T-001a). Metroda tek üçgen ≈ 4 px; orada faset hissi makro kabartma + ayrık sınıf renkleriyle gelir, mikro gürültüyle değil.

## 5. Kaya, yamaç, ada
- Kaya: kapsam metro kara alanının ≤ %6'sı [ÇM]; kıyı uçurumu (≥ 35°) dışında < 450 m kotta görünmez. Ton tek (T6) + parlaklık oynaması; pembe/kırmızı kahve (mevcut ROCK 0.52, 0.40, 0.27) yerine sıcak gri-bej.
- Yamaç sırası (aşağıdan yukarı, yöne göre kayar): T2/T1 → T3 → T4 (gölgeli yüzler) / T5 (güneyli kuru yüzler) → T5 → kaya. D5 yamaçları referans 02'de kuru okra-yeşil karışımı: D5'te T3+T5 baskın, T4 lekeler halinde.
- **Adalar:** tepe kotu 80–180 m (geometri: T-001b, world). Renk: kenar sırası TS veya T6 (dik kıyı), iç alçak düzlükler T2, yamaçlar T3 (maki), > 120 m tepe T5; adada T1 tarla dili yok, T4 orman yalnız > 150 m ve küçük leke. Ada ana karanın ova rengiyle **aynı görünmemeli**.

## 6. Ova tarla dili (D4, D2 — veri odaklı)
- Global tek açılı dama tahtası yerine: **tarla sınırları mesh kenarlarına oturur** (ızgara hizalı veya 45° köşegen); dönük dikdörtgen 100 m'lik köşe ızgarasına rasterize edilmez (testere dişi oluşur). Tarla en az 2 × 3 hücre (≥ 200 × 300 m) [ÇM]; uzun şeritler (en/boy 1:2–1:4) ağırlıklı.
- Yön ve boy 2–4 km'lik yamalarda değişir (ızgara/köşegen + boy seti), tüm ovada tek desen yok. İleride (T-001c/T-005) tarlalar yol/dere/parselden türetilir; bu belge yalnız geçici dili tarif eder.
- Ton seti 8 → **5** ve kontrast düşürülür (V aralığı 0,45–0,64; komşu iki tarlanın V farkı ≤ 0,12):

| | Hex | Color(r,g,b) | Ne |
|---|---|---|---|
| F1 | #A39560 | 0.64, 0.58, 0.38 | buğday/anız |
| F2 | #6F7D45 | 0.44, 0.49, 0.27 | sulu yeşil ürün |
| F3 | #8A6E4E | 0.54, 0.43, 0.31 | nadas toprak |
| F4 | #707448 | 0.44, 0.45, 0.28 | zeytin/meyve bahçesi |
| F5 | #7F8650 | 0.50, 0.53, 0.31 | bağ/sebze |

- Tarlaların %15–25'i arasında koyu sınır sırası (çit/ağaç hattı = T4 × 1,1, tek üçgen sırası). Tarla dışı düz alanlarda (FIELD_STRENGTH_OTHER) tarla dili yalnız seyrek küme olarak.
- Metroda ova "boş renk lekesi" değil ama yorgan da değil: tarla deseni T1 tabanından düşük kontrastla ayrışır [K, VIS-04].

## 7. Su bantları
| Bant | Hex | Color(r,g,b) | Genişlik [ÇM] |
|---|---|---|---|
| Sığ (turkuaz) | #2F7C82 | 0.18, 0.49, 0.51 | en yakın kıyıdan 60–150 m (1–1,5 hücre); ada çevresinde de en çok 150 m |
| Orta | #175A78 | 0.09, 0.35, 0.47 | ana karadan ~0,4–3 km (mevcut büküm korunur) |
| Derin | #0F3D5E | 0.06, 0.24, 0.37 | ana karadan > ~4 km |
- Bantlar **kademeli** (3 adım, adım arası ≤ 1 hücre karışım): kara tarafındaki ayrık faset grameriyle tutarlı; geniş yumuşak turkuaz parıltı (hale izlenimi) yok. Orta↔derin geçişi geniş kalabilir (mevcut `WATER_DEEP_EDGE`, ana karaya bağlı) — yalnız sığ bant keskinleşir.
- Su mat; speküler parlama/yansıma yok; dalga yok (v0).

## 8. Kabul (T-001d teslimi; art-director kapısı)
Preset'ler T-001 ile aynı argümanlarla, önce/sonra: `metro`, `plain_east`, `d5_slopes`, `harbor`, `bay_west`; her biri için `tools/visual-diff.sh` yüzdesi raporlanır.
- P1 `d5_slopes`: üçgen içi gradyan ve piksel mozaiği yok; faset ışıkla okunur; siyah çatlak yok.
- P2 `metro`: 3–5 sınıf ayrı seçilir; ova ile yamaç/orman/maki arasında sınır net; kent kütlesi için açık (V ≥ 0,55) tonlara yer kalır.
- P3 kaya yalnız dik+yüksek (kapsam ≤ %6, perf probe'dan sayılabilir veya örnekleme testiyle).
- P4 `harbor`/`bay_west`: sığ bant ≤ 150 m ve kademeli; adalar ana kara ovasından farklı renk (maki/kuru çayır), tepe gölgesi görünür (T-001b sonrası).
- P5 `plain_east`: tarla kenarlarında testere dişi yok; tek yönlü dama tahtası yok; komşu tarla V farkı ≤ 0,12.
- P6 perf: metro draw call ve kare süresi T-001 ölçümünden kötüleşmez (152 dc; ort 2,7 / p95 5,3 ms, aynı makine koşulu notuyla).
- P7 testler: `tests/view/` palet testleri (determinizm, kaya kuralı) güncellenir; renk değerleri sabit tablodan okunur.

## 9. Açık sorular
- Yok (kanona dokunan karar yok). Ada iç rengi (maki/kuru çayır) ve "adada tarla yok" yalnız görsel ÇM'dir; ada kullanımı oyuncu kararıyla değişebilir (WLD-03) ve o zaman renk veriden (arazi kullanımı) gelir.
