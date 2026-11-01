# 2026-11-01 · B-015 UI ucu / B-017 · sıfır parsellik teklif (ui-engineer)

Karşıladığı: CAN-04, SIM-12, D-014 §1, CAN-03 (yeni bina verbi yok), ADR-0004 (hedefler >= 44 pt).

- Gerçek oyunda üretildi (`tools/godot/zero_parcel_probe.gd`: yol çiz, kamulaştırarak onayla, yık, aynı şeride yeniden çiz). KIRMIZI: panel "Bu yol yapılamaz: Yol mevcut arsaların içinden geçemez; kamulaştırma henüz yok." diyor, "Onayla" pasif, kabul düğmesi yok (yol çizilemiyor). Kök neden: `RoadDrawTool.offer()` ve `ExpropriationText.is_offer` yalnız `taken_parcels > 0` iken teklif sayıyordu.
- Düzeltme: teklif = `crosses_parcels` + `taken_parcels` anahtarı VAR (anahtar yoksa eski "kamulaştırma henüz yok" metni kalır). Sıfırsa: kart "Bu şerit boş" + "Kimsenin evi ya da arsası alınmayacak, yıkım olmayacak. Yol bu şeride düz yol olarak kurulur."; tek ileri düğme "Devam et", sonra sade "Onayla" (yıkım onayı/uyarısı, "Kamulaştırmaktan vazgeç" ve `undo_note` yok; İptal var). Geçerli kartta "Alınacak arsa yok; yıkım olmayacak." Metinler `data/ui/strings.tr.json`.
- Neden otomatik kabul değil: sim'de CAN-04 oyuncu onayı adımı duruyor; araç kendiliğinden kabul etse onay penceresi görünmeden `expropriate: true` komutu hazırlanmış olurdu. İki adım (Devam et, Onayla) bilinçli; ucuz.
- `expropriation.undo_note` (B-013/Q-030) DEĞİŞMEDİ, yalnız yıkımlı akışta görünmeye devam eder.
- Testler: `tests/ui/zero_parcel_offer_test.gd` (önce kırmızı: `is_empty_strip` yok / parse), `tests/ui` tümü 469/0 hata.
- Görsel: `green/1-redraw-review.png`, `green/2-redraw-accepted.png` (scratchpad); gerçek oyunda yeniden yol kuruldu (`public_works` 0 -> 1).
- Doğrulanmadı: dokunmatik cihaz; `full`; imleç etiketi kırmızı tonda "Bu şeritte alınacak arsa yok..." gösteriyor (okunur ama ret rengi).
