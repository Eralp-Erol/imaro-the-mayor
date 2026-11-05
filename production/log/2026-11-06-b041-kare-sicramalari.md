# 2026-11-06 · B-041 yol onayı penceresi kalan kare sıçramaları — kaynak ölçüldü

Ölçüm ortamı (HEPSİ): dev Mac i7-8850H / Radeon Pro 560X, Compatibility, pencereli `scenes/game/playable.tscn --demo`, 1600x900, VSync kapalı, hız 3, tek yol (tohum 4311), `nice -n 19`, `tools/godot/road_window_probe.gd`. **iPad ölçümü DEĞİL**; iPad sayısı yok. Makine paylaşımlı: koşu başı/sonu `uptime` 1 dk yükü 3,0-6,9 (başka ajanların süreçleri); koşular arası yayılım büyük (aynı kodda ortalama kare 8,7-22,3 ms). ADR-0010'daki "yük > 8 atılır" kuralı burada tetiklenmedi, ama yük gürültüsü aşağıdaki karşılaştırmaları sınırlar (açıkça belirtildi).

## 1. Sıçramanın kaynağı (bulgu: yol penceresi DEĞİL, tick'li kare + HUD)
`--split` kare dökümünde tick'li karelerin ~30 ms'si yol hiç gönderilmeden (`--no-road`) de var. Kalemlere bölünce:

