# D-022 · iPad çekmecesi yarı yüksekliği (2026-11-05)

Kaynak: sahip, Q-037 soru kartı. Kararı sahip verdi; aşağıdaki kelime sahibindir.

- Soru: iPad'de alttan çekmece yarı açıkken şehrin ne kadarı örtülsün?
- Sahibin cevabı: **"C"** → "Yol çizerken ve denetçide %45, karar panellerinde %62 (haritada iş yapılan paneller daha alçak)."

## Uygulama (çalışma değeri, sahip iPad'de dener)
- `data/ui/ui_tokens.json`: `drawer_frac_half` 0,62 (karar panelleri: meclis, bütçe, gündem, politika, sonuç, nedensellik, imar), `drawer_frac_half_low` 0,45 (`road_draw`, `inspector`).
- `HudRoot.DRAWER_LOW_PANELS` hangi panellerin alçak açıldığını söyler. Masaüstü etkilenmez.
- Gerçek iPad ve parmakla denenmedi; sahip denemesinden sonra yalnız veri değişir.
