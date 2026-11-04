# ÖNERİ · Haftalık siyaset taraması sıçraması ve `parcel_views` çift okuması

- Durum: **UYGULANDI, numaralı ADR gerekmez (§2.4)** (2026-11-01 notu, technical-director): commit `471a088` §1 Seçenek A'yı ve §2.3 facade-yerel önbelleği uyguladı; commit mesajına göre GOLDEN_A/B ve büyük dünya hash'i değişmedi (bu not yazılırken testler koşulmadı, iddia commit mesajından). §1.4 (D: tick'i iş parçacığına alma) ayrı ADR olarak açık kalır. §2.2'deki "MINOR 1.6" atfı artık "sıradaki boş MINOR" diye okunur: 1.6 yolu yık (ADR-0005 Ek H), 1.7 yeniden iskân (ADR-0009) için ayrıldı.
- (Eski durum satırı: ÖNERİ; numara verilmedi; kabul edilirse ADR numarası alır ya da yalnız görev olarak uygulanır, bkz. §2.4)
- Tarih: 2026-11-01 · Yazan: technical-director · Taban: `3fdecb6`
- Karşıladığı gereksinimler: TEK-01, TEK-02 (determinizm ve kayıt hash'i korunur), TEK-05 (bütçe aşımı kanıtla), PLT-03 (sim kapsamı kısılmaz)
- Girdi: `production/log/2026-10-31-kare-sicramalari.md` (C tablosu, satır 83-89; öneri tablosu satır 123, 126)

## Özet (karar önerisi)

1. **Haftalık tarama:** önce **davranışı değiştirmeyen algoritmik düzeltme** (Seçenek A). GOLDEN_A/B değişmez; değişirse düzeltme yanlıştır ve geri alınır. Taramayı günlere yaymak (C) ve "işçi biterse commit" (F) reddedilir. Tüm tick'i iş parçacığına almak (D) doğru uzun vadeli yöndür ama ayrı ADR ister (ADR-0005 iki kuralına dokunur).
2. **`parcel_views`:** sözleşme değişmeden, `SimFacadeImpl.parcel_views` içindeki gerekçe dizinini (`subject_index`) gerekçe günlüğü sürümüne göre **facade-yerel önbelleğe** al. ADR gerekmez (uygulama ayrıntısı). Gerekçesiz "hafif okuma" sorgusu yalnız bu yetmezse, ADR-0005 eki (MINOR 1.6) olarak.

Sahibe şu an soru YOK. Yalnız A yetmezse sorulacak kart en altta.

---

## 1. Haftalık siyaset taraması (3-20 ms)

### 1.1 Bağlam: kod gerçeği

- Tetik: `src/sim/politics/politics_system.gd:44-49`, `tick % scan_days == 0` (`data/politics/cadence.json:4`, `scan_days = 7`). İçeride sırayla `BlocEngine.scan`, `MediaEngine.scan`, `EventEngine.scan`, `ReactionAgenda.scan`.
- Tick **ana iş parçacığında, karenin içinde** koşuyor: `src/game/playable.gd:747-748` (`_process` -> `_facade.drive_usec`) -> `src/app/tick_driver.gd:64` (`_sim.advance`). Bu, **ADR-0001 Karar 4'ten sapmadır** ("Kare içinde tick çalıştırılmaz", `docs/adr/0001-engine-and-rendering.md:14`). Sıçramanın kareye yansımasının yapısal nedeni budur; tarama ne kadar hızlanırsa hızlansın tick'li kare tick süresi kadar uzar. [doğrulandı: kod okundu]
- Sıcak nokta adayı (kod okumasıyla; **zamanlanmadı**):
  - `EventCauses.region_projects` (`src/sim/politics/event_causes.gd:11-31`) her çağrıda TÜM parsel sütununu tarar (`:19`, gerçek Ismeral'de 40 493), sonra sıralar. Her **değerlendirilen kesim** için bir kez çağrılır: `src/sim/politics/bloc_engine.gd:265` (`_evaluate`). Yorumdaki "ölçekte nadir" varsayımı (`event_causes.gd:8-9`) 40 bin parselde ve aynı haftada birden çok kesim değerlendirildiğinde tutmuyor. Log'daki `BlocEngine.scan` ort 1,4-1,9 / maks 9,0 ms ile uyumlu. [varsayım]
  - `EventCauses.recent_declines` (`event_causes.gd:35-42`) `ReasonLog.find` kullanır; `find` her eşleşmeyi **derin kopyalar** (`src/sim/core/reason_log.gd:117-123`). `_region_of_event` da `by_id` ile derin kopya alır (`src/sim/politics/event_engine.gd:245`, `reason_log.gd:88`). Bunlar yalnız ateşleme olan taramada koşar; `EventEngine.scan` maks 14,4 ms'nin (tick 532) adayıdır. [varsayım]
  - Log'un kendi notu: tek-tick maksimumları kalibrasyonsuz; bir kısmı makine yavaşlaması olabilir (log satır 12-16).

### 1.2 Soru: dilimlemek GOLDEN_A/B'yi değiştirir mi?

GOLDEN testleri (`tests/sim/m2_query_test.gd:13-14`, `:40-45`) gerçek `PoliticsBootstrap` ile 120 ve 60 günlük koşunun **son** durum hash'ini karşılaştırır (`tests/sim/m2_support.gd:28-46`); ~17 ve ~8 haftalık tarama içerir. Hash `GameState.state_hash()` (`src/sim/core/game_state.gd:107`) tüm sim durumunu (gerekçe günlüğü kimlik/tick dahil, siyaset sayaçları dahil) kapsar.

Kural: **Hash ancak aynı tick'te aynı girdilerle aynı yazma dizisi yapılırsa aynı kalır.** Bundan:

| Seçenek | Ne | GOLDEN | Determinizm riski (TEK-01/02) | Kare etkisi | Karar |
|---|---|---|---|---|---|
| **A. Bit-eşit algoritmik düzeltme** | `region_projects`'i tarama başına TEK parsel geçişine indir (bölge başına en yeni `cause_cap` aday; birleşimin ilk `cap`'i = bölgelerin ilk-`cap` adaylarının birleşiminin ilk `cap`'i, aynı sıralama anahtarıyla). Önbellek **tarama yerel değişkeni**: duruma girmez, kayda girmez. `recent_declines`/`_region_of_event`'te `find`/`by_id` yerine kopyasız `peek`/ters tarama (`reason_log.gd:97`). | **Değişmez** (aynı çıktı, aynı yazma sırası) | Düşük. Tek risk: kesimler arasında ekonomi sütunlarının (`stage`, `reason_id`) yazılması. Kodda görmedim ama doğrulanmalı; eşdeğerlik testi + GOLDEN + büyük dünya hash'i yakalar. | Haftalık tick -5..-15 ms (log tahmini; ölçülecek) | **Önerilen** |
| B. Aynı tick içinde işçi iş parçacığında paralel, sıralı birleştirme (ADR-0001 deseni) | Saf okuma kısmı (`region_projects`, kaynak hesabı) `WorkerThreadPool`'da kesim başına; sonuç kesim sırasıyla birleştirilir | Değişmez (birleştirme sırası sabitse) | Orta: GDScript `Dictionary` durumu iş parçacığı güvenli değil; işçiler yalnız Packed sütun OKUMALI. Ana iş parçacığı yine bekler; kazanç çekirdek sayısına bağlı (iPad daha az). A'dan sonra gereksizleşir. | Küçük-orta | A yetmezse |
| C. Taramayı haftanın günlerine yaymak (kesim N, gün N) | Davranış değişikliği | **Değişir** (girdiler farklı günden, gerekçe kimlik/tick sırası değişir) | Deterministik kalır (sabit takvim), ama oynanış anlamı değişir: kesimler farklı günlerde tepki verir. `scan_days` ÇM verisidir ama tepki zamanlaması oyuncunun gördüğü şeydir. | Sıçrama ~1/7'ye bölünür | Reddedildi (yalnız A+D yetmezse sahibe sor) |
| D. Tüm tick'i iş parçacığına almak (ADR-0001 Karar 4'ün asıl hali) | Tick ayrı iş parçacığında; facade tick sınırında tutarlı kopya okur | **Değişmez** (hesap ve sıra aynı; yalnız nerede koştuğu değişir) | Orta-yüksek: ADR-0005 `:44` çift tampon henüz yok; ADR-0005 `:159` sim'in paylaşılan `WorldNetwork`'ü **ana iş parçacığında** değiştirdiğini sabitler (yol/kamulaştırma op'ları tick içinde). Yarış ve yarım-tick görünmesi riski. | Tick kareden tamamen çıkar (tüm sıçrama türleri için) | Uzun vade; ayrı ADR |
| E. Tick'i karelere bölmek (yeniden başlatılabilir tick) | Tick t birkaç karede biter, sonra görünür | Değişmez (aynı sıralı hesap) | D ile aynı sorun: ara karelerde facade yarım tick görebilir (`ReasonLog`, kesim sözlükleri artımlı yazılıyor). Tarama "hesapla/commit" diye ayrılmadan güvenli değil; BlocEngine yazımları EventEngine girdisi (`event_sources.gd:11-27`) olduğundan ayrım aşama aşama gerekir. | Orta | Reddedildi (D'den pahalı, daha az temiz) |
| F. Hesabı önceki tick'lerde başlatıp "bitince" ya da sonraki tick'te commit | Önceki tick'in durumuyla hesap | **Değişir** (girdi t-k'den) | **Yasak** eğer commit anı işçinin bitişine bağlıysa (duvar saatine bağlı = TEK-01 ihlali, kayıt/yükleme farkı = TEK-02 ihlali). Sabit gecikmeli olsa bile C gibi davranış değişikliği. | - | Reddedildi |

Görevin sorduğu "hesabı tick içinde işçiye ya da sonraki tick'lere yay, sonuç aynı tick'te commit edilirse hash aynı kalır" ifadesinin iki yarısı farklı cevap alır:
- **Tick içinde işçiye** (B): evet, hash aynı kalır; ama tick ana iş parçacığında olduğu sürece kare yine bekler. Gerçek kazanç ancak D ile gelir.
- **Sonraki tick'lere yayıp aynı tick'te commit**: mantıksal olarak mümkün değil; tick t'nin sonucu tick t'nin durumuna bağlı ve o durum t'den önce yok. Önceki tick'in durumuyla hesaplamak F'dir (hash değişir). Aynı tick'i karelere yaymak E'dir (hash aynı, ama yarım-tick görünürlüğü sorunu).

### 1.3 Öneri ve kabul ölçütleri (A)

Sahip: `simulation-engineer`. Kanıt planı:
1. **Önce ölç** (kodlamadan): geçici zamanlayıcı ile `region_projects` ve `recent_declines` payını haftalık tick'te ayır (`tests/sim/perf/t043b_real_world_probe.gd --bands`). Pay küçükse A'yı bu iki fonksiyonla sınırlama; asıl sıcak noktayı bul.
2. Değişiklikten **önce** büyük dünya hash'ini kaydet: `t043b_real_world_probe.gd` zaten `state_hash` yazar (`:196`); sabit tick (ör. 1500) ile koş, değeri görev dosyasına yaz. GOLDEN fixture küçük (WorldFixture F1/F2); eşitlik/sıralama kenarlarını 40 bin parselde ancak bu hash yakalar.
3. Eşdeğerlik testi: eski `region_projects` (test içinde referans kopya) ile yeni yol, rastgele tohumlu durumlarda aynı `{reason_ids, parcel_refs}` dönmeli; negatif durum: eşit `reason_id` + farklı parsel sırası.
4. Kabul: GOLDEN_A/B **bit-eşit** (`m2_query_test.gd:40-45`), büyük dünya hash'i bit-eşit, `sim_purity_test`, kayıt/yükleme testleri geçer; haftalık tick maks/ort `cal_ms` kalibrasyonuyla, `CPU_Speed_Limit 100` iken önce/sonra raporlanır (log öneri 1).
5. **GOLDEN değişirse:** düzeltme yanlıştır, GOLDEN güncellenmez, geri alınır. GOLDEN'ı güncellemek yalnız davranış değişikliği bilinçli seçildiğinde (C) ve sahip onayıyla yapılır.

### 1.4 D için ayrı iş (bu öneri kapsamında karar yok)

ADR-0001 Karar 4 ile kod arasındaki sapma kayda geçmeli. D'yi açacak ADR şunları çözmeli: facade çift tamponu (ADR-0005 `:44`), `WorldNetwork`'ün tick sırasında değişmesi (ADR-0005 `:159`; yol op'larını tick sınırında ana iş parçacığında uygula, kalan sistemleri iş parçacığında koş), iPad çekirdek sayısı. Tetik: A'dan sonra tick'li kare p95'i masaüstünde D-007 eşiğini (tiksiz p95 <= 20 ms, ADR-0008 satır 3) hâlâ aşarsa.

---

## 2. `parcel_views` çift okuma

### 2.1 Neden var

- İki bağımsız görünüm tüketicisi aynı değişim akışını (`parcel_changes_since`, `src/sim/facade/sim_facade_impl.gd:395-405`) kendi imleciyle yokluyor ve değişen parselleri ayrı ayrı okuyor: `SimBuildingProjector._read` (`src/view/buildings/sim_building_projector.gd:315-317`; inşaattaki parselleri ilerleme için her gün yeniden okur) ve `LifeSimReader._apply_ids` (`src/view/life/life_sim_reader.gd:160-163`). Bu ADR-0005'in "sinyal yok, her tüketici yoklar, değer kopyası" kuralının (`docs/adr/0005-sim-view-ui-contracts.md:44`) doğal sonucudur; kendi başına hata değil.
- Pahalı olan **okuma sayısı değil, okuma başına sabit maliyet**: `parcel_views` (`sim_facade_impl.gd:272-292`) her çağrıda `ReasonLog.subject_index` ile TÜM gerekçe günlüğünü tarar (`:276` -> `reason_log.gd:127-139`; kapasite 1000, `data/sim/core_config.json:7`), istenen kimlik sayısı 8 de olsa. Log: projector 4,3 sn / 10 400 okuma ≈ 0,41 ms/parsel; `LifeSimReader` yorumu ~90 us/parsel (`life_sim_reader.gd:8`).
- İki tüketicinin hiçbiri `reason_ids` kullanmıyor (projector `_apply` `sim_building_projector.gd:389-420`, `LifeSimReader.state_of` `life_sim_reader.gd:47-58`). Kullananlar yalnız UI denetçisi/M2 paneli (`src/ui/panels/inspector_panel.gd:217`, `src/ui/flows/m2_result_model.gd:188`). Yani maliyetin büyük kısmı iki tüketicinin istemediği alana ödeniyor. [doğrulandı: kod okundu; maliyet payı varsayım, zamanlanmadı]

### 2.2 ADR gerekir mi?

- **En küçük değişiklik için hayır.** Sözleşme (`src/contracts/sim_facade.gd:71`, ADR-0005) aynı kalır, çıktı bit-eşit, durum değişmez. Uygulama ayrıntısıdır; görev kaydı + test yeter.
- Yeni sorgu/parametre (ör. `parcel_views(ids, with_reasons := false)` ya da gerekçesiz `parcel_states`) **sözleşme değişikliğidir**: ADR-0005 madde 3 (`:74`) gereği ADR-0005'e ek (MINOR 1.6) + `tests/contracts` + mock aynı teslimde. Yeni ADR değil, ADR-0005 eki. Log'daki "ADR gerekir" notu (satır 126) bu ikinci yol için doğru, birinci için değil.

### 2.3 En küçük güvenli değişiklik

`SimFacadeImpl.parcel_views` içinde `subject_index` sonucunu **tüm konular için bir kez** kur ve facade-yerel önbellekte tut; anahtar `(_state örneği, _state.reasons örneği, reasons.first_id(), reasons.last_id(), parcel_reason_limit)`. Anahtar değişince yeniden kur (en çok tick başına bir kez; kayıt yüklemede `_state`/`ReasonLog` örneği değişir). Çağrı başına maliyet O(istenen kimlik) olur.

Güvenlik koşulları:
- Önbellek `GameState`'e ve kayda girmez -> hash nötr; `m2_query_test.gd:48` (`test_every_read_query_leaves_the_state_hash_untouched`) bunu korur.
- Günlük yalnız sondan eklenir, baştan budanır (`reason_log.gd:66-70`); `first_id/last_id` ikilisi her mutasyonu yakalar. Elle düzenlenmiş boşluklu kayıt (`peek` yedek yolu, `:105`) id'leri değiştirmez, anahtar yine doğru.
- Dönen `reason_ids` Packed dizi (GDScript'te yazınca kopyalanır) -> değer kopyası kuralı korunur.
- Facade şu an yalnız ana iş parçacığından çağrılıyor (ADR-0005 `:44`); D yapılırsa önbellek commit edilmiş tampona bağlanmalı (o ADR'nin maddesi).

Kabul: yeni test, rastgele tohumlu koşularda önbellekli `reason_ids` == `subject_index(wanted, limit)` (her tick, kayıt-yükleme sonrası dahil; negatif durum: budama sonrası eski id görünmemeli); GOLDEN_A/B ve sözleşme testleri değişmez; projector `read_us`/okuma ve `LifeSimReader` kare süresi önce/sonra (`cal_ms` ile). Sahip: `simulation-engineer` (facade), ölçüm `qa-engineer`.

Ek (isteğe bağlı, ayrı): projector inşaattaki parselleri yalnız `progress_pm` için her gün yeniden okuyor; ADR-0005 Ek D bunu "aşama + süreden türetin" diye önerir (`0005-sim-view-ui-contracts.md:151`). Bu, okuma sayısını da düşürür; `godot-engineer` işi, sözleşme değişmez.

### 2.4 Bu öneri ADR olur mu?

İki madde de sözleşmeyi ve GOLDEN'ı değiştirmediği için **numaralı ADR gerektirmez**; görev olarak uygulanabilir. Numaralı ADR gerektiren tek şey §1.4 (D: tick'i iş parçacığına alma) ve gerekirse §2.2'deki ADR-0005 eki.

---

## Doğrulandı / varsayıldı / test edilmedi

- **Doğrulandı (okudum):** tetik ve tarama sırası; tick'in `_process` içinde ana iş parçacığında koşması ve ADR-0001 Karar 4 sapması; `region_projects`'in kesim başına tam parsel taraması; `find`/`by_id` derin kopyası; `parcel_views`'ın her çağrıda tam günlük taraması; iki görünüm tüketicisinin `reason_ids` kullanmaması; GOLDEN senaryo uzunlukları; ADR-0005 `:44`, `:74`, `:159` kuralları.
- **Varsayıldı:** sıcak noktaların ms payı (`region_projects`, `recent_declines`, `subject_index`) — zamanlanmadı; kesimler arası ekonomi sütunlarının değişmediği (A'nın bit-eşitliği buna dayanır); log'daki tek-tick maksimumlarının bir kısmının makine kaynaklı olduğu.
- **Test edilmedi:** hiçbir kod değişikliği yapılmadı, hiçbir koşu yapılmadı, `tools/verify.sh` koşulmadı.

## Sahibe soru (yalnız A ve D yetmezse sorulur)

> **Haftalık halk tepkisi hesabı bazen kısa takılma yapıyor; önce oyunu hiç değiştirmeden hızlandırıyoruz.**
> Yetmezse gruplar haftanın farklı günlerinde tepki versin mi (takılma küçülür, tepki zamanı biraz kayar)?
> **Önerilen:** Hayır, önce davranışı koruyan hızlandırma ve sim'i arka plana alma. / Evet, yay.
