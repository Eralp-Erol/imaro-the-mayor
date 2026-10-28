# ADR-0008 · Görünür üçgen ve kare bütçesi: yoğun çekirdek kök nedeni ve düzeltme sırası

- **Güncelleme (D-007, kullanıcı kararı, 2026-10-28):** masaüstü kabul eşiği ort <= 14 ms ve tiksiz p95 <= 20 ms olarak yumuşatıldı; bu ADR'deki katı ölçütler iPad / hedef cihaz hedefi olarak kalır; T-071/T-072/T-074 askıda (T-070 ölçümü: `production/log/2026-10-28-T-070-ucgen-dagilimi.md`).
- Durum: önerildi · Tarih: 2026-10-28 · Karar veren: technical-director. Görseli gözle değiştiren tek seçim §Kullanıcıya bölümündedir (Q-020 önerisi). Bu ADR o seçimi yapmaz. Kanon, D-006 ve ADR-0007 değişmez.
- Karşıladığı gereksinimler: TEK-01, TEK-03, TEK-05, VIS-01, VIS-03, VIS-04, PLT-05, PLT-06
- Dayanak: ADR-0001 (render kare süresi sim durdurulmuşken ölçülür; ort ≤ 8 ms, p95 ≤ 16,6 ms), ADR-0004, ADR-0006 §2.5/§3.1/§3.4/§4/§12, ADR-0007, QA raporu `production/log/2026-10-28-T-062-QA-raporu.md` (bulgu B-1), ham ölçüm `artifacts/library/t062/qa/perf/*.json`.
- Etiketler: **[ölçüldü]** QA JSON'larından bu oturumda okundu · **[okundu]** kod/veri okundu · **[hesap]** aritmetik · **[varsayım]** doğrulanmadı · **[ölçülmedi]**. Godot bu ADR için çalıştırılmadı.

## Bağlam

**Ölçüm [ölçüldü].** Tüm değerler 3 koşunun medyanıdır; makine: Radeon Pro 560X, `gl_compatibility`, 1600x900. "Tick'siz" sütunları, sim tick'i olmayan karelerdir (`tick_correlation.non_tick_frame_ms`).

| Sahne | ort ms | p95 ms | tick'siz ort | tick'siz p95 | render_cpu ort | primitives | draw call |
|---|---|---|---|---|---|---|---|
| çekirdek (`street:20200,18700`), önce `bbb84d8` | 12,59 | 15,79 | 11,94 | 15,01 | 8,01 | 2,494M | 414 |
| çekirdek, sonra HEAD | 14,03 | 21,86 | 13,28 | 16,99 | 8,85 | 2,865M | 353 |
| çekirdek, sonra, bitkisiz (n=1) | 13,00 | 17,63 | 12,21 | 15,52 | 7,08 | 2,437M | 312 |
| street:port, sonra | 6,65 | 9,88 | 6,19 | 8,90 | 2,52 | 0,316M | 209 |

**K-1 · p95 aşımının çoğu sim tick'inden.**
- Tick kareleri 240 karenin 52–55'i (≈ %22); tick karelerinin p95'i 21–52 ms, tick'siz p95 16,99 ms. Tick'li karede `sim_drive` ort 5,2–6,3 ms, `hud_poll` 2,7–3,4 ms; r2'de `hud_poll` ort 64 ms (aykırı, sebebi bilinmiyor) [ölçüldü].
- Sonuç: 21,86 ms'lik statik p95 ≈ 17 ms render tabanı + tick sıçramaları. ADR-0001 render süresini sim durdurulmuşken tanımlar, QA render+sim'i birlikte ölçtü; iki ayrı kapı gerekir (Karar 1).

**K-2 · Ortalama, primitive sayısıyla doğrusal görünüyor [hesap].**
- Tick'siz ortalamalardan iki noktalı doğru (port ve çekirdek, sonra): eğim ≈ 2,78 ms / milyon primitive, kesişim ≈ 5,3 ms. Doğru diğer iki noktayı tutuyor: bitkisiz tahmin 12,08 / ölçülen 12,21 ms; önce tahmin 12,24 / ölçülen 11,94 ms.
- Bu doğruya göre ort ≤ 8 ms ≈ 0,97M primitive; 900k bu cihaz için doğru büyüklüktedir, keyfî değildir.
- Sınır: GPU süresi ölçülemiyor (`render_gpu_ms = 0`), vertex/fragment ayrılmadı. `render_cpu_ms` port'ta 2,5, çekirdekte 8,9 ms, nesne sayısı benzer (1.145 / 1.086–1.295): GL sürücüsü GPU'yu bekliyor olabilir [varsayım].

