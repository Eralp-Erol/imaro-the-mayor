# Ekonomi çekirdeği v0 (T-013) — ÇALIŞMA MODELİ

Statü: **çalışma modeli, kanon değil.** Tüm sayılar `data/sim/economy/economy_config.json` içindedir (F05-C, ayarlanabilir); bu belgedeki örnek değerler başlangıç ayarıdır, denge önerisi değildir. Ölçek, nüfus, üretim oranları, para birimi AÇIK (F05-D, Q-003): para **birimsiz tamsayı**, oranlar **1000 ölçekli tamsayı** (‰, `SimContract.FIXED_SCALE`). Yaratıcı karar yoktur: ad/sayı uydurulmaz, aktör adları yer tutucu anahtardır (`actor.investor.<n>.name`).

REQ: SIM-01 (hane/talep) · SIM-02 (yatırımcı kararı) · SIM-03 (parsel/yapı, kademeli) · SIM-07 (yatırım gelmeyebilir) · SIM-08 (etki zamana yayılır) · SIM-12 (gerekçe) · CAN-03 (özel bina yalnız aktör kararı) · CAN-05 (imar/yoğunluk/yükseklik koşul) · TEK-01/02 (saf, tohumlu, deterministik) · PLT-04 (platform bağımsız).

## 1. Döngü (F03: "gör → karar → tepki → şehir değişir")
```
oyuncu: zoning.propose (imar/yoğunluk/yükseklik)          [koşulu değiştirir; bina YARATMAZ]
   ↓ ParcelZoningSystem: N gün sonra yürürlük (T-027)
bölge talep kohortları (hane/iş)  +  altyapı kapasitesi  +  imar  +  maliyet  +  finansman
   ↓ yatırımcı DEĞERLENDİRİR (periyodik tarama + imar sonrası dikkat) → gerekçeli karar (record_reason)
olumlu → parsel `planned` → `under_construction` → `built` (gün sayısı veri)      [SIM-03/08]
olumsuz → parsel boş kalır; gerekçe: hangi etken engelledi                        [SIM-07/12]
   ↓ yeni arz talebi azaltır, kira/altyapı yükü/hane çekimi değişir → geri bildirim döngüsü
```
Belediye hiçbir yerde `development`/`owner_id` yazmaz. Bunları yalnız `EconomySystem` (yatırımcı kararı sonucu) yazar. `EconomySystem` olmayan facade'de parseller hiç gelişmez.

