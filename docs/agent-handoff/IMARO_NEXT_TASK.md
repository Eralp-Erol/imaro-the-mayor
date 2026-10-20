# IMARO_NEXT_TASK — Codex için eksiksiz görev: M01 teknik kapanışını bitir

Önce `docs/agent-handoff/IMARO_CHECKPOINT.md` oku (durum, mimari, bağımlılıklar). Bağlayıcı kaynaklar: `CLAUDE.md`, `design/foundation/` (değiştirilemez), `design/CANON.md`, `design/REQUIREMENTS.md`, `design/decisions/D-001..D-004`, `docs/adr/0001..0005`, `production/LANES.md`, `production/QUESTIONS.md`. Bunları yeniden tasarlama; eksik bilgiyi uydurma (açık kararlar için yapılandırılabilir yer tutucu + rapor).

## ÖNEMLİ — izole worktree'de çalışıyorsan (Agent Handover)
Agent Handover görevi `HEAD`'den AYRI bir worktree'de açar: **ana checkout'taki commit'siz T-017/T-028 dosyaları orada YOKTUR.** Önce geri yükle: `tar xzf docs/agent-handoff/wip/wip-untracked-files.tgz` ve `git apply docs/agent-handoff/wip/wip-tracked-changes.patch` (kökten). Bu yedekler yarım işlerdir; derlenmeyebilir (adım 1). Bu bölümdeki "Mevcut" ifadeleri ana checkout içindir. `.godot` önbelleği ve `.tools/` yoktur: `tools/godot.sh` ana checkout'taki `.tools/` ikilisini bulur; ilk Godot koşusu içe aktarmayı baştan yapar (yavaş).
Doğrulayıcı çıkış kodları handover için sözleşmedir: **0 bitti · 2 yalnız kullanıcı/cihaz onayı kaldı (DUR, ajanı yeniden çağırma) · 1/4 devam et.** Ağır adımlar aynı HEAD + temiz ağaçta önbellekten gelir (`artifacts/verify/m01-heavy-cache.json`, yalnız tam koşudan yazılır); önbellek yoksa betik tam koşar (handover `--verify-timeout` ≥ 1800 verilmeli).

