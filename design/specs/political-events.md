# Siyasi olay sistemi (T-015 · v0)

Statü: **ÇALIŞMA MODELİ** (her bölüm). Şablon adları, sayılar, eşikler, süreler kanon değildir; hepsi veridir.
Görev: T-015 · Hat: `chars` · Tüketenler: T-017 (siyasi aktörler), T-026 (olay iskeleti + yer tutucu içerik), T-022 (karar akışları), T-021 (nedensellik paneli).
REQ: CAN-02, CAN-06, CAN-10, SIM-05, SIM-07, SIM-08, SIM-10, SIM-11, SIM-12, WLD-11, TEK-01, TEK-02 (+ CAN-03: hiçbir olay seçeneği özel bina yerleştirmez).
Bağımlı spec'ler: `design/specs/characters-npc.md` (aktör/ilişki/hafıza/karar çatısı; "§" atıfları orayadır), `design/specs/politics-elections.md`.

## 0. Deneyim hedefi
- Oyuncu, kendi (veya sistemin) kararlarından doğan **şehirli tepkileri** gündemde görür; "neden bu oldu?" sorusunu zincirle (`cause_refs`) yanıtlar (SIM-12).
- Gerilim: hangi tepkiye, hangi bedelle, ne zaman yanıt vereceği; görmezden gelmenin de sonucu vardır.
- Öğrenilen model: "olay, sistem durumundan doğan baskının eşiği aşmasıdır"; ezberlenecek senaryo yoktur.
- Kaçınılacak: kilitli senaryo, her kampanyada aynı sıra, planlama seansını kesen sürekli pop-up (F03 tempo), kaçınılmaz felaket olayı, oyuncuyu inşadan alıkoyan bürokrasi.
- İlke: **olay yazılmaz, tetiklenir.** Şablon yalnız "hangi sistem durumunda, kime, hangi seçenekle, hangi zaman eğrisiyle" bilgisidir; içerik anahtarları yer tutucudur.

## 1. Olay yaşam döngüsü ve gündem
```
Latent (baskı ölçülür) -> Triggered -> Active[stage 0..n] -> Resolved | Expired | Escalated(sonraki şablon/aşama)
```
Gündem (agenda) bir **kuyruk**tur, kesinti değil. Teslim düzeyleri:
| Düzey | Anlamı | Oyuncuyu keser mi |
|---|---|---|
| `ambient` | Yalnız dünyada: kalabalık, afiş, haber bandı | Hayır |
| `agenda` | Gündem listesine düşer, gerekçe ve seçenekler orada | Hayır |
| `decision` | **Modal olmayan** gündem öğesi, geri sayımlı (süre dolunca `defer`/varsayılan seçenek uygulanır; UX hattıyla uyumlu: engelleyici pencere yok, planlama/inşa sürer). Otomatik duraklatma yalnız kullanıcı ayarıdır; varsayılanı kullanıcıya aittir (AS-11), spec varsayılan dayatmaz, yapılandırma değeri `event.autopause` = kapalı (yer tutucu) | Modal olarak hayır; gündemde öne çıkar, `interrupt_budget` ile sınırlı |
Bütçe: çeyrek başına en çok `interrupt_budget_per_quarter` `decision` düzeyi kesinti; aşan olaylar `agenda`ya düşer (F03: "kesintisiz city-building akışı").

