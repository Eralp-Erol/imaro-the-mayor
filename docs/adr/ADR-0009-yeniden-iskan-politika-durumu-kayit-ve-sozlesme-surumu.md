# ADR-0009 · Yeniden iskân politikası: durum yeri, kayıt, hash koruması, sözleşme sürümü (T-065 Aşama 1)

- Durum: **kabul (değişiklikle)** · Tarih: 2026-11-01 · Karar veren: technical-director. Yaratıcı etki yok: oyuncunun gördüğü davranış D-014, D-015, D-016 ve spec §3.0'dan gelir; bu ADR yalnız onu kaydetmenin teknik yolunu seçer.
- Kaynak öneri: `docs/adr/proposals/2026-11-01-yeniden-iskan-politika-durumu-ve-kayit.md` (taban `ccfe68c`). Bu ADR öneriyi aşağıdaki **3 değişiklikle** kabul eder; değişmeyen maddeler için öneri metni geçerlidir (§ numaraları oraya atıftır).
- Taban: `4997bbf` (`agent/handover-imaro-m01-349562fb`; T-042c geri al/yolu yık, B-007/B-008 ve D-014 §3 tepki işleri birleşmiş).
- Karşıladığı gereksinimler: TEK-01, TEK-02 (determinizm, kaydet/yükle/N tick eşitliği), SIM-07 (ev yoksa yok; sahte sayı yok), SIM-12 (neden kaydı), CAN-03 (bina yaratılmaz), CAN-10/SIM-10 (politika bir seçimdir).
- Yöntem: yalnız kod okundu. Godot çalıştırılmadı, test koşulmadı. "Doğrulandı" = kod okundu.

## Kısa karar (sahip için, 5 satır)

1. Politikanın açık/kapalı bilgisi kayıtta ayrı küçük bir bölümde tutulur; hiç dokunulmazsa kayda tek bayt yazılmaz, bugünkü oyun bit-bit aynı kalır.
2. Kayıt sürümü artmaz; eski kayıtlar olduğu gibi açılır ve "politika kapalı" davranır.
3. Tepki defteri gerçek hane sayısını tutmaya devam eder; ev bulunan ailelerin azalan tepkisi okurken tek bir noktada hesaplanır (sahte sayı riski yok).
4. Sözleşme: yolu yıkma şimdi 1.6 olarak kayda geçer; yeniden iskân politikası 1.7 olur. Tek seferde birleştirmiyoruz.
5. Aşama 1 başlayabilir; yalnız kamulaştırma + geri al senaryosunun kilit hash'i (GOLDEN_X) T-065 kodundan önce, ayrı commit'te sabitlenmeli.

## Bağlam

Önerinin §1 kod gerçeği hâlâ geçerli (satır numaraları kaymış olabilir). Öneri yazıldıktan sonra birleşen üç iş kararı etkiliyor:

1. **Geri al artık "hiç yapılmamış gibi"** (T-042c, D-014 §1 uygulama notu): `public_work.undo_last` yolun tepki satırlarını SİLER (`src/sim/public_works/public_work_undo_handler.gd:83-86` -> `ReactionAgenda.retract_command`, `src/sim/politics/reaction_agenda.gd:271-285`) ve yalnız pencere açıkken çalışır: başka yol/yıkım yapılana ya da yolun tepkisi haftalık taramaya girene kadar (`src/sim/public_works/undo_window.gd:33-56`). Önerinin ve spec'in "geri almada tepki defteri kalır (D-011)" varsayımı bu kodla artık uyuşmuyor.
2. **Yolu yık birleşti ve `works[]`'tan satır silmiyor**: yıkım ayrı satır olarak eklenir, hedef yol `demolished_by` ile işaretlenir (`src/sim/public_works/public_works_state.gd:201-216`); bütçe yıkım satırlarını önek eşitlemesinden çıkarır ve yıkım giderini bir kez yazar, yapım giderini iade etmez (`src/sim/budget/budget_system.gd:139-158`, `:194-202`). Önerinin P2 kısıtı karşılandı.
3. **İkinci bir "yeniden yerleşti mi" kancası doğdu**: `ReactionRehousing.still_unhoused` (`src/sim/politics/reaction_rehousing.gd:17`), şimdilik kimlik (hep "hâlâ barınamıyor"); yalnız mahalle okumasından çağrılıyor (`reaction_agenda.gd:147`). Öneri ise rahatlamayı tepki defterine yazarken (`note_reactions`) uygulamayı öneriyordu. İkisi birden uygulanırsa rahatlama **iki kez** düşülür. Biri seçilmeli.

