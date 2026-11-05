# ADR-0011 · B-080 (PE-03 `council.trust_gap` etkin güveni okusun) ve B-052 (yükleme sonrası sim-yapılı parsel sorgusu) karar notu

- Durum: kabul (uygulanmadı; uygulama görevleri aşağıda)
- Tarih: 2026-11-05 · Karar veren: technical-director
- Karşıladığı gereksinimler: B-080 -> SIM-12, SIM-05, TEK-01/02 · B-052 -> TEK-03, TEK-05, TEK-02, WLD-01 (ADR-0005 §8 sözleşme protokolü)
- Okunan taban: `34eae42`. Godot çalıştırılmadı; aşağıdaki her şey kod okumasıdır (Kanıt bölümü).

---

## B-080 · `council.trust_gap` D-021 kesintisini okumuyor

### Karar
**Seçenek B uygulanır:** `EventSources._council_sources` her üyenin güvenini `CouncilTrust.effective_trust` üzerinden okur. Bayrak/yapılandırma anahtarı EKLENMEZ.
Bu bir sim davranış değişikliğidir (salt görünüm değil): GOLDEN_A/B değişmez, **GOLDEN_X büyük olasılıkla değişir**, sözleşme sürümü ve kayıt biçimi değişmez.

### Gerekçe
- `council_trust.gd:76` "Oy girdisi ve üye görünümü TEK bu işlevi okur" diyor; aynı kavramın ("meclisin oyuncuya güveni") üçüncü okuyucusu (`event_sources.gd:156`) ham ilişkiyi okuyor. Panel "güven düştü" derken aynı adı taşıyan olay girdisi eski değeri kullanıyor: SIM-12 (görünen neden ile işleyen neden aynı olmalı) ihlali, gizli tutarsızlık sınıfı.
- Bu yeni bir yaratıcı karar değil: D-021'in sahip sözü "Meclis güveni düşsün". Güven düştüyse güvene bağlı her okuyucu düşmüş güveni görmelidir; ayrı bir "olay baskısı da artsın mı" kararı gerekmez. Büyüklük zaten veride: kesinti `reactions.json` `council_trust`, PE-03 ağırlığı `data/politics/events/pe-03.json` `trust_gap.weight` (systems-designer ayarı).
- Etki küçük ve sınırlı (hesap, veri okumasıyla): 5 üyeden 3'ü etkilenir, tavan 200 pm -> ortalama güven en çok 120 düşer -> `trust_gap` en çok +60 -> sürücü payı en çok +120 -> PE-03 baskısı en çok +36 pm (binde). PE-03 yine `council.budget_vote_failed >= 1` sert koşulu olmadan ateşlenmez.
- Bayrak reddedildi: tek satırlık tutarlılık düzeltmesine yapılandırma yüzeyi + doğrulama + test eklemek, geri dönüşü zaten veri ağırlığıyla mümkün olan bir şey için gereksiz.

### Dosyalar (değişecek)
1. `src/sim/politics/event_sources.gd:156` (tek satır):
   `trust_total += CouncilTrust.effective_trust(state, int(ActorStore.relation(state, ctx.actors, member, player)["trust"]), member)`
   (satır uzunluğu için iki satıra bölünebilir; `council_engine.gd:237` ve `politics_query.gd:51` ile aynı çağrı.)
2. `src/sim/politics/council_trust.gd:17-18, 76` yorumları: okuyucular "oy girdisi, üye görünümü ve PE-03 `council.trust_gap`".
3. `tests/sim/public_works/golden_x_council_trust_test.gd:67-74`: test 2 "siyaset durumu kesinti dışında aynı" diyor; düzeltmeden sonra `politics.events.last_pressure["PE-03"]` de farklı olabilir. Fark bu anahtara (ve PE-03 ateşlenirse ondan doğan gündem/etki alanlarına) daraltılarak açıkça iddia edilmeli; körlemesine silinmemeli.
4. `tests/sim/public_works/golden_expropriation_undo_test.gd:16` `GOLDEN_X`: değişirse AYRI commit'te, gerekçesiyle yeniden alınır (dosya başlığındaki kural; ADR-0009 P3).
5. `production/bugs/B-080.md` kapanış.

