# Yıkım tepkisi: yüksek yerel, çok az ama sıfır olmayan ilçe geneli (sim) — 2026-11-01

REQ: CAN-03, SIM-05, SIM-12, TEK-01/02 · Karar: D-014 §3 (kullanıcının sözleri), D-015 yönü (yeniden iskân, sonra).
Dal: `worktree-agent-aa3b6ef730d618210` (taban: `agent/handover-imaro-m01-349562fb` d6a9b14, ff).

## Ne yapıldı (hepsi veri odaklı, `data/politics/reactions.json` `local`; çalışma değeri, kanon değil)
- Evi yıkılan + yol dibindekiler YÜKSEK: `min_displacement_pm` 20 -> 5 (tek yıkılan ev bile açar), `proximity_share_pm` 250 -> 500,
  yeni `floor_pressure_pm` 600 (yerinden edilen varken öğe baskısı >= 600, kalabalıkla 1000'e çıkar).
- İlçe geneli çok az ama > 0: yeni `district_floor` 1 / `district_gain` 400 -> `ReactionAgenda._district_grievance`, haftalık
  `max(1, hane x 400 / bölge hanesi)` puan, bölge payı olan her kesimin yerinden edilme konulu şikâyet defterine.
- "Yeni ev sunulursa tepki biter": UYGULANMADI (koordinatör kararı; sim'de mekanizma yok: haneler bölge toplamı,
  `household_fate = return_to_latent`, ne hane ne belediye yeni ev bulur/sunar). Karar TEK noktada:
  `ReactionRehousing.still_unhoused(region_code, command_id, households)` — şimdilik hep `households` döner (hiç kimse
  yeniden yerleşmiş sayılmaz), davranış değişmez. D-015 politikası yalnız buraya takılır.
- Geri alma kancası: `ReactionAgenda.retract_command(state, command_id) -> int` (komut kimliğine bağlı yerinden edilme + yakınlık
  defter satırlarını siler; bilinmeyen komut = 0, durum değişmez). Açılmış gündem öğesini kapatmaz (EventEngine'in işi).
  Yol komutlarına dokunulmadı; çağıran: geri alma işleyicisi.
- Kod varsayılanı kapalı/0 (`ReactionConfig`): dosyasız koşular ve GOLDEN A/B değişmez.

## Önce / sonra: gerçek Ismeral D2 (tohum 1467, 400 gün, `expropriation_reaction_real_probe.gd`)
| Yol | Yerinden edilen hane | Önce: PE-01 baskı | Sonra: PE-01 baskı | Konut-maliyeti şikâyeti (barınan kesim) önce -> sonra |
|---|---|---|---|---|
| q10 | 0 | yok | yok (sessiz) | 0 -> 0 |
| q50 | 6 (19 yakın) | 170 | 678 | 0 -> 1 (gün 7-300) |
| q90 | 38 (30 yakın) | 975 | 1000 | 0 -> 1 |
| maks | 72 (72 yakın) | 1000 | 1000 | 0 -> 21 (gün 150), kesim G 9 |
Hepsinde yolun başına tek PE-01 (gün 35), `group.reacted` 0 (ilçe geneli tepki eşik altı: "çok az"). Şikâyet gün 400'de söner
(defter satırı 360 günlük pencereden çıkar). q10 ölçülmedi (0 hane yerinden: birim testi sessizliği sınar).
Yeniden yerleşen hane: gerçek D2'de bölge talebi 8686 > biten konut 6966 (açık 1720, büyüyor); yatırımcı yeni konut
bitirmiyor — yani yeniden yerleşme yok; zaten uygulanmadı.

## Doğrulama
`tests/sim/politics/expropriation_rehousing_test.gd` (16 test) + `expropriation_local_scale_test.gd` (orta yol testi yeni karara göre güncellendi). Ayrıntı: görev raporu.
