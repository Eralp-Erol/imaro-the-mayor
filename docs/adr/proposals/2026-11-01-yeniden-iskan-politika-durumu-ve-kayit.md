# ÖNERİ · Yeniden iskân politikasının durum yeri, kayıt uyumu, hash koruması ve sözleşme sürümü (T-065 Aşama 1)

- Durum: **ÖNERİ** (numara verilmedi; kabul edilince ADR-0005'e "Ek H · Sürüm 1.6" olarak işlenir, ayrı ADR gerekmez)
- Tarih: 2026-11-01 · Yazan: technical-director · Taban: `ccfe68c` (`agent/handover-imaro-m01-349562fb`)
- Karşıladığı gereksinimler: TEK-01, TEK-02 (determinizm, kaydet/yükle/N tick hash eşitliği), SIM-07 (ev yoksa yok), SIM-12 (neden kaydı), CAN-03 (bina yaratılmaz), CAN-10/SIM-10 (politika seçimdir)
- Girdi: `production/tasks/T-065.md`, `design/specs/resettlement-social-security-v0.md` §3.0, `design/decisions/D-016`, D-014 §1, D-011, ADR-0002 Karar 5, ADR-0005 madde 2-3 ve Ek E/F
- Yöntem: yalnız kod okundu. Godot çalıştırılmadı; aşağıdaki "doğrulandı" ifadeleri **kod okuması** anlamındadır, test koşusu değildir.

## Özet (karar önerisi, 6 madde)

1. **Yer:** yeni, ayrı, tembel sim bölümü `state.systems["policy"]` (`PolicyState`). PoliticsState'e GİRMEZ. Bölüm yalnız ilk KABUL EDİLEN `policy.set` komutunda yaratılır; okuma/önizleme/doğrulama yaratmaz. Yokluk = kapalı (sabit kural; veri varsayılanı yok).
2. **Tahsis kaydı:** ayrı bir tahsis tablosu YOK. Tahsis, onu doğuran yolun iş kaydına isteğe bağlı alt kayıt olarak yazılır: `works[i].expropriation.resettlement` (yalnız politika açıkken ve yerinden edilen > 0 iken). Fiziksel etki `latent_hh` aktarımıdır; "ayrılmış birim" ayrıca tutulmaz, hedefin boşluğu aktarımla kendiliğinden düşer.
3. **Kayıt:** `SimSave.VERSION` 2 KALIR, taşıma kodu yok. Eski kayıt aynen açılır (bölüm yok = kapalı, alt kayıt yok = tahsis yok). Bölüm içi `version: 1` ve biçim denetimi `GameState.validate_dict` içinde.
4. **Hash:** politika hiç değiştirilmemiş koşuda yeni hiçbir bayt yazılmaz; GOLDEN_A/B ve kamulaştırmalı koşuların hash'i bit-bit aynı kalır. Hash'e giriş anı: (a) ilk `policy.set` (komut günlüğü + `policy` bölümü + gerekçe/olay), (b) politika açıkken yerinden etme olan yolun uygulanması (alt kayıt + `latent_hh` + bütçe kalemi).
5. **Sözleşme:** yeni komut türü olduğundan **MINOR 1.6** (1.5 içinde isteğe bağlı ek DEĞİL). 1.5'in artık tüketicisi var.
6. **Geri al / yolu yık:** tahsis YALNIZ `public_work.undo_last` ile, iş kaydındaki alt kayıttan geri alınır (aktarım tersine, bedel iadesi; tepki defteri kalır, D-011). "Yolu yık" tahsisi geri ALMAZ ve iadeyi tetiklememelidir; bu, paralel yol-yıkma işine bağlayıcı arayüz kısıtıdır (§6).

Sahibe soru: **YOK.** Bu kararların hiçbiri oyuncunun gördüğü davranışı seçmiyor; D-016 ve spec §3.0 ile belirlenmiş davranışı kaydetmenin en küçük yolu.

---

## 1. Bağlam: kod gerçeği (doğrulandı: kod okundu)

- Tüm durum `GameState`'tedir; `systems` sözlüğü OLDUĞU GİBİ hash'e ve kayda girer: `src/sim/core/game_state.gd:91-102` (`to_dict`), `:107-118` (`state_hash`). Yani `systems`'e yazılan her bayt hash'i değiştirir; yazılmayan bölüm hiçbir şey değiştirmez.
- Hash kanonik, sözlük sırası etkilemez: `src/sim/core/state_hash.gd:16-17`, `:156-182`.
- Kayıt zarfı `{format, version, state_hash, state}`; `VERSION = 2`, `MIN_SUPPORTED_VERSION = 2`: `src/sim/core/sim_save.gd:11-17`, `:57-62`. Zarf sürümü hash'e girmez (hash yalnız gövdeden: `:58-59`).
- Emsal (bu öneri bunu izler): sonradan eklenen üç bölüm de **tembel ve isteğe bağlı**, kayıt sürümü artmadan eklendi:
  - `public_works`: ilk uygulanan yolda yaratılır, ilk kamulaştırmada v1 -> v2 yükselir: `src/sim/public_works/public_works_state.gd:3-5`, `:20-22`, `:129-150` (yükseltme `:145-149`).
  - `budget`: yalnız bütçe sistemi kuruluyken ilk tick'te: `src/sim/budget/budget_state.gd:3-5`, `:36-50`.
  - `politics`: `src/sim/politics/politics_state.gd:37-58`.
  - Doğrulama "bölüm yoksa geçerli" kuralıyla zincirlenir: `src/sim/core/game_state.gd:164-173`; yükleme ek tutarlılık denetimleri `src/sim/facade/sim_facade_impl.gd:463-495` (`:477` alınan parsel tutarlılığı, `:483` bütçe).
- GOLDEN_A/B yalnız imar senaryosudur (yol/kamulaştırma YOK), ama siyaset kuruludur: `tests/sim/m2_query_test.gd:13-14`, `:40-45`; `tests/sim/m2_support.gd:28-46`. Kamulaştırmalı bir koşunun **sabitlenmiş hash'i yok** (testlerde 64 hex sabit yalnız `m2_query_test`, `state_hash_test`, `economy_land_values_unplanned_test`, `network_hash_cache_test`'te). Sonuç: "politika kapalıyken kamulaştırma davranışı bit-bit aynı" bugün KANITLANAMAZ; önce sabitlenmeli (ön koşul P3).
- Tepkinin tek giriş noktası: `src/sim/public_works/expropriation_flow.gd:135-136` (`note_reactions(state, command_id, plan["displaced"], ...)`); defter `public_works_state.gd:101-118` (değeri 0 olan satır yazılmaz, `:108`).
- Yerinden edilen hane bölge düzeyinde hesaplanır ve kaynak bölgede boşluk zaten düşülmüştür: `src/sim/economy/parcel_expropriation.gd:69-78`. `leave_region` kaderinde hane `latent_removed` ile düşer, geri almada geri eklenir: `:118-121`, `:161-164`. Varsayılan kader `return_to_latent`: `data/sim/public_works/road_works.json` (`expropriation.household_fate`).
- Aylık hane akışı `latent_hh`'ı değiştirir ve 0'da keser: `src/sim/economy/economy_system.gd:368-389` (`:388`). Yani bir tahsisten sonra geçen günlerde hedef bölgenin `latent_hh`'ı değişebilir; geri alma bunu hesaba katmalı (§5).
- Önizleme planı memo anahtarı: `expropriation_flow.gd:35-36` = (durum örneği, tick, graf sürümü, alınan parsel sayısı, sınıf, noktalar). Politika durumu anahtarda YOK.
- Bütçe yol gideri/iadesi `works[]` ile önek karşılaştırmasıyla mutabakat yapar; listeden düşen iş = LIFO iade: `src/sim/budget/budget_system.gd:126-141`. Bütçe değişmezi `balance = initial + revenue_total - roads_net`, `roads_net = Σ charged.amount`: `budget_state.gd:94-122`; defter türleri beyaz liste `budget_state.gd:17-20`, `:117-121`.
- Geri alma LIFO, iş kaydından: `src/sim/public_works/public_work_undo_handler.gd:55-62`; kamulaştırma tarafı `expropriation_flow.gd:148-165`.
- Komut kataloğu: "Yeni komut = katalog satırı + MINOR sürüm artışı": `src/contracts/sim_command.gd:9`, `:31-52`. ADR-0005 madde 2 (`docs/adr/0005-sim-view-ui-contracts.md:73`): yeni komut = MINOR. Ek F (`:187`): "1.5 yayımlandıktan sonra gelecek benzer ek 1.6 olur". 1.5'in tüketicileri artık var: `src/ui/flows/expropriation_text.gd`, `src/ui/flows/agenda_model.gd`, `src/ui/flows/agenda_panel.gd`. Sürüm 5 testte kilitli (`tests/contracts/*`: `"1.5"`). ADR-0005 `:90` `policy.*` ad alanını önceden ayırmıştı.

