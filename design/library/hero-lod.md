# Hero bina LOD kütüphanesi — T-056 (2026-10-26)

**Yalnız kütüphane; oyuna entegre değil.** Onaylı 21 LOD0 dosyası değiştirilmedi.
Yeni LOD'lar ve proxy dokuları `proposed`; kullanıcı onayı aktarılmadı.
Görev: `production/tasks/T-056.md`; REQ WLD-01, TEK-03, VIS-01/02/03/05.

## Üretim

`art/blender/hero/build_lods.py`, özgün parametrik bina üreticisinin aynı metre,
origin ve UV fonksiyonlarını kullanır. Kör decimation uygulanmaz. Delikli pencere
ızgarası kapalı duvar ve düz doku pencerelerine dönüşür. LOD1'de balkonlar,
cumbalar, tenteler, kapı/vitrin dokuları, düz panjur yaprakları, çatı kütleleri,
büyük ekipman, kamu saat kulesi ve sanayi bacası korunur. İnce pencere kasaları,
anten, oluk, ufak çatı uçları ve çit direkleri silinir. Doku/Lambert matlığında
özgün hero yönü korunur; bu işlem yeni bina tasarımı değildir.

Proxy, aynı ailenin çatı/ana kütlesi ve büyük ayırt edicilerini tutar: orta/geç
apartmanda çatı merdiven kütlesi; evde bahçe duvarı; sanayide tonoz/beşik farkı,
baca ve konteyner yığını; kamu binasında kademeli kule, piramit çatı ve saatler.
Tüm aileler ortak bir kutuya indirgenmez. Cephe rengi/ritmi, **gerçek LOD0
geometrisinin ışıksız ortografik albedo render'ından** türetilmiş 256px atlasa
aktarılır. Böylece balkon/panjur renk oranı uzakta siyah pencere ızgarasına dönüşmez.
Ön render aynı ön UV alanına paketlenir. Yan/arka doku alanı özgün atlasın
aynı piksellerini korur; sağ cephedeki geometrik ekler arkaya boyanmaz. Çatı ve
palet örnekleri de kaynak atlasın aynı bölgeleridir. Bake gün ışığı/gölge içermez; oyunda ışık ikinci kez uygulanmaz.

```
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python art/blender/hero/build_lods.py
python3 tools/library/hero_lods.py --write
python3 tools/library/hero_lods.py --check
python3 tools/library/validate_catalog.py
```

Üreteç aile seçimi için `-- res_mid` kabul eder. Yalnız geometri/URI doğrulama
tekrarında, kaynakları değiştirmeden mevcut bake'leri kullanmak için
`-- --reuse-proxy-atlases` kullanılabilir; normal yeniden üretim tüm bake'leri yapar.
Paketleme bağımlılığı `uv run --with pillow==11.3.0` ile sabitlenmiştir.
Üretilen geometri her varlıkta yetim Blender veri bloklarından arındırılır;
aile seçimi malzeme adlarına önceki ailelerin sayaçlarını taşımaz.

## Kanıt ve sınırlar

- Gerçek Godot lab: `assets/hero/lod_lab.tscn`. Her sütun ayrı dünya ama **aynı
  kamera konumu, açı, FOV, ışık ve özgün LOD0 çerçevesini** kullanır. Sütunlar
  LOD0 / LOD1 / proxy; satırlar a/b/c. Çıktılar `sheets/hero-lod/` altındadır.
- 65m kontak sayfaları, proxy'nin yakın ölçekte neleri kaybettiğini özellikle
  gösterir; proxy'nin 65m'de kullanılacağı iddiası değildir. 100/300m kareleri
  orta apartman, sanayi ve kamu aileleri için ayrı tutulur.
- Mesafeler yaklaşık100/300m **çalışma değeridir**; otomatik geçiş/HLOD/instancing
  burada kurulmadı. Geçiş patlaması, yoğun kent örtüşmesi ve gerçek 54k bina
  yükü bu teslimin kanıtı değildir.
- AABB ham farkları katalogdaki `lod_chain.levels` üzerinden ölçülür. LOD1'de
  temel ayak izi ve kat/çatı kütlesi korunur; en yüksek anten1.3m, minik baca
  kapağı0.3m, kule uç çubuğu0.7m gibi detayların silinmesi dış sınırı küçültür.
  Proxy'de balkon/tente çıkıntısı silinir; bu yeniden ölçekleme/recenter değildir.
