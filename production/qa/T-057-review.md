# T-057 · Bağımsız QA · Tur1 · 2026-10-27

**Verdict: FAIL — uzak taç temsili ve bozuk source alanı yönlendirmesi düzeltilmeli.**
İnceleyen: uygulayıcıdan ayrı Codex `qa_engineer`. İnceleme HEAD'i `fe89e29`; uygulama çalışma ağacındadır. Kullanıcı onayı verilmez; yalnız kütüphane/lab ölçütleri değerlendirilir. Full başlatılmadı: bilinen görsel kusur varken geniş paketi geçmek teslimi doğru yapmaz.

## Kabul ölçütleri

| Ölçüt | Sonuç | Bağımsız kanıt / sınır |
|---|---|---|
|1 ·10 tür, metre/zemin origin, deterministik üretim, okunur tür|PASS (LOD0 öneri yönü); zincir kusuru ölçüt2'de|10 tür kontağının tamamı açıldı; gövde/dal/taç düzenleri farklı. GLB'ler gerçek dosyadan ölçülüyor. Son32dosya üretim tekrarı kaydında changed=[]; QA Blender üretimini ayrıca tekrar etmedi. Kullanıcı estetik/botanik onayı değildir.|
|2 ·Bütçe, tür/taç tonu/silüet sürekliliği|**FAIL**|Bütçeler geçiyor; fakat gerçek150m karesinde çınar ve iki çam proxy'si taç kütlesini/silüetini korumuyor. Servi LOD1 kontağında da dolu dar sütun, aralıklı yaprak yamaları olan çıplak gövdeye dönüşüyor.|
|3 ·Çalışma ölçeği/1.75m insan/değişmeyen hero referansı|PASS|GLB ölçüleri katalogla eşleşiyor; palmiye9.425/11.315m, zeytin~5m, çınar13.72m. Lineup ve bağlam kareleri açıldı. Eski bina dosyaları hash kontrolünde aynı.|
|4 ·Katalog/proposed/sahiplik/drift/yönlendirme|**FAIL (validator sağlamlığı)**; sahiplik/olağan veri PASS|91 kayıt/0 hata/0 uyarı;10 bitki proposed; önceki81 kayıt tam içerik veGLB hash'i HEAD ile aynı. Fakat bozuk source=None/string/list, yeni dispatch satırında AttributeError ile çöküyor.|
|5 ·Gerçek Godot aynı kamera/ışık kontakları/bağlam/alpha riski|PASS|17 PNG'nin tamamı açıldı; aynı LOD0 bbox/origin/mesafe/ışık kullanılıyor.4 bağlam ve2 AA-off tanısı mevcut; coverage veoyun profili ayrımı açık. Görsel kanıt varlığı, kusurlu proxy'yi PASS yapmaz.|
|6 ·Maliyet/sınırlar/dürüst öneri durumu|PASS|Tek1024 atlasın teorik5.33MiB hesabı gerçek VRAM diye sunulmuyor. Dar3D lab/AA maliyeti ve54k/iPad/yoğun kent test edilmemiş ayrımı açık; tür seçimi kullanıcıda.|
|7 ·Odaklı test/import/lint/bağımsız QA+sanat/final kapı|UNVERIFIED final; odaklı teknik PASS|42 Python test,91kayıt0/0,katalog idempotence,30bitki/42bina Godot import PASS. Full ve ayrı sanat kapısı henüz yapılmadı; önce düzeltme.|

## F1 · Taç kütlesi ve tür silüeti kayboluyor — bloke edici

Kanıt: `design/library/sheets/vegetation-hero/broad-trees-150m-lod.png` **açıldı**. Bu, yazılmış proxy çalışma eşiği>120m'nin ötesinde, aynı150m kamera/origin/ışıkla gerçek Godot LOD0/LOD1/proxy karşılaştırmasıdır.

- **Çınar:** LOD0/LOD1 yuvarlak ve bağlantılı geniş taçken proxy3 ayrı küçük yaprak tutamına/şematik dallara dönüşüyor; taç alanının büyük bölümü kayboluyor.
- **Fıstık çamı:** kaynakta yatay şemsiye taç bulunuyor; proxy'de şemsiye sürekliliği ve genişlik büyük ölçüde yok, ince gövdenin ucunda küçük/lopsided yaprak grupları kalıyor.
- **Kızılçam:** düzensiz ama dolu dikey taçtan birkaç eğik yaprak parçası ve açık gövdeye geçiyor;150m'de de fark görünür.
- `veg_hero_cypress_a.png`: LOD0 servi sürekli dar sütunken **LOD1 bile** ayrı4–5 yaprak yaması ve çıplak gövde görünümüne düşüyor. Bu türün temel ayırt edicisi sütun silüetidir;76tri olmak kalite kanıtı değildir.

Üçgen bütçesine sığmak veya dalların yaprak kartlarına fiziksel bağlanması bu görünüm kusurunu çözmez. Proposed/far etiketi de kabul ölçüt2'yi kaldırmaz.

### Sınırlı düzeltme ve yeniden kanıt

