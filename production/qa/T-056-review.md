# T-056 · Bağımsız QA ve görsel kapı · 2026-10-26

İnceleyen: Codex `qa_engineer`, uygulayıcıdan ayrı ajan. Güncel durum: **PASS — Tur2 düzeltmeleri ve final full doğrulandı.** İlk tur FAIL bulgusu aşağıda tarihçesiyle korunur. Bu verdict yalnız T-056 kütüphane teslimi içindir; kullanıcı onayı/oyun entegrasyonu değildir.

## Kabul ölçütleri · Tur 1

| Ölçüt | Sonuç | Bağımsız kanıt |
|---|---|---|
| 1 · 21 LOD zinciri / bütçe / tekrar üretim | PASS (dosya ve bütçe); üretim tekrarı uygulayıcı kanıtı | `python3 tools/library/hero_lods.py --check`:21 zincir/63 seviye. Python30 test PASS. Bütün7 aile/a-b-c PNG açıldı. Final bağımsız üretim tekrarı henüz yapılmadı. |
| 2 · Özgün LOD0 ve ölçek | PASS (hash); arka temsil sorunu ölçüt3'te | HEAD kataloğu karşılaştırması:21 özgün GLB hash'i aynı; AABB ölçüleri zincirde kayıtlı; küçük silinen detay farkları raporda açık. |
| 3 · Aile görünümü / renk / cephe sürekliliği | **FAIL** | `art/blender/hero/build_lods.py` eski çekirdek PROXY arka duvarında `frontuv` kullanıyor. Özgün `hero_building.py:sides()` arka duvarı `side` atlasıyla kaplıyor. Uzak modele geçişte arka cephede ön vitrin/panjur/cephe ritmi icat ediliyor. |
| 4 · Katalog / sahiplik / oyuna bağlamama | PASS | Bağımsız HEAD karşılaştırması:81 kaydın approval*/user_* alanları aynı; `src`, `scenes`, foundation, kit manifestinde diff yok. Katalog81 kayıt/0 hata/0 uyarı. |
| 5 · Aynı kamera/ışık / aile-varyant kapsaması | PASS (ön/sağ); rear kanıtı eksik | `lod_lab.gd` her sütunda aynı LOD0 bounds/40° FOV/kamera yönü/mesafe ve ışığı kuruyor. 7×3×3 kontak sayfalarının tamamı açıldı. Kamera yönü sabit; arka hata bu karelerde görünmüyor. |
| 6 · Gerçek PNG / kapsamı dürüst rapor | PASS WITH FIXES | `design/library/hero-lod.md`:3-viewport dar lab ölçümleri ve gerçek54k yükünün test edilmediği açık. Ön/sağ karelerde LOD1 karakteri korunuyor; proxy ton düzeltmesi başarılı. Rear karşılaştırma eklenmeli. |
| 7 · Son full / bağımsız kapı | **UNVERIFIED** | Bağımsız `tools/verify.sh full` başladı; canon/studio/lint/import PASS. Somut geometri sorunu bulununca root isteğiyle yalnız bu QA koşusunun PID ağacı durduruldu. Son full düzeltmeden sonra yeniden çalışacak. |

## Düzeltme isteği

1. Eski çekirdek proxy arkasını kaynak `sides()` eşlemesiyle üret: `uv_of("side", (u + W/2) / W * 0.9 + 0.05, 1-z/H)`. Mevcut ön UV arka yüzde kullanılmamalı.
2. Diğer6 ailenin arka UV'leri zaten `side` atlasını kullanıyor; kaynakta olan `0.9+0.05` kırpmasını bunlarda da aynen koru. Sol/sağ duvarların `side_l_uv`/`side_r_uv` eşlemesi kaynakla aynı.
3. GLB'den arka duvar UV'lerinin ön atlas yerine yan atlas dikdörtgenine düştüğünü denetleyen anlamlı regresyon ekle. Yalnız hash'i yeniden yazmak bu hatayı yakalamaz.
4. Tekrarlanabilir arka kamera yönüyle eski çekirdek65m ve300m karşılaştırması al/aç. Aynı kamera/ışıkla ön-arka farkın korunmasını kontrol et.
5. Düzeltme sonrası özgün LOD0 hash/sahiplik alanları, katalog, deterministik üretim, import ve final full tekrar doğrulanmalı.

