# Alınan parselin içindeki bitki örtüsü gizleme (T-042b oyun katmanı bulgusu) — 2026-10-31

REQ: WLD-01/TEK-03 (tek dünya; bitki yerleşimi dünya verisinden, görünüm yalnız temsil), TEK-01/02 (sim görünümden bağımsız; sim ve `src/world/network` DEĞİŞMEDİ), CAN-03 (yeni nesne/bina yok) · Karar: D-011 (yıkım geri alınabilir) · Bulgu kaynağı: `2026-10-31-T-042b-oyun-adimi.md` "AÇIK BULGULAR 1".
Taban: `5537543` (agent/handover-imaro-m01-349562fb). `design/foundation` değişmedi; `playable.gd` 1000 satır, DEĞİŞMEDİ (mantık ayrı dosyalarda).

## Sorun
Kamulaştırılıp yıkılan (`development == taken`) parselin içinde ağaç/çalı duruyordu: bitki yalnız yeni yol koridoru (`VegetationCorridor`) için gizleniyordu.

## Ne yapıldı (kısa)
- **Kural** (`src/view/vegetation/vegetation_parcel_mask.gd`, yeni): alınan parselin dış çizgisi içindeki bitki satırları. Bitki yerleşimi zaten `is_point_in_polygon(p, parcel.outline)` ile parsele göre yapıldığından (`VegetationPlacement` avlu/çit/koru) aynı sınama tersinden kullanılır: rastgelelik YOK, dünya verisinden gelir, saf ve deterministik. Yalnız parselin kutusuna değen 256 m hücrelerin satırları taranır; tarama `step(budget_us)` ile kare dilimlerine bölünür (256 satırda bir saat denetimi); sonuç parsel başına saklanır (geri alınca yeniden taranmaz). `BuildingParcelMask` desenini izler (kimlik -> satırlar, `want` ile fark, `union_rows`).
- **Maske kaynak bitleri** (`VegetationLayout`): `hidden` artık bit maskesi (`CH_CORRIDOR` = yol koridoru, `CH_PARCEL` = alınan parsel). `set_channel_rows(bit, rows)` ARTIMLI (eski küme ile fark; tüm 300 bin sütun taranmaz). Eski `set_hidden(rows)` = koridor bitine sarmalayıcı (davranış aynı). Hücre üreticileri `hidden[i] != 0` denetler.
- **Görünüm** (`VegetationView`): `set_parcel_rows(rows)`; koridor yenilemesi (`playable._refresh_vegetation_corridors`, her yol değişiminde baştan kurar) parsel bitini silmez. Etkilenen hücre/leke parçaları yerelde yenilenir (mevcut yol). **Leke işçileri çalışırken maske yazımı bekletilmez, ERTELENİR** (`_mask_pending`, `track_camera` işçiler bitince yazar; bu sırada yeni işçi başlamaz): ilk denemede `_join_blob_jobs` ana iş parçacığını 14-31 ms bekletiyordu, ertelemeyle yazma 0,1-1,3 ms.
- **Takipçi** (`PlayableExpropriation`): mevcut `parcels_removed/added` akışı. Alınan parselin dış çizgisi ağdan çıktığı için kurulumda `net.parcels.duplicate()` (yalnız referans, 40 bin parsel için yerel kopya) tutulur. T0 yapısı olmayan (boş arsa) alınan parseller de bitki için izlenir (`_gone`). Günlük eksikse (yükleme) tüm anlık görüntü eşitlenir. Bitki görünümü asenkron gelir: `veg_of` çağrılabilir her karede sorar; yerleşim hazır olunca (ya da yeni yerleşimle) alınanlar baştan istenir. Bitki görünümü yoksa (başsız) iş beklemez (`busy()` false).
- `PlayableRoads.create` `veg_of`u bağlar (1 satır).
- Probe: `tools/godot/expropriation_game_probe.gd` bitki yerleşimini bekler, `XPROBE_VEG`/`XPROBE_WORST` basar; `--no-veg-parcel` A/B anahtarı (yalnız ölçüm).

## Dosyalar
src: `src/view/vegetation/vegetation_parcel_mask.gd` (yeni), `vegetation_layout.gd`, `vegetation_view.gd`, `vegetation_cell_builder.gd`, `src/game/playable_expropriation.gd`, `src/game/playable_roads.gd`.
tests: `tests/view/vegetation/vegetation_parcel_mask_test.gd` (5), `tests/game/playable_expropriation_vegetation_test.gd` (4). Araç: `tools/godot/expropriation_game_probe.gd`.
Dokunulmayan: sim, `src/world/network`, `sim_contract`, `playable.gd`.

