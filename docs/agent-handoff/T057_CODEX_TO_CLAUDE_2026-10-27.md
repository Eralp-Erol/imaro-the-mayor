# T-057 · Codex → Claude devir — 2026-10-27

Bu belge teşhis, kanıt ve önerileri devreder. **T-057 tamamlanmadı; blocked / sanat FAIL.** Çalışma safe pause durumunda. Bu belgeyi yazmak üretimi yeniden başlatmaz. Kopyalanabilir devam talimatı aynı dizindeki `T057_CLAUDE_PROMPT.md` dosyasındadır.

## 1. Doğru checkout ve güvenli başlangıç

- Worktree: `/Users/eralperol/Documents/Projects/imaro-the-mayor-handover-imaro-m01-349562fb`
- Dal: `agent/handover-imaro-m01-349562fb`
- Devir öncesi son çalışma commit'i: **1c9c3c0**, `WIP T-057: uzak temsil sanat FAIL kanıtları ve safe pause`.
- Önceki duraklama: `37d2d2b`. Son tamamlanmış teslim: **fe89e29 / T-056**.
- Ana checkout `/Users/eralperol/Documents/Projects/imaro-the-mayor`, eski `dev/m1-parallel` dalındadır. Orada bu işe başlamayın; checkout'u değiştirmeyin.
- `~/.local/state/imaro-autonomy/STOP` mevcut; `lock.json` bırakıldı. Uygulayıcı aktif süreci olmadığını bildirdi; koordinatörün test süreci de tamamlandı. Yeni kullanıcı devam talimatı olmadan üretim başlatmayın.
- Worktree'de önceden var olan izlenmeyen `artifacts/library/` ve `tmp/` korunuyor. Ana checkout'ta önceden var olan `artifacts/verify/m01-report.json` korunuyor. Bunları temizlemeyin veya topluca commit'lemeyin.

Önce `CLAUDE.md`, `production/STATE.md`, `production/tasks/T-057.md` ve bu belgeyi okuyun. Projenin kendi dev-task / canon-check / blender-asset / visual-gate / handoff akışını kullanın. Kullanıcının tercihi **tek uzman, sıralı çalışma; aynı anda tek Godot**. Önemli aşama sonunda safe pause yapın. Codex rol ajanlarının incelemeleri repo dosyalarına kaydedildi; bunlar gerçek Claude Opus/Sonnet çalıştırmaları olarak sunulmuyor.

## 2. İstenen sonuç ve korunacaklar

Kütüphane tamamlanmadan dünyaya yeni varlık eklenmeyecek. Bu çalışma yalnız proposed asset/lab üretimidir; oyun entegrasyonu veya kullanıcı estetik onayı değildir.

- T-056: 21 kaynak bina hero'su korundu, 42 LOD modeli ve 21 proxy atlası teslim edildi. Bağımsız QA/sanat/full geçti. Yeniden tasarlamayın.
- T-057: 10 bitki önerisi / 30 GLB: çınar, iki palmiye, kızılçam, fıstık çamı, iki zeytin, servi, maki ve çit.
- LOD0 yönü, metre ölçeği ve düzeltilen servi LOD1 sanat incelemesinde olumlu. Sorun bütün bitki tasarımını baştan yapmayı gerektirmiyor.
- Bloke edici sorun palmiye dışı uzak temsil ailesi üzerinde. Son iki izole deney yalnız çınarda yapıldı; bu sonuçlardan palmiyelerin bütün uzak açıları geçti sonucu çıkmaz.
- Önceki 81 kayıt, 67 GLB, 14 PNG ve 10 bitki LOD0 hash'i korundu. Katalog toplamı 91 kayıt. Eski kayıtların hepsini kullanıcı onaylı saymayın.
- Q-018 bitki/palmiye/mevsim seçimleri ve T-055 zemin değerlendirmesi açık. Kullanıcının “devam” demesi bunları onaylamaz.
- T-058 donatı, T-059 insan stil önerileri, T-060 araç, T-061 yol kesiti yalnız brief; uygulanmadı. T-057 bağımlılığı ve safe pause nedeniyle sonraki kategoriye geçilmedi.

## 3. Sorun tam olarak nedir?