## 2. Durum (`state.systems["economy"]`; kayda ve hash'e girer)
Parsel sütunları (Packed*, indeks = `parcel_ids` sıralı konumu; parsel kimliği `ParcelSource`'tan):
| Sütun | Anlam |
|---|---|
| `stage` | 0 vacant · 1 planned · 2 under_construction · 3 built · 4 stalled (`ParcelView.development` ile bire bir) |
| `use` | 0 yok · 1 konut · 2 ticaret (başlatılan/biten proje türü) |
| `units` | proje/yapı birim sayısı (konutta hane kapasitesi, ticarette dükkân birimi) |
| `owner_id` | 0 = ilk arsa sahibi (T-011 `owner_id` yuvası) · k>0 = `actor.investor.k` |
| `land_value` | birimsiz tamsayı arsa değeri (spekülasyonla oynar, tavanı vardır) |
| `days_left` | geçerli aşamada kalan gün (durdurulmuşken azalmaz) |
| `reason_id` | parselin en son kayıtlı kararının gerekçe kimliği |
| `last_code`, `last_reason_tick`, `next_review` | gürültü azaltma: aynı olumsuz sonuç tekrar yazılmaz (§5); reddedilen parselin bekleme günü (§4). Durumda ayrıca `review_cursor` |
Seyrek sözlükler (yalnız dokunulan parseller): `zone_seen`, `attention` (parsel→inceleme günü), `attention_cmd`, `active` (planned/under_construction/stalled parseller).
Bölge sütunları (bölge kodu `ParcelSource`'tan okunur; koda gömülü bölge adı yoktur): `latent_hh`, `income_pm`, `access_pm`, `service_pm`, `infra_cap`, `res_built`, `res_pipe`, `com_built`, `com_pipe`, `growth_frac` (kesir birikimi, kesme yanlılığı olmasın).
Yatırımcı havuzu: `capital[]`, `threshold_shift[]`, `monthly_inflow[]` (aylık dış sermaye girdisi: kredi/diğer gelir; kira geliri ayrıca eklenir). `totals`: değerlendirme/onay/ret/tamamlanma sayaçları, arsa satışı, inşaat harcaması, kira geliri (T-014 vergi/bütçe bunları okuyabilir).
T0 mevcut stok: `ExistingStockSource` (parsel → kullanım, birim, sahip). Başlangıçta o parseller `built` doğar (karar kaydı yok: gelişme T0'ın parçasıdır, CAN-03'ü atlatan yol değildir; belediye komutu değil, **başlangıç durumudur**). Şimdilik boş/fixture; T-005 `BuildingColumns` bir adaptörle takılır.

## 3. Talep kohortları (SIM-01) — bölge başına, birleşik
Birim = 1 konut birimi = 1 hane kapasitesi.
- `housed = min(latent_hh, res_built)`.
- **Konut talebi**: `need = latent_hh`, `supply = res_built + res_pipe`. `shortage_pm = (need − supply)·1000 / max(need,1)`; `D_res = clamp(500 + shortage_pm·demand_gain_pm/1000, 0, 1000)`. 500 = denge.
- **Ticaret/iş talebi**: `need = housed · shops_per_household_pm/1000 · income_pm/1000` (desteklenen dükkân birimi), `supply = com_built + com_pipe`; aynı biçim.
- **Aylık hane akışı** (`on_monthly`): `jobs = com_built·jobs_per_commercial_unit`; `job_balance_pm = min(1000, jobs·1000 / max(housed·jobs_needed_per_household_pm/1000,1))`; `pull_pm = (access·w_a + service·w_s + job_balance·w_j)/(w_a+w_s+w_j)`; `growth_pm = growth_base_pm·(pull_pm − 500)/500` (işaretli: erişim/hizmet kötüyse hane **azalır**); `latent_hh += latent_hh·growth_pm/1000` (kesir `growth_frac`'ta biriktirilir). Gelir/erişim/hizmet v0'da bölge sabitidir (T-014/T-017 yazabilir); hane bireyselleşmez.
- Beklenen kira: `rent_mult_pm = rent_floor + D·(rent_cap − rent_floor)/1000`.
- **Spekülasyon (SIM-07 "aşırı talep")**: ayda bir, `D_res ≥ speculation_demand_pm` olan bölgenin boş yapılabilir parsellerinde `land_value += land_value·speculation_rate_pm/1000` (tavan `max_multiplier_pm`); `D_res ≤ relax_demand_pm` ise tabana doğru geri çekilir. Etki: arsa maliyeti getiriyi düşürür (kendini sınırlar); `speculation_index` bölge istatistiğidir. Ayrı "spekülatör aktör" yok (T-016/T-017).

## 4. Yatırımcı kararı (SIM-02) — doğrusal, gerekçeli
Yatırımcı havuzundan **tohumlu RNG** (`state.rng.stream(&"economy")`) bir yatırımcı seçilir; kararda ikinci çekim `market_sentiment` gürültüsüdür. Proje türü, imarın izin verdiği kullanımlardan **mevcut talebi yüksek olan** (eşitlikte listedeki ilk).
`units = max(1, area_m2·units_per_1000m2·density_pm/10^6 · kat_oranı)`; yoğunluk ve yükseklik `zoning.propose`'tan gelen yürürlükteki değerler (yoksa imarın varsayılanı); `kat_oranı = min(max_height_m/storey_m, reference_floors)/reference_floors`.
`outlay = units·cost_per_unit + land_value`.

| Etken (`reason.factor.*`) | Değer (1000 ölçekli, aralık) | Ağırlık | Not |
|---|---|---|---|
| `demand` | `clamp((D_after − 500)·2, −1000, 1000)`; `D_after` = proje arzı eklenmiş talep | 400 | aşırı yoğunluk burada düşer (arz > talep) |
| `expected_return` | `clamp((yıllık_kira·1000/outlay − interest_pm)·1000 / yield_full_scale_pm, ±1000)` | 300 | bugünkü kira çarpanı |
| `construction_cost` | `−min(1000, outlay·1000/project_scale_ref)` | 100 | tahmin (`is_estimate`) |
| `infrastructure_capacity` | kalan kapasite `‰` (üstten `infra_bonus_max`); proje sığmıyorsa **−1000** | 1000 | engel etkeni |
| `financing` | `(capital − outlay)·1000/outlay` (üstten `financing_bonus_max`); sermaye yetmiyorsa **−1000** | 1000 | engel etkeni |
| `zoning_fit` | izin veriliyorsa 0, imar yapılanmaya kapalıysa **−1000** | 1000 | engel etkeni |
| `market_sentiment` | `rand(−sentiment_range, +sentiment_range)` | 100 | tahmin; tohumlu |

`score = Σ (değer·ağırlık)/1000` (ReasonLog hesaplar); **olumlu ⇔ `score ≥ threshold`**, `threshold = base_threshold + yatırımcı.threshold_shift`. Engel etkenleri (−1000 × 1000) diğer tüm etkenlerin azami katkısını (≈ 990 − bu etken) aştığı için (testle korunur) **tek başına** olumsuz sonuç verir; böylece her karar tek bir doğrusal kayıtla açıklanır, ayrı "gizli ret" yolu yoktur. Sonuç kodu (`code`): `approved` · `zoning_not_buildable` · `infrastructure_exhausted` · `insufficient_financing` · `demand_too_low` · `return_too_low` (engel yoksa katkısı en düşük olan).
Olumlu karar: `capital −= outlay` (arsa bedeli + inşaat; arsa sahibi defteri yok, `totals.land_sales`), parsel `planned`, `owner_id = yatırımcı`, `days_left = plan_days`, boru hattı sayaçları artar (talep hemen düşer: aynı gün aynı pazara çifte yatırım yapılmaz). Olumsuz: parsel boş; kayıt §5.

**Değerlendirme zamanlaması (SIM-08, TEK-02):** (a) durumda saklanan bir **imleç** tick başına `n/review_period_days` parsel gezer (her boş parsel ≈ periyotta bir görülür; `review_enabled=0` ile kapatılır); ön eleme: izinli kullanımların mevcut talebi `prescreen_demand_pm` altındaysa değerlendirilmez (pazar ölü); reddedilen parsel `decline_backoff_days` bekler; bölge başına günlük en fazla `max_starts_per_region_per_day` başlangıç; tick başına en fazla `max_reviews_per_tick` tam değerlendirme (yatırımcı dikkati kıt; kesilen tarama imleçten sürer, yüksek indeksli parsel aç kalmaz — tick maliyetini sınırlar). (b) imar yürürlüğe girince `attention_delay_days` sonra **mutlaka** değerlendirilir (ön eleme yok) ve `command.<id>` gerekçenin `subjects`'ine girer: oyuncu "imarımın sonucu ne oldu?" sorusunu yanıtlayabilir. Yatırım hiçbir yerde "sihirle" anında gelmez.

## 5. Kademeli gelişme ve olaylar (SIM-03/08/12)
`planned` (`plan_days`) → `under_construction` (`construction_base_days + units·construction_days_per_unit`) → `built`. Her geçiş `parcel.changed` olayı: `event.construction.started`, `event.construction.completed`; yatırım kararı `actor.decided`: `event.investor.develop` / `event.investor.declined` (olay `reason_ids` taşır).
**Durma:** inşaatta bölge altyapı yükü kapasiteyi aşarsa (`infra_cap` düşünce — T-014 bakım yetersizliği bunu yapacak) `stalled` (`event.construction.stalled`, gerekçe `construction_stalled`); kapasite dönünce `under_construction` (`event.construction.resumed`). Durmuşken `days_left` azalmaz.
**Gerekçe gürültüsü:** olumlu karar her zaman yazılır. Olumsuz sonuç yalnız (i) parselin son kaydından farklı `code` ya da (ii) tekrarlanabilir kod (`demand_too_low`, `return_too_low`) için `negative_repeat_days` geçmişse yazılır (`zoning_not_buildable`/`infrastructure_exhausted`/`insufficient_financing` değişmedikçe tekrar yazılmaz). İmar değişince sayaç sıfırlanır. Yazılmayan olumsuz tarama sayaçta tutulur (`totals.declines_unrecorded`): hiçbir ret sessiz değil, ama kayıt taşması da yok.

## 6. SIM-07 / CAN-03 sözleşmesi (testle)
a) Yol/altyapı/imar tek başına bina yaratmaz: talep yok + altyapı var + imar var ⇒ ufukta `development` hep `vacant`.
b) Aynı imar iki koşulda: yüksek talep/yeterli altyapı → `planned`→…→`built`, gerekçe olumlu; düşük talep/yetersiz altyapı → boş, gerekçe olumsuz ve hangi etkenin engellediğini söyler. Sonuç RNG gürültüsünden bağımsızdır (çoklu tohumla doğrulanır).
c) Belediye komutları (`zoning.propose`, `budget.propose`) yalnız koşulu değiştirir; `building.* / private.* / spawn.*` `not_a_mayor_verb` ile reddedilir (T-027 beyaz listesi korunur). `development` değişimi yalnız bir `actor.decided` gerekçesinden sonra ve aynı parsel için olur (testle: her `planned` geçişinin öncesinde olumlu gerekçe var).
d) **Aşırı talep → spekülasyon:** v0'da **kısmi**: arsa değeri yükselir, getiri düşer (uygulandı). **Yanlış yoğunluk → bütçe baskısı:** v0'da **kısmi**: yoğunluk altyapı yükünü ve `infra_load_pm` istatistiğini artırır, altyapı dolunca yatırım durur/yavaşlar; belediye bütçesine/bakım maliyetine bağlanması **T-014**. Gerçek bütçe baskısı bu belgede iddia edilmez.

