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

## Malzeme, LOD ve maliyet

- 30 GLB **aynı gerçek1024² RGBA Texture2D** kaynağını kullanır. Ayrı her GLB'de
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
- LOD1 dal/yaprak sayısını azaltır; proxy bütçesi ağaç40, çalı/çit24 üçgen.
  Sekiz palmiye dışı proxy, gerçek LOD0 ön/yan/üst albedo+alpha bake’inden
  üç dik kesişen karttır (6 üçgen). Palmiye proxy’leri40 üçgen kalır. Yakın proxy tanısı görünüm farkını bilerek açık eder; yakın kamera
  kullanım önerisi değildir.50/120m mesafeleri yalnız çalışma değeridir;
  otomatik LOD seçimi, rüzgâr veya dünya yerleşimi bu teslimde yoktur.

## Tekrarlanabilir kanıt

```
uv run --with pillow==11.3.0 python art/blender/vegetation/atlas.py
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python art/blender/vegetation/build.py -- --base-only
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python art/blender/vegetation/bake_proxies.py
uv run --with pillow==11.3.0 python art/blender/vegetation/pack_proxies.py
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python art/blender/vegetation/build.py -- --proxy-only
python3 tools/library/vegetation_catalog.py --write
python3 tools/library/vegetation_catalog.py --check
python3 tools/library/validate_catalog.py
tools/godot.sh --headless --path . --editor --import --quit
tools/godot.sh --headless --path . --script res://tools/library/check_vegetation_import.gd
uv run --with pillow==11.3.0 python tools/library/render_vegetation_sheets.py
python3 -m unittest discover -s tests/library -p 'test_*.py' -q
```

Kontak sayfaları `design/library/sheets/vegetation-hero/veg_hero_*_a.png`:
üstte ön/yan/üst, altta LOD0/LOD1/proxy. Alttaki karşılaştırma ayrı gerçek Godot
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

| Kimlik | Yükseklik m | X×Z m | LOD0 / LOD1 / proxy |
|---|---:|---:|---:|
| veg_hero_cypress_a | 10.362 | 2.89×2.75 | 316 / 300 / 6 |
| veg_hero_hedge_a | 1.197 | 4.80×1.25 | 360 / 100 / 6 |
| veg_hero_maquis_a | 2.493 | 3.58×2.11 | 288 / 80 / 6 |
| veg_hero_olive_open_a | 5.021 | 5.37×4.67 | 428 / 122 / 6 |
| veg_hero_olive_twisted_a | 5.121 | 6.01×4.72 | 552 / 152 / 6 |
| veg_hero_palm_date_a | 9.425 | 6.84×6.84 | 610 / 150 / 40 |
| veg_hero_palm_slender_a | 11.315 | 4.64×4.66 | 502 / 150 / 40 |
| veg_hero_pine_brutia_a | 12.152 | 7.78×7.10 | 608 / 286 / 6 |
| veg_hero_pine_stone_a | 12.792 | 9.66×8.74 | 544 / 272 / 6 |
| veg_hero_plane_a | 13.720 | 10.01×8.67 | 1024 / 288 / 6 |

30GLB +ortak PNG diskte **1.22MiB** (import cache hariç). Palmiye ölçüleri9.425/11.315m,11.5m çalışma üst sınırının içinde. Çit1.197m ile1.2m çalışma ölçüsüne yakın; değerler üreteç parametresinden değil dosyadan ölçüldü.

## Kaynak-türetilmiş düzeltme · bağımsız karar bekliyor

İlk QA FAIL sonrası sekiz palmiye dışı adayın tamamı gerçek LOD0 GLB’den
ışıksız Emission+Transparent /alpha0.45 ile ön, yan ve üst yönden512² bake edilir.
Işık/gölge bake edilmez; çalışma zamanında tekrar ışıklanan albedodur.
Her görünüm fiziksel bbox oranıyla kırpılır,112² içerik +8px kenarla128² tile’a
paketlenir.24 tile mevcut1024² atlasın y640..1023 boş alanındadır; üst512 satır
bark/yaprak/frond pikselleri bayt eşit korunur, yeni Texture2D/VRAM eklenmez.
`proxy_bakes.json` kaynak GLB hash/bbox/görünüm/tile RGBA hash’lerini tutar;
katalog `proxy_source` bu manifesti hash’ler. Üretim sırası önemlidir:
atlas → base-only → bake → pack → proxy-only → katalog kontrolü. Atlası tek
başına yeniden yapmak alt proxy tile’larını siler; zincir tamamlanmalıdır.