## Görsel gözlemler · açılan tüm aile sayfaları

Kaynak: `design/library/sheets/hero-lod/*-variants.png` (65m; tüm3 varyant ve3 detay seviyesi).

- old_core: LOD1 cumba/tente/çatı karakteri ve panjur rengi korunuyor; proxy çatı ayrıntısını siliyor, ön cephe tonu korunuyor. Rear hata koddan kesinleşti.
- bazaar: ahşap çıkmalar, dükkân bandı ve kiremit çatı LOD1'de okunuyor; proxy çıkmayı düzleştiriyor, renk izi kalıyor.
- res_mid: kat/balkon bantları, panjurlar ve çatı merdiveni korunuyor; proxy daha yassı ama artık siyah pencere ızgarasına dönüşmüyor.
- res_late: kat silüeti ve balkon ritmi LOD1'de korunuyor; proxy cephe ayrıntısı azalıyor, genel krem/gri oranı korunuyor.
- house: çatı, iki katlı kütle ve bahçe duvarı tüm aşamalarda tanınabilir.
- industrial: beşik/tonoz varyantı, baca ve konteyner yığını ayrı karakterini koruyor; çitin LOD1'de silinmesi görünür ama raporlu ve bu uzaklık hattının bilinen kaybı.
- civic: LOD1 saat kulesi, katlar ve giriş sütunları korunuyor; proxy saati de tutuyor, küçük kule altı açıklıkları kayboluyor. Eski T-054 kule oranı bu görevce değiştirilmemiş.

Bütün şehir, liman konumu, T0 yoğunluğu, bölge çeşitliliği, gerçek54k performansı ve otomatik geçiş pop'u bu bina lab'ından PASS ilan edilmez. Bu görev kütüphane önerisidir; kullanıcı onayı verilmiş sayılmaz.

## Bağımsız çalıştırılan komutlar

- `python3 -m unittest discover -s tests/library -p 'test_*.py' -q`:30 PASS.
- `python3 -I tools/library/validate_catalog.py`:81 kayıt/0 hata/0 uyarı.
- `python3 tools/library/hero_lods.py --check`:21 zincir/63 seviye.
- `tools/godot.sh --headless --path . --script res://tools/library/check_hero_lod_import.gd`:HERO_LOD_IMPORT_OK meshes=42 declared_texture_resources=42 (`artifacts/verify/t056/qa-import.log`).
- `tools/canon-check.sh`:11/11 hash aynı.
- `git diff --check`:temiz.
- Full ilk turu: `artifacts/verify/t056/full.log`; durdurulmuş, tamamlanmış full olarak kullanılmaz. Yalnız kendi başlattığım verifier22788 ve onun23021/23022/23023 çocukları durduruldu; başka Godot süreçleri hedeflenmedi.


## Tur2 · düzeltme doğrulaması (final full sürüyor)

Arka cephe hatası **giderildi**. Bütün7 ailede PROXY arka UV'si kaynağın yan atlasına ve0.9+0.05 kırpmasına eşit. Proxy bake artık yalnız önü değiştiriyor; kaynak yan/arka albedo korunuyor. Üçgen/VRAM bütçesi bu düzeltmeyle büyümedi.

- Bağımsız taze koşu:32 Python test PASS; katalog81/0 hata/0 uyarı; hero_lods --check21zincir/63seviye; side tile denetimi21/21; Godot runtime import42mesh/42doku kimliği; diff-check temiz.
- Regresyonun negatif yolu ayrıca bağımsız sınandı: TEMP GLB'de gerçek arka TEXCOORD_0 verisindeki4 vertex değiştirildi; aynı `test_exported_rear_mapping_matches_approved_source` başarısız oldu. Üretim dosyaları değiştirilmedi. Bu test yalnız üretici kodundaki metni veya yeniden yazılmış hash'i denetlemiyor.
- Final ağaçta81 kullanıcı alan seti ve21 özgün LOD0 GLB hash'i HEAD ile yeniden karşılaştırıldı; aynı.
- Açıldı: bütün7 `*-rear-65m.png` +`old_core-rear-300m.png`. Eski çekirdeğin arkasında kaynak gibi aralıklı sade pencere/duvar ritmi var; vitrin/panjur önü arka yüze taşınmıyor. Diğer ailelerde arka kat/pencere ritmi ve sanayi bacası korunuyor. Proxy65m'de bulanık; bu yakın tanı karesi, kullanım mesafesi iddiası değil.
- Yenilenmiş7 `*-variants.png` de tekrar açıldı (a/b/c, LOD0/LOD1/PROXY). Ön cephe tonal düzeltmesi korunuyor; yan/arka tile koruması ön karakteri bozmamış. Tüm ailelerde LOD1/proxy ana kütle/renk sürekliliği geçiyor; bağımsız sanat yönü kararı ayrı incelemede.

