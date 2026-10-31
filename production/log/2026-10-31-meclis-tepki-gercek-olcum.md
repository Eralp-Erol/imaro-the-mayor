# 2026-10-31 · Meclis yolu ve kamulaştırma tepkisi · GERÇEK Ismeral D2 ölçümü

Statü: **ÖLÇÜM RAPORU** (geçti/başarısız değil). Oyun/sim kodu, `data/` ve `design/foundation/` DEĞİŞMEDİ; yalnız iki ölçüm probu eklendi. Push/merge yok.
Soru kaynağı: `design/specs/playable-tuning-review-2026-10-31.md` satır 7 ve 10-11 (H1, H2), `production/log/2026-10-31-calisma-degerleri-incelemesi.md`.
Kurulum: gerçek Ismeral, dünya tohumu 1467, `data/game/playable_economy.json` + `data/game/playable_politics.json` (oynanabilir yapılandırma), T0 yerleşimi, gösterge bütçe, `SimBuildingProjector`; başsız, sim tick'i = 1 gün. Yol/bölge: D2 (yük 9316, kapasite 9317, oran 999 pm; hane 8686). Dal `worktree-agent-a33fa3a3c4d632a78`.

## 0. Öne alınan bulgular (sırayla önem)

1. **H1 doğrulanmadı: meclis büyük planı REDDETMEDİ.** 18 doğal oylamanın 18'i kabul (13'ü 3-2, 4'ü 4-1, 1'i 5-0). Ama kabul **yalnız 14 gün gecikme + ince marj** ile geliyor (bkz. §2, §2.1). Hipotez "ilk plan reddedilebilir"in yarısı doğru: ret ölçülmedi, ama her oylamada altyapı doluluğu her üyeden -99 puan siliyor ve en zayıf "evet" oyu eşiğin 3-59 puan üstünde.
2. **H2: oynanabilir oyunda kamulaştırmalı yol HİÇ çizilemiyor.** `playable_roads.gd` kamulaştırma köprüsünü takmıyor; binalı arsadan geçen yol "Yol mevcut arsaların içinden geçemez; kamulaştırma henüz yok." ile reddediliyor (§6). D-008 üçüncü adımı ("halk tepki versin") ve D-011 oyunda erişilemez.
3. **H2: köprü takılsa bile D2'de halk tepkisi YOK.** 127 gerçek D2 yolu örneğinde en büyük yerinden etme 72 hane (= bölge hanesinin 8,3 pm'i); gündem eşiği 20 pm (174 hane) ve kesimlerin D2 payı %7,0-7,9 < %10 eşik. 400 günde 0 gündem, 0 tepki, 0 yakınlık sinyali kesimlere ulaşıyor (§5.2-5.4). Kök neden iki bağımsız yerde (§7).
4. Yol geri alınca da hiçbir şey olmuyor (zaten tepki yok); yalnız "Yıkımlı yol geri alındı ... Halkın tepkisi geri gelmedi." bildirimi düşüyor (§5.6).

## 1. Ölçüm araçları (yeni; mevcut `t043b_real_world_probe.gd` / `infra_politics_probe.gd` / `t042b_real_expropriation_probe.gd` kurulumuyla aynı)

| Probe | Ne yapar |
|---|---|
| `tests/sim/perf/council_real_probe.gd` | Yol (rank 0 = 108 m, rank 1 = 248 m, `t043b ... --list` ile aynı adaylar) + imar planı; meclis oylaması, gün sayıları, üye gerekçe etkenleri, ilk inşaat/bina. Seçenekler: `--plan-n --sim-seed --days --warm --zone --retry --hostile` |
| `tests/sim/perf/expropriation_reaction_real_probe.gd` | D2'de 150 rastgele 60-250 m yol dokunuşu (sim önizlemesi), seçilen yol için gerçek `NetworkExpropriationPort` + T0 korunan küme ile 60/200/400 gün tepki ölçümü. Seçenekler: `--list --pick=q10/q50/q90/max --undo-at --no-port --no-road --pts --cf-*` |

Ham çıktılar (her sayının kaynağı): `production/log/2026-10-31-meclis-tepki-ham/<küme>__<ad>.jsonl` (49 dosya, tek JSON satırı; satır başı `COUNCIL_REAL ` / `EXPROP_REAL ` / `EXPROP_LIST `). Not: `h1__*` koşuları probun ilk sürümüyle alındı (`zone`, `forecast_at_open`, `politics_events` alanları yok; sayılar aynı). Duvar saati bilinçle yazılmadı.