Yakındaki bitki, ayrı yaprak kümeleri, kümeler arasındaki boşluklar, düzensiz dış çizgi, dallanma ve küçük aydınlık/koyu yüzeylerle okunuyor. Uzak modelin üçgen sayısını azaltırken **aynı bitki olarak okunması** gerekiyor. Şu ana kadarki uzak temsiller bunu başaramadı.

### A. Üç çapraz kartta görünüm ve yüzey sürekliliği bozuluyor

Kaynak ağacın ön/yan/üst albedo+alpha görüntüleri üç dik düzleme yerleştirildi: toplam 6 üçgen. Dış taç izini, ilk seyrek proxy'ye göre geri getirdi; fakat bu düzlemler gerçek bir yaprak hacmi değil.

- Düzlem yönleri ve kesişimler ışık/gölge altında X, panel ve dikiş izleri üretti.
- Her kartın ayrı UV/normal alanı aynı fiziksel kesişim noktasında farklı yüzeyler seçiyordu. Bu somut adresleme kusuru ayrıca giderilip sınandı.
- Fakat ortak RGB/normal alanı doğru hale getirildiğinde de kendi kartına ait alpha/görünürlük/derinlik yapısı ve eksik hacimsel bilgi sorunu sürdü. Kart sınırı ve ton/kontrast kaybı görünür kaldı.
- Son F(P,C) deneyinde aynı fiziksel noktada RGB/normal farkı **0**; affine projeksiyon hatası **1.39e-17**. Buna rağmen gerçek görüntü FAIL. Sorunu yalnız yanlış UV, gamma veya eksik normal diye yeniden teşhis etmek mevcut kanıtı görmezden gelir.

Bu bulgular **sınanan üç eşzamanlı kart mimarisini** reddeder; bütün impostor tekniklerinin imkânsız olduğunu göstermez.

### B. Tek kapalı taç kabuğu gerekli yaprak yapısını siliyor

Yeni mimaride kaynak alpha-geçerli yaprak noktalarından kapalı bir convex hull üretildi. Kesişen düzlemler tamamen kaldırıldı; gerçek geometri normalleri ve normal gölge alma/verme kullanıldı.

Ancak tek convex hull, kümeler arasındaki girintileri ve boşlukları dolduruyor. 24 üçgenlik taç birkaç büyük düz yüzeye dönüşüyor. Kaynak renkleri doğru olsa da gerçek yüzey yönleri ve gölgelenme artık yaprak kümelerine değil bu büyük kapalı yüzeylere ait. Sonuç koyu, dolu, sivri/çokgen bir hacim ve dolu bir zemin gölgesi.

150 m'de fark görünür; 120 m'de LOD1 ile adayın sabit çiftinde belirgin kütle/ton/gölge sıçraması var. Hareketli kamera geçişi ayrıca test edilmedi; sabit çift zaten kabulü geçmiyor. Kabuğu biraz açmak veya rengini parlaklaştırmak kaybedilmiş boşlukları ve yaprak geometrisini geri getirmez.

### C. Çalışma hedefi gereğinden agresif olabilir — henüz ölçülmüş sonuç değil

**40 üçgen proxy üst sınırı ve 50/120 m LOD mesafeleri kullanıcı kanonu değildir.** Bunlar bu görev için seçilmiş teknik çalışma değerleridir. Görevde ağaç bütçesi 1800/300/40, çalı/çit 600/120/24 olarak yazıldı.

Bu hedefleri iterasyon sırasında sessizce değiştirip FAIL'i gizlememek doğruydu. Ancak yeni mimari kararda bunları fiziksel zorunluluk gibi korumak gerekmiyor. 120 m'deki 14 m çınar, mevcut kamera ve çözünürlükte yaprak kütlesi farkı açıkça görülebilecek kadar büyük. Kesin ekran piksel eşiği ve cihaz maliyeti henüz ölçülmedi.

**Kanıtlanan:** denenen iki temsil ailesi mevcut koşullarda yetersiz.
**Kanıtlanmayan:** 40 üçgenle herhangi bir çözümün imkânsız olduğu; 120 m'de proxy'nin performans için zorunlu olduğu; daha yüksek üçgenli bir ara LOD'un kent/iPad bütçesini bozacağı.

## 4. Denenen yollar ve sonuçları

