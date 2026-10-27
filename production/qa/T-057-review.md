# T-057 · Bağımsız QA · Tur1 · 2026-10-27

**Güncel tur2: odaklı teknik QA PASS; F1/F2/F3 düzeltmeleri doğrulandı. Sanat kararı ve final full PENDING; görev done değildir.**

**Tur1 verdict: FAIL — uzak taç temsili ve bozuk source alanı yönlendirmesi düzeltilmeli.**
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


## Tur2 · kullanıcı “devam” sonrası bağımsız teknik kontrol

İnceleme noktası37d2d2b WIP sonrası donmuş düzeltme ağacı. Önceki tur1 kanıtları tarihçedir; son aday için aşağıdaki taze sonuçlar geçerlidir. Full bu turda başlatılmadı.

### F1 çözümü · teknik taç kütlesi / ölçek PASS, sanat hükmü bekliyor

Sekiz palmiye dışı proxy artık kendi gerçekLOD0 ön/yan/üst albedo+alpha render'ından üretilmiş3 çapraz kart/6 üçgendir. Orijinal atlasın boş alanındaki24 tile kullanılır; aynı tekTexture2D korunur. Servi LOD1,300tri ile kaynak sütuna yakın yaprak örtüsünü tutuyor. Bütçe veya50/120m çalışma eşikleri gevşetilmemiş.

**Açılan son görüntüler:** `nonpalms-150m-lod.png` (bütün8 aday), `cypress-50m-lod.png`, `proxy-side-top-proof.png` ve8 yenilenen tür kontağı. Önceki150m'deki3ayrı tutam/çıplak dal proxy sorunu bu temsilde giderilmiş; çınarın geniş yuvarlak, fıstık çamının yatay şemsiye, zeytinlerin yayvan ve servinin dar sütun izi geri gelmiş. Servi50m LOD1 artık ayrı yaprak adaları olan çıplak gövdeye dönüşmüyor. Türlerin bbox/metre/origin konumları kaynakla aynı.

**Görsel sınırlama gizlenmez:** sabit kartlar yakında düz ve kesişen yüzey olarak okunuyor; ön/yan farklı normal ışıklanması ton farkı yaratıyor; çınarın üst tanısında koyu X/kesişim belirgin. Bunlar gerçek PNG'de mevcut. Önceki objektif taç kaybının düzelmesi, bu impostor görünümüne bağımsız sanat PASS'ı verildiği anlamına gelmez. Bu tur teknik representasyon/silüet bütünlüğünü doğrular; >120m sanat kabulü ayrı art-director kapısına kalır. Yoğun kent/zoom geçişi/gölge/AA-off uzak tanı ve cihaz performansı test edilmedi.

### F2 çözümü · PASS

Bağımsız doğrudan deney: source=None/string/list için genel `check_entry`, doğrudan `vegetation_catalog.validate_chain` ve gerçek genel doğrulayıcı CLI çağrısı kontrollü `source must be an object` tanısı veriyor. CLI çıkış1, traceback yok. Geçerli bitkiler doğru handler'a gidiyor; eski21 bina testleri/42 gerçek import halen çalışıyor.

### F3 · yeniden üretim komutu metadata'sı — küçük düzeltme bekliyor

`vegetation_catalog.entry()['source']['rebuild']` önceki `atlas.py; Blender build.py -- species` komutunu taşıyordu. Yeni çapraz temsil, atlas→base-only→bake→pack→proxy-only sırası gerektiriyor. Eski komut atlasın alt proxy tile'larını temizleyip geri doldurmadığından katalogdaki tekrar üretim tarifi eksik/yanlış. Raporun tam komutu doğru; katalog traceability'si de ona bağlanmalı. Parent küçük wrapper/metadata düzeltmesini yapıyor; geometri veya LOD0 tasarım döngüsü istenmiyor. Son katalog/idempotence ve wrapper sırası düzeltmeden sonra yeniden kontrol edilecek.

### Tur2 taze teknik kanıtlar