**K-3 · 2,87M primitive'in kaynağı.** Görünür paylar ayrıştırılmadı [ölçülmedi]; ayrıştırma T-070'in işi. Elde olanlar:

| Kalem | Bilinen | Görünür pay |
|---|---|---|
| Bitki | Açık/kapalı farkı +428k primitive, +41 draw call, +1,0 ms (n=1) [ölçüldü]. LOD0: 102 örnek × 288–1.024 üçgen ≤ 104k; LOD0 ayrıca gölge geçişinde ≤ 104k. LOD1: 1.025 örnek × 80–300 üçgen ≤ 307k (frustum ayıklamasız üst sınır) [hesap]. Leke: 400 m'den yakın fragmanı gölgelendiricide atar ama üçgeni yine gönderir (`data/view/vegetation_view.json` blob notu) [okundu]. | Kademeler arası dağılım ölçülmedi |
| Bina, LOD0 yuvası (hero LOD1) | Bina başına ort. 436 üçgen (13,89M / 31.829); kitte 261 idi [ölçüldü stats]. Kademe kararı 1 km hücre MERKEZİNE göre verilir; merkez ≤ 1,5 km ise hücredeki binalar gerçek ~2,2 km'ye kadar 436 üçgenle çizilir (`building_lod.gd`) [okundu+hesap]. | Ölçülmedi. En büyük kalem olduğu tahmin ediliyor [varsayım] |
| Bina, LOD1 yuvası (hero PROXY, 1,3–3,0 km) | Ort. 41 üçgen; tüm hücrelerde toplam 1,317M [ölçüldü stats] | Ölçülmedi |
| HLOD1 | Tüm hücrelerde toplam 607k → 1,317M (×2,17; kit PROXY ≤ 14 üçgendi, hero PROXY 30–80) [ölçüldü stats]. Uzak düzlem 60 km ve eğim 12° olduğundan ufka kadar çizilir (`camera_math.gd` FAR_BASE_M) [okundu]. | Ölçülmedi; kaba tahmin 0,15–0,3M [hesap] |
| Gölge geçişi | Bina görsel düğümleri gölge düşürmez. Gölgeyi yalnız PROXY `S1` düğümü düşürür, hücre merkezine göre ≤ 700 m (`building_view.gd:286-321`). Güneş `SHADOW_ORTHOGONAL`; 60 m'de gölge menzili max(1,8 × 60, 500) = 500 m (`world_preview.gd:53-55,162,359`) [okundu]. Bitkide LOD0 gölge düşürür. `RENDER_TOTAL_PRIMITIVES_IN_FRAME` sayacının gölge geçişini içerdiği varsayılıyor [varsayım; engine-reference'ta yok; dolaylı destek: `building_view_config.gd:16` "+340k üçgen" notu]. | Ölçülmedi |
| Arazi, su, yol | Toplam: kara 199,6k, su 126,9k üçgen; T-062'de değişmedi [ölçüldü]. T-062 farkına katkısı 0. | Ölçülmedi |

- T-062'deki üçgen artışının tamamı bitkiden gelir. Bitkisiz sahne tabana çok yakındır (2,437M'ye karşı 2,494M).
- Ancak tabanın kendisi bütçenin 2,7 katıdır. Yapısal neden 1 km hücre-merkezli LOD'dur; ADR-0006 §3.1 bu sınırı bilerek kabul etmişti.

**K-4 · ADR-0006 §3.4 ret koşulu kanıtlanmadı.** Mesafe kısaltması hiç denenmedi; QA'da `--lod0-end`, `--lod1-end` ve `--veg-lod1` koşusu yok. Koşul büyük olasılıkla tetiklendi, ama kanıtı yok. Karar yine de TD'ye gelir; bu ADR o karardır.