| Ölçüt | Tur2 güncel sonuç | Kanıt/sınır |
|---|---|---|
|1 ·21 zincir/bütçe/tekrar üretim|PASS|32 test;63 seviye dosya/bütçe kontrolü; uygulayıcı deterministik üretim kayıtları görevde. QA bütün Blender üretimini tekrar etmedi; özgün hash ve gerçek GLB ölçümlerini bağımsız doğruladı.|
|2 ·Özgün LOD0/ölçek|PASS|21 özgün hash aynı; gerçek rear vertex konumları LOD0 ile aynı; küçük silinen detaylar belgeli.|
|3 ·Görünüm/renk/cephe|PASS|Arka gerçek GLB UV testi ve21 tile piksel denetimi; ön7sayfa+arka8kare açıldı.|
|4 ·Katalog/sahiplik/scope|PASS|81 kullanıcı alan seti aynı; katalog0/0; oyun entegrasyonu yok.|
|5 ·Aynı kamera/ışık/kapsama|PASS|Lab view/yaw ile tekrarlanabilir arka görüntü; bütün aile/varyantlar mevcut.|
|6 ·Gerçek görseller/dürüst kapsam|PASS|Gerçek Godot ön/arka kareler; rapor dar lab/hesap ve gerçek54k test edilmemiş ayrımını koruyor.|
|7 ·Final full/bağımsız kapı|PENDING|İkinci full şu an çalışıyor; exec session27815, artifacts/verify/t056/full.log. Bütün ölçütler PASS olmadan done yok.|

Final `full-latest.json` sonucu ve parmak izi koşu bitince bu rapora eklenecek. Şu an broad kapı PASS sayılmıyor.


## Final kapı · PASS

İkinci bağımsız `tools/verify.sh full` **çıkış0 / result=pass** ile tamamlandı. Rapor `artifacts/verify/full-latest.json`; tam stdout `artifacts/verify/t056/full.log`. Yedi adımın tamamı `pass`; skip yok:

| Kapı | Sonuç |
|---|---|
|canon-check|11/11 foundation dosyası manifestle aynı|
|studio-check|12 ajan/17 skill/kural-hook-MCP tutarlılığı|
|gdlint|temiz|
|Godot import|temiz|
|GdUnit4|1633 test;0 hata/0 başarısızlık/0 flaky/0 skip/0 orphan;633 saniye|
|canon-guard|105 PASS/0 FAIL;83 saniye|
|runtime-smoke|gerçek ana sahne180 kare hatasız;3 saniye|

Rapor parmak izi **`c96a3ba37077f18b3c837840d01bd67b509d52ed48977e2be2f1e2f4f549de71`**, koşu sonrası `tools/fingerprint.sh` ile birebir aynı. Kanıt HEAD'i `bc6d2e961ccd2ee315f4f97d860b6233e3870154`; bu teslim henüz commit edilmediğinden rapor kaynak ağaç parmak izini esas alır.

Son kriter sonucu: **1 PASS ·2 PASS ·3 PASS ·4 PASS ·5 PASS ·6 PASS ·7 PASS**. Tur2 tablosundaki PENDING kaydı bu final sonuçla kapanır. Ayrı sanat incelemesi de `production/qa/T-056-art-review.md` kapsamında PASS; kullanıcı yeni LOD dosyalarını onaylamış sayılmaz.

Kalanlar teslim kusuru olarak gizlenmez: gerçek54k kent yükü/otomatik geçiş-pop/gölge sürekliliği ve hedef cihazlar test edilmedi; bu görev yalnız kütüphane zincirini teslim eder. Tüm kütüphane tamamlandı sonucu çıkarılmaz.