## Kurallar
- Çalışma dalı `dev/m1-parallel`; **main'e merge YOK, deploy YOK, M02 YOK, yeni özellik görevi YOK**. Force push yok. `design/foundation/` altına yazma yok; her teslimde `tools/canon-check.sh`.
- **Commit'siz T-017/T-028 çalışmasını SİLME/SIFIRLAMA.** Önce incele, sonra tamamla (yedek: `docs/agent-handoff/wip/`).
- Sim saf/deterministik; CAN-03 (özel bina yalnız aktör kararıyla); HUD gerçek veri; sahte başarı/imza/onay üretme (`M01_MANUAL_SIGNOFF.json`'u yalnız kullanıcı/gerçek kanıt doldurur).
- Doğrulama: hat bazlı `tools/lane.sh verify <hat>` (actors, sim, contracts, world, render, ux, playable); entegrasyonda `tools/verify.sh quick`; bitiş ölçüsü `python3 scripts/verify_imaro_m01.py`. Token/zaman tasarrufu için `--quick` ile ucuz ön kontrol, tam koşu yalnız sonda.
- Her görevde kendi kanıtını `production/tasks/T-0NN.md` "Kanıt" bölümüne yaz (komut, sonuç, doğrulanmadı listesi). Çalıştırmadığına "geçti" deme.

## Adımlar (bu sırayla)
### 0. Ön kontrol (≤10 dk)
`git status`, `git log -3`, `python3 scripts/verify_imaro_m01.py --quick` (beklenen: exit 1/4; hangi kalemler FAIL görünür). `tools/lane.sh status` ile hat sahipliği. Yarım dosyaların derleme durumunu `tools/lane.sh verify actors` / `verify sim` ile gör.

### 1. T-017 siyasi aktörler v0'ı bitir (hat `actors`; T-017 süresince `src/sim/facade/` ve `core/game_state.gd` actors hattında)
Tanım: `production/tasks/T-017.md` (8 ölçüt). Mevcut: `src/sim/politics/` (bloc/council/media/event motorları, bootstrap, snapshot, query), `data/politics/*.json`, `tests/sim/politics/*`. Yap: derleme/parse hatalarını gider; ölçütleri tek tek testle kanıtla (≥2 grup farklı yönde tepki; küçük meclis oylaması `requires_council` iki yol [Q-014 AÇIK]; medya tonu; PE-01/02/03/04/07 agenda düzeyi; snapshot `groups/council` `available=true`; `GameState.validate_dict` → `ActorStore.validate_data`; determinizm + kaydet/yükle; ReasonLog hacmi ölçümü; mock/gerçek parity; canon taraması [parti/rakip/protagonist adı yok, `corruption` şablonları kapalı]). Bitince `lane verify actors && lane verify sim && lane verify contracts`, kanıtı T-017.md'ye yaz, `actors` hattını commit'le (yalnız T-017 dosyaları), facade/game_state sahipliği `sim` hattına döner.

### 2. T-029 kayıt/hash maliyeti (hat `sim`) — `production/tasks/T-029.md`
Önce ölçüm betiği (`tests/sim/perf/`), taban çizgisi 2k/10k/30k parsel; sonra düzeltme (artımlı/zincirli hash, ikili sütunlu kayıt, günlük kapasite politikası). Hedef: 10k parselde `state_hash` ≤~500 ms, kayıt+yükleme ≤~1,5 s. `SimSave.VERSION` artır, eski sürüm reddi. Sonuçlar `artifacts/verify/m01-perf.json` anahtarları: `state_hash_ms_10k_parcels`, `save_load_ms_10k_parcels`.

### 3. T-030 entegre demoyu tamamla (hat `playable`) — `production/tasks/T-030.md`
Mevcut: `src/game/playable.gd` (+`scenes/game/playable.tscn`), `tools/godot.sh --path . res://scenes/game/playable.tscn -- --preset=district:D1 --demo`. Eksikler (öncelik): (a) T0 yapı stokunu sim'e aktar (`ExistingStockSource` adaptörü `BuildingColumns`'tan; sim parselleri "built" başlasın; karar kaydı yok); (b) HUD imar akışını dünyadan parsel seçimine bağla (`WorldNetwork.parcel_id_at` + `DecisionPanels.attach`; seçim `HudRoot`/`InputProfile.select_requested`); (c) imar sonrası gelişmeyi sahnede göster (`BuildingView.set_columns` hücre-yerel yeniden kurulum; render'a bağlı olmayan kısmı "henüz bağlı değil" yaz, sahte gösterim yok); (d) açılışı hızlandır (≈4 dk: ağ/yerleşim/view'ı ölç, gerçek ilerleme göstergesi, yerel ignored önbellek; commit'li koordinat verisi YOK); (e) `tools/smoke_playable.sh`: başsız bölüm (dünya+ağ+yerleşim+sim bağla, N gün ilerlet, imar komutu→sonuç, kaydet/yükle/hash) + pencereli bölüm (sahne açılır, M kare, hata günlüğü taraması, capture); sonunda stdout'a `SMOKE_OK` ve `artifacts/verify/m01-perf.json` yazar (anahtarlar: `frame_avg_ms`, `frame_p95_ms`, `draw_calls_max`, `local_phase_triangles_max`, `k8_lod0_lod1_diff_pct`, `state_hash_ms_10k_parcels`, `save_load_ms_10k_parcels`); (f) birleşik yük ölçümü (metro/district/street, hız basamakları); (g) bağımsız QA notu (kendi işini onaylama: ayrı doğrulama koşusu + bulgu raporu, mümkünse farklı oturum).

### 4. T-012 açık kriterleri (hat `render`) — `production/tasks/T-012.md`
K8 LOD0↔LOD1 ≤%5 (aday: LOD0'ı 500 m hücrelere böl, çakışmayı ~700 m'ye uzat), yerel evre yapı üçgeni ≤900k, low-key ışık için arazi V bandı kontrolü (medyan 0,32–0,64). Ölçümü `m01-perf.json`'a yaz. Sanat kararı gerektirenleri (HLOD2 örnekleme, ışık onayı) art-director/kullanıcı kaydına bırak.

### 5. T-028 topoloji haritasını bitir (hat `world`, bağımsız) — `production/tasks/T-028.md`
Q-015 için etiketli, "ÇALIŞMA VERİSİ — ONAYSIZ" damgalı harita (kuzey, ölçek, D1–D6, liman, ana kara, adalar, gelişim alanları); `tools/capture.sh topo --scene res://scenes/dev/topology_map.tscn --resolution 2000x2000`; PNG'leri kullanıcıya sunulmak üzere `artifacts/screenshots/captures/` altında bırak. Coğrafyayı değiştirme/onaylama.

### 6. M1 kapısı raporu ve DUR
`production/tasks/T-006.md` yaz (M1 kapısı: yukarıdakilerin kanıt özeti, açık riskler). `python3 scripts/verify_imaro_m01.py` (tam). Beklenen sonuç: kullanıcı onayları (Q-015, T-008 iPad, T-009, T-010, Windows, art-director kapısı, kullanıcı incelemesi) eksik olduğu sürece **exit 2** — bu doğru ve beklenen; onayları UYDURMA. Kullanıcıya şunları sun ve DUR: demo açma komutu + ekran görüntüleri, tamamlananlar/eksikler/test sonuçları, kullanıcıya özel bekleyen maddeler (Q-015, iPad). M02 veya yeni görev başlatma.

## Kabul (bu görevin bitişi)
- `git status` temiz (T-017/T-028 commit'li), `lane verify` tüm hatlar PASS, `tools/verify.sh quick` PASS, `scripts/verify_imaro_m01.py` yalnız manuel/kullanıcı kalemleri nedeniyle exit 2 (başka FAIL yok), checkpoint güncel, kullanıcıya sunum yapıldı.
- Yarım kalırsa: durumu `IMARO_CHECKPOINT.md`'ye yaz, commit'siz dosya bırakma ya da yedekle, devret.
