# Kamulaştırmada yeniden iskân yükümlülüğü ve sosyal güvenlik politikaları (v1)

Statü: **ÇALIŞMA MODELİ** (aksi belirtilmedikçe). Hiçbir sayı kanon değildir; sayılar "çalışma değeri" etiketiyle, gerekçesiyle ve test fikriyle verilir.
Köken: D-016 (2026-11-01, sahip kararları), D-015, D-014 §3, D-011. v1 = v0 + D-016 işlendi; aşamalı uygulama planı: `production/tasks/T-065.md`. Yazan: systems-designer. Tarih: 2026-11-01.
REQ: SIM-01, SIM-03, SIM-05, SIM-07, SIM-09, SIM-10, SIM-12, CAN-03, CAN-04, CAN-06, CAN-10, TEK-01, TEK-02. Açık kanon: F05-D (bütçe/yasal yetki formülleri, seçim kuralları).

## Sade özet (sahip için)

1. Dediğiniz gibi: yeniden iskân, açılıp kapanan KALICI bir politika. Bir kez açarsınız, sonraki kamulaştırmalar için geçerli; kapatırsınız, bugünkü hâl döner.
2. Açıkken yıkılan ailelere şehirdeki gerçekten boş evler ayrılır; ev bulunan ailenin tepkisi sıfır olmaz, biraz kalır.
3. Belediyenin bedeli ekranda görünür (şimdilik gösterge, gerçek para engeli yok). Açmamak da meşru bir yoldur; sonuçlar buna göre çıkar.
4. Boş ev yoksa yol yine yapılır, ekran "şu kadar aile için ev yok" der, o ailelerin tepkisi sürer.
5. İlk dilim küçük: aç/kapa düğmesi, ev ayırma, bedel göstergesi, "ev yok" mesajı. Tepki bölge düzeyinde; tek tek ailelere bakmıyor.
6. Sonraki aşamalar ayrı: hane sınıfı verisi ("duruma göre" fark), meclis/seçim bağı. Belediyenin kendi konut yapması ayrı ve kapsam dışı.
7. Teknik direktörün karar vermesi gereken bir nokta var (kalıcı politikanın kayıt yeri); ben karar vermedim.
8. Sayılar "çalışma değeri"dir, kanon değil. Sorunuz yalnızca 2 küçük kart, en sonda.

## 0. D-016 ile ONAYLANMIŞ YÖN (v1 eklemesi; v0 soruları cevaplandı)

| Madde | Sahibin sözü (D-016) | Statü | v0'a etkisi |
|---|---|---|---|
| Nasıl açılır | "acilik kapatilabilen bir politika olmali. belediye sosyal belediyecilik de yapabilir, yapmaya da bilir. sonuclari da buna benzer durumlarda ortaya cikar." | ONAYLANMIŞ YÖN | Seçenek A (yol başına anahtar) yerine C'nin politika kısmı: **kalıcı, açılıp kapatılabilen politika**. Varsayılan KAPALI; açmak da kapatmak da meşru (CAN-10, SIM-10). |
| Bulunan ailenin tepkisi | "Duruma göre biraz kalsın" | ONAYLANMIŞ YÖN | `residual_reaction_pm` 0 değil: **biraz** kalır; D-014 §3 "hiç olmasın" bu noktada güncellendi. Miktar hanenin durumuna göre; veri gelene kadar bölge düzeyi, tek sabit çalışma değeri. |
| Ev yoksa | "Yol yine yapılır (Önerilen)" | ONAYLANMIŞ YÖN | Yol reddedilmez; "N aile için ev yok" sistem mesajı; o ailelerin tepkisi tam sürer; bedel görünür. |

Hâlâ AÇIK (sorulmadı, uydurulmaz): "decent"in nihai tanımı (üç denetim §4 ÇALIŞMA MODELİ kalır), meclisin politikayı nasıl onaylayacağı/hangi çoğunluk (F05-D), seçimde nasıl yargılanacağı, belediye konut inşası, mülk sahibi tazminatı (Q-017/Q-022), gerçek para kısıtı (T-014/Q-003).

Aşamalı uygulama planı: `production/tasks/T-065.md`. Aşama 1 = en küçük oynanabilir dilim (aşağıdaki "Politika değişkeni" ve §3 "v1 Aşama haritası").

## 1. Sahibin sözü ve ONAYLANMIŞ YÖN (REQ: CAN-06, SIM-05, SIM-12)

