# Teknik direktör kararları: `_notes` hash dışı + PerfLogger `format` (2026-11-07)

Kaynak: `production/log/2026-11-06-golden-x-fark.md`. Kod DEĞİŞTİRİLMEDİ; bu dosya karar + uygulama reçetesidir.
Uygulayıcı: `simulation-engineer` (sonnet) veya ana oturum. REQ: TEK-01 (determinizm), TEK-02 (sim saflığı).

## Karar 1: EVET. `_` önekli ÜST DÜZEY meta anahtarlar aktör yapılandırma özetinden çıkarılır; GOLDEN'lar tek commit'te yenilenir

### Kök neden (kod okunarak doğrulandı, koşulmadı; davranış 2026-11-06 deneyiyle doğrulanmıştı)
- `src/sim/actors/actor_config.gd:129-140` `_load_sections`: ham JSON'u `to_ints` ile olduğu gibi (üst düzey `_notes` dahil) `data`ya koyar.
- `actor_config.gd:143-146` `_finish`: `digest = StateHash.of(data)` -> `_notes` metni özete girer.
- `src/sim/actors/actor_store.gd:45-47`: özet `state.systems.actors.config_digest`e yazılır -> `GameState.state_hash()` (`game_state.gd:107`) `systems`i içerir -> GOLDEN.
- Karşılaştırma: `src/sim/politics/politics_config.gd:126-140` `_prepare`/`_without_notes` üst düzey `_` anahtarları ZATEN atıyor. Yani tutarsızlık yalnız ActorConfig'te. `SimConfig` (`sim_config.gd:51-61`) yalnız bilinen anahtarları kopyalar; `sim._notes` duruma girmez.
- `config_digest` hiçbir tick kodunda OKUNMAZ (yalnız `ActorStore.config_matches`; üretimde çağıranı yok, yalnız `tests/sim/actors/actor_relation_test.gd:28`). Yani değişiklik sim gidişatını değiştiremez; yalnız özet dizgisi değişir.

### Neden doğru (ve neden "sayıları da hash dışı bırak" değil)
- Yorum cümlesi düzeltmek GOLDEN kırmamalı: yanlış alarm "hash yenile" alışkanlığı üretir, gerçek sim değişikliğini gizler. Bu, determinizm kapısının değerini düşürür.
- Sayı/eşik değişikliği hash'i değiştirmeye DEVAM eder (özet kalır; bu bilinçli: senaryo o sayıyı kullanmasa da ayar değişikliği görünür olur).
- Reddedilen alternatifler: (a) `config_digest`i durumdan tamamen çıkarmak: veri ayarı değişikliği GOLDEN'da görünmez olur, kayıt-yapılandırma uyumsuzluğu bilgisi kaybolur. (b) Özeti ayrıştırılmış yapılardan (tablolar/kadro) hesaplamak: daha sağlam ama daha geniş etki alanı; şimdilik gereksiz. (c) Özyinelemeli (iç içe) `_` silme: `data/actors/*.json`da iç içe `_` anahtar YOK (taranarak doğrulandı) ve iç içe bilinmeyen anahtarlar `ActorSchema.check_unknown` ile zaten reddedilir; PoliticsConfig ile aynı (üst düzey) kural yeterli ve tutarlı.

