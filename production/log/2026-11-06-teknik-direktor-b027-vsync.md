# 2026-11-06 · Teknik direktör karar notu: B-027 (gerekçe saklama ufku) + iPad kare maliyeti ölçütü (VSync)

- Taban: `452dfcc` (dal `agent/handover-imaro-m01-349562fb`). `main` bu dalın atası değil (iki boş birleştirme commit'i önde), ama incelenen dosyalarda `HEAD..main` farkı yok [okundu: `git diff --name-only HEAD main -- src/sim src/view/perf docs/adr data/sim`].
- Yalnız okuma ve yazılı inceleme. **Godot ve testler ÇALIŞTIRILMADI.** `src/`, `tests/`, `data/`, `docs/adr/` değişmedi. ADR-0010 metin önerisi aşağıda; ADR dosyasına işlenmesi ayrı bir iştir.
- Etiketler: **[okundu]** kod/belge okundu · **[kaynak]** Godot 4.7.2-stable kaynak kodu ya da 4.7 resmî belgesi okundu · **[kayıt]** ölçüm JSON'u/kaydı okundu, yeniden koşulmadı · **[hesap]** aritmetik · **[çıkarım]** okunandan türetilen, ayrıca kanıtlanmamış sonuç · **[varsayım]** · **[ölçülmedi]**.

---

## Konu 1 · B-027: yapılan parselin yatırımcı gerekçesi günlükten düşüyor

### Karar (öneri)
1. **Şimdi: (d). Davranış olduğu gibi kalır, B-027 "kasıtlı saklama ufku, dürüst metinle karşılanmış" diye kapanır.** (d)'nin sim ve UI tarafı ADR-0005 Ek D ile zaten uygulanmış durumda (aşağıda kanıt). Kod değişikliği yok, GOLDEN değişmiyor.
2. **M3'te: (b), ama "kalıcı dizin" biçiminde DEĞİL, parsel başına "karar anı kopyası" biçiminde.** Yatırım kararının etkenleri, eşiği ve puanı karar anında ekonomi durumuna kopyalanır. Kod içinde örneği var: `CouncilWhy`, oylama nedenini `vote["why"]` alanına kopyalıyor ("gerekçe kayıtları budanabilir"). **Bu seçenek GOLDEN yenilemesi ve kayıt sürümü artışı gerektirir. Sahip onayı ve ayrı commit şart.**
3. **(a) kapasite artırımı ve (c) konu bazlı halkalar REDDEDİLDİ** (gerekçe tabloda).
4. **Yeni bulgu (B-027'den önemli):** gerekçe günlüğü yalnız açıklama deposu değil. **Sim tick mantığı da onu okuyor.** Bu yüzden saklama ufku, gizli bir oynanış parametresi. Ayrı izlenmeli (aşağıda R1).

### Bugünkü durum (doğrulanmış, kod okundu)
- `ReasonLog` tek halka. Kapasite `GameState.config.reason_log_capacity` = 1000 (`data/sim/core_config.json:7`). Budama yalnız baştan yapılıyor, kimlikler boşluksuz artıyor (`src/sim/core/reason_log.gd:69-70`). `peek` O(1) çalışıyor ve bu değişmeze dayanıyor (`:97-111`). İki önbellek de aynı değişmeze dayanıyor: `ReasonSubjectCache` (`src/sim/facade/reason_subject_cache.gd:8-15`) ve `ReasonLatestCache` (`src/sim/facade/reason_latest_cache.gd:6-8`). §5 olay ufku da öyle: `first_retained_event_seq` (`src/sim/facade/sim_facade_impl.gd:521-530`).
- `config` ve `reasons` ikisi de `state_hash`e ve kayda giriyor (`src/sim/core/game_state.gd:91-113`). Eski kayıt kendi kapasitesini taşıyor.
- `reasons_for` tüm günlüğü tarıyor ve eşleşmeleri derin kopyalıyor (`sim_facade_impl.gd:533-538`, `reason_log.gd:117-122`).
- **Karar özeti kalıcı:** `ParcelView.decision/decision_code/decision_tick` ekonomi sütunlarından türüyor, budanmadan etkilenmiyor. Budanınca yalnız `decision_reason_id` 0'a düşüyor (`src/sim/economy/economy_state.gd:173-202`; ADR-0005 Ek D, `docs/adr/0005-sim-view-ui-contracts.md:143-149`).
- **Dürüst metin var:** denetçi, `reason_pruned` durumunda `m2.investor.pruned` gösteriyor (`src/ui/panels/inspector_model.gd:111-131`, `src/ui/panels/inspector_panel.gd:174-175`). Sonuç paneli de aynısını gösteriyor (`src/ui/flows/m2_result_panel.gd:202`). Metin: "Karar verildi — gerekçe kaydı kapasite nedeniyle budandı" (`data/ui/strings.tr.json:594`). Bu yolu kapsayan testler var: `tests/ui/m2_result_default_regime_test.gd`, `tests/ui/m2_inspector_test.gd` [okundu, koşulmadı].
- **B-027'nin "açık soru"suna yanıt [okundu]:** 100+ gün sonra denetçi binanın kararını, tick'ini ve kodunu (`approved`) gösteriyor. **Etkenleri ("neden") göstermiyor.** Ayrı bir önbellek ya da olay kaydı yok. Reddedilen parselde ret kodu kalıcı, yani neden kısmen görünüyor. Onaylanan parselde kod yalnız `approved`, yani neden kayboluyor. **SIM-12 eski binalar için kısmen karşılanıyor.**

### Yeni bulgu: sim günlüğü okuyor (R1)
- `EventCauses.recent_declines`, son `declines_days` = 30 günün olumsuz yatırımcı kayıtlarını günlükten tarıyor ve olayın nedenini ve bölgesini buna göre seçiyor (`src/sim/politics/event_causes.gd:36-46`, `src/sim/politics/event_engine.gd:250,306`, `data/politics/events.json:13`). `CouncilWhy.build` ve `MediaEngine` de `peek` ile okuyor, ama yazdıkları kopyalar karar anında alınıyor.
- Ufuk 30 günden kısaysa (B-001 ölçümünde günde 55-60 kayıt, yani ~16-18 gün [kayıt, eski yapı]), siyasi olay girdisi **saklama kapasitesine bağlı oluyor** [çıkarım]. Determinizm bozulmuyor (kapasite durumla birlikte taşınıyor). Ama kapasiteye dokunan her değişiklik **davranış değişikliği** sayılır, yalnız hash değişikliği değil.
- Bugünkü oynanabilir dünyada günlük kayıt hızı **ölçülmedi**. B-027 ilçe senaryosu ~9/gün (≈110 gün ufuk), B-001 ~55-60/gün. Ufuk koşula göre 16 ile 110 gün arasında oynuyor.

### Seçenekler

| | (a) Kapasite artır (örn. 10 000) | (b) Olumlu/yapı kararını kalıcı tut | (c) Olumsuzlar ayrı halkada | (d) Bırak + dürüst metin |
|---|---|---|---|---|
| Ne çözer | Ufku uzatır, sınırı kaldırmaz (55-60/gün ile ~170 gün [hesap]) | Yapılan her binanın nedeni bina durdukça kalır | Olumlu kayıtlar daha yavaş döner, ama yine döner (grup/meclis kayıtları da olumlu) | Hiçbir şeyi çözmez, sınırı dürüstçe söyler |
| GOLDEN | **Tümü değişir.** `config` hash'te; 10 test dosyası GOLDEN taşıyor [sayıldı]. Ufkun 30 günden kısa olduğu koşularda siyasi davranış da değişir (R1) | b2 (önerilen): ekonomi durumuna yeni alan. Alan ilk onayda yaratılırsa (public_works deseni) onaysız koşuların hash'i aynı kalır, onaylı GOLDEN'lar değişir. Sim davranışı DEĞİŞMEZ (yalnız yazılır, okunmaz) | **Tümü değişir.** Hash yapısı ve `recent_declines` girdisi değişir, yani davranış değişir | **Yok** |
| Kayıt şeması | Değişmez. Eski kayıtlar 1000 kapasiteyle kalır, yeni oyunlar büyük kapasiteyle başlar | `SimSave.VERSION` 2→3. Taşıma: eski kayıtta kopya boş, UI "budandı" der. `MIN_SUPPORTED_VERSION` 2 kalır | Değişir (iki halka + kimlik eşlemesi), taşıma gerekir | Değişmez |
| Bellek / kayıt boyutu | Kayıt başına 8 sözlük (1 kayıt + 7 etken). Bellek ~2-5 KB/kayıt [varsayım] ⇒ 10k ≈ 20-50 MB; kayıt dosyası ~1 KB/kayıt [varsayım] ⇒ ~10 MB | Sabit genişlik: 7 değer + 7 ağırlık + 2 kaynak komut + tick/eşik/puan ≈ 85 B/parsel [hesap]. Packed sütun ya da yalnız yapılan parseller için seyrek | (a)'ya benzer, toplam kapasiteye bağlı | Yok |
| Çalışma maliyeti | `reasons_for` (denetçi, derin kopya) ve `recent_declines` (tick içinde) O(N): ~10× [çıkarım]. iPad'de seçim takılması riski [ölçülmedi] | Okuma O(1) (parsel başına). Yazma karar başına bir kopya | Ek dizin yönetimi | Yok |
| SIM-12 | Kısmi (daha geç düşer) | **Karşılanır** (yapılan binalar için) | Kısmi | Kısmi (karar ve kod var, etken yok) |
| TEK-01/02 | Deterministik, ama davranış değişir (R1) | Deterministik. Yeni durum serileştirilir, hash'e girer, kaydet/yükle testi gerekir | Deterministik, ama `peek` O(1), iki önbellek ve §5 ufku değişmezleri ("budama yalnız baştan") **kırılır** | Etkilenmez |
| Ret nedeni | Sorunu ertelerken davranışı ve performansı değiştiriyor | — | En büyük yarıçap, kalıcılık garantisi yok | — (şimdilik seçildi) |

**(b)'nin iki biçimi:**
- **b1 · ReasonLog içinde "sabitlenmiş" kayıtlar** (budanmayan beyaz liste). Avantajı: `reason(id)` ve zincirler aynen çalışır. Dezavantajı: `peek`, iki önbellek, `ReasonAdapter.to_record(first)` (`src/sim/facade/reason_adapter.gd:22-41`) ve §5 olay ufku, yani `first_id` anlamı değişir. **Reddedildi.**
- **b2 · Karar anı kopyası ekonomi durumunda (ÖNERİLEN).** `CouncilWhy` deseni. ReasonLog ve §5 değişmezlerine dokunmaz. Boyutu parsel sayısıyla sınırlı. Kopya, özgün gerekçe kimliğini taşır. Facade bundan `ReasonRecord`'u geri kurar, `parent_ids`'in budanmış olanları mevcut adaptör kuralıyla elenir. Yeniden geliştirmede üzerine yazılır.

### Sonraki adımlar
1. **Studio Director (şimdi, belge):** `production/bugs/B-027.md`'yi şöyle kapat: "BİLİNEN SINIR, kasıtlı ufuk (ADR-0005 Ek D). Karar kalıcı, etkenler ufuk kadar. Dürüst metin `m2.investor.pruned`." Bu nota bağla.
2. **ui-engineer (küçük, isteğe bağlı, sahip zevki değil):** "kapasite nedeniyle budandı" iç jargon. Oyuncu metni kalıcı `decision_tick`i kullanabilir, örneğin "Yatırımcı N. gün yapmaya karar verdi; ayrıntılı gerekçe artık kayıtta yok." Metin kararı ui-engineer'ın. Sahte sayı yok, `decision_tick` gerçek.
3. **simulation-engineer + qa-engineer (test, GOLDEN'a dokunmaz):** R1 bekçisi. Temsilî uzun koşuda (gerçek dünya, oynanabilir yapılandırma) `tick - reasons.first(tick) >= declines_days` iddiası ve günlük kayıt hızının ölçümü. Ufuk 30 günden kısaysa ayrı hata açılır. Çözüm `recent_declines`'ı ekonomi sütunlarından (`last_code`, `last_reason_tick`, `reason_id`) okumaktır, ama bu da davranış değişikliği ve GOLDEN demektir.
4. **M3 görevi önerisi · "Yatırım kararı kalıcı gerekçe kopyası" (b2)** (simulation-engineer). REQ: SIM-12, TEK-01, TEK-02, CAN-03 (değişmez). Kabul:
   - Kopya karar anında yazılır ve hiç okunmaz (sim davranışı aynı: aynı seed + komut ile ekonomi ve siyaset sayaçları aynı).
   - Kaydet → yükle → N tick sonrası hash eşit. v2 kayıt yüklenir, kopya boş olur, UI "budandı" der.
   - 260 günlük B-027 senaryosunda `developed_by_sim` parsellerin %100'ünde gerekçe çözülür.
   - Facade'a soyut OLMAYAN `decision_reason(parcel_id) -> ReasonRecord` eklenir (varsayılan null, mock destekli). ADR-0005'e küçük sürüm eki yazılır.
   - **GOLDEN yenilemesi ayrı commit'te ve sahip onayıyla** yapılır. Hangi GOLDEN'ın neden değiştiği commit mesajına yazılır.
5. Kapasite (a) değerine **dokunulmaz**. Değişirse bu bir oynanış değişikliği sayılır (R1) ve systems-designer onayı gerekir.

---

## Konu 2 · iPad "kararlı ort ≤ 8 ms": VSync'te ölçülemiyor

### Karar (öneri)
**"Kararlı ort ≤ 8 ms" satırı kare SÜRESİ ölçüsü olmaktan çıkar, kare başına CPU MEŞGUL SÜRESİ ölçüsü olur:** karenin başından `RenderingServer.frame_post_draw` anına kadar geçen süre (VSync bekleme dışarıda). Sayılar korunur (ort ≤ 8, tavan 14). Yanına iki satır eklenir:
- Ölçüm yenileme hızında kullanım oranı (Σmeşgul / Σduvar).
- Isıl satırı, kare süresi p95'i yerine meşgul süre p95'ine bağlanır.

"p95 ≤ 8,33" ya da "aralığı aşan kare oranı" türü VSync'e uyumlu ölçüler akıcılığı ölçer, ısıl payı ölçmez. Tanı olarak yazılır, kapı olmaz. 60 Hz tavanı ölçüm aracı değil, ürün ayarıdır. Isıl pay hedefinin 120 Hz'de tutup tutmadığını ölçüm gösterir, karar sahibin.

### Neden ölçülemiyor (doğrulanmış)
- **iOS + Compatibility'de VSync zorunlu açık, betikten kapatılamaz [kaynak].**
  - Godot 4.7.2 `DisplayServerAppleEmbedded::window_set_vsync_mode` yalnız `RD_ENABLED` iken ve `rendering_context` varken bir şey yapıyor. Compatibility (GLES3) yolunda işlem yok. `window_get_vsync_mode` bu yolda hep `VSYNC_ENABLED` döndürüyor (`drivers/apple_embedded/display_server_apple_embedded.mm:819-836`, tag 4.7.2-stable).
  - 4.7 belgesi: "V-Sync modes other than VSYNC_ENABLED are only supported in the Forward+ and Mobile rendering methods, not Compatibility." `FEATURE_SWAP_BUFFERS` yalnız Windows, macOS ve Linux'ta var. Bu özelliği olmayan platformda V-Sync zorla açık.
  - Proje `gl_compatibility` kullanıyor, mobil dahil (`project.godot:15-16`) [okundu]. Ölçülen `vsync_mode=1` tam bu davranış [kayıt].
- **Kare temposunu CADisplayLink belirliyor [kaynak].** `display/window/ios/allow_high_refresh_rate` (varsayılan `true`) ise `preferredFramesPerSecond` 120, değilse 60 (`platform/ios/godot_view_ios.mm:90-93`, `drivers/apple_embedded/godot_view_apple_embedded.mm:206`). Yani 60 Hz tavanı için desteklenen yol bu proje ayarı. `Engine.max_fps`'in iOS'ta nasıl davrandığı doğrulanmadı.
- **GPU süresi iOS'ta alınamıyor [kaynak].** GLES3 zaman damgası sorgusu yalnız `is_gles_over_gl()` (masaüstü GL) iken `glQueryCounter` çağırıyor (`drivers/gles3/storage/utilities.cpp:329-341`). OpenGL ES'te GPU süresi yok. ADR-0010:71'deki "GPU süresi 0" notu bununla uyumlu.
- **`Performance.TIME_PROCESS` kare başına ölçü değil [kaynak].** Değer, son ~1 saniyedeki EN BÜYÜK `process_ticks` (işlem + `RenderingServer.draw`, fizik hariç), saniyede bir güncelleniyor (`main/main.cpp:5059-5100,5136-5139`). Tepe gözcüsü olarak işe yarar, ortalama için yaramaz.
- **`viewport_get_measured_render_time_cpu`** VSync ve kare tavanından bağımsız render CPU süresi veriyor. Yalnız `viewport_set_measure_render_time(rid, true)` sonrası çalışıyor, `_process` ve sim'i içermiyor. Toplam için `get_frame_setup_time_cpu()` eklenmeli [kaynak: 4.7 belgesi].

### Ölçüm kayıtlarından yan bulgular [kayıt + çıkarım]
- **b1 koşusu iki nedenle geçersiz, yalnız VSync değil.**
  - `refresh_hz` = 60, kare p50 = 16,68 ms. a1-a3'te 120 Hz ve 8,34 ms.
  - 4.7.2'de `screen_get_refresh_rate`, `lowPowerModeEnabled` iken 60 döndürüyor (`platform/ios/display_server_ios.mm:104-113`) [kaynak]. Bu iPad'de 60 okuması büyük olasılıkla **Düşük Güç Modu açık** demek [çıkarım].
  - b1'in tick karesi ortalaması 23,9 ms, a-serisinde 12,2-12,9 ms. Bu da CPU kısılmasıyla uyumlu [kayıt + çıkarım].
  - a4'ün raporu da 60 Hz (rapor sonda yazıldığı için koşu sırasında geçiş olmuş olabilir).
  - **Hipotez (doğrulanmadı):** %20 pil uyarısı ya da Düşük Güç Modu iletişim kutusu uygulamayı etkinlikten çıkardı (`reason=pause`, "Audio interruption").
  - Sonuç: koşu şarjda, Düşük Güç Modu kapalı ve otomatik kilit "asla" iken yapılmalı. `refresh_hz` başta ve her pencerede yazılmalı; bugün yalnız rapor anında okunuyor (`src/view/perf/perf_logger.gd:509`).
- **Tick kareleri VSync'e rağmen gerçek maliyeti gösteriyor.** Aralığı aşan kare kilitlenmiyor.
  - a1-a3'te 6000 karenin 199'u tick karesi: ort 12,2-12,9 ms, en az 9,7 ms, p99 17-19 ms. Her tick karesi 120 Hz aralığını kaçırıyor.
  - Masaüstünde tick karesi 11,2-11,4 ms [kayıt, ADR-0010 bağlam]. iPad CPU'su tick karelerinde masaüstüyle aynı mertebede.
  - Tick'siz kareler 8,33 ms'nin altında, ne kadar altında olduğu **bilinmiyor**.
  - Masaüstü tick'siz kararlı ortalaması ~6 ms. iPad benzerse 120 Hz'de kullanım ~%70'in üstünde olur ve "%50 ısıl pay" niyeti 120 Hz'de tutmaz [çıkarım, ölçülmedi].

### Ölçütlerin niyete (ısıl pay) sadakati

| Ölçüt | Ölçülebilir mi (iOS/Compat) | Isıl payı ölçer mi | Karar |
|---|---|---|---|
| Kare süresi ort ≤ 8 ms (bugünkü) | Hayır, 8,33'e kilitli | — | Kaldırılır |
| p95 ≤ 8,33 / aralığı aşan kare oranı | Evet | **Hayır.** %95 yüklü cihaz da %0 kaçırma verebilir. Pay ancak tükenince görünür | Tanı (akıcılık), kapı değil |
| 60 Hz sabit tavan (`allow_high_refresh_rate=false`) | Kare süresi yine kilitli (16,67) | Pay **yaratır**, ölçmez | Ürün ayarı. Ölçümden sonra sahibe |
| `TIME_PROCESS` | Evet, ama saniyelik tepe | Kısmen (yalnız tepe) | Tanı |
| Render CPU (`viewport_get_measured_render_time_cpu` + kurulum) | Evet [kaynak, cihazda denenmedi] | Kısmen (sim ve betik hariç) | Döküm kalemi |
| GPU süresi (Godot) | **Hayır** (GLES'te sorgu yok) | — | Xcode Instruments ile ayrıca [varsayım: GL yolunda veri verdiği doğrulanmadı] |
| **CPU meşgul süresi** (kare başı → `frame_post_draw`) + kullanım oranı | Evet, yenileme hızından bağımsız [çıkarım; sinyal sırası cihazda doğrulanmadı] | **Evet (CPU tarafı).** Niyet "60 Hz bütçesinin yarısı = iş ≤ 8 ms" idi; ölçtüğü şey tam bu iş | **ÖNERİLEN kapı** |
| 15 dk ısıl kayma | Evet (kesintisiz koşu gerekir) | Sonucu doğrudan ölçer, ama geç | Kalır. Meşgul p95'e bağlanırsa kısılma, kareler kaçmadan görünür |

**Bilinen zayıflık (risk):**
- Meşgul süre GPU işini içermiyor. GPU'ya bağlı bir darboğaz yalnız GL çağrılarındaki beklemeler kadar görünür.
- `frame_post_draw`un iOS'ta sunumdan (`presentRenderbuffer`) önce mi sonra mı yayıldığı ve sunumun bloklayıp bloklamadığı **doğrulanmadı**. Bloklarsa meşgul süre VSync beklemesini içerir ve şişer: güvenli yönde hata, ama yanlış FAIL üretir.
- Önlem: iki bileşen ayrı yazılır. (i) kare başı → `frame_pre_draw` (işlem + sim + betik) ve (ii) `viewport_get_measured_render_time_cpu` + `get_frame_setup_time_cpu`. Toplamları (i)+(ii) yedek ölçüdür.
- Kalibrasyon deneyi aşağıda.

### ADR-0010'a yazılacak metin önerisi (Karar 3 değişikliği; dosyayı bu not DEĞİŞTİRMEDİ)

> **Karar 3a · iPad ölçüm tanımı (2026-11-06, technical-director; Karar 1'e iPad eki)**
> - iOS + Compatibility'de V-Sync kapatılamaz: Godot 4.7.2 Compatibility'de `window_set_vsync_mode` iOS'ta etkisizdir, kare temposu CADisplayLink'tir (`display/window/ios/allow_high_refresh_rate`: 120/60). Duvar saatiyle ölçülen kare süresi yenileme aralığına kilitlenir. Bu yüzden iPad'de kare süresi satırları (p95, p99, maks, etkileşim karesi) **akıcılık** ölçüsüdür, **maliyet** ölçüsü değildir. `--perf-log-novsync` iOS'ta etkisizdir; rapor alanı (`vsync_mode`) kanıt olarak kalır.
> - **CPU meşgul süresi** (`busy_ms`): her karede, o karenin ilk `SceneTree.physics_frame`/`process_frame` sinyalinden `RenderingServer.frame_post_draw` sinyaline kadar geçen süre. Döküm: `pre_draw_ms` (kare başı → `frame_pre_draw`), `render_cpu_ms` (`viewport_get_measured_render_time_cpu` + `get_frame_setup_time_cpu`). **Kullanım** = Σ`busy_ms` / Σkare süresi, koşunun yenileme hızında. GPU süresi Compatibility/GLES'te Godot'tan okunamaz; gerektiğinde Instruments ile ayrıca bakılır ve ayrı etiketlenir.
> - Koşu koşulu (eksikse koşu geçersizdir): release, şarjda, Düşük Güç Modu kapalı, otomatik kilit "asla". `refresh_hz` başta ve her pencerede yazılır (Godot iOS'ta Düşük Güç Modu açıkken 60 döndürür). Koşu içinde `refresh_hz` değişirse koşu geçersizdir.
>
> | Ölçü (iPad) | Ön hedef | Tavan | Not |
> |---|---|---|---|
> | Kararlı CPU meşgul ort (`busy_ms`) | ≤ 8 ms | 14 ms | Önceki "Kararlı ort" satırının yerine. Niyet aynı (60 Hz bütçesinin yarısı); ölçülen şey bekleme hariç iş |
> | Kararlı CPU meşgul p95 | ≤ 16,6 ms | 20 ms | Kare süresi p95'i ile aynı sayılar; iş ölçüsü |
> | Kullanım (oynanan yenileme hızında) | ≤ %50 | — | 60 Hz'de `busy` ≤ 8,33 ms'ye, 120 Hz'de ≤ 4,17 ms'ye denk gelir. 120 Hz'de tutmazsa iPad profili için 60/120 seçimi sahibe gider (ürün ayarı, ADR-0004 profili) |
> | Kare süresi p95 / p99 / maks, aralığı aşan kare oranı (> 1,5 × aralık) | p95/p99 satırları aynen | aynen | Akıcılık tanısı; aralığı aşan oran kapı değil, yazılır |
> | Isıl | 15 dk'da son 2 dk `busy_ms` p95 ≤ ilk 2 dk `busy_ms` p95 × 1,25 | — | Kare süresi p95'i VSync'te kısılmayı geç gösterir; meşgul süre CPU saat düşüşünü kareler kaçmadan gösterir |
>
> - Masaüstü (Karar 2) değişmez: V-Sync kapalı kare süresi orada maliyeti zaten ölçer. `busy_ms` masaüstünde de yazılır ve iki platformu aynı birimle karşılaştırır.

### Sonraki adımlar
1. **Deney (godot-engineer, `experiments/` altında ya da `PerfLogger`'a bayrak arkasında; sim'e dokunmaz, GOLDEN yok):** `busy_ms`, `pre_draw_ms`, `render_cpu_ms`, `refresh_hz` başta ve pencere başı.
   - **Kalibrasyon (masaüstü):** aynı `--demo` koşusu V-Sync kapalı ve açık. Kabul ölçütleri:
     - V-Sync kapalıyken kararlı `busy_ms` ortalaması, kare süresi ortalamasının ±%10'u içinde.
     - V-Sync açıkken `busy_ms` ortalaması, V-Sync kapalı değerin ±%10'u içinde. Bu, sunum beklemesinin dışarıda kaldığını kanıtlar.
   - Tutmazsa yedek ölçü (`pre_draw_ms` + `render_cpu_ms`) kapı olur.
   - Sinyal sırasını (`frame_pre_draw`/`frame_post_draw` ile sunum) bu deney doğrular. 4.7 belgesinde ya da kaynakta bu not için **okunmadı**.
2. **qa-engineer (T-076 devamı):** a-serisi aynı yapıyla `busy_ms` eklenerek 3 koşu, sonra 15 dk ısıl. Koşu koşulu Karar 3a'daki gibi. b1/b2 "V-Sync'siz" serisi **iptal**: iOS'ta yapılamaz [kaynak].
3. **Studio Director:** ADR-0010'u bu metinle güncellet (technical-director imzası). ADR-0010:70-71'deki "VSync'siz istek uygulanmadı" notu "uygulanamaz (Godot 4.7.2 iOS/Compatibility), Karar 3a" olur.
4. **Sahibe soru, yalnız ölçümden sonra ve yalnız kullanım 120 Hz'de %50'yi aşarsa** (Studio Director sorar; bu not sormuyor). Taslak kart:
   > "iPad'de oyun ekranı saniyede 60 mı, 120 mi yenilesin?"
   > - **A (Önerilen)** · 60: cihaz daha serin, pil daha uzun; şehir kurmada kaydırma yine akıcı [varsayım: fark az].
   > - **B** · 120: kaydırma ve yakınlaştırma daha akıcı; cihaz ısınır, uzun oturumda kare düşebilir.
   >
   > Uygulama tek proje ayarı (`display/window/ios/allow_high_refresh_rate`). Düşük Güç Modu zaten 60'a indirir [kaynak: ayar ve `lowPowerModeEnabled` yolu okundu; iOS'un kendi davranışı [varsayım]].

---

## Doğrulanmış / varsayılan / test edilmemiş

**Doğrulanmış (okundu ya da kaynak):**
- ReasonLog halka ve budama değişmezleri. `config` ve `reasons` hash'te ve kayıtta. Karar özeti kalıcı ve `decision_reason_id` budanınca 0. Denetçide ve sonuç panelinde dürüst metin var.
- Sim tick içinde günlüğü okuyan kod var (`EventCauses.recent_declines`, `declines_days`=30). `CouncilWhy` kopya deseni. GOLDEN taşıyan 10 test dosyası.
- Godot 4.7.2: iOS'ta `window_set_vsync_mode` Compatibility'de etkisiz ve get hep `ENABLED`. Kare temposu CADisplayLink'te, `allow_high_refresh_rate` 120/60. `screen_get_refresh_rate` Düşük Güç Modunda 60. GLES'te GPU zaman damgası yok. `TIME_PROCESS` saniyelik tepe (işlem + draw). `viewport_get_measured_render_time_cpu` V-Sync'ten bağımsız ve ölçüm açılmazsa 0.
- iPad JSON alanları: a-serisi 120 Hz, `max_fps` 0, `vsync_mode` 1. b1 60 Hz, p50 16,68, `novsync_requested` true, `vsync_mode` 1. Tick kareleri 9,7-19 ms.

**Varsayılan / çıkarım:**
- b1'deki 60 Hz okumasının Düşük Güç Modundan gelmesi. Kesintinin pil uyarısından gelmesi. Tick'siz iPad maliyetinin ~6 ms olması ve 120 Hz'de kullanımın %70'i aşması.
- Kayıt başına bellek (2-5 KB) ve kayıt boyutu (~1 KB) tahminleri. b2'nin ~85 B/parsel boyutu.
- `frame_post_draw`un sunum beklemesini dışarıda bıraktığı. Instruments'ın GL yolunda GPU verisi vermesi. `Engine.max_fps`'in iOS davranışı.
- Bugünkü oynanabilir dünyada gerekçe ufkunun 30 günden kısa olabileceği (R1).

**Test edilmemiş / ölçülmedi:**
- Hiçbir Godot koşusu ve hiçbir test bu oturumda çalıştırılmadı. Pruned-yol UI testleri (`tests/ui/m2_result_default_regime_test.gd`, `tests/ui/m2_inspector_test.gd`) okundu, koşulmadı.
- Günlük kayıt hızı bugünkü yapıda ölçülmedi. `busy_ms` ölçüsü hiçbir platformda denenmedi. b2 uygulanmadı. Kapasite artırımının ms maliyeti ölçülmedi.

## Kaynaklar
- Godot 4.7 belgeleri: [RenderingServer](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html), [DisplayServer](https://docs.godotengine.org/en/stable/classes/class_displayserver.html), [Performance](https://docs.godotengine.org/en/stable/classes/class_performance.html).
- Godot `4.7.2-stable` kaynağı (github.com/godotengine/godot): `drivers/apple_embedded/display_server_apple_embedded.mm`, `drivers/apple_embedded/godot_view_apple_embedded.mm`, `platform/ios/godot_view_ios.mm`, `platform/ios/display_server_ios.mm`, `drivers/gles3/storage/utilities.cpp`, `main/main.cpp`, `doc/classes/ProjectSettings.xml`.
- Apple: [Optimizing iPhone and iPad apps to support ProMotion displays](https://developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays) (Düşük Güç Modunun 60'a indirmesi için yalnız ikincil kaynak bulundu [varsayım]).
- `docs/engine-reference/godot/` V-Sync, iOS kare temposu ve ölçüm API'leri hakkında **bilgi içermiyor**. Bu yüzden yukarıdaki sürüm etiketli kaynak ve belge kullanıldı. Yerel referansa eklenmesi önerilir (`modules/rendering.md`).
