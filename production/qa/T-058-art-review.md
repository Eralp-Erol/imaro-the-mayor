# T-058 · Bağımsız sanat kapısı · 2026-10-27

İnceleyen: `art-director` (Claude Opus), uygulayıcıdan ve QA'dan bağımsız. Godot çalıştırılmadı; kod/asset değiştirilmedi. Yalnız mevcut gerçek Godot kareleri ve kontak sayfaları açıldı. Kırpım/montajlar yalnız inceleme içindir (`/private/tmp/claude-501/t058ad/`, kalıcı değil). **Bu hüküm kullanıcı onayı değildir; Q-018 (donatı/metal rengi, kiosk, ışık) kullanıcıdadır.**

## Verdict: PASS WITH FIXES (koşullu)

8 öneri varlığın LOD0 yönü sanat olarak kabul edilebilir: silüet, ölçek ve malzeme okunuyor, kutu yığını değil. **İki engelleyici kusur var (B1, B2).** İkisi de küçük ve yerel düzeltme. Düzeltilip aynı kamerayla yeniden çekilmeden T-058 sanat PASS sayılmaz. Yeniden tasarım istenmiyor.

## Gözlem (gördüğüm) / çıkarım ayrımı

### Tür bazında: silüet, ölçek, malzeme (LOD0)
| Varlık | Gördüğüm | Hüküm |
|---|---|---|
| bench | Ahşap çıtalar (damarlı, budaklı) ile koyu döküm çerçeve ayrı okunuyor. Üç ayak, taban plakası, kolçak ve gergi çubuğu var. 1,75 m kapsülün yanında oturma yüksekliği doğru. | iyi |
| bin | Sekizgen gövde; kapak, topuz, bant ve dikey lamel var. Ön plaka boş, yazı yok. Renk koyu petrol. | iyi; uzakta koyu leke |
| lamp_street | 8 m gövde, boyun halkaları, kıvrık kol ve düz armatür var. Işık/emisif yok. `context-scale` karesinde tepe, 5 katlı hero'nun yaklaşık 2. kat balkonuna denk. | iyi |
| bollard | Sekizgen, sivri başlı. Halka ve taban yakası var. Çok koyu (lacivert-siyah). | kabul; uzakta düz koyu |
| bike_rack | Üç ters-U kemer, dönüşleri yuvarlak, taban plakaları var. | iyi; 100 m'de 1 px çizgi |
| bus_stop | Petrol-mavi çerçeve, gri çatı, ahşap kiriş uçları, beton plak ve içte bank var. Cam: **koyu petrol, üstüne pişirilmiş çapraz parlama bantları** (B2). | yapı iyi, cam engelleyici |
| planter | Taş blok kap ve toprak var. Çalı iri fasetli küre kümesi. | LOD0 kabul; LOD1 engelleyici (B1) |
| kiosk | Yeşil boyalı tahta, taş kaide, şeritli tente, kepenk, konsollu tezgâh, kapı, parapet ve çatıda havalandırma/kapak var. Markasız. Türk büfesi gibi okunuyor. | en güçlü parça |

Logo, reklam yazısı ve gece ışığı **hiçbir karede görülmedi**.

### Hero bina ve insan yanında ölçek/çıta (VIS-01/02/03/05/07)
- `context-street.png` ve `context-scale.png`: bank, çöp kutusu, bollard ve kiosk, 1,75 m kapsül ile 5 katlı hero'ya göre makul. Kiosk zemin kat dükkân tentesinin altında kalıyor, direk yaklaşık 2. kata çıkıyor. Ölçek hatası görmedim.
- Doku yoğunluğu hero cepheden belirgin biçimde sade. Bunu kusur saymıyorum: donatı oyun zoom'unda birkaç on pikseldir ve "density restraint" ilkesine uygundur. Mat, düz gölgeli dil hero ile aynı aile.
- Tonda en yüksek sesli öğe durak. Doygun mavi çerçeve, koyu cam ve neredeyse beyaz plak sahnede baskın. `context-scale.png` kırpımında cam, tekrar eden çapraz şeritli koyu panel gibi okunuyor.

### LOD0 → LOD1 sürekliliği (yakın, aynı kamera ön çiftleri)
- **planter: KIRIK (B1).** LOD1 çalısı düz üstlü, prizmatik bir kutuya dönüşüyor ve **topraktan havada duruyor**: çalı altı ile toprak arasında görünür boşluk ve gölge var. Ayrıca sola kaymış. Kareyi ~%9'a küçülttüğümde (yaklaşık 40 m görünür boyu; bu bir çıkarım, ölçüm değil) düz üst/yuvarlak küme farkı hâlâ seçiliyor.
- bench (orta ayak ve sırt çıtaları kayboluyor), bin (kapak çıkıntısı ve topuz kayboluyor), bollard (halka ve taban yakası kayboluyor), bike_rack (yuvarlak dönüş köşeli oluyor, taban plakası kayboluyor), lamp (kıvrık kol kırık iki parçaya dönüyor, halkalar kayboluyor), bus_stop (kiriş uçları ve cam alt rayı kayboluyor, kayıtlar kalınlaşıyor), kiosk (pencere çerçevesi ve kapı kolu kayboluyor). Ton ve silüet korunuyor. Çıkarımım: 40/60/80 m geçişte engel değil.
- **Kanıt boşluğu:** geçiş mesafesinde (40/60/80 m) aynı kamerayla LOD0/LOD1 çifti yok. 25 m LOD0 ve 100 m LOD1 kareleri farklı mesafede.