**K-5 · ADR-0007'nin bu soruna katkısı ≈ 0 [hesap].**
Sokak bandında (< 300 m) K1 yok, ufuk görünür; `pitch_min(60 m)` ≈ 13° (bugün 12°); 50 m alt sınır preset'ten yakındır. 18 km tavan yalnız metro/core'u ucuzlatır; en kötü bakış (çekirdekte sokak) değişmez.

## Karar

1. **Bütçe gevşetilmez; tanımı netleşir.**
   - **Render kapısı** (ADR-0001): tick'siz kareler ya da sim duraklatılmış koşu; ort ≤ 8 ms, p95 ≤ 16,6 ms, draw call ≤ 400.
   - **Birleşik kapı** (render + sim): tüm karelerde p95 ≤ 16,6 ms. Ayrı iştir (T-074); üçgen kararlarıyla kapanmaz.
   - **Üçgen sınırı:** `RENDER_TOTAL_PRIMITIVES_IN_FRAME` (görünür + gölge; muhafazakâr) ≤ 900k. Bu bir tanı bütçesidir; bağlayıcı olan ms'dir.
   - **En kötü durum referansı:** `street:20200,18700` statik ve aynı noktada `--sweep`. `tools/smoke_playable.sh` serisine eklenir.
   - iPad bütçesi cihazda ölçülene kadar yazılmaz (ADR-0004).
2. **Önce ölç, sonra yapısal düzelt.** Mesafe sayılarıyla oynamak ürün çözümü değildir. Sıra §Plan'dadır. T-062 geri alınmaz: aşım tabanda da var; T-062'nin payı ort +1,4 ms.
3. **Yapısal düzeltme: yakın halkada bina kademesi örnek başına seçilir** (bitkideki `VegetationWindow` deseni).
   - Kameraya yakın hücrelerde LOD0 yuvası (hero LOD1) yalnız gerçek uzaklığı ≤ R olan örnekleri içerir; geri kalanı PROXY MMI tamponuna geçer.
   - Kamera `step_m` kadar hareket edince tamponlar yeniden doldurulur; iş kare tavanlıdır. Draw call sayısı değişmez.
   - R veridir (`data/view/` JSON). Başlangıç değeri, T-012'deki K8 eşiği 650 m + marjin; nihai değeri ADR-0006 §4 d* kuralı ve K8 ≤ %5 ölçümü belirler.
   - Sim etkilenmez (TEK-01); dünya verisi aynıdır, yalnız temsil değişir (TEK-03).
4. **Hero mesh seyreltme son çaredir.** ADR-0006 §2.5 ("aşım varlığı kırparak değil, mesafe ya da yoğunlukla çözülür") korunur.

## Alternatifler ve tahmini etki (kazançlar T-070'den önce yalnız tahmindir)

X = LOD0 yuvasının (hero LOD1) görünür üçgeni; değeri T-070 ölçer.

