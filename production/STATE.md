# Üretim durumu

Tek devam noktası. `CHECKPOINT` bloğu SessionStart hook'u ile her oturuma enjekte edilir; `handoff` skill'i günceller. Geçmiş: `production/log/`.

<!-- CHECKPOINT:BEGIN -->
- Tarih: 2026-10-20 · Dal: task/T-001-ismeral-world (main'e alınması kullanıcıda; worktree kullanılmıyor)
- M0: operasyonel olarak KAPALI (açık doğrulama eksikleriyle): C-02 PASS; C-07 KISMİ (doğrudan yol canlı PASS, dolaylı yeni-guard senaryoları canlı DOĞRULANMADI → T-901, engellemez). `production/M0-CLOSURE.md` Çalıştırma 3
- M1: **T-001 DONE** (Ismeral dünya iskeleti; art-director GEÇER, QA PASS; `production/tasks/T-001.md`). Önizleme: `tools/godot.sh --path . res://scenes/dev/world_preview.tscn -- --preset=metro`. Sıradaki: T-002 (sim çekirdeği), T-007 (platform profili/export zinciri); T-001 takipleri T-001a–d (ışık+harbor dikiş deliği, ada/batimetri, alt-hücre kıyı+D4 parseller, arazi paleti spesifikasyonu)
- Kararlar: D-001 POC silindi · D-002 başlangıç ilçesini oyuncu seçer · D-003 Windows+macOS birincil, iPadOS ikincil · D-004 iPad Pro (M) + Apple Developer hesabı var, iPad testi M1'de, renderer sabit değil
- Açık (engellemeyen): Q-003 para birimi. Engelleyen soru: yok
- Kanıtlanmamış: birleşik yük (render+sim) performansı, iPadOS zinciri ve iPad perf, renderer karşılaştırması, platformlar arası determinizm (Intel↔ARM; yükseklik FastNoiseLite), kıyı alt-hücre doğruluğu
<!-- CHECKPOINT:END -->