## 7. Facade kancası ve API (T-014/T-017 için)
`ParcelView.development/land_value/owner` ekonomiden okunur (`EconomyState.decorate_view`); kurulu değilse şablon korunur. `EconomyQuery` (salt okunur): `region_stats(state)`, `demand_pm(state, region_index, use)`, `parcel_record(state, parcel_id)`, `totals(state)`. T-014 yazma noktaları (bu görevde yalnız tanımlı): `infra_cap`, `income_pm`, `access_pm`, `service_pm`, `interest_pm` (config). T-017 grup tepkileri `res_built/units`, `land_value`, kira baskısını (`rent_mult_pm`) okur. Kurulum: `EconomyBootstrap.create_facade(...)`; varsayılan `SimFacadeImpl.create` ekonomiyi **kurmaz** (mevcut davranış korunur).

## 8. Determinizm
Sistem durumsuzdur (yalnız `ParcelSource`'tan türeyen değişmez önbellek tutar); tüm kalıcı veri §2'dedir. Tek RNG akışı `economy`, değerlendirme başına tam 2 çekim, ön elemeden sonra. İterasyon: indeks/sıralı anahtar. Kesir yok: tam sayı bölme sıfıra doğru, kesir birikimi `growth_frac`.

## 9. Denge hipotezleri (ölçülebilir; kanon DEĞİL)
Ölçüm: sentetik 200 parsel, tek bölge, varsayılan config (altyapı 100000 aksi belirtilmedikçe), `tests/sim/economy/economy_hypotheses_test.gd` yönleri korur (monotonluk), mutlak sayılar ayarla değişir.
| Hipotez | Ölçüm (varsayılan ayar) |
|---|---|
| H1 yatırım talep kıtlığıyla artar | 360 günde onay: hane 0→0, 20→2, 50→4, 100→9, 200→18, 400→36, 800→52 (800+ sermaye sınırlı, bkz. H6) |
| H2 arz talebe yetişince başlangıç durur (öz-sınırlama) | hane 150: 30 günlük pencerelerde başlangıç [14,0,0,…]; D_res 500 civarında dengelenir |
| H3 yoğunluk ↑ ⇒ proje ↓, altyapı dolar | hane 3000, altyapı 400: yoğunluk 500/1000/2000/3000 → onay 80/40/19/12, altyapı yükü %100/100/99,7/96 (altyapı dolu); proje başına yük ↑ |
| H4 aşırı talep ⇒ arsa yükselir | 720 günde boş parsel ort. arsa: hane 100→1000 (taban), 400→1038, 2000→1594 (tavan 3000) |
| H5 erişim/hizmet ⇒ hane ve yatırım | karma imar, hane 300, 720 gün: erişim=hizmet 0→hane 221/onay 30; 600→369/36; 1000→509/48. Yalnız konut imarı iş yaratmaz ⇒ hane 253 vs karma 369 |
| H6 sermaye hızı sınırlar | 720 gün, hane 2000: sermaye 5000/yatırımcı girdisiz → 0 onay (tümü `insufficient_financing`); girdi 6000/ay → 52; 80000+girdi → 86 |
Gözlemler: (i) varsayılan config'te büyük taleplerde (hane ≥ 800) üretim **sermaye sınırlı**dır (H6) — `monthly_inflow` ve `capital` denge ayarıdır; (ii) yalnız konut imarlı şehir iş çekimi olmadığı için yavaş küçülür (pull<500) — oyuncunun karma/ticaret imarı gerçek bir seçimdir; (iii) belediye bütçesi/bakım maliyeti yoktur (T-014): "yanlış yoğunluk ⇒ bütçe baskısı" yalnız altyapı doluluğuna indirgenmiştir.
**Maliyet (10k parsel, 4 bölge, GDScript, Intel Mac, 360 gün):** tick ort. 12,8 ms (ay sınırı 27 ms, en çok 79 ms); 2k parsel 6,8 ms; 30k parsel 15,4 ms (ay sınırı 60 ms). Ekonomi durumu 10k parselde ≈ 0,47 MB (`var_to_bytes`), 30k'de ≈ 1,4 MB. Kayıt/hash maliyetinin baskın kısmı ekonomi değil **gerekçe günlüğü**dür (10k parselde ≈ 9k kayıt ⇒ 16 MB kayıt, hash ≈ 9 s): `reason_log_capacity` ve ilk-tarama gerekçe seli ölçekte risktir (T-016 ile ele alınmalı).

## 10. AÇIK sorular (karar gerekmeden ilerlendi)
Q-E1 Başlangıç nüfus/hane sayısı ve bölge başına altyapı kapasitesi (F05-D). Q-E2 Para birimi/vergi (Q-003) — v0 birimsiz. Q-E3 Yatırımcı çeşitliliği/kimlikleri (T-015/T-016). Q-E4 Kıyı/ada bölge ayrımının ekonomik etkisi (WLD verisi sonrası). Hepsi yapılandırma; yaratıcı karar gerektirmez.

## 11. v1.1 sözleşme istekleri (contracts hattı)
`ParcelView`: `development_progress_pm` (kalan süre), `project_use`, `units`. `ParcelSource`: toplu sütun okuma (`region_code_of`, `area_of`, parsel başına erişim/cephe) — `template()` kopyası ölçekte pahalı. Yeni metin anahtarları: `reason.factor.{financing, zoning_fit, market_sentiment}`, `event.construction.{completed, stalled, resumed}`, kod anahtarları §4. Bölge/talep görünümü (`DistrictView`: talep, doluluk, arsa endeksi).
