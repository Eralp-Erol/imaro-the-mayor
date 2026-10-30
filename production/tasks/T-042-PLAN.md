# T-042 uygulama planı · yol çizimi → altyapı kapasitesi → yatırımcı gerekçesi (technical-director, 2026-10-30)
REQ: CAN-04, CAN-05, CAN-03, SIM-03, SIM-04, SIM-12, WLD-01, WLD-12, TEK-01/02/03 · Sözleşme: ADR-0005 Ek E (ÖNERİLDİ, v1.3). [okundu]/[ölçülmedi]; Godot çalıştırılmadı.

## 1. Bugünkü gerçek durum [okundu]
- **Delta var, oyuncu yolu yok.** `NetworkDelta` (`network_delta.gd:1-16`): `add_road/remove_edge/set_open`, tamsayı cm. `WorldNetwork.add_road` + `apply_delta`
  (`world_network.gd:228-254`), su reddi (`:294`), kısa yol reddi (`:301`), JSON gidiş-dönüş testi (`network_model_test.gd:334`). Komut, handler, araç YOK.
- **Geri alma API'si yok.** Ters işlem = eklenen kenarları `remove_edge`. Grafı bit-bit geri getirdiği test edilmiş (`network_model_test.gd:285-304`),
  ama bloklar/parseller **yeni kimliklerle** yeniden türer (`world_network.gd:446-468, 511-514`).
- **Temel risk:** yapılı bloğu bölen yol o bloğun parsellerini siler, yenilerini üretir (`network_model_test.gd:202-221`). Sim'in parsel kümesi ise STATİK:
  açılışta bir kez kuruluyor (`playable.gd:344-389`), ekonomi sütunları n boyunda (`economy_system.gd:125-147`), kayıt parsel sayısını denetliyor
  (`sim_facade_impl.gd:322-323`). Bu yüzden v0 yolu **hiçbir parseli silmemeli ya da eklememeli**.
- `refresh_blocks` her op'ta TÜM ağın yüzlerini yeniden çıkarıyor (`world_network.gd:277, 404-421`), maliyeti [ölçülmedi]. **Ağın sahibi şu an oyun katmanı** (`playable.gd:202`), sim'de ona başvuru yok. ADR-0002 §1 "ağı sim değiştirir" diyor. Sim ana iş parçacığında koşuyor
  (`sim_facade_impl.gd:128`); `RoadView` (≥4 chunk) ve bitki yükleyicisi ise ağı işçi iş parçacığında okuyor.
- **Yol render'ı delta'yı okuyabilir.** `RoadView.rebuild_chunks(keys)` (`road_view.gd:136`) yalnız verilen 2 km'lik chunk'ları kuruyor, <4 chunk'ta iş parçacığı
  yok (`:9`). Plan farkı protokolü `src/view/roads/README.md`'de. Delta bağlantısı yok.
- **Altyapı kapasitesi BÖLGE düzeyinde.** `regions.infra_cap[r]` yalnız kurulumda yazılıyor (`economy_system.gd:212`; varsayılan 1000,
  `economy_config.json:47`; oynanabilirde T0 yükü + pay, `playable_economy.gd:45`). Boş kapasite <0 ise VETO (`investor_decision.gd:35-37`), kod
  `infrastructure_exhausted` (`:76-77`). T-014'ün yazma noktası. Etken `source_ref` alanı taşınıyor (`reason_log.gd:58`), ama `_factor` doldurmuyor (`:65`).
- Girdide `select_requested/cancel_requested` var, imleç-gezinme sinyali yok (`input_profile.gd:43,50`). İnşa modu boş (`mode_toolbar.gd:27`).
  Yakalama mesafesi 3 m (`network_rules.gd:15`). `system_data` bölümü ilk çağrıda yaratıyor (`game_state.gd:40-44`).

## 2. v0 kapsamı (öneri)
- **İki dokunuş:** A ucu, B ucu, düz tek parça. Sınıf yalnız `local` (yerel sokak), liste veride (`data/sim/public_works/road_works.json`). Uç ~24 px içindeki
  düğüme ya da kenara yapışır; komuta yapışılan gerçek koordinat gider. **En az bir uç ana yol bileşenine bağlı olmalı.**
- Denetimlerin hepsi saf `RoadDraftCheck`'te; UI önizlemesi ve sim AYNI kodu kullanır. Anahtar `public_work.reject.*` → metin: `too_short` "Yol çok kısa." ·
  `too_long` "Tek seferde en fazla {max_m} m yol çizilebilir." · `water` "Yol suyun üstünden geçemez; köprü henüz yok." · `slope` "Arazi bu yol için fazla dik." ·
  `not_connected` "Yol en az bir ucundan mevcut yol ağına bağlanmalı." · `crosses_parcels` "Yol mevcut arsaların içinden geçemez; kamulaştırma henüz yok." ·
  `duplicate` "Burada zaten yol var." · `outside_jurisdiction` "Bu nokta belediyenin yetki alanı dışında." (bölgesiz nokta; yetki imarla aynı, veride) ·
  `busy` "Dünya hazırlanıyor, birazdan yeniden deneyin." (§5).
