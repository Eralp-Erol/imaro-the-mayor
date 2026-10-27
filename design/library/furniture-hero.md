# Sokak donatısı HERO kütüphanesi — T-058 · 2026-10-27

**8 öneri, kullanıcı onayı değil; yalnız kütüphane/lab (approval: proposed).** Q-018 (donatı/metal rengi, kiosk,
ışık) kullanıcıdadır; renkler ve ölçüler *teknik çalışma değeridir*. Oyuna/manifest'e bağlama, yerleşim, gece ışığı,
logo/kurum rengi/reklam yazısı yoktur. Kaynak: `production/tasks/T-058.md`, `design/library/templates-v0.md` §f;
REQ VIS-01/02/03/05/07, WLD-01, TEK-03. Katalog: 81 kit + 10 bitki (T-057) + 8 donatı = 99 kayıt.

## Varlıklar (ölçüm GLB'den; LOD0/LOD1 üçgen, çalışma mesafeleri)

| Kimlik | g × d × y m | Üçgen LOD0/LOD1 | Mesafe m (LOD0/LOD1 sonrası cull) | sha8 | Şablon |
|---|---|---|---|---|---|
| `fur_hero_bench_a` | 1,80 × 0,57 × 0,80 | 600 / 144 | 40 / 150 | 53d01613 | fur_bench_a |
| `fur_hero_bin_a` | 0,50 × 0,50 × 0,90 | 256 / 90 | 40 / 150 | 695088d9 | fur_bin_a |
| `fur_hero_lamp_street_a` | 1,67 × 0,28 × 8,00 | 390 / 94 | 80 / 300 | cc306260 | fur_lamp_street_a |
| `fur_hero_bollard_a` | 0,20 × 0,20 × 0,87 | 138 / 44 | 40 / 150 | 673bbbc8 | fur_bollard_a |
| `fur_hero_bike_rack_a` | 0,81 × 1,91 × 0,86 | 552 / 120 | 40 / 150 | c8d9c013 | yok (çalışma değeri) |
| `fur_hero_bus_stop_a` | 5,00 × 1,60 × 2,60 | 652 / 158 | 60 / 200 | d90a64a0 | fur_bus_stop_a |
| `fur_hero_planter_a` | 1,20 × 1,20 × 1,34 | 304 / 124 | 40 / 150 | 5a3244ab | fur_planter_a |
| `fur_hero_kiosk_a` | 2,40 × 2,00 × 2,68 | 486 / 142 | 60 / 200 | 2f923ab0 | fur_kiosk_a |

Bütçe LOD0 ≤ 1600, LOD1 ≤ 240 (üreteç ve doğrulayıcı reddeder). Ölçü §f şablon değeridir; çalışma değerleri:
bisiklet demiri (şablonda yok: 3 ters-U, 0,70 × 0,85, 0,9 m aralık), saksı toplam yüksekliği 1,34 (kap 0,70 + çalı;
şablon "beton + çalı", kullanıcı isteği taş/toprak olduğundan taş), sokak direği kolu ≈ 1,5 (başlık dahil 1,53),
çalışma kesme mesafeleri (`working-model-not-integrated`; küçük sınıf 40/150, kiosk/durak 60/200, direk 80/300).
Uzak proxy yoktur: LOD1'den sonra cull. 8 m direk 300 m'de ≈ 30 px; cull'da fark edilir pop riski vardır (aşağıda).

## Üretim