### Palet/ton (F04 mat, düşük kontrast Ege)
Ölçüm, ham karelerden alan ortalaması, sRGB:
- Durak camı üst kısmı ≈ (0,08; 0,14; 0,17), L≈32/255.
- Beton plak L≈225.
- Kaldırım L≈191.
- Taş saksı güneşli yüzü L≈197.

Buna göre **taş saksı çok açık değil** (kaldırıma eşit); uygulayıcının bu gözlemine katılmıyorum. Beton plak ise kaldırımdan belirgin açık. Saksı çalısı (≈0,36; 0,46; 0,29) T-057 maki ve çit yaprak tonundan daha yeşil. Ayrıca yaprak kartı değil faset küre; dil farklı.

## Engelleyici (sanat FAIL nedeni; PASS için önce düzeltilmeli)
- **B1 · planter LOD1** (`fur_hero_planter_a.png` ve ön LOD1 ham karesi). Sorun: çalı topraktan kopuk havada duruyor, kutu silüetine dönüyor, yana kaymış. Bu, T-058 ölçüt 1/5'teki "gerçek bağlantı"yı ve LOD sürekliliğini (WLD-01/TEK-03) bozuyor. Düzeltme: LOD1 çalısının tabanını toprak yüzeyine oturt, merkezini LOD0 ile hizala, biçimi LOD0 küme zarfına yakın alçak bir kubbe yap (8–10 kenar, 2 halka; ≤240 üçgen içinde). LOD0'a dokunma.
- **B2 · cam atlas karosu** (`furniture_atlas.png` cam bölgesi; `fur_hero_bus_stop_a.png`, `bus_stop-back_lod0`, `context-scale.png`). Sorun: çok koyu cam ve pişirilmiş çapraz parlama şeritleri durağı arkadan siyah bir kutuya, önden "ekran/reklam paneli" gibi bir yüzeye çeviriyor. Mat ve düşük kontrast ilkesini (VIS-01/05) ve reklam paneli çağrışımı nedeniyle VIS-07 ruhunu bozuyor. Düzeltme: yalnız cam karosunu açık, az doygun gri-mavi yap (sRGB ≈0,45–0,55 değer, hero pencere camı ailesi). Çapraz bantları kaldır, en fazla tek bir hafif dikey gradyan bırak. Opak kalabilir. Aynı turda kiosk penceresi de bu karoyu kullanıyorsa birlikte kontrol et.
- **Tekrar kabulü:** aynı kamera ve ışıkla planter ön LOD0/LOD1 çifti ile bus_stop ön/arka/3/4 ve `context-scale` yeniden çekilsin. Ek olarak planter için 40 m'de aynı kamerayla LOD0/LOD1 çifti alınsın (`tools/visual-diff.sh`).

## Devredilebilir (entegrasyon / Q-018 / sonra)
- **D1** Küçük metal (bollard, bin, bike_rack, bank çerçevesi) neredeyse siyah ve uzakta düz koyu leke. Q-018 metal rengi seçilince metal değeri biraz yükseltilsin (koyu antrasit-gri, ≈0,22–0,28). Tek atlas karosu.
- **D2** Saksı çalısı tonu T-057 maki/çit yaprak tonuna çekilsin (yeşil kanalı düşür). İsteğe bağlı olarak faset küme daha küçük parçalara bölünsün.
- **D3** Beton plak karosu yaklaşık %10–12 koyulaştırılsın. B2 atlas turuna eklenmesi ucuz, ama engel değil.
- **D4** Durak çerçevesinin doygun mavisi ve kiosk tentesinin petrol/krem rengi kurum rengi veya hero tentelerinden (sarı/krem) kopuk bir dil gibi okunabilir. Karar Q-018'de. O zamana kadar nötr metal ailesi öneririm.
- **D5** Geçiş mesafesinde (40/60/80 m) her tür için aynı kamerayla LOD0/LOD1 çifti ve hareketli geçiş kanıtı entegrasyonda alınsın.
- **D6** 100 m'de bike_rack kemerleri 1 px kırık çizgi, bollard/bin birkaç piksel. Entegrasyonda küçük sınıf için daha erken cull (≈100 m) ölçülsün; pop riski kaydedilsin.
- **D7** Kiosk penceresi koyu ve boş. İsteğe bağlı olarak hero dükkân camındaki gibi bir raf izi eklenebilir. Kozmetik.