### Riskler ve cevapları
- Kayıt/yükleme uyumu: `SimSave` zarfı ve gövde biçimi değişmez; eski kayıtların `state_hash`i kendi gövdesiyle tutarlıdır -> yüklenir. Eski kayıtta eski `config_digest` kalır -> `config_matches` false döner (bilgi amaçlı, yüklemeyi engellemez). Dağıtılmış oyuncu kaydı yok.
- `SimSave.VERSION` (2) ARTMAZ; `ActorStore.SCHEMA` (1) ARTMAZ; `SaveSlot` sürümü ARTMAZ. Gerekçe: alan adı/türü/anlamı aynı (yine 64 hex özet).
- Determinizm testleri: iki-koşu eşitlik testleri (`sim_facade_determinism_test`, `politics_determinism_test`, `economy_determinism_test`) etkilenmez. Yalnız sabit kodlu hash'ler değişir.
- Gerçek bir değişikliği gizleme riski: aşağıdaki "maske kanıtı" ile kapanır (yeni hash'in TEK farkının özet dizgisi olduğu ispatlanır).
- PoliticsConfig özeti DEĞİŞMEMELİ (zaten atıyordu); değişirse DUR.

### Etkilenen dosyalar
- Kod: `src/sim/actors/actor_config.gd` (`_load_sections`), `src/sim/actors/actor_schema.gd` (ortak yardımcı), `src/sim/politics/politics_config.gd` (`_without_notes` yardımcıya yönlenir, davranış bit-bit aynı).
- GOLDEN sabitleri (değişmesi BEKLENEN; aktör sistemi kurulu senaryolar):
  - `tests/sim/m2_query_test.gd:21` `GOLDEN_A`, `:22` `GOLDEN_B` (kullanan: `tests/sim/parcel_changes_test.gd:438-439`)
  - `tests/sim/public_works/golden_expropriation_undo_test.gd:23` `GOLDEN_X`
  - `tests/sim/public_works/golden_x_council_trust_test.gd:15` `GOLDEN_X_BEFORE_D021`
- Kontrol (değişmemesi BEKLENEN; siyaset/aktör kurulmayan ekonomi koşusu): `tests/sim/economy/economy_land_values_unplanned_test.gd:20` `OLD_CODE_STATE_HASH`. Değişirse DUR: başka bir sızıntı var, TD'ye dön. (Beklenti varsayımdır: koşu yalnız ekonomi tutamacı kuruyor gibi okunuyor.)
- Dokunulmaz: `tests/world/network/network_hash_cache_test.gd` (dünya hash'i, sim değil), `tests/sim/state_hash_test.gd` (StateHash birim vektörleri), `design/foundation/`.

### Uygulama adımları (sırayla)
1. Worktree HEAD'in `main`i içerdiğini doğrula. Başlamadan önce mevcut 5 sabiti (4 GOLDEN + kontrol) not et.
2. `ActorSchema`ya `static func without_meta(raw: Dictionary) -> Dictionary` ekle: üst düzey `str(key).begins_with("_")` anahtarları atar, gerisini olduğu gibi kopyalar (`PoliticsConfig._without_notes` ile aynı gövde). `PoliticsConfig._without_notes` bunu çağırsın (ya da kaldırılıp çağrı yerleri `politics_config.gd:128,677` yönlendirilsin).
3. `ActorConfig._load_sections` (`actor_config.gd:137`): `data[file_name] = ActorSchema.without_meta(ActorSchema.to_ints(raw))`. `float_problems` ham `raw` üzerinde kalsın (sıra korunur). Sınıf belgesine bir satır: "Üst düzey `_` anahtarlar belgedir; özete girmez."
4. Yeni testler `tests/sim/actors/actor_config_test.gd` içine:
   - 9 dosyanın her birinde `_notes` metnini değiştir / `_notes` ekle-sil -> `digest` AYNI.
   - Bir sayı değişince `digest` FARKLI (mevcut `test_integral_floats_from_json_become_ints_and_digest_is_stable` zaten var; koru).
   - `tests/sim/politics/politics_config_test.gd`: olay şablonu ve üst düzey dosyalarda `_notes` değişince `PoliticsConfig.digest` aynı (kilit; bugün zaten doğru olmalı).
5. Maske kanıtı (atılabilir; `experiments/notes_hash_mask/` altında, üretime import edilmez, commit'e girmez veya ayrı tutulur): 4 GOLDEN senaryosunu YENİ kodla koş; bitiş durumunda `systems.actors.config_digest`i ESKİ yöntemle hesaplanan özetle (ham dosyalar `_notes` dahil `StateHash.of({dosya: to_ints(ham)})`) değiştir; `state_hash()` ESKİ GOLDEN değerine BİT-BİT eşit olmalı. Dördü de eşitse yeni hash'in tek farkı özet dizgisidir. Biri tutmazsa DUR, TD'ye dön. (`SimFacadeImpl._state` özel alan; deney betiğinde erişim kabul.)
6. `tools/verify.sh quick` -> yalnız 4 beklenen GOLDEN testi kırılmalı. Yeni değerleri test çıktısından al, sabitleri güncelle. Her sabitin üstüne yorum: "2026-11-07 meta-anahtar özeti (TD kararı, production/log/2026-11-07-teknik-direktor-notes-hash.md): eski <hash> -> yeni; sim gidişatı aynı (maske kanıtı)". `GOLDEN_X_BEFORE_D021` yorumunda zincir korunur (c987fb3d -> 92d1a99e -> yeni) ve "kural kapalı referans" anlamı aynen kalır.
7. `tools/verify.sh full` (GOLDEN/determinizm değişikliği = teslim düzeyi; quick yetmez). Ayrıca 2026-11-06 deneyini tekrarla: yalnız `decision_tables.json` `_notes` metnini geçici değiştir -> `GOLDEN_X_BEFORE_D021` testi GEÇMELİ; dosyayı geri al, `git status` temiz.
8. TEK commit, içinde YALNIZ: kod (adım 2-3) + testler (adım 4) + 4 sabit + yorumlar. Başka iş karışmaz. Başlık: `Aktör yapilandirma ozeti _ meta anahtarlari disarida; GOLDEN_A/B/X/X_BEFORE_D021 yenilendi (sim gidisati ayni)`. Gövdede eski->yeni 4 hash ve maske kanıtı sonucu. Push yok.
9. Kayıt: `production/STATE.md` bir satır; bu dosyaya "uygulandı: <sha>" eki.

### Geri alma
- `git revert <sha>`: kod ve sabitler birlikte, atomik döner (ara commit yok, bisect kırılmaz).
- Kayıt göçü gerekmez (iki yönde de): eski/yeni kayıtlar kendi hash'iyle yüklenir; yalnız bilgi amaçlı `config_matches` değeri değişir.

## Karar 2: HAYIR. PerfLogger `format` 2 KALIR; `extras_version: 1` yeterli

### Kanıt (doğrulandı)
- `src/view/perf/perf_logger.gd:63` `FORMAT_VERSION := 2`, `:83` `EXTRAS_VERSION := 1`, `:741` rapora yazılır; `:46` ve `:82` belge "format 2 KALIR" diyor.
- `artifacts/perf/**.json` tarandı: 527 `imaro_perf_log` raporu; 441 adet `(format 2, extras yok)`, 86 adet `(format 2, extras_version 1, cpu_probe_enabled true)`. Ayırt edici alan her yeni dosyada VAR.
- Depoda `format == 2` ile kapı tutan tüketici yok (`tools/` betikleri JSON sürümüne bakmıyor); tek kilitler testler: `tests/view/perf/perf_logger_env_test.gd:47`, `tests/view/perf/perf_logger_modes_test.gd:126-127`.

### Gerekçe
- A1/A2 eklemeleri yalnız YENİ alan ekler (geriye uyumlu). Dürüst not: A3 (`cpu_probe`) mevcut özetlerin anlamını hafif değiştirdi (yoklama karesi busy/kare süresi özetinden atılır). Bu katı sürümlemede ana sürüm artışı gerektirirdi; AMA ayırt edici (`extras_version`, `cpu_probe_enabled`) her dosyada olduğu için iki seri karıştırılamaz.
- Şimdi 3'e çıkarmak, içeriği `(2,1)` ile birebir aynı üçüncü bir durum `(3,1)` yaratır; ADR-0010/T-076 iPad serisinin (8 geçerli koşu) karşılaştırılabilirliğini bölmekten başka bir şey kazandırmaz.

### Kural (bundan sonra)
- Okuyucu etkin sürümü `(format, extras_version ?? 0)` çiftiyle belirler.
- Yalnız alan EKLEME -> `EXTRAS_VERSION` +1. Mevcut alanı silme/yeniden adlandırma, birimini veya tanımını değiştirme (ör. `busy_ms` ölçüm noktası) -> `format` 3 olur ve `perf_logger_env_test.gd:47` ile `perf_logger_modes_test.gd:126` aynı commit'te güncellenir.
- `perf_logger_env_test.gd:47`deki sabit `2` bilinçli kilittir (kazara artışı yakalar); `FORMAT_VERSION`a bağlanmasın.
- İsteğe bağlı küçük iş (ana oturum, tek satır): bu kuralı `perf_logger.gd:82` belge satırına ekle.


## Uygulandı (2026-11-07)
dd1405b: `ActorSchema.without_meta`, 4 GOLDEN yenilendi (sim gidişatı aynı; maske kanıtı 4 senaryoda bit-bit, `experiments/notes_hash_mask/`), `OLD_CODE_STATE_HASH` değişmedi. `verify full` PASS (3184 test, 0 hata, kapsam tam @dd1405b). PerfLogger `format` 2 kaldı.