`art/blender/furniture/atlas.py` — tek opak RGB 1024² mat atlas (`assets/hero/furniture/furniture_atlas.png`, 16 doku:
ahşap ×2, koyu/yeşil-gri metal, cam, taş, beton, toprak, büfe yeşili, petrol, kepenk oluğu, tente, çalı, sıva, çatı, pişmiş
toprak); bölgeler `atlas_layout.json`. `kit.py` (düz gölgeli çokgen, atlas UV'si dokunun dünya boyutuna göre kırpılır),
`assets.py` (8 parametrik üreteç) ve `build.py` (Blender, `--factory-startup`, GLB; doku harici `furniture_atlas.png`,
malzeme `mat_furniture_atlas`, roughness 1, specular 0, opak, tek yüz). Gerçek bağlantılar: bank 3 döküm çerçeve +
altıgen cıvata + gergi çubuğu; direk kaide/kapak/boyun halkaları + kıskaç + kol + gövde; durak 6 direk + cam çerçeve +
ahşap kiriş + knee-brace + oluk borusu + beton plak; kiosk taş kaide + pencere çerçevesi + tezgâh/konsol + tente iskeleti
+ kepenk + kapı + parapet. `rebuild.sh` tek komut (atlas → Blender → Godot import → `generate_lods=false` sabitleme →
Godot import → katalog → doğrulama). `generate_lods=false` ve post-import yok (T-057 sözleşmesi).

## Doğrulama (bu oturumda koşuldu)

- `bash art/blender/furniture/rebuild.sh` iki kez GERÇEKTEN çalıştırıldı (`tools/library/furniture_determinism.py`):
  16 GLB + atlas + layout + katalog sha256 eşit → `artifacts/verify/t058/determinism.json` (identical=true).
- Koruma: `artifacts/verify/t058/preservation.json` — 91 eski kayıt tam eşit, 216 bina/bitki/zemin/model dosyası
  (GLB/PNG/JSON) hash'i değişmedi (`tools/library/furniture_preservation.py`).
- `python3 -m unittest discover -s tests/library`: 73 test OK (20 yeni: `test_furniture_catalog.py`; drift/eksik/bozuk/
  kesik GLB/over-cap (gerçek 652 üçgenli GLB'nin LOD1 yerine konması)/generate_lods=true/post-import/proxy kalıntısı/
  yanlış yönlendirme/kullanıcı alanı koruması).
- `furniture_catalog.py --check`, `vegetation_catalog.py --check`, `hero_lods.py --check`, `build_catalog.py --check`,
  `validate_catalog.py` (99 kayıt, 0 hata) geçti. `check_furniture_import.gd` gerçek Godot importunda
  `FURNITURE_IMPORT_OK meshes=16 …` verdi. `gdlint` yeni .gd dosyalarında temiz. `tools/verify.sh` KOŞULMADI (Studio Director).

## Kendi görsel gözlemim (gerçek Godot PNG'leri açıldı; art-director değerlendirmesi değildir)

Kanıt: `design/library/sheets/furniture-hero/` (8 kontak sayfası: ön/yan/arka/üst/3-4/LOD1 aynı kamera + 25 m LOD0 ve
100 m LOD1 gerçek piksel kırpımı; `context-scale|street|lineup.png`; `index.json`). Lab: `assets/hero/furniture/furniture_lab.tscn`.

- İlk örnek (bank) çoğaltmadan önce açıldı: ahşap tahta/döküm çerçeve/okunur; yalnız insan figürünün kamera yönünde
  yakın durması ölçeği yanıltıyordu → 3/4'te figür uzak tarafa alındı, yan/ön görünümde derinlik payı eklendi.
- İyi: bank, durak (cam/metal/ahşap/beton ayrımı), kiosk (tente, kepenk, kapı, konsol) ve direk silüeti okunur, hero bina
  yanında ölçek gözle makul görünüyor (`context-street.png`); ölçüm değil, görsel izlenim.
- Zayıf/dürüst: (1) Hero bina dokulu ve ince detaylı; donatılar daha sadedir (özellikle bollard, çöp kutusu, bisiklet
  demiri düz renk gibi okunur, doku uzaktan seçilmez). (2) Cam, çapraz parlama bantlarıyla "ekran" gibi okunuyor; çok
  koyu. (3) Çalı faset kümeleri yeşil ve iri; bitki hattının yaprak kartlarından farklı bir dil (opak). (4) Taş saksı ve
  beton plak çok açık (güneşte patlamaya yakın). (5) Tente çizgileri bina tentelerinden (sarı/krem) farklı renkte;
  renk dili kullanıcı/art-director kararı. (6) 100 m LOD1 karelerinde donatılar birkaç pikseldir; bollard/çöp kutusu
  neredeyse görünmez → cull mesafesi küçük donatı için bile gevşektir olabilir, ölçülmedi.
- Hero bina ile fark: bina atlası çok daha yoğun doku/cam/panjur içerir; donatı kalitesi "mat, dokulu" çıtanın altında
  değil ama bina kadar zengin değil; kabul sanat kararıdır.

## Ölçülen / hesaplanan / test edilmeyen

Ölçülen: üçgen/bbox/sha/GLB boyutu (≤ 45 KB), import denetimi, determinizm, koruma. Hesaplanan: piksel boyu tahminleri
(300 m'de 8 m direk ≈ 30 px, FOV 50° / 1080p). Test EDİLMEDİ: gerçek şehir/hedef cihaz bütçesi ve draw-call etkisi
(varlık başına 1 mesh/1 yüzey/1 malzeme, ortak tek atlas; oyun içi ölçüm yok), oyun içi LOD geçişi, `tools/verify.sh`,
bağımsız QA, art-director kapısı, Q-018 kararları.

## Riskler

Küçük donatıda kamera uzaklığında cull "pop"u; direk uzun mesafede görünür kalır. Metal rengi (FN1/FN2) ve tente
renkleri Q-018 kapsamındadır. Atlas bölgeleri sabit 256 px kare; ek malzeme için layout değişimi tüm GLB UV'sini etkiler.
