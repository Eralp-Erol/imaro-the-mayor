# 2026-11-01 QA: GOLDEN_X bağımsız doğrulama (T-065 ön koşulu P3, ADR-0009)

Doğrulayan: qa-engineer (yazıcı değil). Dal: `agent/handover-imaro-m01-349562fb` (HEAD 696bf0c). Donanım: macOS (Darwin 24.6.0), Godot 4.7.2 başsız. Kod/veri değişikliği commit'lenmedi; mutasyonlar geçici, geri alındı.

## Doğrulandı (koştum, gördüm)
- `golden_expropriation_undo_test.gd` + `m2_query_test.gd` 3 AYRI Godot sürecinde: her seferinde 24/24 geçti (5 + 19), `GOLDEN_X_CANDIDATE=9b935788...72289` üç koşuda da aynı; GOLDEN_A/B sabitleri (d66d81a9..., 3e85ce2c...) iddia ediliyor ve geçti (bit-bit aynı).
- Kod okuma: hash `GameState.state_hash()` = `StateHash.of({world_seed, tick, config, rng, reasons, systems, pending_commands, command_log, next_command_seq})`. Kanonik: sözlük anahtarı sıralı, float IEEE-754 binary64, NaN/-0 kanonik. `src/sim` içinde `randf/randi/Time./OS./Engine.get_*` yok. Tek `get_instance_id()` kullanımı (`expropriation_flow.gd:35`, `public_work_demolish_handler.gd:117,124`) yalnız bellek-içi memo ANAHTARI; duruma/hash'e girmez (3 süreçte hash aynı).
- Senaryo gerçekten üç sistemi sürüyor: `test_scenario_commands_all_take_effect...` olay sırası (expropriated, built, restored, removed, expropriated, built, built, demolished) ve `test_the_locked_scenario_really_exercises...` (road_cost + road_refund + road_demolish defter kalemleri, tepki defteri satırı, >=3 tarama, tam 1 PE-01 öğesi) geçti. Kayıt/yükle (tick 30) round-trip testi geçti.
- Mutasyon duyarlılığı (hash DEĞİŞMELİYDİ; hepsi değişti, kontrol ayni kaldı). Senaryo: geri al adımı kaldırıldı -> e5bf20ab...; yolu yık kaldırıldı -> d73b4fab...; A' kamulaştırmasız (expropriate=false) -> 24d13593...; FINAL_TICK 61 -> f5b2a73a...; 3 yerine 2 haftalık tarama -> 00f8e348.... Veri: `cause.threshold` 10->11 -> 55a957b8...; `cause.weights.road_proximity` 300->301 -> 8a3351c2...; `demolish_cost_per_m` 15->16 -> 7201eafe...; `initial_balance` 50000->50001 -> ce97080c...; `window_days` 360->30 -> a3c41897...; `district_gain` 400->0 -> 82639ca8...; `housed` grievance `gain` 400->0 -> ea7fd024....
- `tests/sim/public_works` + `tests/sim/politics` (36 suite, tek süreç): 381/381 geçti, 0 hata, 0 orphan, çıkış 0. Birleşme sonrası yeni şeyler (sözleşme 1.6, yolu yık, tepki geri alma, undo_reaction_window, undo_demolish_real_world) bu koşuda temiz. Hata yok: B-009 AÇILMADI.

## Hash'in KAPSAMADIĞI / zayıf kaldığı yerler (ölçüldü)
- Bu mutasyonlarda hash DEĞİŞMEDİ: `window_days` 360->361, `district_gain` 400->401, `agenda.min_displacement_pm` 20->21, `local.floor_pressure_pm` 600->0, `local.proximity_share_pm` 500->0. İlk üçü küçük deltalar (tam sayı yuvarlama/eşik altı); `floor_pressure_pm` ve `proximity_share_pm` bu senaryoda HİÇ etki etmiyor (0'a çekmek bile hash'i oynatmıyor). T-065 bu iki düğmeye ya da yeniden iskân politikası bayrağına dokunursa GOLDEN_X onu yakalayamaz; politika-AÇIK yol ayrı sabit/test ister.
- `reactions.json` yapılandırması politika config digest'ine girmez (dosya notu, bilinçli); hash yalnız çıktı durumunu (defter, sinyal, açılan öğe, `scans` sayacı) görür. Yapılandırma değişikliği ancak çıktıyı oynatırsa fark edilir.
- Yol AĞI (WorldNetwork) ve gerçek parsel/hane verisi hash'te yok: dünya ReactionWorldBase sahte köprüsü (`FakeExpropriationWorld`, parsel 1-3 köşegende, 6 yakın) + 6 parsel. Gerçek Ismeral kamulaştırması hash'lenmiyor (yalnız `real_expropriation_world_test` / `undo_demolish_real_world_test` davranış testleri).
- Tek tohum (SEED) ve tek komut dizisi; "farklı tohum -> farklı hash" bu senaryo için test edilmiyor. Tek hız/kare yolu (frame bağımsızlığı) yok; `advance` hep tam sayı tick.
- Politika (yeniden iskân) kapalı hâli kilitli; açık hâli kilit dışı (henüz yok).
- Süreç içi `get_instance_id` memo anahtarı: ayrı durum nesnesi ID'si yeniden kullanılırsa (import_save sonrası) aynı tick + graph_version + command_id'de eski memo dönebilir (varsayım, tetiklenmedi; kayıt/yükle testi geçiyor).

## Test edilmedi
`verify quick/full` koşulmadı (istenmedi); yalnız belirtilen dosya ve iki klasör. Perf/görsel yok. Başka dalın (T-048 roads) etkileşimi bakılmadı.
