# 2026-11-01 · Yol çiz paneli: klasik GERİ AL + YOLU YIK (D-014 §1, T-042c UI)

REQ: CAN-03 (araç yalnız komut gönderir), SIM-12 (ret nedeni sim'den), VIS/ADR-0004 (dokunmatik >= 44 pt, aralık >= 8 pt).

- `src/ui/flows/road_draw_panel.gd`: geri al düğmesi sim `undo_available()` açıkken görünür (zaten vardı); kapanınca sim'in nedeni ("Geri alma kapandı: ...") yazılır. Yeni "Son yolu yık" düğmesi + "Yıkım maliyeti: N birim" (sim önizleme `cost`, kurulu değilse "henüz kurulmadı"); sim yıkımı reddederse düğme yerine ret nedeni (ölü düğme yok). Düğme ek onay kartı açar: yol/kapasite, "geri alınamaz", kamulaştırmalı yolda "alınan arsalar ve yıkılan binalar geri gelmez, halkın tepkisi de kalır", Evet, yık / Vazgeç.
- Yalnız en son duran yol hedeflenir (`tool.last_road()`); eski yolu seçip yıkma arayüzü yok.
- Metinler `data/ui/strings.tr.json` (`road.undo_closed`, `road.demolish_*`).
- Test: `tests/ui/road_undo_demolish_test.gd` (9). Kareler: `artifacts/screenshots/captures/20261101-041034-geri-al-yik-desktop.png` (1600x900), `...-041142-geri-al-yik-ipad.png` (1024x768, `--imaro-input-profile=touch`).
- Doğrulanmadı: yıkım ONAY kartının gerçek kare görüntüsü (bayrakla açılamıyor; yalnız panel testi), gerçek iPad dokunma, MOCK facade'de yıkım (mock `public_work.demolish` uygulamaz).