- GLB'den yetim gömülü PNG bufferView ve BIN yükü çıkarıldı. GLB'ler dış dokuya
  referans verir. LOD1, kaynak PNG'nin başka bir kopyasını yüklemek yerine
  **LOD0'ın Godot'ta zaten kullandığı aynı Texture2D kaynağını** kullanır.
- 21 yeni256×256 proxy atlası: RGBA8 taban+mip zinciri varsayımıyla yaklaşık
  **7MiB ek doku belleği**. Bu hesap; sürücü/VRAM ölçümü değildir. Sıkıştırma ve
  gerçek yerleşik atlas sayısı entegrasyonda ölçülecek. Özgün atlas bellek yükü
  bu7MiB hesabına dahil değildir.
- Determinizm: tüm42 GLB ve21 proxy PNG, tam bake'in ikinci üretiminde
  bayt düzeyinde aynı çıktı verdi. Son URI/veri bloğu düzeltmesinden sonra
  geometri tekrarının hash sonuçları ayrıca kaydedilir. Özet görev kanıtındadır.
- Testler gerçek dosyaların ölçüsünü/hash'ini, bütçeyi, onay alanlarının
  korunmasını ve bozuk/eksik veriyle kapanmayı sınar. Godot import denetimi
  42 modelin gerçek malzeme doku yollarını/üçgenlerini ve LOD0/LOD1 kaynak
  kimliğinin aynılığını kontrol eder (`tools/library/check_hero_lod_import.gd`).

## Görsel uygulayıcı notları (bağımsız kapı yerine geçmez)

65m sayfalarında LOD1, özgün kat ritmini, panjur renklerini, cumbaları ve cephe
karakterini korur. Düz pencere yüzeyleri yakın incelemede daha sığdır; ince
çit/anten kaybı görünür. Proxy'nin yalın silüeti yakında belirgindir. İlk proxy
denemesi siyah pencere oranını artırıyordu; bu sürüm reddedilip gerçek kaynak
albedo bake'iyle değiştirildi. 300m'de ışık/cephe tonu daha tutarlıdır.
Kamu/çarşı hero'sunun eski aile içi çeşitlilik ve kule oranı sorunları T-054'ten
miras kalır; LOD çalışması bunları yeniden tasarlamaz.

Ölçülen aile tablosu ve dar lab performansı aşağıya eklenir. Gerçek kent bütçesi
geçti veya tüm kütüphane tamamlandı sonucu çıkarılmaz.

## GLB üzerinden ölçülen üçgenler

| Aile | LOD0 | LOD1 | Proxy |
|---|---:|---:|---:|
| hero_civ_hero | 4090 | 480 | 78 |
| hero_com_bazaar | 3065 | 449 | 30 |
| hero_ind_hero | 2140–2360 | 258–290 | 58–74 |
| hero_old_core | 4233 | 421 | 30 |
| hero_res_house | 1572 | 270 | 80 |
| hero_res_late | 6738 | 530 | 32 |
| hero_res_mid | 6416–6558 | 530–552 | 30–32 |

42 GLB +21 proxy PNG toplamı: **1.90MiB** (import cache ve PNG sidecar dosyaları hariç).

Yalnız bütçe hesabı:100×6738 LOD0 +100×552 LOD1 +2000×80 proxy = **889,000 üçgen**. Bu hesap2200 görünür yapı varsayar; 54k yapının görünürlük/instancing/LOD seçimini doğrulamaz. Kare süresi veya yerel900k bütçesi için PASS sonucu değildir.

## Dar lab performansı (ölçüm, 2026-10-26)

Godot4.7.2 Compatibility;1600×900; Intel i7-8850H2.60GHz / Radeon Pro560X4GB;
VSync kapalı,60 ısınma +180 örnek. Aynı anda üç ayrı karşılaştırma viewport'u,
her birinde tek bina +zemin +ışık;100m kamera. Arka planda headless quick testleri
çalışıyordu; dış yük ve pencereli çizim gürültüsü vardır. Bunlar GPU timer
ölçümleri değil, render döngüsünün kare aralıklarıdır.

| Aile | Ortalama ms | P95 ms | Draw call | Render primitive |
|---|---:|---:|---:|---:|
| res_mid | 4.59 | 4.76 | 27 | 14392 |
| industrial | 4.80 | 5.00 | 27 | 5502 |
| civic | 4.62 | 4.76 | 27 | 9436 |

Render primitive sayısı gölge/viewport geçişlerini içerir; GLB üçgen tablosunun
karşılığı değildir. Bu dar sahne, gerçek kentte8ms veya900k üçgen bütçesinin
sağlandığını kanıtlamaz. Geçiş ve gerçek entegre performans ölçümü kütüphane
tamamlanıp entegrasyona izin verildikten sonra yapılacak.