| Yol | Teknik/görsel sonuç | Devamda yapılmaması gereken |
|---|---|---|
| Az sayıda ayrı yaprak yaması | Uzakta taç kütlesi kayboldu; QA FAIL | Aynı seyrek yamaları geri getirmek |
| Kaynak ön/yan/üst üç çapraz kart, 6 tri | Dış taç geri geldi; koyu X/panel ve ton farkı | Bütçe geçti diye teslim etmek |
| Konumdan sentetik taç normali, skaler AO | X azaldı; kaynak faset/ton yerine düz/açık görünüm | AO/tint parametre taraması |
| Gerçek kaynak nesne-uzayı normal atlası | Normal verisi/ışık çeşitliliği geri geldi; yan dikiş sürdü | Yeniden aynı normal bake'ini yapmak |
| Ortak F(P,C) RGB+normal alanı | Adresleme/süreklilik teknik olarak doğrulandı; şerit/kenar ve ton kaybı sürdü | Alpha/ağırlık keskinliği ile üç-kart tuning döngüsü |
| Kapalı kaynak 3D shell, 36 tri | Geometri/import/determinism doğru; dolu geometrik taç, sanat FAIL | Destek yönü/renk ayarıyla tek hull'u cilalamak |

Son shell: 7,440,320 alpha-geçerli kaynak texel örneği → 14 destek → 24 taç + 8 gövde + 4 çatal üçgeni. Üç kapalı, outward bileşen; gerçek flat normaller; kaynak örneklerden lineer renk. İki tam üretimde GLB ve provenance hash'leri aynı. Gerçek import: bir opaque materyal, sıfır sampler; normal gölge alma/verme. Bunlar teknik doğruluğu gösterir, görsel yeterliliği değil.

İlk shell kareleri Godot'un vertex rengini albedoya katmaması yüzünden beyazdı. Adaya özel post-import ile `vertex_color_use_as_albedo=true`, `vertex_color_is_srgb=false` düzeltildi; son kareler yeniden alındı. **Beyaz kareler çözülmüş import hatasıdır; güncel sanat FAIL'inin sebebi değildir.**

## 5. Kanıtı hızlı bulma sırası

1. `production/qa/T-057-art-review.md` — son **Karar 3** bölümü ve 10 kare tablosu.
2. `experiments/t057-proxy-shell/comparison.png` — son düzeltilmiş karelerin karşılaştırması.
3. `experiments/t057-proxy-shell/frames.json` — 10 gerçek PNG yolu ve tekrar capture komutları; hepsini açın.
4. `experiments/t057-proxy-shell/README.md` — kaynak tarifi, ölçüm, import düzeltmesi ve sınırlamalar.
5. `experiments/t057-proxy-shell/{audit,determinism,preservation,negative-results,provenance}.json`.
6. `experiments/t057-proxy-normals/FPC-REPORT.md`, `fpc-comparison-150m.png`, `fpc-frames.json` — reddedilen kart mimarisinin son doğru adresleme deneyi.
7. `production/qa/T-057-technical-review.md` — üç teknik karar, deney kapsamları ve durma kuralları.
8. `production/qa/T-057-review.md`, `design/library/vegetation-hero.md` — önceki teknik QA, tüm türler, lab/üretim hattı. Tarihî sonuçları son adayın kabulü diye okumayın.

Son ham kareler `artifacts/screenshots/captures/20261027-142114-...` ile `20261027-142204-...` aralığında; 150 m ön/yan/üst ve güneş+60°, ayrıca 120 m LOD1/aday çifti. `invalid-white-frames.json` geçersiz ilk seti ayırır. `broad-trees-150m-lod.png` de tarihî başarısız kanıttır; güncel teslim değildir.

Lab gerçek runtime sahnesidir; ürün şehrine entegrasyon değildir. Galeri üreticisi `tools/library/build_gallery.py`, mevcut offline çıktı `artifacts/library/t056-gallery.html`; reddedilen son deneyler onaylı galeri teslimi gibi yayımlanmadı.

## 6. Önerilen yeniden başlangıç — uygulanmış veya onaylanmış çözüm değildir

### Öncelik 1: Temsil gereksinimini performans varsayımından ayırın

