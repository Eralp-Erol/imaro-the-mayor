# M0 kapanış kontrolü

Bu oturumda (kurulum worktree'si) doğrulanamayan, **yeni bir oturumda** yapılması gereken kontroller. Kural: kanıt yoksa durum PASS olamaz. Durumlar: `BEKLİYOR` · `PASS` · `FAIL` · `DOĞRULANAMADI` (neden yazılır).
M0 kapanır: C-01…C-07, C-09, C-10 PASS olduğunda. Bir FAIL varsa T-001 başlamadan düzeltilir.

| # | Kontrol | Nasıl doğrulanır | Beklenen | Durum | Kanıt |
|---|---|---|---|---|---|
| C-01 | Harness `main`'de | Ana checkout'ta `git log --oneline -3 main` ve `test -f CLAUDE.md && test -d .claude/agents` | Kurulum commit'leri `main`'de; dosyalar mevcut | BEKLİYOR | |
| C-02 | SessionStart hook canlı oturumda | Yeni oturumda ilk soru: "SessionStart bağlamında hangi checkpoint'i gördün?" | `production/STATE.md` checkpoint'i, Q-003 "açık, engellemiyor", son doğrulama satırı | BEKLİYOR | |
| C-03 | Proje ajanlarının keşfi | Yeni oturum `Agent` aracını `subagent_type: qa-engineer` ve `subagent_type: design-director` ile "Reply only: OK" istemiyle çağırır | İkisi de yanıt verir; "Agent type not found" = FAIL | BEKLİYOR | |
| C-04 | Opus/Sonnet yönlendirmesi | Terminalde (bir kez `claude auth login` sonrası), yeni worktree kökünde: komut aşağıda | `modelUsage` anahtarlarında `claude-sonnet-5-5` (qa-engineer) ve `claude-opus-5-5` (technical-director) var | BEKLİYOR | |
| C-05 | Haiku yasağı | C-04 çıktısı + `python3.14 -I tools/studio_check.py` | Hiçbir `modelUsage` anahtarı `haiku` içermez; studio-check PASS. Alt ajan kullanımı `modelUsage`'da görünmüyorsa C-04/C-05 = DOĞRULANAMADI (PASS değil) | BEKLİYOR | |
| C-06 | Blender MCP bağlantısı | `tools/blender/start-mcp.sh` → yeni oturumda `blender` MCP sunucusunu onayla → `get_scene_info` çağır | Cube, Light, Camera döner. Blender açılmazsa veya sunucu bağlanmazsa FAIL | BEKLİYOR | |
| C-07 | Kanon koruması canlı | Yeni oturumdan `design/foundation/README.md` dosyasına bir satır eklemesini iste | Hook reddeder; ardından `tools/canon-check.sh` 11/11 | BEKLİYOR | |
| C-08 | Stop kapısı canlı (isteğe bağlı) | Oyun dosyasında küçük değişiklik yaptır, doğrulamadan bitirmeye çalıştır | Hook bir kez durdurur | BEKLİYOR (script düzeyinde test edildi) | `docs/STUDIO-VALIDATION.md` §3 |
| C-09 | Doğrulama hattı yeni worktree'de | `tools/verify.sh quick` | 5/5 PASS; Godot, `tools/godot.sh` ile ana checkout'taki `.tools/` içinden bulunur | BEKLİYOR | |
| C-10 | `artifacts/.gdignore` main'de | `git ls-files artifacts/.gdignore` | Dosya izleniyor (birleştirmede sessizce silinmemiş) | BEKLİYOR | |

C-04 / C-05 komutu (yeni worktree kökünde):
```bash
claude -p --output-format json "Use the Agent tool twice: subagent_type qa-engineer with prompt 'Reply only: OK', then subagent_type technical-director with prompt 'Reply only: OK'. Then answer DONE." | jq '{result: .result, models: (.modelUsage | keys)}'
```

## Kapanıştan sonra izlenen açık teknik riskler
| Risk | Kayıt | İlk kontrol noktası |
|---|---|---|
| Birleşik yük (render + sim) hiç ölçülmedi; tüm performans hedefleri kanıtlanmamış | ADR-0001 | T-006 |
| iPadOS zinciri (Godot 4.7.2 iOS şablonu → Xcode 26.3 → iPad) denenmedi | ADR-0004 §4 | T-007 |
| Renderer seçimi platform başına ölçülmedi | ADR-0001 §2, D-004 | T-010 |
| Platformlar arası determinizm (x86-64 ↔ ARM64) | ADR-0004 §2 | T-009 |
| Windows çalıştırma testi için cihaz yok | ADR-0004 §3 | T-006 |
| Proje ajan/skill kaydı ve model yönlendirmesi canlı oturumda görülmedi | bu dosya C-03…C-05 | M0 kapanışı |
