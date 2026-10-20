# Karakter, NPC ve aktör modeli (T-015 · v0)

Statü: **ÇALIŞMA MODELİ** (her bölüm). Hiçbir ad, sayı, eşik veya katsayı kanon değildir; hepsi yapılandırma verisidir ve oynatma testiyle değişir.
Görev: T-015 · Hat: `chars` · Tüketenler: T-016 (aktör + karar/gerekçe çatısı), T-017 (siyasi aktörler v0), T-026 (profil verisi + olay iskeleti), T-021/T-022 (UI nedensellik/karar akışı).
REQ: CAN-02, CAN-06, CAN-07, CAN-09, CAN-10, CAN-11, SIM-05, SIM-09, SIM-10, SIM-11, SIM-12, WLD-11, TEK-01, TEK-02 (+ CAN-03, CAN-08 sınır koşulu).
Kardeş spec'ler: `design/specs/political-events.md` (olay sistemi), `design/specs/politics-elections.md` (M4 seçim katmanı; bu spec ile §10'da hizalıdır).

## 0. Deneyim hedefi (game-systems-design çerçevesi)
- Oyuncu, fiziksel/ekonomik kararlarının **kimi, neden ve ne kadar** etkilediğini sokakta ve panelde okuyup sorgular (SIM-12); bir sonraki gündemini bu tepkiden çıkarır (F03 döngüsü).
- Gerilim: kimin desteğini, kimin tepkisini ve hangi bütçe/zaman pahasına kabul edeceği. Tek popülerlik skoru yoktur (SIM-09); sicil kesim/aktör bazlı tutulur.
- Öğrenilecek model: "kararım -> etkilenen kesimin şikâyeti/memnuniyeti -> örgütlenme/medya -> meclis sürtünmesi -> yeni gündem".
- Kaçınılacak: sabit kişilik yazısı, kilitli kadro/senaryo, gizli rastgele düşmanlık, tek ahlak göstergesi, oyuncuyu gündemle kesen sürekli pop-up.
- Sınır: bu spec **aktörlerin karar/ilişki/hafıza çatısını** tanımlar. Hane/yatırımcı ekonomik kararları T-013 (SIM-01/02) kapsamındadır; burada yalnız onların **siyasi örtüsü** (siyasi risk sinyali, kesim türetimi) vardır.

## 1. Açık yaratıcı kararlara karşı kural (CAN-01, CAN-07, F05-D)
| Konu | Durum | Bu spec'teki karşılığı |
|---|---|---|
| Protagonist adı, geçmişi, görünümü | AÇIK (cinsiyet/süreklilik KANONİK: aynı erkek, CAN-07) | Yalnız `actor.protagonist` anahtarı + `loc.actor.protagonist.name` yerelleştirme anahtarı; geçmiş `profile_slots[]` = boş; veri yoksa sıfır etki |
| Parti adları/ideolojileri/sayısı | AÇIK | `party.<harf>` yer tutucu; `parties[]` N uzunlukta; M2'de parti yok |
| Rakipler, diğer metropol liderleri, hikâye karakterleri | AÇIK | `actor.rival.<n>`, `actor.remote.<bölge>.<n>`, `actor.story.<n>`: yalnız şema + boş/yer tutucu kadro |
| Seçim takvimi, kaybetme sonucu, başlangıç senaryosu | AÇIK | `politics-elections.md` parametreleri/kancaları; burada kullanılmaz |
| Tonlama sınırları (şiddet, taciz, yolsuzluk temsili) | AÇIK | `content.tone_profile` yapılandırma anahtarı; olay şablonlarında `tone_tags` (bkz. political-events.md) |
| Para birimi | AÇIK (Q-003) | Tutarlar birimsiz tamsayı; görüntü `economy.currency_*` |
Hiçbir ad bu belgede örnek olarak bile "gerçekmiş gibi" geçmez; örnek JSON'daki tüm `name_key` değerleri `loc.*` anahtarıdır ve karşılığı `[YER TUTUCU]` metnidir.

## 2. Sınır, zaman ölçekleri, LOD
- [TEKNİK] Tick = 1 oyun günü (ADR-0002 §4; yaratıcı karar değil, stüdyo/ADR kararı). Aktör sistemleri aynı tick döngüsünde sabit sırayla çalışır; sırada iterasyon `actor.key` sözlük sırasıyla (TEK-01).
- Ölçekler: günlük (şikâyet/memnuniyet çürümesi, olay süreleri), haftalık (kesim yeniden değerlendirme, medya döngüsü), aylık (kesim yeniden türetme, meclis oturumu, bütçe), çeyreklik (soyut bölge aktörlerinin hamlesi). Oranlar `data/actors/cadence.json` (ÇM).
- LOD (WLD-11, CAN-11): odak ilçede tüm tür tam; diğer Ismeral bölgelerinde yalnız seçmen kesimi + soyut belediye aktörü; diğer 6 metropolde yalnız `actor.remote.*` (SIM-06). Odak yükselince (ilçe -> metropol) tek tek aktör hafızaları silinmez: ilçe aktörünün `memory[]`i LOD düşünce `legacy{konu: ağırlıklı_değer}` özetine katlanır, ilişki değerleri (trust/resentment) **olduğu gibi** korunur. Makam değişimi yetkiyi değiştirir, aktörleri/ilişkileri sıfırlamaz (CAN-11).
- Kampanya yalıtımı (CAN-09): her aktör ve ilişki `campaign_id` altındadır; başka bölge kampanyasına referans veremez.
- Determinizm: tüm değerler tamsayı **binde** (permille) veya tamsayı; sistem başına tohumlu akışlar `rng.actors`, `rng.media`, `rng.events` (ADR-0002 §5; platformlar arası eşitlik T-009 için float yok önerisi). Veri formatı `float` kullanırsa yükleme sırasında permille'e yuvarlanır.

## 3. Aktör taksonomisi (acceptance 1)
Anahtar kalıbı: `actor.<tür>.<n>`; protagonist istisna: `actor.protagonist`. `n` dünya kurulumunda sıralı verilir, kampanya içinde sabittir. Görünen ad: `loc.<anahtar>.name`. Hiçbir kodda ad/anahtar sabit string olarak mantığa girmez (yalnız tür).

