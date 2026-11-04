# 2026-11-01 · Her yolu yık (UI) + geri alma notu düzeltmesi

**REQ:** CAN-04, SIM-12, D-014 §1. **Dokunulmayan:** playable.gd, sim kodu, kanon, blocs.json.

- Yol paneli (`road_draw_panel.gd`): "Son yolu yık" korundu; 2+ yol varsa "Başka yolu yık (N yol daha)" listeyi açar
  (varsayılan kapalı: panel şehri örtmez). Satır: "Yol n: uzunluk, kapasite" (sim `public_works()`), altında sim yıkım
  önizlemesinden maliyet; sim reddederse düğme yerine ret nedeni. Satıra basınca mevcut onay kartı ("Evet, yık/Vazgeç").
  Gerekçe: haritada yol seçimi playable.gd/girdi katmanına dokunurdu (yasak); liste dokunmatikte >= 44 pt, hover'sız.
- Yıkım kuru koşuları (ağı geçici değiştirir) (gün, yol sayısı) anahtarıyla önbelleklenir; `busy` önbelleğe alınmaz.
- `expropriation.undo_note`: kısa süre açık; tepki işlenince ya da başka yol yapılınca kapanır (kural/pencere aynı; Q-030 açık).
- Testler: tests/ui/road_demolish_any_test.gd (yeni), expropriation_ui_test.gd (güncel). Kare: tools/godot/demolish_any_probe.gd.
- Doğrulanmadı: haritada yolu vurgulama yok; fiziksel iPad dokunuşu yok.
