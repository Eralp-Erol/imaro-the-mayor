# Paralel üretim hatları (departmanlar)

Tek üretim koordinatörü: **Studio Director (ana oturum)**. Görev sahipliği, bağımlılıklar ve entegrasyon burada yönetilir; ajanlar yalnız kendi hattının yollarına yazar. Araç: `tools/lane.sh` (durum, sahiplik kontrolü, hat bazlı doğrulama ve commit). Kayıt defteri bu dosyanın sonundaki `LANE|…` satırlarıdır (en uzun yol öneki kazanır; sahipsiz değişiklik = hata).

## ZORUNLU DURAKLAMA (kullanıcı kararı, 2026-10-20)
M1 teknik kapanışı ve T-030 entegre demo tamamlandığında **dur**: demo + ekran görüntüleri + çalıştırma talimatı + tamamlananlar/eksikler/test sonuçları/açık riskler sun; kullanıcı onayı bekleyen maddeleri (Q-015 coğrafya, T-008 iPad) gerekçeleriyle ayrıca belirt. **Kullanıcının açık onayı olmadan M2 veya yeni özellik görevi BAŞLATILMAZ** (yeni görevler yalnız backlog'a eklenir). Sonsuz doğrulama döngüsüne girilmez. Duraklamaya kadar sürenler: T-017, T-028, T-029, T-030, T-012 açık kriter kararları, M1 kapısı (T-006). Backlog (onay bekliyor, başlatılmaz): T-014 bütçe/altyapı, T-026 NPC/olay içeriği iskeleti, T-001a–c cila, kit v1, T-009/T-010, M2 işleri.

## Çalışma kuralları (hatlar paralel, çakışma yok)
1. **Yalnız kendi hattının yollarına yaz.** Paylaşılan dosyalar yalnız koordinatörde: `production/` (ROADMAP, STATE, QUESTIONS, bu dosya), `design/REQUIREMENTS.md`, `design/decisions/`, `CLAUDE.md`, `.claude/`, `tools/` (hat yolu olmayanlar), `project.godot`, `.gitignore`, `addons/`. Bunlarda değişiklik gerekiyorsa raporunda iste; koordinatör uygular.
2. **Git'e dokunma** (`add/commit/stash/checkout/reset/merge` yok). Commit'i koordinatör `tools/lane.sh commit <hat> "<mesaj>"` ile yalnız o hattın dosyalarıyla yapar. Dal: `dev/m1-parallel` (T-001 dalından), `main`'e alma kullanıcıdadır.
3. **Doğrulama:** kendi hattın için `tools/lane.sh verify <hat>` (gdlint + yalnız hattın GdUnit4 dizinleri). Tam `tools/verify.sh quick/full` yalnız entegrasyonda koordinatör tarafından. Başka hattın yarım işi senin doğrulamanı kırmaz; kırıyorsa sahipsiz/ihlal sayılır, raporla.
4. **Yarım dosya bırakma:** bir dosyayı parse eder halde yaz (başka hatların import/test koşuları görür). Godot'u yalnız kendi PID'inle başlat/öldür; `pkill -f Godot` yasak. Aynı anda ağır Godot işi (import/capture/export) en çok 2 hat.
5. **Hatlar arası API yalnız sözleşmeyle** (`docs/adr/0005-*`, `src/contracts/`). Sözleşme değişikliği = contracts hattı. Karşı hat henüz yoksa **mock** (`MockSimFacade`, `WorldFixture`) ile geliştir; gerçek bağlantı entegrasyon görevidir.
6. **Yaratıcı kararları kanonlaştırma.** Açık konu (`design/foundation/docs/05` §D) → ad/sayı/senaryo uydurma; yer tutucu + yapılandırma/veri + raporuna "AÇIK SORU" maddesi. Koordinatör gruplayıp `production/QUESTIONS.md`'ye yazar; kullanıcı karar verene kadar iş bloklanmaz (yapılandırılabilir ilerlenir).
7. **Model politikası:** uygulayıcılar `sonnet`, director kapıları `opus`; **Haiku yok**. Ajanlar görev başına bir kez çağrılır, işi bitirince biter (boşta oturum yok). Eşzamanlı ajan tavanı: 7 (dalga 1; ağır Godot işi en çok 2 hat). İnceleme/QA yalnız teslim kapılarında.
8. **Coğrafya bağımlılığı yalnız şuna uygulanır:** gerçek `WorldData` koordinatlarını okuyan işler (T-005 yerleşim, T-003 kamera çerçevesi, T-011 yol/parsel, T-012 yapı yerleşimi). Kıyı/ada/bölge koordinatları ÇM verisidir ve değişebilir; kod koordinat gömmez, `WorldData` API'sini (ADR-0005 §WorldData okuma sözleşmesi) kullanır. Sim, UI, karakter/siyaset, platform, sanat kiti **geografiden bağımsızdır** (fixture/mock ile başlar). **Coğrafya yaratıcı onayı (Q-015) bekliyor:** bu yüzden hiçbir hat kalıcı şehir/mahalle/liman/yol koordinatı sabitlemez; yerleşim/ağ çalışma zamanında WorldData'dan türer, üretilmiş koordinat verisi commit'lenmez, testler göreli/topolojik.

## Departmanlar ve görevleri
Durum: ▶ aktif · ⏸ bekliyor (neden) · ✓ bitti · ○ planlı. Dalga 1 = hemen; Dalga 2 = sözleşme/spec teslimiyle açılır.

| Departman | Hat | Görev | Bağımlı | Dalga | Durum |
|---|---|---|---|---|---|
| **World & City Building** | world | T-001 ✓ · T-001b ada/batimetri · T-001c alt-hücre kıyı · **T-011** yol/parsel/blok veri modeli (`WorldNetwork`) · **T-005** T0 yerleşim üreteci | T-011←T-001 ✓; T-005←T-001 ✓, T-004, T-011 | 1→2 | T-011 ✓ · ▶ T-005 |
| | render | T-001a ışık+dikiş deliği · **T-003** ✓ çok ölçekli kamera rig'i · **T-012** yapı MultiMesh + HLOD | T-012←T-004 ✓, T-011 ✓, T-003 ✓ | 2 | T-003 ✓ · ▶ T-012 |
| | art | **T-025** ✓ sanat spec v0 → **T-004** ✓ low-poly yapı kiti v0 (technical-artist) | T-004←T-025 ✓ | 1 | ✓ (kit v1 ○) |
| **Simulation Engineering** | sim | **T-002** ✓ sim çekirdeği · **T-009** çapraz platform determinizm · **T-027** ✓ `SimFacadeImpl` (gerçek sim → sözleşme) · **T-013** ekonomi çekirdeği v0 (parsel/mülkiyet/imar, hane, yatırımcı kararı + gerekçe) · **T-014** belediye bütçesi + altyapı kapasitesi v0 | T-009←T-002,T-007; T-027←T-002,T-023; T-013←T-002,T-023; T-014←T-013 | 1 | T-002 ✓ · ▶ T-027 |
| **Characters, NPC & Political Gameplay** | chars | **T-015** karakter/NPC/siyasi olay spec v0 (systems-designer; yer tutucu adlar, AÇIK sorular listesi) | — (canon-safe) | 1 | T-015 ✓ |
| | actors | **T-016** aktör modeli + karar/gerekçe çatısı (`Actor`, `Decision`, `Reason`) · **T-017** siyasi aktörler v0: ≥2 seçmen/çıkar grubu tepkisi + küçük meclis oylaması + medya tonu (M2 gereği) · **T-026** NPC/karakter profil verisi + diyalog/olay iskeleti (yer tutucu içerik) | T-016←T-002,T-023,T-015; T-017←T-016,T-013; T-026←T-015,T-023 | 2 | ○ |
| **Game UX/UI & Interaction** | ux | **T-018** UX spec v0 (IA, akışlar, masaüstü+dokunmatik, Türkçe metin sistemi) · **T-019** UI temeli: tema, ölçek, merkezi metin, platform-duyarlı yerleşim, `ui_lab` (mock facade) · **T-020** HUD + zaman kontrolü + parsel denetçisi · **T-021** nedensellik paneli (SIM-12) · **T-022** karar akışları (imar önerisi, meclis oylaması, bütçe) | T-018 yok; T-019..022←T-018,T-023 (mock facade) | 1→2 | T-018 ✓ · T-019 ✓ · T-021 ✓ · T-020 ◐ (T-019 kapsadı) · T-022 ○ |
| **Platform Engineering** | platform | **T-007** profil katmanı + export hattı · **T-008** iPad duman testi · **T-010** renderer karşılaştırması | T-008←T-003,T-007; T-010←T-007 | 1 | T-007 ✓ (macOS export+duman PASS; Windows çalıştırma ve iPad ⏸ cihaz) |
| **Cross-cutting / Contracts** | contracts | **T-023** ADR-0005: Sim↔View↔UI sözleşmeleri (`SimFacade`, `Snapshot`, `Command`, `Event`, `Reason`), `WorldFixture`, `MockSimFacade` | — | 1 | T-023 ✓ (v1.1 ○) |
| **Integration (öncelikli)** | playable | **T-030** entegre oynanabilir sahne (terrain+T0+kamera+gerçek SimFacade+HUD+bir eylem→gözlenebilir sonuç; birleşik yük; smoke+QA) · **T-029** kayıt/hash maliyeti (ReasonLog) performans görevi · **T-028** Q-015 etiketli topoloji haritası | T-030←T-017, T-022 ✓, T-012 (açık kriterler korunur); T-029←T-017 (core dokunuşu) | 2 | ○ T-028 ▶ |
| **QA & Directors** | qa | T-006 M1 kapısı; hat teslimlerinde bağımsız QA; T-901 canlı kanon probları | hat teslimleri | kapılar | ○ |

Açık kullanıcı onayı gerektirenler: (1) T-007 Godot export şablonlarının resmî sürüm sayfasından indirilmesi (dosya indirme); (2) T-901 canlı kanon probları; (3) `QUESTIONS.md`'ye giren yaratıcı kararlar (blokaj değil).

## Kayıt defteri (tools/lane.sh bunu okur) — `LANE|id|sahip|yollar (virgülle, önek)|testler|not`
LANE|coordinator|studio-director|production/,design/REQUIREMENTS.md,design/decisions/,design/CANON.md,docs/STUDIO.md,docs/engine-reference/,CLAUDE.md,.claude/,tools/,project.godot,.gitignore,.gitattributes,addons/,export_presets.cfg.import,README|—|paylaşılan; yalnız koordinatör
LANE|sim|simulation-engineer|src/sim/,src/app/tick_driver,src/app/save_slot,tests/sim/,data/sim/,design/specs/economy|tests/sim|T-002, T-009, T-013, T-014
LANE|actors|simulation-engineer|src/sim/actors/,src/sim/politics/,tests/sim/actors/,tests/sim/politics/,data/actors/,data/politics/,src/sim/facade/,src/sim/core/game_state.gd|tests/sim/actors,tests/sim/politics|T-016 ✓, T-017, T-026 (GEÇİCİ: T-017 süresince src/sim/facade/ ve core/game_state.gd actors hattında — sim hattı boşta; T-017 bitince geri dönülür)
LANE|platform|godot-engineer|src/app/platform_profile,src/app/input_profile,export_presets.cfg,tools/export.sh,tests/app/|tests/app|T-007, T-008, T-010
LANE|contracts|technical-director|docs/adr/0005,docs/adr/0006,src/contracts/,tests/contracts/,tests/fixtures/|tests/contracts|T-023
LANE|world|world-engineer|data/world/,src/world/,tests/world/,scenes/dev/topology_map|tests/world|T-001b/c, T-011, T-005, T-028
LANE|render|godot-engineer|src/view/,scenes/dev/world_preview,tests/view/,tools/godot/,tools/perf.sh|tests/view|T-001a, T-003, T-012
LANE|art|art-director|design/specs/art/,art/,assets/,scenes/dev/kit_lab,tests/art/|tests/art|T-025, T-004 (technical-artist)
LANE|chars|systems-designer|design/specs/characters,design/specs/politics,design/specs/political-events|—|T-015 (spec)
LANE|playable|godot-engineer|src/game/,scenes/game/,tests/game/,tools/smoke_playable|tests/game|T-030 entegre oynanabilir sahne (yalnız bağlama; alt sistemlere dokunmaz)
LANE|ux|ui-engineer|design/specs/ux/,src/ui/,scenes/ui/,scenes/dev/ui_lab,tests/ui/,data/ui/|tests/ui|T-018..T-022
LANE|qa|qa-engineer|tests/qa/,production/qa/|tests/qa|bağımsız doğrulama