Ayrıca: tepki defterinin okuyucuları üç tanedir (doğrulandı, `grep reaction_rows`): bölge sinyali `src/sim/politics/bloc_engine.gd:83-84`, mahalle okuması `reaction_agenda.gd:129`, neden kaydının hane sayısı `src/sim/politics/reaction_cause.gd:104-120`. Neden kaydındaki `reason.factor.displaced_household_count` "penceredeki gerçek hane sayısı" olarak tanımlı (`reaction_cause.gd:6`, `:48`, `:76`).

## Karar

### Önerinin olduğu gibi kabul edilen maddeleri

- **A · Durum yeri** (öneri §2): `state.systems["policy"]`, `PolicyState`; `{version: 1, resettlement: {enabled, changed_tick, command_id}}`. Yalnız ilk KABUL EDİLEN `policy.set` yaratır; okuma/önizleme/doğrulama/ret yaratmaz. Yokluk = kapalı (sabit kural; veride varsayılan yok). PoliticsState ve `public_works` bölümü reddedildi (gerekçe öneri §2 tablosu).
- **B · Tahsis kaydı** (öneri §3): ayrı tahsis tablosu yok; alt kayıt `works[i].expropriation.resettlement = {moves, rehoused, unplaced, cost, residual_pm, effective}` yalnız politika açık VE yerinden edilen > 0 iken yazılır. `ResettlementPlanner` saf; önizleme ve uygulama aynı planı kullanır. `leave_region` kaderinde `latent_removed` yalnız bulunamayan kadardır.
- **C · Kayıt** (öneri §4): `SimSave.VERSION` **2 kalır**, `MIN_SUPPORTED_VERSION` 2, taşıma kodu yok. `GameState.validate_dict` zincirine `PolicyState.validate_data` (`src/sim/core/game_state.gd:168-173` arasına, aynı kalıp). Alt kayıt değişmezleri `PublicWorksState._expropriation_problem`'de. İleri uyum (yeni kayıt eski derlemede) desteklenmez; ilk dağıtılan derlemede yeniden açılır.
- **D · Hash** (öneri §5): politika hiç değiştirilmemiş koşuda yazılan yeni bayt sıfır. Hash'e giriş yalnız ilk `policy.set` ve politika açıkken yerinden etme olan yol.
- **Önbellek anahtarı** (öneri §3, zorunlu): `ExpropriationFlow.problem` memo anahtarına (`src/sim/public_works/expropriation_flow.gd:35-36`) politika bayrağı eklenir (`|0`/`|1`). Anahtar `PublicWorksContext` üzerindedir, duruma ve kayda girmez: biçimini değiştirmek hash'i etkilemez. Aynı tick'te `policy.set` + önizleme bayat plan döndürmez (test öneri §11 madde 4).
- **Bütçe** (öneri §4): `charged[i].resettlement` (isteğe bağlı, > 0 iken) + tembel `resettlement_net`; değişmez `balance = initial + revenue_total - roads_net - resettlement_net` (alan yoksa 0, eski formül). Defter türleri `resettlement`, `resettlement_refund`. Ayrı alan seçildi, yıkımdaki gibi `amount`'a katılmadı: bütçe görünümünde "Yol" kalemi yeniden iskân bedelini içerirse oyuncuya yanlış kalem gösterilir (SIM-07). Görünümde `budget.line.resettlement` satırı yalnız alan varken eklenir.

### Değişiklik 1 · Tepki rahatlaması defter yazımında DEĞİL, okumada, tek fonksiyonda (öneri §3 ve §6 "yıkım tepkisi" maddesi yerine)