| Seçenek | Tahmini kazanç | Görsel risk | Karar |
|---|---|---|---|
| Örnek başına yakın halka, R ≈ 700 m (Karar 3) | Etkin alan oranı (0,7 / 1,5)² ≈ 0,22. Eklenen PROXY düşülünce ΔP ≈ −0,71·X; örneğin X = 1,5M ise ≈ −1,06M, ≈ −2,9 ms [hesap+varsayım] | Düşük-orta: geçiş bina başına ve doğru mesafede. K8 ölçülür, art-director onaylar | **ÖNERİLEN 1** (godot-engineer) |
| Hücre-merkezli mesafe kısaltma (`--lod0-end`) | Kalem ∝ r² | Yüksek: 1 km'lik blok sıçraması (T-012'de K8 %9,54 idi) | Yalnız T-070 ölçümü için; ürün çözümü değil |
| HLOD1 kaynağı = kutu (`hlod1_source=box`, A5 A/B) | Toplam 1,317M → ~0,32–0,38M (10–12 üçgenlik kutu). Görünür kazanç ~0,1–0,25M [hesap, kaba] | Düşük: yalnız > 2,85 km'de çatı silüeti | **ÖNERİLEN 2** (technical-artist + godot-engineer) |
| Lekeyi yakın hücrelerde CPU'da üretmemek (fragman atma yerine) | Yakın leke üçgeni kadar [ölçülmedi] | Yok: ekrandaki pikseller aynı kalır | **ÖNERİLEN 2** |
| Gölge caster menzilini güneş gölge menziline ve örnek başına halkaya bağlamak | ≤ ~0,1–0,2M [varsayım] | Düşük | T-070'teki gölge payına bağlı |
| Bitki LOD1 400 → 250 m | LOD1 halka alanı × 0,33 → ≈ −0,1…0,2M, ≈ −0,3 ms [hesap] | Orta: QA B-5'teki leke sıçraması yakına gelir | Koşullu, kullanıcıya (Q-020 B) |
| Bitki yoğunluğunu azaltmak | Yoğunlukla doğrusal | Yüksek: kullanıcının "ağaç yok" geri bildirimine ters | **Reddedildi** |
| Hücre başına üçgen tavanı / dinamik R | Tavanı garanti eder | Orta: yoğun bölgede geçiş mesafesi oynar | Karar 3'ün üstüne yalnız güvenlik sınırı |
| Sokak bandında ufuk pusu + uzak kesme (~6–8 km) | HLOD1, HLOD2 ve arazinin uzak payı [ölçülmedi; `--hlod1-end` ile kestirilir] | Gözle görünür: ufuk değişir | Kullanıcıya (Q-020 A) |
| Hero LOD1'e ikinci kademe / seyreltme | 436 → ~200 üçgen olursa kalem ≈ −%50 [hesap] | Yüksek: yeni türetilmiş varlık onay döngüsüne girer (D-005); ADR-0006 §2.5 değişir | Son çare |
| Kamera alt sınırı 50 m (ADR-0007) | ≈ 0 (K-5) | — | Kazanç yok |
| 900k'yı gevşetmek | — | — | **Reddedildi**: K-2 hesabı 900k ile tutarlı; ms bağlayıcı |

## Plan, sahipler ve kabul ölçütleri

Önerilen görev kimliklerini Studio Director atar.

1. **T-070 · Ayrıştırma ölçümü** (qa-engineer; probe eki godot-engineer). Görsel değişiklik yok.
   - Matris, çekirdek statik ve çekirdek sweep için: tam sahne / `--no-vegetation` / `--veg-no-blob` / `--veg-no-shadow` / `--bld-no-lod0` / `--bld-no-lod1` / `--bld-no-hlod1` / `--bld-no-hlod2` / `--hide=land`, `water`, `roads` (her biri ayrı) / `--no-shadows` / `--lod0-end=700` / `--veg-lod1=250` / 800x450 pencere (fragman duyarlılığı).
   - Koşu kuralı: her hücre için 3 koşu, sıraları araya girerek; medyan alınır.
   - Probe eki: `viewport_get_render_info` ile VISIBLE ve SHADOW primitive'leri ayrı yazılır [4.7 API'si doğrulanmadı]. Tick'siz istatistik raporun ana satırı olur.
   - Kabul: kalem başına primitive / ms tablosu; kalemlerin toplamı ölçülen değerle ±%10 içinde kapanır; K-4 ölçümle yanıtlanır.
2. **T-071 · Örnek başına yakın halka** (godot-engineer). Karar 3.
3. **T-072 · Ucuz kalemler** (technical-artist + godot-engineer): HLOD1 kutu A/B, leke yakın hücre dışlama, gölge caster menzili. Art-director kapısından geçer.
4. **T-073 (koşullu):** Q-020'de seçilen seçenek.
5. **T-074 · Birleşik kapı** (simulation-engineer + godot-engineer): tick işini karelere yayma, `hud_poll`'un 64 ms'lik aykırı değeri. Bu ADR'nin kapsamı dışında ama bağımlı.