## 2. Karar A · Politika durumu nerede

**`state.systems["policy"]`, sınıf `PolicyState` (statik erişimciler, `PublicWorksState` kalıbı).**

```
systems.policy = {
  version: 1,
  resettlement: {enabled: bool, changed_tick: int, command_id: int}
}
```

- Yaratılış: YALNIZ `PolicySetHandler.apply_with_id` (ilk kabul edilen `policy.set`). `validate`, önizleme, facade sorguları bölüm yaratmaz (`state.system_data()` yaratır, `game_state.gd:40-44`; okuyucular `state.systems.get(KEY, null)` kullanmalı, `public_works_state.gd:41-43` gibi).
- Okuma: `PolicyState.enabled(state, &"resettlement") -> bool`: bölüm/anahtar yoksa `false`. O(1).
- Kapatma bölümü SİLMEZ (`enabled: false` kalır). Gerekçe: komut günlüğü zaten farklı olduğundan hash eşitliği hedeflenmez; silme ek kod ve "kim kapattı" bilgisinin kaybı demektir.
- Yokluk = kapalı **sabit kuraldır**; `road_works.json`'a `enabled_default` konmaz. Gerekçe: veri varsayılanı eski kayıtların davranışını sessizce çevirirdi (yükleme sonrası aynı durum, farklı sonuç = TEK-02 ihlali). Yeni oyunda açık başlatmak istenirse açılış önyüklemesi bölümü açıkça yazar (bilinçli GOLDEN değişikliği).
- Konum: Aşama 1 için `src/sim/public_works/policy_state.gd` + `policy_set_handler.gd` (T-065 dosya alanı); işleyici `PublicWorksContext.handlers()`'a eklenir (`public_works_context.gd:113-114`). Bölüm anahtarı genel (`policy`) olduğundan Aşama 3'te başka modüle taşımak durum biçimini değiştirmez.

