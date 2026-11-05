# D-023 · Meclis ve Bütçe düğmeleri oyunda görünsün (2026-11-05)

Kaynak: sahip, Q-038 soru kartı. Kararı sahip verdi; aşağıdaki kelime sahibindir.

- Soru: Oyunda Yönetim modunda Meclis ve Bütçe düğmeleri görünsün mü? (Şu an yalnız Politikalar vardı.)
- Sahibin cevabı: **"gorunsun."** → Seçenek A: Meclis ve Bütçe (ve Gündem) düğmeleri Yönetim modunda görünsün.

## Uygulama
- `src/game/playable.gd`: `DecisionPanels.attach(..., true)` (satır sayısı 999, değişmedi).
- Meclis, Bütçe ve Gündem Yönetim modu araç çubuğunda; her biri iPad'de çekmecede yarı açılır (D-021/D-022).
- B-124 kapandı; karakterizasyon testi (`tests/game/drawer_real_scene_test.gd`) ters çevrildi.
- Gerçek iPad ve parmakla denenmedi.
