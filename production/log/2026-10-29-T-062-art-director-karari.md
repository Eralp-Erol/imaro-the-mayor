# T-062 sanat kapısı · art-director kararı · 2026-10-29

- Kanıt: yalnız mevcut gerçek runtime kareleri, Read ile tek tek açıldı: `artifacts/library/t062/qa/frames/` (13 kare; `metro.png` yok sayıldı, 18 km tavanının dışında) + `artifacts/library/t064/tilt/floor3-a-street60.png`, `floor3-b-neigh500.png` (bağlam için `floor3-c/d` da açıldı). Godot çalıştırılmadı, yeni kare alınmadı.
- Ölçüm (sRGB, kare kırpımından piksel ortalaması): LOD1 düz çatı `core-street-d110-p35` = (149-159, 142-149, 124-129). Yerinde ağaç tacı `rural-d4-d400-blobcrop` = (69-108, 80-100, 43-68); bitki lekesi = (71-107, 81-92, 44-75). Renkler uyumlu; sorun boyutta.
- Kareler duvar saatiyle ilerlediği için `visual-diff` bu set için anlamlı değil (QA §3). Düzeltmelerin önce/sonra karşılaştırması aynı preset ve duraklatılmış sim ile yapılmalı.

**Genel karar: PASS WITH FIXES.** Kent her mesafede kent gibi okunuyor. Hero binalar, çatı ve cephe dili, Ege ağaçları ve zemin aynı sanat grameriyle duruyor (VIS-01/02, WLD-01). Kullanıcıya göstermeden önce üç küçük düzeltme var (madde 1, 2, 5). Hiçbiri geometri ya da kompozisyonu yeniden kurmayı gerektirmiyor.

## 1. B-4 · PROXY/HLOD1 çatı tonu: DÜZELT (küçük)
- Gördüğüm: `tier-d2200.png`'de orta ve geç dönem apartmanların düz çatıları uzak sıralarda krem-beyaz yanıyor. Yakın sırada bu çatılar gri-bej, kırmızı kiremit baskın. Sonuç olarak kent bir bantta "beyazlaşıyor". `tier-d1300.png`'nin orta bandında da aynı krem kutular var. Bunun nedeni A3 notuyla örtüşüyor: PROXY atlasında düz çatı krem, LOD1'de gri. Aynı şehrin iki tonu kademe sınırını gösteriyor (VIS-05, tek dünya hissi).
- Öneri: HLOD1 ve HLOD2 çatı rengini PROXY atlasından değil, LOD1 çatı malzemesinin ortalamasından pişir. PROXY kademesi için, onaylı asset'e dokunmadan, görünüm verisinde modül başına çatı tonu çarpanı kullan (`res_mid`, `res_late`; hedef sRGB yaklaşık (154, 146, 127)). Atlası üreteçten yeniden basmak katalog hash'ini değiştirir, bu yüzden ikinci yol olarak kalsın.
- Kabul: `tier-d2200` aynı preset ile yeniden alınır. Uzak sıradaki düz çatı kırpımı ile yakın sıranınki arasındaki fark kanal başına ≤ 8/255 olmalı.

## 2. B-5 · 400 m ötesi bitki lekesi: DÜZELT (küçük, yalnız veri)
- Gördüğüm: `rural-d4-d400-blobcrop.png`'de lekeler yaklaşık 30-36 m çaplı, altıgen ve kayaya benzeyen yeşil tümsekler. 10-14 m'lik evlerden 2-3 kat büyükler. `veg-d4-d260-p15.png`'nin orta planında da evleri gölgede bırakıyorlar. 400 m'de hiçbir geçiş yok, keskin bir sınır var. Bu bir ölçek tutarlılığı ihlali (VIS-03, WLD-07). Bu haliyle kabul edilemez.
- Öneri (`data/view/vegetation_view.json` `blob`): `max_clump_radius_m` 18 → 8, `radius_mult` 1.3 → 1.0, `clump_m` 40 → 24, `min_clump_radius_m` 4.5 → 3. LOD1'den lekeye 360-440 m arasında dither ile çapraz geçiş yap (mevcut uzak dither aynı yöntem). Leke sayısı artacağı için üçgen ve p95 değeri yoğun çekirdekte ölçülmeli (B-1 bütçesi zaten aşılmış). Tutmazsa `clump_m` 30'da kalsın, yarıçap tavanı yine 8 olsun.