## Bağımsız QA tur1 düzeltmesi · arka cephe (2026-10-26)

QA, yalnız ön/sağ kameralarda görünmeyen gerçek bir hata buldu: eski çekirdek
proxy arkasında yanlışlıkla ön cephe UV'si kullanılmış, diğer6 ailede arka UV'nin
0.9+0.05 kaynak kırpması atlanmıştı. Bunların hepsi özgün LOD0 ile aynı
`side` atlas eşlemesine getirildi. Yeni kamera `--view=rear` (180°) veya
`--yaw=DEGREES` kabul eder; her sütunda aynı dönüş kullanılır.

Ayrıca proxy atlasının sağ duvar geometrisi bake'i kaldırıldı. Tek bir yan tile
hem yan hem arka duvarda kullanıldığı için, sağdaki gerçek geometriyi bu tile'a
bake etmek özgün arkada olmayan bir kapı/pencereyi arkaya taşıyabilirdi. Şimdi
yalnız ön cephe gerçek LOD0 görüntüsünden türetilir; yan/arka tile özgün kaynak
albedosunun aynı pikselleridir (256px küçültme ve sınır filtresi dışında).
Ek malzeme, üçgen veya doku belleği gerekmedi.

Regresyon `tests/library/test_hero_rear_uv.py`, gerçek GLB BIN verisinden
POSITION/NORMAL/TEXCOORD_0 ve üçgen indekslerini okur; arka gövde yüzlerinin
konum ve UV'lerini özgün LOD0 çıktısıyla karşılaştırır. Üreteç metnini karşılaştırmaz.
Düzeltme öncesi21 proxy başarısızdı; düzeltme sonrası42 azaltılmış arka yüz
eşlemesi geçer. Ek piksel denetimi (`check_proxy_side_tiles.py`)21 proxy atlasının
yan/arka alanının kaynak albedo ile aynı olduğunu, yalnız4px Lanczos sınırı
hariç tutarak doğrular.

Arka kanıtlar: `sheets/hero-lod/*-rear-65m.png` (7 aile,a varyantı,3 detay
seviyesi) ve `old_core-rear-300m.png`. Ön/sağ sayfalar da son atlaslarla yeniden
yakalandı. Önceki geniş quick ve durdurulmuş QA full, bu düzeltmenin son teslim
kapısı değildir; final full yeniden bağımsız QA tarafından çalıştırılacak.

## Görsellere hızlı erişim

Her ön sayfa a/b/c varyantlarını satırlarda, LOD0/LOD1/proxy seviyelerini sütunlarda gösterir. Arka sayfalar aynı kamera ile a varyantını karşılaştırır; kamera, ışık ve ölçek sütunlar arasında değişmez.

| Aile | Ön / üç varyant · 65 m | Arka · 65 m |
|---|---|---|
| Tarihî çekirdek | [Görsel](sheets/hero-lod/old_core-variants.png) | [Görsel](sheets/hero-lod/old_core-rear-65m.png) |
| Çarşı | [Görsel](sheets/hero-lod/bazaar-variants.png) | [Görsel](sheets/hero-lod/bazaar-rear-65m.png) |
| Orta dönem apartman | [Görsel](sheets/hero-lod/res_mid-variants.png) | [Görsel](sheets/hero-lod/res_mid-rear-65m.png) |
| Geç dönem apartman | [Görsel](sheets/hero-lod/res_late-variants.png) | [Görsel](sheets/hero-lod/res_late-rear-65m.png) |
| Müstakil ev | [Görsel](sheets/hero-lod/house-variants.png) | [Görsel](sheets/hero-lod/house-rear-65m.png) |
| Sanayi | [Görsel](sheets/hero-lod/industrial-variants.png) | [Görsel](sheets/hero-lod/industrial-rear-65m.png) |
| Kamu / saat kulesi | [Görsel](sheets/hero-lod/civic-variants.png) | [Görsel](sheets/hero-lod/civic-rear-65m.png) |

Gerçek mesafe karşılaştırmaları: [apartman · 100 m](sheets/hero-lod/res_mid-100m.png), [apartman · 300 m](sheets/hero-lod/res_mid-300m.png), [sanayi · 300 m](sheets/hero-lod/industrial-300m.png), [kamu · 300 m](sheets/hero-lod/civic-300m.png), [tarihî arka cephe · 300 m](sheets/hero-lod/old_core-rear-300m.png).