## 2. H1 · yol + plan, meclis eşiği açık (tohum 1467 sim; ayrıca sim tohumları 2-5)

Gün = plan komutunun gönderildiği tick'ten (tick 31; yol tick 30'da gönderildi ve aynı tick'te yapıldı) itibaren. `uygulama` = `event.zoning.applied`. 4 gün/sn ile saniye: gün/4.

| Senaryo (yol, plan) | Plan birimi | Yol | Oylama (kabul/ret, oy) | Oylama sonucu günü | Uygulama günü | İlk inşaat | İlk bina | Bina sayısı ~400 gün | Kaynak (`h1__...`) |
|---|---|---|---|---|---|---|---|---|---|
| a) 108 m, 12 parsel | 51 | meclis | **kabul** (3-2 ×4 tohum, 4-1 ×1) | 11 | 17 | 29 (7,3 sn) | 83 (20,8 sn) | 3 başladı / 3 bitti | `r0_n12_s{1467,2,3,4,5}` |
| b) 108 m, 9 parsel | **36** | doğrudan | - | - | 3 | 15 (3,8 sn) | 72 (18,0 sn) | 2 / 2 | `r0_n9_s{...}` |
| c) 248 m, 12 parsel | 43 | meclis (parsel >= 10) | **kabul** (3-2 ×4, 4-1 ×1) | 11 | 17 | 29 | 83 | 7 / 7 | `r1_n12_s{...}` |
| d) 248 m, 9 parsel | 32 | doğrudan | - | - | 3 | 15 | 69 (17,3 sn) | 7 / 7 | `r1_n9_s{...}` |