Değişmeyecek: `src/contracts/*` (sürüm 1.9 kalır, yüzey yok), `SimSave.VERSION`, politika digest'i (yalnız kod), `data/`.

### Risk
- **GOLDEN_X kayar (beklenen):** `EventEngine._evaluate_template` (`event_engine.gd:78-82`) PE-03'ün baskısını sert koşuldan ÖNCE her taramada `events.last_pressure`'a yazar; `cadence.json` milestone M2 olduğundan PE-03 açıktır. GOLDEN_X senaryosunda kesinti var (16 hane, eşik 10) -> `trust_gap` ve dolayısıyla yazılan baskı değişir. Tamsayı bölmesi farkı yutarsa değişmeyebilir; ölçülmeli.
- **GOLDEN_A/B değişmez:** yıkımsız koşuda `politics.council_trust` hiç yaratılmaz (`council_trust.gd:49-52`), `penalty()` 0 döner; ilişki güveni zaten [-1000,1000] (`actor_memory.gd:104,231` `clamp_permille`), dolayısıyla `effective_trust` özdeşliktir. Kod okuması; koşulmadı.
- Eski kayıt: kesinti ortasında kaydedilmiş oyun yeni kodla yüklenince PE-03 baskısı yeni kurala göre sürer. Kayıt biçimi değişmez; bilinçli davranış değişikliği.
- Kural kapalıyken (`enabled: false`) GOLDEN_X eski değeri `c987fb3d…` değişmemeli (tablo yok -> özdeşlik).

### Test planı (simulation-engineer)
1. Yeni test (`tests/sim/politics/council_trust_test.gd` içine): kesinti varken `EventSources.compute(...)["council.trust_gap"]` bağımsız formülle `clampi((1000 - ortalama(ilişki - kesinti)) / 2, 0, 1000)`; kesinti yokken ham ilişki formülüyle bit-eşit.
2. Kesinti varken PE-03 baskısı (`events.last_pressure["PE-03"]`) kural kapalı koşudan büyük-eşit; kesinti sıfıra toparlanınca eşit.
3. `tests/sim/m2_query_test.gd` (GOLDEN_A/B) aynen yeşil.
4. `golden_x_council_trust_test.gd` test 1 (kural kapalı = `c987fb3d…`) aynen yeşil; test 2 daraltılmış farkla yeşil.
5. GOLDEN_X: değişirse ayrı commit, mesajda neden (`last_pressure.PE-03`). `tools/verify.sh quick` (politika alanı + koruma çekirdeği), teslimde `full`.

---

## B-052 · Yükleme sonrası ~1,1 sn senkron okuma + T0 süpürmesinin ~11-12 sn yayılımı

### Karar
**B-052'deki `released_stock_parcel_ids()` önerisi yerine daha genel tek sorgu:** `SimFacade.sim_developed_parcel_ids() -> PackedInt64Array` = `ParcelView.developed_by_sim == true` olan TÜM parsel kimlikleri (artan, tekrarsız; T0 olan/olmayan ayrımı yok). Salt okunur sorgu; durum, hash, kayıt biçimi DEĞİŞMEZ. Sözleşme **MINOR 1.9 -> 1.10** (ADR-0005 §8 madde 2; Ek H: sürümsüz isteğe bağlı ek yolu kapalı). ADR-0005'e "Ek M · Sürüm 1.10" uygulama teslimiyle yazılır.

Projector yükleme sonrası tam eşitlemede (`_full_sync`) tüm parselleri değil yalnız bu listeyi okur; listede olmayan her gösterilen satırı unutur; T0 süpürmesi (`_t0_sweep`) kalkar.

