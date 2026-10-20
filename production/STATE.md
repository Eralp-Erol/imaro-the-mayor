# Üretim durumu

Tek devam noktası. `CHECKPOINT` bloğu SessionStart hook'u ile her oturuma enjekte edilir; `handoff` skill'i günceller. Geçmiş: `production/log/`.

<!-- CHECKPOINT:BEGIN -->
- Tarih: 2026-10-20 · Dal: dev/m1-parallel (T-001 dalından; paralel hatlar, path-scoped commit; main'e alma kullanıcıda; worktree yok)
- Çalışma modeli: `production/LANES.md` + `tools/lane.sh` (status/check/verify/commit). Aktif hatlar: sim (T-027), world (T-005), render (T-012). Bitenler: T-001..T-004, T-007, T-011, T-015, T-018, T-019, T-021, T-023, T-025 (kanıt: `production/tasks/`)
- M0: operasyonel kapalı (C-07 kısmi → T-901). M1: T0 dünya (arazi+yol/parsel), kamera, yapı kiti, UI temeli, sözleşmeler, platform profili, sim çekirdeği hazır; T-012 (yapı render), T-005 (T0 yerleşim), T-027 (SimFacadeImpl) sürüyor; sıradaki T-013 (ekonomi), T-016/T-017 (aktör/siyaset), T-022 (karar akışları), T-008 (iPad cihaz testi), T-006 (M1 kapısı)
- Kararlar: D-001..D-004. Açık (engellemeyen): Q-003 para birimi, Q-005..Q-013 (protagonist, partiler, seçim, kaybetme, rakipler, ton, UX tercihleri, takvim, kit v0 soruları)
- Kanıtlanmamış: birleşik yük (render+sim) performansı, iPadOS zinciri ve iPad perf (cihaz), Windows çalıştırma, renderer karşılaştırması (T-010), platformlar arası determinizm (T-009), alt-hücre kıyı, gerçek fare/trackpad/dokunma elle denemesi
- **ZORUNLU DURAKLAMA:** M1 teknik kapanış + T-030 demo sonrası dur ve kullanıcıya sun; M2/yeni özellik görevi onaysız başlatılmaz. Onay bekleyen: Q-015 (coğrafya), T-008 (iPad cihaz testi). Sürenler: T-017, T-028, T-029, T-030. Backlog: T-014, T-026, T-001a–c, kit v1, T-009/T-010.
<!-- CHECKPOINT:END -->
