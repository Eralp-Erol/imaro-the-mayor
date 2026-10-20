# Üretim durumu

Tek devam noktası. `CHECKPOINT` bloğu SessionStart hook'u ile her oturuma enjekte edilir; `handoff` skill'i günceller. Geçmiş: `production/log/`.

<!-- CHECKPOINT:BEGIN -->
- Tarih: 2026-10-20 · Dal: claude/imaro-mayor-studio-setup-ad0bdb (worktree; main'e alınmayı bekliyor) · M0 stüdyo kurulumu TAMAM (docs/STUDIO.md, docs/STUDIO-VALIDATION.md)
- Kararlar: D-002 başlangıç ilçesini oyuncu seçer (Orven yalnız M2 geliştirme test alanı) · D-003 Windows+macOS birincil, iPadOS ikincil (ADR-0004) · Q-003 para birimi bilinçli AÇIK (config, `¤`)
- Milestone: M1 "Tek dünya iskeleti + platform temeli" (production/ROADMAP.md)
- Next: paralel grup A — T-001 (Ismeral dünya verisi), T-002 (sim çekirdeği), T-007 (platform profili + export) — üçü de `ready`
- Kullanıcıdan beklenen (karar değil, kaynak): Windows test cihazı (T-006 çalıştırma testi), iPad + Apple hesabı (M2, T-008)
- Doğrulanmamış: yeni oturumda proje ajan/skill kaydı ve env model yönlendirmesi; Blender MCP'nin LLM üzerinden çağrısı; Windows/iPad hiç çalıştırılmadı
<!-- CHECKPOINT:END -->