### Gerekçe
- Projector'ın ürettiği satır kümesi tanım gereği `developed_by_sim` parselleridir (`sim_building_projector.gd:7-9`). Bu kümeyi doğrudan sim'den almak hem 16.205 T0 DIŞI okumayı hem 24.304 T0 süpürmesini aynı anda "yapılı parsel sayısı" kadar okumaya indirir. Önerilen `released_stock_parcel_ids()` yalnız süpürmeyi çözerdi ve "T0 parseli yalnız arsa geri açılınca sim yapısı alır" varsayımına (B-025 yolu) bağlı kalırdı; seçilen sorgu bu varsayıma bağlı değildir.
- Otorite sim'dir (TEK-03, ADR-0005): görünüm dünya op günlüğünden (`net.delta.ops` `restore_parcels`, B-051'in kullandığı yol) de serbest bırakılan T0 parsellerini türetebilirdi ve sözleşme değişmezdi; ama yalnız süpürmeyi çözer, sim ile ikinci bir doğruluk kaynağı açar. Reddedildi.
- Yalnız bütçe artırma (`SWEEP_BUDGET_US`) reddedildi: toplam iş (~2,4 sn) aynı kalır, iPad kare payını ölçmeden büyütür (ADR-0008/0010).
- Uyum: `SimFacade` tabanındaki varsayılan uygulama SOYUT DEĞİL ve **doğru**: `parcel_ids()` + `parcel_views()` (dilimli) ile `developed_by_sim` süzer. Mock ve eski uygulamalar doğru (yavaş) sonuç verir; projector yeteneğe göre dallanmaz. `SimFacadeImpl` hızlı yolu ezer.

### Dosyalar
- `src/contracts/sim_facade.gd`: yeni varsayılanlı yöntem (doğru yavaş yol) + belge yorumu. (contracts hattı, technical-director onayı bu ADR.)
- `src/contracts/sim_contract.gd:34-35`: `VERSION_MINOR := 10`, `VERSION := "1.10"`. `is_compatible` tamsayı ayrıştırır (`sim_contract.gd:57-61`), "1.10" güvenli; dizgi/float karşılaştırması yapan tüketici bulunmadı (grep).
- `src/sim/economy/economy_state.gd:143`: `developed_by_sim` yüklemini tek statik işleve çıkar (`stage != STAGE_VACANT and last_code == CODE_APPROVED`); `decorate_view` ve yeni `developed_parcel_ids(state)` (paketli sütun taraması, `parcel_ids` sırası artan) aynı işlevi kullanır: iki tanım kaymaz.
- `src/sim/facade/sim_facade_impl.gd`: ezme; ekonomi yoksa/kurulmadıysa boş dizi. Durum yazmaz.
- `src/contracts/sim_contract_checks.gd`: `check_facade` içinde sorgu = varsayılan yol eşitliği (küçük dünyada).
- Kilitli sürüm testleri "1.9" -> "1.10": `tests/contracts/policy_contract_test.gd:18,20`, `m2_contract_extension_test.gd:56,66`, `agenda_respond_contract_test.gd:42`, `expropriation_contract_test.gd:23-24`, `agenda_item_contract_test.gd:28`.
- `src/view/buildings/sim_building_projector.gd:366-396` (`_full_sync`) ve süpürme alanları (`:63-64`, `:176-182`, `:276-281`), `sim_building_pump.gd:57-58` (süpürme bütçe dalı): godot-engineer. `sweep_pending()` geriye dönük olarak hep false dönebilir ya da kaldırılır (çağıranlar güncellenir).
- `docs/adr/0005-sim-view-ui-contracts.md`: Ek M (1.10).

### Risk
- GOLDEN_A/B/X: sorgu durum yazmaz -> değişmemeli. Kanıt ŞART (koşulmadı): üç golden testi + sorgu öncesi/sonrası `state_hash()` eşitliği.
- Hızlı yol maliyeti (HİPOTEZ, ölçülmedi): ~40,5 bin elemanlık paketli dizide tek GDScript döngüsü; Intel Mac'te tek haneli ms, iPad'de daha fazla beklenir. Bugünkü 1.064-1.183 ms senkron okumaya göre küçük; ölçülmeli. Oyun ilerledikçe liste büyür (yüzler-binler); okunacak iş zaten o kadar satırdır.
- Davranış: liste `planned` parselleri de içerir (projector bunlara satır üretmez, okur ve geçer). Mevcut kural değişmez.
- Projector yükleme sonrası yalnız listedeki parselleri okursa, `_shown`'da kalıp listede olmayan T0 parsel satırları da hemen unutulmalı (bugün süpürmeyi bekliyor, `:388-391`). T0 binasının gizlenmesi projector'da değil `PlayableExpropriation` (B-051) yolundadır; o yol değişmez.
- 1.10 ilk iki haneli MINOR: yalnız tamsayı ayrıştıran karşılaştırma kullanılmalı; yeni kod dizgi karşılaştırması yapmamalı.