| Kaynak | Söz / içerik | Statü |
|---|---|---|
| D-015 | "politikalari daha sosyal guvenlik uzerine sekillendirebilmeli oyuncu. bu da kamulastirmalari (tabii ki oturan kisilerin varliklarina, ekonomik ve sosyo politik durumlarina gore de degisecektir ama..) daha az tepkili hale getirir, cunku bu bir ozellik gibi kamulastirmada vatandaslara decent yeni bir ev bulma yukumlulugu gelmistir." | karar metni |
| D-014 §3 | "onlara yeni ev sunulmadigi surece tepki olsun. eger sunulursa tepki hic olmasin." (evi yıkılan ve yol dibindekiler yüksek, ilçe geneli çok az ama sıfır değil) | karar metni |
| D-011 | Yıkımlı yol onaydan sonra geri alınır (binalar döner, halk tepkisi dönmez); halk esas olarak yerinden edilmeye tepki verir | karar metni |

Bundan çıkan **ONAYLANMIŞ YÖN** (yön bağlayıcı; nesneler/sayılar değil):
- OY-1: Oyuncu politikalarını sosyal güvenlik yönünde şekillendirebilir.
- OY-2: Kamulaştırmada "uygun yeni ev bulma yükümlülüğü" bir politika/özellik olarak vardır.
- OY-3: Yükümlülük kamulaştırmanın halk tepkisini azaltır; azalma oturanların varlığına, ekonomik ve sosyo-politik durumuna göre değişir.
- OY-4: Ev sunulmadıkça tepki sürer (D-014 §3).

**AÇIK (sorulmadı, uydurulmaz):** yükümlülüğün nasıl açılıp kapandığı (tek seferlik anahtar mı, kalıcı politika mı), maliyeti, "decent"in tanımı, sunulan evde kısmi tepki kalıp kalmayacağı, ilk sürüm kapsamı, belediyenin yeni konut yapması, mülk sahibi tazminatı (Q-017/Q-022 ile örtüşür). D-015 kapsam notu: bu karar tek başına yeni sistem uygulamaya izin vermez; bu spec sorulacak kartın taslağıdır.

Kısıtlar (kanon): CAN-03 (oyuncu özel bina yerleştirmez; boş ev tahsisi bina yaratmaz), SIM-07 (sihirli çözüm yok; yeterli ev yoksa yoktur), SIM-09 (tek "mutluluk %" yok), SIM-10/CAN-10 (yükümlülük şart değil, seçim; reddedilen/başarısız sonuç anlamlı olmalı), TEK-01/02 (belirlenimci, rastgelelik yok, kayıtlı).

## 2. Sim'de bugün OLAN ve OLMAYAN veriler (REQ: SIM-01, SIM-03, SIM-12)

Hepsi kodu okuyarak doğrulandı (çalıştırılmadı).

