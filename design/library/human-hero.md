# İnsan stil seçenekleri — T-059 · 2026-10-27

**6 öneri, kullanıcı onayı değil; yalnız kütüphane/lab (approval: proposed).** Hiçbir stil seçilmiş sayılmaz (Q-018 stilizasyon, kimlik/giyim,
mevsim ve Q-005/Q-010 kullanıcıdadır). Oyuna/manifest'e bağlama yok. Kaynak: `production/tasks/T-059.md`, `design/library/templates-v0.md` §a;
REQ VIS-01/02/03/05/07, WLD-01, TEK-03. Katalog: 81 kit + 10 bitki + 8 donatı + 6 insan = 105 kayıt (99 eski kayıt bayt eşit).

## Seçenekler ve modeller (ölçüm GLB'den; g × d × y m, üçgen LOD0 / LOD1)

| Kimlik | g × d × y m | Üçgen | sha8 LOD0 |
|---|---|---|---|
| `hum_hero_block_broad_a` | 0,614 × 0,3 × 1,75 | 198 / 98 | 34143be9 |
| `hum_hero_block_neutral_a` | 0,522 × 0,275 × 1,75 | 198 / 98 | 4c0a6f05 |
| `hum_hero_facet_broad_a` | 0,614 × 0,305 × 1,75 | 654 / 98 | 324c39fc |
| `hum_hero_facet_neutral_a` | 0,522 × 0,285 × 1,75 | 654 / 98 | 3bba6013 |
| `hum_hero_pawn_broad_a` | 0,564 × 0,28 × 1,75 | 122 / 66 | 4543aa96 |
| `hum_hero_pawn_neutral_a` | 0,464 × 0,23 × 1,75 | 122 / 66 | 398b91e5 |

- **A piyon** (`pawn`): uzuvsuz gövde prizması (ayakkabı bandı, pantolon, gömlek, omuz rafı), boyun, kutu baş, saç kütlesi. Şablondaki "uzuvsuz" tarife
  uyar; kol/bacak/el/ayak **yoktur** (anatomi yalnız baş/boyun/omuz/gövde düzeyinde okunur). Şablon 24–40 üçgen diyordu; çalışma modeli 122 (8 kenarlı halkalar).
- **B blok figür** (`block`): daralan gövde, 2 bacak, 2 kol, blok el (eldiven biçimli), kama ayak, kutu baş + saç. Şablon el/ayak saymıyordu; görev anatomi istediği için eklendi (198).
- **C faset figür** (`facet`): 8 kenarlı eklemli uzuvlar (diz/dirsek/bilek), ayakkabı + taban, manşet bandı, yaka bandı, başparmak, faset baş ve saç (654).
- Oranlar: `neutral` omuz ≈ 0,46 m (hum_adult_m_a 0,48 ile hum_adult_f_a 0,42 arası **çalışma değeri**), `broad` ≈ 0,56 m (hum_adult_broad_a; şablon boyu 1,74 → eşit karşılaştırma için 1,75, çalışma değeri).
  Kol açıklığı nedeniyle ölçülen toplam genişlik B/C'de nötr 0,52, geniş 0,61 m (A: 0,46 / 0,56).
- Aynı duruş (dik, kollar gövdeden ≈ 3° açık, avuç içe), aynı çalışma kıyafeti (düz gömlek/ceket CL7, pantolon CL4, ayakkabı CL15, ten SK2, saç HR2, taban CL6, manşet CL2, yaka CL1).
  Desen, şerit, yazı, logo, yüz detayı, kültürel/dini giyim, üniforma, adlı karakter, mevsim kararı **yoktur**.
- Mesafe (çalışma, `working-model-not-integrated`): LOD0 < 30 m, LOD1 < 120 m, sonrası cull; uzak proxy yok. 120 m'de 1,75 m figür ≈ 17 px (README §5.1 hesabı; ölçüm değil).