### Test planı
1. Sözleşme (`tests/contracts/developed_ids_contract_test.gd`, yeni): `VERSION == "1.10"`; hızlı yol == taban varsayılan yol şu durumlarda: taze dünya (boş), yatırımcı yapıları olan orta oyun, kamulaştırma + arsa geri açma + yeniden yapılaşma (T0 parseli listede), kayıt -> yükle sonrası; artan/tekrarsız; mock facade varsayılan yolla doğru sonuç; sorgu öncesi/sonrası `state_hash()` eşit; `sim_purity_test` yeşil.
2. GOLDEN: `tests/sim/m2_query_test.gd` (A/B), `tests/sim/public_works/golden_expropriation_undo_test.gd` (X) değişmeden yeşil.
3. Projector (`tests/game/m2_change_feed_projector_test.gd` + gerekirse yeni): yükleme sonrası tam eşitlemede okunan parsel sayısı == liste uzunluğu; çıktı sütunları eski tam tarama + süpürme sonucuyla (ve sıfırdan kurulan projector ile) bit-eşit; serbest bırakılıp yeniden yapılan T0 parseli yüklemenin hemen ardından çizili (süpürme beklemeden).
4. Ölçüm: `tools/godot/b050_load_probe.gd` önce/sonra `import_save`, `load_resync_ms`, `parcel_reads`, kare en çok ms. Hedef (kabul ölçütü önerisi): Intel Mac'te `load_resync_ms` <= 100 ms, süpürme kareleri 0. iPad ölçümü ayrı ve zorunlu değil ama raporda "ölçülmedi" yazılır.
5. `verify quick` her adımda (contracts + sim + view alanları), teslimde `full`.

---

## Sahibe sorulacak soru
**Yok.** İkisi de teknik bütünlük kararıdır: B-080 sahibin kendi D-021 sözünün tutarlı uygulanmasıdır (büyüklük veride, systems-designer ayarı); B-052 oyuncuya görünen hiçbir kuralı değiştirmez, yalnız yükleme süresini kısaltır. systems-designer'a bilgi: PE-03 `trust_gap` ağırlığı artık yıkım kesintisini de taşır (en çok +36 pm baskı).

## Kanıt
- **Doğrulandı (kod okundu, `34eae42`):** `event_sources.gd:143-159`; `council_trust.gd:36-78`; `council_engine.gd:235-238`; `politics_query.gd:47-52`; `event_engine.gd:33-90` (baskı sert koşuldan önce duruma yazılır); `cadence.json` milestone M2 / `events.json` milestones; `pe-03.json` sürücüleri; `reactions.json` `council_trust` değerleri; `relations_init.json`; `actor_memory.gd:104,231` sınırlama; `golden_x_council_trust_test.gd:52-74`; `golden_expropriation_undo_test.gd:14-16`; `sim_building_projector.gd` (süpürme ve `_full_sync`); `economy_state.gd:122-143`; `sim_facade_impl.gd:184-204, 345-375, 479-489`; `sim_contract.gd:33-61`; kilitli sürüm testleri (grep); `parcel_view.gd` alanları; B-051 düzeltme yolu.
- **Varsayıldı:** GOLDEN_X'in B-080 ile değişeceği (baskı farkının tamsayı bölmesinden sağ çıkması); GOLDEN_A/B'nin iki karar sonrasında değişmeyeceği; hızlı yol maliyetinin tek haneli ms olacağı; `developed_by_sim` dışında projector'ın yükleme sonrası başka parsel okumasına ihtiyaç duymadığı (`_staged` takibi listedeki görünümlerden kurulur).
- **Test edilmedi:** hiçbir şey. Godot çalıştırılmadı (tam doğrulama kilidi başka oturumda), `tools/verify.sh` koşulmadı.
