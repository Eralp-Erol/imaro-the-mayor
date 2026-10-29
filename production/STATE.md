# Üretim durumu

Tek devam noktası. `CHECKPOINT` bloğu SessionStart hook'u ile her oturuma enjekte edilir; `handoff` skill'i günceller. Geçmiş: `production/log/`.

<!-- CHECKPOINT:BEGIN -->
- 2026-10-27 DEVAM (Claude devri): kullanıcı açık talimatıyla durmadan sürüyor; push/main/ana checkout yok. Kilit claude-t057-continue-20261027.
- DONE (koşullu, proposed teslim): T-057 bitkiler (LOD0->LOD1, Karar 5), T-058 donatı (8), T-059 insan (6 model). Son tam doğrulama: `verify full` HEAD a8dbd41 PASS (1633 test, canon-guard 105, smoke 180 kare).
- KULLANICI ONAYLARI (D-005, 2026-10-27): 60 approved (21 hero bina, 10 bitki, 8 donatı, 6 insan, 14 zemin, veg_plane), 45 rejected (eski kit). Onay sistemi: artifacts/library/approval.html + tools/library/apply_approvals.py (hash'e bağlı), design/library/approval-system.md.
- T-062 (onaylı varlıkları oyun demosuna entegre): plan hazır docs/adr/ADR-0006-*.md; kararlar (Studio Director): saat kulesi yok (T0 landmarksız), hero tek boy inşaat, dükkânlı zemin yalnız bazaar, 7 aile x 3 stil, insan bu işte yok, rejected kit dosyaları silinmez. Sıra A0..A5 (bina+zemin) -> B (bitki) -> C (donatı). Perf tabanı street p95 16,43 ms (bütçe 16,6) — risk.
- Açık (kullanıcı): Q-018 (insan stili, palmiye/mevsim), T-055 zemin değerlendirmesi hâlâ işaretli ama zeminler approved; Q-003..Q-017. T-060 araç, T-061 yol kesiti T-062'den sonra.
- Ölçülmedi: şehir/iPad bütçesi, hareketli LOD geçişi, hücre lekesi (HLOD).
<!-- CHECKPOINT:END -->
- 2026-10-29 DURAKLAMA (kullanıcı: "t-062den sonra pause"): T-062 kapandı (koşullu), verify full PASS 1856 test; kamera 50 m-18 km + eğim + çatı açıklığı. Yeni iş başlatılmadı; ayrıntı production/log/2026-10-29-T-062-kapanis-duraklama.md.
