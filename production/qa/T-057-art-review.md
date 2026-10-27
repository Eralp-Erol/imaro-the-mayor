# T-057 · Bağımsız sanat kapısı · 2026-10-27

**Verdict: FAIL — mevcut uzak proxy ışıklanması/ton sürekliliği.**

İnceleyen: uygulayıcıdan ve QA'dan ayrı Codex `art_director`. Claude Opus çalıştırıldığı iddia edilmez. Teknik testlerin geçmesi veya kayıtların `proposed` olması bu görsel kusuru geçirmez. Kullanıcı onayı ve oyun entegrasyonu verilmedi.

## İncelenen son aday

Eski `broad-trees-150m-lod.png` tarihî FAIL kanıtıdır; bu hüküm onun üzerinden verilmedi. Son 6 üçgen kaynak-türetilmiş palmiye dışı proxy'ler, 300 üçgen servi LOD1 ve değişmeyen LOD0 önerileri incelendi.

Açılan güncel yayın PNG'leri (`design/library/sheets/vegetation-hero/`):

- On tür kontağının tamamı: `veg_hero_{plane,pine_brutia,pine_stone,olive_open,olive_twisted,cypress,maquis,hedge,palm_date,palm_slender}_a.png`.
- Dört bağlam: `context-{true,street,slope,lineup}.png`.
- İki AA-off: `olive_open-scissor-no-msaa.png`, `palm_date-scissor-no-msaa.png`.
- Üç son tanı: `nonpalms-150m-lod.png`, `cypress-50m-lod.png`, `proxy-side-top-proof.png`.

Kompozitlerin küçültülmesinin kusuru gizlememesi için şu ham gerçek Godot kareleri ayrıca açıldı:

- `artifacts/screenshots/captures/20261027-010931-t057-impostor-plane-lod0-150.png`
- `artifacts/screenshots/captures/20261027-010942-t057-impostor-plane-proxy-150.png`
- `artifacts/screenshots/captures/20261027-011203-t057-edge-plane-top-lod0.png`
- `artifacts/screenshots/captures/20261027-011209-t057-edge-plane-top-proxy.png`

## A1 · Hedef uzaklıkta kart normali/kesişimi ağacın tonunu ve yüzeyini değiştiriyor — bloke edici

**Kanıt:** `proxy-side-top-proof.png`, `nonpalms-150m-lod.png` ve yukarıdaki dört ham çınar karesi. Bunlar aynı kaynak/origin/kamera/ışıkla **150 m** görüntüleridir; yazılı proxy çalışma eşiği olan >120 m'nin ötesindedir.

- Çınar kaynağı önden gölgeli/aydınlık yaprak parçaları olan hacimli bir taçtır. Son proxy aynı dış taç izini büyük ölçüde geri getirmiştir; önceki çıplak dal/ayrı üç tutam problemi artık ana kusur değildir.
- Buna karşılık kaynakta olmayan **geniş, düz, açık yeşil paneller ve koyu merkez/kesişim** proxy'nin üstüne çizilmiş gibi görünür. Bu fark yalnız yakın kontak sayfasında değil, ham 150 m ön/yan karesinde de okunur.
- 150 m üst karesinde kaynak, düzensiz ve derinliği olan yeşil taçtır. Proxy, üzerinde **belirgin koyu X bulunan düz yeşil yaprak damgasına** dönüşür. X, türün taç/dal yönü değil, kesişen kartların yüzey/ışık davranışıdır. Kent kuşbakışı için merkezde bu geometrik işaretin üretilmesi kabul edilmez.
- Zeytin ve maki kontaklarında da aynı düz panel/karşılıklı koyu-açık yüzey mekanizması görünür. Bu yakın görüntüler tek başına uzak mesafe FAIL kanıtı olarak kullanılmadı; paylaşılan temsil ailesinin birlikte yeniden kontrol edilmesi gerektiğini gösterir.

