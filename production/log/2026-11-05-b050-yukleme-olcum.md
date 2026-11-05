# 2026-11-05 · B-050/B-051: kayıt yükleme sonrası bina çizimi ölçümü ve düzeltmesi (B-025 artığı)

Dal: `worktree-agent-aad506b5c9de50cbc` (main `bf757d4`'e ff). Godot 4.7.2 başsız, gerçek `scenes/game/playable.tscn`, `nice -n 19`, kilit `/tmp/imaro-godot.lock`. Makine: Intel i7 Mac, yük 3-4; **iPad DEĞİL**. `src/game/playable.gd`, `src/sim/*`, kayıt biçimi, GOLDEN, `src/view/life/*`, `data/view/life.json` DEĞİŞMEDİ.

## Prob
`tools/godot/b050_load_probe.gd`: oyun akışı (gerçek `_process` kare yolu, `SimBuildingPump`): kamulaştırmalı yol (seed 7 adayı, D2: 15 parsel, 10 T0 yapılı) -> yıkım -> `municipal_lands` -> `zoning_propose(zone.residential, municipal_reuse)` -> gün 134 -> `export_save`. Sonra (a) AYNI süreçte `import_save` + `resync_sim_buildings_after_load` + kare yolu, (b) YENİ playable sürecinde (tick 0) aynı baytlarla yükleme (oyuncunun gerçek yüklemesi). Sayım: sim'de `developed_by_sim` + yapı evresi + birim > 0 olan parseller vs projector satırı/`unplaced`; T0 görünümünde çizilen yapılar vs yolun aldığı 10 T0 yapılı parsel.

## ÖNCE (düzeltmesiz)
- Canlı (kayıt anı): sim 12 `built` (hepsi eski T0 parseli) -> projector 11 satır + 1 `unplaced` (`t0_merged`).
- Aynı süreçte yükleme, sakinleşince: **2 satır, 9 parsel eksik** (19546, 19833-19836, 19838, 19839, 19857, 19858). T0 görünümü: 24.294 çizili (alınan 10 gizli) = canlı.
- Yeni süreçte yükleme, sakinleşince: **2 satır, 9 parsel eksik**. (Bu ilk koşuda hayalet-T0 sayacı yoktu. B-051'in "önce" sayısı (10) ara koşudan: projector düzeltmesi vardı, takipçi kodu özgündü; takipçi projector'dan bağımsız olduğu için "önce" değerini değiştirmez.)
- `resync_sim_buildings_after_load`: 1063,7 ms (aynı süreç), 1122,2 ms (yeni süreç); T0 DIŞI 16.205 parsel okuması.

## SONRA (B-050 projector süpürmesi; takipçi düzeltmesi B-051 aşağıda)
İki koşu (ara koşu: yalnız projector düzeltmesi; son koşu: projector + takipçi düzeltmesi). Son koşu sayıları, parantezde ara koşu:
- Aynı süreç: yükleme anında 11 satır (bayat T0 satırları korunur), süpürme sonrası **11 satır, 0 eksik** (+1 `unplaced`). Süpürme: +24.304 okuma (toplam 41.652), 636 (639) kare, `ms_max` 5,1 (5,2) ms, `ms_sum` 2405,9 (2417,9) ms (kare başı ort ~3,8 ms, `_process` taban işi dahil).
- Yeni süreç: yükleme anında 2 satır (9 eksik, süpürme bekliyor), süpürme sonrası **11 satır, 0 eksik** (+1 `unplaced`). 694 (665) kare (60 Hz'de ~11-12 sn oyun zamanı), `ms_max` 45,2 (46,4) ms (nedeni ayrıştırılmadı; düzeltmesiz yeni-süreç koşusunda 38,9 ms vardı).
- `resync_sim_buildings_after_load`: 1169,6 / 1180,1 (1183,3 / 1176,7) ms (aynı iş, fark gürültü; `sync()` ham okuması AYNI: 17.348 / 16.205).
- Yeni süreç, hayalet T0 (B-051): `T0_TAKEN_STILL_DRAWN` 10 -> **0**, `follow_taken` 0 -> 10, çizili T0 yapı 24.304 -> 24.294 (canlıyla aynı).

## B-051 (bu ölçümde bulundu): yeni süreçte yüklemede hayalet T0 binaları
Yeni süreçte yükleme sonrası yolun aldığı 10 T0 yapılı parselin eski binası ÇİZİLİYOR (`T0_TAKEN_STILL_DRAWN = 10`, takipçi `follow_taken = 0`; canlıda 0 çizili, 10 gizli). Neden: `restore_parcels` (arsa geri açma) parseli dünyaya aynı kimlikle boş döndürür, ağ sürümünü değiştirmez; takipçi yalnız `net.parcels` bakıyordu. Düzeltme `PlayableExpropriation._reused_land()`; ayrıntı `production/bugs/B-051.md`. SONRASI sayı yukarıda (son koşu).

## Testler
- `tests/game/m2_change_feed_projector_test.gd` (+3 yeni, 2 mevcut test süpürmeye uyarlandı), `tests/game/playable_expropriation_test.gd` (+2).
- YEŞİL: bu iki dosya + `m2_sync_budget_test` + `playable_expropriation_vegetation_test` + `can03_guard_test` + `m2_causal_loop_test`: 0 hata (iki dosya birlikte 23/23).
- KIRMIZI (iki düzeltme geçici kapalı: `reused.has(pid)` -> `false`, `_t0_sweep` boş): 5 yeni test KIRMIZI (`reused_land_t0_buildings_stay_hidden...`, `a_full_reconcile_does_not_show...`, `drawn_after_a_save_load`, `pump_gives_the_t0_sweep...`, `t0_sweep_after_a_load_is_frame_sliced...`); düzeltmeler geri alındı (dosyalar bayt-bayt yedekten döndü).

## Doğrulanmadı / yapılmadı
iPad/dokunmatik; pencereli ekran karesi (başsız ölçüm: çizim sayıları `BuildingView.stats`/sütunlardan, görüntü alınmadı); `verify full`; başka seed/bölge; yükleme sırasında sürekli tick (sim duraklatılmış ölçüldü).
