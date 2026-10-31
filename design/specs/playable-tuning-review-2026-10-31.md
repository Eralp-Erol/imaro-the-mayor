# Oynanabilir çalışma değerleri incelemesi · 2026-10-31

Statü: **ÇALIŞMA MODELİ** (sistem tasarımı incelemesi; değer değişikliği UYGULANMADI, yalnız öneri). Kod, `data/` ve `design/foundation/` değişmedi.
REQ: CAN-03, CAN-04, CAN-05, CAN-06, SIM-05, SIM-07, SIM-08, SIM-09, SIM-10, SIM-12. Kararlar: D-008, D-009, D-010, D-011. Açık: Q-003, Q-014 (ayrıntılar), Q-016, Q-017 (ayrıntılar), Q-025.
Kaynak: bu belge yalnız okunan belgelere dayanır; kod koşturulmadı. Ölçüm = görevde verilen ve `production/log/2026-10-31-*.md` içinde okunan sayılar.

## 0. Hedef deneyim ve tek cümlelik sonuç

Sahip ilk 5 dakikada yol çizer, yatırımcı bina yapar, halk tepki verir (D-008); binalı arsadan geçen yol bina yıkar ve geri alınır (D-011).
**Sonuç:** "yol -> kapasite -> bina" halkası ölçülmüş ve okunur (yalnız yol = 0 bina, yalnız plan = 0 bina, 248 m yol = 7 bina). "Halk tepki versin" halkası ise **gerçek dünyada hiç ölçülmedi**; tepki yalnız kamulaştırma yolunda var ve eşikleri sentetik testlerden geliyor. Ayrıca büyük planın meclis yolu, ölçülen 12/66 gün sayısını **bozabilir** (bkz. §2 satır 7, §3 öneri 1).

## 1. Durum tablosu (ne ölçüldü, ne değil)

| Halka | Durum | Kanıt |
|---|---|---|
| Yol -> kapasite (yol N birim, N birimlik proje sığar) | ölçüldü, D2, tohum 1467 | `yol-altyapi-kapasitesi`: yalnız plan 0, yalnız yol 0 |
| Plan -> ilk inşaat 12 gün, ilk bina 66 gün (12 parsel, 108 m yol) | ölçüldü AMA meclis eşiğinden ÖNCE | `T-043B-gercek-dunya-olcumu` (plan 3 günde yürürlük); eşik sonra geldi (`plan-meclis-esigi`: gerçek dünyada büyük plan -> meclis uçtan uca oynanmadı) |
| Halk tepkisi, kamulaştırmasız yol+plan | ölçüldü: **sessiz** (400 gün, 0 tepki) | `altyapi-siyaset-yan-etkisi` §5, Q-025 |
| Halk tepkisi, kamulaştırmalı yol | **gerçek dünyada ölçülmedi** | `T-042b-sim-adimi` yalnız sentetik/fixture; UI logu "gerçek bağdaştırıcı yok" diyor |
| İnsanla his testi (core-loop-v0 §6 gözlem 1-7) | **hiç yapılmadı** | `core-loop-v0` §6 durum satırı |

## 2. Çalışma değerleri

Etki: + iyi, ~ nötr/belirsiz, - kötü. Karar: **K** = kullanıcı kararı gerekir, **M** = mühendis kararı yeter.