| Tür | Anahtar | Örnek sayı (ÇM, M2) | Yazar | LOD | Karar türleri | Kademe |
|---|---|---|---|---|---|---|
| Protagonist | `actor.protagonist` | 1 | oyuncu (komut) | her zaman | karar yok: oyuncu komutları; sicil `PlayerRecord` | M2 |
| Meclis üyesi | `actor.council.<n>` | 5 (parametre `council.size`) | sistem | odak ilçe | `council.vote`, `council.lobby_response` | M2 |
| Çıkar grubu temsilcisi | `actor.interest.<n>` | 0-2 | sistem | odak + bölge | `interest.lobby`, `interest.mobilize` | M2 (min 0), M3 |
| Yatırımcı/geliştirici (siyasi örtü) | `actor.investor.<n>` | T-013'ten | sistem | odak ilçe, diğerleri kohort | `investor.political_risk_signal` (ekonomik karar T-013) | M2 |
| Medya organı | `actor.media.<n>` | 1 | sistem | metropol | `media.coverage` | M2 |
| Seçmen kesimi | `actor.bloc.<n>` | >=2 tepki veren | hane kohortundan türer | odak: parsel/mahalle; diğer: kohort | `bloc.react` | M2 |
| Rakip aday | `actor.rival.<n>` | 0 (M4) | sistem | metropol | `rival.attack`, `rival.position` | M4 |
| Soyut siyasetçi (diğer bölge/komşu belediye) | `actor.remote.<bölge>.<n>` | 1 komşu + 6 metropol | sistem | soyut | `remote.policy_move` | M2 (komşu), M4 |
| Hikâye karakteri | `actor.story.<n>` | 0 | AÇIK | — | — | AÇIK: şema ayrılmış, kadro yok |
Not: "belediye bürokratı/kurum" gerekirse genişleme noktasıdır (`actor.official.<n>`); M2'de hizmet kapasitesi sistem değişkenidir (T-014).

### 3.1 Ortak aktör şeması
```
Actor {
  key: String                 # actor.<tür>.<n>, benzersiz
  kind: Enum                  # tablo yukarıda
  campaign_id: String
  name_key: String            # loc anahtarı; ad kanon değil
  traits: {trait_id: permille}    # 0..1000, §3.2
  stance: {axis_id: permille}     # -1000..1000, eksenler veri (§3.3)
  salience: {topic_id: permille}  # 0..1000, hangi konuya duyarlı
  resources: {political: int, money: int(birimsiz), organization: int}   # 0..1000 / birimsiz
  affiliations: [party_key | interest_key | bloc_key]   # boş olabilir
  relations: {actor_key: Relation}    # §4, seyrek tutulur
  memory: [MemoryEntry]               # üst sınır K_mem, §4
  state: {kind'a özgü}
  lod: Enum {full, cohort, abstract}
}
```
### 3.2 Eğilim özellikleri (sayısal; sabit kişilik metni yok)
Her özellik 0..1000; değer **karar ağırlıklarını kaydırır**, davranışı betimlemez. İlk set (ÇM; veri `data/actors/traits.json`):
| trait_id | Etki (karar çatısında) |
|---|---|
| `risk_tolerance` | Yatırım/eylem eşiğini düşürür, belirsiz faktör cezasını azaltır |
| `time_horizon` | Gelecek faktörlerinin ağırlığı; kısa ufuk -> anlık şikâyete duyarlı |
| `self_interest` | Kişisel/çıkar faktörü ağırlığı (`own_gain`) vs kamu faktörleri |
| `public_spirit` | `public_good` faktörü ağırlığı |
| `partisanship` | `party_line`/müttefik faktörü ağırlığı |
| `combativeness` | Çatışmayı seçme eşiği (protesto, açık muhalefet, sert haber) |
| `volatility` | Gürültü genliği ve histerezis darlığı |
| `integrity` | Çıkar çatışması/iltimas kabul eşiği; teşvikle ödünleşim |
Tür başına kullanılan alt kümeler §5 tablosundadır. Yeni özellik eklemek kod değil veri değişikliğidir.

### 3.3 Politik eksen ve konu listeleri (veri; ÇM)
- Eksenler (politics-elections.md §3 ile aynı ilk set; tanımlayıcılar İngilizce, ÇM): `growth_vs_preservation`, `public_investment_vs_market`, `centralism_vs_localism`. Liste AÇIK; veriden okunur. Görünen ad ayrı anahtardır: `loc.axis.<axis_id>.name` (+ uçlar için `loc.axis.<axis_id>.neg` / `.pos`); kod yalnız `axis_id` ile çalışır. Konum işareti: -1000 = ilk uç (`growth`), +1000 = ikinci uç (`preservation`) gibi veri tanımlıdır (`data/actors/axes.json`).
- Konular (`topic_id`; şikâyet/memnuniyet ve olay etki hedefleri): `housing_cost`, `mobility`, `environment_health`, `jobs_income`, `services_utilities`, `public_space`, `heritage_identity`, `fiscal_burden`. Liste ÇM, veri `data/actors/topics.json`.

## 4. İlişki ve hafıza modeli (acceptance 1, SIM-05, SIM-12)
### 4.1 Varlıklar
```
Relation (a -> t) {
  trust: int -1000..1000        # a'nın t'ye güveni (niyet/yeterlilik)
  resentment: int 0..1000       # birikmiş kırgınlık; güvenden bağımsız ve daha yavaş silinir
  obligation: int -1000..1000   # >0: t, a'ya borçlu (iyilik dengesi)
  familiarity: int 0..1000      # temas yoğunluğu; spillover ve olay etkisini ölçekler
  scar_floor: int 0..1000       # kırgınlığın inebileceği taban (yara izi)
  peak_resentment: int
}
MemoryEntry { tick, topic_id, valence(-1000..1000), magnitude(0..1000),
              source_ref(decision/event id), attributed_to(actor_key|null), decay_class }
```
Seçmen kesiminde bireysel hafıza yoktur: `grievances{topic}`, `satisfaction{topic}` (ikisi **ayrı** defter; net edilmez, bir kesim aynı anda hem memnun hem öfkeli olabilir) ve `trust_player` toplulaştırılmış değerdir.

### 4.2 Güncelleme kuralları
Olay/karar `ev` aktör `a`'yı etkilediğinde (valence `v`, büyüklük `m`, atıf `alpha` in [0,1]: sorumluluk oyuncuya ne kadar yüklenir):
```
rho    = a.salience[ev.topic] / 1000
fam    = 0.5 + 0.5 * relation.familiarity / 1000
impact = m * rho * alpha * fam                        # 0..1000 ölçekli

if v >= 0:
    trust      += k_gain  * impact * (1000 - trust) / 1000 * v/1000
    resentment -= k_forgive * impact * (resentment - scar_floor) / 1000 * v/1000
else:
    trust      -= k_loss  * impact * (1000 + trust) / 1000 * |v|/1000     # k_loss = loss_aversion * k_gain
    resentment += k_resent * impact * (1000 - resentment) / 1000 * |v|/1000
    peak_resentment = max(peak_resentment, resentment)
    scar_floor = max(scar_floor, scar_frac * peak_resentment)
memory.push(MemoryEntry(...))
```
Günlük çürüme (üstel, yarı ömürden türer: `lambda = ln2 / half_life`, tamsayı tablo ile uygulanır):
```
trust       -> trust0(a,t) ile  half_life_trust
resentment  -> scar_floor ile   half_life_resent   (> half_life_trust)
memory.weight = 2^(-age / half_life[decay_class])
```
Bellek sınırı `K_mem`: aşılınca aynı `topic_id`'li en düşük ağırlıklı iki kayıt birleştirilir (ağırlıklı ortalama, eşitlikte düşük indeks), böylece belirlenimli ve sınırlı.
Dedikodu/yayılma: `a` güncellenince, `a`'nın ağındaki (`aynı kesim`, `aynı çıkar grubu`, `aynı parti`) `n` için, `spill_delay_days` sonra `trust_n += spill_frac * edge_weight * dTrust_a` (sınırlı, tek sıçrama; zincir yok, salınımı önler).
Onarım: telafi/özür/gerçekleşen söz `v>0` olayıdır ama `resentment` yalnız `scar_floor`a kadar iner; `k_gain < k_loss` olduğundan kötü etki iyi etkiden hızlı birikir (dengesiz ama oyunun siyasi gerilimini taşır; oranı playtest ayarlar).

