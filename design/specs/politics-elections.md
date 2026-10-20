# Siyasi katman ve seçim sistemi (M4)

Statü: ÇALIŞMA MODELİ. Hiçbir ad, süre veya katsayı kanon değildir; hepsi ayarlanabilir parametredir.
Köken: 2026-10-20 stüdyo doğrulama koşusunda (E2E-C, systems-designer) üretildi; inceleme ve açık soruların kullanıcıya sorulması M4 planlamasına (`plan-milestone M4`) ertelendi.
REQ: CAN-06, CAN-07, CAN-10, SIM-05, SIM-07, SIM-09, SIM-10, WLD-10. Dayanak: F01 "Bir kampanyanın hikâyesi", F03 mod 3 ve "Siyasi ilerleme", F05-C ve F05-D.

## 1. Amaç ve sınır
Oyuncunun fiziksel ve ekonomik kararlarının seçmen kesimlerinde farklı tepkiler doğurmasını, bunun da bir seçimle sonuçlanmasını tanımlar. F01'in gerilimini taşır: iyi yönetmek ile seçim kazanmak aynı şey mi?
Kapsam dışı: ulusal seçim ve cumhurbaşkanlığı mekaniği (final, ayrı spec), gerçek yasal yetki tablosu, meclis usulleri.

## 2. Bu spec'in bilerek SABİTLEMEDİĞİ şeyler (F05-D, AÇIK)
| Brif talebi | Durum | Kaynak |
|---|---|---|
| İki partinin adı ve ideolojisi | AÇIK. Uydurulmaz. | F01 "Devlet ve toplum" ("partilerin adları... henüz uydurulmayacak"); F05-D |
| Parti sayısının iki olması | AÇIK. Veri `parties[]` listesidir, N parametredir. | F05-D "Partiler" |
| Seçim aralığı ("kaç yılda bir") | AÇIK. `T_elec` parametre. | F03 "Statü: çalışma önerisi" ("seçim sıklığı kesinleşmedi"); F05-C |
| Oyuncunun hangi partiden aday olduğu (ve bağımsız adaylık) | AÇIK. `player_party_id` oyuncu seçimi/veri ve **boş (null) olabilir** = bağımsız adaylık (characters-npc AS-2 seçenek C). Boşken oyuncu kendi `platform` vektörüyle tek kişilik bir `Candidate` olarak oy pusulasına girer (`party_id = null`); sistem hiçbir yerde `player_party_id != null` varsaymaz. | F05-D |
| Oyun adayla mı yoksa yeni seçilmiş başkanla mı açılır | AÇIK. `start_mode` ∈ {campaign, in_office, both}. | F05-D "Başlangıç seçimi" |
| Seçim kanunu, kaybetme sonrası kariyer | AÇIK. Yalnızca arayüz/kanca bırakılır. | F05-D, F01 (kaybetme sonucu "detaylandırılmadı") |

Kesinleşen yalnızca KANONİK/OY çerçevedir: aynı erkek protagonist (CAN-07), tek "Mutluluk %" yok (SIM-09), kaybedilen seçimin anlamlı sonucu olmalı (CAN-10), farklı oyuncular farklı sonuçlara varabilmeli (SIM-10).

