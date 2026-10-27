> **SAFE PAUSE / WIP (2026-10-27):** Kullanıcı hemen durdurdu. Aşağıdaki raporun sayı/bulgu/görselleri ilk uygulama içindir; son impostor ve source guard düzeltmesini bütünüyle yansıtmaz. Yeni kanıt görselleri üretilmiş ama incelenmemiştir; son deterministik tekrar, bağımsız yeniden QA/sanat ve full yapılmadı. Bu bir kabul edilmiş teslim değildir. Devam noktası: production/STATE.md.

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
eklendi. Son kanıtlar bu düzeltmeleri içerir.

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
  Geniş ağaç proxy'lerinde5 taç merkezi, çapraz bağlı dal şeritleri ve gövde
  kullanılır. Yakın proxy tanısı görünüm farkını bilerek açık eder; yakın kamera
  kullanım önerisi değildir.50/120m mesafeleri yalnız çalışma değeridir;
  otomatik LOD seçimi, rüzgâr veya dünya yerleşimi bu teslimde yoktur.

## Tekrarlanabilir kanıt

```
uv run --with pillow==11.3.0 python art/blender/vegetation/atlas.py
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python art/blender/vegetation/build.py
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
| veg_hero_cypress_a | 10.362 | 2.89×2.75 | 316 / 76 / 22 |
| veg_hero_hedge_a | 1.197 | 4.80×1.25 | 360 / 100 / 14 |
| veg_hero_maquis_a | 2.493 | 3.58×2.11 | 288 / 80 / 14 |
| veg_hero_olive_open_a | 5.021 | 5.37×4.67 | 428 / 122 / 30 |
| veg_hero_olive_twisted_a | 5.121 | 6.01×4.72 | 552 / 152 / 36 |
| veg_hero_palm_date_a | 9.425 | 6.84×6.84 | 610 / 150 / 40 |
| veg_hero_palm_slender_a | 11.315 | 4.64×4.66 | 502 / 150 / 40 |
| veg_hero_pine_brutia_a | 12.152 | 7.78×7.10 | 608 / 286 / 36 |
| veg_hero_pine_stone_a | 12.792 | 9.66×8.74 | 544 / 272 / 36 |
| veg_hero_plane_a | 13.720 | 10.01×8.67 | 1024 / 288 / 36 |

30GLB +ortak PNG diskte **0.82MiB** (import cache hariç). Palmiye ölçüleri9.425/11.315m,11.5m çalışma üst sınırının içinde. Çit1.197m ile1.2m çalışma ölçüsüne yakın; değerler üreteç parametresinden değil dosyadan ölçüldü.

## Açık görsel sorun · uzak proxy henüz onaylı değil

**Görsel PASS verilmedi.** `broad-trees-150m-lod.png`, çınar/kızılçam/fıstık
çamının aynı origin ve kameradan150m mesafede LOD0/LOD1/proxy karşılaştırmasıdır.
Proxy için yazılan >120m çalışma eşiğinde bile taç kütlesi kayboluyor: çınar
beş ayrık yaprak yamasına, fıstık çamı seyrek dallı bir direğe yaklaşıyor.
Dal bağlantısının teknik olarak düzeltilmesi, taç silüetinin korunduğu kanıtı
değildir. Yakın kontaklar ve bu uzak kare açıkça bunu gösteriyor.

LOD0 yönü (özellikle yuvarlak çınar vs şemsiye çam ayrımı) koordinatör tarafından
olumlu değerlendirildi; bu, yeni varlıklara kullanıcı onayı değildir. Teknik
drift/bütçe testlerinin geçmesi de proxy sanat kapısını kapatmaz. Bağımsız
QA/art incelemesi beklenir. Muhtemel sınırlı çözüm, aynı bütçede kaynak LOD0'dan
türetilmiş taç impostor/cross-card proxy'sidir; bu teslimde uygulanmış sayılmaz.
Kullanıcının güvenli duraklama isteği nedeniyle yeni kategori/T-058 başlatılmaz.

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

- Odaklı Python:42 test; katalog91 kayıt /0 hata /0 uyarı; building21 zincir
  kontrolü ve genel katalog idempotence kontrolü de geçer.
- Godot import:30 bitki mesh'i aynı tek Texture2D; çift taraf/MASK0.45/mipmap
  açık; gerçek ithal üçgenler katalogla aynı. Eski42 bina LOD import denetimi
  geçer. Kaynak türü ayrımı ve negatif geometri/doku drift testleri vardır.
- Son tam üretim tekrarı:30GLB +PNG +layout,32/32 dosya bayt/hash eşit
  (`artifacts/verify/t057/pause-delivery-determinism.json`).
- Bütün81 eski katalog kaydı ve mevcut GLB hash'leri değişmedi. Yeni10 kayıt
  proposed; oyun yükleyicisi, manifest, src/scenes ve foundation değişmedi.
-17 yayın PNG'si:10 kontak,4 bağlam,2 AA-off tanı,1 adet 150m LOD karşılaştırması.
  Uygulayıcı10 kontağın tamamını, sokak/yamaç, AA-off ve150m karelerini açtı.
- GDScript yeni lab/audit dosyaları ayrıca lint edildi. Tam quick/full bu
  üretim adımlarında çalıştırılmadı; son teslim kapısı bağımsız inceleme sonrası
  bir kez çalışacak. Görev done değil; proxy sorunu ve bağımsız karar açık.
