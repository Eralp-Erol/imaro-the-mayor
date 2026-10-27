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


## Karar 5 · Palmiye dışı zincir LOD0→LOD1 (leke ayrı görev) · mahalle lab · bağımsız sanat · 2026-10-27

İnceleyen: `art-director` (Claude Opus), uygulayıcıdan bağımsız. Godot çalıştırılmadı; yalnız mevcut kareler ve lab betiği okundu. **Bu hüküm kullanıcı onayı değildir.**

**Verdict: PASS WITH FIXES (koşullu)**: Palmiye dışı 8 türün LOD0→LOD1 varlık çifti sanat yönünden kabul edilebilir. 400 m sınırı ve 120 m geçişi bu kanıtla doğrulanmadı (kanıt yok). Blob önizlemesi sanat olarak kabul edilmedi.

**Açılan dosyalar (tek tek):** `artifacts/screenshots/captures/20261027-182139-nbhd-150-lod1.png`, `…-182147-nbhd-300-lod1.png`, `…-182156-nbhd-900-lod1.png`, `…-182206-nbhd-300-blob.png`, `…-182216-nbhd-900-blob.png`; yakın kırpımlar (yalnız inceleme, scratchpad); `design/library/sheets/vegetation-hero/veg_hero_{plane,olive_open,pine_brutia,cypress,hedge}_a.png`; `assets/hero/vegetation/neighborhood_lab.gd`.

**Gözlenen kritik kanıt kusuru:** `neighborhood_lab.gd` `_place_trees()` seviyeyi **kameraya değil dünya merkezine (kamera hedefi) uzaklığa** göre seçiyor (`Vector2(pos.x,pos.z).length()`), ve seçim yalnız B tuşunda yeniden çalışıyor. HUD üç lod1 karesinde de aynı: `45 LOD0 · 305 LOD1 · 0 leke`. Yani kareler zinciri değil, merkez çevresinde sabit 120 m/400 m halkalarını gösteriyor. 900 m karesinde hiç leke yok, 400 m sınırı karede hiç bulunmuyor. Merkezdeki 45 ağaç ise kamera 900 m uzaktayken bile LOD0.

1. **150/300 m LOD1:** Kapı, panel, X, şerit veya kart dikişi görülmedi. Çınar (yuvarlak loblu), zeytin (alçak geniş), servi (dikey) ve palmiyeler hâlâ ayrışıyor. Taç kütlesi ve gölge yaprak deseni korunmuş. Kareler içinde LOD0 ile LOD1 ağaçlar arasında göze çarpan ton veya biçim sıçraması yok (halkanın sınırı karede seçilemiyor). Kontak sayfalarında LOD1'in kayıpları görülüyor: çınarın tepesinde sivri bir kart çıkıntısı var, ton biraz açılıyor. Zeytin tacı ayrık kümelere bölünüyor ve açılıyor. Çit LOD1 sürekli çit değil, aralıklı tek tek fidan dizisi gibi okunuyor. Servi LOD1 neredeyse aynı (316→300 üçgen, tasarruf yok; teknik not). Zaman içindeki 120 m geçişi **test edilmedi**, çünkü statik halka anlık geçiş (pop) kanıtı değildir.
2. **900 m:** Karede gerçekte tümü LOD0/LOD1 olan ağaçlar var. LOD1 ağaçlar kentte küçük koyu benekler olarak, seyrek ama doğal okunuyor ve kabul edilebilir. LOD1+leke karışımı ve 400 m sınırı bu karede **yok, kanıt yok**.
3. **lod1 ve blob karşılaştırması:** 300 m'de lod1 açıkça daha tutarlı. Blob doygun, düzgün yeşil küreler; palmiye ve servi de top oluyor, yani tür kayboluyor. Aynı adada LOD0 ağaçların yanında oyuncak gibi duruyor (VIS-05 "toy" riski). Ayrıca 120 m halkası çok belirgin. 900 m'de blob "yeşil var" mesajını LOD1 beneklerinden daha iyi veriyor. Ama LOD1 yaprağından daha açık ve doygun, bu yüzden merkezdeki koyu LOD0 kümesiyle sınırı seçiliyor. **Öneri:** "120 m ötesi hepsi leke" uygulanamaz. LOD1 orta mesafede korunsun. Leke/HLOD yalnız LOD1'in zaten benek okunduğu uzaklıkta, LOD1 yaprak tonunda (daha koyu, daha az doygun) ve tek ağaç küresi yerine hücre ölçeğinde düzensiz taç kütlesi olarak başlasın. Sınırın 400 m olup olmadığına bu karelerden karar verilemez.