- Tüm 5 sim tohumunda aynı günler ve sayılar (tablo hücreleri tohumlar arası eşit; yalnız oy dağılımı 3-2 / 4-1 değişiyor).
- "Uygulamadan sonra" bakınca: a) 12 / 66 gün (ilk inşaat / ilk bina) = önceki `T-043B` ölçümüyle (12 / 66) **aynı**; meclisin eklediği tek şey uygulamadan ÖNCEKİ 14 gün (3 -> 17). b) 12 / 69, d) 12 / 66.
- **9 parsel = 39 birim ÇIKMADI**: yola en yakın 9 boş parsel 36 birim (108 m) ve 32 birim (248 m). 10. parsel eklenirse parsel eşiği (>= 10) meclise götürür. Tutarlı: ikisi de eşiğin altında, doğrudan.
- 12 parsel + 248 m planı 43 birim; yani meclise **parsel sayısından** gidiyor, birimden değil. (Ticaret 12 parsel = 33 birim de meclise gitti: `h1b__zone_commercial`.)
- D-010 hedefi (<= 40 gün ilk inşaat, <= 100 gün ilk bina): dört senaryonun hepsinde karşılandı (29/83 en kötüsü).
- Meclis bekleme süresi tek sabit değil: oturum 14 günün katı. Teklif gününe göre oylama sonucu: 3, 5, 7, 9, 11, 15 gün (ölçülen: teklif tick'i 39, 79, 63, 47, 31, 55 -> `h1b__warm_*`); koddan aralık 3-16 gün. Uygulama = oylama + 6 gün (apply 3 + sürtünme 3). Yani meclis yolunda uygulama 9-22. gün, doğrudan yolda 3. gün.

### 2.1 Oy neden 3-2? (SIM-12 gerekçe kayıtları, `h1__r0_n12_s1467.votes_at_resolve`)

Beş üyenin etken tablosu (puan / eşik 0): üye1 -12 (hayır), üye2 -95 (hayır), üye3 +159, üye4 +19, üye5 +58 (evet). Her üyede `budget_realism` = **-990** (ağırlık 100 -> katkı **-99**). Gerçek D2 oranı 998 pm iken `realism_of` uç değere düşüyor: `(998-600)*1000/400 = 995 -> 1000-2*995 = -990`.
- Bu terim olmasaydı üye1 +87, üye2 +4 olurdu (5-0). Yani "meclis altyapı yükünü okuyor ve en kötü uca düşüyor" hipotezi **doğru**; ama diğer etkenler (stance_distance +30..+204, bloc_pressure) onu aştığı için plan geçiyor.
- Marj ince: 3-2 oylarda en zayıf "evet" üyenin puanı 19-59 (13 oylamada); 4-1'de en zayıf iki "evet" 3+67 (warm 46), 9+21 (s3), 10+22 (s3, 248 m), 56+82 (ticaret); 5-0'da (konut) 9+91+99. Oylama gürültü etkeni ±37 gözlendi (`reason.factor.noise`). Ret için tek bir üyenin ~20-60 puan kayması yeter (3-2 -> 2-3, eşitlik = ret ama 5 üye ve çekimser bandı 0 olduğundan eşitlik hiç oluşmadı: tüm oylamalarda `abstain` 0).
- Arazi kullanımı: karma (zone.mixed) 3-2 / 4-1; konut 5-0 (`h1b__zone_residential`); ticaret 4-1 (`h1b__zone_commercial`). Karma en zayıf kullanım.
- Kanıtlanmayan: kabul olasılığı. 18 oylamada 0 ret; 3-2 oranı yüksek (13/18). Farklı tohum/teklif günü/arazi kullanımı çeşitlendirildi, bölge hep D2 ve yük hep 997-998 pm olduğundan "farklı doluluk" ölçülmedi.

### 2.2 Meclis yolunda başka ne düşüyor?

`h1d__r0_n12_pol` (400 gün): oylama sonuçlanınca (gün 11) `event.media.published` (konu `housing_cost`) + PE-04 "Medya gündemi için yanıt bekleniyor" gündemi (gün 11 açıldı, 71'de süresi doldu); PE-02 "Yatırımcı çekincesi" gün 74 ve gün 277 (iki öğe, açık). Doğrudan yol (`h1d__r0_n9_pol`): 400 günde **sıfır** siyasi olay. Yani meclis yolu gündem üretiyor, doğrudan yol sessiz. Günlük gürültü: 400 günde 3 gündem öğesi (1/133 gün), bildirim şeridine uygun olaylar gün 0 (`vote_opened`), gün 11 (`vote_passed`), gün 17 (12 x `zoning.applied`) (`notification_strip`).

## 3. H1 · reddedilirse ne olur (ZORLANMIŞ ret; doğal değil)

Doğal ret hiç olmadığı için mekanik, `--hostile` ile ölçüldü: 5 üyenin "büyüme/koruma" duruşu +1000 yapıldı (`tests/sim/politics/plan_council_test.gd::_stance` ile aynı yöntem). Bu **gerçek veri davranışı değil**, yalnız ret yolunun gerçek D2'deki mekaniği (`h1c__hostile_*`).

| Adım | Ölçüm |
|---|---|
| Oylama | açıldı gün 0, sonuç gün 11 (tick 42): 0 evet / 5 hayır, `vote_failed`; 12 parselde `plan_rejected` durumu (`rejected_tick` 42), `approvals` 0, bina 0 |
| Oyuncuya düşen olaylar (şerit, öncelik 2 = oyuncu) | gün 0 `event.council.vote_opened`; gün 11 `event.zoning.plan_rejected` + `event.council.vote_failed` |
| Metinler (`data/ui/strings.tr.json`) | `event.council.vote_failed` "Meclis oylaması reddedildi: {yes} evet, {no} hayır" (:557); `event.zoning.plan_rejected` "İmar planı teklifi reddedildi; parsel plansız kaldı, yeniden teklif verilebilir" (:727); parsel durumu `plan.state.rejected` "Teklif reddedildi (gün 42); yeniden teklif verilebilir" (:732); `zoning.status.vote_failed` "Meclis öneriyi kabul etmedi" (:463) |
| Neden metni | **YOK.** Sayı (evet/hayır) var; "altyapı dolu" gibi neden yok. Snapshot'ta oylamada 5 gerekçe kaydı var (`snapshot_votes_end.reasons` 5) ama etken adlarından yalnız `trust_in_player` için Türkçe metin var (`reason.factor.trust_in_player` :827); `budget_realism, stance_distance, bloc_pressure, lobby_pressure, resentment, obligation` için anahtar yok (grep: 0 sonuç) -> `reason_panel.gd:548` `UiText.t` ham anahtarı döndürür (kod okuması; UI'da gözlenmedi). `proposal.route` oy görünümüne taşınmıyor (`council_vote_view.gd` alanı yok). Oylama önünde tahmin (`x.sim.council.forecast.*`, ör. 3 evet / 2 hayır / 1 belirsiz) snapshot'ta var ama `src/` içinde UI tüketicisi yok (grep) |
| Gönderim öncesi yön bilgisi | `zoning_flow_model.gd:172-` `route_text()`: "Neden meclise gidiyor: plan büyük (12 parsel, eşik 10 ...). Küçük planlar doğrudan işlenir." (:447); ret nedeni değil, yönlendirme nedeni (kod okuması) |
| Gündem/bildirim | ret için ayrı gündem öğesi yok; yalnız şerit satırı + parsel durumu |
| İkinci teklif mümkün mü? | **Evet**, hiçbir engel/bekleme yok: `validate` valid, `submit` queued, aynı gün (tick 42) |
| `--retry=same` (aynı 12 parsel, duruş hâlâ düşman) | 2. oylama gün 11'de açıldı, tick 56'da kapandı (14 gün oturum), yine 0-5, yine ret (`h1c__hostile_same`) |
| `--retry=small` (ilk 9 parsel, 36 birim) | `council_required` **false**; doğrudan: tick 45'te (retten 3 gün sonra) uygulandı, ilk inşaat gün 26 (tick 57), 100. günde 2 başladı; kalan 3 parsel `plan_rejected` kaldı (`h1c__hostile_small9`). **Büyük planı reddedilen oyuncu planı eşiğin altına bölerek meclisi atlayabiliyor.** |
| `--retry=same-calm` (duruşlar özgün değere döner) | 2. oylama 4-1 kabul (tick 56), uygulama tick 62, ilk inşaat tick 74 (gün 43 ilk tekliften), 100. günde 3 bina başladı (`h1c__hostile_samecalm`) |

## 4. H2 · gerçek D2'de kamulaştırma kapsamı (köprü takılı, T0 miras/landmark/sivil 433 parsel korunan)

`h2__list` + `h2b__*`: 150 rastgele D2 yol dokunuşu (60-250 m, tohum akışı `h2_probe`); **127'si geçerli ve ≥ 1 parsel alıyor**. Sayılar sim önizlemesi (`validate_command` args), tick 30'da:

| Büyüklük | min | p25 | medyan | p75 | p90 | maks | ortalama |
|---|---|---|---|---|---|---|---|
| Alınan parsel | 1 | 6 | 9 | 12 | 14 | 18 | 9,0 |
| Yıkılan bina (yapılı parsel) | 0 | 1 | 3 | 6 | 8 | 12 | 3,6 |
| Yerinden edilen hane | 0 | 0 | **6** | 16 | 38 | **72** | 12,6 |
| Yakın ama alınmayan hane | 0 | 4 | 14 | 32 | 70 | 115 | 24,0 |
| Yol uzunluğu (m) | 60 | 117 | 160 | 198 | 225 | 249 | 156 |

- 24/127 yol yalnız boş arsa alıyor (yıkım 0); 39/127 yol hiç hane yerinden etmiyor; 15 yol bina yıkıyor ama hane 0 (ticaret binası).
- 87 hane (şikâyet kuralı alt sınırı 10 pm) ve üstü yerinden eden yol: **0/127**; 174 hane (gündem eşiği 20 pm) ve üstü: **0/127**. En büyük: 72 hane = 8,3 pm.
- D2 `latent_hh` 8686, `housed_hh` 6966, `res_built` 6966 (tick 30); q90 yolundan (38 hane) sonra `housed_hh` 6928 (-38), `res_built` 6928 (`h2b__q90` `d2_before/d2_after`); q50'de 6960 (-6).

## 5. H2 · 400 günlük tepki (köprü takılı)

Seçilen yollar (yerinden edilen haneye göre sıra, 127 içinden): q10 = 0 hane (9 parsel, 3 bina, yakın 8 hane); q50 = 6 hane (6 parsel, 3 bina, yakın 19, 168 m); q90 = 38 hane (9 parsel, 7 bina, yakın 30, 115 m); maks = 72 hane (11 parsel, 11 bina, yakın 72, 133 m). Her koşuda yol tick 30'da gönderildi, aynı tick'te yapıldı ve `event.road.expropriated` yayımlandı.

| Ölçüm (gün = yol gününden) | q10 | q50 (tohum 1467 ve 2) | q90 | maks | yol yok (taban) |
|---|---|---|---|---|---|
| **PE-01 gündem öğesi** (kaç günde / kaç hane) | yok | yok | yok | **yok** | yok |
| Herhangi bir gündem öğesi, 400 gün | 0 | 0 | 0 | 0 | 0 |
| `group.reacted` (tepki olayı), 400 gün | 0 | 0 | 0 | 0 | 0 |
| Kesim `displacement` sinyali (gün 1/7/14/60/400) | 0 | 0 | 0 | 0 | 0 |
| Kesim `proximity` sinyali (aynı günler) | 0 | 0 | 0 | 0 | 0 |
| Bildirim şeridi uygun olay / gün | 3 yol gününde (command.applied, road.built, road.expropriated), sonra 0 | aynı | aynı | aynı | 0 |
| Günlük en çok gündem öğesi | 0 | 0 | 0 | 0 | 0 |
Kaynak: `h2__q10, q50, q50_s2, q90, baseline_noroad`, `h2b__q90, max` (`events.agenda_per_template`, `events.group_reacted_n`, `samples[].blocs.*.displacement/proximity`, `events.strip_*`).

### 5.1 Yakınlık tepkisi (yakında yaşayanlar)
Yakın ama alınmayan hane (q50: 19, maks: 72) sim'de sayılıyor (olay `nearby_households`), bölge düzeyi `proximity` sinyali gün 1'de 1 pm (maks yol) -> kesimlere ulaşmıyor (0). Ulaşsa bile `proximity` kuralı `lo` 5 pm; 1 pm altında. Yani yakınlık tepkisi **var ama D2'de ölçülebilir değil**.

### 5.2 Kesimler D2'yi görmüyor
`blocs.json:6` `blend: peak, min_share_pm 100`; `bloc_signals.gd:74-77` yalnız pay >= %10 olan bölgelerin tepe sinyalini alır. Ölçülen D2 payı: kesim 1 (barınan) 70 pm (%7,0), kesim 2 (arayan) 76-79 pm. D1 ve D6 payları 300-415 pm. Bu nedenle D2'de yıkım ne kadar büyük olursa olsun kesim sinyali 0 (kanıt: `h2b__max.samples[].blocs.*.displacement` hep 0 iken `region_signal_pm_D2` 8 pm).

### 5.3 Bölge sinyali bile eşiğin altında
Bölge `displacement` en büyük yolda 8 pm (gün 1) -> gün 400'de 0 (360 gün doğrusal sönüm). `reactions.json:10` gündem eşiği `min_displacement_pm` 20, `full` 100; gündem `reaction_agenda.gd:27-28` `level >= min` ister. 20 pm = 174 hane (hane 8686).

### 5.4 Sessiz mi, gürültülü mü?
**Sessiz.** 400 günde yol sonrası: 0 gündem, 0 tepki, 0 kesim hareketi; taban (yol yok) ile aynı sayılar. (Kesim 2'nin `G` değeri 53 -> 421 yükseliyor ama yol varlığından bağımsız: `h2__baseline_noroad` aynı; sebep talep, `reaction` hep `neutral`.)

### 5.5 Sayaç-olgusal deneyler (GÖNDERİLEN veri DEĞİL; `--cf-min-share`, `--cf-agenda-min`; kararı sahibe/design'a bırakır)
`cf__*`: yalnız eşikleri düşürünce ne görünürdü, gürültü ölçüsü için.
| Deney | Sonuç (maks yol 72 hane, 400 gün) |
|---|---|
| kesim pay eşiği 50 pm (D2 görünür) | kesim sinyali 8 pm olur (gün 7); gündem hâlâ yok (eşik 20 pm); tepki 0 (`cf__max_share50`) |
| + gündem eşiği 5 pm | **PE-01 gün 5'te** açılır; sonra 40, 75, 110. günlerde yeniden açılır (öğe ~30 gün açık kalıp `lapsed`); PE-04 (medya) gün 12 ve 89; 400 günde 6 öğe (4 PE-01 + 2 PE-04), aynı anda en çok 2 açık; şerit olayı 19, günlük en çok 3 (`cf__max_share50_agenda5`). Hâlâ `group.reacted` 0 |
| q90 (38 hane) + eşik 3 pm | PE-01 gün 5, 40, 75; PE-04 gün 12 (`cf__q90_share50_agenda3`) |
Not: gündem öğesi `args {stage 0, topic ""}`; başlık `event.pe01.reason` "Mahalle tepkisi için yanıt bekleniyor" (`strings.tr.json:308`).

### 5.6 Yolu geri alınca
`h2__q50_undo60` (gün 60'ta `public_work.undo_last`): gün 60'ta `event.road.restored` ("Yıkımlı yol geri alındı: 3 bina geri geldi. Halkın tepkisi geri gelmedi." `strings.tr.json:797`) + `event.road.removed`; `works_end` 0; `res_built/housed_hh` 6966'ya döner (`d2_after`). Gerçek veriyle tepki zaten yok -> geri almanın siyasi etkisi ölçülemedi. Deneyle (`cf__max_share50_agenda5_undo60`): gündem öğeleri geri alma sonrası da açılmaya devam ediyor (gün 75, 110: tepki defteri geri alınmıyor, tasarıma uygun) ve sinyal yolun yokluğundan bağımsız 360 günde sönüyor.

## 6. Oynanabilir oyun şu an ne yapıyor? (`--no-port`, `h2b__q50_noport`)
Aynı yol (q50, 168 m) kamulaştırma köprüsüz oyun kurulumuyla: `validate` ve `submit` -> `rejected` `public_work.reject.crosses_parcels`, args yalnız `at_x_cm, at_z_cm, length_m, max_m, min_m` (`taken_*` yok); yol yapılmadı (`works_end` 0). Oyuncuya "Yol mevcut arsaların içinden geçemez; kamulaştırma henüz yok." (`strings.tr.json:660`). Kök neden: `src/game/playable_roads.gd:37-43` `attach_commands()` `ctx.set_expropriation(...)` ve `set_protected(...)` çağırmıyor (API `src/sim/public_works/public_works_context.gd:71,78`; `T-042b-dunya-adimi` günlüğü "Oyun katmanına kalan iş 1" bunu açıkça bırakmıştı). Yani §5 sonuçları "köprü bağlanırsa" senaryosudur; bugünkü oyun yapılı arsadan yol çizmeyi reddediyor.

## 7. Kök nedenler (dosya:satır)

| Konu | Yer |
|---|---|
| Meclise gitme kuralı: parsel >= 10 YA DA birim >= 40 | `src/sim/politics/politics_gate.gd:40-49`; veri `data/game/playable_politics.json:7-8` |
| Oturum kapanışı = (açılış + 3'ten sonraki) 14'ün katı | `src/sim/politics/council_engine.gd:114-118`; veri `data/politics/council.json` `session_days 14`, `min_lead_days 3` |
| Yürürlük = oylama + apply 3 + sürtünme 3 | `src/sim/politics/council_engine.gd:179-187`; `data/sim/facade_config.json:11`; `council.json` `friction_days 3` |
| Uygulanabilirlik (altyapı yükü -> -990), ağırlık 100 | `src/sim/politics/council_engine.gd:288-304` (`realism_of`), `data/politics/council.json:15` (`lo 600, hi 1000`), `data/actors/decision_tables.json:13`; yük ~999 pm kaynağı `data/game/playable_economy.json:5` (`infra_free_units_max 0`) |
| Eşitlik = ret (pratikte oluşmuyor: 5 üye, çekimser 0) | `src/sim/politics/council_engine.gd:163`; `council.json` `tie_result fail`, `abstain_band 0` |
| Kamulaştırma köprüsü oyunda bağlı değil | `src/game/playable_roads.gd:37-43` |
| D2 kesim payı < %10 -> bölge sinyali kesime ulaşmıyor | `data/politics/blocs.json:6`, `src/sim/politics/bloc_signals.gd:74-77` |
| Gündem eşiği 20 pm (D2'de 174 hane) | `data/politics/reactions.json:10`, `src/sim/politics/reaction_agenda.gd:27-28` |
| Oylama gerekçe etken adları UI'da metinsiz | `data/ui/strings.tr.json` (yalnız :827), `src/ui/panels/reason_panel.gd:548` |

## 8. Seçenekler (öneri değil; kısa)

- Meclis (H1): (a) olduğu gibi, ilk plan 14 gün gecikir ama geçer (ölçülen); (b) eşiği yükselt (10 parsel/40 birim -> 12 parselin doğrudan gitmesi için >= 13 parsel / >= 52 birim); (c) uygulanabilirlikte "bölge dolu ama sığıyor"u nötr say (kod değişikliği); (d) ret görünür kalsın istenirse neden metni + tahmin UI'a taşınır. Karar sahibe (tuning-review Kart 1).
- Tepki (H2): önce köprü bağlanmalı (godot-engineer, `playable_roads.gd`); sonra "D2'de halk tepkisi olsun mu?" sorusu: kesim pay eşiği (`min_share_pm`), gündem eşiği (`min_displacement_pm`) veya yerinden etme normalleştirmesi (hane / bölge hanesi) - üçü bağımsız kaldıraç; deney §5.5.

## 9. Doğrulanmış / varsayılan / test edilmemiş

**Doğrulanmış (çalıştırıldı, ham çıktı repoda):**
- §2 tablo (20 koşu: 4 senaryo x 5 sim tohumu x 400 gün), §2.1 etken tabloları (18 doğal oylama), teklif günü duyarlılığı (6 koşu), arazi kullanımı (konut, ticaret; sanayi sim tarafından `invalid_value` ile reddedildi, UI listesinde var - kenar gözlemi).
- §3 ret mekaniği (4 koşu, ZORLANMIŞ duruş; yalnız mekanik).
- §4 dağılım (150 örnek, 127 geçerli), §5 tepki (q10, q50 x2 tohum, q90, maks, taban, geri alma = 8 koşu), §6 köprüsüz oyun (1 koşu), §5.5 deneyler (4 koşu).
- Her iki prob gdlint (gdtoolkit 4.5.0) temiz (`max-line-length` dosya başında kapatıldı). `tools/verify.sh` ÇALIŞTIRILMADI (görev yalnız ölçüm: sim/oyun kodu değişmedi; prob dosyaları testlere girmiyor).

**Varsayılan:**
- Tohum çeşitliliği: dünya tohumu tek (1467). Sim tohumu 2-5 kabul/ret dağılımını pek değiştirmiyor (oy 3-2/4-1); farklı dünya, D1/D6, başka bölge doluluğu denenmedi.
- §2'de "9 parsel = 39 birim" yerine ölçülen 36 / 32 birim kullanıldı (yola en yakın 9 boş parsel); 39 birimlik bileşim ayrıca seçilmedi.
- `proximity` ve `displacement` bölge sinyali değerleri `BlocSignals.reaction_pm` ile probda yeniden hesaplandı (D2 hane sayısı örnek anındaki); kesim düzeyi değerler doğrudan durumdan.
- UI metinleri ve `route_text()` / neden eksikliği kod ve veri okumasından; oyun UI'sında gözlenmedi.
- Köprü takılı koşular, `playable.gd`'nin gelecekte kuracağı kurulumun (köprü + T0 bayraklı korunan küme) probdaki karşılığıdır; gerçek oyun yolu henüz yok.

**Test edilmemiş:**
- İnsan his testi; gerçek viewport / ekran görüntüsü; gerçek oyun yolunda yıkımlı yol (bağ yok).
- Doğal meclis reddi (hiç oluşmadı; ret yalnız zorlanmış duruşla görüldü).
- Meclis oy tahmininin (`forecast`) UI'sı; `reason_panel`'in çok oylu ham anahtar görünümü.
- Başka bölgeler (D1, D6) ve başka tohumlu dünya; çok yollu zincir; yol maliyeti (kurulu değil).
- Duvar saati/performans (bu işin kapsamı değil).

## 10. Komutlar (yeniden üretim)

```
IMARO_GODOT=<Godot> tools/godot.sh --headless --path . --script res://tests/sim/perf/council_real_probe.gd -- --rank=0 --plan-n=12 --days=400 [--sim-seed=N --warm=N --zone=zone.residential --hostile --retry=same|small|same-calm]
IMARO_GODOT=<Godot> tools/godot.sh --headless --path . --script res://tests/sim/perf/expropriation_reaction_real_probe.gd -- --list
IMARO_GODOT=<Godot> tools/godot.sh --headless --path . --script res://tests/sim/perf/expropriation_reaction_real_probe.gd -- --pick=q50 --days=400 [--undo-at=60 --no-port --pts=x1,z1,x2,z2 --no-road --cf-min-share=50 --cf-agenda-min=5]
```
Kurulum: `git merge --ff-only agent/handover-imaro-m01-349562fb`; ana checkout'tan `.godot` kopyalanıp `tools/godot.sh --headless --import` (30 sn) çalıştırıldı.
