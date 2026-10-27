# Bitki HERO kütüphanesi — T-057 · 2026-10-27

**10 öneri, kullanıcı onayı değil; yalnız kütüphane/lab.** Q-018 palmiye türü,
mevsim ve çiçek kararları açık. Yerleşim oranı, bölge dağılımı, üretim mekaniği
veya dünyaya entegrasyon eklenmedi. Eski T-051 stash'i geri yüklenmedi; mevcut81
katalog kaydı ve GLB hash'leri korunur. Kaynak: `production/tasks/T-057.md`,
`design/library/templates-v0.md` §d; REQ VIS-01..05, WLD-01, TEK-03.

## Üretim ve görünüm

`art/blender/vegetation/atlas.py`: sabit seed ile çizilmiş özgün RGBA bark,
geniş yaprak kümesi, gümüşi zeytin yaprakları, iğne/tüy yaprak ve kıvrık palmiye
frond dokuları. Haricî/AI doku veya gerçek marka yok. `build.py` metre ölçekli
parametrik gövde/dal tüpleri ile3B yönlendirilmiş yaprak kümelerini ve segmentli
eğilen frondları kurar. Tek küre/koni veya yeşil kutu ağaç yerine dallanma,
asimetri, taç boşlukları ve kesilmiş gerçek yaprak şekilleri kullanılır.

Çınar, daha derin ve yuvarlak asimetrik taç ile şemsiye taçlı fıstık çamından
ayrılır. Zeytinin iki farklı taç dağılımı vardır. İki palmiye farklı gövde/taç
oranı taşır; kalın gövdeli adayda geniş sarkık frondlara ek yükselen merkez
sürgünleri bulunur. Bunlar botanik doğruluk iddiası değil, oyun stilinde tür
önerileridir. Yakın detayda zeytin yaprak kümelerinin kart düzlemleri ve iri
soyutlaması okunur; tek tek yaprak geometrisi gibi sunulmaz.

İlk zeytin/palmiye prototipleri gerçek Godot görüntüsüyle incelendi. İlk başarılı
prototipte taç seyrek, palmiye çizgileri fazla ince/parlaktı. Gerçek yaprak
kaplama alanı ve taç katmanları artırıldı, ton sakinleştirildi, mipmap/coverage
konfigürasyonu açık hale getirildi; sonra10'lu dalgaya geçildi. İlk başarısız gri
capture (GDScript tip çıkarımı) kanıt olarak kullanılmadı. Sonraki çınar/pine
incelemesinde yakın proxy'deki kopuk taç parçaları ve benzer şemsiye silüeti
reddedildi: çınar yuvarlaklaştırıldı,3 geniş ağaç proxy'sine bağlı dal şeritleri
eklendi. Bu ilk temsil bağımsız QA tur1’de reddedildi; son kaynak-türetilmiş temsil aşağıdadır.

## Zincir · Teknik karar 5 (2026-10-27) · çalışma modeli, oyuna bağlı değil