**Reddedilen alternatifler**

| Seçenek | Artı | Eksi (neden reddedildi) |
|---|---|---|
| PoliticsState içinde (`systems.politics.policies`) | Yeni bölüm yok | Siyaset GOLDEN koşularında kuruludur (`m2_support.gd:28-46`): alan tembel olmazsa GOLDEN kırılır, tembelse PoliticsState'in "kurulunca tam şema" kuralı (`politics_state.gd:37-58`) bozulur. Siyaset kurulu olmayan yapılandırmada (facade siyasetsiz kurulabilir) politika yaşayamaz; oysa okuyan taraf kamu işleridir. Belediye yürütme kararı ile tepki motorunun iç durumu birbirine bağlanır. Aşama 3 meclis bağı bir **süreçtir** (oy/yetki), sahiplik gerektirmez. |
| `public_works` bölümü içinde | Tek dosya alanı | Bölüm ilk yolda `base_graph_hash` ile yaratılır (`public_works_state.gd:129-139`); yol çizilmeden politika açılırsa sahte/boş taban hash'i yazmak gerekir; doğrulama (`:209-237`) yol listesine bağlı. |
| Yol başına `resettle` parametresi | Durum yok | D-016 §1 ile çelişir (kalıcı politika); spec §3.0 açıkça reddetti. |
| Ayrı `reserved {bölge: birim}` tahsis tablosu | Açık "ayrılmış" sayısı | Gereksiz: `latent_hh` aktarımı hedef boşluğu zaten düşürür (boşluk = `res_built - latent_hh`, spec §2.1 satır 56). İkinci gerçek kaynağı = tutarsızlık riski + doğrulama kodu. |

## 3. Karar B · Tahsis kaydı ve tek hesap

