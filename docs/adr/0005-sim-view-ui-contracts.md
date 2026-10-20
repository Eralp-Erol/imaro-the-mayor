# ADR-0005 · Sim↔View↔UI sözleşmeleri (v1.0)

- Durum: kabul (v1.0) · Tarih: 2026-10-20 · Karar veren: technical-director (contracts hattı, T-023). Yaratıcı etki yok: ad, parti, protagonist, para birimi, sayı **üretilmez**.
- Karşıladığı gereksinimler: TEK-01, TEK-02, TEK-03, SIM-05, SIM-07, SIM-09, SIM-12, CAN-03, PLT-04
- Dayanak: ADR-0002 (katmanlar, komut, gerekçe), ADR-0001 (tick kare içinde değil), ADR-0004 (platform bağımsız sim), Q-003 (para AÇIK)
- Kod: `src/contracts/` · Mock: `src/contracts/mock/` · Fixture: `tests/fixtures/` · Testler: `tests/contracts/`

## Bağlam
Paralel hatlar (sim, ux, actors, render, world) aynı anda yazıyor. ADR-0002 katmanları ve yönü tanımladı ama hatlar arası **veri yüzeyi** yoktu: UI gerçek sim'i (T-027) beklemeden geliştirilemiyordu ve her hat kendi "gerekçe", "komut", "olay" biçimini uyduracaktı. Bu ADR tek yüzeyi, değişiklik kuralını ve gerçek sim gelene kadar kullanılacak deterministik mock'u sabitler. Kapsam bilerek v1.0 ile sınırlıdır; T-018 veri ihtiyaçları (`design/specs/ux/ux-data-needs.md`) v1.1 revizyonuna girer (§9).

## Karar

### 1. Sözleşme listesi ve sahipliği (a)
Tüm dosyalar saf GDScript, `RefCounted`, statik tipli; Node/Time/OS/rastgelelik yok (tarama testi). Sahip: **contracts hattı** (technical-director). Başka hat değiştirmez; ihtiyaç raporla gelir (§8).

| Sınıf | Rol |
|---|---|
| `SimContract` | Sürüm (`VERSION = "1.0"`), `FIXED_SCALE = 1000`, kaynak sabitleri (`&"sim"`/`&"mock"`), referans dizgeleri (`parcel.12`, `actor.investor.3`, `vote.1`, `command.7`, `budget.1`), tür zorlama, kanonik sözlük |
| `SimFacade` (`@abstract`) | View/UI'nin sim'e tek kapısı (§2) |
| `SimDto` (`@abstract`) | DTO tabanı: `to_dict()`, `to_bytes()`, `same_as()` |
| `SimSnapshot`, `ClockView` | Tick sınırı özet kopyası: saat, bütçe, meclis, grup tepkileri, sayaçlar, `extensions` |
| `SimCommand`, `CommandResult` | Komut + beyaz liste katalog + ortak şekil doğrulaması; gerekçeli sonuç |
| `SimEvent` | Olay kaydı (çekme modeli, `seq` imleci) |
| `ReasonRecord`, `ReasonFactor` | `{aktör, karar, faktörler[{ad,değer,ağırlık}], eşik, tick}` + sonuç/puan/zincir |
| `ActorRef` | Aktör referansı: `kind`, `id`, `name_key` (ad yok) |
| `ParcelView`, `BudgetView`, `BudgetLineView`, `GroupReactionView`, `CouncilView`, `CouncilBlocView`, `CouncilVoteView` | Alan görünümleri |
| `SimContractChecks` | Her facade uygulamasına uygulanan uyum kontrolleri + `observable_state()` (hash) |
| `MockScenario`, `MockSimFacade` | MOCK veri yükleyici/doğrulayıcı ve deterministik oynatıcı (§6) |
| `WorldFixture` (`tests/fixtures/`) | Küçük sentetik `WorldData` (§7) |