Servi LOD1 300 üçgenle kaynak sütunun daha sürekli yaprak örtüsünü korur;
LOD0 stilleri ve çalışma eşikleri50/120m değiştirilmedi. `nonpalms-150m-lod.png`
sekiz adayın tamamını aynı origin/kamera/ışıkta150m’de gösterir.
`cypress-50m-lod.png` sütun tanısı; `proxy-side-top-proof.png` çınar/çit yan ve
üst görünümüdür. Uygulayıcı bu üç gerçek sayfayı açtı: önceki ayrık beş yama
problemi azalır ve taç kütlesi geri gelir; **görsel PASS verilmedi**. Üç sabit
kartın açı/ışıklanma/paralaks farkları, özellikle üstten koyu çapraz çizgi ve
uzakta ton farkı görünür. Yakın proxy kareleri kullanım önerisi değildir.
Bağımsız QA/art bu sınırlamanın >120m çalışma eşiğinde kabulünü değerlendirecek.
Kullanıcı onayı ve gerçek şehir/iPad kabulü yok; T-058 başlatılmaz.

## Dar lab ölçümü ve doğrulama

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

## Katalogdan tekrar üretim

Katalogdaki her bitkinin `source.rebuild` komutu `bash art/blender/vegetation/rebuild.sh` olur. Ortak atlas nedeniyle tek türün atlasını sıfırlamak güvenli değildir; wrapper tüm batch için atlas → base-only → bake → pack → proxy-only → katalog güncelleme/doğrulama sırasını uygular. `IMARO_BLENDER_BIN` yalnız alternatif Blender binary yolu içindir; varsayılan yerel4.5.14 kurulumudur.

## A1 sanat FAIL sonrası sınırlı materyal adayı · inceleme bekliyor

`proxy_canopy.gdshader` / `proxy_canopy.tres` / `proxy_import.gd` gerçek asset
import zinciridir.8 palmiye dışı `.glb.import` bu EditorScenePostImport betiğini
kullanır; malzeme yalnız labda değiştirilmez. Kaynak GLB/atlas/bake dokunulmaz.
Normaller kart yüzünden değil ortak model-pozisyonu/bbox alanından, yukarı
0.25 bias ile türetilir; üç kartın kesişiminde aynı konum aynı normale sahiptir.
Lambert, roughness1, specular0, cull_disabled ve alpha-scissor0.45 korunur.
Sabit güneş veya emission/unshaded yoktur; canlı ışık/ambient ile tekrar ışıklanır.
Tek atlas/Texture2D ve üçgen bütçesi aynı kalır. Importta8 küçük materyal örneği
bbox parametresini taşır; yeni texture veya render pass eklenmez.

`shadows_disabled` alınan gölgeyi kapatır, gölge üretimini kapatmaz
([Godot4.7 spatial shader belgesi](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/spatial_shader.html)).
Mesh çift taraf gölge üretir: zemindeki alpha-silüet gölgesi kalır. Buna karşılık
proxy başka bina/ağaçların gölgesini de almaz; uzak canopy için gerçek bir
tradeoff’tur. AO0.55/AO_LIGHT_AFFECT0.75 çözümlenmeyen yaprak örtüşmesine kaba
malzeme yaklaşımıdır; Compatibility görüntüsünde gölge kaybını bütünüyle telafi
etmediği gözlendi. Kaynak albedo değiştirilmez veya önceden ışıklanmaz.

İlk gerçek150m çınar ön/yan/üst adayı koyu X’i kaldırır fakat kaynakta görülen
ince gölge/ışık dağılımından daha düzgün/açık kalır. **Sanat PASS’ı değildir.**
Bu ilk aday henüz bütün8 uzak/contact kanıtına geçirilmedi; eski son sayfalar
önceki materyali gösterir. İlk aday ham PNG’ler `artifacts/screenshots/captures/`
altında `20261027-120851-t057-a1-plane-calibrated-front.png` ve
`20261027-120855-t057-a1-plane-calibrated-top.png`; kaynak eşleri
`20261027-120725-t057-a1-plane-front-lod0.png`,
`20261027-120741-t057-a1-plane-top-lod0.png`.

Odaklı suite47 PASS (`artifacts/verify/t057/a1-tests.log`); gerçek runtime audit
30 mesh/tek texture/8 importlu shader policy/zemin gölgesi ayarı PASS
(`a1-runtime.log`). İki yeni negatif test shader içeriği drift’i ve gerçek
GLB import assignment kaldırılmasını reddeder. Materyal/helper/import SHA’ları
katalog `proxy_runtime` içindedir. GDScript lint temiz (`a1-lint.log`).