### 2.1 OLAN
| Veri | Yer | Not |
|---|---|---|
| Hane = **bölge toplamı**. `latent_hh` (bekleyen hane), `income_pm`, `access_pm`, `service_pm`, `infra_cap`, `res_built`, `res_pipe`, `com_built`, `com_pipe` bölge sütunlarıdır | `src/sim/economy/economy_state.gd:51-54` | Tek hane nesnesi yok. |
| Barınan hane = `min(latent_hh, res_built)`; arayan = `latent_hh - barınan`. Boş birim = `max(res_built - latent_hh, 0)` (kodda ayrı alan değil, buradan türer) | `src/sim/economy/economy_query.gd:42-49`; `src/sim/politics/bloc_signals.gd:41-44` | Konut birimi = hane kapasitesi (`economy_config.json` `units_per_1000m2`). |
| Yerinden edilen hane = yıkılan konut biriminin neden olduğu **barınan hane düşüşü**; kapasite fazlası varsa 0 çıkar | `src/sim/economy/parcel_expropriation.gd:69-75` | Mevcut boşluk zaten düşülmüş sayılır (bkz. §3 etkisi). |
| Hane kaderi bayrağı: `return_to_latent` (bölgenin bekleyen talebine döner) / `leave_region` (bölgeden ayrılır). Hane başka bölgeye taşınmaz, kuyruğa girmez | `parcel_expropriation.gd:15-17,77-78`; `src/sim/public_works/public_works_config.gd:12,23`; `data/sim/public_works/road_works.json` (`household_fate`) | "Yeniden yerleşme" bugün = piyasanın kendi arz/talep akışı: aylık hane akışı `latent_hh`'ı çekime göre değiştirir (`src/sim/economy/economy_system.gd:370-389`). |
| Tepki girişi: `plan["displaced"]` -> `note_reactions` (yerinden edilen defteri) ve yakınlık defteri | `src/sim/public_works/expropriation_flow.gd:135`; `src/sim/public_works/public_works_state.gd:101-123` | **Tek giriş noktası**: yükümlülük bu sözlüğü düşürerek tepkiyi azaltır. |
| Tepki hesabı: defterden `displacement`/`proximity` sinyali; mahalle okuması `displaced/neighborhood_households` (çalışma değeri 200 hane) | `src/sim/politics/bloc_signals.gd:91-97`; `src/sim/politics/reaction_agenda.gd:89-134`; `data/politics/reactions.json` | Tepki yalnız "yerinden edilen" (yüksek) ve "yakındaki" (hafif) ayrımı bilir. |
| Neden kaydı (SIM-12): yerinden edilen / yakınlık / hane sayısı etkenleri, komut ve parsel özneleriyle | `src/sim/politics/reaction_cause.gd:43-54,71-83` | Yeni etken eklenebilir. |
| Kira çarpanı bölge talebinden: `rent_mult_pm`; konut kirası `rent_per_unit_month` (çalışma verisi) | `src/sim/economy/economy_math.gd:31-32,86-91`; `data/sim/economy/economy_config.json` | "Kira" bölge ve parsel üzerinden okunur; hane başı kira yok. |
| Parsel konumu (cm) ve bölge kodu; yakınlık hesabı | `parcel_expropriation.gd:171-222`; `economy_system.gd` `static_columns()` | Mesafe ölçülebilir. |
| Gösterge bütçe: kasa, aylık vergi, yol gideri/iadesi, defter türleri (`tax`, `road_cost`, `road_refund`); kasa hiçbir komutu reddetmez | `src/sim/budget/budget_state.gd:5-30`; `src/sim/budget/budget_system.gd:83-160`; `data/sim/budget/budget_config.json` | Kamulaştırma bedeli yok (Q-022 AÇIK). |
| Geri alma anlık görüntüyü geri koyar; tepki defteri geri alınmaz | `parcel_expropriation.gd:128-164`; `expropriation_flow.gd:148-165` | D-011 ile uyumlu. |
| Yıkım sonucunun arayüze gelen sayısı | `src/sim/facade/sim_facade_impl.gd:150-158` | `displaced_households` yalnız sayı. |

### 2.2 OLMAYAN
| Eksik | Kanıt | Sonuç |
|---|---|---|
| **Yeniden iskân / "yeni ev sunma" mekanizması hiç yok.** Kodda ilgili yapı bulunmadı (arama: iskân, rehouse, resettle, relocat) | D-014 §3 notu "sim'deki karşılığı SORULMADI"; `economy_system.gd`'da taşıma yok | D-014 §3 "sunulursa tepki hiç olmasın" kuralı **henüz uygulanmış değil**; tepki her zaman çalışıyor. |
| **Hane başına** varlık, gelir, kiracı/mülk sahibi, kıdem, kırılganlık | Sütunlar yalnız bölge toplamı (`economy_state.gd:51-54`). `owner_id` parselin **yatırımcı** kimliği, oturan değil (`economy_state.gd:9`) | "Oturanların varlığına/durumuna göre" ilk sürümde **yalnız bölge düzeyinde** olabilir. |
| `income_pm` pratikte etkisiz: tek kullanımı ticaret talebi; tüm bölgeler varsayılan 1000, `overrides` boş | `economy_math.gd:93`; `economy_config.json` bölüm "regions" | Bölgeler arası gelir farkı bugün **yok**; "duruma göre" için önce veri girmeli. |
| Hanenin gideceği yer, taşınma süresi, kuyruk | `parcel_expropriation.gd` yalnız 2 kader bayrağı | Taşıma = yeni kod. |
| Mülk sahibi tazminatı, işletme kaybı, kamulaştırma bedeli | `road_works.json` `_note` ("Uygulanmayanlar: tazminat parası, işletme kaybı, hane yeniden yerleşim kuyruğu"); Q-022 | Yükümlülük bedeli bunlardan **ayrı** bir kalem olmalı. |
| Belediye konut projesi / sosyal konut | `src/sim/public_works` yalnız yol; CAN-04'te "belediye tesisi" var ama konut türü kararlı değil | AÇIK; kapsam dışı. |
| Politika durumu (yükümlülüğü tutan anahtar) | `PoliticsState`'te sosyal güvenlik alanı yok; `src/sim/politics/authority.json` yetki verisi var ama bu anahtar yok | Yeni küçük durum alanı gerekir (§3). |