- Tepki defteri (`displaced`) **ham** yerinden edilen haneyi tutar; `note_reactions` çağrısı (`expropriation_flow.gd:135-136`) değişmez. Önerinin "`note_reactions`'a `effective` ver" maddesi **reddedildi**.
- Rahatlama tek noktadadır: `ReactionRehousing`. `still_unhoused` durum alır ve iş kaydındaki `resettlement.effective[kod]`'u döndürür (alt kayıt yoksa gelen sayıyı aynen). Tarama başına bir kez kurulan `{komut_kimliği: {kod: etkin}}` dizini kullanılır (O(iş) bir kez); dizin boşsa hiçbir şey kopyalanmaz.
- Üç okuyucudan YALNIZ tepki şiddeti hesaplayan ikisi bu noktadan geçer: mahalle okuması (zaten geçiyor, `reaction_agenda.gd:147`) ve bölge sinyali (`bloc_engine.gd:83`: `displaced` satırları `ReactionRehousing` üzerinden). Neden kaydının hane SAYISI ham kalır (`reaction_cause.gd:104-120`); mahalle neden kaydındaki sayı `reading["households"]` yerine `reading["displaced_total"]` olur (politika kapalıyken ikisi eşit, `reaction_agenda.gd:147-152`; hash değişmez). Rahatlama ayrıca `reason.factor.rehoused_households` / `unplaced_households` etkenleriyle görünür.
- Neden: (a) defter gerçek kalır; "12 aile yerinden edildi" yerine etkin ağırlık "3" yazılması SIM-07 ihlali olurdu; (b) rahatlama iki yerde uygulanmaz; (c) geri al penceresi politikadan bağımsız kalır (ham satır her zaman var, pencere ilk taramada kapanır; yazımda rahatlatsaydık "hepsine ev bulundu ve kalan tepki 0" durumunda satır yazılmaz, pencere aylarca açık kalırdı); (d) yıkılan yolda alt kayıt iş satırında durduğu için rahatlama sürer, geri alınan yolda satırlar zaten silinir.
- Bedel: `bloc_engine.gd` T-065 dosya alanına eklenir (tek çağrı). Politika kapalıyken iki yol da aynı diziyi/aynı sayıyı geçirir: bit-bit eşitlik korunur (test: GOLDEN_A/B + GOLDEN_X).
- Kural: `ReactionRehousing` dışında hiçbir kod politika durumuna bakarak tepkiyi azaltmaz. Aşama 2 (hane sınıfı) da buraya takılır.

### Değişiklik 2 · Geri al: tahsis geri sarılır VE tepki satırları silinir (öneri §6 "tepki defteri kalır" yerine)