Önce mevcut LOD1'i görsel ve maliyet tabanı kabul edin. Aynı nesnenin farklı kamera/çözünürlüklerdeki ekran kaplamasını ölçün. Mevcut LOD1'i 120–150 m'de korumanın temsil sayısı başına üçgen, draw call, materyal ve alpha-overdraw maliyetini karşılaştırın. Tek ağaç mikro ölçümüyle kent veya iPad bütçesi geçti demeyin; mevcut platform/ADR rejimini kullanın.

Yeni teknik kararda gerektiğinde ara LOD bütçesi veya LOD politikası açıkça revize edilebilir. Kabulü gizlemek için kötü adayı uzağa itmekten farklı olarak, önce görsel olarak uygun temsil seçilip sonra görünür ekran hatası ve gerçek maliyetle eşik belirlenmeli. Eski 120/150 m karşılaştırmalarını tanı tabanı olarak koruyun; önceki FAIL'i sonradan PASS diye yeniden etiketlemeyin.

### Öncelik 2: Yakın/orta mesafede kaynak yaprak kümelerini koruyan ara LOD

Tercih ettiğim ilk aday, mevcut LOD1'den kaynaklanan ve kümeleri/alpha boşluklarını koruyan bir ara modeldir. Dal ve küçük yaprak sayısı azaltılabilir; bütün taç tek convex hull'a kapatılmamalı. Kaynak alpha-aware kart/küme geometrisi, kendi gerçek yerel konumu ve geçerli normalleriyle korunabilir. Gerekirse tek hull yerine birkaç kaynak kümesi kullanılabilir; bunun silüet, boşluk, ton ve maliyeti ayrıca sınanır.

Burada “40 yetmiyor, rastgele çok yükseltelim” önerilmiyor. Önce küçük bir adayla görsel kaybın hangi noktada kabul edilebilir kaldığını ve bunun gerçek maliyetini bulun. Daha yüksek bir çalışma bütçesi seçilirse gerekçesi, ölçümü, katalog ve test sözleşmesi birlikte güncellensin. Bu önerinin henüz uygulaması/performans kanıtı yok.

### Öncelik 3: Gerçekten küçük ekran kaplaması için ayrı çok görünüşlü impostor

Gerçek uzaklıkta gerektiği kanıtlanırsa, üç görüntüyü sürekli çapraz sergilemek yerine kamera yönüne göre kaynak görünümlerini seçen bir impostor ayrıca değerlendirilebilir. Kaynak normal/depth/ışık/gölge tutarlılığı, üstten ve çapraz bakış, dönme/geçiş, doku belleği, sampler ve overdraw maliyeti baştan tanımlanmalı. Mevcut sayısal normal bake/eksen/gamma testleri araştırmada yararlı olabilir; başarısız F(P,C) shader'ını aynen taşımak zorunlu değil.

Bu daha büyük bir renderer yatırımı olabilir. En küçük çözüm olduğu veya iPad'de daha hızlı olacağı henüz gösterilmedi; ilk otomatik tercih yapmayın. Uygulama/API seçerseniz kurulu Godot sürümü, yerel motor referansı ve gerektiğinde resmî dokümanla doğrulayın.

### Yürütme sınırı

Tek çınar, tek yeni hipotez ve yazılı durma koşulu. Önce kaynak/aday gerçek görüntü; sonra temsil ailesine yayma. İlk doğru aday sanat kabulü alamazsa nedenini ayırın, yeniden aynı parametre turuna dönmeyin. Doğru uygulanmış iki farklı temsil ailesinin başarısız olması temel varsayımı gözden geçirmek için yeterli uyarıdır; bütün bitki kütüphanesini yeniden tasarlamak için gerekçe değildir.

## 7. Kod ve testlerde devir tuzakları