- **Parsel güvencesi:** yol parselli bloğun İÇİNE giremez (2 m adımla `block_at`; uç ve kesişim çevresi hariç). Delta kenarlarının çevirdiği yeni yüzler v0'da
  parsellenmez, `KIND_OPEN` kalır (ağ kuralı, veri bayrağı). Raporda `added/removed_parcels` doluysa bu bir hatadır (assert + özellik testi).
- Geri alma yalnız SON oyuncu yolu için (LIFO), taban yol silinmez. Maliyet "henüz kurulmadı" (T-014); para/birim yok (Q-003); kalıcı koordinat yok (Q-015).

## 3. Komut sözleşmesi (ayrıntı: ADR-0005 Ek E)
- `public_work.road {points_cm: PackedInt64Array [x0,z0,x1,z1], road_class: StringName}`, `public_work.undo_last {}`; CAN-03 önekleri değişmez.
- `validate_command` sonucu: `valid` + `args {length_m, regions:{kod: birim}}` (sim'in kendi hesabı, önizlemede görünür) ya da `rejected` + anahtar.
  `submit_command` → `queued`. Tick'te yeniden denetlenir (arada başka yol gelmiş olabilir) → olay `public_work.built|removed` (`subjects: command.N,
  region.<kod>`) ya da `command.rejected`.
- Durum: `public_works` bölümü (`ops` NetworkDelta biçiminde, `works[{id, command_id, tick, region_units}]`, op başına `graph_hash_after`) yalnız İLK
  uygulanan yolda yaratılır. `validate` `system_data` çağırmaz. Böylece **t0 hash'i ve GOLDEN_A/B değişmez** (`m2_query_test.gd:13-14`).
- Kayıt/yükleme: `import_save` durumu kabul etmeden önce ağı kayıttaki `ops`'a eşitler (ortak önek → fazlası LIFO geri al → eksiği uygula, her adımda hash
  karşılaştırılır). Uyuşmazsa ret; eski durum ve ağ korunur. Mock aynı şekli doğrular, `mock_scenario_public_road.json` (ret → yol → onay) ile oynar.

## 4. Etki modeli (ÇM, veri; sayıları systems-designer verir)
- Yol, eklediği her kenar parçasının bölgedeki uzunluğu × `infra_units_per_km[sınıf]` kadar `infra_cap[r]`'yi artırır. Bağlantı koşul olduğu için bağlantısız
  yol etki yaratmaz. Geri alma aynı miktarı düşer; yük kapasiteyi aşarsa mevcut kural uygulanır (`stalled`).
- Görünür neden (SIM-12): kapasite etkeni `source_ref = command.N` taşır (bölgede kapasiteyi en son artıran yol). Yol yoksa `""`, golden kayıtlar aynı kalır.
  Yeniden değerlendirme mevcut periyodik taramayla yapılır. `infrastructure_exhausted` parsellere dikkat gecikmesi isteğe bağlı bir veri bayrağıdır
  (varsayılan kapalı, sonucu zorlamaz; kararı systems-designer verir).
- **Çift senaryo testi:** fixture ağ (`NetworkTestSupport.grid_network` + açık arazi), iki bölge A/B, dar kapasite, aynı imar. Önce ikisi de
  `infrastructure_exhausted`. A'ya bağlı yol → A `approved`, kapasite etkeni ≥ 0 ve `source_ref = command.N`; B ret kalır. Olumsuz: B'de bağlantısız yol →
  ret, kapasite aynı, hash komutsuz koşuyla AYNI. 5 tohum. Geri alma → kapasite düşer → durma kuralı devreye girer.

## 5. Görünür sonuç ve UX
- `WorldNetwork` durum dışı, sınırlı bir değişim günlüğü tutar. Playable `graph_version` değişince plan farkıyla yalnız etkilenen chunk'ları yeniden kurar.
  3D, harita ve seçim aynı ağdan okur (WLD-01). Yol koridorundaki bitki örnekleri gizlenir.
- Koruma: bitki yükleyicisi ya da iş parçacıklı yol kurulumu sürerken komut `busy` ile reddedilir. Ağ yalnız ana iş parçacığında, tick sınırında değişir.
- Araç İnşa → "Yol"; yalnız handler bağlıysa kaydedilir (ölü düğme yok). Sokak, komşuluk ve ilçe bandında açık; metro bandında "Yol çizmek için yakınlaşın"
  (ADR-0007).
- Akış: A'ya dokun (uç halkası, yapışma göstergesi). Masaüstünde imleç önizlemesi var; dokunmatikte B'ye dokununca araziye oturan çizgi çıkar. Renk:
  geçerli = focus token, geçersiz = uyarı token + ret metni. Panelde uzunluk, sınıf, bölge, "Altyapı kapasitesi +N", "Maliyet: henüz kurulmadı",
  [Onayla] [İptal] [Son yolu geri al]. Esc / `cancel_requested` iptal eder; sürükleme pan olarak kalır.
- T-041 denetçisinde gerekçe satırı "Altyapı kapasitesi ← Yol (gün N)" yazar (dokununca yola odaklanır); bölge satırında "kapasite X (yollarla +Y)".

## 6. İş bölümü ve sıra (aynı dosyaya iki yazıcı yok; Godot testleri sırayla, tek süreç)
1. **world-engineer** (`src/world/network/`, `tests/world/network/`, ağ kural verisi): `RoadDraftCheck`, delta yüzü kuralı, `undo_last_op`, değişim günlüğü.
   Önce ölçüm `experiments/t042-road-probe/`: `refresh_blocks`, chunk yeniden kurulumu, bölge başına açık arazi payı. Kabul: 500 tohumlu taslakta "denetim
   geçti ⇒ parsel değişmedi + graf bütün"; geri alma ⇒ taban `graph_hash`; yeniden oynatma bit-eşit; her ret anahtarı için olumsuz test;
   `refresh_blocks` ≤ 50 ms ya da yerel yenileme.
2. **simulation-engineer** (`src/contracts/` + mock + fixture, `src/sim/public_works/`, `src/sim/economy/` kaynak bağı, `import_save`, `data/sim/public_works/`,
   `tests/sim|contracts`): 1'e bağlı. **Sözleşme + mock önce teslim edilir.** Kabul: §4 çift senaryo; GOLDEN_A/B değişmez; yolla kaydet → yükle → N tick
   hash eşit; aynı komut dizisi → aynı sim hash + `graph_hash`; `SimContractChecks` mock + gerçek; ret durumu bozmaz.
3. **godot-engineer** (`src/game/playable.gd` + ağın sim'e verilmesi, `src/game/road_draw_tool.gd`, `src/view/overlay/road_draft_preview.gd`, `src/view/roads`,
   bitki tüketicisi, `tests/game|view`): 2'ye bağlı. Kabul: gerçek viewport girdi testi (A, B, onay → tick → kenar ağda, yalnız beklenen chunk'lar kuruldu);
   koridorda bitki yok; `busy` koruması; `m2-t042-*` pencereli yakalamalar; perf bütçesi.
4. **ui-engineer** (`src/ui/flows/road_draw_panel.gd`, araç kaydı, denetçi satırları, `data/ui/strings.tr.json`, `tests/ui`): mock ile 3'e paralel, `playable.gd`'ye
   dokunmaz. Kabul: her ret anahtarının metni var, onay `validate_command`'e bağlı, metroda kilit metni çıkıyor.
- Sıra: 1 → 2 (önce sözleşme) → (3 ∥ 4) → bağımsız QA (`production/qa/T-042-qa.md`) + design-director + technical-director.

## 7. Riskler ve test edilmeden kalacaklar
- R1 [ölçülmedi]: yoğun çekirdekte açık arazi az olabilir; v0 aracı çoğu yerde "geçemez" der (Soru 1). R2: `refresh_blocks` tüm ağı tarıyor, tick'te ani artış;
  iPad ölçülmedi. R3: tek paylaşılan ağ nesnesi; koruma kaçarsa veri yarışı olur (iş parçacığı testi). R4: etki bölge düzeyinde; bölge içinde yolun yeri fark
  etmez (Soru 2). R5: çok op'luk LIFO geri alma kanıtsız (yalnız tek op, `:285`); zincir özellik testi şart.
- Test edilmeyecekler: gerçek el ve iPad hissi (cihaz AÇIK), bütçe/bakım (T-014), köprü/tünel, ray/feribot, kamulaştırma, yeni sanat.

## Kullanıcıya ürün soruları
1. **Yol yapılı mahallelerin içinden geçebilsin mi?** (a, Önerilen) v0'da hayır: yalnız boş/açık arazide, mevcut yollara bağlanarak; kamulaştırma ayrı iş.
   (b) Boş arsaları bölebilsin (sim'e değişken parsel kümesi gerekir, büyük iş). (c) Binaların içinden de geçsin (kamulaştırma + siyasi tepki, M3+).
2. **Yolun yatırımcıya etkisi ne kadar yerel olsun?** (a, Önerilen) Bölgenin altyapı kapasitesini artırsın: hızlı, ama bölge içinde yolun yeri fark etmez.
   (b) Yalnız yakın arsalara erişim versin: daha gerçekçi, karar modeline parsel düzeyinde erişim eklemek gerekir.