## 3. 50 m bakışta hero LOD1: PASS (D-006 ertelemesi riskte değil) + DÜZELT (küçük, kamera)
- Gördüğüm: LOD1, cepheye 30 m ve daha uzak olduğu her karede yeterli: `floor3-a-street60.png` (sanayi, göz hizası), `veg-low-d150.png`, `core-street-d110-p35.png`, `rotind-h90.png`. Pencere, balkon, saçak ve kiremit okunuyor. `core-street-d60.png` ise bir LOD sorunu değil, kamera sorunu: göz bir çatının içine girmiş, kiremit dokusu bulanık, pencere gerilmiş. LOD1 ancak birkaç metreden bakılınca bozuluyor.
- Risk: 3° eğim tabanında 50-60 m uzaklıkta göz yerden yaklaşık 3 m yüksekte kalıyor. Yoğun çekirdekte bu, cepheye birkaç metreden bakmak demek ve ertelenmiş LOD0 ihtiyacını erkene çeker. Göz açıklığı bugün yalnız araziye göre hesaplanıyor (`CameraMath.clearance_m`).
- Öneri (godot-engineer): bina farkında göz açıklığı. Kural: göz ≥ 15 m yarıçap içindeki en yüksek çatı + 2 m (ayak izi ve yükseklik verisi simde zaten var). İkinci seçenek: gözü cepheden en az 20 m uzakta tut. Bu sağlanırsa LOD0 M2 sonrasına kadar gerekmez.

## 4. Döndürülmüş sanayi yapısı (`rotind-h0`, `rotind-h90`): PASS
- Uzun kenarı sokağa paralel; bacalı, tuğla tabanlı ve gri çatılı bir atölye ya da depo olarak mahalle dokusunda inandırıcı. Yola taşma ya da başka yapıyla çakışma yok, iki açıdan da okunuyor. Kısa ucun yana bakması depo tipolojisinde doğal.
- Bilgi: `floor3-a`/`b`'de D3 avlularında aynı tek sanayi modeli yaklaşık 30 kez tekrarlanıyor (madde 12, tekrar). Bu T-062'yi engellemez; "aile çeşitliliği" zaten açık bir kullanıcı kararı.

## 5. Neredeyse yatay eğimde ufuk ve arka plan: DÜZELT (küçük, en görünür olan)
- Gördüğüm: `floor3-a`, `floor3-b`, `veg-low-d150`, `veg-d4-d260-p15`'te ekranın %35-45'i lacivert-siyah (`world_preview.gd` `BG_COLOR` (0.045, 0.06, 0.085)). Kare "gece" diye okunuyor. `floor3-c-edge-west` ise tümüyle siyah ve koyu deniz. Bu, gündüz varsayılanı kuralını bozuyor (visual-gate ışık maddesi, VIS-01). Sahip yatay eğimi kendisi istedi, ilk göreceği şey bu olacak.
- Öneri: `ProceduralSkyMaterial` ile gündüz gökyüzü. Değerler: tepe (0.42, 0.60, 0.80), ufuk (0.80, 0.84, 0.86), zemin ufku ufukla aynı, zemin altı (0.45, 0.47, 0.42), güneş diski kapalı ya da küçük. Ambient `COLOR` kalsın, böylece gök radyansının maliyeti olmaz. Kenar sisinin rengi ufuk rengine eşitlensin ki dünya kenarı göğe karışsın. Compatibility'de maliyet sorun çıkarırsa en az çözüm: `background_color` (0.78, 0.84, 0.88) ve aynı sis rengi.

## 6. Genel: kapanış için yeterli; gösterimden önce 1, 2 ve 5 yapılmalı
- Engelleyici sanat hatası yok (FAIL yok). Göstermeden önce siyah gök (5) ve dev lekeler (2) düzeltilmeli; ikisi de ilk bakışta "bozuk" diye okunuyor. Çatı tonu (1) ve kamera açıklığı (3) aynı turda yapılabilir, toplamı küçük iş.
- Kapsam dışı ama en büyük görsel açık: bitişik nizam 0,042. `rotind-h0`, `core-street-d110-p35` ve `rural-d4-d400`'de evler çıplak toprak üzerinde serpiştirilmiş duruyor. Bu, katmanlı Ege kent dokusu yönünden (F04) uzak. Yeni bir yerleşim kompozisyonu işi gerektiriyor, yama ile çözülmez. Demo gösterildikten sonra kullanıcıya ürün sorusu olarak sorulmalı: "sıkışık apartman dokusu mu, bahçeli seyrek doku mu?"
- Bu kararın kapsamı dışında: B-1 performans (TD), B-2/B-3 (kapı ve ölçüt metni).