- Ana 8 palmiye dışı proxy'nin `.glb.import` dosyaları hâlâ `proxy_import.gd` / `proxy_canopy.gdshader` üzerinden **sanat kabulü almamış** sentetik normal/AO politikasını kullanıyor. Ana dizinde bulunması onu kabul edilmiş çözüm yapmaz.
- `tools/library/check_vegetation_import.gd` ve ilgili testler bu mevcut politikayı denetliyor; shader metnindeki `AO = 0.55`, `AO_LIGHT_AFFECT = 0.75`, `local_position - canopy_center` gibi uygulama ayrıntılarını arıyor. Yeni mimari bunları taşımak zorunda değil. Yeni temsil için audit sözleşmesini dürüstçe değiştirin: gerçek mesh/material/import/gölge/kaynak bütünlüğü ve anlamlı negatif testler. Sırf test yeşil olsun diye reddedilen shader parçalarını tutmayın; kalite denetimini de kaldırmayın.
- Ana katalog mevcut çapraz kart varlıklarına işaret eder. İzole shell ve normal adayları kataloğun kabul edilmiş LOD'ları değildir.
- `art/blender/vegetation/rebuild.sh` mevcut batch sırasını kurar: atlas → base-only → albedo bake → pack → proxy-only → katalog. **Bu komut yeni shell/normal mimarisini üretmez; şu an reddedilen ana kartları tekrar üretir.** Yeni temsil benimsenirse üretim/rebuild/provenance/katalog/import denetimi birlikte güncellenmeli.
- Wrapper için bash-n ve altkomut sırası kontrol edildi; 33 dosyalık üretim sırası byte-eşit sınandı. Wrapper'ın kendisi ayrıca uçtan uca yeniden çalıştırılmadı. Bu ayrımı koruyun.
- Paylaşılan atlasın üst 512 satırı kaynak bark/yaprak/frond; alttaki y640–1023 bölgesi kart bake tile'larıdır. Tek türe ait atlas-reset komutu diğerlerinin tile'larını bozabilir; mevcut batch tarifini anlamadan çalıştırmayın.
- `assets/hero/vegetation/{normal_experiment,shell_experiment}/` gerçek ithal adaylar; `experiments/` altındaki üretici/raporlar ayrı. `experiments/.gdignore` nedeniyle runtime sahne/scriptlerini oraya koymayın. Dosya kaynaklarını okumakla runtime resource import'u aynı şey değildir.

## 8. Doğrulanan ve doğrulanmayan durum

**Doğrulanan:** son koordinatör koşusunda 47 kütüphane testi, 0 hata, 19.158 s. Log: `artifacts/verify/t057/shell-checkpoint-focused.log`. Shell dosya/runtime audit, iki negatif denetim ve iki üretim determinismi geçti. Koruma sonuçları shell `preservation.json` içinde. Önceki ana batch için 45 test / 33 dosya tekrarı / 91 kayıt / gerçek 30 bitki + 42 bina import QA'sı tarihli raporda mevcut.

**Geçmeyen:** son bağımsız sanat kapısı; T-057 ölçütlerinin bütünü. Son adayın kaynak taç/tür/ton sürekliliği yok. Kullanıcı bu bitkileri seçmiş/onaylamış değil.

**Çalıştırılmayan:** T-057 final full, hareketli LOD geçişi, yoğun kent / gerçek iPad performans kabulü. T-057 için eski T-056 full sonucunu kullanmayın.

`artifacts/verify/full-latest.json` T-056'ya aittir: 1633 test / guard105 / runtime180. Fingerprint'i `c96a3ba37077f18b3c837840d01bd67b509d52ed48977e2be2f1e2f4f549de71`; son T-057 WIP fingerprint'i `7a539821510dad6fe778e8e44d935bba6bdec41d363922bf21861c2b29cb1990`, farklıdır. Yeni koddan sonra fingerprint'i yeniden ölçün; bu devirde yalnız belgeler düzenlendi.

## 9. Claude'dan beklenen ilk çıktı

Gerçek görüntülere dayanarak kök nedeni teyit edin ve **40tri/120m hedefinin çalışma varsayımı** olduğunu doğru sınıflandırın. Ardından en küçük yeni teknik kararı/deneyi seçin; eski tuning döngüsünü sürdürmeyin. Amaç test sayısını artırmak değil, kaynak bitkiyle aynı karakteri daha ucuz temsilde korumaktır.

Kabul edilen tek tür yöntemi varsa tüm aileye ayrı doğrulamayla yayın, bağımsız QA/sanat ve en sonda final full yapın. Başarısızsa done demeyin. Önemli aşamada kanıt/commit/STATE/QUEUE/handoff ve safe pause bırakın. Push, main merge, foundation veya onaysız oyun entegrasyonu yapmayın.