### 4.3 Kararlara giriş (hepsi gerekçe kaydında faktör olur)
| Faktör adı | Değer kaynağı |
|---|---|
| `trust_in_player` | `relations[player].trust` |
| `resentment` | `-relations[player].resentment` |
| `obligation` | `relations[player].obligation` |
| `topic_memory(topic)` | `sum(weight_i * valence_i * magnitude_i) / sum(weight_i)` |
| `bloc_pressure` | meclis üyesi için, seçmen kesimi `grievances` ağırlıklı toplamı (kendi temsil ettiği kesimler) |
| `precedent` | aynı karar türünde son `N_prec` sonucun işaret ortalaması (tutarlılık beklentisi) |
Bu sayede "aynı karar iki oyuncuda/iki zamanda farklı sonuç" (SIM-10/SIM-11) hafıza ve ilişki farkından doğar, gizli zarda değil.

### 4.4 Protagonist kaydı
Protagonist karar vermez, **komut verir**; davranış tarzı önceden seçilmez, geçmiş kararlardan türer (`PlayerRecord.style{consultative, unilateral, fiscal_hawk, builder}` -> yalnız gösterim ve ilişki beklentisi; oyuncuya hedef puan değildir). `PlayerRecord` göstergeleri politics-elections.md §3 ile aynıdır (`delivery`, `fiscal`, `service`, `equity`, `reputation_by_group`, `media_tone`, `ally_support`); `reputation_by_group[b]` = ilgili aktörlerin `trust_in_player` toplulaştırması (tek skor üretmez). Söz defteri (M3/M4): `Promise {id, topic, target_key, metric, threshold, deadline_tick, state}`.
Protagonist `profile_slots[]` (geçmiş/özellik modifikatörleri) varsayılan boştur; AÇIK karar gelince veri olarak dolar, kod değişmez.