### 2. `SimFacade` yüzeyi
```
contract_version() -> String            is_mock() -> bool            provenance() -> StringName
current_tick() -> int                   speed() -> int               available_speeds() -> PackedInt32Array
set_speed(level: int) -> bool           advance(ticks: int) -> int   # yalnız tick sürücüsü/testler
validate_command(c: SimCommand) -> CommandResult   # kuru koşu: valid | rejected
submit_command(c: SimCommand) -> CommandResult     # queued (id>0, apply_tick=tick+1) | rejected (id=0)
snapshot() -> SimSnapshot
parcel_ids(region_code := &"") -> PackedInt64Array             parcel_views(ids) -> Array[ParcelView]
events_since(after_seq: int, max_count := 0) -> Array[SimEvent]
last_event_seq() -> int                 first_retained_event_seq() -> int
reasons_for(subject_ref: StringName) -> Array[ReasonRecord]    reason(id: int) -> ReasonRecord
```
Kurallar: okumalar **değer kopyası** ve **tick sınırında tutarlı** (sim iş parçacığında koşsa da yarım tick görünmez — T-027 çift tampon/kopya ile sağlar); yazma yalnız komut; ana iş parçacığından çağrı; **sinyal yok** (tüketici `current_tick()`/`last_event_seq()` değişimini yoklar — iş parçacığı sınırında sinyal karmaşası ve istek/yanıt için sinyal yasağı nedeniyle). Hız sim durumu **değildir** (determinizme ve komut günlüğüne girmez): seviye `SPEED_PAUSED=0 … SPEED_FASTEST=3`; seviye → gün/sn eşlemesi tick sürücüsü yapılandırmasıdır (ÇM). Snapshot parsel listesi taşımaz (ölçek: on binlerce) — parseller `parcel_ids/parcel_views` ile sınırlı sorgulanır.

### 3. DTO kuralları
- `to_dict()` yalnız StateHash'in kabul ettiği türleri üretir: tekil `Vector2` yok (`[x, z]`), tipli `Array` yok (bayt kodlaması farklı — 4.7.2'de doğrulandı). Serileştirme `var_to_bytes(to_dict())`; karşılaştırma `StateHash.of(to_dict())` veya `same_as()` (bayt eşitliği). Açık uçlu sözlükler (komut parametreleri, `args`, `extensions`) kanonik anahtar sırasıyla yazılır.
- `static from_dict(d)`: JSON'un float sayılarını tamsayıya, dizgeleri StringName'e, dizileri Packed dizilere zorlar; **bilinmeyen alanları yok sayar** (ileri uyum), **eksik alana varsayılan** verir (geri uyum). JSON → DTO → JSON kayıpsızdır (test).
- Metin yok: tüm görünen metinler **anahtar** (`decision_key`, `name_key`, `message_key`, `reason_key`, `title_key`, `line_key`) + `args` (int/String/bool; ondalık yok).
- Oran/ağırlık/duruş/yoğunluk: sabit nokta tamsayı (`FIXED_SCALE = 1000`; 0.42 → 420). Kalıcı sim durumunda float yok kuralıyla (ADR-0004 §2) uyumlu.
- Kaynak: `SimSnapshot`, `ParcelView`, `SimEvent`, `ReasonRecord`, `CommandResult` `provenance` taşır. UI `provenance != &"sim"` olan her yüzeyde **MOCK** rozeti gösterir (`app.mock_badge`).
- SIM-09: sözleşmede tek toplam memnuniyet/onay alanı yoktur; `SimContractChecks.check_no_aggregate_score` ağaçta `happiness/approval/satisfaction/popularity…` anahtarlarını reddeder.

### 4. Komutlar ve CAN-03
Yaşam döngüsü: `submit_command` → ortak şekil doğrulaması (`SimCommand.validate_shape`: tür, zorunlu/bilinmeyen parametre, tip, aralık) + belirlenebilen durum denetimi → `queued` ya da gerekçeli `rejected`; sonraki tick sınırında uygulanır → `command.applied` ya da duruma bağlı ret `command.rejected` olayı (aynı `command_id`, `message_key` = ret anahtarı). Reddedilen komut kimlik tüketmez. Ret anahtarları: `command.reject.{unknown_kind, not_a_mayor_verb, missing_param, unknown_param, bad_param_type, invalid_value, invalid_target, precondition}`.
Katalog **beyaz liste**, v1.0: `zoning.propose {parcel_ids: PackedInt64Array, land_use: StringName; density?, max_height_m?: int}`, `budget.propose {lines: {StringName: int ≥ 0}}`. `building.* / private.* / spawn.*` türleri `not_a_mayor_verb` ile reddedilir ve katalogda bulunamaz (test). Arazi kullanımı sözlüğü (`land_use`) sim yapılandırmasıdır; sözleşme değer kümesini sabitlemez.