| Kalem (tick'li kare, ms) | ölçüm |
|---|---|
| `hud.poll()` -> `HudRoot.refresh()` | ort 28-30, maks 33-36 (sakin koşuda ~21-25); yalnız tick'li karelerde |
| ...bunun içinde `DecisionPanels._on_refreshed` -> `_update_trust_notice()` (`CouncilTrustNotice.affected_members`) | **21,8** (10 tekrar; `snapshot` 0,7, `top_bar` 0,2, `_relayout` 0,2) |
| sim sürüşü (`facade.drive_usec`) | ort ~4 (maks 11-12) |
| Yaşam `reader.poll` | ~1,4 |

- Yani "20-36 ms sıçramaları"nın baskın kaynağı bu görev kapsamında DEĞİL: `src/ui/flows/decision_panels.gd` (B-081, a818bf3). Ayrıntı, ölçüm ve öneri: `production/bugs/B-042.md` (UI alanı, dokunulmadı).
- Tanı koşulu `--no-decision-refresh` (probe, yalnız o süreçte bu aboneyi keser): kontrol (yol yok) koşusunda p95 29,6 -> 14,3 ms, maks 32,6 -> 22,6 ms (`A_ctl1` / `B_ctl1`).

## 2. Yol penceresinin GÖRÜNÜM payı (sakin koşular, `--split --nodes --no-decision-refresh`; kare başına kalem ms)
| Kalem | değer | kaç kare |
|---|---|---|
| `RoadEditSync.poll` uzak mesh dilimi (`step_far`) | 4,7-8,5 | ~10 ardışık kare |
| ...ayrıntı (geçici sayaç, geri alındı): bir 24k köşeli yüzey = `merge_parts` 0,6-1,0 + `add_surface_from_arrays` 3,3-4,4; `_begin_far_job` 0,5; son takas 0,1 | | 10 yüzey |
| bitki koridoru (`playable.gd`, DOKUNULMADI) | 8,7-13,5 | 1 |
| Yaşam bütçeli yenileme (`runtime_rebuild_budget_us` 3000) | 3-4,5 (+ `reader.poll`) | ~100-130 |
| Yaşam, dizin bitişi (yerine koyma + hücre listeleri sıralama) | 8-11 | 1 |
| Yaşam `begin_rebuild` (40k parsel anahtarı sırala) | **14-23** (en büyük tek görünüm kalemi) | 1 |
| `roadpoll_join/install` | 2,8-4,1 | 1-2 |

Sakin koşuda (HUD payı kapalı) yol penceresinin en kötü karesi 19-22 ms, kontrol 22,6 ms: yani görünüm payı HUD'sız ~kontrol düzeyinde (`B_road3`: ort 7,7 / p95 15,1 / maks 22,4 ms; `B_ctl1`: 7,0 / 14,3 / 22,6). Kare dilimi ana hatlarıyla B-040'tan beri doğru çalışıyor.

## 3. Denenenler (eşli, serpiştirilmiş, `--split`, senaryo B; üçer koşu, medyan)
| Deney | Sonuç | Karar |
|---|---|---|
| E1 · Yaşam yenileme dilimini tick'li karede ertele (en çok 2 kare, `life.json` ayarı) | tick'li karede Yaşam payı ort 2,7 / 3,3 / 3,5 -> 2,7 / 2,3 / 3,6 ms (medyan 3,3 -> 2,7; kazanç <= ~0,6 ms); yenileme süresi 100-147 -> 99-136 kare (anlamlı fark yok); kare maks/p95 ayırt edilemez (gürültü içinde) | **GERİ ALINDI** (kazanç yok) |
| E2 · uzak mesh dilimi küçült (`far_group_verts` 8000 + 1,5 ms bütçe; 12000 + 2,5 ms) | `step_far` maks 8,7 -> 7,4 / 6,6 ms, ama ~10 -> 19 / 15 kare; kare p95 19,2 -> 22,0 / 19,5, maks 29,6 -> 29,5 / 31,1 (kazanç yok); uzak modda yüzey (draw call) sayısı ~10 -> ~30; draw call ölçülmedi | **GERİ ALINDI** |
| E3 · `begin_rebuild` anahtarlarını `PackedInt64Array` ile sırala (aynı sıra) | mikro ölçüm 40.493 anahtar: `keys()+Array.sort` 9,2 ms -> paketli 3,3 ms (3 tekrar, aynı sonuç `q == p`). Yaşam en büyük kare (`life max`): F0 22,1 / 23,5 / 23,0 -> F1 11,8 / 17,4 / 15,8 (medyan 23,0 -> 15,8 ms, 3/3 koşuda düştü) | **UYGULANDI** |

## 4. Önce / sonra (motor sürümlü, bölmesiz: toplam kare süresi; ms; 150 karelik yol penceresi; 3 koşu serpiştirilmiş)
Kod değişikliği tek karelik bir kalemi hedefliyor; pencere toplamlarında etkisi gürültünün içinde (aşağıda) ve **kanıtlanmış bir pencere-düzeyi kazanç YOK**. E3 yalnız hedeflediği kalemde (Yaşam en büyük kare, bölüm 3) ölçülmüş kazanç gösterdi.

Senaryo A (teslim edildiği gibi, HUD güven şeridi dahil):
| | ort (3 koşu) | p95 | en kötü tek kare | >33,3 ms kare | yük (başı->sonu) |
|---|---|---|---|---|---|
| ÖNCE | 22,3 / 10,8 / 13,0 (medyan 13,0) | 48,3 / 29,8 / 34,2 (34,2) | 57,5 / 40,6 / 47,5 (47,5) | 54 / 5 / 12 | 3,8-5,1 |
| SONRA | 18,4 / 15,5 / 14,3 (15,5) | 44,1 / 38,8 / 35,6 (38,8) | 56,9 / 50,8 / 48,0 (50,8) | 45 / 33 / 26 | 3,7-5,1 |

Senaryo B (tanı: HUD güven şeridi probe'da kapalı; görünüm payı görünür):
| | ort | p95 | en kötü tek kare | >33,3 ms kare | yük |
|---|---|---|---|---|---|
| ÖNCE | 8,7 / 12,2 / 20,1 (12,2) | 15,6 / 22,3 / 38,3 (22,3) | 26,6 / 47,4 / 72,1 (47,4) | 0 / 2 / 16 | 4,3-5,5 |
| SONRA | 13,3 / 12,2 / 11,1 (12,2) | 23,6 / 22,4 / 20,9 (22,4) | 39,4 / 33,7 / 41,9 (39,4) | 1 / 1 / 1 | 4,3-5,5 |

- Önceki B-040 sonrası koşular (aynı gün, kod öncesi): A `road1/2/3` ort 13,7 / 15,3 / 12,6, p95 34,8 / 37,2 / 34,7, maks 47,0 / 54,3 / 46,7; kontrol (yol yok) ort 8,4, p95 29,6, maks 32,6. B: `road1/2/3` ort 13,0 / 19,3 / 7,7, maks 37,7 / 48,7 / 22,4; kontrol 7,0 / 14,3 / 22,6.
- Yorum (HİPOTEZ, kanıtlanmadı): koşular arası yayılım (aynı kodda ort 7,7-22,3) değişikliğin payından büyük; farkın nedeni makinedeki başka ajan yükü (`at_tick` 858-936 arası kayıyor: yavaş koşularda yol daha geç gönderiliyor).
- ADR-0010 ölçütleri (masaüstü, yol penceresi): en kötü kare 47-57 ms (A, HUD payıyla) ve 34-47 ms (B); >33,3 ms kare sayısı B'de <= 2 (medyan), A'da 5-54. A'da hedef (<= 3) karşılanmıyor; neden bölüm 1 (HUD).

## 5. Değişen yollar
- `src/view/life/life_edge_activity.gd`: `_rebuild_keys` `PackedInt64Array`; `begin_rebuild` paketli sıralama (aynı sıra, aynı sonuç).
- `tests/view/life/life_activity_layout_test.gd`: +2 test (işleme sırası ekleme sırasından bağımsız artan kimlik; boş durumda anında biter).
- `tools/godot/road_window_probe.gd`: yeni bayraklar `--no-road` (kontrol), `--no-decision-refresh` (tanı), `--hud-cost` (HudRoot.refresh/abone dökümü), `--life-defer=N`, `--far-verts=N`; her karede `proc_sim_drive` / `proc_hud_poll`; gdlint max-line 120 (eski satırlar da düzeltildi).
- `production/bugs/B-042.md` (yeni, UI alanı), `B-041.md` (sonuç bölümü), bu kayıt.

## 6. Doğrulanan / varsayılan / test edilmeyen
- Doğrulanan: `tools/verify.sh quick` PASS (130 suite, 1194 test, 0 hata; kısmi, ATLANDI satırı çıktıda); gdlint (probe + src + test) temiz; mikro ölçüm ve eşli koşular yukarıdaki gibi.
- Varsayılan/HİPOTEZ: yük gürültüsü açıklaması; `reasons_for` maliyetinin neden kaydı büyüklüğüyle arttığı (B-042).
- Test edilmeyen: iPad/cihaz; uzak mod draw call etkisi (E2 geri alındığı için ölçülmedi); imar/yıkım/geri al pencereleri; bitki koridoru kaymaları (`playable.gd`, kapsam dışı); sakin (< 2 yük) makine.