## 5. Tür başına ayrıntı
| Tür | Kullanılan özellikler | Ek durum | Karar faktörleri (ilk ağırlık çizelgesi `decision_tables.json`'da) |
|---|---|---|---|
| Meclis üyesi | `self_interest, public_spirit, partisanship, integrity, volatility` | `seat_group`, `constituency_blocs[]`, `party_key` (M2'de null) | `stance_distance` (öneri ekseni vs üye duruşu), `trust_in_player`, `resentment`, `bloc_pressure`, `lobby_pressure`, `budget_realism`, `party_line` (M4), `obligation` |
| Çıkar grubu temsilcisi | `combativeness, self_interest, time_horizon` | `goals[{topic, direction}]`, `capacity` (örgütleme kapasitesi), `reach{aktör: pay}` | `goal_gain` (karar hedefe ne kadar yarar/zarar), `trust_in_player`, `resource_slack`, `media_window` |
| Yatırımcı (siyasi örtü) | `risk_tolerance, time_horizon, integrity` | `political_risk` (0..1000) çıktısı | `council_instability`, `policy_reversal_count`, `unrest_level`, `permit_delay` -> T-013 yatırım faktörüne `political_risk` olarak girer |
| Medya organı | `combativeness, volatility, integrity` | `lean{eksen: pozisyon}`, `sensationalism`, `reach{bloc: pay}`, `credibility` | `newsworthiness` (çatışma, ölçek, yenilik), `lean_alignment`, `fact_signal`, `credibility_cost` |
| Seçmen kesimi | `volatility, combativeness` (kesim ortalaması) | `size`, `priorities` (=`salience`), `grievances`, `satisfaction`, `exposure` | `grievance_level`, `satisfaction_level`, `media_amplification`, `organizer_capacity`, `trust_in_player` |
| Rakip aday (M4) | `combativeness, partisanship` | `platform`, `war_chest` | `exposure_of_weakness`, `bloc_swing_potential`, `resource_slack` |
| Soyut siyasetçi | `risk_tolerance, partisanship` | `region`, `policy_vector` | `own_region_gain`, `rivalry_pressure`, `macro_conditions` (SIM-06) |

## 6. Karar çatısı (acceptance 1 ve 3)
### 6.1 Genel puanlama (tüm türler için tek mekanizma)
```
# factors: her biri f_i in [-1000,1000] (normalize edilmiş), w_i taban ağırlık (tablo)
w_i' = w_i * (1 + mod[i,trait] * (trait_value - 500) / 500)       # özellik kaydırması, [mod] tabloda
S    = sum(w_i' * f_i) / sum(|w_i'|)             # [-1000,1000]
eps  = noise_amp * volatility/1000 * rng(stream, tick, actor_key, decision_key)   # tohumlu
theta = theta_d - (h if önceki_karar == evet else 0)                              # histerez, ping-pong önler
karar = (S + eps) >= theta
margin = S + eps - theta
```
Eşik ve ağırlık tabloları `data/actors/decision_tables.json`'dadır (kodda sayı yok). Kararlar sıkı bir zamanlama veya tetikle çalışır (§6.4).

### 6.2 `Decision` + `Reason` yapısı: `src/contracts/reason_record.gd` v1.0 ile eşleme
Sözleşme okundu (değiştirilmedi): `ReasonRecord {id, tick, actor:ActorRef, decision_key, outcome ∈ {positive,negative}, factors:[ReasonFactor], threshold, score, scoring="linear", subjects:PackedStringArray, parent_ids:PackedInt64Array, provenance}`; `ReasonFactor {name_key, value, weight, is_estimate, source_ref}`. Değişmezler: `score == Σ trunc(value*weight/1000)` ve `outcome == positive ⇔ score >= threshold`. Spec artık kendi şemasını dayatmaz; kayıt bu sözleşmedir.
| Bu spec (önceki taslak) | Sözleşme v1.0 | Eşleme kuralı |
|---|---|---|
| `actor` (`actor.<tür>.<n>`) | `actor: ActorRef` | `ActorRef.ref()` dizgesi bu anahtar biçimidir; `sys.events` için bkz. v1.1 isteği (a) |
| `decision` (`council.vote`) | `decision_key` | `decision.<tür>.<fiil>` (örn. `decision.council.vote`) |
| `factors[{name,value,weight}]` | `factors[ReasonFactor]` | `name` -> `name_key = reason.factor.<name>`; `value`/`weight` permille tamsayı = `FIXED_SCALE` 1000 ile uyumlu |
| `threshold` | `threshold` | `theta_eff = theta_d - (h if önceki karar evet)` yazılır (histerez eşiğin içindedir) |
| `margin` | (alan yok) | **türetilir**: `score - threshold`; saklanmaz |
| `outcome` yes / no | `outcome` positive / negative | yes -> positive, no -> negative; eylem gerçekleşti mi sorusu |
| `outcome` delayed / partial | (karşılığı yok) | **eşlenemez**: gecikme/kısmilik karar sonrası kuralın sonucudur (`council_friction`), kayıtta değil `CouncilView.delay_days` / olay Effect'inde taşınır; bkz. v1.1 isteği (b) |
| `cause_refs[]` | `parent_ids` | Reason id'leri (int). Olay ateşleme de Reason olduğu için (political-events §3) olay kimlikleri de `parent_ids`'te yer alır; ayrı olay id'si gerekmez |
| `id` ("r-000412") | `id: int` | Sıralı tamsayı (sim sayacı); metin biçimi UI'de üretilir |
| `target_ref` | `subjects` | `parcel.12`, `vote.1`, `actor.bloc.2` |
| `text_key` | (alan yok) | **türetilir**: `reason.<decision_key>.<outcome>.<en_büyük_|katkı|_faktör_adı>`; ayrı saklanmaz |
| `text_args{}` | (alan yok) | Kısmen türetilir: `subjects` + faktör `source_ref`; serbest argümanlar eşlenemez, bkz. (c) |
| `Decision` kaydı | (ayrı tür yok) | Gereksiz: Reason karar kaydıdır |
**Puanın sözleşmeye oturması (öncekiyle çelişen düzeltme).** Sözleşmedeki puan *normalize edilmeden* `Σ value·weight/1000`'dir; §6.1'deki `S` normalizedir. Üretici, kayda yazarken ağırlıkları `w_i'' = round(1000 · w_i' / Σ|w'|)` yapar (gürültü hariç toplam |ağırlık| = 1000), gürültüyü `reason.factor.noise` adlı ek faktör (`value = eps`, `weight = 1000`) olarak ekler; böylece `score ≈ S + eps` (tamsayı kesme farkı en çok faktör sayısı kadar permille) ve değişmez tutar. Kesme yükü belirlenimlidir (aynı sırayla sıfıra doğru).
**Basamaklı kararlar** (`bloc.react`: petition/protest/boycott): sözleşme tek eşik taşır; her değerlendirilen basamak için ayrı kayıt yazılır: `decision_key = decision.bloc.react.<tier>`, `threshold = theta_tier`, aynı `factors`; ulaşılan en yüksek basamak positive, bir üstü negative ("neden boykot değil?" sorgusu için). Basamak kayıtları birbirine `parent_ids` ile bağlanabilir.
**Olay ateşleme** (`decision.event.fire`): `factors` = baskı bileşenleri (`weight = 0`, yalnız gösterim, `is_estimate = false`) + `reason.factor.hazard` (`value = hazard`, `weight = 1000`) + `reason.factor.rng_draw` (`value = -draw`, `weight = 1000`); `threshold = 0`. Böylece `score = hazard - draw >= 0 ⇔ ateşle` değişmezle uyumludur.
**Tahmin etiketi:** medya `fact_signal`, belirsiz bir mesafe kestirimi vb. `is_estimate = true` (UI `reason.estimate` ile etiketler).
**v1.1 TEKNİK istekleri (eşlenemeyenler; kararı `technical-director`/contracts sahibi verir, bu spec zorunlu kılmaz):**
- (a) `ActorRef` sistem sözde aktörünü (`sys.events`) ve `actor.<tür>.<n>` biçimini kabul etmeli (şu an `kind`/`id`/`name_key`; sistem türü belirtilmemiş).
- (b) Karar sonucunun `delayed/partial` nüansı için isteğe bağlı `outcome_detail: StringName` (positive/negative değişmezi bozulmadan); alternatif: nüansı yalnız `CouncilView`/`SimEvent`te taşımak (v1.0 ile de çalışır).
- (c) Serbest `text_args` yerine isteğe bağlı `subjects`-dışı `args: Dictionary` (UI cümle yerleştirmesi için); yoksa UI `subjects` + `source_ref`ten kurar.
- (d) Basamaklı eşik (`thresholds[]`) yerel desteği (şu an basamak başına kayıtla çözülür).
- (e) `campaign_id` (CAN-09) kayıtta yok; kampanya yalıtımı `SimSnapshot` düzeyinde mi sağlanıyor, teyit istenir.
Hiçbiri zorunlu değildir; yoksa spec yukarıdaki eşlemelerle v1.0 üzerinde çalışır.
Sahip testi (T-016/T-027): üretilen her kayıt için `ReasonRecord.is_consistent()` doğru; `score - threshold` işareti `outcome` ile uyumlu.
Gösterim: panel `factors`ı `|contribution|` (`|value*weight|/1000`) payına göre sıralar, ilk N (parametre `reason.top_n`) olanı yerelleştirilmiş cümlede gösterir (`reason.factor.noise` ve `weight = 0` bilgi faktörleri cümleye girmez); kalanı "ayrıntı" altında tutar. Gerekçe her kararda **zorunludur**; üretilemeyen karar uygulanmaz (SIM-12).

### 6.3 Karar tabloları (ilk ayar; hepsi ÇM, `decision_tables.json`)
| Karar | Faktörler (taban ağırlık, permille) | Eşik `theta` | Not |
|---|---|---|---|
| `council.vote` | stance_distance 300, trust_in_player 150, resentment 100, bloc_pressure 200, lobby_pressure 100, budget_realism 100, obligation 50 | 0 (salt çoğunluk için üye başına evet/hayır) | Öneri başına bağımsız; `party_line` M4'te 200 ağırlıkla eklenir |
| `bloc.react` | grievance_level 450, satisfaction_level -250 (karşı), media_amplification 150, organizer_capacity 100, trust_in_player -50 | basamak: `petition` 250, `protest` 500, `boycott` 700 | basamaklı eşik; üst basamak alt basamağı içerir |
| `media.coverage` | newsworthiness 400, lean_alignment 250, fact_signal 250, credibility_cost -100 | `publish` 150 | ton ayrıca §6.5 |
| `interest.lobby` | goal_gain 450, resource_slack 200, media_window 150, trust_in_player 100 | 200 | hedef: üye/medya/oyuncu kanalı |
| `investor.political_risk_signal` | council_instability 300, policy_reversal_count 250, unrest_level 250, permit_delay 200 | (sinyal, eşik yok; çıktı 0..1000) | T-013 yatırım kararına faktör |
| `remote.policy_move` | own_region_gain 400, rivalry_pressure 250, macro_conditions 350 | 100 | çeyreklik |
Eşiklerin tamamı ÇM; değer değişirse davranış değişir, kod değişmez.

### 6.4 Zamanlama
| Karar | Ne zaman | Gerekçe |
|---|---|---|
| `bloc.react` | haftalık + olay tetiği (etki > `react_trigger_min`) | Şikâyet birikir; kesim gün gün oynamaz (salınım yok) |
| `council.vote` | oturum (aylık) + oyuncu önerisi komutu | Meclis dönemsel (F03 tempo) |
| `media.coverage` | haftalık, aday haber üretimi olay/karar tetiğiyle | Medya gecikmeli yankı |
| `interest.lobby` | aylık + hedef konu eşiği | |
Gecikme: karar -> uygulanan etki `effect_delay_days` ile zamana yayılır (SIM-08).

### 6.5 Seçmen kesimi tepkisi ve medya tonu
```
# Kesim
for t in topics:
    g[t]  = g[t]  * (1 - lambda_g[t]) + sum_over_events(max(0, -impact_signed) * sens[b][t] * exposure(b, ev))
    s[t]  = s[t]  * (1 - lambda_s[t]) + sum_over_events(max(0,  impact_signed) * sens[b][t] * exposure(b, ev))
G = sum_t(priorities[t]/1000 * g[t])               # kesimin ağırlıklı şikâyeti
amp = 1 + k_media * max(0, -tone_for(b)) / 1000    # olumsuz medya şikâyeti büyütür
R = G * amp
bloc.react(R, ...) -> {none, petition, protest, boycott}    # §6.3 basamak
# Protesto fiziksel biçimi: kesimin exposure parsellerine yakın kalabalık (UI/dünya T-021/T-020)

# Medya tonu (konu başına)
tone[topic] = clamp( w_fact * fact_signal      # nesnel sonuç (gecikme, maliyet, yarar) 
                   + w_lean * lean_alignment   # çıkış organının duruşu vs karar
                   + w_sens * sensationalism * conflict_intensity , -1000, 1000)
for b in outlet.reach: bloc.media_tone_for[b] = reach[b] * tone   # gecikmeli (media_lag_days)
```
`exposure(b, ev)`: kararın coğrafi/ekonomik ayak izine (etkilenen parsel/ağ hücreleri) kesimin yaşam alanı örtüşmesi; `0..1000`.

### 6.6 Kesim türetme (hane kohortlarından, SIM-01)
```
key(h) = (district_id, tenure{owner,renter}, income_band, age_band)       # bantlar veri
cohort[key].size += voters(h)
küçük kohortlar (size < min_bloc_size) en yakın anahtara (sözlük sırası + mesafe) birleştirilir
bloc.priorities[t] = sum_h rule[t](h) / size        # konu ağırlığı (= salience), 0..1000; rule tablosu data/actors/bloc_priority_rules.json
bloc.stance[a]     = clamp(sum_h srule[a](h) / size, -1000, 1000)   # EKSEN konumu (seçim `dist` bunu okur); data/actors/bloc_stance_rules.json
bloc.exposure     = hane parsellerinin birleşimi
her bloc_rederive_days: yeniden türet; örtüşme >= keep_overlap ise AYNI actor.bloc.<n> id'si korunur (hafıza sürekliliği)
```
`stance` ile `priorities` farklı uzaylardır: `priorities` *hangi konuya ne kadar önem verdiği* (0..1000, konu başına), `stance` *eksen üzerinde nerede durduğu* (-1000..1000, eksen başına). Seçim formülü partinin `platform` vektörünü kesimin `stance` vektörüyle karşılaştırır (politics-elections §4); `priorities` yalnız `local_grievance` ve `perf` ağırlığıdır. `srule[a](h)` hane niteliklerinden (kiracı/mülk sahibi, gelir bandı, yaş bandı, hizmet erişimi) eksen konumuna veri tablosudur (ÇM; içerik AÇIK siyasi ideoloji kararı değildir, yalnız türetme mekaniğidir; ilk tablo nötr/sıfır olabilir). `stance` her `bloc_rederive_days`ta yeniden türetilir; yaşanmış deneyimden kayma (`stance_drift`) varsayılan 0'dır (parametre). Aynı kural aktörler için: `stance` aktör verisinde sabit başlar (§3.1).
Satisfaction defteri seçime girer: `perf(b,p)` (politics-elections §4) `satisfaction{topic}` ve `grievances{topic}` defterlerini ayrı ayrı, `priorities` ağırlığıyla okur; olumlu iş oya dönüşür.
Kesim yalnız sayı grubu değil, konum ve öncelik taşır; bu yüzden aynı karar farklı kesimlerde zıt işaret üretir (destek + protesto aynı anda, SIM-05).

## 7. Veri şemaları (simulation-engineer için; hepsi yer tutucu)
Konum: `data/actors/` (hat `actors`). Alan adları İngilizce; metinler `loc.*` anahtarı.
```jsonc
// data/actors/roster_m2.json
{ "schema": 1, "campaign_template": "m2_test",
  "actors": [
    { "key": "actor.protagonist", "kind": "protagonist", "name_key": "loc.actor.protagonist.name",
      "profile_slots": [] },
    { "key": "actor.council.1", "kind": "council", "name_key": "loc.actor.council.1.name",
      "traits": {"self_interest": 500, "public_spirit": 500, "partisanship": 400, "integrity": 600, "volatility": 300},
      "stance": {"growth_vs_preservation": 0, "public_investment_vs_market": 0, "centralism_vs_localism": 0},
      "salience": {"housing_cost": 500, "mobility": 500, "fiscal_burden": 500},
      "constituency_blocs": ["actor.bloc.1"], "party_key": null },
    { "key": "actor.media.1", "kind": "media", "name_key": "loc.actor.media.1.name",
      "traits": {"combativeness": 500, "volatility": 300, "integrity": 600},
      "lean": {"growth_vs_preservation": 0}, "sensationalism": 400, "credibility": 600,
      "reach": {"actor.bloc.1": 600, "actor.bloc.2": 600} }
  ] }

// data/actors/relations_init.json  (başlangıç önsel ilişki; yoksa trust0 = 0, resentment = 0)
{ "schema": 1, "default": {"trust": 0, "resentment": 0, "obligation": 0, "familiarity": 200},
  "overrides": [ {"from": "actor.council.1", "to": "actor.protagonist", "trust": 100} ] }

// data/actors/memory_params.json
{ "schema": 1, "k_gain": 400, "loss_aversion": 2000, "k_resent": 500, "k_forgive": 250,
  "scar_frac": 300, "half_life_days": {"trust": 360, "resentment": 900, "memory_short": 90, "memory_long": 720},
  "K_mem": 32, "spill_frac": 150, "spill_delay_days": 14 }     // permille birimli; hepsi ÇM

// data/actors/decision_tables.json
{ "schema": 1, "decisions": {
    "council.vote": { "factors": [
        {"name": "stance_distance", "weight": 300, "trait_mod": {"partisanship": 100}},
        {"name": "bloc_pressure",   "weight": 200, "trait_mod": {"public_spirit": 150}},
        {"name": "trust_in_player", "weight": 150},
        {"name": "lobby_pressure",  "weight": 100, "trait_mod": {"self_interest": 200}} ],
      "theta": 0, "hysteresis": 30, "noise_amp": 80 },
    "bloc.react": { "tiers": [{"id": "petition", "theta": 250}, {"id": "protest", "theta": 500}, {"id": "boycott", "theta": 700}],
      "factors": [{"name": "grievance_level", "weight": 450}, {"name": "satisfaction_level", "weight": -250},
                  {"name": "media_amplification", "weight": 150}, {"name": "organizer_capacity", "weight": 100}] } } }

// Reason örneği (çalışma zamanı kaydı; ReasonRecord.to_dict() v1.0 biçimi, margin = score - threshold = -140 türetilir)
{ "id": 412, "tick": 812, "actor": "actor.council.3", "decision_key": "decision.council.vote", "outcome": "negative",
  "factors": [ {"name_key": "reason.factor.bloc_pressure", "value": -620, "weight": 400, "is_estimate": false, "source_ref": "actor.bloc.1"},
               {"name_key": "reason.factor.stance_distance", "value": 150, "weight": 600, "is_estimate": false, "source_ref": ""},
               {"name_key": "reason.factor.noise", "value": 18, "weight": 1000, "is_estimate": false, "source_ref": ""} ],
  "threshold": 0, "score": -140, "scoring": "linear", "subjects": ["vote.7", "actor.bloc.1"], "parent_ids": [71, 398], "provenance": "sim" }
```
Senaryo verisi (kim kimle bağlı, başlangıç kadro) T-026'nın görevidir; bu spec yalnız şema ve yer tutucu sağlar. "Kadro" içeriği AÇIK sorularda.

## 8. M2 asgari dilim ve M4 genişleme noktaları (acceptance 4)
### 8.1 M2 asgari dilim (ROADMAP M2: "≥2 grup tepkisi + küçük meclis")
Dahil:
1. **>=2 seçmen kesimi** (`bloc.react`): en az biri etkilenen/olumsuz, biri yararlanan/olumlu tepki üretebilmeli; tepki fiziksel (protesto kalabalığı / destek) ve panelde gerekçeli.
2. **Küçük meclis** (`council.size`, ilk 5): bütçe ve imar önerisi oylaması, `council_friction` gecikmesi; parti yok, yalnız `stance` + ilişki + `bloc_pressure`.
3. **Medya tonu** (1 organ): konu başına `tone`, gecikmeli yankı, kesim tepkisini büyütür/sönümler.
4. Yatırımcı `political_risk` sinyali (T-013 faktörü).
5. Hafıza/ilişki modeli tam (§4) ama yalnız `actor.protagonist` <-> diğerleri.
6. Olaylardan M2 şablonları (political-events.md §5: `PE-01, 02, 03, 04, 07`).
Hariç: seçim, parti, rakip, söz defteri, çıkar çatışması dedikodusu, soyut metropol siyaseti (yalnız 1 komşu belediye aktörü), hikâye karakterleri.
Kabul işareti: bir imar kararı sonrası gerekçeli iki zıt kesim tepkisi + bir meclis oylaması + bir haber, nedensellik zinciri `cause_refs` ile gezilir (SIM-05, SIM-12).

### 8.2 M4 genişleme noktaları (`politics-elections.md` ile tutarlı)
| Nokta | M2'deki kanca | M4'te |
|---|---|---|
| `Party` ve `party_line` faktörü | `party_key = null`, faktör ağırlığı 0 | `parties[]` N, `party_line` aktif |
| Seçim `U(b,p)` | `bloc` zaten `priorities`, `grievances`, `trust_player` taşır | `local_grievance(b)`, `perf(b,p)` doğrudan buradan okunur |
| `PlayerRecord.media_tone` | medya organının `tone_for(b)` | seçim formülündeki `media_tone_for(b)` |
| `PlayerRecord.reputation_by_group` | `trust_in_player` toplulaştırma | itibar ekranı |
| `ally_support`, ittifak, çıkar çatışması | `obligation` alanı hazır | koalisyon pazarlığı |
| Rakip aday | `actor.rival` şeması | `rival.attack`, kampanya |
| Soyut metropol siyaseti (SIM-06) | `actor.remote.*` şeması + 1 komşu | 6 metropol çeyreklik hamle |
| Kaybetme sonucu | karar yok, `lose_consequence` kancası politics-elections'ta | AÇIK karar sonrası |
| Hikâye karakterleri | `actor.story.<n>` boş | AÇIK karar sonrası |

## 9. Oyuncu fiilleri (aktör düzeyi)
Oyuncu aktörleri doğrudan "yönetmez"; şu komutları verir (M2 alt kümesi **kalın**): **öneri sun (meclise)**, **telafi/kamulaştırmasız çözüm teklif et (kesime)**, **toplantı/dinleme oturumu (kesimle; zaman ve siyasi sermaye maliyeti)**, **medyaya yanıt ver**, ittifak/iyilik talebi (M3+), söz ver (M3+), çıkar grubuna taviz (M3+). Doğrudan oy/destek satın alma yoktur; iyilik takası `obligation` yaratır ve medya ifşa riskini artırır (M3+). Hiçbir komut özel bina yerleştirmez (CAN-03).

## 10. Geri bildirim (oyuncuya ne gösterilir)
- Dünyada: ilgili kesimin yaşadığı parsellerde kalabalık/afiş/ses (T-020/T-021 ile), meclis salonunda oy dağılımı, medya bandı.
- Panelde ("neden?" sorgusu): son N karar; her biri için `text_key` cümlesi + ilk faktörler + `cause_refs` zinciri; kesim için `grievances` konu dökümü ve en çok etkileyen karar (kaynak `source_ref`). Kesim "memnuniyet %" gösterilmez (SIM-09).
- Belirsizlik: kesim tepkisi tahmini için aralık verilebilir (politics-elections §6 ile uyumlu); sahte kesinlik yok.

## 11. Parametre tablosu (ÇM; tamamı `data/actors/*.json`)
| Parametre | Başlangıç | Gerekçe | Test fikri |
|---|---|---|---|
| `council.size` | 5 | Küçük, anlaşılır oylama; beraberlik çifte veto olmasın diye tek sayı | 3/5/7: oy dağılımı çeşitliliği |
| `k_gain`, `loss_aversion` | 400, 2.0x | Kötü hatıra iyiden hızlı birikir (siyasi gerilim) | Tek zarar + tek telafi sonrası güven farkı ölç |
| `half_life.trust` / `resentment` | 360 / 900 gün | Kırgınlık güvenden uzun yaşar | Dönemler arası hafıza etkisi |
| `scar_frac` | 0.30 | Telafi her şeyi silmesin | Tekrarlayan zararda taban |
| `K_mem` | 32 | Sınırlı bellek, belirlenimli birleştirme | Bellek taşma testi |
| `spill_frac` | 0.15 | Dedikodu etkisi küçük ve tek sıçrama | Salınım yok testi |
| `noise_amp` | 80 | Küçük sürpriz | Tohum süpürmesi |
| `hysteresis` | 30 | Ping-pong oy yok | Art arda karar dalgalanma sayısı |
| `react_trigger_min` | 100 | Küçük etki tepki yaratmasın | Eşik süpürmesi |
| `reason.top_n` | 3 | Panel okunabilirliği | Okuma testi (§12 H1) |
| `min_bloc_size` | veri (nüfusa göre) | Çok küçük kesim gürültü | Kesim sayısı vs oturum başarısı |
| `bloc_rederive_days` | 90 | Kimlik sürekliliği | id değişim oranı |
| `k_media`, `media_lag_days` | 0.5, 7 | Medya büyütür ama belirleyici değil | Medya kapalı/açık A/B |

## 12. Kabul ölçütleri ve senaryolar
Pozitif:
- **S-P1 (zincir):** Aynı seed, aynı komut dizisi: yoğunlaştırıcı imar kararı sonrası kesim A `protest` basamağına çıkar, kesim B `satisfaction` artar; her ikisi için `Reason` kaydı, `cause_refs` ile imar kararına ve yatırım kararına bağlı (SIM-05, SIM-12).
- **S-P2 (farklılaşma):** Aynı T0, iki farklı komut dizisi -> en az 3 kesimde `grievances`/`trust` vektörü anlamlı ayrışır (SIM-10, SIM-11).
- **S-P3 (onarım):** Zarar sonrası telafi -> güven `scar_floor`a kadar toparlanır, daha fazla değil.
Negatif/kenar:
- **S-N1:** `trust` -1000 ve `resentment` 1000'de bir meclis üyesi bile geçerli bir `Reason` üretir ve karar alanında kalır (taşma yok).
- **S-N2:** Sıfır kesim, tek meclis üyesi, eşit oy, `party_key=null`, boş `profile_slots`, olmayan `name_key` ile çökme yok; eksik anahtar uyarı + `[?]` görünümü.
- **S-N3:** Kodda `actor.*` anahtarı veya ad mantığa girer (tarama testi başarısız olmalı); eski POC adı bulunmaz (tarama testi).
- **S-N4:** Oyuncu yalnız en büyük kesimi memnun eder -> diğer kesimlerin `grievances` birikimi sonunda tepki basamağını tetikler (dejenere strateji sürdürülemez).
- Determinizm: aynı seed + komut günlüğü = aynı `Reason` dizisi; kaydet->yükle->N tick hash eşit (TEK-01/02).
- Gerekçesiz karar uygulanmaz; testte sahte/tek faktörlü karar reddedilir.

## 13. Ölçülebilir playtest hipotezleri
| ID | Hipotez | Ölçüt |
|---|---|---|
| H1 | Oyuncu gerekçe panelinden protestonun nedenini okuyabilir (SIM-12) | >=80% test katılımcısı 30 sn içinde doğru ilk nedeni söyler; yanlış okuma oranı <10% |
| H2 | Tek faktör baskın değil | Hiçbir faktör, kararların >%60'ında |katkı| payının >%60'ını almaz (baskın faktör taraması) |
| H3 | Meclis ne ezici ne tıkayıcı | Oyuncu önerilerinin geçme oranı %40-75; ortalama gecikme <= `council_friction` x beklenen |
| H4 | Zarar-telafi asimetrisi okunur | Telafi sonrası güven geri kazanımı, kaybın %30-70'i arasında (2 oyun-yılı) |
| H5 | Medya anlamlı ama baskın değil | Medya kapalı vs açık A/B: protesto olasılığı farkı %10-35 |
| H6 | Hikâyeler farklı | 5 oyuncu/seed: ilk 10 tetiklenen aktör kararının dizisinin ikili örtüşmesi <%50 |
| H7 | Kesim memnuniyeti tek sayıya indirgenmeden anlaşılır | Katılımcıların >=%70'i "kim neden öfkeli" sorusuna panelle cevap verir |
| H8 | Tepki gecikmesi öğrenilir | 3. denemede katılımcı tepkiyi doğru tahmin eder (>=%60) |
| H9 | Ölü uç yok | En kötü durumda bile >=1 telafi seçeneği mevcut (otomatik tarama %100) |
Hipotezler yanlışlanabilir; sonuçlar T-017/T-026 sonrası `production/qa/` altında kaydedilir.

## 14. AÇIK SORULAR (kullanıcıya gruplanmış; koordinatör QUESTIONS.md'ye işler)
Hiçbiri kanonlaştırılmadı; `design/decisions/` yazılmadı. "Beklerken" = stüdyonun yapılandırılabilir ilerleyişi.
| Taslak | Soru | Neden gerekli | Seçenekler | Öneri | Beklerken stüdyo ne yapar |
|---|---|---|---|---|---|
| AS-1 | Protagonistin adı, geçmişi, görünümü; ilk açılışta özelleştirme var mı? | Yerelleştirme, diyalog, görünüm, ilişki başlangıçları | A) sabit ad+geçmiş B) sabit ad, seçilebilir geçmiş C) oyuncu adlandırır | Karar yok; yalnız B/C'nin sonraya sığması önemli | `actor.protagonist`, `[YER TUTUCU]`, `profile_slots=[]` |
| AS-2 | Partiler: sayı, ad, ideoloji, oyuncu hangi partiden? | M4 seçim, `party_line`, ittifak | A) 2 B) 3+ C) bağımsız adaylık da | Veriden N; karar M4 öncesi | `party.a`, `party.b`, ideoloji boş; M2'de parti yok |
| AS-3 | Rakipler ve diğer 6 metropolün liderleri, hikâye karakterleri: önceden yazılı kadro mu, sistem üretimi mi? | SIM-11 (sistemden doğan hikâye) ile tarihî yazım dengesi | A) tamamen üretimli B) üretimli + az sayıda yazılı C) yazılı kadro | B; kadro kullanıcıdan | `actor.rival/remote/story` şema + yer tutucu üretici |
| AS-4 | Seçim takvimi ve başlangıç modu (adaylıkla mı, görev başında mı) | Kampanya akışı, oyuncunun ilk aylarındaki baskı | politics-elections `start_mode` | karar M4 öncesi | `start_mode` parametresi; M2'de seçim yok |
| AS-5 | Kaybetme sonucu: kampanya biter mi, muhalefet dönemi mi, geri dönüş mü | CAN-10 anlamlı sonuç; sicil/ilişki kalıcılığı | A) son B) muhalefet C) hibrit | C ama kullanıcıya ait | `lose_consequence` kancası; `defeated` durumu |
| AS-6 | Tonlama sınırları: yolsuzluk, tehdit, şiddet, taciz, etnik/dinsel konular, gerçek siyasi figürlere benzerlik | Olay içeriği, yaş derecelendirmesi, T-026 metinleri | A) ılımlı kurumsal B) gerçekçi sert C) satirik | A ile başla | `content.tone_profile`, olaylarda `tone_tags`; yasak liste kullanıcıdan |
| AS-7 | Medya organları: kaç yerel/ulusal organ var, çizgileri (`lean`) nasıl dağılır? (F01 "bağımsız ulusal medya" der: bağımsızlık kanonik çerçevedir; devlet medyası seçeneği bu çerçeveyle çelişebilir ve bu soruya sokulmaz, çelişirse ayrı soru olarak sorulur) | Medya tonu etkisi ve haber dengesi | A) tek yerel B) 2-3 çizgi (yerel) C) ulusal bağımsız + yerel | Veri N | 1 organ yer tutucu; `media` yalnız bağımsız organ olarak modellenir |
| AS-8 | Meclis kuralları: üye seçimi, oy usulü, başkanın veto/kararname yetkisi | `council.vote` mekaniği, `council_friction` | politics-elections AÇIK | Hukuk tablosu istenmez; oynanış sınırı yeter | 5 üye, salt çoğunluk, veri |
| AS-9 | Olay dengesi: sistemden doğan vs yazılı olay oranı | SIM-11; üretim maliyeti | A) %100 sistem B) çoğu sistem + az "tohum" olay | A/B | Yalnız sistem tetikli şablonlar |
| AS-10 | Çıkar çatışması mekaniğinin **varlığı** soru değildir: F03 mod 3 ve CAN-06 ("çıkar çatışması") bunu zaten kapsar. AÇIK olan yalnız **sunum, ceza şiddeti ve ton**: iddia nasıl sahnelenir (haber bandı / açık ifşa), sonuçları ne kadar ağırdır (güven kaybı mı, görevden alma mı), yolsuzluk teması hangi tonda işlenir | Tonlama (AS-6 ile birlikte), yaş derecelendirmesi, PE-05 metinleri | A) yalnız risk/dedikodu düzeyi (ılımlı) B) açık ifşa + sonuç C) satirik | Kullanıcı; A ile başla | Mekanik veri olarak vardır (`obligation`, PE-05 şablonu M3); `tone_tags:["corruption"]` taşır ve varsayılan `tone_profile`'da KAPALI (çıktıya çıkmaz); sunum/ceza parametreleri veri |