### 5. Olaylar ve gerekçeler
- `SimEvent.seq` 1'den başlar, boşluksuz artar; v1.0 türleri: `command.applied/rejected`, `actor.decided`, `group.reacted`, `parcel.changed`, `budget.changed`, `council.vote_opened/vote_resolved`. Saklama sınırlı olabilir; `after_seq < first_retained_event_seq() − 1` ⇒ kayıp, tüketici snapshot ile yeniden eşitlenir. **Kural:** olay saklama ufku ≤ gerekçe saklama ufku (saklanan olay budanmış gerekçeye işaret etmez).
- `ReasonRecord` değişmezi (v1.0, `scoring = linear`): `score = Σ contribution(value, weight)`, `contribution = (value × weight) / FIXED_SCALE` (sıfıra doğru kesme); `outcome = positive ⇔ score ≥ threshold` — `decision_key`'deki eylem gerçekleşti (yatırım yaptı/protesto etti); `negative` ⇔ gerçekleşmedi (yatırım gelmedi, SIM-07). `subjects` ilgili varlık referansları; `parent_ids` nedensellik zinciri (yalnız daha küçük id). Faktör: `name_key, value, weight, is_estimate, source_ref`. Doğrusal olmayan puanlama gerekirse yeni `scoring` değeri = MINOR sürüm + UI desteği.

### 6. Mock (`MockSimFacade`) ve senaryolar
Senaryo dosyası (`tests/fixtures/mock_scenario_*.json`, biçim Ek A) `provenance: "MOCK"` ve `"MOCK"` ile başlayan açıklama taşımazsa **yüklenmez**; beyan edilen her gerekçe sonucu etken aritmetiğiyle doğrulanır (mock bile tutarsız "neden" gösteremez). Mock rastgelelik/zaman kullanmaz; kurallar: komutun genel anlamı (imar → `pending_zone`; bütçe → `proposed` + `status=proposed`) + ilk eşleşen kuralın etkileri `after_ticks` sonra. Beş senaryo: `investment_positive`, `investment_declined` (aynı imar, farklı koşul, SIM-07), `group_reactions` (destek + protesto), `council_budget_vote`, `invalid_commands`. Mock parselleri `WorldFixture` karasında, beyan edilen bölgededir (test).