1. LOD0 stilini yeniden tasarlama; kusurlu uzak temsili düzelt. KaynakLOD0 albedo/silüetinden türeyen taç impostor/cross-card veya eşdeğer kütle koruyan temsil uygundur. Mevcut bütçe/eşikler kaliteyi geçirmiş gibi gevşetilmez.
2. Servi LOD1'de dar sütunu koru; LOD0 yalnız316tri olduğundan300 çalışma bütçesinde taç geometrisine yakın kalmak mümkün. Salt yaprak sayısını5'e düşürmek yerine görünür alan/silüeti koru.
3. Etkilenen bütün **palmiye dışı** temsil ailesini birlikte kontrol et:3 geniş ağaç,2zeytin,servi,maki,çit. Zeytin ve çalı/çit proxy kontaklarında da yaprak alanı inceliyor; yakın tanı tek başına150m kusuru kanıtı değildir. Bu nedenle düzeltme sonrası sadece3geniş ağacı tekrar çekmekle yetinme:8palmiye dışı varlık için150m LOD karşılaştırması, ayrıca servi50m karşılaştırması üret/aç. Zeytinlerin geniş yuvarlak taçları ve servi sütunu korunmalı; çalı/çitte havada duran seyrek yaprak lekesine dönüşme olmamalı.
4. Temsil değiştirilirse alpha/mip/shared texture/provenance/bütçe ve deterministik dosya kontrolleri yenilenmeli. Çapraz kart yan/üst kenar kaybolmasını saklamamalı; en az ön/yan ve uzak tanı korunmalı. Bu, yeni dünya yerleşimi veya animasyon talebi değildir.

## F2 · Bozuk source alanı doğrulayıcıyı çökertiyor — sınırlı teknik düzeltme

`tools/library/validate_catalog.py:94` yeni yönlendirme, mevcut source tip kontrolünden **önce** `e.get("source", {}).get("kind")` çağırıyor. Bağımsız bellek kopyasında source=None, `"bad-source"` ve[] ile `check_entry` çağrılarının üçü de **AttributeError** verdi. Çıktı kontrollü katalog hatası olmalı; traceback değildir.

Düzeltme: dispatch'ten önce source sözlük tipini güvenle denetle; ilgili doğrudan bitki doğrulayıcısı da bozuk source ile çökmesin. Source-kind yönlendirmesinin yalnız doğru handler'ı çağırdığı ve bozuk source'un hata listesi ürettiği negatif test ekle. Yeni mimari/refactor gerekmez.

## Gerçek çalıştırılan odaklı komutlar

- `python3 -m unittest discover -s tests/library -p 'test_*.py' -q`: **42 PASS**.
- `python3 -I tools/library/validate_catalog.py`: **91 kayıt/0 hata/0 uyarı** (geçerli mevcut katalog için).
- `python3 tools/library/vegetation_catalog.py --check`:10 öneri/30 seviye PASS.
- `python3 tools/library/hero_lods.py --check`:eski21 bina/63seviye PASS.
- `python3 tools/library/build_catalog.py --check`:91 kayıt güncel.
- `check_vegetation_import.gd`: **VEGETATION_IMPORT_OK meshes=30 shared_texture=1 alpha=MASK double_sided=true mipmaps=true**; `artifacts/verify/t057/qa-import.log`.
- `check_hero_lod_import.gd`: **HERO_LOD_IMPORT_OK meshes=42 declared_texture_resources=42**; `artifacts/verify/t057/qa-building-import.log`.
- Önceki81 katalog kaydı tam içerik olarakHEAD ile eşit; her mevcutGLB'nin gerçek SHA-256'sı HEAD kaydıyla aynı. Yalnız approval alanları değil bütün eski kayıtlar korundu.
- `tools/canon-check.sh`:11/11 manifestle aynı; `src`, `scenes`, foundation ve kit manifestinde diff yok; `git diff --check` temiz.
- Source-kind değişiklikleri eski bina testlerini körleştirmiyor: açık kind=hero filtresi bitkileri dışarıda tutuyor, bina testleri halen21 kaydı/42mesh'i doğruluyor.
- Determinizm dosyası `pause-delivery-determinism.json`:32 dosya,changed=[] (uygulayıcı üretim kaydı; bağımsız hash/katalog kontrolleri ayrıca yapıldı).

## Açılan PNG'lerin tamamı

`veg_hero_{plane,pine_brutia,pine_stone,olive_open,olive_twisted,palm_date,palm_slender,cypress,maquis,hedge}_a.png`; `context-{true,street,slope,lineup}.png`; `olive_open-scissor-no-msaa.png`; `palm_date-scissor-no-msaa.png`; `broad-trees-150m-lod.png`.

LOD0 aileleri birbirinden ayrılıyor ve hero bina yanında ölçek ilişkisi tutarlı. Palmiye seçimi veya bitkilerin kullanıcı onayı verilmez. Önce F1/F2 giderilmeli; bu tur **done** veya **görsel PASS** olarak kapatılamaz. Kullanıcının güvenli duraklama kapsamı korunur; T-058+ başlatılmaz.
