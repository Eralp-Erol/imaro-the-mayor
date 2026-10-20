# Stüdyo doğrulaması · 2026-10-20

Makine: 2019 MacBook Pro (i7-8850H, Radeon Pro 560X), macOS 15.8, Godot 4.7.2, Blender 4.5.14, Claude Code 2.1.220.
Kural: yalnız gerçekten çalıştırılanlar "geçti" sayılır.

## 1. Uçtan uca iş akışı
| Adım | Test | Sonuç | Kanıt |
|---|---|---|---|
| 1. Gereksinimi referans paketinden okuma | E2E-A: design-director, T-001 ön kontrolü (Opus) | **Geçti** — foundation bölümlerini kaynak göstererek sınıflandırdı; 6 REQ satırını kaynak metne karşı denetledi; 2 gerçek kusur buldu (T-001'de belirsiz "referans 02" atfı, WLD-05 özetinin kaynaktan katı olması) → düzeltildi | `production/tasks/T-001.md`, `design/REQUIREMENTS.md` |
| 2. Uzmana yönlendirme | Studio Director → simulation-engineer (T-900), qa-engineer, systems-designer, design-director | **Kısmi** — rol tanımları ve yönlendirme mantığı çalıştı; Claude Code'un proje ajanlarını canlı keşfi **doğrulanmadı** (M0-CLOSURE C-03) | — |
| 3. Skill/araç etkinleştirme | Ajanlar önyüklenen skill'leri okuyup uyguladı (TDD, sim-invariants, canon-check, verification) | **Kısmi** — E2E-C `canon-check`'i resmi biçimde değil elle uyguladı | ajan raporları |
| 4. Küçük izole teknik görev | T-900 kanonik durum hash'i: TDD (önce kırmızı, sonra yeşil), 31 test | **Geçti** | `src/sim/core/state_hash.gd`, `tests/sim/state_hash_test.gd` |
| 5. Gerçek doğrulama | `tools/verify.sh quick` | **Geçti** — 5 adım, 36 test | `artifacts/verify/quick-latest.json` |
| 6. Bağımsız inceleme | qa-engineer, uygulayıcının raporunu görmeden | **Geçti** — 7/7 ölçüt; 19 mutasyonla testlerin hata yakalayabildiği gösterildi; 2 zayıf nokta yeni testlerle kapatıldı; iki ayrı süreçte aynı hash | `production/tasks/T-900.md` |
| 7. Kayıt ve kalıcı bağlam | Görev kanıtı, T-002'ye devredilen bulgular, STATE, log | **Geçti** | `production/` |

**Not (adım 2):** Proje ajanları Claude Code'da oturum başında yüklenir; bu kurulum oturumunda `subagent_type` olarak çağrılamadılar ("Agent type not found"). Testler, her ajanın tanım dosyasını ve önyüklenen skill'lerini birebir okuyup aynı model/effort ile çalışan alt ajanlarla yapıldı. Frontmatter geçerliliği `tools/studio_check.py` ile doğrulandı. **Yeni oturumda yerel kayıt doğrulanmalı** (§4).

## 2. Hata senaryoları
| Senaryo | Sonuç |
|---|---|
| Kanonla çelişen istek (T0'da adada liman, "Konut İnşa Et" butonu, tek memnuniyet %) | Üç çatışma da kaynakla tespit edildi; sohbetten gelen isteğin kanonu geçebileceği ama sessizce uygulanmayacağı doğru yorumlandı → `NEEDS USER DECISION` + seçenekli soru taslağı. Hiçbir şey inşa edilmedi. |
| Ajanın tamamlayamadığı görev (AÇIK karar: parti adları, seçim takvimi) | systems-designer uydurmadı; her birini foundation kaynağıyla reddetti, parametreye çevirdi, 4 soru hazırladı (M4 planlamasına ertelendi). |
| Godot yok / yanlış sürüm | `tools/godot.sh` açık mesajla çıkış 2 / 3. |
| Blender köprüsü kapalı | MCP sunucusu çökmeden "Blender addon is running?" hatası verdi. |
| İç içe `claude -p` oturumu | OAuth süresi dolmuş → LLM üzerinden MCP ve model-kullanım testi yapılamadı (ortam sınırı; atlatılmadı). |

## 3. Kapılar ve hook'lar (olumlu + olumsuz)
| Mekanizma | Olumlu | Olumsuz |
|---|---|---|
| `canon-check.sh` | 11/11 SHA-256 eşleşmesi | manifest dışı dosya / değişiklik → çıkış 1 (kod incelemesi) |
| `guard-canon` hook | `design/foundation` okuma ve `design/specs` yazma serbest | foundation'a Write ve `sed -i` → deny |
| `studio_check.py` | 12 ajan, 17 skill, kurallar, hook, MCP sabitleri sağlam | ajana `model: haiku` yazılınca → 2 hata, çıkış 1 |
| `verify.sh quick` unit adımı | 36/36 | parse hatalı test paketi → FAIL (önceden yanlışlıkla PASS'ti, düzeltildi) |
| `stop-verify-gate` hook | doğrulanmış durumda izin | doğrulamadan sonra değişen oyun dosyası → `block`; döngü koruması çalışıyor |
| `session-start` hook | checkpoint, açık sorular, son doğrulama ve bayatlık durumu enjekte ediliyor | — |
| Performans | — | Benchmark sonuçları **sentetiktir**; render/sim/birleşik yük ayrımı ve kanıtlanmamış hedefler ADR-0001'de |
| Blender hattı | headless üreteç 3 koşuda aynı SHA-256; Godot içe aktarma 208 üçgen, 14×15,9×10 m, 2 materyal | yanlış genişlik → `RESULT: FAIL` |

## 4. Kurulum sırasında bulunan ve düzeltilen hatalar
1. Worktree, kullanıcının eski POC'yi sildiği (commit'lenmemiş) durumdan önceki commit'ten açıldı; POC bir kez çalıştırıldı → silme bu dalda birebir uygulandı (D-001, ADR-0003). Ders: oturum başında ana checkout'un commit'lenmemiş durumu da kontrol edilir.
2. GdUnit4 çöktüğünde `verify.sh` PASS raporluyordu → özet satırı yoksa ve `Abnormal exit`/parse hatasında FAIL.
3. `-d` bayrağı parse hatasında Godot'yu debugger isteminde bekletebiliyordu → kaldırıldı.
4. GdUnit4 `-rd` mutlak yolla depo içinde başıboş `Users/`, `private/` ağaçları açtı (2 kez) → `.gitignore` koruması.
5. Bir ajanın `pkill -f Godot` kullanması diğer ajanın benchmark'ını öldürebilirdi → ölçümler yeniden alındı; ders `CLAUDE.md`'ye eklendi (yalnız kendi PID'ini sonlandır).
6. `studio_check.py` YAML liste ayrıştırma hatası → düzeltildi, olumsuz testle doğrulandı.

## 5. Doğrulanmamış / kullanıcı tarafında yapılacak

Takip listesi ve kesin kontrol komutları: `production/M0-CLOSURE.md` (C-01…C-10). Aşağıdakilerin hiçbiri PASS sayılmaz.

- **Yeni oturumda kayıt:** proje ajanlarının (`/agents`) ve skill'lerinin listelenmesi, `env` ile Haiku→Sonnet yönlendirmesinin etkinleşmesi. Doğrulama (giriş yapılmış terminalde): `claude -p --output-format json "merhaba" | jq '.modelUsage|keys'` → yalnız opus/sonnet görünmeli.
- **Blender MCP'nin LLM üzerinden çağrısı:** `tools/blender/start-mcp.sh` sonra yeni oturumda `blender` MCP sunucusunu onaylayıp `get_scene_info`.
- iPad/Metal, export şablonu performansı, render+sim birlikte (ADR-0001 §Kanıt).
- Global Blender'ınızdaki eski `blender_mcp` eklentisi (v1.7, protokol 9) güncel değil; proje köprüsü `--factory-startup` ile onu atlıyor, dokunulmadı.