## 15. Riskler ve notlar
- Aşırı model: ilişki+hafıza+medya+kesim birlikte pahalı olabilir. Sınırlar: `K_mem`, LOD, haftalık döngü. Önce yalnız 2 kesim + 5 meclis + 1 medya ile ölçülür.
- Salınım: tepki-medya-kesim döngüsü pozitif geri besleme (öfke -> haber -> öfke). Kırıcılar: üstel çürüme, `media_lag`, tek sıçrama dedikodu, `amp` tavanı, histerez.
- Dengeli geri besleme: sürekli şikâyet birikimi kendi içinde tükenmez; telafi seçenekleri ve `half_life` bunu sağlar.
- Hata spirali: oyuncunun tüm aktörlerin güvenini kaybetmesi -> en az bir "yeniden başlangıç" yolu (dinleme oturumu, küçük görünür iş) her zaman bulunur (H9).
- Tasarım hatası: `trust` ile `resentment` ayrımı kaybolursa özür/telafi anlamsızlaşır; ayrı tutulmalı.

## 16. Canon check özeti
```
CANON CHECK — characters-npc.md (T-015)
Verdict: CLEAR WITH CONDITIONS
Touches: CAN-02, CAN-06, CAN-07, CAN-09, CAN-10, CAN-11, SIM-05, SIM-09, SIM-10, SIM-11, SIM-12, WLD-11
- [KANONİK] aynı erkek protagonist — F01/F05-A — ok (cinsiyet dışında hiçbir özellik kanonlaştırılmadı)
- [AÇIK] protagonist adı/geçmişi, parti, rakip, takvim, kaybetme, tonlama — F05-D — yer tutucu + veri + soru
- [ÇM] tüm eşik/katsayı/özellik/konu/eksen listeleri — F03 "Statü: çalışma önerisi" — ayarlanabilir
- [OY] SIM-09 tek skor yok — kesim/aktör bazlı sicil
- [TEKNİK] permille tamsayı, tohumlu akışlar — ADR-0002
Questions added: AS-1..AS-10 taslak (koordinatör işler)
Safe to proceed with: T-016 (şema/karar çatısı), T-017 (M2 dilimi), T-026 (yer tutucu profil/diyalog iskeleti)
```