İlgili kural: **T-057 ölçüt 2** (“Tür ve taç tonu LOD'da değişmez”), ölçüt 1'de hero yanında aynı özen; **VIS-01/VIS-05** mat, okunur low-key low-poly ve üçgen/yıldız dekor görünümünden kaçınma; **WLD-01/TEK-03** kaynak nesnenin temsilini sadeleştirme. Kart veya impostor kullanmak yasak değildir; kaynakta olmayan görünür bir X/renk sıçraması üretmek kusurdur. Riski belgelemek, hâlihazırda hedef mesafede görülen hatanın giderilmesi yerine geçmez.

### Sınırlı düzeltme ve tekrar kabulü

1. LOD0 tür tasarımını, mevcut çalışma bütçesini veya 50/120 m eşiklerini değiştirmeden palmiye dışı proxy'lerin **normal/ışık/öz-gölge** davranışını düzelt. Taç yüzeyinde sabit koyu X ve geniş dikdörtgensi ton bölünmesi oluşmamalı. Uygun canopy normal yaklaşımı, kartların öz-gölgesini ayırma veya eşdeğer görünüm koruyan impostor çözümü teknik uygulayıcının seçimidir; yalnız kamera/ışığı değiştirmek çözüm değildir.
2. Aynı 150 m kamera/ışıkta çınarın ön, yan ve üst LOD0/proxy karesini tekrar üret/aç. Taç dış izi kadar **ortalama renk ilişkisi ve gölgeli/aydınlık yüzeyin** kaynağa benzerliği değerlendirilmeli. Sadece albedo tile hash'i bu ışıklanma kusurunu doğrulamaz.
3. Ortak proxy malzemesi/normal yolu değişirse bütün sekiz palmiye dışı adayın 150 m karşılaştırmasını yenile. Üst/yan kanıtında en az çınar ve mevcut çit tanısı korunmalı. Yeni tür, gece, rüzgâr veya dünya entegrasyonu istenmiyor.
4. Yeni materyal/normal/doku davranışının maliyetini ve gerçek Godot import durumunu odaklı doğrula; bunun ardından bağımsız sanat kapısı tekrar verilsin. LOD0'lar ve önceki 81 kayıt korunmalı.

## Geçen yönler — yeniden tasarım istenmiyor

| Konu | Gözlem / hüküm |
|---|---|
| Tür ayrımı · LOD0 | **PASS öneri yönü:** çınar daha yuvarlak/derin; fıstık çamı yatay şemsiye; kızılçam düzensiz dik taç; zeytinler gümüşi ve yayvan; servi dar sütun. İki palmiye gövde/taç oranıyla ayrılıyor; maki ve çit alt ölçek dolduruyor. Botanik doğruluk veya kullanıcı seçimi verilmez. |
| Hero ile dil / ölçek | **PASS öneri yönü:** `context-true/street/slope` karelerinde muted zeytin, mat gövde ve yeşil palmiye hero cephesiyle aynı sakin dokulu ailede. 1.75 m figür ve korunmuş bina, bitkileri büyük oyuncak aksesuar gibi göstermiyor. Ölçümlerin teknik denetimi QA raporunda. |
| Servi LOD1 düzeltmesi | **PASS:** `cypress-50m-lod.png` içinde 300 üçgen sürüm sürekli dar sütunu koruyor; önceki çıplak gövdeli ayrı yaprak adaları sorununa dönmüyor. 50 m proxy tanısı kullanım mesafesi diye sunulmadı. |
| Önceki taç kaybı | **Düzeldi:** sekiz adayın 150 m sayfasında kaynak-türetilmiş proxy taç dış izini geri getiriyor. Bu, A1 ışık/ton sorununun geçmesi anlamına gelmiyor. |
| Alpha / AA dürüstlüğü | İki AA-off karesi açıldı; ince yaprak/frond kenarları tırtıklı. 4×MSAA lab görüntüsü cihaz profili kanıtı sayılmıyor; bu risk raporlanmış. Yeni bir AA gereksinimi eklenmedi. |
| Palmiye LOD tanısı | Yakın kontakta proxy daha seyrek ve frond sayısı az; bu kareden 150 m palmiye kalitesi için kesin hüküm çıkarılmadı. Mevcut bloke edici A1 palmiye dışı ortak temsil üzerindedir. |

## Visual-gate kapsam eşlemesi

- **F04-Q1/Q4:** bina ve bitki önerileri ölçeğinde Ege/çok dönemli hero diliyle uyum olumlu. Tam çağdaş metropol, yaşayan toplum veya tarım sistemi kanıtı değildir.
- **F04-Q2/Q3/Q5:** T0 çekirdek yoğunluğu, liman/ada coğrafyası ve gelecekte büyüme bu kütüphane laboratuvarında değerlendirilmez.
- **F04-Q6 / tek dünya:** aynı kaynak ölçüsü korunmuş; fakat hedef uzaklıktaki mevcut taç yüzey dönüşümü nedeniyle bütün LOD sanat sürekliliği PASS değildir.
- **Ölçek/stil:** öneri LOD0 yönü geçiyor. Proxy'nin hedef mesafedeki geometrik X'i stil ve temsil sürekliliğini bozuyor.
- **Yoğunluk/tekrar/HUD:** bağlam kareleri az sayıda laboratuvar nesnesidir; yoğun kentte çeşitlilik, okunurluk veya HUD sonucu çıkarılmaz. Ürün HUD'ı yoktur.
- **Işık:** sade aynı gün ışığıyla tanı var; bu nedenle A1 başka güneş açısıyla gizlenmemeli. Hareketli ışık ve gece testi bu düzeltmenin önkoşulu değildir.

## Görev kararı

Görsele ilişkin ölçüt 1, LOD0 öneri yönünde olumlu; ölçüt **2 FAIL** (hedef mesafede taç ton/yüzey sürekliliği). Ölçüt 5 gerçek kanıt ve risk açıklaması bakımından mevcut, fakat A1 görüntüsü hazır sanat teslimi değildir. Teknik ölçütler için bağımsız QA raporu esas alınır; final full henüz PASS değildir.

**T-057 şu hâliyle done veya sanat PASS olarak kapatılamaz.** Kaynak bitki önerileri korunarak sınırlı uzak temsil düzeltmesi istenir; tüm kütüphaneyi, bina hero'larını veya bitki türlerini yeniden başlatma talebi yoktur.


## Karar 3 · Kapalı kaynak-taç kabuğu — bağımsız sanat FAIL · 2026-10-27

**Kesin verdict: FAIL. Uzak temsil mimarisi çözülememiştir; T-057 sanat kapısı kapalı kalır.** Bu sonuç, doğru geometri/import ve deterministik kaynak tarifinin görsel yeterlilik yerine geçmediğini gösterir. Yeni renk/normal/destek/alpha ayar turu veya diğer türlere yayma istenmez. Teknik karar 3'ün sonlu durma koşulu gerçekleşmiştir.

### Gerçekte açılan kanıt

`production/qa/T-057-technical-review.md` Teknik karar 3 ve `experiments/t057-proxy-shell/README.md` okundu. `experiments/t057-proxy-shell/comparison.png` açıldı; ardından `frames.json` içindeki **10 son düzeltilmiş 1600×900 PNG'nin tamamı tek tek açıldı**. İlk beyaz import kareleri (`invalid-white-frames.json`) hüküm için kullanılmadı.

Aşağıdaki dosyaların ortak dizini `artifacts/screenshots/captures/`; tam yollar ve tekrar komutları `experiments/t057-proxy-shell/frames.json` içindedir:

| Koşul | Kaynak kare | Son aday kare | Gözlenen sonuç |
|---|---|---|---|
| Ön · 150 m · güneş +0° | `20261027-142114-t057-shell-final-plane-front-lod0-150-sun0.png` | `20261027-142119-t057-shell-final-plane-front-proxy-150-sun0.png` | Kaynaktaki düzensiz, parçalı yuvarlak yaprak tacı; sivri üstlü, geniş düz yüzlü koyu geometrik kütleye dönüyor. Kaynağın yaprak/faset renk değişimi ve taç boşlukları kayboluyor. |
| Yan · 150 m · güneş +0° | `20261027-142123-t057-shell-final-plane-side-lod0-150-sun0.png` | `20261027-142128-t057-shell-final-plane-side-proxy-150-sun0.png` | Kaynak çınarın loblu dış çizgisi yerine keskin üçgen/çokgen kenarları ve kapalı dolu hacim okunuyor. Çınarın kaynak tür karakteri korunmuyor. |
| Üst · 150 m · güneş +0° | `20261027-142133-t057-shell-final-plane-top-lod0-150-sun0.png` | `20261027-142139-t057-shell-final-plane-top-proxy-150-sun0.png` | Kart X'i yok; fakat yerini açık/koyu birkaç büyük düz yüze bölünmüş, deliksiz koyu yeşil çokgen alıyor. Kaynağın yaprak kümeleri ve aralıkları olan üst görünümüyle aynı sanat grameri değil. |
| Ön · 150 m · güneş +60° | `20261027-142145-t057-shell-final-plane-front-lod0-150-sun60.png` | `20261027-142151-t057-shell-final-plane-front-proxy-150-sun60.png` | Kaynakta yaprak ışığı/ton değişimi görülüyor. Aday gerçek 3B yüzeylerle ışık alabilse de büyük koyu geometrik taç ve kayıp yaprak karakteri sürüyor. Bu, yanlışlıkla unlit çalıştığı iddiası değildir; meşru 3B ışık tepkisi tek başına yeterli değil. |
| Ön · 120 m · LOD1 → aday sınırı | `20261027-142157-t057-shell-final-plane-front-lod1-120-sun0.png` | `20261027-142204-t057-shell-final-plane-front-proxy-120-sun0.png` | Kaynak LOD1'in dağınık/loblu yaprak tacından koyu dolu çokgene, dallanmış gövdeden çok sade koyu sapa ve parçalı gölgeden dolu koyu lekeye belirgin görsel sıçrama var. Bu, hareketli geçiş testi değil; eşik mesafesindeki sabit çiftte süreklilik kusuru zaten görülebiliyor. |

### Ölçüt hükmü

- **T-057 ölçüt 1/2, VIS-01/02/05, WLD-01/TEK-03 açısından FAIL:** dış destek noktalarının kaynak alpha-valid yapraklardan gelmesi kabuğun kaynak tür silüetini, taç içi boşluklarını, yaprak/faset dağılımını ve ton ilişkisini koruduğu anlamına gelmiyor. Aday aynı yaklaşık konum/ölçekte başka bir geometrik ağaç estetiği gibi okunuyor. Sakin low-poly yön, onaylanmış dokulu hero/bitki kaynağını bu açık mesafede dolu piramit/çokgene dönüştürme yetkisi değildir.
- **Düzelen şey:** çapraz kartın X/dikiş sorunu bu adayda yok; gerçek kapalı hacim ve gölge alma/verme var. Buna rağmen asıl kaynak temsil sürekliliği geçmedi.
- **Teknik olarak raporlanan, bu incelemede yeniden test edilmeyen şeyler:** 36 üçgen/kapalı outward bileşenler, kaynak destek ve lineer renk provenance'ı, gerçek ithal opaque vertex-color malzemesi, deterministik üretim ve eski varlıkların korunması. Bunlar teknik audit'in alanıdır; burada bozuk oldukları iddia edilmedi ve sanat PASS yerine kullanılmadı.
- **Korunan kabul:** önceki LOD0 öneri yönü, bitki metre ölçeği ve servi LOD1 iyileşmesi bu çınar uzak temsil deneyinin FAIL'iyle iptal edilmez. Bina hero'ları veya kaynak LOD0 yeniden tasarlanmaz.

### Sonlu durma / devir

Bu doğru kapalı-shell uygulaması mevcut 40 üçgen üst sınırı ve 50/120 m çalışma eşikleri içinde gerekli sanat sürekliliğini sağlamadı. **Çözülmemiş uzak temsil mimarisi bloke edicidir.** Bu rapor üçüncü bir geometri/renk kalibrasyonu, yeni capture, tam batch veya final full başlatma yetkisi vermez. Deney ve tarihî başarısız temsiller kanıt olarak korunmalı; görev/STATE/QUEUE ve güvenli duraklama kaydını Studio Director tamamlamalı. Daha sonra çalışma yeniden yetkilendirilirse sonraki mimari yaklaşım ayrı teknik karar ve kaynakla aynı görsel kabul koşulları gerektirir. T-057 done, kullanıcı onaylı veya sanat PASS değildir.
