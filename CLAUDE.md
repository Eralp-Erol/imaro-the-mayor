# Imaro: The Mayor — stüdyo anayasası

Bu repo bir **oyun stüdyosu**dur. Oyun: yaşayan 3D city-builder + siyasi kariyer (Anderva → Ismeral → ilçe → sokak, tek fiziksel dünya). Belgeler Türkçe; kod, tanımlayıcılar ve araç adları İngilizce.

## Yaratıcı gerçek nerede?

- **Kanon:** `design/foundation/` (değiştirilemez, hook korur) + `design/decisions/` (kullanıcı onaylı sonraki kararlar). Öncelik ve tarihî çelişkiler: `design/CANON.md`.
- **İzlenebilirlik:** `design/REQUIREMENTS.md` (CAN/WLD/SIM/VIS/TEK kimlikleri). Her görev karşıladığı REQ kimliklerini yazar.
- Eski POC kullanıcı tarafından silindi (D-001, ADR-0003); yalnız git geçmişinde. Referans veya başlangıç noktası değildir; "Ilgın" gibi adları kullanma.
- AÇIK kararlar uydurulmaz. Gerekirse işi kararı gerektirmeyecek biçimde (veri odaklı) yap veya `production/QUESTIONS.md`'ye gruplanmış soru ekle (`canon-check` skill'i).

## Yetki modeli

| Alan | Yetkili | Not |
|---|---|---|
| Yaratıcı kimlik, kanon, AÇIK kararlar | **Kullanıcı (Creative Director)** | Ajanlar yalnız önerir; `production/QUESTIONS.md` |
| Kanon yorumu, tasarım sadakati kapısı | `design-director` (opus) | Kanonu değiştiremez |
| Mimari, motor, ADR'lar, teknik çatışma | `technical-director` (opus) | `docs/adr/` |
| Görsel kalite kapısı, sanat spesifikasyonu | `art-director` (opus) | Gerçek ekran görüntüsüyle karar verir |
| Planlama, yönlendirme, entegrasyon, ilerleme kaydı | Ana oturum = **Studio Director** | `production/` |
| Uygulama | sonnet uzmanları (aşağıda) | Kendi alanının dosyaları |
| Bağımsız doğrulama | `qa-engineer` + ilgili director | Uygulayıcı kendi işini onaylamaz |

## Yönlendirme

| İş | Ajan |
|---|---|
| Deterministik simülasyon, ekonomi, aktörler, siyaset sistemi, kayıt | `simulation-engineer` |
| Godot runtime, sahne, kamera, girdi, render, performans, export | `godot-engineer` |
| Arazi, kıyı, yol ağı, parsel, T0 şehir üretimi, dünya LOD verisi | `world-engineer` |
| Low-poly asset kiti, materyal, shader, ışık/hava, Blender hattı | `technical-artist` |
| HUD, paneller, dokunmatik UX, Türkçe metin, nedensellik açıklamaları | `ui-engineer` |
| Oynanış/ekonomi/siyaset spesifikasyonu ve denge verisi | `systems-designer` |
| Test yazımı, `tools/verify.sh`, playtest, performans ölçümü, hata raporu | `qa-engineer` |

Kural: tek dosyalık/küçük işleri ana oturum doğrudan yapar; uzman yalnızca ölçülebilir değer kattığında çağrılır. Bağımsız işler paralel; aynı dosyalara iki yazıcı asla. Ajan çağrılarında modeli her zaman açıkça ver (`opus` veya `sonnet`) — **Haiku hiçbir koşulda kullanılmaz.** Opus yalnız director kararları ve büyük teslim incelemeleri içindir.

## İş akışı

1. Görev `production/tasks/T-NNN.md` (şablon: `production/tasks/_TEMPLATE.md`); kabul ölçütleri + REQ kimlikleri + kanıt planı olmadan uygulamaya başlanmaz. `/dev-task T-NNN` tam döngüyü yürütür.
2. Uygula → `tools/verify.sh quick` (her değişiklikte) / `full` (teslimde) → sunuma duyarlı işte `visual-gate` → büyük teslimde director incelemesi.
3. Kayıt: görev dosyasına kanıt, `production/STATE.md` checkpoint, `production/log/`. Oturum sonunda `handoff`.

## Kalite kuralları (pazarlıksız)

- Build/test geçmesi veya sahnenin render etmesi **oynanış tamamlandı kanıtı değildir**. Oynanış işi: gerçek runtime görüntüsü + nedenselliğin görünürlüğü + kabul ölçütleri.
- Doğrulanmış / varsayılan / test edilmemiş her raporda ayrı yazılır. Çalıştırmadığın şeye "geçti" deme.
- Oyuncu özel bina spawn edemez (CAN-03). HUD yalnız gerçek simülasyon verisi gösterir; sahte sayı, ölü buton yok.
- Simülasyon render/input'tan ayrı, sabit tick'li, seed'li ve deterministik (TEK-01/02).
- Tek dünya: her ölçek aynı dünya verisinden (WLD-01, TEK-03).
- Yanlış temel fark edilirse yama yığma: `technical-director`/`design-director`'a eskale et, temiz yeniden başlangıcı değerlendir.
- Remote'a push ve geri alınamaz git işlemleri kullanıcı onayı olmadan yapılmaz.
- Worktree oturumunda ilk iş `git log --oneline -1` ile HEAD'in `main`'i içerdiğini doğrula (`git merge-base --is-ancestor main HEAD`); değilse commit'siz ise `git merge --ff-only main`, değilse yeni worktree. Hook'lar masaüstü uygulamasında ana checkout'tan çalışır: hook/`settings.json` değişikliği `main` güncellenip ana checkout'ta dosyalar değişmeden canlı olmaz (`production/M0-CLOSURE.md` Çalıştırma 2).
- Kanon (`design/foundation/`) üç katmanla korunur: PreToolUse `guard-canon.sh`, PostToolUse `post-canon-verify.sh` (HEAD'den geri yükler), Stop kapısı. Testi: `tools/test-canon-guard.sh` (`verify full` içinde). Hook'ları değiştirirsen bu testi çalıştır.
- Worktree oturumunda başlarken ana checkout'un commit'lenmemiş durumuna da bak (`git -C <ana checkout> status`); kullanıcı orada dosya silmiş/eklemiş olabilir.
- Süreç sonlandırırken yalnız kendi başlattığın PID'i öldür; `pkill -f Godot` gibi geniş desenler paralel ajanların işini öldürür.

## Araçlar

- Godot 4.7.2: `tools/godot.sh` (sürüm doğrular). Testler/kapılar: `tools/verify.sh quick|full`, ekran görüntüsü `tools/capture.sh`, görsel fark `tools/visual-diff.sh`. Ayrıntı: `tools/README.md`.
- Godot API'si için önce `docs/engine-reference/godot/` (model bilgisi 4.7'nin gerisinde olabilir).
- Blender: tekrarlanabilir asset'ler için headless üreteçler `art/blender/`; keşif için `blender` MCP (`tools/blender/README.md`).
- Mimari kararlar: `docs/adr/`. Stüdyo düzeni ve gerekçesi: `docs/STUDIO.md`.