| # | Değer | Nerede | Neden böyle | İlk 5 dk etkisi | Risk | Karar |
|---|---|---|---|---|---|---|
| 1 | `infra_free_units_max` 0 (+1 birim pay), `infra_headroom_pm` 300 | `playable_economy.json` | %30 pay yolun 10 birimlik etkisini gizliyordu; 0 = bölge dolu, yatırım için yol şart (D-009) | + yol görünür neden olur: yalnız plan 0 bina, yalnız yol 0 bina. | Yolsuz hiçbir bölge büyümez: "yaşayan dünya" donukluğu (core-loop-v0 §risk 2). Oran ~%99,9 olduğundan altyapıyı okuyan her sistem (meclis gerçekçiliği, §7) uç değer görür. | **K** (oyunun "kural"ı: yol şart mı?) D-009 buna yakın; sayı kısmı M |
| 2 | `infra_units_per_km` 100 (`local`) | `road_works.json` | 1 birim = 1 konut/ticaret birimi; ölçek ekonomiyle aynı | ~ 108 m = 10 birim = **3 bina**; 12 parselin planı 51 birim: 9 parsel "altyapı doldu" ile reddedilir. 248 m = 7 bina. Oyuncu "yol uzat = daha çok bina"yı öğrenir (+), ama kısa ilk yolda 12 parsel planı çoğunlukla ret görür (SIM-07 başarısızlığı okunur ama hayal kırıklığı riski) | Tek sınıf (`local`), maliyet yok -> uzun yol bedava = baskın strateji; oyuncu "en uzun yol" çizer | M (sayı), maliyet bağı **K** (Q-003 AÇIK) |
| 3 | `infra_bonus_max` 0, `base_threshold` 300 | `playable_economy.json` decision | Kapasite bonusu orana bağlı, binlerce birimde 0'a yuvarlanıyordu; altyapı yalnız sığar/sığmaz kapısı | + Ret gerekçesi tek ve okunur (`infrastructure_exhausted` + yol komutu). - Kapasite "az dar/çok dar" ayrımı yok | Bonus kapalı = altyapının skor etkisi sıfır; ileride kapasite bonusu istenirse sim varsayılanıyla kopar | M |
| 4 | `latent_demand_pm` 250 | `playable_economy.json` | Gizli hane talebi T0 stoğundan | ~ Ret nedenlerinden "talep" bu değere bağlı; ölçümde 12 parselden 12 inşaat başladı (talep engel olmadı) | Düşük sayıda ret = "hep onay" (core-loop-v0 §6 gözlem 3 "hep hepsi onay" kalma ölçütü); tohum 2 ve 3'te de 3 bina: **sapma kanıtlanmadı** (SIM-10) | M |
| 5 | `max_reviews_per_tick` 8 | `playable_economy.json` | Kare bütçesi (sim varsayılanı 60 tick'te 17 ms, 8'de 4,3 ms); "denge kararı DEĞİL" | ~ Günde ~8 karar; sonuç: onay 105 -> 69, ret %95-98 | Denge değeri performans gerekçesiyle seçildi; ileride sessizce denge etkisi kalır | M (ama "performans değeri" olarak ayrı etiketli kalmalı) |
| 6 | `priority_radius_m` 150, `priority_max_parcels` 12, `attention_delay_days` 2 | `playable_economy.json` | Yol/plan sonrası yakın parsellerin hızlı değerlendirmesi (D-010 Soru 1) | + İlk inşaat 12 gün (= plan 10 + dikkat 2), ilk bina 66 gün (= 12 + 45 + 3 x ~3 birim); 4 gün/sn'de 3 sn / 16,5 sn: hedef (<=40 / <=100 gün, ~25 sn) içinde | 12 parsel üst sınırı = 12 parselden fazla plan hızlı kuyruğa girmez; 30 parsellik planda son bina gün 87 | M |
| 7 | `plan_council_min_parcels` 10, `plan_council_min_units` 40 (+ `council.json`: oturum 14 gün, min öncü 3, sürtünme 3, eşitlik = ret) | `playable_politics.json` | D-011 Soru 4: "ikisi de, seçenek" -> küçük doğrudan, büyük meclise; eşik kullanıcı vermedi | **-- Ölçülen 12 parsellik plan (51 birim) artık meclise gider**: oylama beklemesi ~3-17 gün + 3 sürtünme ekler (hipotez: 66 -> ~70-86 gün), eşitlikte ret, 5 üyeli yer tutucu meclis. | **Hipotez, ölçülmedi:** meclis uygulanabilirliği altyapı yükünden okur (`realism` lo 600, hi 1000 -> +1000..-1000); bölge ~%99,9 dolu iken (satır 1) büyük planın oy skoru en kötü uca düşebilir -> ilk planın reddi olası. Bu "başarısızlık" okunur olabilir ama ilk 5 dk'yı kırar. | Eşik sayısı **M** (kanon değil); "büyük plan ilk dakikada ret yiyebilir mi" **K** |
| 8 | `blocs_grievance_rule_overrides`: `infra_stress` lo 1000, hi 1300 | `playable_politics.json` | Sim varsayılanı (lo 500) dolu-ama-sığan bölgede oyuncu hiçbir şey yapmadan şikâyeti 1000'e doyuruyordu (sahte tepki, yanlış `cause_refs`) | + Sahte tepki gitti (SIM-12). - Bunun yan etkisi: kamulaştırmasız yol+plan akışında tepki 0 (400 gün) | D-008 üçüncü adımı bu veride kamulaştırmaya bağlı kaldı | Etkisi **K** (Q-025 kartı); sayı M |
| 9 | `expropriation_margin_m` 3,0; `proximity_radius_m` 60; `protect_heritage` true; `household_fate` return_to_latent | `network.json`, `road_works.json` | Kenar payı: yol ekseni <= yarı genişlik + 3 m ise parsel BÜTÜNÜYLE alınır (köşesi kesilen de); tarihî yapı korunur (kart açıklaması) | ~ Kaç bina yıkılır = geometri; D2'de tipik 108 m yolda gerçek sayı **ölçülmedi**. Önizleme "N bina, M hane" gösteriyor (UI logu) | Kısmi kamulaştırma yok: köşe kesilince bütün bina gider -> beklenmedik büyük yıkım ("neden bu?"). 60 m yakınlık yarıçapı D2 sokak dokusunda kaç haneyi kapsar bilinmiyor. `return_to_latent`: hane kaybolmaz, talebe döner -> yıkımın ekonomik bedeli düşük, Q-017 AÇIK | Yarıçap/marj **M**; `household_fate` ve "köşe kesilince bütün parsel" **K** (Q-017) |
| 10 | Tepki ağırlıkları: neden 700 (yerinden edilme) / 300 (yakınlık); `window_days` 360; şikâyet kuralları `displacement` lo 10, hi 150, gain 400 (barınan) / 300 (arayan); `proximity` lo 5, hi 100, gain 200; `reaction_keep_days` 720 | `reactions.json` | D-011 Soru 3: esas yerinden edilme, yakınlar daha hafif | + Sıralama kullanıcı sözüyle uyumlu (yerinden edilme > yakınlık). 360 gün solma = 4 gün/sn'de 90 sn: tepki 5 dk içinde görünür kalır (hipotez) | Sinyal = hane x 1000 / **bölge hanesi**: büyük bölgede az sayıda yıkım payı eşiğin altında kalır (barınan eşik lo 10 pm = %1). Sessizlik şu an "kamulaştırmasız" için kanıtlı; "kamulaştırmalı" için kanıtsız. | Ağırlık sırası **K'ya bağlı kalır** (kullanıcı verdi); sayılar M |
| 11 | Gündem eşiği `min_displacement_pm` 20, `full` 100; şablon PE-01 | `reactions.json` | Yerinden edilme dolaylı değil doğrudan neden: tepki basamağı aranmadan gündem açılır | + Nedenli gündem öğesi mümkün (core-loop-v0 §6 gözlem 4). | **D2'de 20 pm = bölge hanesinin %2'si** (hipotez: yük 9316 birim; hane sayısı bilinmiyor, 20 pm ~ yüzlerce hane = onlarca bina olabilir) -> küçük/orta bir yıkım gündem açmayabilir. Ölçülmedi. | M (ölçümden sonra) |
| 12 | Pay eşiği `min_share_pm` 100 (sim varsayılanı, değişmedi) | `blocs.json` | Kesim sinyali yalnız bölge payı >= %10 olan bölgelerden gelir | - D2 barınan payı ~%7,5 (yaklaşık, koddan çıkarım): inşaat baskısı hiçbir kesime ulaşmaz (`max_construction_burden_signal` 0) | "Bina çıktı" tepkisi D2'de yapısal olarak yok | **K** (Q-025: bina tepkisi isteniyor mu?) |
| 13 | Yol maliyeti "henüz kurulmadı" (`cost.available` false) | `road_works.json` | Q-003 AÇIK, T-014/T-043C göstergesi | ~ Yol bedava -> kısıt yok; tek fren altyapı ve kamulaştırma tepkisi | Sınırsız yol çizme baskın strateji; SIM-07 "kötü kararın sonucu" yalnız siyasi | **K** (Q-003, para birimi AÇIK; gösterge bütçe D-010 Soru 3 ile verildi) |