## Üretim
`art/blender/human/` — `atlas.py` (1024×512 opak RGB, 8 düz 256 px karo + ince grenaj; bant/degrade yok), `kit.py` (düz gölgeli çokgen, UV karonun merkezi %30'una),
`assets.py` (3 stil × 2 oran), `build.py` (Blender `--factory-startup`; GLB, harici `human_atlas.png`, `mat_human_atlas`, roughness 1, specular 0, opak, tek yüz),
`set_import.py` (generate_lods=false, mipmaps), `rebuild.sh`. Katalog `tools/library/human_catalog.py` (`source.kind: hero_human`, `category: human`;
LOD1 zarfı LOD0 sınırı içinde olmalı, yasak içerik tag/etiket denetimi). Lab `assets/hero/human/human_lab.tscn`.

## Doğrulama (bu oturumda koşuldu)
- `bash art/blender/human/rebuild.sh` `tools/library/human_determinism.py` ile iki kez GERÇEKTEN çalıştı: 12 GLB + atlas + layout + katalog = 15 dosya sha256 eşit (`artifacts/verify/t059/determinism.json`).
- Koruma: `artifacts/verify/t059/preservation.json` — 99 eski kayıt eşit, 234 bina/bitki/zemin/donatı/model dosyası hash'i değişmedi (`tools/library/human_preservation.py`).
- `python3 -m unittest discover -s tests/library`: 96 test OK (yeni `test_human_catalog.py`; T-058 testinde yalnız sayım sabitleri 91+8 → insan eklenince geçerli olacak şekilde gevşetildi).
- `human_catalog.py --check`, `furniture_catalog.py --check`, `vegetation_catalog.py --check`, `hero_lods.py --check`, `build_catalog.py --check`, `validate_catalog.py` (105 kayıt, 0 hata); `check_human_import.gd` gerçek Godot: `HUMAN_IMPORT_OK meshes=12 …`.
- `tools/verify.sh` KOŞULMADI (görev gereği).

## Kendi görsel gözlemim (gerçek Godot PNG'leri açıldı; art-director değerlendirmesi değildir)
Kanıt: `design/library/sheets/human-hero/` (6 kontak sayfası, `style-compare.png`, `context-compare-*.png`, `context-street.png`, `context-scale.png`, `index.json`).
- İlk örnek (B nötr) çoğaltmadan önce açıldı: insan gibi okunuyor; ilk kare hatalı bulunanlar düzeltildi (kol açıklığı fazlaydı: 0,11 → 0,05; C ceket eteğindeki fazla açılan etek halkası kaldırıldı; karşılaştırma etiketleri çakışıyordu).
- B ve C sokakta (hero bina, bank, bollard yanında) gerçek ölçekte makul: figür zemin kat kapısının ≈ 3/4'ü, bank oturağı bele göre doğru. A piyon yakın planda bacaksız sütun gibi okunur ("oyun taşı" riski, templates-v0 uyarısı doğrulandı); 60 m'de (`far_all` kırpımı) A ayırt edilir (bacak arası yok), B ve C birbirinden ayırt edilemez (C'nin LOD1'i B ile aynı yapı).
- **Kıyas adilliği uyarısı (kostüm):** C, A ve B'de olmayan ek kostüm detayı taşır (beyaz yaka, manşet, ceket eteği, ayakkabı tabanı). A/B/C kıyası bu yüzden yalnız stili (piyon / blok / faset uzuv) değil, kostüm detayını da birlikte ölçer; C'nin "daha zengin" okunması kısmen kostümdendir ve stilden ayrı değerlendirilmelidir.
- C 12 m'de B'den belirgin daha zengin (yaka, manşet, ayakkabı tabanı). Yüz bilinçli boş; "mankene" benzer sert bir okuma var.
- **C ceket eteği kusuru, K1 sonrası gerçek kareyle (`hem_facet_*_{front,side,back}.png`, 6x):** İki düzeltme uygulandı: (1) `facet()` gövde halkaları z 0,80/0,90'da `hp+0,02` (genişlik); bu yalnız broad'ı kapattı, nötrde çentik kaldı. (2) Yeni kök neden derinlikti (bacak üst halkası sekizgen pahta ceketten ≈ 1 cm taşıyordu): aynı iki halkada `hd+0,02`. Sonuç: nötr ve geniş C'nin ön, yan ve arka 6x kırpımlarında mavi çentik/iğne deliği GÖRÜNMÜYOR; etek kenarı temiz. Etek kusuru kapandı (yalnız bu altı kırpımda gözle doğrulandı; hareket/animasyonda test edilmedi). Yalnız iki C LOD0 GLB değişti.
- 3/4 ve yan kıyas kareleri düzeltildi: altı figür kamera eksenine dik sırada, kameraya eşit uzaklıkta (önceki 3/4 karede C ≈ 1,45x büyük görünüyordu; adil değildi). `context-compare-side.png` artık altı figürü ayrı gösteriyor.
- Hero bina cephesi dokusu figürlerden belirgin zengin: figürler düz renkli (dokusuz), bu fark gerçek ve kalite eşitsizliği olarak raporlanır.
- LOD1 (B/C ortak yapı, 98 üçgen): ön görünümde LOD0 zarfına oturur; C'nin LOD1'i B'den ayırt edilmez (aynı yapı, bütçe 100).

## Riskler / test edilmedi
Gerçek kalabalık, çok figürlü draw call, hareket/yürüme, LOD geçiş pop'u, hedef cihaz, gece, kapalı hava; renk ve oran kararları Q-018. Sanat kapısı ve bağımsız QA ayrıca gerekir.