**ADR kabul ölçütleri.** T-071 + T-072 sonrası ölçülür; koşullar: dev Mac, 1600x900, VSync kapalı, 3 koşu medyanı.
- Çekirdek statik: tick'siz ort ≤ 8,0 ms; tick'siz p95 ≤ 16,6 ms; primitive ≤ 900k; draw call ≤ 400.
- Çekirdek sweep: tick'siz p95 ≤ 16,6 ms. Yakın halka yeniden doldurma maliyeti ≤ 1 ms/kare (kare tavanlı). Sweep'te boş ya da geç kademe yok (yakalama ile).
- Gerileme yok: street:port, district:D1 ve ADR-0007 `core` medyanları bugünkü HEAD medyanından kötü değil.
- Sim: iki koşuda `state_hash` eşit; `src/sim` diff'i boş (TEK-01).
- Görsel: R geçişinde K8 ≤ %5. Çekirdekte ve D1'de 50 / 150 / 300 / 700 / 1.300 m yakalamaları alınır, art-director PASS verir, PNG'ler kullanıcıya gönderilir.
- Çekirdek statik ölçütleri tutmazsa Q-020 açılır.

## Kullanıcıya (Q-020 önerisi)

Yalnız T-071 + T-072 sonrası çekirdek hâlâ bütçe dışındaysa sorulur; her seçenek için gerçek PNG çifti gösterilir.

> "Yoğun çekirdekte sokak bakışı hâlâ ağır. Hangisinden vazgeçelim?"

- **A (Önerilen) · Uzak ufuk pusu:** sokak bakışında ~6–8 km ötesindeki şehir hafif pusa karışır. Yakın plan, ağaç sayısı ve ağaç ayrıntısı aynen kalır.
  - Gerekçe: "ağaç yok" geri bildirimine dokunmaz; B-5 leke sıçramasını büyütmez.
  - Not: Bu pus ADR-0007'deki kutu-kenarı pusundan ayrıdır ve yakın planı boğmaz. ADR-0007'nin reddettiği seçenek kenar sorunu için önerilmiş kameraya-uzaklık sisiydi. Design-director'a bilgi verilir.
- **B · Ağaçlar daha yakında sadeleşir:** tek tek ağaç ~400 m yerine ~250 m'ye kadar çizilir, ötesi yeşil lekedir. Ufuk net kalır; leke geçişi daha yakında görünür.

## Sonuçlar ve riskler

- **R1:** K-2 iki noktaya dayanıyor; 800x450 testi fragman bağımlılığı gösterirse üçgen indirimi ms'i beklenenden az düşürür, sıra değişir (overdraw, leke discard, atlas mip). **R2:** yakın halka CPU maliyeti ve hızlı sweep'te geç kalan kademe (önlem: kare tavanı + histerezis). **R3:** sayacın gölgeyi içerdiği doğrulanmadı (T-070 ayırır). **R4:** paylaşımlı makine gürültüsü ±%40 (araya giren 3 koşu + yük ortalaması zorunlu). **R5:** iPad ölçülmedi (PLT-06/07).
- **Yeniden açma:** T-070'te bina dışı bir kalem baskın çıkarsa; K8 ya da art-director R geçişini FAIL ederse; iPad ölçümü gelirse; M2 sonrası hero LOD0/insan/araç/donatı eklenirse (D-006; sokakta 80k pay, `design/library/README.md`).

## Kanıt

- **Okundu:** QA raporu; ADR-0001/0004/0006/0007; `perf/*.json` (çekirdek/port koşuları, `tick_correlation`, `scene_build_stats`), `perf_medians.tsv`; `building_lod.gd`, `building_view.gd:270-329`, `building_view_config.gd`; `vegetation_view.json`, `game_buildings.json`/`game_plants.json` üçgenleri; `world_preview.gd` gölge ayarları, `camera_math.gd` uzak düzlemi, `camera_presets.gd` (street 60 m / 12°); `playable.gd`/`world_preview.gd` ablasyon bayrakları.
- **Hesap:** K-2 doğrusu; alan oranları (0,22 / 0,33); HLOD1 kutu toplamı; bitki üst sınırları; `pitch_min(60)`.
- **Varsayım:** primitive sayacına gölgenin dahil olması; LOD0 yuvasının en büyük kalem olması; GPU'ya bağımlılık; X = 1,5M örneği; `viewport_get_render_info` ve Compatibility'de sis davranışı (engine-reference'ta yok).
- **Ölçülmedi:** kalemlerin görünür payları; mesafe kısaltmasının etkisi; GPU süresi; iPad.