Palmiye dışı 8 tür: **LOD0 → LOD1** (tekil ağaç başına uzak proxy yok). Uzak temsil
ayrı görevde hücre başına birleşik ağaç lekesi/HLOD'dur (T-057 dışı). Palmiyeler:
LOD0 → LOD1 → 40 üçgenlik PROXY (sanat kapısı reddetmedi; uzak kabulü ayrıca
kanıtlanmış değil). Çalışma eşikleri **LOD0 <120 m, LOD1 <400 m**: teknik çalışma
tercihi, ölçülmüş cihaz sonucu değil, `working-model-not-integrated`. Kullanıcının
mahalle labında 900 m'de "iyi görünüyor" yorumu bir yön sinyalidir, estetik onay değil.
Tüm bitki `.glb.import` dosyaları `meshes/generate_lods=false`; post-import betiği ve
özel shader yok (katalog `import_policy` + `validate_chain` + Godot audit kilitler).
Eski çapraz kart proxy'leri (GLB/import/`proxy_canopy.*`/`proxy_import.gd`/
`proxy_bakes.json`) kaldırıldı; atlasın y640–1023 tile bölgesi **ölü piksel olarak
bayt-eşit** kalır (`assets/hero/vegetation/atlas_regions.json` hash'i; temizleme ayrı,
drift testli bir adımdır). `atlas_layout.json` eski `proxy_*` bölgelerini ölü rezerv
olarak listelemeye devam eder (hash'i değişmesin diye).

## Malzeme, LOD ve maliyet

- 22 GLB **aynı gerçek1024² RGBA Texture2D** kaynağını kullanır. Ayrı her GLB'de
  atlas PNG yükü gömülü tutulmaz; yetim PNG bufferView/BIN verisi ayıklanır.
- Mat pürüzlülük1, specular0; yaprak kartları çift taraflı **MASK0.45**. BLEND
  sıralama yolu kullanılmaz. Kartların birbirini/gölgeyi örtmesi yine gerçek
  fill-rate/overdraw maliyetidir; düşük üçgen sayısı ucuz GPU garantisi değildir.
- PNG import: mipmap açık, alpha-border düzeltmesi açık, kayıplı alfa yok.
  RGBA8 +tam mip zinciri hesabıyla tek atlas yaklaşık **5.33MiB**; bu teorik
  atlas belleği, sürücü VRAM tahmini veya gerçek kent toplamı değildir.
- Varsayılan lab **4×MSAA +alpha-to-coverage**, `--aa=off` tanısı MSAA/coverage
  olmadan alpha-scissor gösterir. Bu ayarlar yalnız labdadır; oyun profili
  değiştirilmedi. Düşük AA'da ince kenar titreşimi ve uzakta yaprak kaplama
  kaybı riski sürer; dokunmatik/cihaz/iPad kalitesi doğrulanmadı.
- LOD1 dal/yaprak sayısını azaltır; bütçeler: ağaç LOD0 1800 / LOD1 300 (palmiye
  PROXY 40), çalı/çit 600 / 120. Palmiye proxy'leri 40 üçgen kalır. Mesafeler yalnız
  çalışma değeridir; otomatik LOD seçimi, rüzgâr veya dünya yerleşimi bu teslimde yoktur.

## Tekrarlanabilir kanıt

```
bash art/blender/vegetation/rebuild.sh   # atlas -> base-only -> palmiye proxy -> katalog yaz -> validate
python3 tools/library/vegetation_catalog.py --check
python3 tools/library/validate_catalog.py
tools/godot.sh --headless --path . --editor --import --quit
tools/godot.sh --headless --path . --script res://tools/library/check_vegetation_import.gd
uv run --with pillow==11.3.0 python tools/library/render_vegetation_sheets.py [tür ...]
python3 -m unittest discover -s tests/library -p 'test_*.py' -q
```

Kontak sayfaları `design/library/sheets/vegetation-hero/veg_hero_*_a.png`:
üstte ön/yan/üst, altta LOD0/LOD1 (yalnız palmiyelerde ek olarak proxy). Alttaki karşılaştırma ayrı gerçek Godot
çalıştırmalarında **aynı origin/kamera/ışık** ile alınır; tüm seviyeler aynı LOD0
bbox'ıyla çerçevelenir; seviyeler tek tek normalize edilmez. Tür sayfaları kendi
LOD0 ölçüsüne göre çerçevelenir; `context-lineup.png` türler arasında sabit
ortografik ölçeği ve1.75m figürü gösterir. Sayfa başlığındaki metre/üçgen verisi
GLB'den ölçülür. `index.json` gerçek ham capture yollarını tutar.

`context-true.png` zeytin/palmiye +değişmeyen hero apartmanını;
`context-street.png` meydan/sokak ölçeğini; `context-slope.png` basit8° laboratuvar
yamacında çam/zeytin/servi +değişmeyen hero evi gösterir. T-055 avlu/kuru ot
malzemeleri aynen kullanılır. Bu laboratuvar yerleşimi oyun coğrafyası veya
onaylı gerçek şehir dağılımı değildir. `*-scissor-no-msaa.png` tanıları AA
bağımlılığını gizlemez; başlıkta açıkça etiketlidir.

Son ölçüm tablosu, doğrulama özeti ve dar lab maliyeti aşağıdadır. Gerçek54k
binalı kent, yoğun ağaç grupları ve iPad bütçesi geçti sonucu çıkarılmaz.

## Gerçek GLB ölçümleri

| Kimlik | Yükseklik m | X×Z m | LOD0 / LOD1 / proxy (yalnız palmiye) |
|---|---:|---:|---:|
| veg_hero_cypress_a | 10.362 | 2.89×2.75 | 316 / 300 |
| veg_hero_hedge_a | 1.197 | 4.80×1.25 | 360 / 100 |
| veg_hero_maquis_a | 2.493 | 3.58×2.11 | 288 / 80 |
| veg_hero_olive_open_a | 5.021 | 5.37×4.67 | 428 / 122 |
| veg_hero_olive_twisted_a | 5.121 | 6.01×4.72 | 552 / 152 |
| veg_hero_palm_date_a | 9.425 | 6.84×6.84 | 610 / 150 / 40 |
| veg_hero_palm_slender_a | 11.315 | 4.64×4.66 | 502 / 150 / 40 |
| veg_hero_pine_brutia_a | 12.152 | 7.78×7.10 | 608 / 286 |
| veg_hero_pine_stone_a | 12.792 | 9.66×8.74 | 544 / 272 |
| veg_hero_plane_a | 13.720 | 10.01×8.67 | 1024 / 288 |

22 GLB +ortak PNG diskte **1.20MiB** (import cache hariç). Palmiye ölçüleri9.425/11.315m,11.5m çalışma üst sınırının içinde. Çit1.197m ile1.2m çalışma ölçüsüne yakın; değerler üreteç parametresinden değil dosyadan ölçüldü.

## Emekli: kaynak-türetilmiş çapraz kart proxy (Karar 5 ile kaldırıldı)

Palmiye dışı sekiz türün 3 çapraz kartlı (6 üçgen) kaynak-türetilmiş proxy'si
ve onun A1 materyal/post-import adayı (`proxy_canopy.*`, `proxy_import.gd`) sanat
kapısında kabul görmedi ve **kaldırıldı**. Tarihî başarısızlık kanıtı olan eski
tanı sayfaları `design/library/sheets/vegetation-hero/retired-proxy/` altına taşındı
(`nonpalms-150m-lod`, `broad-trees-150m-lod`, `cypress-50m-lod`,
`proxy-side-top-proof`); **güncel zinciri göstermezler**. Atlasın alt tile bölgesi
ölü pikseldir. Kullanıcı onayı ve gerçek şehir/iPad kabulü yok; T-058 başlatılmaz.

## Dar lab ölçümü ve doğrulama

**Not:** aşağıdaki lab ölçümü ve "Yeniden devam sonrası" maddeleri Karar 5 öncesi
30 GLB / proxy'li zincire aittir; tarihî kayıt olarak kalır, güncel durum için
"Karar 5 doğrulaması" bölümüne bakın.

Godot4.7.2 Compatibility/OpenGL, AMD Radeon Pro560X;1600×900; VSync kapalı;
60 ısınma +180 örnek. Street lab:6 bitki +değişmeyen hero bina, zemin ve figür.
Bunlar kare aralıklarıdır; GPU timer veya yoğun şehir karşılaştırması değildir.

| Lab AA | Ort.ms | P95ms | Draw call | Renderer primitive | Texture monitor MiB |
|---|---:|---:|---:|---:|---:|
| coverage | 4.79 | 5.00 | 24 | 34158 | 65.58 |
| off | 2.71 | 2.78 | 24 | 34146 | 21.64 |

Texture monitor tüm lab ve render hedeflerini içerir; farkı yalnız atlas
belleği diye yorumlamayın. MSAA'nın örnek/render hedefi maliyeti de vardır.
Sık ağaçlık, gerçek şehir, iPad ve düşük-AA uzak görünüm onayı kanıtlanmadı.

- Yeniden devam sonrası taze odaklı Python: **45 test PASS**
  (`artifacts/verify/t057/resume-focused.log`); None/string/list source için
  genel doğrulayıcı ve doğrudan bitki doğrulayıcısı istisna yerine tanı döndürür.
  Gerçek proxy GLB UV/bbox/6tri, bozuk tile pikseli ve drift negatif testleri var.
- Katalog91/0 hata/0 uyarı; vegetation/hero/build katalog check temiz.
  Gerçek son Godot import:30 mesh, tek Texture2D, MASK/çift taraf/mipmap PASS
  (`resume-import.log`, `resume-runtime-import.log`).
- Tam üretim tekrarı **33/33 bayt/hash eşit**:30 GLB +PNG +layout +proxy manifest.
  `artifacts/verify/t057/resume-determinism.json`; tüm komutlar/hash’ler kayıtta.
- Tile audit:8 kaynak/24 görünüm; üst512RGBA korunumu, kaynak/tile hash ve alfa
  kaplama kontrolü PASS. Önceki32-dosya sonucu son temsil kanıtı olarak kullanılmaz.
- fe89e29 ile81 eski kayıt tam eşit;67 GLB +14 PNG hash’i korunur.10 bitki LOD0
  hash’i düzeltme öncesiyle aynı (`resume-preservation.json`).
-20 yayın PNG’si:10 güncel kontak,4 bağlam,2 AA-off tanı, geniş3 ve bütün8 aday
  150m karşılaştırması, servi50m ve yan/üst tanı. `index.json` güncel6tri proxy
  ve300tri servi LOD1 ölçümlerini/ham capture yollarını içerir; son ek tanı yolları
  `diagnostics` alanındadır. Eski36tri kontaklar son kanıt diye bırakılmadı.
- Yukarıdaki dar street ölçümü önceki LOD0 bağlamındandır; bu düzeltmede yeniden
  ölçülmedi. LOD0 ve üst atlas pikselleri aynı; far-proxy performans ölçümü değildir.
- Yeni broad quick/full çalıştırılmadı. Son durum: **bağımsız yeniden QA/art ve
  ardından full bekliyor; görev done değil.**

## Karar 5 doğrulaması (2026-10-27)

Kanıt: `artifacts/verify/t057/karar5-*`. 22 GLB, atlas ve layout iki tam
`rebuild.sh` koşusunda ve Karar 5 öncesine göre bayt-eşit (`karar5-determinism.json`);
korunanlar `karar5-preservation.json`. Kontak sayfaları yalnız 8 palmiye dışı tür için
yeniden üretildi (LOD0/LOD1, gerçek Godot capture); iki palmiye sayfası, 4 bağlam ve
2 AA-off tanı LOD0/palmiye proxy'sine ait olup değişmedi, yeniden üretilmedi.
Bağımsız art-director incelemesi ve hareketli LOD geçişi **yok**.

## Katalogdan tekrar üretim

Katalogdaki her bitkinin `source.rebuild` komutu `bash art/blender/vegetation/rebuild.sh` olur: atlas (üst 512 satır yeniden, alt satırlar bayt-eşit taşınır) → base-only → palmiye proxy → katalog yazma/doğrulama. `IMARO_BLENDER_BIN` yalnız alternatif Blender binary yolu içindir; varsayılan yerel 4.5.14. Blender betik hatasında dışarıya 0 döndürdüğü için wrapper `--python-exit-code 1` kullanır.

## Emekli: A1 sanat FAIL sonrası materyal adayı

`proxy_canopy.gdshader` / `proxy_canopy.tres` / `proxy_import.gd` (konum-alanı
normali, AO 0.55 / AO_LIGHT_AFFECT 0.75) sanat kabulü almadı ve Karar 5 ile
kaldırıldı. Ayrıntı yalnız git geçmişinde ve `production/qa/T-057-*.md` içinde.