## 3. İlk sürüm için seçenekler

### 3.0 v1: seçilen yön ve aşama haritası (D-016 sonrası; seçenekler A/B/C aşağıda tarihî karşılaştırma olarak kalır)

Seçim: **A'nın hesabı + C'nin kalıcı politika kabuğu**, aşama aşama. Politika değişkeni: `resettlement_policy.enabled` (bool, varsayılan false), oyuncunun komutuyla değişir, kayıtta durur, yol komutundan bağımsızdır (yol başına `resettle` parametresi YOKTUR; o v0 A fikriydi). Yol onayı anında politika neyse o uygulanır; önizleme aynı hesabı gösterir.

| Aşama | İçerik | Sim'e eklenen | GOLDEN riski | ADR | Boyut |
|---|---|---|---|---|---|
| 1 | Aç/kapa politika, açıkken boş evleri yıkılan ailelere ayır, bedel göstergesi, "ev yok" mesajı, kalan tepki bölge düzeyinde | politika durumu, `ResettlementPlanner`, `latent_hh` aktarımı, `resettlement` defter türü, 2 neden etkeni, komut | Düşük: politika hiç açılmazsa durum alanı yaratılmaz, kapalıyken bit-bit aynı (test şart) | Gerekebilir: kalıcı politika durumunun kayıt/anlık görüntü yeri (technical-director kararı) | Orta |
| 2 | Hane sınıfı verisi (bölge gelir/kiracı payı) ve "duruma göre" kalan tepki | yeni bölge sütunları + T0 verisi, kırılganlık formülü | Yüksek: T0 verisi ve ekonomi akışı değişir, GOLDEN yeniden üretilir | Gerekir: sütun/veri şeması, kayıt sürümü (technical-director) | Büyük |
| 3 | Meclis/seçim bağı | politikanın meclis onayı veya yetkisi, seçim sicilinde `equity` bağı | Orta: yeni oy ve sicil alanları | Muhtemelen (F05-D AÇIK: yasal yetki, seçim kuralları kullanıcı kararı bekler) | Büyük |
| (kapsam dışı) | Belediye konut inşası | ayrı sistem (CAN-03 ile uyumlu belediye tesisi, kamu işi) | Yüksek | Gerekir | Büyük, AYRI görev; sahip kararı bekler |


