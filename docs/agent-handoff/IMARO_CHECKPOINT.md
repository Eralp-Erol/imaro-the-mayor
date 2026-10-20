# IMARO: THE MAYOR — CHECKPOINT (Claude → Codex güvenli devir)

Tarih: 2026-10-20 (gece). Hazırlayan: Claude (Studio Director oturumu). Bu dosya başka sohbet geçmişine ihtiyaç duymadan okunabilir.

## 1. Repo / dal / durum (gerçek, tespit edilmiş)
- Repo (ana checkout, worktree DEĞİL): `/Users/eralperol/Documents/Projects/imaro-the-mayor` · remote `origin` = `https://github.com/Eralp-Erol/imaro-the-mayor.git`
- Çalışma dalı: **`dev/m1-parallel`** (T-001 dalı `task/T-001-ismeral-world` üzerine kuruldu; ikisi de `main`'e MERGE EDİLMEDİ, `main` = `a0237b0`). HEAD SHA bu dosyayı içeren son commit'tir (`git log -1`).
- Çalışma ağacı **TEMİZ DEĞİL** (bilinçli): T-017 ve T-028 yarım işleri commit'siz duruyor (bkz. §4). Yedekleri bu dizinde: `docs/agent-handoff/wip/` (yama + arşiv). Başka worktree'ler (`.claude/worktrees/*`, `../imaro-the-mayor.integration`) eski M0 artıkları: DOKUNMA.
- Alt ajan/süreç: çalışan alt ajan YOK (T-017, T-028 durduruldu). Yetim süreçler temizlendi.
- Model politikası (CLAUDE.md): yalnız Opus 5.5/Sonnet 5.5, **Haiku yasak**. Codex için karşılık: aynı kalite/kural; aşağıdaki "bağlayıcı kaynaklar" kuralları model-bağımsızdır.

## 2. Hedef ve mimari (kısa)
Oyun: yaşayan 3D city-builder + siyasi kariyer (Anderva → Ismeral → ilçe → sokak, tek fiziksel dünya). Godot 4.7.2 (`tools/godot.sh`), GDScript statik tipli, GL Compatibility.
- `src/world/` saf dünya verisi: `WorldData` (arazi, kıyı, D1–D6), `network/` (`WorldNetwork`: yol/ray/feribot, blok, 37k parsel; base+delta), `settlement/` (`T0Settlement` → `BuildingColumns`, 54.856 yapı). Veri `data/world/ismeral/*.json` (ÇM/OY, kilitli değil).
- `src/view/` görünüm: `terrain/` (chunk'lı flat-shaded arazi+su), `buildings/` (MultiMesh + LOD0/LOD1/HLOD), `camera/` (`CameraRig`, origin rebasing).
- `src/sim/` deterministik sim (saf, tick=1 gün, seed'li RNG akışları): `core/` (GameState, Commands, ReasonLog v2 sabit nokta, SimSave v2), `facade/` (`SimFacadeImpl`: ADR-0005 sözleşmesinin gerçek implementasyonu), `economy/` (T-013), `actors/` (T-016), `politics/` (T-017 YARIM).
- `src/contracts/` + `docs/adr/0005-*`: Sim↔View↔UI sözleşmeleri, `MockSimFacade`, `WorldFixture`. `src/ui/`: HUD, paneller, karar akışları (Türkçe, `data/ui/strings.tr.json`). `src/app/`: `PlatformProfile`, `InputProfile`, `TickDriver`, `SaveSlot`.
- `src/game/playable.gd` + `scenes/game/playable.tscn`: T-030'un ASGARİ entegre demosu (arazi+T0+kamera+gerçek SimFacade/ekonomi+HUD).
- Paralel üretim modeli: `production/LANES.md` (hat sahipliği) + `tools/lane.sh` (status/check/verify/commit). Codex tek ajan ise: aynı yol kurallarına uy, hat bazlı doğrulamayı kullan (`tools/lane.sh verify <hat>`).

## 3. BAĞLAYICI kaynaklar (yeniden tasarlama, uydurma yok)
- `design/foundation/` (DEĞİŞTİRİLEMEZ kanon; SHA-256 manifest: `tools/canon-check.sh`), `design/CANON.md` (öncelik), `design/REQUIREMENTS.md` (REQ kimlikleri), `design/decisions/D-001..D-004` (kullanıcı kararları), `docs/adr/0001..0005`, `CLAUDE.md` (stüdyo anayasası), `production/QUESTIONS.md` (açık sorular Q-003, Q-005..Q-015: **kanonlaştırma, yapılandırılabilir yer tutucu kullan**).
- Claude'a özgü hook'lar (kanon koruması vb.) Codex'te çalışmaz: **`design/foundation/` altına ASLA yazma**, her teslimde `tools/canon-check.sh` (11/11) çalıştır.
- Özel kural: Oyuncu özel bina spawn edemez (CAN-03); HUD yalnız gerçek sim verisi gösterir (sahte sayı/ölü buton yok); sim saf ve deterministik (Node/Time/OS/global rastgelelik yok); para birimsiz tamsayı (Q-003); yalnız D2 "Orven" adı (CAN-01); kullanıcı kararı gerektirenleri uydurma.

## 4. M01 (= ROADMAP M1) durumu
**M01 DOĞRULANMADI.** Teknik çalışmanın büyük kısmı commit'li; kalan işler ve kullanıcı onayları var. Gerçek ölçüt: `python3 scripts/verify_imaro_m01.py` (exit 0 olmadan M01 bitmiş sayılmaz; DONE dosyası geçerli değil).

### Biten ve commit'li (kanıt: `production/tasks/T-0NN.md` "Kanıt" bölümleri)
T-001 arazi/dünya (art-director GEÇER, QA PASS; **yaratıcı onay Q-015 kullanıcıda**) · T-002 sim çekirdeği · T-003 CameraRig · T-004 yapı kiti v0 (36 mesh, Blender üreteçleri) · T-005 T0 yerleşim · T-007 platform (macOS export+`.app` duman PASS; Windows `.exe` üretildi ama ÇALIŞTIRILMADI; iOS yalnız preset) · T-011 yol/parsel ağı · T-012 yapı render (**KISMİ**, aşağıda) · T-013 ekonomi çekirdeği · T-015 karakter/siyaset spec · T-016 aktör çatısı · T-018/T-019/T-021/T-022 UX spec + UI temeli + nedensellik paneli + karar akışları · T-023 sözleşmeler · T-025 sanat spec · T-027 SimFacadeImpl · T-030 **asgari** demo (commit `11013cc`).
Son hat bazlı testler (`tools/lane.sh verify <hat>`, o günkü sonuçlar): sim 433 · actors 87 · world 209 · render 192 · ux 225 · contracts 64 · platform 54 · art 37 — hepsi 0 hata. Son **tam** `tools/verify.sh quick` PASS = 157 test @ `4a1cae2`; **o zamandan beri tam doğrulama KOŞULMADI**.

### Yarım / bitmemiş (öncelik sırasıyla)
1. **T-017 siyasi aktörler v0 — YARIM** (commit'siz): `src/sim/politics/` (≈19 `.gd`), `src/sim/facade/{proposal_gate,snapshot_provider}.gd`, `data/politics/*.json`, `tests/sim/politics/` (12 test dosyası) + tracked değişiklikler: `src/sim/core/game_state.gd`, `src/sim/facade/sim_facade_impl.gd`, `src/sim/facade/zoning_propose_handler.gd`, `data/actors/decision_tables.json`, `tests/sim/actors/actor_config_test.gd`. Ajan durdurulduğunda `politics_query.gd` yeniden yaratılıyordu; derleme/test durumu DOĞRULANMADI. Görev tanımı: `production/tasks/T-017.md`.
2. **T-028 topoloji haritası — YARIM** (commit'siz): `scenes/dev/topology_map.{gd,tscn}`, `src/world/topology_map/`, `tests/world/topology_map/`. Q-015 için etiketli harita; T-030'dan bağımsız.
3. **T-029 kayıt/hash maliyeti** — başlanmadı: 10k parselde `state_hash` ≈9 sn, kayıt ≈16 MB (ReasonLog kaynaklı). Görev: `production/tasks/T-029.md`.
4. **T-030 tam kapsam** — asgari demo var; eksikler: T0 stoku sim'e aktarılmamış (sim parselleri boş başlıyor), HUD imar paneli dünyadan parsel seçimine bağlı değil (eylem Z tuşu), imar sonucu sahnede yapı olarak görünmüyor, açılış ~4 dk (pencereli), `tools/smoke_playable.sh` yok, birleşik yük/kayıt-hash ölçümü yazılı değil (`artifacts/verify/m01-perf.json`), bağımsız QA yok.
5. **T-012 açık kriterleri** (commit ≠ kabul): K8 LOD0↔LOD1 %9,54 (>%5); yerel evre yapı üçgeni ~1,27M (>900k); low-key ışık onayı (arazi V bandı); gerçek T0 verisiyle görsel kapı (VIS-04). Ayrıntı `production/tasks/T-012.md`.
6. **M1 kapısı T-006** — görev dosyası yok; yazılacak (bkz. NEXT_TASK).
7. Backlog (başlatma): T-014, T-026, T-001a–c, kit v1, T-009, T-010 (M1 kapısında EKSİK raporlanır).

### Kullanıcı onayı/cihaz gerektirenler (M01'i bloke eder; UYDURMA SIGNOFF YASAK)
Q-015 coğrafya kararı · T-008 iPad cihaz testi (kullanıcının iPad'i + Apple hesabı; imza bilgisi repoya girmez) · T-009 çapraz platform determinizm · T-010 renderer karşılaştırması · Windows çalıştırma · art-director yapı görsel kapısı · kullanıcının demoyu incelemesi. Kayıt yeri: `docs/agent-handoff/M01_MANUAL_SIGNOFF.json` (şema script içinde).

## 5. Değişikliklerin bulunduğu dosyalar
- Commit'li: `git log --oneline dev/m1-parallel` (≈60 commit; hat başına bölünmüş). Hat sahipliği: `production/LANES.md`.
- Commit'siz (korunuyor, silme/sıfırlama YOK): yukarıdaki T-017/T-028 listesi. Yedek: `docs/agent-handoff/wip/wip-tracked-changes.patch` (5 dosya, +45/−12) ve `wip-untracked-files.tgz` (`tar xzf` ile geri açılır; zaten çalışma ağacında duruyorlar).
- `artifacts/**` gitignored (capture/perf/verify günlükleri); son capture'lar: `artifacts/screenshots/captures/` (`playable-final.png`, `*t001-final*`, `*t004*`, `*t021*`, `*t022*`).

## 6. Bilinen hatalar / riskler / engeller
- Kayıt/hash maliyeti (T-029); açılış süresi ~4 dk (dünya 2 s + ağ 4–6 s + yerleşim 18–20 s + view; pencereli koşuda çok daha yavaş gözlendi); ağ bellek +~95 MB.
- Şehirler elips "damga" (T-011 ayak izi); liman noktası kıyıdan ~1,5–2 km (T-001b, kanon verisi kaydırılmadı); kıyı 100 m hücre basamaklı; D4 tarla ızgarası; D5 ort. eğim 13–15°.
- ReasonLog kapasitesi 20000 (büyük dünyada dolar). UI v1.1 sözleşme istekleri `ux-data-needs.md` + T-022 raporunda (AgendaItemView vb.).
- `tools/verify.sh quick` içinde `studio-check` ve `lane.sh` düzeltmeleri yapıldı; `lane.sh` hat bazlı doğrulamada import adımını sınıf önbelleği eskiyse yapar.
- Ölçülmemiş/Doğrulanmamış: iPad, Windows çalıştırma, birleşik yük (yalnız `playable` demosunda kaba: ort. kare ~9 ms, ~17 oyun günü/sn), çapraz platform hash, gerçek fare/trackpad/dokunma.

## 7. Devralan Codex ilk olarak ne yapmalı
`docs/agent-handoff/IMARO_NEXT_TASK.md` — adım adım, kendi kendine yeterli.

## 8. M01'in tamamlandığını kanıtlayan acceptance kriterleri
`scripts/verify_imaro_m01.py` bunları nesnel denetler; **exit 0 = M01 doğrulandı**:
1. Repo/araç/Godot 4.7.2 ortamı sağlam; kaynak ağacı commit'li (T-017/T-028 yarım işi kalmamış).
2. `tools/canon-check.sh` 11/11 ve `studio_check.py` temiz.
3. Zorunlu görevler (T-001..T-030 listesi script'te) `Durum: done` + dolu Kanıt bölümü; T-006 dahil.
4. Gerekli sahne/sistem dosyaları var ve git'te izleniyor (playable, world_preview, kit_lab, ui_lab, topology_map, sim/politics, smoke betiği…).
5. Godot projesi headless açılır, GdUnit4 **tam** koşu 0 hata/0 başarısız, gdlint temiz.
6. `tools/smoke_playable.sh` (pencereli+başsız) `SMOKE_OK` basar ve `artifacts/verify/m01-perf.json` yazar; sınırlar: kare ort ≤8 ms/p95 ≤16,6 ms (render+sim), draw call ≤600, yerel evre üçgen ≤900k, K8 ≤%5, 10k parselde state_hash ≤500 ms ve kayıt+yükleme ≤1,5 s.
7. Manuel/kullanıcı onayları `M01_MANUAL_SIGNOFF.json` içinde kayıtlı (Q-015, T-008, T-009, T-010, Windows, art-director kapısı, kullanıcı incelemesi); `waived` yalnız `by:"user"` ile.
Exit kodları: 0 doğrulandı · 1 otomatik FAIL · 2 manuel onay eksik · 3 ortam · 4 koşu eksik.