## 2. Şablon şeması (acceptance 2)
```
EventTemplate {
  id: "PE-nn"                     # şablon tanım kimliği (yer tutucu; kanon değil)
  category: protest | investment | council | media | conflict_of_interest | housing | service | regional | coalition | promise
  min_milestone: "M2"|"M3"|"M4"   # kademe kapısı (özellik bayrağı)
  hard: [Condition]               # hepsi doğru olmalı (ön koşul)
  drivers: [{name, source, lo, hi, weight}]    # baskı bileşenleri
  weight: int permille            # taban ağırlık
  gamma: int                      # baskı üssü (doğrusal dışılık)
  cooldown_days, rearm_below      # yeniden silahlanma (histerez)
  mutex: [group]                  # aynı konuda çakışmayı önler
  affected: Selector              # kesim/aktör/parsel seçici (veri sorgusu; ad değil)
  delivery: ambient|agenda|decision
  reason_key: String              # loc anahtarı; gerekçe cümlesi şablonu
  tone_tags: [String]             # tonlama profili için (AÇIK, characters-npc AS-6)
  options: [Option]               # oyuncuya seçenekler; daima "defer" içerir
  stages: [{after_days, if, effects, next}]    # zamana yayılma / yükseltme
  expiry_days
}
Option { id, verb, label_key, requires:{authority, resources}, costs:{budget, political_capital, time_days},
         preview_key, effects:[Effect], risk:{p_fail_permille, fail_effects:[Effect]} }
Effect { target, scope, magnitude(permille), delay_days, duration_days, curve: step|linear|decay, attribution }
```
`Effect.target` değerleri (yalnız mevcut sistem durumları; yeni "sihirli" göstergeler yok):
`bloc.grievance[topic] | bloc.satisfaction[topic] | relation.trust | relation.resentment | media.tone[topic] | investor.political_risk | budget.line | council.stance_shift | council.friction | world.cue`
Her etki, characters-npc §4.2 güncelleme kurallarından geçer (ayrı bir yol yoktur); etkiler gecikme + süre + eğri ile zamana yayılır (SIM-08).
`Condition` kaynakları (okuma sözleşmesi, T-023 snapshot DTO'ları): `bloc.react`, `grievance`, `budget_view`, `service_utilization`, `investor_decision_log`, `rent_index`, `land_value_rate`, `neighbor_policy`, `council_vote_log`. Şablon yalnız bunları okur (olay -> sim bağımlılığı tek yönlü okuma + etki komutu).

## 3. Seçim ve tetik algoritması
```
her event_scan_days (ÇM 7 gün), şablonlar id sırasıyla:
  atla eğer: milestone kapalı | cooldown | mutex-aktif | hard koşul sağlanmıyor
  pressure = sum(w_k * clamp((x_k - lo_k)/(hi_k - lo_k), 0, 1)) / sum(w_k)         # [0,1]
  rising   = pressure geçen taramaya göre yükseliyor  ve  önceki tarama < rearm_below ya da cooldown bitti
  hazard   = weight/1000 * pressure^gamma                                           # tarama başına olasılık
  ateşle   = rising ve rng.events(tick, tpl.id) < hazard
yeni_olay_üst_sınır = max_new_per_scan        # fazlası bir sonraki taramaya, ağırlık sırasıyla
ateşlenen olayın Reason'ı: actor="sys.events", decision_key="decision.event.fire", factors=drivers (weight 0, gösterim) + hazard(+) + rng_draw(-), threshold=0  # score=hazard-draw
```
Olay ateşleme de `Reason` kaydıdır (characters-npc §6.2: `decision_key = decision.event.fire`, `score = hazard - draw`, `threshold = 0`, `ReasonRecord` v1.0). `actor="sys.events"` bir **sistem sözde aktörü**dür; `ActorRef`in sistem aktörünü kabul etmesi gerekir (v1.1 TEKNİK isteği (a), characters-npc §6.2).
Aşamalandırma: `stages[i].after_days` sonra `if` (örn. `bloc.react` hâlâ >= basamak) doğruysa sonraki aşamaya/şablona geçer, değilse `Expired`. Zincir yalnızca **durumla** olur; "A olayı bitince B olayı" kodlanmaz (SIM-11).

## 4. Hikâye-sistemden-doğar kuralları (SIM-10, SIM-11)
1. Hiçbir şablon belirli bir oyuncu seçimini adıyla ön koşul yapmaz; yalnız sistem durumunu okur.
2. Hiçbir şablon zorunlu değildir; bir kampanyada hiç ateşlenmeyebilir.
3. Aynı sistem durumu iki farklı kampanyada, ilişki/hafıza farkı yüzünden farklı olayı veya aynı olayı farklı aşamada üretir.
4. Sıra yoktur: şablon `id`si sıralama bildirmez (yalnız tarama sırası için determinizm).
5. Çeşitlilik ölçütü: kampanya başına ilk 10 olayın şablon kümesi iki farklı seed arasında kısmen farklıdır (hipotez PH-3).
6. Hiçbir olay "kayıp ekranı" zorlamaz; ağır sonuçlar (yatırım kaçması, bütçe donması) kurtarma seçenekleri bırakır (hata spirali koruması, §7).

## 5. Şablon kataloğu (yer tutucu içerik; 11 şablon, 8'i M2/M3 çekirdeği)
Yetki kapısı: `requires.authority` değerleri (`rent_protection`, `levy_speculation`, `district_works`, `council_vote`…) **yetki anahtarlarıdır**, yetki tablosu `data/politics/authority.json`'dan gelir; hangi makamın neye yetkili olduğu AÇIK (F05-D), tablo yer tutucudur. Yetki yoksa seçenek gizlenmez, kilitli ve nedeniyle gösterilir; `defer` ve en az bir yetkisiz bedelli seçenek her zaman kalır (PH-9).
Tüm metinler `loc.*` anahtarıdır; aşağıdaki başlıklar yalnız belgelenme içindir, oyunda görünen metin değildir. Statü: ÇM.
| ID | Tür | Kademe | Sert koşul | Baskı bileşenleri (drivers) | Etkilenen | Seçenekler (oyuncu fiili) | Zamana yayılma |
|---|---|---|---|---|---|---|---|
| PE-01 | Mahalle protestosu | M2 | herhangi bir kesim `bloc.react` >= `protest` | ağırlıklı şikâyet `G`, medya büyütme, örgütleme kapasitesi, yakın zamanlı karar yakınlığı | tepki veren kesim + dedikodu ağı | dinleme oturumu; telafi projesi (inşa/bütçe); kararı değiştir/geri al; görmezden gel | protesto `duration`, görmezden gelirse `boycott` aşamasına yükselme; telafi inşası bitince şikâyet çürümesi hızlanır |
| PE-02 | Yatırım çekilmesi/gelmemesi | M2 | bir yatırımcının kararı `no` ve `political_risk` faktörü baskın (T-013 gerekçesi) | `council_instability`, `policy_reversal_count`, `unrest_level`, `permit_delay` | yatırımcılar; bölgenin iş/gelir tabanlı kesimleri | teşvik (bütçe); imar belirlilik taahhüdü (meclis oyu); altyapı önceliği; bekle | güven aylar içinde toparlanır; komşu bölgeye kayma (PE-08) |
| PE-03 | Meclis bütçe krizi | M2 | `council.vote` bütçe önerisi `no/delayed` veya açık tahmini < eşik | `budget_realism`, `lobby_pressure`, `bloc_pressure`, `trust_in_player` | meclis üyeleri; hizmet bağımlı kesimler | revize bütçe; müzakere (taviz -> `obligation`); geçici devam bütçesi; harcama ertele | hizmet satırları `carryover_frac`ta donar (inşa durmaz); sonraki oturumda yeniden oy |
| PE-04 | Medya haberi | M2 | `media.coverage` `publish`; konu: gecikme/maliyet aşımı VEYA başarı VEYA soruşturma | `newsworthiness`, `lean_alignment`, `fact_signal` | medya erişimi olan kesimler | yanıt ver; düzeltme talep et (risk: itibar); projeyi hızlandır; sessiz kal | ton etkisi `media_lag` sonra, çürüyerek |
| PE-05 | Çıkar çatışması iddiası (`tone_tags:["corruption"]`; varsayılan `tone_profile`'da KAPALI, açılmadıkça hiç seçilmez) | M3 | oyuncunun onayladığı imar/kamu işinden yararlanan parsel sahibiyle `obligation`/bağlılık ilişkisi (veri ilişkisi, kurgu yok) | yararlanma büyüklüğü, `sensationalism`, rakibin varlığı, `integrity` | medya, meclis, ilgili kesim | şeffaflık açıklaması; bağımsız denetim talebi; kararı revize; sessiz kal | `trust` ve `media.tone` kaymaları; ton etiketi `corruption` taşır, varsayılan profilde KAPALI; sunum/ceza AÇIK (AS-10, çıkar çatışması mekaniğinin varlığı değil) |
| PE-06 | Değer artışı -> kira baskısı | M3 | kamusal alan/restorasyon tamamlandı ve `rent_index` artışı > eşik | `rent_index`, `heritage_identity` şikâyeti, mülkiyet yoğunluğu | kiracı kesimler (olumsuz), mülk sahibi/esnaf kesimler (olumlu) | kira koruma tedbiri (`requires.authority: rent_protection`, veri kapısı; yetki yoksa seçenek kilitli ve gerekçesi gösterilir; vergi/yetki AÇIK, F05-D); yeni konut arzı için imar; teşvik; bekle | iki kesimde zıt etki; kiracı çıkışı hane taşınmasına (SIM-01) döner |
| PE-07 | Hizmet kapasitesi aşımı | M2 | `service_utilization` > kapasite >= N gün (T-014) | aşım süresi, nüfus artışı, bakım borcu | hizmeti kullanan kesimler | acil kapasite yatırımı; imar yoğunluğunu sınırla; ücret/öncelik; bekle | şikâyet dalgası -> PE-01'e baskı; kapasite inşaatı sonrası çürüme |
| PE-08 | Komşu belediye hamlesi | M3 (M2'de yalnız 1 komşu aktörle test) | `remote.policy_move` çıktısı çekici + sermaye farkı > eşik | `own_region_gain`, `rivalry_pressure`, `macro_conditions` | yatırımcılar, komşu bölge | rekabetçi teşvik; işbirliği teklifi (ortak proje); izle | yatırım kayması aylara yayılır; WLD-11 |
| PE-09 | Spekülasyon dalgası | M3 | `land_value_rate` > eşik ve talep > arz (SIM-07) | değer hızı, boş parsel oranı, faiz | kiracılar, geliştiriciler | spekülasyon harcı (`requires.authority: levy_speculation` + meclis oyu; harç/vergi yetkisi AÇIK, F05-D, veri kapısı); arz için imar; izle | fiyat sıçraması, sonra ani düşüş riski |
| PE-10 | İttifak/iyilik teklifi | M4 | bir aktörün `obligation` > eşik ve hedef proje bekliyor | `obligation`, `ally_support`, medya penceresi | teklifi yapan aktör, rakipler | kabul (bağ + risk); koşullu kabul; reddet | `obligation` ve ifşa riski zamanla |
| PE-11 | Söz vadesi | M4 | `Promise.deadline_tick` yaklaşıyor/geçti | metrik farkı, kesim beklentisi | söz verilen kesim | teslim et; erteleme açıkla; geri çek | `delivery` göstergesi ve `trust` etkisi |
M2 asgari dilimi: PE-01, 02, 03, 04, 07 (characters-npc §8.1). Her şablon için `affected` bir veri sorgusudur; ad barındırmaz.

### 5.1 Örnek şablon verisi (T-026 iskeleti için)
```jsonc
// data/actors/events/pe-01.json
{ "schema": 1, "id": "PE-01", "category": "protest", "min_milestone": "M2",
  "hard": [ {"src": "bloc.react", "op": ">=", "value": "protest", "any_bloc": true} ],
  "drivers": [ {"name": "weighted_grievance", "src": "bloc.G", "lo": 400, "hi": 900, "weight": 500},
               {"name": "media_amplification", "src": "bloc.amp", "lo": 0, "hi": 500, "weight": 200},
               {"name": "organizer_capacity", "src": "bloc.organizer", "lo": 200, "hi": 800, "weight": 300} ],
  "weight": 400, "gamma": 1, "cooldown_days": 60, "rearm_below": 300, "mutex": ["bloc_unrest"],
  "affected": {"type": "bloc", "from": "trigger"},
  "delivery": "agenda", "reason_key": "event.pe01.reason", "tone_tags": [],
  "options": [
    { "id": "listen", "verb": "listen_session", "label_key": "event.pe01.opt.listen",
      "costs": {"political_capital": 80, "time_days": 7},
      "effects": [ {"target": "bloc.grievance", "scope": "trigger_topic", "magnitude": -120, "delay_days": 7, "duration_days": 90, "curve": "decay", "attribution": 1000},
                   {"target": "relation.trust", "scope": "trigger_bloc", "magnitude": 60, "delay_days": 7, "duration_days": 0, "curve": "step", "attribution": 1000} ] },
    { "id": "remedy", "verb": "fund_remedy_project", "label_key": "event.pe01.opt.remedy",
      "requires": {"authority": "district_works"}, "costs": {"budget": 500, "time_days": 60},
      "effects": [ {"target": "bloc.grievance", "scope": "trigger_topic", "magnitude": -400, "delay_days": 60, "duration_days": 360, "curve": "linear", "attribution": 1000} ] },
    { "id": "reverse", "verb": "revise_decision", "label_key": "event.pe01.opt.reverse",
      "effects": [ {"target": "investor.political_risk", "scope": "district", "magnitude": 150, "delay_days": 0, "duration_days": 180, "curve": "decay", "attribution": 1000},
                   {"target": "bloc.satisfaction", "scope": "beneficiary_blocs", "magnitude": -250, "delay_days": 14, "duration_days": 180, "curve": "decay", "attribution": 1000} ] },
    { "id": "defer", "verb": "defer", "label_key": "event.defer", "effects": [] } ],
  "stages": [ {"after_days": 30, "if": {"src": "bloc.react", "op": ">=", "value": "protest"}, "effects": [], "next": "stage_boycott"} ],
  "expiry_days": 120 }

// data/actors/events/pe-02.json
{ "schema": 1, "id": "PE-02", "category": "investment", "min_milestone": "M2",
  "hard": [ {"src": "investor_decision_log", "op": "outcome_is", "value": "no", "dominant_factor": "political_risk"} ],
  "drivers": [ {"name": "council_instability", "src": "politics.council_instability", "lo": 200, "hi": 800, "weight": 300},
               {"name": "policy_reversal_count", "src": "politics.reversals_180d", "lo": 1, "hi": 5, "weight": 300},
               {"name": "unrest_level", "src": "politics.unrest", "lo": 200, "hi": 800, "weight": 200},
               {"name": "permit_delay", "src": "economy.permit_delay_days", "lo": 30, "hi": 180, "weight": 200} ],
  "weight": 350, "gamma": 1, "cooldown_days": 90, "rearm_below": 250, "mutex": ["investor_confidence"],
  "affected": {"type": "investor", "from": "trigger"}, "delivery": "agenda", "reason_key": "event.pe02.reason",
  "options": [ {"id": "incentive", "verb": "grant_incentive", "label_key": "event.pe02.opt.incentive", "costs": {"budget": 400},
                "effects": [ {"target": "investor.political_risk", "scope": "trigger_investor", "magnitude": -200, "delay_days": 30, "duration_days": 270, "curve": "decay", "attribution": 1000} ] },
               {"id": "commit_zoning", "verb": "council_commit", "label_key": "event.pe02.opt.commit", "requires": {"authority": "council_vote"},
                "effects": [ {"target": "investor.political_risk", "scope": "district", "magnitude": -300, "delay_days": 60, "duration_days": 360, "curve": "linear", "attribution": 1000} ] },
               {"id": "defer", "verb": "defer", "label_key": "event.defer", "effects": [] } ],
  "stages": [], "expiry_days": 180 }
```
Tüm sayılar ÇM'dir; ağırlık/eşik/süre tablosu `data/actors/events/*.json`'da kalır, kodda sayı olmaz.

## 6. Örnek nedensellik zinciri ve sapma (SIM-10, SIM-11)
Zincir A (aynı T0, oyuncu 1): yoğunlaştırıcı imar kararı -> geliştirici yatırım kararı `yes` (gerekçeli) -> inşaat bitişi -> trafik/hizmet yükü `service_utilization` aşımı -> PE-07 -> kesim A şikâyeti artar -> `bloc.react` = `protest` -> PE-01 -> medya `publish` (olumsuz ton) -> PE-04 -> meclis üyesi `bloc_pressure` yüzünden bütçe oyunu `no` -> PE-03 -> hizmet hattı donar -> yatırımcı `political_risk` artar -> PE-02 (yeni yatırım gelmez).
Zincir B (oyuncu 2, koruma ağırlıklı): imar sınırlı -> yatırım az -> `jobs_income` şikâyeti kiracı/dar gelirli kesimde birikir; protesto yerine PE-02/PE-08 (komşu çekiyor); meclis desteği yüksek kalır. Aynı olay şablonları, farklı yol ve sonuç; hiçbiri önceden yazılmadı.
Oyuncuya görünen: her halkada `Reason` + `cause_refs`; "neden?" tıklaması zinciri geriye doğru açar (SIM-12).

## 7. Kayıp/sapma koruma, hata spirali, dejenere yollar
- **Asgari eylem bütçesi:** Hiçbir olay oyuncunun inşa komutlarını kapatmaz. PE-03 yalnız hizmet/işletme satırlarını `carryover_frac` düzeyinde dondurur.
- **Kurtarma yolu:** her olayın en az bir seçeneği `defer` dışında bedelli bir çözümdür; test: bütün olay/durum kombinasyonlarında >=1 uygulanabilir seçenek (otomatik tarama, PH-9).
- **Pozitif geri besleme sınırı:** `cooldown`, `rearm_below`, `max_new_per_scan`, `interrupt_budget`, `gamma`; medya ve dedikodu zincirinde tek sıçrama.
- **Dengeleyici:** uzun süre olaysız şehir baskı biriktirmez ("rahatlama"); baskı yalnız gerçek şikâyet/risk durumundan okunur, yapay zar yok.
- **Dejenere:** "her olayı defer" stratejisi: görmezden gelmenin sonuçları (yükselme aşamaları) zamanla yapısal maliyet üretmeli (test PH-5); "her olayı para ile çöz" stratejisi: bütçe sağlığı `fiscal` göstergesine ve PE-03'e geri döner.
- **Tonlama:** `tone_tags` ve `content.tone_profile` AÇIK (characters-npc AS-6); yasaklı etiketli şablonlar profil kapalıyken hiç seçilmez.

## 8. Oyuncuya geri bildirim
- **Dünya:** `world.cue` (kalabalık, afiş, haber bandı, kapalı şantiye); `ambient` düzeyi sürekli çalışır.
- **Gündem paneli:** olay başlığı (loc anahtarı), kimi etkilediği, **neden** (Reason ilk faktörler), seçenekler ve her seçeneğin **ön izlemesi** (beklenen yön, bedel, belirsizlik aralığı; sahte kesinlik yok), geri sayım.
- **Sonuç izlemesi:** seçim sonrası, zamana yayılan etkiler "bekleyen etkiler" listesinde gecikme ve eğri ile görünür.
- **Sorgulanabilirlik:** her olaydan `cause_refs` zinciri; UI yalnız gerçek Reason verisi gösterir (ölü buton/sahte sayı yok).

## 9. Parametre tablosu (ÇM)
| Parametre | Başlangıç | Gerekçe | Test fikri |
|---|---|---|---|
| `event_scan_days` | 7 | Haftalık tarama: günlük titremeyi önler | 3/7/14 ile olay sıklığı ve kesinti |
| `max_new_per_scan` | 2 | Yığılma önler | Yığılma testi |
| `interrupt_budget_per_quarter` | 2 | Planlama kesintisiz (F03) | Oturum başına `decision` sayısı <= 2/çeyrek |
| `cooldown_days` | şablona göre 60-90 | Aynı sorunun üst üste tetiklenmemesi | Cooldown süpürmesi |
| `rearm_below` | 0.25-0.30 baskı | Histerez | Ping-pong tarama |
| `gamma` | 1 | Doğrusal başla; tekrarlayan olay görülürse artır | Hazard eğrisi |
| `weight` | 350-400 permille | Taban ağırlık | Olay frekansı dağılımı |
| `carryover_frac` | 0.7 | Bürokrasi boğmaz | Bütçe donması sırasında inşa/hizmet sürekliliği |
| `expiry_days` | 120-180 | Çözülmeyen olay kendini sürdürmez | Ömür dağılımı |
| `escalate_after_days` | 30 | Görmezden gelme maliyetli | Yükselme oranı |
| `event.content.tone_profile` | `moderate` yer tutucu | AÇIK | — |

## 10. Kabul ölçütleri ve senaryolar
Pozitif:
- **E-P1:** Aynı seed, aynı komutlar -> aynı olay dizisi, aynı `Reason`'lar (TEK-01/02). Kaydet->yükle->N tick hash eşit (bekleyen etkiler dahil).
- **E-P2 (sistemden doğma):** Test: yoğunlaştırıcı imar -> en az PE-07 veya PE-01 kendiliğinden tetiklenir; hiçbir olay oyuncu adı/seçim etiketiyle çağrılmaz (kodda tarama).
- **E-P3 (zıt tepki, SIM-05):** PE-06 benzeri durumda iki kesimde zıt işaretli etki doğar (destek + protesto).
- **E-P4 (zaman):** `delay_days` ve `duration_days` ile etkiler yayılır; seçimin etkisi anında tam değildir.
Negatif/kenar:
- **E-N1:** Tüm sert koşullar sağlanmaz -> hiçbir olay ateşlenmez, hata yok.
- **E-N2:** Eksik `reason_key`/`loc` anahtarı -> `[?]` ve uyarı; ateşleme reddedilmez ama QA taramasında başarısızlık.
- **E-N3:** Seçeneği olmayan şablon veya `defer` içermeyen -> yükleme hatası (şema doğrulaması).
- **E-N4:** Aynı tarama içinde 5 şablon aynı anda eşik aşar -> `max_new_per_scan` ve `interrupt_budget` uygulanır, kalanı sonraya.
- **E-N5:** Oyuncu hiçbir olaya yanıt vermez -> yükselme aşamaları devreye girer, ama inşa komutları çalışır; kaybetme zorlanmaz.
- **E-N6 (SIM-07):** Altyapı yeterli ama yatırım gelmeyen durum PE-02'yi doğru gerekçeyle tetikler (sihirli bina spawn'ı yok).
- **E-N7:** Kampanya A kaydı ile kampanya B (CAN-09) aynı olay örneğini paylaşmaz.

## 11. Ölçülebilir playtest hipotezleri
| ID | Hipotez | Ölçüt |
|---|---|---|
| PH-1 | Planlama akışı olaylarla kesilmiyor | `decision` düzeyi kesinti <= 2 / çeyrek; oyuncu anketinde "kesildim" <= 2/5 |
| PH-2 | Olay nedeni anlaşılıyor (SIM-12) | >=%80 katılımcı bir PE-01'in kaynağını 30 sn içinde doğru söyler |
| PH-3 | Hikâyeler farklılaşıyor | 5 seed x farklı oyuncu: ilk 10 olay şablon kümesi ikili örtüşme <%60 |
| PH-4 | Seçenek ön izlemesi yeterli | Seçilen seçeneğin sonuç yönünü doğru tahmin: >=%65 |
| PH-5 | Görmezden gelme anlamlı maliyetli ama telafi edilebilir | `defer` x3 sonrası maliyet > tek telafi maliyeti, ama telafi sonrası toparlanma var |
| PH-6 | Olay frekansı kabul edilebilir | 1 oyun-yılda ortalama 4-12 `agenda`+`decision` olayı (ÇM aralık) |
| PH-7 | Baskın tek yol yok | Her seçeneğin seçilme payı %10-60 aralığında (dominant seçenek taraması) |
| PH-8 | Zincir izlenebilir | Rastgele seçilen olay için `cause_refs` ile köke ulaşma %100 (otomatik) |
| PH-9 | Ölü uç yok | Tüm tarama durumlarında >=1 uygulanabilir bedelli seçenek (otomatik) %100 |
Hipotezler ÇM sınırlarıdır; sonuçlar `production/qa/` içinde saklanır.

## 12. Açık sorular (characters-npc.md §14 ile birlikte okunur)
Olay-özel gruplar: **AS-6** tonlama sınırları, **AS-9** sistem-vs-yazılı olay dengesi, **AS-10** yolsuzluk/çıkar çatışması mekaniği. Ek:
| Taslak | Soru | Neden gerekli | Beklerken |
|---|---|---|---|
| AS-11 | Olayların kesme düzeyi: oyuncu otomatik duraklatma istiyor mu, varsayılan ne? | F03 "kesintisiz akış" vs kritik karar | `interrupt_budget`, kullanıcı ayarı, varsayılan kullanıcıya ait (yer tutucu: kapalı) |
| AS-12 | Oyuncu geçmiş olay "arşivi" (haber/kronik) görsün mü, anlatı katmanı? | Nedensellik ve kampanya hafızası | Panelde salt veri listesi |
| AS-13 | Medya ve olay metinlerinin gerçek-dünya benzerliği ve siyasi hicvi | Tonlama ve hukuki risk | Yer tutucu `loc` metinleri, jenerik |
Hiçbiri kanon değildir; `design/decisions/` yazılmadı.

## 13. Canon check özeti
```
CANON CHECK — political-events.md (T-015)
Verdict: CLEAR WITH CONDITIONS
Touches: CAN-02, CAN-06, CAN-10, SIM-05, SIM-07, SIM-08, SIM-10, SIM-11, SIM-12
- [OY] SIM-11 hikâyeler sistemden doğar — F01 "Hissiyat" — ok, kilitli senaryo yok
- [ÇM] şablonlar, eşikler, süreler — F03 tempo "çalışma önerisi" — veri
- [AÇIK] tonlama, partiler, takvim, kaybetme, kadro — F05-D — yer tutucu + AS-6/9/10
- [KANONİK] özel bina yerleştirme yok — CAN-03 — hiçbir seçenek spawn etmez
- [RED] saf siyasi metin seçme oyunu — F05-E — olaylar şehir durumundan doğar, inşayı kapatmaz
Questions added: AS-11..13 (taslak)
Safe to proceed with: T-017 (PE-01..04, 07), T-026 (iskelet + yer tutucu içerik)
```
