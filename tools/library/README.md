# tools/library — varlık kütüphanesi araçları (T-052)

Katalog: `data/library/catalog.json` (şema: `data/library/SCHEMA.md`). Sayfalar: `design/library/sheets/`.

| Araç | Ne yapar |
|---|---|
| `build_catalog.py` | `kit_manifest.json` + GLB dosyalarından kataloğu üretir. Boyut ve üçgen sayısı GLB'den ÖLÇÜLÜR. Idempotent; kullanıcı alanlarını (`approval*`, `user_note`, `user_*`) ve kit dışı kayıtları korur; `approved/rejected` ASLA yazmaz. |
| `validate_catalog.py` | Şema, çift kimlik, eksik GLB/üreteç, manifest↔katalog, GLB'den sürüklenme, bütçe, onay sahipliği kuralları. Çıkış 1 = hata. |
| `render_sheets.sh` | Kontak sayfaları: Blender (headless, EEVEE) görünümleri + Pillow ile etiketli sayfa. |
| `glb_info.py` | Bağımlılıksız GLB okuyucu (üçgen sayısı, bbox). |
| `blender_render_views.py` | Blender içi işçi (doğrudan çalıştırılmaz). |

## Komutlar (repo kökünden)

```
python3 tools/library/build_catalog.py            # ne değişirdi? (yazmaz)
python3 tools/library/build_catalog.py --write    # katalogu güncelle (manifest/GLB değişince)
python3 tools/library/build_catalog.py --check    # bayatsa çıkış 1
python3 -I tools/library/validate_catalog.py      # doğrula
python3 -I tests/library/test_catalog.py          # birim testleri (yalnız stdlib)
tools/library/render_sheets.sh                    # tüm kategorilerin sayfaları
tools/library/render_sheets.sh --category building --force   # yalnız bina, önbelleği yok say
```

`render_sheets.sh` önce katalog güncel mi diye bakar; bayatsa durur. Gereksinim: Blender 4.5 (`BLENDER=` ortam
değişkeni ya da `/Applications/Blender.app`) ve Pillow'lu `python3` (`python3 -m pip install pillow`; `-I` KULLANMA).
Görünüm önbelleği `artifacts/library/views/` (çalışma ağacı dışı); anahtar = GLB sha256 + palet + işçi betiği + ölçek.
Tam bina seti ilk koşuda ~3 dk, önbellekle birkaç sn.

## Sayfa düzeni

`design/library/sheets/<kategori>-NN.png` (+ `index.json`: kimlik → sayfa/satır/ölçek). Her satır bir varlık:
sol sütun kimlik, aile · dönem · çatı, ölçü (m, GLB'den), üçgenler (LOD0/LOD1/PROXY), onay durumu. Beş görünüm:
ön (14° eğim), 3/4 ön-sağ, 3/4 arka-sol, tepeden (ön = aşağı, 10 m çubuk), ve "ölçek" (7 m'lik yakın kare, bina
köşesinin yanında 1,75 m insan). Ölçek sayfa başına sabittir ve başlıkta yazar (kenar = N m); büyük yapılar için sayfa
ölçeği küçük figürü okunmaz yapar, bu yüzden "ölçek" görünümü eklenmiştir.

Işık/renk: sabit tek güneş (52° yükseklik, dünya sabit), düz mat, Standard görüntü dönüşümü, nötr gri zemin/arka plan;
renkler `assets/kit/kit_palette.json`'dan (duvar/çatı/aksan için manifestte ilk listelenen satır; oyunda örnek başına
değişir). Oyun gölgelendiricisi (`mat_kit`) değil Blender malzemesi kullanılır: renk eşleşir, tam piksel değildir.

## Kapsam sınırları (dürüstlük)

- Yeni insan/araç/yol varlığı ÜRETMEZ; yalnız mevcut kit'i listeler. `proposed` şablon kayıtları art-director onayına bağlı.
- `region` alanı şimdilik `null` (bölge karakteri kararı yok).
- Kategoriler `road_section`, `ground`, `street_furniture`, `marking` henüz boş (sayfa üretilmez).

## Hero LOD zincirleri (T-056)

```
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python art/blender/hero/build_lods.py
python3 tools/library/hero_lods.py --write
python3 tools/library/hero_lods.py --check
python3 tools/library/validate_catalog.py
python3 -m unittest discover -s tests/library -p 'test_*.py' -q
```

İsteğe bağlı `-- old_core|bazaar|res_mid|res_late|house|industrial|civic` aile seçer.
Üreteç source LOD0'ı değiştirmez; anlamsal yüz/geometri sadeleştirmesi yapar.
Proxy doku paketleme için `uv run --with pillow==11.3.0` kullanır; üreteç bunu çağırır.
Ham ışıksız ortografik bake kanıtları `artifacts/verify/t056/proxy-bake/` altındadır.
Yeni GLB'lerde gömülü doku yükü ayıklanır; LOD1 kaynak atlası, proxy kendi 256px
atlasını dış referansla kullanır. Ayrıntı ve sınırlar: `design/library/hero-lod.md`.
Lab: `res://assets/hero/lod_lab.tscn`; `--fam=... --distance=100 --variants=true`.
Her sütunun aynı kamera/ışık ve ayrı dünyası vardır: LOD0 | LOD1 | PROXY.

Arka cephe denetimi: lab `--view=rear` veya `--yaw=180` ile tekrarlanır.
Proxy yalnız ön bake kullanır; yan/arka tile özgün albedoyu korur.
`uv run --with pillow==11.3.0 python tools/library/check_proxy_side_tiles.py`
bu tile'ın değişmediğini piksel üzerinden denetler. GLB arka yüz UV regresyonu
normal Python test keşfindedir (`tests/library/test_hero_rear_uv.py`).

## Bitki HERO önerileri (T-057, kütüphane/lab)

```
bash art/blender/vegetation/rebuild.sh   # atlas -> base-only -> palmiye proxy -> katalog yaz -> validate
python3 tools/library/vegetation_catalog.py --check
python3 tools/library/validate_catalog.py
tools/godot.sh --headless --path . --editor --import --quit
tools/godot.sh --headless --path . --script res://tools/library/check_vegetation_import.gd
uv run --with pillow==11.3.0 python tools/library/render_vegetation_sheets.py
python3 -m unittest discover -s tests/library -p 'test_*.py' -q
```

GLB'ler gömülü PNG yükü taşımaz;22 model tek gerçek `vegetation_atlas.png`
Texture2D kaynağını kullanır. PNG import ayarında mipmap açık, alpha-border düzeltmesi
var. Yapraklar çift taraflı MASK0.45; blend/sıralama yolu kullanılmaz. Lab
`--aa=off` ile MSAA/coverage olmadan tanı üretir; varsayılan4×MSAA+coverage yalnız
bu lab ayarıdır, oyun profiline uygulanmaz. Tüm kaynaklar öneri, Q-018 açık.
Yeni sayfalar `design/library/sheets/vegetation-hero/`; katalog ve `index.json`
ölçüleri GLB'den gelir. Açıklama/sınırlamalar `design/library/vegetation-hero.md`.

Bitki zinciri (T-057 Karar 5): palmiye dışı 8 tür LOD0/LOD1, palmiyeler LOD0/LOD1/PROXY;
tüm `.glb.import` `meshes/generate_lods=false`. Atlas üst 512 satırı ve ölü y640–1023 tile
bölgesi `assets/hero/vegetation/atlas_regions.json` hash'iyle korunur; denetim:
`uv run --with pillow==11.3.0 python tools/library/check_vegetation_atlas.py`.