### 7. `WorldData` okuma sözleşmesi (d)
Kararlı yüzey (`src/world/world_data.gd`, world hattı uygular; değişikliği contracts hattı bu ADR'ye işler):
- Alanlar (salt okunur): `world_id, world_seed, origin, size, cell_size, width, height, sea_level`, raster'lar `heights, land_mask, region_ids, landmass_ids, shore_distance` (satır-büyük, `idx = j*width + i`, örnek = hücre köşesi), `regions[]` (`id, code, anchor, radius, centroid, cell_count`), `islands[]`, `sites[]`, `terraces[]`, `port_site`; sabitler `REGION_NONE, LANDMASS_WATER, LANDMASS_MAINLAND`.
- Metodlar: `bounds, contains, cell_to_world, world_to_index, height_at, is_water, depth_at, region_at, region_code_at, landmass_at, slope_degrees_at, region_by_code, terraces_of_region, site_by_id, state_dict, state_hash`.
- Koordinat: dünya metresi, x doğu, z güney, y yükseklik (ADR-0002 §2). **Kıyı/ada/bölge koordinatları ÇM verisidir ve değişir: kod koordinat ve bölge kodu GÖMMEZ**; konumları `region_by_code(...).anchor/centroid`, `port_site`, `sites` üzerinden okur, kodları veriden alır. `WorldFixture` bilerek farklı kodlar (`F1`, `F2`), sıfırdan farklı köken ve 8×8 km/200 m ızgara kullanır: gerçek dünyaya gömülü varsayım fixture'da kırılır. View/UI dünya verisini değiştirmez; değişiklik (yol, parsel bölünmesi) yalnız sim'den ve ileride `WorldNetwork` sözleşmesiyle (T-011, v1.1) gelir.

### 8. Değişiklik protokolü (b)
1. Değişikliği yalnız contracts hattı yapar; ihtiyaç sahibi hat raporunda ister, koordinatör contracts görevine bağlar.
2. **MINOR** (`1.x`): yeni isteğe bağlı alan (varsayılanlı), yeni komut/olay/`scoring` türü, yeni DTO. Eski tüketici çalışmaya devam eder. **MAJOR** (`2.0`): alan kaldırma/yeniden adlandırma/anlam değişikliği; `SimSnapshot.from_dict` ve `MockScenario` uyumsuz MAJOR'u reddeder.
3. Her değişiklik: bu ADR'de sürüm notu + `tests/contracts` güncellemesi + mock/senaryo güncellemesi aynı teslimde. Deneysel alan önce `SimSnapshot.extensions["x.<hat>.<ad>"]` ile denenir, kalıcıysa MINOR'da tipli alana taşınır.

### 9. Üretici/tüketici tablosu (c) ve "nasıl tüketilir"
| Hat / görev | Üretir | Tüketir |
|---|---|---|
| contracts T-023 | Bu ADR, `src/contracts/`, mock, fixture, uyum kontrolleri | `WorldData` (fixture için), `StateHash` (testler) |
| sim T-002 → **T-027** | `SimFacadeImpl extends SimFacade` | `SimCommand.validate_shape`, DTO'lar, `SimContractChecks` |
| actors T-016/T-017 | `ReasonRecord` değişmezine uyan karar kayıtları; grup/meclis durumu | `ActorRef`, `ReasonFactor`, `GroupReactionView`, `CouncilView` |
| ux T-019..T-022 | — (yalnız komut gönderir) | `SimFacade` (mock ile), tüm görünümler, ret anahtarları |
| render T-003/T-012, world T-011 | — | `WorldData` (§7); `ParcelView` (seçim/denetçi); toplu sütun görünümü v1.1 |

- **T-027 (sim):** `class_name SimFacadeImpl extends SimFacade` (`@abstract` eksik metodu ayrıştırma hatası yapar). `submit_command`: önce `command.validate_shape()`; geçerse `Commands.submit(state, command.kind, command.params)`. Eşlemeler: `ReasonLog` id'leri 0'dan başlar → sözleşme id'si 1'den (+1 ya da sim tarafında değişiklik); faktör `value/weight` sözleşmede `FIXED_SCALE`'li tamsayıdır — `ReasonLog`'un "weight yoksa 1" ve float değerleri **uyumsuz**, sim tarafında sabit noktaya geçilmeli (öneri) ya da adaptör ölçeklemeli; `outcome/score/subjects/parent_ids` alanları `ReasonLog`'ta yok → T-016'da eklenmeli; sim ret kodları (`&"unknown_command"`) → `command.reject.*` anahtarlarına eşlenir; `TickDriver` hız adları (`&"normal"`) ↔ sözleşme seviyeleri (int) yapılandırma sırasıyla eşlenir. Kabul: `tests/sim/` içinde `SimContractChecks.check_facade(impl)` boş + mock ile aynı senaryo testleri (`tests/contracts/mock_scenarios_test.gd` örnek) gerçek sim'e uyarlanır.
- **T-019 (ux):** `ui_lab` bir `MockSimFacade.from_file("res://tests/fixtures/mock_scenario_*.json")` alır, UI yalnız `SimFacade` tipine bağlanır (gerçek sim'e geçişte kod değişmez). Her kare değil, `current_tick()` veya `last_event_seq()` değişince snapshot okunur. Onay düğmesi `validate_command()` sonucuna bağlanır (ret anahtarı = devre dışı gerekçesi). `is_mock()` → MOCK bandı. Para `economy.currency_*` yapılandırmasıyla biçimlenir.
- **T-016/T-017 (actors):** her karar `ReasonRecord.finalize()` ile aynı doğrusal değişmezi kurar; aktör kimliği `ActorRef.make(kind, id, name_key)`, ad anahtarı yer tutucu (`actor.<tür>.<n>.name`). Grup tutumu grup başına ayrı (`GroupReactionView`), toplam skor yok.

### 10. v1.1 için bırakılan uzantı noktaları
`SimSnapshot.extensions` (deneysel alanlar) · katalogda yeni mayor fiilleri (`public_work.draw` + `PublicWorkDraft` ön izleme, `policy.*`, meclis destek arama) · `ParcelView` → `DistrictView` ve imar ön izlemesi · `PlayerRecord`/sicil görünümü (SIM-09, `politics-elections.md`) · medya tonu · render için toplu sütun görünümü (`ParcelColumns`: Packed dizilerle id/konum/tür/yükseklik; T-012) · `WorldNetwork` okuma sözleşmesi (T-011) · `scoring` türleri · olay saklama/`gap` bildirimi. UX taslağındaki `SetSpeed/TogglePause` komutları bilerek komut değildir (hız sim durumu değil, §2).

## Alternatifler ve neden reddedildi
| Seçenek | Artı | Eksi |
|---|---|---|
| UI'nin `GameState`'i doğrudan okuması | Sıfır kopya | Katman ihlali (ADR-0002), iş parçacığı yarışları, mock yapılamaz, sim iç biçimi değişince UI kırılır |
| Sinyal/itme (push) olaylar | Anlık bildirim | İş parçacığında koşan tick'te güvensiz; kare/tick sırasına bağlı determinizm riski; istek/yanıt için sinyal kuralı ihlali |
| DTO = `Resource` | Editör denetçisi | Serileştirme/yükleme maliyeti, `var_to_bytes` ile nesne kodlaması yok; RefCounted + `to_dict` daha basit ve hash'lenebilir |
| JSON DTO / ham Dictionary | Esnek | int/float ayrımı kaybolur (T-900 bulgusu), tip güvenliği yok |
| Float faktör/ağırlık | Doğal | Platformlar arası son bit farkı (ADR-0004 §2), kayıt hash'i oynar; sabit nokta tamsayı seçildi |
| Her karede tam snapshot (parseller dahil) | Basit | Metroda on binlerce parsel; ölçek dışı. Parseller sorgulu, toplu görünüm v1.1 |

## Sonuçlar ve riskler
- Kazanım: UI/aktör/render hatları bugün mock ile ilerler; gerçek sim aynı yüzeyi aynı uyum kontrolleriyle (`SimContractChecks`) kanıtlar.
- Risk: mock davranışı (komut genel anlamı, kural oynatma) gerçek sim'den sapabilir → T-027 aynı beş senaryoyu gerçek kurallarla geçmeli; mock sayıları **denge verisi değildir**.
- Risk: `ReasonLog` (T-002) ile ReasonRecord arasında birim (float/1 vs sabit nokta) ve alan farkı (§9) — T-016/T-027 öncesi kapatılmalı; kapanmazsa adaptör kayıplı olur.
- Risk: snapshot kopyası ölçekte maliyetli (meclis/bütçe küçük; grup sayısı orta) — T-027'de ölçülür; aşımda yalnız değişen bölümler.
- Yeniden açma tetikleyicileri: T-018 veri ihtiyaçları (v1.1), T-027'de adaptörün kayıplı kalması, snapshot maliyetinin tick bütçesini (ADR-0001) bozması, çapraz platform hash farkı (T-009).

## Kanıt
- `tools/lane.sh verify contracts`: gdlint temiz, GdUnit4 64/64 (`artifacts/verify/lane-contracts/`), 2026-10-20.
- Mutasyon denemesi: CAN-03 önek listesi boşaltılıp imar anlamı silinince 5 test kırıldı; geri alındı.
- Doğrulanan Godot 4.7.2 davranışı (deneme projesi): `@abstract` + varsayılan argümanlı soyut metod, `Script.is_abstract()`, JSON sayıları float, tipli/tipsiz Array bayt farkı.
- Doğrulanmamış: gerçek sim ile uyum (T-027), snapshot maliyeti ölçekte, çapraz platform hash (T-009), dışa aktarılmış derlemede `tests/fixtures` JSON erişimi (ui_lab yalnız editör/dev).

## Ek A · MOCK senaryo biçimi (`imaro.mock_scenario` v1)
```
{format, format_version: 1, provenance: "MOCK", contract_version: "1.0", id: "mock_*", description: "MOCK: …",
 initial: {tick, speed, world_id, land_uses[], parcels[ParcelView], budget: BudgetView, council: CouncilView, groups[GroupReactionView]},
 rules: [{when: {kind, params?(alt küme eşleşmesi)}, reject?: {reason_key, args}, effects: [Etki]}],
 timeline: [Etki + at_tick ≥ 1]}
Etki: {after_ticks ≥ 0, type, reason_labels?[]} ve türe göre:
 reason {label, reason: {actor, decision_key, factors[], threshold, outcome (beyan, doğrulanır), score?, subjects[], parent_labels[]}}
 event {event: SimEvent alanları + reason_labels[]} · parcel {parcel_id, set{}} · group {reaction: GroupReactionView}
 budget {set{}, commit_proposal? | discard_proposal?} · council_vote {vote: CouncilVoteView (+closes_after, positions[].reason_label)}
```
Etiketler aynı kural tetiklenmesinde (ya da timeline'da) önce tanımlanmalı ve daha geç yürümemelidir (doğrulanır).

## Ek B · v1.0'da kullanılan metin anahtarları (UX metin tablosuna girdi)
`command.reject.*` (§4) · `event.command.applied`, `event.zoning.applied`, `event.investor.develop`, `event.investor.declined`, `event.construction.started`, `event.group.support`, `event.group.protest`, `event.council.vote_opened`, `event.council.vote_passed`, `event.budget.approved` · `decision.investor.develop`, `decision.group.support`, `decision.group.protest`, `decision.council_bloc.vote_yes` · `reason.factor.{demand, expected_return, infrastructure_capacity, construction_cost, jobs_access, commute_time, traffic_noise, rent_pressure, alignment_with_mayor, district_benefit, fiscal_concern}` · `council.vote.budget` · `budget.line.{roads, parks, services}` · `zone.{residential, mixed, commercial, green}` · `zoning.reject.protected_area` · aktör adları yalnız `mock.actor.<tür>.<n>` (yer tutucu). Hiçbiri kanon değildir.