## 3. Varlıklar ve durum
- `Candidate` (oy pusulasındaki varlık): `id`, `party_id` (null olabilir: bağımsız), `platform`. Oyuncu adayı için `party_id = player_party_id` (boş olabilir).
- `Party`: `id`, `display_name` (yer tutucu: "Parti A/B", yerelleştirme anahtarından gelir), `platform` = {eksen -> konum} vektörü. Eksenler AÇIK; ilk set önerisi (ÇM): `growth_vs_preservation`, `public_investment_vs_market`, `centralism_vs_localism` (tanımlayıcılar İngilizce; görünen metin `loc.axis.<id>.name` anahtarından, characters-npc §3.3). Aşağıdaki formüllerde `p`, `Candidate`'i belirtir (parti yoksa adayın kendi `platform`'u).
- `VoterBloc` (SIM-01 hanelerinden türetilir, bölge x gelir x yaş x hizmet erişimi): `size`, `stance{eksen: konum}` (kesimin eksen konumu, characters-npc §6.6), `priorities{konu: ağırlık}` (= `salience`, konu duyarlılığı; eksen konumu DEĞİLDİR), `grievances{konu}` ve `satisfaction{konu}` (ayrı defterler), `trust_player`.
- `PlayerRecord` (sicil; tek skor değil): ayrı ayrı tutulan göstergeler: `delivery` (söz/proje), `fiscal` (bütçe sağlığı), `service` (hizmet kapasitesi), `equity` (bölgeler arası), `reputation_by_group{}`, `media_tone`, `ally_support{}`.
- `Council`: koltuk dağılımı, `player_bloc_support` (bütçe/imar oylamasında değişkendir).
- `ElectionCycle`: `next_election_tick`, `T_elec`, `state` ∈ {governing, campaign, vote, result}.
- Mülkiyet kuralı: yalnızca tek bir seçim sistemi (dosya adı teknik karar, T-017/M4) `ElectionCycle` ve sandık sonucunu yazar; diğer sistemler yalnızca `grievances`/`record` olayı yayar.

## 4. Kurallar
Zaman çıpası: simülasyon tick'i (deterministik, kare hızından bağımsız; TEK-01; [TEKNİK] ADR-0002 §4: 1 tick = 1 oyun günü). `T_elec` oyun-günü cinsindendir.

Seçim döngüsü: governing -> (T_elec - `campaign_len`) campaign -> vote -> result -> governing.

Oy kararı, kesim `b` için parti `p` (ÇM, tüm katsayılar ayarlanabilir):
```
U(b,p) = w_pol  * (1 - dist(b.stance, p.platform))      # eksen konumu vs eksen konumu, aynı uzay (-1000..1000)
       + w_perf * perf(b, p)            # iktidar adayı için sicil (olumlu + olumsuz defter), muhalefet için beklenti
       + w_loc  * local_grievance(b)    # bölgeye özgü: ulaşım, taşkın, kira, gürültü
       + w_media* media_tone_for(b)
       + w_ally * endorsements(b,p)
       + noise(seed, b)                 # deterministik tohumlu
vote_share(b,p) = softmax(U(b,p)/temp)
turnout(b) = base_turnout + k*salience(b) - k2*cynicism(b)
```
`dist(a, b)` = eksenler üzerinde |a_k - b_k| / 2000 ortalaması (eksen başına isteğe bağlı `axis_weight`, varsayılan eşit; 0..1). `priorities` konu ağırlığıdır; `dist` içinde değil, yalnız `local_grievance` ve `perf` içinde kullanılır.
`perf(b,p)` oyuncu adayı için `PlayerRecord`'dan kesime özgü okunur (ör. ulaşım mağduru kesim `service` ve `equity`'ye bakar) ve **iki ayrı defteri** birlikte taşır: `perf(b) = sum_t priorities[t] * (k_sat * satisfaction[t] - k_gri * grievances[t]) / sum_t priorities[t]` (`k_sat`, `k_gri` ÇM; defterler net edilmez). Böylece olumlu iş (iyileşen hizmet, teslim edilen proje) `satisfaction` yoluyla oya döner; yalnız şikâyet cezalandırmaz. Muhalefet adayı için `perf` = kesimin onun `platform`'una göre beklenti kestirimi (belirsizlik aralıklı). Sonuç tek skora indirgenmez; ekranda kesim bazlı döküm gösterilir (SIM-09).

Kazanma: `election.rule` parametresi belirler (varsayılan ÇM yer tutucusu: `plurality_candidate`; örnek seçenekler `runoff`, `ranked`, `party_list`). Seçim kanunu AÇIK (F05-D): formül parti çoğulluğunu sabitlemez. Aday `c` başına `tally(c) = sum_b size_b * turnout_b * vote_share(b,c)` hesaplanır, `election.rule` bunu kazanana (veya ikinci tura/sıralamaya) çevirir. Beraberlikte tohumlu sıralama. Bağımsız aday (`party_id = null`) her kuralda geçerlidir.
Kaybetme: `lose_consequence` bir kanca (AÇIK); varsayılan ÇM: oyun durumu `defeated` olur, bir sonuç ekranı gösterir, kayıt saklanır. Kampanya sonu mu, muhalefet dönemi mi kararı sorudadır.