- Kod bugün geri almada tepki satırlarını siliyor (Bağlam 1). T-065 bununla tutarlı olmalı: `ExpropriationFlow.revert` (`expropriation_flow.gd:148-165`) `ParcelExpropriation.restore`'dan sonra `moves`'u ters sırada geri alır (`geri = min(hane, latent_hh[hedef])`, kırpma öneri §6'daki gerekçeyle kalır: pencere bir ay sınırını kapsayabilir ve siyaset kurulu değilse pencere taramayla hiç kapanmaz), `public_work.restored` args'ına `rehoused_returned` yazar; bütçe iadesi `resettlement_refund`. Tepki satırları mevcut kancayla (`retract_command`) silinir; T-065 buna ek bir şey yapmaz.
- T-065 ölçüt 5 ve spec §7 E-1 metni ("tepki defteri kalır") koda göre düzeltilmeli. Bu yaratıcı bir seçim değildir (geri alma davranışını T-042c zaten belirledi), ama D-014 §1'de "geri almada tepki ne olur" sahibe sorulmamıştı; değişirse yalnız `retract_command` çağrısı değişir, T-065 tasarımı değişmez.
- Yolu yık tahsisi geri almaz, bedeli iade etmez (öneri §6 kısıt 1). Kod buna uygun: yıkım `works[]`'tan satır silmez, bütçe yıkılmış yolu iade saymaz (P2 karşılandı).

### Değişiklik 3 · Sözleşme: yolu yık = 1.6 (şimdi), yeniden iskân = 1.7 (T-065 teslimi)

- **1.6 gerekli.** T-042c sözleşmeye yeni komut türü (`public_work.demolish`), yeni olay türü (`public_work.demolished`), iki yeni facade sorgusu (`undo_available()`, `demolish_cost()`), dört yeni ret anahtarı ve `undo_last` için daraltılmış anlam ekledi, ama `SimContract.VERSION` "1.5" kaldı (`src/contracts/sim_contract.gd:22-24`; kaynakta "v1.5 isteğe bağlı ek" notları: `sim_command.gd:20`, `:102`, `sim_facade.gd:117`, `:126`, `sim_event.gd:24`). Bu ADR-0005 §8 madde 2'ye (yeni komut/olay = MINOR) ve Ek F'nin kendi kapanış kuralına ("1.5 yayımlandıktan sonra gelecek benzer ek 1.6 olur") aykırı; 1.5'in tüketicisi var (`src/ui/flows/agenda_panel.gd`, `expropriation_text.gd`) ve yıkım/geri alma yüzeyinin de tüketicisi var (`src/game/road_draw_tool.gd:277`, `:283`, `:296`). Ayrıntı ve uygulama listesi: ADR-0005 Ek H.
- **Tek seferde birleştirme REDDEDİLDİ.** Teknik olarak yapılabilirdi (1.6'yı T-065 teslimine kadar beklet, ikisini birlikte yaz), ama: (a) yıkım zaten birleşti ve tüketiliyor; T-065 bitene dek (Aşama 1 "orta" boy) sözleşme yalan söyler; (b) ADR-0005 §8 madde 3 "değişiklik + test + mock aynı teslimde" der; politika yüzeyini uygulamadan önce kataloğa yazmak ölü komut demektir; (c) önerinin "paralel tren" kuralı 1.6'nın arada tüketicisi oluşursa sonrakinin 1.7 olmasını şart koşuyordu; tüketici oluştu. Maliyet farkı küçük: her sürüm artışı 5 kilitli test + 1 fixture satırıdır.
- `agenda.respond` ve `agenda_items()` 1.5 olarak kalır (o etiketle tüketildi; geçmiş yeniden yazılmaz). Bundan sonra "sürüm artmadan isteğe bağlı ek" yolu **kapalıdır**: yeni komut, olay, sorgu ya da ret anahtarı = yeni MINOR.
- `undo_last` anlamının daralması (pencere + tepki silme) MAJOR sayılmadı: komut biçimi, DTO alanları ve eski ret anahtarları aynı; yeni sonuç yalnız `public_work.reject.` ailesinde yeni bir anahtarla gelir ve bu aile zaten "küme büyüyebilir, önek sabit" diye tanımlı (`src/contracts/command_result.gd:25-28`); depo dışında tüketici yok. MAJOR, tüm 1.x fixture'larını `SimSnapshot.from_dict`/`MockScenario`'da reddettirirdi; güvenlik kazancı yok. Bu bir istisnadır, Ek H'de açıkça yazılı.
- **1.7 içeriği** (T-065 Aşama 1 teslimi, ADR-0005 Ek I olarak aynı teslimde): öneri §7'deki liste aynen (`policy.set {policy_id, enabled}` ve ret kodları, `SimFacade.policies() -> Array[PolicyView]` varsayılanlı, `public_work.road` önizleme ve `PublicWorkView` isteğe bağlı alanları, `policy.changed` olayı, `restored.rehoused_returned`) + `budget.line.resettlement` metin anahtarı.
- Sıra: 1.6 kodu (Ek H uygulaması) T-065'in sözleşme adımından önce birleşmeli. Birleşmediyse T-065 önce 1.6'yı ayrı commit'te yapar, sonra 1.7.

### GOLDEN_X sabitleme planı (P3)

- **Ne:** gerçek kod yolunu sabit hash'le kilitleyen yeni test `tests/sim/public_works/golden_expropriation_undo_test.gd`, sabit `GOLDEN_X` (64 hex).
- **Senaryo** (tek koşu, `tests/sim/politics/reaction_world_base.gd` dünyası + `facade.attach_budget(BudgetConfig.load_default())`, gerçek `data/` dosyaları; her komutun `accepted` olduğu ayrıca doğrulanır, yoksa hash anlamsızdır):
  1. Kamulaştırmalı yol A uygulanır; ilk haftalık taramadan ÖNCE `public_work.undo_last` (pencere açık; tahsis/tepki silme yolu).
  2. Aynı noktalara kamulaştırmalı yol A' tekrar; 3 haftalık tarama geçecek kadar ilerle (PE-01 öğesi, ilçe şikâyeti, bütçe).
  3. Düz yol B; sonra `public_work.demolish` B (yıkım yolu, bütçe yıkım gideri).
  4. Tick 60'a kadar ilerle; `state_hash()` == `GOLDEN_X`.
  5. Aynı tohumla ikinci koşu aynı hash'i verir; tick 30'da kaydet/yükle yapılan koşu da aynı hash'i verir (TEK-02).
- **Kim/ne zaman:** `simulation-engineer` yazar ve değeri koşudan alıp sabitler; **ayrı commit**, T-065 kodundan ÖNCE, birleşik taban üzerinde. `qa-engineer` bağımsız iki koşuyla teyit eder. Commit mesajına taban SHA'sı yazılır.
- **Kural:** T-065 Aşama 1 bu sabiti değiştirmeden geçmeli (kabul ölçütü 1'in asıl kanıtı). `data/politics/reactions.json`, `data/sim/public_works/road_works.json`, `data/sim/budget/budget_config.json` çalışma değeri değişirse GOLDEN_X bilinçli, gerekçeli ve ayrı commit'te yeniden üretilir (GOLDEN_A/B kuralıyla aynı). Politika açık davranışı ayrı sabit `GOLDEN_R` ile kilitlenir (öneri §5).
- Fixture seçimi gerekçesi: gerçek dünya köprüsünde kamulaştırmalı yolun yıkımı reddediliyor (`tests/sim/public_works/undo_demolish_real_world_test.gd:3-5`) ve siyaset kurulu değil; sahte dünya + siyaset + bütçe üç sistemi birlikte kapsayan tek mevcut taban.

## `independent` bayrağı hükmü (EventEngine, B-008)

**Hüküm: KABUL EDİLEBİLİR** (`src/sim/politics/event_engine.gd:207-230`). Gerekçe, kod okumasıyla:

1. **Determinizm:** bayrak veriden gelir (`reactions.json` `local.independent_items`, `reaction_agenda.gd:181`), duruma bakmaz; dal saf bir `if`'tir, rastgelelik, saat ya da sözlük sırası bağımlılığı yok. Aynı durum + aynı yapılandırma = aynı sonuç (TEK-01).
2. **`false` yolu değişmedi:** `8042ae6` farkında `false` dalı önceki gövdeyle bayt bayt aynı; yalnız `if independent: return true` eklendi ve `open_direct` parametreyi aktarıyor. Bölge yolu (`reaction_agenda.gd:64`, `:72`) bayrağı hiç geçirmez.
3. **GOLDEN_A/B etkilenmez:** iki senaryoda yol yok (`tests/sim/m2_support.gd`), `public_works` bölümü yaratılmaz, `ReactionAgenda.scan` ilk satırda döner (`reaction_agenda.gd:33-34`); `can_open_direct`/`open_direct`'in tek çağıranı `ReactionAgenda`dır (grep). Yani dal GOLDEN_A/B'de erişilemez. **Bu kod okumasıdır; test koşulmadı.**
4. **Durum özeti dışı kural verisi:** `reactions.json` bütünüyle `PoliticsConfig.digest` dışındadır (bilinçli tasarım, `src/sim/politics/politics_config.gd:418-420`, `reaction_config.gd:4`); `independent_items` bu kör noktaya bir alan daha ekler. Aynı derlemede kaydet/yükle eşitliğini (TEK-02) bozmaz; farklı veriyle yüklenen kayıt sessizce farklı ilerler. Kabul edilen risk; ilk dağıtılan derlemede (öneri §4 ileri uyum maddesiyle birlikte) yeniden açılır.
5. **Davranış notları (determinizm sorunu değil; systems-designer bilsin):** bağımsız açılan öğe `_is_armed`'ı atladığı için süresi geçmiş bekleme kaydını silmez, ama `_fire` yine `cooldown_until[PE-01]` yazar (`event_engine.gd:195`) ve açık öğe PE-01'in mutex gruplarını tutar: haftalık `EventEngine.scan`'deki aynı gruptaki şablonları sonraki haftalarda bastırabilir. `max_new_per_scan` doğrudan öğelere uygulanmaz; `ReactionAgenda.scan` zaten tarama başına en çok bir öğe açar (`:39-43`).
6. **Tasarım notu:** iki gate'i birden kapatan boolean parametre; iki çağrı noktasında kabul. Üçüncü tüketici gelirse adlandırılmış kapı kümesine (örn. `DirectGate`) çevrilir.
7. Bayrak açıkken kamulaştırmalı koşuların hash'i değişti (bilinçli, B-008). Kamulaştırma yolunda sabit hash olmadığı için bu değişikliğin "yalnız beklenen yerde" olduğu bugün kanıtlanamıyor; GOLDEN_X bu boşluğu kapatır.

## Alternatifler ve neden reddedildi

| Seçenek | Artı | Eksi |
|---|---|---|
| Rahatlamayı defter yazımında uygulamak (öneri §3) | Politika koduna dokunmaz; tüm okuyucular otomatik | Defterdeki "gerçek hane sayısı" etkin ağırlığa döner (SIM-07); `ReactionRehousing` ile çift düşüm riski; tümüyle rahatlayan yolda satır yazılmaz, geri al penceresi taramayla kapanmaz |
| Rahatlamayı hem yazımda hem `still_unhoused`'ta | - | Çift düşüm |
| 1.6'yı T-065 teslimine kadar bekletip tek sürüm | Bir sürüm artışı daha az | Yıkım haftalarca yanlış etiketle tüketilir; politika yüzeyini uygulamadan kataloğa yazmak ölü komut |
| `undo_last` daralması için 2.0 | Kurala harfiyen uyum | Tüm 1.x fixture'ları reddedilir; depo dışı tüketici yok, kazanç yok |
| Politika durumunu PoliticsState'te tutmak | Yeni bölüm yok | Öneri §2 tablosu (GOLDEN, siyasetsiz kurulum, sahiplik) |

## Sonuçlar ve riskler

- Kazanım: kapalı politikada yapısal olarak sıfır yeni bayt; kayıt taşıması yok; defter dürüst; rahatlama tek noktada.
- Maliyet: T-065 dosya alanı `src/sim/politics/bloc_engine.gd` (1 çağrı), `src/sim/core/game_state.gd` (1 satır), `src/sim/budget/`, `src/contracts/` + mock + `tests/contracts/`, `src/sim/facade/` ile genişler (T-065 güncellendi). Ayrıca 1.6 için küçük bir sözleşme işi (Ek H).
- Risk 1: GOLDEN_X sabitlenmeden T-065 kodlanırsa ölçüt 1 kanıtsız kalır. Azaltma: P3 ön koşul.
- Risk 2: birisi `ReactionRehousing` dışında politikaya bakıp tepkiyi azaltırsa çift düşüm. Azaltma: bu ADR kuralı + test "açık politika, tümü yerleşti: bölge sinyali = mahalle okuması = etkin değer, ham sayı neden kaydında".
- Risk 3: geri alma kırpması (öneri §8 risk 3) aynen geçerli.
- Yeniden açma tetikleyicileri: ilk dağıtılan derleme (ileri uyum, `reactions.json` özeti); Aşama 2 hane sınıfı sütunları; Aşama 3 meclis onayı (`policy` bölümüne `pending`); sahibin geri almada tepkinin silinmemesini istemesi.

## Kanıt

- Doğrulandı (kod okundu, `4997bbf`): Bağlam ve Karar'daki tüm dosya:satır atıfları; `independent` farkı (`git show 8042ae6`); yıkımın `works[]`'tan silmemesi ve bütçenin iade saymaması; tepki defterinin üç okuyucusu; `ReactionAgenda.scan`'in defter yokken erken dönmesi; GOLDEN_A/B senaryolarında yol olmaması; 1.5 etiketiyle eklenen yıkım yüzeyi ve tüketicileri; memo anahtarının duruma girmemesi.
- Varsayıldı: `bloc_engine.gd:83`'e eklenecek tek sarmalama dışında politikada başka değişiklik gerekmediği; `reaction_world_base` dünyasında aynı noktalara ikinci kamulaştırmalı yolun kabul edileceği (GOLDEN_X adım 2; reddedilirse senaryo farklı noktalarla kurulur, ilke değişmez); `systems` anahtarlarını dolaşıp bilinmeyen bölümde bozulan kod olmadığı (öneri §9).
- Test edilmedi: hiçbir şey. Godot çalıştırılmadı, `tools/verify.sh` koşulmadı. GOLDEN_A/B'nin değişmediği iddiası kod okumasıdır.