-45 Python test PASS (buna gerçek dışa aktarılmış proxy UV/bbox/6tri, bozuk tile pikseli ve malformed source negatif testleri dahil); katalog91 kayıt/0 hata/0 uyarı; bitki10/30seviye veeski bina21/63seviye check PASS; genel katalog91 kayıt güncel.
- Gerçek son Godot denetimleri:30 bitki mesh'i/tekTexture2D/MASK0.45/çift taraf/mipmap PASS; eski42 bina mesh/doku kimliği PASS (`qa-resume-import.log`, `qa-resume-building-import.log`).
- Tile provenance denetimi:8 kaynak/24 ön-yan-üst tile, kaynakLOD0 SHA ve üst512RGBA pikselleri PASS. Negatif test gerçek tile pikselini geçici kopyada değiştirip reddedildiğini sınar; yalnız metadata hash'ini değiştirme testi değildir.
- fe89e29 katalogundaki81 kaydın **tam içeriği** ve tüm67 özgün GLB hash'leri bağımsız yeniden karşılaştırıldı: aynı.14 eski zeminPNG hash'i de aynı.37d2d2b'deki10 bitkiLOD0 gerçek hash'i korunmuş.
- Üretici tam tekrar kaydı `resume-determinism.json`:33 dosya/equal/changed=[] ve komut listesi. QA tüm Blender hattını üçüncü kez çalıştırmadı; gerçek kaynak/çıktı hash'lerini ve taze check araçlarını bağımsız doğruladı.
- Kanon11/11; `src`, `scenes`, foundation ve oyun manifestinde diff yok; git diff-check temiz.

| Ölçüt | Tur2 sonucu | Açıklama |
|---|---|---|
|1 ·tür/ölçek/üretim|Teknik PASS|KaynakLOD0 korunuyor; bütçeli zincir, kaynak türetimi ve deterministik kanıt mevcut. Kullanıcı onayı değil.|
|2 ·bütçe/LOD sürekliliği|Teknik PASS / sanat PENDING|Önceki taç kaybı ve serviL1 kopuk sütun giderildi. Kart ton/kesişim görüntüsü art kapısında ayrıca karara bağlanmalı.|
|3 ·ölçek/ref hero|PASS|Aynı kaynak ölçüleri; korunmuş referanslar.|
|4 ·katalog/koruma/traceability|F2 PASS / F3 PENDING|81 eski kayıt+67GLB+14PNG ve10plantLOD0 korunuyor; source guard sağlam. Rebuild metadata son düzeltmesi bekliyor.|
|5 ·gerçek görseller/alpha risk|PASS|Son8kontak+3tanı açıldı; önceki değişmeyen bağlam/AA-off kareleri tur1'de açılmıştı. Riskler açık.|
|6 ·dürüst maliyet/kapsam|PASS|Yeniimpostor şehir performansı diye sunulmuyor; önceki ölçümün değişmeyenLOD0 labına ait olduğu açık.|
|7 ·odaklı/finalQA/art|Odaklı45 PASS; art/full PENDING|Genel done veya tüm kriterlerPASS sonucu henüz yok.|


## Tur2 kapanış · odaklı teknik PASS / sanat ve full PENDING

F3 metadata düzeltmesi doğrulandı.10 bitki kaydının `source.rebuild` alanı artık `bash art/blender/vegetation/rebuild.sh`. Wrapper `set -euo pipefail` ile repo köküne geçip tam ortak-atlas dalgasını sırayla çalıştırıyor: atlas→base-only→bake→pack→proxy-only→catalog-write→validate. `bash -n` PASS. İlk5 üretim adımı33dosya deterministik tekrar kaydındaki komutlarla aynı. **Wrapper ayrıca uçtan uca yeniden çalıştırılmadı**; doğrulanan şey yazılı wrapper sırası/sözdizimi ve aynı alt komutların mevcut taze tam üretim kanıtıdır. Tek tür komutunun paylaşılan atlası silmesi artık katalog tarifi olarak sunulmuyor.

Metadata düzeltmesinden sonra yeniden çalıştırılanlar:

-45 Python test PASS; katalog91/0 hata/0 uyarı; vegetation10/30vehero21/63 check; build_catalog91güncel;24tile/source denetimi PASS.
- Gerçek runtime30bitki/tekTexture2D/MASK/çift taraf/mipmap PASS; eski42bina import PASS.
-81 eski tam kayıt+67GLB+14PNG ve10bitkiLOD0 hash'i yeniden aynı;10katalog rebuild komutu doğruwrapper'a bağlı; diff-check temiz.

**Güncel kriter durumu:**1 teknikPASS ·2 teknik kütle/bütçePASS ve sanatPENDING ·3PASS ·4PASS ·5PASS ·6PASS ·7odaklıPASS/art+fullPENDING. Eski tur1 FAIL giderildi; yeni doğrulanmış teknik blocker yok. Yakın/üst impostor kart kesişimi ve ton/ışık farkı sanat incelemesinde açıkça değerlendirilmelidir; bu rapor o görünümü sessizce sanatPASS saymaz. Final full başlatılmadı ve tüm görev tamamlandı denmez.