Meclis ve ara dönem (SIM-05): bütçe ve imar kararları `Council` oylamasından geçer; `player_bloc_support` yeterli değilse karar gecikir veya kısmen uygulanır (sürtünme, yaratıcı inşayı boğmayacak şekilde `council_friction` sınırlı).

Nedensellik zinciri (F03 döngüsü): oyuncu imar/proje kararı -> yatırımcı tepkisi -> fiziksel değişim -> kira/trafik/hizmet etkisi -> `local_grievance` ve `record` güncellemesi -> kesim `U` -> seçim gündemi.

## 5. Oyuncu fiilleri
Parti platformunda pozisyon seçmek (partinin sınırları içinde; `player_party_id` boşsa — bağımsız adaylık — sınır yoktur, oyuncu kendi `platform` vektörünü seçer ve parti desteği/`party_line` etkisi olmaz, ittifak ve onay (`endorsements`) yine aranabilir), söz vermek (ölçülebilir; tutulmazsa `delivery` düşer), koalisyon/ittifak aramak, medyaya yanıt vermek, kampanya kaynağı bölgelere dağıtmak, seçimden önce popülist bir çıkış yapmak (maliyeti bütçeye gider). Doğrudan oy satın alma veya özel bina yerleştirme yoktur (CAN-03).

## 6. Oyuncuya geri bildirim
Seçime kalan süre ve aşama; kesim bazlı **konu başına** şikâyet/memnuniyet haritası (iki defter yan yana; tek skor ve toplam "memnuniyet %" yok, SIM-09) ve nedenleriyle birlikte şikâyet listesi ("X mahallesinde ulaşım şikâyeti arttı, çünkü Y hattı gecikti"); anket tahmini belirsizlik aralığıyla; seçim gecesi bölge bölge sonuç ve "neden" dökümü.

## 7. Parametre tablosu (hepsi ÇM, kanon değil)
| Parametre | Başlangıç | Gerekçe | Test fikri |
|---|---|---|---|
| `T_elec` | 4 oyun-yılı (yer tutucu) | Yer tutucu: "kampanyada 2-3 seçim oynanabilmeli" bir TASARIM VARSAYIMIDIR, kanon değil (F03 seçim sıklığını kesinleştirmedi); gerçek değer AÇIK | 2, 4, 6 ile oturum süresi ve seçim sayısı ölç |
| `campaign_len` | 0.25 x T_elec | Hazırlık penceresi | Kısa sürede oyuncu tepki verebiliyor mu |
| `w_pol, w_perf, w_loc, w_media, w_ally` | 0.30, 0.30, 0.20, 0.10, 0.10 | Hiçbir bileşen tek başına belirleyici olmamalı | Bileşenleri tek tek sıfırla; kazanan değişiyor mu (baskın yol testi) |
| `temp` | 0.5 | Düşük = keskin seçim | Sonuç duyarlılığı |
| `base_turnout` | 0.65 | Yer tutucu | Katılım aralığı |
| `council_friction` | 0.15 | Bürokrasi boğmamalı | Karar gecikme dağılımı |
| `noise` | ±0.05 | Küçük sürpriz | Tohum süpürmesi |
| `party_count` | 2 (yer tutucu) | AÇIK; "2" brif sayısıdır, kanon değil; N'e ölçeklenmeli | N=2,3 ile aynı kod |
| `election.rule` | `plurality_candidate` (yer tutucu) | Seçim kanunu AÇIK | Kuralı değiştir; kazanan hesabı koddan değil veriden değişsin |
| `player_party_id` | null (yer tutucu) | AÇIK; boş = bağımsız | null ve dolu ile aynı kod |

