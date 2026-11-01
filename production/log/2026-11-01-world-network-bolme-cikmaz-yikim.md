# 2026-11-01 · world_network.gd bölme + çıkmaz yol yıkımı (ADR-0005 Ek J takip f, a, d)

Sahip: world-engineer · Karşıladığı: WLD-01/TEK-03, TEK-01/02, CAN-04, D-014 §1.

## 1) Davranışsız bölme (f) — commit `9190004`
- `world_network.gd` 995 -> 768 satır. Yeni `src/world/network/network_block_build.gd` (`NetworkBlockBuild`, 250 satır):
  `refresh`, `update_matched_block`, `build_block`, `parcelize_block`, `make_parcel`, `set_frontage`, `remove_block`,
  `needs_land_check`, `outline_on_land`, `touches_spur` + üç sabit (`LAND_FAST_PATH_MARGIN_M`, `BLOCK_REGION_MAX_M`,
  `OPEN_WEDGE_MIN_AREA_M2`). `WorldNetwork.refresh_blocks()` ince sarmalayıcı kaldı.
- Arkadaş çağıranlar yeni sınıfa geçti: `NetworkBlockMatch`, `NetworkExpropriation`, `NetworkLocalRefresh`,
  `NetworkRestore`. Mantık satırı değişmedi (tek istisna: uzun `elif` satırı kırıldı, değerlendirme sırası aynı).
- `world_network.gd` `graph_hash` yorumundaki "parseller yeniden türer" mühür sonrası için düzeltildi (Ek J takip f).
- Önce/sonra: `tests/world` + `tests/sim/public_works` + `m2_query_test` + `parcel_changes_test`: **654 vaka, 0 hata /
  0 başarısızlık**, test adları aynı, `GOLDEN_X_CANDIDATE=9b935788...` ve `DEMOLITION_PROPERTY demolished=209
  through=195 failures=0` çıktıları bit-bit aynı. gdlint `src/world/network` temiz.

## 2) Çıkmaz yol yıkımı (a) — KIRMIZI ÜRETİLEMEDİ, `next_edge` DEĞİŞMEDİ
Ek J takip a "kod okuması; test edilmedi" idi. Ölçüm (başsız, `NetworkTestSupport.grid_network`, KEEP_PARCELS):
- Ön koşul sağlandı (en küçük kimlikli delta kenar ağa BAĞLI, yaprak değil): iki kenarlı dirsekli çıkmaz (ileri ve ters
  çizim) ve üç kenarlı çıkmaz için `DemolitionPlan.run` **ok**, `added/removed_parcels = 0`, graf tabana döndü, geri
  alma tabana bit-eşit.
- Gözlem: ilk kenar silindikten sonra 9 blok da `parcelized`, 130 parsel yerinde (hata ayıklama çıktısı). Yorumum (kodda
  doğrulanmadı, gözlemle uyumlu): spur'lar yüz çevresinde değil `spurs` alanında olduğundan yüzün köşe anahtarı aynı kalır
  (imza yalnız `#H` eki alır), `NetworkBlockMatch` eski bloğu eşler ve `kind`/parseller korunur. `holed` yüz yalnız
  eşleşme KOPARSA önemli olur; çıkmaz yolda kopmuyor.
- Rastgele tarama (tek seferlik betik, kalıcı değil): 3.646 blok-bölmeyen çok kenarlı çıkmaz yol x iki yön, **2 hata**,
  ikisi de yolun kendi başlangıç yoluna geri kıvrılıp kestiği halkalı taslak (kenar sırası değişmez; sonuç aynı).
  Yaprak-önce ve "ada bırakma" sıralarını da denedim: aynı iki hata, yani SEBEP SIRA DEĞİL. Davranış değiştiren bir düzeltme
  kanıtsız olurdu (op sırası kayıt/hash'e yansır), bu yüzden uygulanmadı; yalnız koruma testleri eklendi.
- Kalıcı koruma: `tests/world/network/network_demolition_dead_end_test.gd` (6 vaka; 424 denemelik özellik testi dahil).
- Açık kalan: halkalı / kendini kesen taslakta yıkımın parsel değiştirmesi (2/3.646). Oyuncu bunu çizerse yıkım güvenli
  reddedilir (`demolition_changes_parcels`, durum değişmez); kök neden araştırılmadı. Gerçek Ismeral ağında çıkmaz yol
  yıkımı denenmedi (sentetik ızgara).

## 3) Aynı şeride yeniden yol (d) — ÖLÇÜLDÜ, HATA (düzeltme küçük DEĞİL, yapılmadı)
Sim köprüsüyle (gerçek `NetworkExpropriationPort`, `public_works_support` dünyası) ölçüm: kamulaştırmalı yol + yıkım sonrası
aynı çokgen:
- `taken_parcels` = 0 (alınanlar dünyada yok); `RoadDraftCheck` ALLOW kipinde **ok**.
- AMA `validate_command(public_work_road(..., expropriate=true/false))` ikisi de `rejected / crosses_parcels`; teklif
  yok, gönderim durumu değiştirmez. Yani "0 parsellik teklif" ÇIKMIYOR; daha kötüsü, oyuncu yıktığı şeride yolu
  yeniden ÇİZEMİYOR.
- Neden: `ExpropriationFlow._problem` `taken` boşsa düz yola düşer ("bu yol parsel almıyor"); düz denetim blok tabanlı
  (`RoadDraftCheck._in_parcelized_block`) ve birleşen blok parselli. Yalnız denetimi parsel tabanlı yapmak yetmez:
  kamulaştırmasız `add_road` havuzlanmaz, birleşen bloğu BAŞTAN parseller (yeni numara -> `parcels_changed`). Doğru
  düzeltme: `taken` boş ama şerit parselli bloktan geçiyorsa yolu havuzlu (0 alınan) komitlemek; sim akışı + plan
  yapısı (boş plan) + dünya `NetworkExpropriation.active` koşulu birlikte değişir -> `simulation-engineer` + `world-engineer`,
  hash/kayıt etkisi gözden geçirilmeli.
- Sabitlendi: `test_known_limitation_redrawing_over_a_freed_strip_still_reports_crosses_parcels` (düzeltilince bilerek
  değişir). Önerilen sahip: simulation-engineer; ürün sorusu yok (oyuncunun "yıktım, tekrar çizeyim" beklentisi D-014 §1 ile
  tutarlı).