## Kapsam dışı / test edilmedi
Gerçek şehir yoğunluğu, tekrar, HUD, iPad/performans, hareketli LOD geçişi, gece. Zemin dokusunun uzak moiresi T-058 kapsamı değildir. Teknik ölçütler (hash, üçgen, katalog) QA raporunun alanıdır; burada yeniden doğrulanmadı.

## Açılan dosyalar
Kontak sayfaları (tek tek):
- `/Users/eralperol/Documents/Projects/imaro-the-mayor-handover-imaro-m01-349562fb/design/library/sheets/furniture-hero/fur_hero_{bench,bin,lamp_street,bollard,bike_rack,bus_stop,planter,kiosk}_a.png`
- `/Users/eralperol/Documents/Projects/imaro-the-mayor-handover-imaro-m01-349562fb/design/library/sheets/furniture-hero/context-{street,scale,lineup}.png`

Karşılaştırma:
- `/Users/eralperol/Documents/Projects/imaro-the-mayor-handover-imaro-m01-349562fb/design/library/sheets/hero-res_mid.png`
- `/Users/eralperol/Documents/Projects/imaro-the-mayor-handover-imaro-m01-349562fb/design/library/sheets/vegetation-hero/context-street.png`
- `/Users/eralperol/Documents/Projects/imaro-the-mayor-handover-imaro-m01-349562fb/assets/hero/furniture/furniture_atlas.png`

Ham kareler. Ortak dizin: `/Users/eralperol/Documents/Projects/imaro-the-mayor-handover-imaro-m01-349562fb/artifacts/screenshots/captures/`.
- Tek başına açılanlar: `20261027-193052-t058-bin-near_lod0.png`, `20261027-193057-t058-bin-far_lod1.png`.
- 16 kare yan yana ön LOD0|LOD1 montajı olarak açıldı (ham çözünürlük, 2800×1100): her türün `*-front_lod0.png` + `*-front_lod1.png` çifti (192933/193000 bench, 193019/193046 bin, 193105/193132 lamp, 193150/193218 bollard, 193237/193304 bike_rack, 193323/193350 bus_stop, 193410/193437 planter, 193456/193523 kiosk).
- Kırpım veya ölçekle açılanlar: `20261027-193507-t058-kiosk-back_lod0.png`, `20261027-193334-t058-bus_stop-back_lod0.png`, `20261027-193542-t058-context-scale.png` (durak ve küçük donatı kırpımı), `20261027-193548-t058-context-street.png` (örnekleme), ayrıca bollard/bike_rack/lamp_street/planter `*-far_lod1.png` 4× merkez kırpımı.

Yalnız kontak sayfası üzerinden görülenler (ham olarak ayrıca açılmadı): diğer side/back/top/3q ham kareleri.

## Ek: B1/B2 yeniden inceleme (2026-10-27, art-director)

Hüküm: **PASS** (B1 ve B2 kapandı). Kullanıcı onayı değildir; varlıklar PROPOSED kalır, Q-018 açık.

- B1 kapandı. `captures/20261027-195400-t058-planter-front_lod1.png` ile `-195331-...front_lod0.png` karşılaştırıldı: LOD1 çalısı kubbe biçiminde, toprağa oturuyor, ortalı, LOD0 zarfıyla aynı yükseklik ve genişlikte. 40 m çiftinde (`-195542-...40m_lod0`, `-195547-...40m_lod1`) siluet ve ton aynı, LOD geçişinde fark edilir bir sıçrama yok. LOD1'de saksının orta bandı yok; bu kabul edilebilir.
- B2 kapandı. Ön, 3/4 ve context-scale karelerinde (`-195243`, `-195306`, `-195513`) güneşli cam açık gri-mavi okunuyor. Çapraz bant yok. Ekran ya da siyah kutu izlenimi kalmadı. Arka yüz (`-195254`) koyu slate, örnek ortalama ≈RGB(57,70,88). Çerçeveli üç panel olarak okunuyor, kara kutu gibi görünmüyor. Aynı karede figür kapsülü de koyu: bu, yüzün gölgede kalmasından geliyor (bu bir çıkarım). Engelleyici değil.
- Yan etki yok. Kiosk servis penceresi `metal_dark` karosunu kullanıyor (assets.py), cam karosu değil. Koyu iç görünümü tente altında açık kepenk gibi okunuyor. Bank, ahşap ve metal tonlarıyla değişmemiş görünüyor. Durak plağı (D3) hâlâ açık beton olarak okunuyor.
- Entegrasyona devredilenler (engelleyici değil):
  - (i) Durağın arka yüzünü üretim ışığında/ortam ayarında yeniden kontrol et. Hâlâ "duvar" gibi okunursa camı yarı saydam yap ya da ışık tarafında çöz. Atlas karosunu daha da açma.
  - (ii) Saksı çalısının yeşilini T-057 maki ile aynı karede yan yana doğrula.