- Alt kayıt (yalnız politika açık VE plandaki yerinden edilen toplamı > 0 iken yazılır):
```
works[i].expropriation.resettlement = {
  moves: [[kaynak_kod, hedef_kod, hane], ...]   # kaynak koda, sonra hedef sırasına göre; hane > 0
  rehoused: int, unplaced: int, cost: int, residual_pm: int,
  effective: {kaynak_kod: int}                   # tepki defterine giden değer
}
```
- `ResettlementPlanner.plan(state, cols, expropriation_plan, cfg) -> Dictionary` saf ve durumsuz; `ExpropriationFlow._problem` içinde, `ParcelExpropriation.plan`'dan hemen sonra çağrılır (`expropriation_flow.gd:75-86`). Önizleme ve uygulama aynı `p["plan"]`'ı kullanır (ölçüt 8).
- **Memo anahtarına politika bayrağı eklenmeli** (`expropriation_flow.gd:35-36`): aynı tick'te `policy.set` sonrası önizleme bayat plan döndürür. Bu bir hata kaynağıdır, isteğe bağlı değil.
- Uygulama (`ExpropriationFlow.apply`, `:128-136`): `ParcelExpropriation.apply`'dan sonra `moves` uygulanır (`latent_hh[kaynak] -= n`, `latent_hh[hedef] += n`); `leave_region` kaderinde `latent_removed[kaynak]` yalnız **bulunamayan** kadardır (bulunan hane bölgeden ayrılmaz, taşınır; aksi halde çift düşüm olur). `note_reactions`'a `plan["displaced"]` yerine `resettlement.effective` verilir; kapalıyken **aynı** `plan["displaced"]` nesnesi verilir (kod yolu değişmez).
- `plan["displaced"]` ve `summary["households"]` anlamı DEĞİŞMEZ (ham yerinden edilen). Etkin değer ayrı anahtardır; böylece paralel tepki işi (§6) ham sayıya dayanmaya devam edebilir.
- Tamsayı notu (systems-designer onayı gerekir, sahip sorusu değil): `effective = unplaced + rehoused * residual_pm / 1000` sıfıra doğru kesilirse 1-4 hanelik tahsiste kalan tepki 0 olur; D-016 §2 "biraz kalsın" sözüyle çelişir. Öneri: `rehoused > 0 ve residual_pm > 0` iken yukarı yuvarlama (en az 1).
- Bina yaratılmaz (CAN-03): planner yalnız mevcut `res_built` boşluğunu okur, hiçbir parsel/sütun birimi yazmaz.

## 4. Karar C · Kayıt uyumu (TEK-02)

- `SimSave.VERSION` **2 kalır**; `MIN_SUPPORTED_VERSION` 2 kalır; taşıma kodu yok.
  - Eski kayıt -> yeni sürüm: `policy` bölümü yok = kapalı; `resettlement` alt kaydı yok = tahsis yok. Kayıpsız ve kimlik dönüşümü; taşımaya gerek yok.
  - Emsal ile tutarlı: `public_works`, `budget`, `politics` bölümleri de sürüm artırmadan, bölüm içi `version` ile eklendi (§1).
- Doğrulama:
  - `GameState.validate_dict`'e bir satır: `PolicyState.validate_data(data["systems"].get(PolicyState.KEY, null))` (`game_state.gd:164-173` zincirine). Yoksa geçerli; varsa `version == 1`, `resettlement.enabled` bool, `changed_tick >= 0` int, `command_id >= 1` int. Bilinmeyen politika anahtarı reddedilmez (ileriye dönük), okunmaz.
  - `PublicWorksState._expropriation_problem` (`public_works_state.gd:258-280`): `resettlement` varsa biçim + değişmez `rehoused == Σ moves.hane`, `rehoused + unplaced == households` (hane = o işin ham yerinden edileni), her `hane > 0`, kodlar dizge. `public_works` bölüm sürümü artmaz (yeni üst düzey sözlük eklenmiyor; v1 -> v2 yükseltmesi üst düzey `taken/displaced/nearby` eklendiği için yapılmıştı, `:145-149`).
  - Bütçe: `charged[i].resettlement` (isteğe bağlı, yalnız > 0) ve bölüm alanı `resettlement_net` (tembel, yoksa 0). Değişmez `balance = initial + revenue_total - roads_net - resettlement_net` (yoksa 0 ile eski formülün aynısı). `_LEDGER_KINDS`'e `resettlement`, `resettlement_refund` eklenir (sabit eklemek hash'e girmez).