Ortak çerçeve (ÇALIŞMA MODELİ):
- Oyuncu fiili: yol çizerken (kamulaştırma önizlemesi) **yeniden iskân anahtarı** açık/kapalı.
- Önizleme dürüst olur: "N hane yerinden edilecek; M'sine uygun ev bulunabilir; K'sına bulunamaz; tahmini bedel B" (sim'in gerçek hesabı; sahte sayı yok).
- Yükümlülük **bina yaratmaz** (CAN-03): yalnızca mevcut, boş yapılı konut birimlerini ailelere ayırır.

### Seçenek A (ÖNERİLEN): Anahtar + gerçek tahsis + bedel göstergesi + durum-bazlı kısmi azalma

Ne yapar: anahtar açıksa yerinden edilen haneler için çevredeki boş konut birimleri "decent" ölçütünden geçenler arasından ayrılır, haneler fiilen taşınır (kaynak bölgeden hedef bölgeye `latent_hh` aktarımı), belediyeye bedel yazılır, yalnız ev bulunamayan haneler tepki defterine girer.

Kural (sözde formül; hepsi tamsayı, sıfıra doğru kesme, rastgelelik yok):
```
for each source region r (sorted code):
  D_r   = plan.displaced[r]                       # parcel_expropriation.gd:76
  for each candidate region t (sorted by distance, then code):
     if not duty_on: break
     vac_t   = max(res_built[t] - latent_hh[t], 0) - reserved[t]
     decent_t = capacity_ok(vac_t>0) and rent_ok(t, r) and place_ok(t, r)   # §4
     take    = min(D_r_left, floor(vac_t * max_fill_pm / 1000))
     if decent_t: rehoused[r] += take; reserved[t] += take
     elif partial_t: rehoused_partial[r] += take      # yalnız kira veya yer şartından biri aşıldı
  eff_displaced_r = D_r - rehoused[r] - rehoused_partial[r] * (1000 - partial_relief_pm) / 1000
note_reactions(displaced = eff_displaced)            # expropriation_flow.gd:135 tek giriş
latent_hh[r] -= rehoused_all ; latent_hh[t] += rehoused_t   # fiziksel taşınma
cost = rehoused_all * unit_cost(t)
```
- Not: yerinden edilen > 0 ise kaynak bölgede yıkım sonrası boş birim zaten 0'dır (`parcel_expropriation.gd:73`: kapasite fazlası düşülmüştür); bu yüzden adaylar başka bölgelerdir, çift sayım olmaz (varsayım, formülden türetildi; test: kaynak bölge adaylardan çıkarılınca sonuç değişmemeli).
- `unit_cost(t)` = hedef bölgenin aylık konut kirası (`rent_per_unit_month * rent_mult_pm(t) / 1000`) x `support_months` + `move_grant`. Böylece bedel piyasadaki kiraya bağlıdır (kira arttıkça yükümlülük pahalanır: geri bildirim döngüsü).
- Hane durumu (OY-3), ilk sürümde bölge düzeyinde: `vulnerability_r = 1000 - income_pm[r]`; kırılganlık yüksekse `partial_relief_pm` düşer ve `rent_tolerance_pm` daralır (yoksul bölge hanesine daha yakın/daha ucuz ev gerekir). **Bugün tüm bölgelerde `income_pm` = 1000 olduğundan etki sıfırdır**; farkı doğuracak veri (bölge geliri `overrides` veya hane sınıfı sütunu) ayrı bir görevdir ve §6 açık sorusudur.
- Kısmi tepki kalıntısı (v1, D-016 §2): `residual_reaction_pm` çalışma değeri **200** (sıfır DEĞİL). v0'daki "0" D-016 ile geçersiz.
- Geri alma (D-014 §1 "klasik undo"): tahsis geri alınır (`latent_hh` aktarımı tersine, bedel iade, `road_refund` gibi); halk tepkisi geri gelmez (D-011). ÇM varsayımı; sahibe ayrıca sorulmadı.

Sim'e eklenecekler (maliyet):
1. Yapılandırma: `road_works.json` `expropriation` altında `resettlement` bölümü (anahtar varsayılanı, `support_months`, `move_grant`, `max_fill_pm`, `rent_tolerance_pm`, `max_distance_m`, `partial_relief_pm`, `residual_reaction_pm`). Bölüm yoksa KAPALI -> kamulaştırmasız ve yükümlülüksüz koşuların hash'i (GOLDEN) değişmez.
2. `ParcelExpropriation.plan`'a `rehoused`/`unplaced` çıktısı ve `ResettlementPlanner` (saf, durumsuz; önizleme ve tick aynı hesabı kullanır, tıpkı `plan`).
3. `apply`/`restore`'a `latent_hh` aktarımı ve iş kaydına `rehoused`, `cost` alanları (kayıt/yükleme TEK-02; eski kayıtlar `rehoused` yoksa 0).
4. Komut parametresi `resettle: true/false` (`public_work.road`), kapalıysa bugünkü davranış bit-bit aynı.
5. Bütçe: yeni defter türü `resettlement` + iade; gösterge, kasa komut reddetmez (D-010 karar 3; `budget_state.gd` `_LEDGER_KINDS`).
6. Neden kaydı: yeni etken `reason.factor.rehoused_households` ve `reason.factor.unplaced_households` (`reaction_cause.gd`), SIM-12 için.
7. Görünüm: `RoadWorkView`/önizlemeye `rehoused_households`, `unplaced_households`, `resettlement_cost` (`sim_facade_impl.gd:150-158` yanına). Metin ve panel ayrı UI görevi.
8. Politika durumu: anahtarın varsayılanı (oyuncu seçimi) için küçük bir alan; yalnız anahtar açılınca yaratılır (hash koruması).
9. Testler: determinizm (aynı tohum aynı sonuç), kayıt/yükleme, sıfır boş ev, çok boş ev, geri alma, anahtar kapalıyken eski davranış.

Etkisi / döngü: oyuncu anahtarı açar -> boş evler azalır (hedef bölgede `housed` artar, kira çarpanı dolulukla yükselir) -> bölge talebi/yatırımcı kararı değişir -> belediye bedeli ödedi (gösterge) -> tepki azalır -> yeni gündem tipi ("ev bulunamayan N hane") doğar. Dengeleyici döngü: boş ev azaldıkça sonraki kamulaştırmada yükümlülük daha az hane karşılar.

Riskler: (i) boş ev tükenince yükümlülük sessizce etkisiz kalmasın diye önizleme "M/N hane" göstermeli; (ii) tüm boş evleri tek yol için tüketme istismarı: `max_fill_pm` hedef bölgenin boşluğunun en çok payını alır; (iii) dominant strateji: bedel gösterge olduğu için "her zaman aç" baskın çıkabilir -> bedelin gerçek kısıta bağlanması T-014/Q-003 kararıdır, bu spec dışı.

### Seçenek B: Yalnız anahtar + bedel göstergesi (taşıma yok)
Anahtar açıksa yerinden edilen hane sayısı, boş ev varsa tepki defterine yazılmaz; hane taşınmaz (bölge toplamına dokunulmaz), yalnız `resettlement` bedeli yazılır.
- Sim maliyeti: A'nın 1, 4, 5, 6, 7, 9. maddeleri; taşıma/`latent_hh` aktarımı ve hedef seçimi yok. Küçük ve ucuz.
- Zayıflık: ev sihirle "bulunmuş" sayılır, dünyada görünür fiziksel değişiklik yok (nedensellik zayıf, SIM-07/SIM-12 ruhuna ters). Boş ev şartını yine de denetleyebilir (yalnız sayı koşulu), bu hâliyle "ucuz taslak"tır. Yalnız hız gerekiyorsa kabul edilebilir; sonra A'ya genişletilir.

### Seçenek C: Kalıcı sosyal güvenlik politikası (kademeli) + hane sınıfı verisi
A'ya ek: yükümlülük tek yol için değil, belediyenin kalıcı politikası olur (kademe: yok / kira desteği / tahsis); meclis desteğiyle (council) ve seçim sicilinde `equity` (bölgeler arası eşitlik) göstergesiyle bağlanır; bölge/hane **sınıfı** (düşük gelir payı, kiracı payı) yeni sütun olarak eklenir ve tepki azalması bunlara göre değişir (OY-3 tam karşılık).
- Sim maliyeti: A'nın tamamı + hane sınıfı sütunları ve T0 verisi (kimse tasarlamadı; world/ekonomi verisi gerekir) + politika durumu + `PlayerRecord.equity` ile bağ + meclis oylaması. Büyük; F05-D (yasal yetki, bütçe formülleri) AÇIK olduğundan birçok yerde veri odaklı bırakılır.
- Ne zaman: A kanıtlanıp sahip "kalıcı politika olsun" derse.

## 4. "Decent ev" nasıl ölçülür (REQ: SIM-01, SIM-03, SIM-09)

Tek puan yok; üç ayrı, görünür denetim. Hepsi **mevcut** verilerle hesaplanabilir (§2.1):

| Denetim | Ölçü | Veri | Eşik (ÇALIŞMA DEĞERİ) |
|---|---|---|---|
| Kapasite | Hedef bölgede boş yapılı konut birimi var mı: `max(res_built - latent_hh, 0) - ayrılmış` >= alınacak hane | `res_built`, `latent_hh` | Eşik yok; 0'sa uygun değil. `max_fill_pm` = 300: bir tahsisin hedef bölge boşluğunun en çok %30'unu almasına izin ver. Gerekçe: tek yolun tüm boş evleri tüketmesini önlemek. Test: boş ev sayısı 10, 100 haneli yıkımda en çok 3 ev tahsis edilir. |
| Kira | `kira(hedef)` <= `kira(kaynak, yıkımdan önce)` x (1000 + `rent_tolerance_pm`) / 1000; kira = `rent_per_unit_month * rent_mult_pm / 1000` (konut) | `economy_config.json`, `economy_math.gd:31` | `rent_tolerance_pm` = 250 (çalışma değeri). Gerekçe: aynı bölge kirası sabit çarpanlı olduğu için ilk sürümde farkı bölgeler arası talep belirler; %25 başlangıç tahmini. Test: iki bölgeli sahnede ucuz bölgeye tahsis geçer, pahalıya geçmez. |
| Yer | Hedef bölge, kaynak parselin merkezine `max_distance_m` içinde (parsel merkezleri üzerinden, aynı bölge öncelikli) | parsel merkezi (cm), `region_of` | `max_distance_m` = 800 (çalışma değeri). Gerekçe: bir mahalle ölçeği (`neighborhood_households` = 200 hane) yürünebilir mesafeye denk gelsin; ölçülmedi. Test: Ismeral D2 üzerinde 150 yol denemesinde kapsama oranı (M/N) dağılımı. |

"Kısmi decent" (`partial_relief_pm`, çalışma değeri 600): kira **veya** yer şartı aşılmış ama kapasite var -> tepki %60 azalır; ikisi de aşılmışsa decent değil. **Gerekçe:** D-015 "duruma göre değişir" dedi; kısmi durum bunun en basit görünür biçimi. **Sınır:** ölçekleri gerçek haneye göre ayarlamak veri girince (§2.2) yapılacak.

Kapsam dışı (veri yok): ev kalitesi (m2, bozukluk), oda sayısı, işe erişim süresi, komşuluk bağı, hane başına borç. `access_pm`/`service_pm` (hizmet/erişim) bölgeler arası farkı **ek denetim** olarak eklenebilir (hedef `service_pm` >= kaynağın) ama bugün tüm bölgelerde varsayılan sabit olduğundan etkisizdir.

## 5. Geri bildirim (oyuncuya gösterilecek; SIM-12, CAN-03)

- Yol önizlemesi: "Yerinden edilecek: N hane. Uygun ev bulunabilecek: M. Bulunamayacak: K (neden: kapasite/kira/yer). Yükümlülük bedeli (gösterge): B."
- Onaydan sonra: dünyada görünür: taşınan haneler (insan figürü yok -> bölge sayacı ve "taşındı" olayı), yıkılan bina izi (mevcut). Hiçbir bina spawn olmaz.
- Gündem: ev bulunamayan haneler için mevcut PE-01 tepki öğesi, nedenler zinciri "yerinden edildi <- yol" yanında "yeniden iskân: M/N karşılandı".
- Bütçe satırı: "Yeniden iskân: -B (gösterge)"; geri almada iade satırı.

## 6. Parametre tablosu (hepsi ÇALIŞMA DEĞERİ, kanon değil)

| Parametre | Çalışma değeri | Gerekçe | Test fikri |
|---|---|---|---|
| `resettlement.enabled_default` | false | Politika seçimdir, açmamak da meşrudur (D-016, CAN-10); kapalıyken bugünkü davranış ve hash'ler korunur | Politika kapalıyken GOLDEN A/B değişmez |
| `max_fill_pm` | 300 | Tek yolun boş evleri tüketmesini önler | 10 boş ev -> en çok 3 |
| `rent_tolerance_pm` | 250 | Kira şartı; başlangıç tahmini | İki bölge senaryosu |
| `max_distance_m` | 800 | Mahalle yürünebilirliği; ölçülmedi | D2 150 yol kapsama dağılımı |
| `partial_relief_pm` | 600 | "Kısmi decent" için yer tutucu ara değer | Kira aşımı -> tepki %60 düşer |
| `residual_reaction_pm` | 200 (çalışma değeri, binde) | D-016: ev bulunsa da "biraz" kalır; yüksek tepkinin (1000) beşte biri, ilçe geneli "çok az ama sıfır değil" ruhuna yakın; ölçülmedi | Tam tahsis -> kalan tepki yok-tepkinin 0.2 katı; ev yok -> 1.0 katı; ayar 0 -> eski D-014 davranışı |
| `support_months` | 12 | Tepki penceresi 360 gün (`reactions.json` `window_days`) ile aynı ufuk; bedel tahmini | Bedel = ay x kira |
| `move_grant` | AÇIK (sayı verilmez) | Para birimi ve ölçeği Q-003/T-014; birimsiz tamsayı olarak veriden gelir | Sıfırken bedel yalnız kira |
| `vulnerability` ağırlığı | AÇIK | Bölge geliri farkı yok (§2.2) | Bölgelere farklı `income_pm` verilince kısmi azalma değişir |

## 7. Kabul ölçütleri ve test senaryoları

Olumlu (O-1): Anahtar açık, hedef bölgede 40 boş ev, yol 12 hane yerinden ediyor, kira ve yer şartları uygun. Beklenen: 12 hane tahsis edilir (`max_fill_pm` 300 -> 12 <= 12), `latent_hh` kaynakta 12 azalır hedefte 12 artar, tepki defterine yalnız kalan pay (`residual_reaction_pm`) yazılır, ev bulunamayan sayısı 0 olduğundan "ev yok" mesajı çıkmaz, bütçe defterinde `resettlement` satırı, neden kaydında M=N. Aynı tohum ve komut dizisiyle iki koşu aynı durum hash'i.

Olumsuz (N-1): Anahtar açık ama bölgelerde boş ev yok. Beklenen: M=0, K=N, önizleme "ev bulunamayacak (kapasite)" der, yol yine yapılır (reddedilmez), "N aile için ev yok" mesajı çıkar, tepki bugünkü gibi tam çalışır, bütçe bedeli 0, sahte "karşılandı" metni yok (SIM-07).

Olumsuz (N-2): Politika kapalı. Beklenen: bugünkü davranış bit-bit aynı (hash'ler değişmez).

Olumsuz (N-3): Kira şartı aşılıyor ve yer şartı da aşılıyor -> decent değil, tepki azalmaz.

Uç (E-1): Geri al. Beklenen: tahsis geri alınır, bedel iade edilir, tepki defteri kalır (D-011).
Uç (E-2): 10 boş evli bölgeye ardışık iki yol; ikincisi daha az ev bulur (ayrılmış sayaç).
Uç (E-3): Kayıt/yükleme (TEK-02): kaydet -> yükle -> N tick -> hash eşit; eski kayıt `rehoused` alanı yokken yüklenir.
Kabul: oyuncu tepkinin azaldığını nedenleriyle (hangi hane karşılandı, hangisi karşılanmadı) okuyabilir; bu, SIM-12'nin yeni kullanımı. Bu spec **uygulama kanıtı değildir**; gerçek runtime görüntüsü ve nedenselliğin görünürlüğü uygulama görevinde istenir.

## 8. Doğrulanan / varsayılan / test edilmemiş

- Doğrulanan (kodu okuyarak): §2.1 ve §2.2 tablolarındaki her satır dosya:satır ile; D-011/D-014/D-015 metinleri.
- Varsayılan (ajan yorumu): hane kapasitesi = konut birimi (yorum `economy_config.json` açıklamasından); boş birim = `res_built - latent_hh` türetimi; aylık hane akışı yeni tahsisi bozmaz (`economy_system.gd:370-389`); geri alma tahsisi de geri alır; §6 sayıları.
- Test edilmemiş: hiçbir şey çalıştırılmadı (Godot çalıştırılmadı); önerilen formüller ve eşikler hiçbir koşuda denenmedi.

## 9. Açık sorular

Cevaplandı (D-016): açılış biçimi, kalan tepki, ev yoksa. Kalanlar: sahibe 2 küçük kart (aşağıda); teknik soru: kalıcı politika durumunun kayıt yeri (technical-director); F05-D (meclis yetkisi, seçim kuralları) AÇIK; hane sınıfı verisi Aşama 2; mülk sahibi tazminatı Q-017/Q-022; belediye konut inşası kapsam dışı.

## Sahibe kart önerisi

**Önceki kart (v0, 3 soru) CEVAPLANDI: D-016.** Soru 1 (nasıl açılsın) -> kalıcı aç/kapa politika; Soru 2 (bulunan ailenin tepkisi) -> duruma göre biraz kalsın; Soru 3 (boş ev yoksa) -> yol yine yapılır. Bu üçü yeniden sorulmaz.

Aşağıdaki 2 soru YENİ ve plana özeldir; cevap gelene kadar Aşama 1 ikisinden de bağımsız ilerler (varsayılanla).

**Soru 1 · Politika nerede açılıp kapansın?** (Aşama 1'in ekranını belirler)
- A) Önerilen: Bütçe/politika panelinde tek bir "Yeniden iskân" aç/kapa düğmesi; yol çizerken önizlemede durumu ve bedeli görürüm.
- B) Hem panelde hem yol çizerken ("bu yolda geçici kapat" yok; yalnız aynı düğmeye kısayol).

**Soru 2 · Ev bulunan ailenin kalan tepkisi ilk sürümde nasıl olsun?**
- A) Önerilen: Hepsi için aynı küçük pay (çalışma değeri); aileler ayrışınca (sonraki aşama) duruma göre değişir.
- B) İlk sürümde bölgeye göre farklı olsun (bugün bölgeler arası gelir farkı verisi yok; önce o veri yazılmalı, ilk sürüm gecikir).