## ÖNCE / SONRA (gerçek pencere 1600x900, gerçek Ismeral D2, 300 bin bitki örneği, 134 m yol, 15 parsel alındı, 10 yapılı)
Intel i7-8850H Mac, yük ortalaması 8-17 (paralel ajanlar) -> gürültülü; iPad DEĞİL.
| Ölçü | Değer |
|---|---|
| Taranan bitki satırı (15 parsel) | 4460 (300 bin satırın ~%1,5'i) |
| Gizlenen bitki örneği | 9 (parsel bitleri; toplam gizli 11 = +2 koridor) |
| Tarama adımı, tek kare (`veg_scan_max_ms`) | 0,69 - 1,31 ms |
| Maske yazma (`mask_write_ms` parsel bit) | 0,2 - 0,28 ms |
| Takipçi bitki payı toplam (tarama + yazma) | <= ~1,6 ms/kare |
| Koridor maske yazımı (eski, ertelemesiz -> ertelemeli) | 14 - 31 ms (işçi bekleme) -> 0,08 - 1,3 ms |
| Tüm takipçi `poll` tepe (`poll_max_ms`) | 11,7 - 13,1 ms; bunun 6,9 - 11 ms'i ÖNCEKİ iş: `BuildingView` kurulum dilimi (`pump_max_ms`), bitki payı değil |
Hedef "bitki adımı <= 8 ms/kare": SAĞLANDI (<= 1,6 ms). Takipçinin bütün `poll`u yüklü makinede 8 ms'i AŞIYOR (11-13 ms), ama bu bina kurulumunun bölünemez maliyeti (önceki log: 6,9 pencereli temiz makine); bu işin değiştirdiği kısım değil.
A/B (`--no-veg-parcel`, parsel gizleme KAPALI): `VegetationView.update_ms_max` 110 ms, AÇIK: 111 ms; en pahalı kare 57-62 ms iki durumda da aynı sırada. Yani kareler arası sivrilmeler (yol chunk kurulumu + koridor kaynaklı leke yenileme) bu işten gelmiyor, ÖNCEDEN VAR (önceki logdaki "AÇIK BULGULAR 3" ile uyumlu); ayrı iş.

## Pencereli gerçek akış — ekran görüntüleri
Dizin: `/private/tmp/claude-501/veg_screens/` (repoda DEĞİL). Probe: `--ui --prefix=ab-on` (düzeltmeli) ve `--ui --prefix=ab-off --no-veg-parcel` (eski davranış, aynı aday yol).
- `ab-off-2-after-road.png` — ESKİ: yıkılmış arsanın ortasında bir ağaç (~700,330) ve bir çalı (~1005,415) KALMIŞ.
- `ab-on-2-after-road.png` — YENİ: aynı kare, arsa içinde ağaç/çalı YOK; yol kenarındaki ince servi/sokak ağaçları (parsel dışı, sokak katmanı) duruyor (doğru).
- `ab-on-1-before.png`, `ab-on-3-after-undo.png` — geri alınca binalar ve ağaçlar geri; `crops-before-after-undo.png` üç karenin aynı kırpımı alt alta. Gözle: geri al karesi önce karesiyle aynı ağaç yerleşimi.
- Diğerleri: `*-1b-offer`, `*-1c-confirm`, `*-2b-undo-confirm` (UI akışı).
Bakıldı: ağaç kalmadı = evet (parsel içinde); geri alınca geri geldi = evet (gözle; piksel eşitliği ölçülmedi, HUD/gün farkı var).

## DOĞRULANMIŞ (çalıştırıldı)
- `res://tests/view/vegetation`: 60 test, 0 hata, 0 başarısızlık (5 yeni + mevcut koridor testleri, ertelemeli yazımla da).
- `res://tests/game`: 123 test (4 yeni dahil), 0 hata, 0 başarısızlık, 2 yetim düğüm uyarısı (yeni oyun testi tek başına 0 yetim; öteki suite'lerden, öncesiyle karşılaştırılmadı).
- Yeni testler: kural == kaba kuvvet (sıralı/tekil); dilimli tarama == tek seferlik tarama; `want` düşer ama kalanı yeniden taramaz; koridor+parsel kaynakları birbirini bozmaz ve fark artımlı (bit eşit taze kurulumla); görünüm gizler/geri getirir ve koridor yenilemesi parsel bitini silmez; oyun: alınan parsellerin (boş arsa dahil) ağacı gizli, sokak ağacı ve diğerleri değil; geri al hepsini döndürür; bitki geç gelirse; değişim günlüğü boşluğu (tam eşitleme); koridor yenilemesi.
- gdlint (gdtoolkit 4.5.0): değişen/yeni src, tests ve probe dosyalarında "no problems found" (`tools/` altında başkasının dosyalarındaki mevcut uyarılar benimle ilgisiz).
- Pencereli probe (yukarıdaki sayılar ve görüntüler).
- `tools/verify.sh quick`: FAIL (1 test, benimle ilgisiz; aşağıya bakın). Quick PASS/FAIL tam doğrulama DEĞİLDİR.

## VARSAYILAN (doğrulanmadı / çıkarım)
- Sınır bulanıklığı: `Geometry2D.is_point_in_polygon` sınırda ~0,06 m bulanıktır; kaba kutu 0,5 m payla süzülür ki sonuç kaba kuvvetle birebir olsun (testte doğrulandı: ilk sürümde 0,05 m payla tek bir örnek kaçtı). Yerleşimin kendisi aynı fonksiyonu kullandığından parsel kenarındaki çit örnekleri aynı kurala uyar.
- Sokak (parsel dışı) ağaçları bilerek gizlenmez; yıkılan parselle ilişkisiz.
- Maske artımlıdır ama `VegetationLayout.hidden` ilk kullanımda 300 bin baytlık dizi ayırır (kurulumda bir kez, <1 ms ölçülmedi ayrı).
- `veg_cells_changed` ertelenmiş yazımlarda 0 görünür (bilgi alanı).

## TEST EDİLMEDİ
- Gerçek iPad/dokunmatik davranışı ve iPad kare süresi; hiçbir sayı iPad sayısı değildir.
- Kayıt yükleme yolunda önceden alınmış parsellerin bitkisi: takipçi kayıt yüklemeden ÖNCE kuruluyor (anlık görüntü alınmış parseller dahil) varsayımıyla; gerçek kayıt yüklemeyle uçtan uca denenmedi (yalnız değişim günlüğü boşluğu birim testi).
- Aynı karede birden çok ardışık kamulaştırma, birden çok yol, D2 dışı, başka dünya tohumu, uzun oturum bellek.
- Çok yoğun bitkili parsel (kırsal koru) için tarama süresi (D2 kent parselleri ölçüldü; koru parselleri büyük olabilir, dilimleme bu durumda da bütçeyi korur ama toplam gecikme ölçülmedi).
- Gölge/LOD0 yakın çekim görünümü (probe uzaklığı 230 m, LOD1 ve leke); yakın kamerada LOD0 hücresi ekran görüntüsüyle ayrıca doğrulanmadı (birim testte LOD0 sayısı doğrulandı).

## Verify (son adım, tek koşu)
`tools/verify.sh quick` (head 5537543 + bu değişiklikler, taban b6fa635b3 son-başarılı-full -> 234/244 suite koştu; 1094 sn, yüklü makine):
- PASS canon-check, studio-check, area-map, gdlint (137 dosya), import.
- FAIL unit-gdunit: 2366 test, 0 hata, **1 başarısızlık**: `tests/world/settlement/settlement_hero_mapping_test.gd > test_settlement_control_data_names_no_rejected_or_unapproved_identity` ("Expecting 45 but was 44", satır 32). Settlement kontrol verisi/onaylı kimlik sayısı testi; bu işin dokunduğu hiçbir dosya (görünüm bitki/oyun takipçisi) ya da veri değil. TABANDA da başarısız mı DİYE ÇALIŞTIRILMADI (taban ayrı checkout gerektirir) -> "bu işten kaynaklanmıyor" ÇIKARIMDIR, kanıtlanmadı. Kök neden araştırılmadı (kapsam dışı).
- ATLANDI: 10 suite (tests/app 4, tests/view 4, tests/world 2), canon-guard, ve alan değiştiği halde YAVAŞ sayılan: `view/vegetation/vegetation_cache_test`, `view/vegetation/vegetation_cell_builder_test`, `world/vegetation/vegetation_invariants_test`, `world/vegetation/vegetation_placement_test`. `vegetation_cell_builder_test` benim değiştirdiğim `hidden[i] != 0` satırlarını kapsar: tek başına koşulan `tests/view/vegetation` (60 test, hepsi geçti, yavaş suite'ler dahil) bunu karşılar; ancak `world/vegetation/*` (yerleşim) bu işin dokunmadığı alanda ve quick'te koşmadı.