- **İleriye uyum (yeni kayıt eski derlemede) desteklenmez:** dağıtılmış derleme yok; ADR-0002 Karar 5 yalnız eskiden yeniye ve kaydet/yükle/N tick eşitliğini ister. Not: eski derleme `policy` bölümünü atmaz (`from_dict` `systems`'i olduğu gibi kopyalar, `game_state.gd:131`) ama okumaz; bu kabul edilen risk. İlk dağıtılan sürümden sonra bu karar yeniden açılır (o noktada zarf sürümü artışı + `version_too_new` koruması).

## 5. Karar D · Hash'e ne zaman girer, GOLDEN nasıl korunur

Politika hiç değiştirilmemiş koşuda yazılan yeni bayt **sıfır**. Gerekçe zinciri (her biri test edilecek):

| Yol | Kapalıyken | Kanıt/test |
|---|---|---|
| `systems.policy` | Yaratılmaz (yalnız `apply_with_id`) | okuma/önizleme sonrası `systems.has("policy") == false` |
| Planner | Çağrılmaz (`PolicyState.enabled` false) | kapalı koşuda iş kaydında `resettlement` anahtarı yok |
| `note_reactions` girdisi | Aynı `plan["displaced"]` | defter satırları önceki ile aynı |
| `latent_hh` | Yazılmaz | GOLDEN_X |
| Bütçe | `charged[i]` ve bölüm alanları eklenmez | GOLDEN_X (bütçeli kurulumda) |
| Gerekçe/olay günlüğü | Yeni kayıt yok (id sırası kaymaz) | GOLDEN_A/B + GOLDEN_X |
| Sözleşme sürümü 1.6 | Durumda değil | GOLDEN_A/B |

- GOLDEN_A/B zaten yol içermez; değişmemeleri gereklidir ama kamulaştırma yolu için yeterli kanıt değildir. Asıl risk kamulaştırma yolunda. **Ön koşul P3:** T-065 kodundan ÖNCE, birleşik tabanda (paralel iki dal birleştikten sonra) sahte dünya ile "kamulaştırmalı yol -> 30 gün -> geri al -> 30 gün" (bütçe kurulu) senaryosunun `state_hash`'i `GOLDEN_X` olarak AYRI commit'te sabitlenir. T-065 bu sabit değişmeden geçmelidir (ölçüt 1'in gerçek kanıtı).
- Açıkken hash'e giriş: ilk `policy.set` (komut günlüğü, `systems.policy`, gerekçe `decision.municipal.policy_set`, olay `policy.changed`); sonra politika açıkken yerinden etme olan her yol (alt kayıt, `latent_hh`, bütçe kalemi, neden etkenleri `reason.factor.rehoused_households` / `unplaced_households`). Bunlar yeni davranıştır; ayrı yeni sabit (`GOLDEN_R`) ile kilitlenir.
- Determinizm: rastgelelik yok; hedef sırası (mesafe, sonra kod), kaynak sırası (kod) ve `moves` sırası kanonik. Aynı tick'te `policy.set` ve yol: komut sırasına (seq) göre uygulanır; önizleme memo anahtarı bayrağı içerdiği için tutarlı.

## 6. Karar E · Geri alma, yolu yıkma ve paralel işlerle arayüz

**Geri al (`public_work.undo_last`, D-014 §1 "klasik undo"):**
- `ExpropriationFlow.revert` (`expropriation_flow.gd:148-165`), `ParcelExpropriation.restore`'dan sonra `moves`'u **ters sırada** geri alır: `geri = min(hane, latent_hh[hedef])`, `latent_hh[hedef] -= geri`, `latent_hh[kaynak] += geri`. Kırpma gereklidir çünkü aradaki aylık akış hedefi düşürmüş olabilir (`economy_system.gd:388`); `latent_hh` negatife düşmez, hane korunur (çıkan kadar döner). Gerçek dönen sayı `public_work.restored` olay args'ına `rehoused_returned` olarak yazılır (dürüst sayı; kırpma olduysa UI "N'si döndü" der).
- Bedel iadesi: bütçe mutabakatı iş listeden düşünce yol iadesiyle birlikte `resettlement_refund` yazar (`budget_system.gd:133-135` kalıbı). Tepki defteri KALIR (D-011, `public_works_state.gd:28-30`).
- Politika sonradan kapatılsa da geri alma tahsisi geri alır (kayıt işin üzerinde; politika durumuna bakılmaz).

**Yolu yık (D-014 §1, paralel ajan) — bağlayıcı arayüz kısıtları:**
1. Yolu yıkmak tahsisi geri ALMAZ: taşınan aileler taşınmış kalır, bedel iade edilmez. (Ajan yorumu, sahip kararı değil: yıkılan yolda binalar dönmüyorsa aileleri geri taşımanın gidecek evi yok. Yıkım binaları geri getirecekse bu madde yeniden açılır.)
2. Bu yüzden yolu yıkma, ilgili işi `works[]`'tan **ÇIKARMAMALIDIR** ya da çıkarıyorsa bütçe mutabakatının (`budget_system.gd:130-135`) bunu iade saymayacağı açık bir yol eklemelidir. Bugünkü önek mutabakatı "listeden düşen iş = iade" varsayar; ortadan bir iş silmek hem yolu hem tahsisi yanlışlıkla iade eder ve ondan sonraki tüm yolları yeniden tahsil eder. En küçük güvenli biçim: yıkım = yeni bir iş/op kaydı (`remove_road`), eski iş yerinde kalır. Bu, yol-yıkma işinin kendi tasarımıdır; burada yalnız kısıt konur.
3. `PublicWorkUndoHandler` "başka yol yapılana dek" kısıtına (D-014 §1) çevrilirse tahsis tarafı değişmez (yine LIFO, derinlik 1).

**Yıkım tepkisi (paralel ajan) — arayüz kısıtı:**
- Tepkinin hane girişi tek noktadır (`expropriation_flow.gd:135-136`). Yeni bir kanal (ör. D-014 §3 "ilçe geneli az ama sıfır değil") yerinden edilen hane sayısını `summary["households"]`/`plan["displaced"]`'dan doğrudan okursa yeniden iskân rahatlaması o kanala ulaşmaz. Kural: tepki tarafı haneyi `note_reactions`'a verilen sözlükten (yani defterden) okur. İlçe geneli kanalın da rahatlayıp rahatlamayacağı tasarım sorusudur (systems-designer; gerekirse sahibe).

## 7. Karar F · Sözleşme sürümü: MINOR 1.6

- Gerekçe: yeni komut türü = MINOR (`sim_command.gd:9`, ADR-0005 `:73`); Ek F'nin "açık tren" istisnası (`:187`) 1.5'in tüketicisi yokken geçerliydi, artık UI 1.5 alanlarını okuyor (§1). 1.5 içinde "isteğe bağlı ek" yapmak, kilitli `"1.5"` testlerinin anlamını sessizce genişletir.
- 1.6 içeriği (Ek H olarak ADR-0005'e, aynı teslimde `tests/contracts` + mock):
  - Komut `policy.set {policy_id: StringName, enabled: bool}` (`SimCommand.policy_set`). Ret: bilinmeyen politika `invalid_value`/`param=policy_id`; yapılandırmada yoksa `precondition`/`why=system.not_built`; aynı değer `precondition`/`why=policy.unchanged` (günlüğe boş kayıt düşmesin).
  - Sorgu `SimFacade.policies() -> Array[PolicyView]` (soyut OLMAYAN, varsayılan boş; mock/eski uygulama çalışır). `PolicyView {policy_id, enabled, changed_tick (-1 = hiç), changed_by_command (0 = hiç)}`. Bölüm yokken gerçek sim `resettlement` için `enabled=false, -1, 0` döndürür (yapılandırma varsa).
  - `public_work.road` önizleme args'ına ve `PublicWorkView`'a isteğe bağlı: `resettlement_applied (bool), rehoused_households, unplaced_households, resettlement_cost`; yalnız politika açıkken yazılır (kapalıyken anahtar yok = 1.5 tüketicisi etkilenmez).
  - Olay `policy.changed`; `public_work.restored` args'ına `rehoused_returned`.
- **Paralel tren kuralı:** yol-yıkma işi de yeni komut ekliyorsa o da 1.6 ister. İkisi aynı 1.6 trenine biner: handover'a ilk birleşen `VERSION`'u 1.6'ya çeker ve kilitli testleri günceller; ikincisi Ek H'ye satır ekler, sürümü tekrar artırmaz, ANCAK 1.6'nın arada UI tüketicisi oluşmadıysa. Oluştuysa 1.7.

## 8. Sonuçlar ve riskler

- Kazanım: GOLDEN riski yapısal olarak sıfıra yakın (yazılmayan bayt hash'i değiştiremez); kayıt taşıması yok; tahsisin tek gerçek kaynağı `latent_hh` + iş kaydı.
- Maliyet: `game_state.gd` (1 satır), `budget_state.gd`/`budget_system.gd` (isteğe bağlı alan), `src/contracts/` + mock + `tests/contracts/`, ADR-0005 Ek H. T-065'in yazılı dosya alanı bunları içermiyor; genişletilmeli (P4).
- Risk 1: GOLDEN_X sabitlenmeden uygulama başlarsa "kapalıyken bit-bit aynı" kanıtsız kalır. Azaltma: P3.
- Risk 2: yol-yıkma `works[]`'tan silerse bütçe çift iade/yeniden tahsil. Azaltma: §6 kısıt 2, P2'de teyit.
- Risk 3: geri alma kırpması hane sayısını korur ama hedef bölgenin pazar dinamiğini (çekim) dolaylı değiştirir. Kabul: geri alma "hiç olmamış gibi"nin en yakın deterministik yaklaşığıdır; tam eşitlik ancak anlık görüntüyle olur ve aradaki pazar akışını silmek olurdu.
- Yeniden açma tetikleyicisi: ilk dağıtılan derleme (ileri uyum), Aşama 2 hane sınıfı sütunları (sütun şeması ayrı karar), Aşama 3 meclis onayı (politika değişimi oylamaya bağlanırsa `policy` bölümüne `pending` alanı gerekir).

## 9. Kanıt

- Doğrulandı (kod okundu, çalıştırılmadı): §1'deki tüm dosya:satır atıfları, taban `ccfe68c`.
- Varsayım: `systems` anahtarlarını dolaşan ve bilinmeyen bölümde bozulan kod yok (arama: yalnız `src/sim/actors/actor_store.gd:81` kendi bölümünü dolaşıyor). Kaydet/yükle testiyle doğrulanacak.
- Varsayım: paralel iki dalın değişiklikleri görülmedi (izole worktree'ler; yalnız dal başlıkları okundu). §6 kısıtları onların bugünkü kodu değil, D-014 kararı üzerinden yazıldı.
- Test edilmedi: hiçbir şey koşturulmadı (talimat: Godot çalıştırma).

## 10. Ön koşullar (T-065 "blocked" kaldırılması için, tek satır)

P1 bu öneri Studio Director/TD tarafından kabul edildi · P2 paralel iki dal (yıkım tepkisi; yol geri al/yolu yık) handover'a birleşti ve yolu-yıkın `works[]`'tan iş silmediği ya da iade saymayan ayrı yol eklediği teyit edildi · P3 birleşik tabanda kamulaştırma+geri al senaryosunun hash'i `GOLDEN_X` olarak ayrı commit'te sabitlendi · P4 T-065 dosya alanına `src/sim/core/game_state.gd` (1 satır), `src/sim/budget/`, `src/contracts/`, `src/sim/facade/`, mock + `tests/contracts/` ve ADR-0005 Ek H eklendi.

## 11. Testler (Aşama 1 kabulüne eklenir)

1. GOLDEN_A/B ve GOLDEN_X değişmez (kapalı yol).
2. Okuma/önizleme/doğrulama sonrası `systems.has("policy") == false`; `policy.set` reddi de bölüm yaratmaz.
3. Kaydet (politika açık, bir tahsisli yol) -> yükle -> N tick: hash eşit; eski (bölümsüz) kayıt açılır ve kapalı davranır.
4. Aynı tick'te `policy.set(on)` + yol önizlemesi: önizleme tahsisi gösterir (memo bayat değil).
5. Geri al: `latent_hh` kaynak/hedef eski değerine döner (araya ay sınırı girmeyen durumda tam eşit), bütçe iadesi, tepki defteri kalır; ay sınırı girip hedef düştüyse kırpılmış `rehoused_returned` olayda.
6. `leave_region` kaderinde bulunan haneler çift düşülmez (kaynak toplam düşüm = bulunamayan + bulunan, hedef + bulunan).
7. Bozuk `policy` bölümü ve `rehoused != Σ moves` olan kayıt `corrupt` ile reddedilir.
