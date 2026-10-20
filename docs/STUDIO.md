# Imaro stüdyo harness'i

Kurulum: 2026-10-20 (M0). Doğrulama sonuçları: `docs/STUDIO-VALIDATION.md`.

## 1. Seçilen çerçeve: tek orkestrasyon katmanı
**Claude Code Game Studios (CCGS) omurga fikri olarak alındı, şablon olarak kopyalanmadı.** CCGS'nin değerli parçaları (Godot 4.7 referans dokümanları, GDScript/sahne kuralları, yön → uygulama → bağımsız inceleme ayrımı, checkpoint ile oturum devri, "çalıştır ve gözle" ilkesi) uyarlandı. Alınmayanlar: 49 ajan / 73 skill (bağlam yükü), "her yazmadan önce izin iste" protokolü (otonom üretimi durdurur), sprint/epic/story seremonisi, Unity/Unreal içeriği, Windows bildirimi, 5 Haiku skill'i. Superpowers ve GodotPrompter'ın kendi SessionStart iş akışları **kurulmadı**; yalnızca bağımsız skill'leri alındı — böylece tek bir iş akışı (bu belge + `dev-task`) var.

## 2. Organizasyon
```
Kullanıcı = Creative Director (kanon, AÇIK kararlar)
   │  production/QUESTIONS.md  ←  gruplanmış sorular
Ana oturum = Studio Director (opus): planlama, yönlendirme, entegrasyon, kayıt
   ├── design-director (opus)    kanon yorumu, tasarım sadakati kapısı
   ├── technical-director (opus) mimari, ADR, teknik çatışma, restart kararı
   ├── art-director (opus)       görsel kapı (yalnız gerçek capture), sanat spesifikasyonu
   ├── uygulayıcılar (sonnet):  simulation-engineer · godot-engineer · world-engineer
   │                            technical-artist · ui-engineer · systems-designer
   └── qa-engineer (sonnet, high) bağımsız doğrulama; uygulayıcı kendi işini onaylamaz
```
- **Yaratıcı otorite** kullanıcıdadır; `design/foundation/` hook ile kilitli, `design/decisions/` yalnız kullanıcının sohbette söylediğiyle yazılır.
- **Teknik otorite** technical-director + ADR'lardadır; rutin teknik kararlar sorulmadan alınır.
- **Uygulama** alan sahibi uzmandadır; küçük işleri ana oturum doğrudan yapar (ajan sayısı ilerleme değildir).
- **Bağımsız inceleme**: QA her görevde; director'lar türüne göre (mimari / sadakat / görsel).
- **Çatışma**: teknik → technical-director (kanıtla, gerekirse `experiments/` deneyi); yaratıcı → kullanıcı sorusu; precedence `design/CANON.md`.
- **Tasarım değişikliği yayılımı**: kullanıcı kararı → `design/decisions/D-NNN` → `design/REQUIREMENTS.md` güncellenir → REQ kimliğini içeren görevler `rg` ile bulunup yeniden `canon-check`'ten geçer.
- Ertelenen roller: audio-designer (M3), narrative-designer (karakter/parti kararları verildikten sonra, M4), release-engineer (M7). İhtiyaç anında aynı şablonla eklenir.

## 3. Model ve maliyet politikası
| Rol | Model | Effort |
|---|---|---|
| Ana oturum, design/technical/art-director | opus | high |
| simulation/godot/world-engineer, qa-engineer | sonnet | high |
| technical-artist, ui-engineer, systems-designer, Explore, claude-code-guide | sonnet | medium |
Haiku hiçbir yerde: tüm ajanlarda açık `model:`, yerleşik `claude-code-guide` (varsayılanı Haiku) ve `Explore` (varsayılanı Opus) proje override'ı, `env.ANTHROPIC_DEFAULT_HAIKU_MODEL=claude-sonnet-5-5` (arka plan görevleri), `env.CLAUDE_CODE_SUBAGENT_MODEL=sonnet`, `availableModels`. Sınır: proje ayarı yönetilen (managed) `deniedModels` kadar kesin kilit değildir; dokümante edilmiş en güçlü proje düzeyi önlem budur.