## 3. Öneriler (en çok 5; hiçbiri uygulanmadı)

| # | Öneri | Gerekçe | Doğrulama (hangi ölçümle) |
|---|---|---|---|
| 1 | **Önce ölç, sonra değiştir:** gerçek Ismeral D2'de, meclis eşiği açıkken, 12 parsellik plan + 108 m yol senaryosunu 5 sim tohumunda koştur; "plan karar günü, oylama sonucu, ilk inşaat/ilk bina günü" yaz. Sonuç ret/yavaşsa seçenekler: (a) eşiği yükselt (örn. parsel 16 / birim 80, ilk tipik plan doğrudan kalsın), (b) meclis uygulanabilirliğinde "bölge dolu ama sığıyor" durumunu nötr say (kod değişikliği), (c) olduğu gibi bırak ve kullanıcıya kartla sor. | Ölçülen 12/66 değerleri eşikten önceydi; meclis yolu gerçek dünyada oynanmadı | Probe: `t043b_real_world_probe` benzeri, çıktı = oylama sonucu + gün sayıları, 5 tohum; kabul: tipik ilk plan <=100 gün ilk bina VEYA ret gerekçesi görünür |
| 2 | **Kamulaştırmalı yolu D2'de ölç:** 108 m yolu yapılı bloktan geçir; yıkılan bina, yerinden edilen hane, `displacement`/`proximity` pm, gündem açıldı mı (20 pm eşiği), ilk tepki günü. Sonra `min_displacement_pm`/lo-hi karar ver. | D-008 üçüncü adımı ve D-011 şu an yalnız sentetik testte; satır 10-11 kanıtsız | Probe çıktısı tablosu (3 yol, 3 tohum); kabul: bir yıkımlı yol 5 dk (~1200 oyun günü, 4 gün/sn) içinde en az 1 nedenli gündem öğesi VEYA sessizliğin sayısal gerekçesi |
| 3 | **İlk yolun bina sayısını okunur kıl, `infra_free_units_max` 0'da kal:** değeri değiştirme; önerilen yol: yol önizlemesi "bu yol N birimlik proje sığdırır (~3 bina)" desin (UI), plan önizlemesi "altyapı X birim, sığar/sığmaz" desin. Alternatif (kullanıcı isterse): küçük pozitif başlangıç boş kapasite (örn. 20-30 birim) ile ilk yol daha çok bina verir. | 108 m = 3 bina, 12 parselden 9 ret; nedeni okunur ama his testi yok | İnsan testi: gözlem 1 ve 6 (>=4/5 ilk 90 sn'de nedeni söyler); sayısal: aynı senaryoda bina sayısı = birim/ortalama birim |
| 4 | **Kamulaştırma marjı ve kısmi alım değerlendirmesi:** `expropriation_margin_m` 3 ve "köşe kesilen bütün parsel" için D2'de örnek dağılım çıkar (kaç yol -> kaç bina); gerekirse marjı 0-1 m yap veya önizlemede kenar vakaları ayır. | Kullanıcı: "yol binanın içinden geçerse"; 3 m pay, bitişik binayı da alabilir (beklenmedik yıkım) | 30 rastgele geçerli yol çizgisi: alınan bina sayısı dağılımı, marj 0/1/3 m karşılaştırması; kabul: yıkılan bina ile oyuncunun gördüğü (önizleme) bire bir ve "yola değen ama içinden geçmeyen" bina alınmıyor |
| 5 | **Tepkisizliği karar kartına bağla:** Q-025 (A sessiz / B bina tepkisi / C yol-plan kararına tepki / D eski) hâlâ AÇIK; D-011 Soru 3 yalnız yerinden edilme + yakınlık kapsadı. İnşaat tepkisi (satır 12) kullanıcıya sorulmadan `min_share_pm` düşürülmesin. | Sahte tepki yok (SIM-12) ve bölge payı eşiği yapısal | Karardan sonra: 5 dk içinde >=1 nedenli gündem, <=2 kesinti (gözlem 4); sahte sayı yok (test: tepki=0 iken HUD'da tepki yok) |

## 4. Kanon / karar çakışması

Doğrudan çakışma **yok**. İzlenecekler:
| Konu | Not |
|---|---|
| CAN-03 (oyuncu özel bina spawn edemez) | Etkilenmiyor; yatırımcı karar verir, plan yetkisi oyuncuda. Kamulaştırma bina üretmez, yıkar |
| SIM-09 (tek popülerlik skoru yok) | Tepki kesim bazlı; öneriler tek skor eklemiyor |
| Q-017 AÇIK ayrıntılar (hane akıbeti, işletme kaybı, tazminat) | `household_fate` "bayrak/çalışma değeri"; satır 9'daki karar K'ya bağlı, uydurma yok |
| Q-003 (para birimi) | Yol maliyeti uydurulmuyor; satır 13 |
| Q-014 (meclis usulü) | D-011 yanıtladı ama eşik/usul kullanıcı tarafından verilmedi; satır 7 çalışma değeri |
| Hız hedefi (D-010: ~40/~100 gün) | Ölçülen 12/66 hedefin içinde, ama meclis yolu hesapta yoktu |

## 5. Doğrulanmış / varsayılan / test edilmemiş

- **Doğrulanmış (belgelerden okundu):** JSON değerleri (`playable_economy`, `playable_politics`, `reactions`, `road_works`, `council`), yukarıdaki ölçümler (12/66 gün, 3 ve 7 bina, 0 tepki 400 gün, eşik 10/40, 51 birim = 12 parsel), D-008..D-011 metinleri, Q-025 durumu.
- **Varsayılan (hipotez):** meclisin `realism` ile yüksek doluluklu bölgede büyük planı reddedeceği ve gecikme aralığı; D2'de 20 pm eşiğinin kaç haneye denk geldiği; 360 gün solmanın 90 sn'ye çevrilmesi (4 gün/sn); 108 m yolun D2'de hiç binalı arsadan geçip geçmediği.
- **Test edilmemiş:** insan his testi; kamulaştırmalı yolun gerçek dünyada tepkisi; büyük plan -> meclis gerçek dünyada; diğer tohum ve bölgeler (D1, D6); kod çalıştırılmadı.

## 6. Sahibe sorulacak kararlar (en çok 3; kullanıcı adına karar yazılmadı)

**Kart 1 · İlk büyük imar planın meclise gitsin mi?** (satır 7)
- A) **Önerilen:** İlk tipik planın (yaklaşık 12 parsel) doğrudan yürürlüğe girmesi; meclis daha büyük planlarda (eşik ölçümle belirlenir).
- B) Her plan meclise gitsin; ilk plan reddedilebilir, bu oyunun ilk dersi olsun.
- C) Şu anki gibi kalsın (10 parsel / 40 birim), önce ölçelim.

**Kart 2 · İlk yolun etkisi:** (satır 1-2)
- A) **Önerilen:** Bölge dolu kalsın, yol şart olsun; yol önizlemesi "yaklaşık kaç bina" desin.
- B) Küçük bir başlangıç boşluğu olsun, ilk yol daha çok bina getirsin.
- C) Yolsuz bölgeler de yavaş büyüsün (dünya daha canlı, yolun gücü azalır).

**Kart 3 · Yıkım yoksa halk tepkisi var mı?** (satır 12, Q-025)
- A) **Önerilen:** Yalnız yerinden edilme ve yakınlıkta tepki; yıkımsız yol sessiz kalsın, sahte tepki olmasın.
- B) Yeni bina gelince çevre tepki göstersin (gürültü, kira).
- C) Yol/plan kararının kendisine de tepki göstersin (D-011 Soru 3 son cümlesi).
