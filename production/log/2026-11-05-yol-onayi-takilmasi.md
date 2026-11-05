# 2026-11-05 · Yol onayı takılması (ADR-0010 Karar 5) — kaynak bulundu ve düzeltildi

Ayrıntı ve ölçümler: `production/bugs/B-040.md` (düzeltme), `B-041.md` (kalan paylar, öneri). Dev Mac (i7-8850H / Radeon Pro 560X, Compatibility, 1600x900), iPad DEĞİL.

- Kaynak: yol görünümü bitince `LifeHost` Yaşam verisini TEK karede yeniden kuruyordu (`index_edges` 73 ms + `begin_rebuild` 11 ms + 5000 parsel/kare ~37 ms x 5 kare). ADR-0010'daki "beş yol tüketicisi" hipotezi ölçümle çürüdü (yol kalemleri kare başına ~5-15 ms).
- Düzeltme (yalnız görünüm): `LifeEdgeActivity.step_refresh` + `LifeHost` süre bütçesi (3 ms/kare). Sim/GOLDEN/`playable.gd` dokunulmadı.
- Önce/sonra en kötü yol-penceresi karesi (aynı probe, `--life-old` A/B): önce 137 / 202 / 233 / 279 ms (4 koşu), sonra 21,9 / 24,2 / 36,2 ms (teslim kodu, 3 koşu); >50 ms kare önce 5, sonra 0.
- Yeni araç: `tools/godot/road_window_probe.gd` (`--split`, `--nodes`, `--life-split`, `--life-old`).
- Doğrulanmadı: iPad; imar/yıkım/geri al pencereleri; Life'ın yeni yol kenarını ~1 sn geç göstermesinin gözle etkisi.