## 8. Kabul ölçütleri ve senaryolar
- Pozitif: iki oyuncu aynı T0'dan farklı imar kararları verir (biri yoğunlaşma, biri koruma); seçimde kesim bazlı sonuçlar anlamlı biçimde ayrışır ve her fark `local_grievance`/`record` kalemlerine izlenebilir (SIM-10).
- Negatif/başarısızlık: hizmet kapasitesini aşan yoğunluk veren oyuncu bütçe stresi ve hizmet şikâyetiyle seçimi kaybedebilir (SIM-07); `defeated` durumu tetiklenir.
- Determinizm: aynı tohum, aynı karar dizisi, kare hızından bağımsız aynı sonuç.
- Hiçbir UI veya kod yolu `Party` adını sabit string olarak içermez; ad değişince kod değişmez.
- Tek bir toplam "memnuniyet %" hiçbir yerde gösterilmez (SIM-09).
- Sahte HUD yok: gösterilen her sayı `PlayerRecord`/kesim durumundan türer.
- Rekabet/oylama kenar durumları: tek parti, sıfır kesim, eşit oy.
- Dejenere strateji testi: yalnızca en büyük kesimi memnun etmek sürdürülemez olmalı (diğer kesimlerin `grievances` birikimi, oy birikimi dengeleyici).

## 9. Açık sorular (production/QUESTIONS.md'ye koordinatör yazar)
Düzeltme (T-015): önceki metindeki "Q-005..Q-008" kimlikleri `production/QUESTIONS.md`'de yoktu (dosya yalnız Q-001..Q-004 içerir). Sorular `characters-npc.md` §14'te gruplanmış taslaklar olarak (AS-2 partiler, AS-4 seçim takvimi/başlangıç modu, AS-5 kaybetme sonucu) verilmiştir; Q numarasını koordinatör atar.

## 10. T-015 ile hizalama (düzeltme kaydı, ÇALIŞMA MODELİ)
Statü: ÇALIŞMA MODELİ. Düzeltme: önceki sürümdeki "çelişki yoktur" iddiası yanlıştı. `priorities` hem konu ağırlığı (characters-npc `salience`) hem eksen konumu olarak kullanılıyordu ve `dist(b.priorities, p.platform)` farklı uzayları karşılaştırıyordu. Çözüm: `stance` (eksen konumu) ile `priorities` (konu ağırlığı) ayrıldı (§3, §4). Aşağıdakiler kavram eşlemesidir.
- `VoterBloc` = `actor.bloc.<n>` (`characters-npc.md` §3, §6.6): `priorities` = `salience` (konu ağırlığı), `stance` = eksen konumu (characters-npc §6.6 türetir), `grievances` ve ayrı `satisfaction` defteri (ikisi de `perf` içinde okunur, §4), `memory{}` yerine toplulaştırılmış `trust_player`. `local_grievance(b)` = `sum_t priorities[t]/1000 * grievances[t]`.
- `PlayerRecord.reputation_by_group` = ilgili aktörlerin `trust_in_player` toplulaştırması; `media_tone` = medya organının `tone_for(b)` (characters-npc §6.5); `ally_support` = `obligation` + oy geçmişi.
- `Council.player_bloc_support` = önceki oturumlardaki `council.vote` sonuçlarından türeyen tahmin (alan olarak saklanmaz, hesaplanır); `council_friction` gecikmesi §6.3/political-events PE-03 ile uyumludur.
- Sayı birimi: bu belgedeki ondalık katsayılar (0.30, 0.5, ±0.05) uygulamada permille tamsayıya çevrilir (T-009 determinizm); değerler ÇM kalır.
- Parti yer tutucusu: `Party.display_name` = `party.<harf>` anahtarından yerelleştirme; "Parti A/B" metni yalnız yer tutucu görünümdür. M2'de parti yoktur (`party_key = null`).
- Başlangıç modu `start_mode` ve seçim kancaları M4'tür; M2 asgari dilimi seçim içermez (characters-npc §8).