**Koşullar (T-057 sanat PASS'i için):**
- K1: Lab, seviyeyi her ağacın **kamera konumuna** uzaklığıyla ve kamera değiştikçe seçsin. 150/300/900 m kareleri aynı tohum ve aynı açıyla yeniden alınsın. HUD sayıları ön ayara göre değişmeli, 900 m karesinde 400 m sınırı görünür olmalı.
- K2: 120 m eşiğinde aynı kamerayla LOD0/LOD1 çifti alınsın (`tools/visual-diff.sh`). En az çınar, zeytin (açık) ve çit için. Sivri tepe veya ton sıçraması varsa yalnız ilgili LOD1 düzeltilsin, LOD0 yeniden tasarlanmasın.
- K3: Blob önizlemesi varlık değildir ve kabul edilmedi. HLOD görevinin kabulü yukarıdaki ton ve kütle ilkesine bağlansın.
- Not: Palmiyelerin uzak proxy'si bu incelemede ayrıca değerlendirilmedi. 300 m lod1 karesindeki "4 fps" HUD değeri performans hükmü değildir (ölçülmedi). Bina hero'ları, zemin ve yollar bu kararın kapsamı dışındadır.

### Studio Director takibi · art-director koşullarının karşılanması (2026-10-27) — sanat hükmü DEĞİL
- **K1 karşılandı:** `neighborhood_lab.gd` artık seviyeyi her ağacın KAMERAYA uzaklığına göre seçer ve kamera/B tuşu değiştikçe yeniden seçer (önceki dünya-merkezi seçimi hatalıydı; art-director'ın bakıp "sabit halka" bulduğu ilk 5 kare `…182139…182216-nbhd-*.png` geçersiz sayıldı ve silindi — hüküm metnindeki o dosya yolları artık yok). Yeni kareler: `artifacts/screenshots/captures/20261027-182547-nbhd-150-lod1.png`, `…182556-nbhd-300-lod1.png`, `…182605-nbhd-900-lod1.png`. HUD sayıları artık kademeye göre değişir (900 m karesi: 0 LOD0 · 0 LOD1 · 350 leke). Yeni karelerin bağımsız sanat incelemesi yapılmadı; art-director verdict'i "PASS WITH FIXES (koşullu)" olarak kalır.
- **K2 (120 m LOD0/LOD1, aynı kamera, tools/visual-diff.sh, fark pikseli/1,44M):** çınar 4711 (%0,327), açık zeytin 1329 (%0,092), çit 358 (%0,025). Çınar ve zeytin çiftleri yan yana açıldı (montaj /private/tmp/claude-501/k2/*.png, kalıcı yol `artifacts/screenshots/captures/*k2-{plane,olive_open,hedge}-lod{0,1}-120.png`); 120 m'de iki seviye gözle ayırt edilemiyor. Çit çiftinin montajı açılmadı (yalnız sayısal fark). Kontak sayfalarında bildirilen LOD1 kayıpları (çınar tepe çıkıntısı, zeytin tacı açılması, çit aralıklı fidan, servi 316→300) YAKIN mesafede kalır; 120 m ve ötesinde bu karelerde görünmez. Düzeltilmedi; LOD1 yakın-kalite iyileştirmesi ayrı iş olarak not edildi (LOD0 yeniden tasarımı yok).
- **K3 kabul:** yeşil leke gerçek varlık/sanat değil; hücre lekesi/HLOD görevi art-director ilkesine bağlanır (LOD1'e yakın ton, düzensiz kütle, tek tek küre değil). Önerilen: "120 m ötesi hepsi leke" uygulanmaz; LOD1 orta mesafede kalır. 400 m sınırı bu karelerden doğrulanmış değildir (çalışma tercihi).
- **Doğrulanmayan:** hareketli 120 m LOD geçişi (kare indeksine bağlı dolly), sınır 400 m, performans, iPad.