## 17. Hat arası uyumsuzluk / uyum notları (koordinatöre)
1. `src/contracts/` artık var; `reason_record.gd` v1.0 okundu ve §6.2'de eşlendi (hizalama doğrulandı: kod okuma düzeyinde; çalışan sim kaydıyla test T-016/T-027 işi, test edilmemiş). `src/contracts/` değiştirilmedi.
2. Eşlenemeyenler (v1.1 TEKNİK istekleri) §6.2'de (a)-(e): sistem sözde aktörü, `delayed/partial` nüansı, serbest `args`, basamaklı eşik, `campaign_id`. `outcome`, `cause_refs`, `id`, `text_key` artık sorun değil: sırasıyla `outcome`, `parent_ids`, `id`, türetilen anahtar.
3. Puan semantiği: sözleşme normalize edilmemiş doğrusal toplamdır; üretici ağırlıkları normalize edip gürültüyü faktör yapar (§6.2). Sim uygulayıcısı bunu yapmazsa `is_consistent()` kırılır.
4. Sayı tipi: sözleşme de tamsayı sabit noktalıdır (`FIXED_SCALE` 1000), spec permille ile uyumlu; önceki "float riski" notu kalktı.
5. `GroupReactionView`/`CouncilView` alanları (bloc: `size, grievances, satisfaction, tier`; council: `votes[{actor, outcome, reason_id}], margin, delay_days`) dosyaları mevcut; alan düzeyi karşılaştırma yapılmadı (test edilmemiş), UX/sim hattı teyit etmeli.
