# Üretim durumu

Tek devam noktası. `CHECKPOINT` bloğu SessionStart hook'u ile her oturuma enjekte edilir; `handoff` skill'i günceller. Geçmiş: `production/log/`.

<!-- CHECKPOINT:BEGIN -->
- Tarih: 2026-10-20 · Dal: claude/imaro-mayor-studio-setup-ad0bdb (worktree) · M0 stüdyo kurulumu TAMAM (docs/STUDIO.md, docs/STUDIO-VALIDATION.md)
- Milestone: M1 "Tek dünya iskeleti" başlıyor (production/ROADMAP.md)
- Next: T-001 (Ismeral dünya verisi + metro render + dünya-kanon testleri) ve paralelde T-002 (sim çekirdeği; T-900 StateHash üzerine) — ikisi de `ready`
- Son tamamlanan: T-900 StateHash (QA 7/7 PASS). Motor: Godot 4.7.2 / Compatibility (ADR-0001)
- Repo oyun içeriği içermiyor: eski POC kullanıcı tarafından silindi (D-001, ADR-0003)
- Kullanıcı kararı bekleyen: Q-002 (ilk ilçe — M2'yi bloklar), Q-003 (para/dil), Q-004 (platform önceliği + cihaz)
- Doğrulanmamış: yeni oturumda proje ajan/skill kaydı ve env model yönlendirmesi; Blender MCP'nin LLM üzerinden çağrısı; iPad (bkz. STUDIO-VALIDATION §5)
<!-- CHECKPOINT:END -->