## 4. İş akışları
| İhtiyaç | Mekanizma |
|---|---|
| Gereksinim → milestone → görev | `plan-milestone` skill, `production/ROADMAP.md`, `production/tasks/T-NNN.md` |
| Görevi uçtan uca kapatmak | `dev-task` skill (hazırlık kapısı → kanon ön-kontrolü → yönlendirme → doğrulama → bağımsız inceleme → kayıt) |
| Kanon uyumu / çatışma / soru | `canon-check` skill, `design-director` |
| Görsel kalite | `visual-gate` skill, `art-director`, `tools/capture.sh`, `tools/visual-diff.sh` |
| Simülasyon doğruluğu | `sim-invariants` skill + `.claude/rules/simulation.md` |
| Asset üretimi | `blender-asset` skill; headless üreteçler + isteğe bağlı Blender MCP |
| Oturumlar arası devamlılık | `production/STATE.md` (SessionStart hook enjekte eder), `handoff` skill, `production/log/` |
| Paralel oturumlar | kullanıcının git-wt akışı (global CLAUDE.md); her worktree kendi dalında |

## 5. Kalite kapıları
1. `tools/verify.sh quick` — kanon bütünlüğü (SHA-256), gdlint, Godot import/parse hataları, birim testleri (GdUnit4). Her değişiklikte.
2. `tools/verify.sh full` — quick + pencereli runtime duman testi (ana sahne varsa). Teslimde.
3. Görsel kapı — gerçek capture'lar, açılıp bakılır, checklist + art-director verdict'i.
4. Oynanış kabulü — görevdeki gözlemlenebilir ölçütler; QA her birini kanıta bağlar; "build geçti" kanıt sayılmaz.
5. Director incelemeleri — milestone kapanışında üçü birden.
Zorlayıcılar: `guard-canon` hook (foundation yazımını reddeder), `stop-verify-gate` hook (doğrulanmamış oyun kodu değişikliğiyle "bitti" demeyi bir kez durdurur), `canon-check.sh` (manifest).

## 6. Envanter
**Kurulan / uyarlanan:** bkz. `third_party/README.md` (CCGS dokümanları+kurallar, 5 awesome-gamedev skill'i, 3 Superpowers skill'i, 2 mevcut Codex skill'i, Blender MCP 2.1.9, GdUnit4). Godot 4.7.2 (mevcut kurulum), gdtoolkit 4.5.0 (uvx ile sabit), ImageMagick (mevcut).
**Yaratılan (proje skill'leri):** `canon-check`, `visual-gate`, `sim-invariants`, `dev-task`, `plan-milestone`, `handoff`, `blender-asset`.
**Reddedilen:** `scpli/blender-mcp` (upstream'in 1.8.7'de kalmış çatalı), resmî Blender Lab MCP (Blender 5.1+ ister; kurulu 4.5), tüm Godot MCP'leri (Coding-Solo/bradypp/ee0pdt/tomyud1/GDAI — CLI + kendi script'lerimiz daha güvenilir ve commit'lenebilir; tomyud1 projeye eklenti ister, GDAI ücretli), Superpowers eklentisi ve hook'u, GodotPrompter hook'u, awesome-gamedev router'ı ve ~66 alakasız skill, thedivergentai/Game-Dev-Agentic-Skills (LGPL-3.0), Gemini görsel analiz MCP'si (kullanıcının model kısıtı: yalnız Opus/Sonnet).
**Ertelenen:** Erodenn `godot-mcp-runtime` (canlı girdi/ekran görüntüsü gerekirse M2'de denenecek), playtest-bot skill'i (ilk oynanış döngüsü olunca, M2), audio araçları (M3), iOS export/imza hattı (Q-004 + cihaz), CI sunucusu (remote yetkisi yok).
