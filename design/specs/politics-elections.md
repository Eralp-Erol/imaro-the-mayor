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
| Oyuncunun hangi partiden aday olduğu | AÇIK. `player_party_id` oyuncu seçimi/veri. | F05-D |
| Oyun adayla mı yoksa yeni seçilmiş başkanla mı açılır | AÇIK. `start_mode` ∈ {campaign, in_office, both}. | F05-D "Başlangıç seçimi" |
| Seçim kanunu, kaybetme sonrası kariyer | AÇIK. Yalnızca arayüz/kanca bırakılır. | F05-D, F01 (kaybetme sonucu "detaylandırılmadı") |

Kesinleşen yalnızca KANONİK/OY çerçevedir: aynı erkek protagonist (CAN-07), tek "Mutluluk %" yok (SIM-09), kaybedilen seçimin anlamlı sonucu olmalı (CAN-10), farklı oyuncular farklı sonuçlara varabilmeli (SIM-10).

## 3. Varlıklar ve durum
- `Party`: `id`, `display_name` (yer tutucu: "Parti A/B", yerelleştirme anahtarından gelir), `platform` = {eksen -> konum} vektörü. Eksenler AÇIK; ilk set önerisi (ÇM): `kent_buyume_vs_koruma`, `kamu_yatirim_vs_piyasa`, `merkeziyet_vs_yerellik`.
- `VoterBloc` (SIM-01 hanelerinden türetilir, bölge x gelir x yaş x hizmet erişimi): `size`, `priorities{eksen: ağırlık}`, `grievances{}`, `memory{}`.
- `PlayerRecord` (sicil; tek skor değil): ayrı ayrı tutulan göstergeler: `delivery` (söz/proje), `fiscal` (bütçe sağlığı), `service` (hizmet kapasitesi), `equity` (bölgeler arası), `reputation_by_group{}`, `media_tone`, `ally_support{}`.
- `Council`: koltuk dağılımı, `player_bloc_support` (bütçe/imar oylamasında değişkendir).
- `ElectionCycle`: `next_election_tick`, `T_elec`, `state` ∈ {governing, campaign, vote, result}.
- Mülkiyet kuralı: yalnızca `election.gd` benzeri tek sistem `ElectionCycle` ve sandık sonucunu yazar; diğer sistemler yalnızca `grievances`/`record` olayı yayar.

## 4. Kurallar
Zaman çıpası: simülasyon tick'i (deterministik, kare hızından bağımsız, AGENTS.md). `T_elec` oyun-günü cinsindendir.

Seçim döngüsü: governing -> (T_elec - `campaign_len`) campaign -> vote -> result -> governing.

Oy kararı, kesim `b` için parti `p` (ÇM, tüm katsayılar ayarlanabilir):
```
U(b,p) = w_pol  * (1 - dist(b.priorities, p.platform))
       + w_perf * perf(b, p)            # iktidar partisi için sicil, muhalefet için beklenti
       + w_loc  * local_grievance(b)    # bölgeye özgü: ulaşım, taşkın, kira, gürültü
       + w_media* media_tone_for(b)
       + w_ally * endorsements(b,p)
       + noise(seed, b)                 # deterministik tohumlu
vote_share(b,p) = softmax(U(b,p)/temp)
turnout(b) = base_turnout + k*salience(b) - k2*cynicism(b)
```
`perf(b,p)` oyuncunun partisi için `PlayerRecord`'dan kesime özgü olarak okunur (ör. ulaşım mağduru kesim `service` ve `equity`'ye bakar). Sonuç tek skora indirgenmez; ekranda kesim bazlı döküm gösterilir (SIM-09).

Kazanma: `argmax_p sum_b size_b * turnout_b * vote_share(b,p)`. Beraberlikte tohumlu sıralama.
Kaybetme: `lose_consequence` bir kanca (AÇIK); varsayılan ÇM: oyun durumu `defeated` olur, bir sonuç ekranı gösterir, kayıt saklanır. Kampanya sonu mu, muhalefet dönemi mi kararı sorudadır.

Meclis ve ara dönem (SIM-05): bütçe ve imar kararları `Council` oylamasından geçer; `player_bloc_support` yeterli değilse karar gecikir veya kısmen uygulanır (sürtünme, yaratıcı inşayı boğmayacak şekilde `council_friction` sınırlı).

Nedensellik zinciri (F03 döngüsü): oyuncu imar/proje kararı -> yatırımcı tepkisi -> fiziksel değişim -> kira/trafik/hizmet etkisi -> `local_grievance` ve `record` güncellemesi -> kesim `U` -> seçim gündemi.

## 5. Oyuncu fiilleri
Parti platformunda pozisyon seçmek (partinin sınırları içinde), söz vermek (ölçülebilir; tutulmazsa `delivery` düşer), koalisyon/ittifak aramak, medyaya yanıt vermek, kampanya kaynağı bölgelere dağıtmak, seçimden önce popülist bir çıkış yapmak (maliyeti bütçeye gider). Doğrudan oy satın alma veya özel bina yerleştirme yoktur (CAN-03).

## 6. Oyuncuya geri bildirim
Seçime kalan süre ve aşama; kesim bazlı memnuniyet haritası ve nedenleriyle birlikte şikâyet listesi ("X mahallesinde ulaşım şikâyeti arttı, çünkü Y hattı gecikti"); anket tahmini belirsizlik aralığıyla; seçim gecesi bölge bölge sonuç ve "neden" dökümü.

## 7. Parametre tablosu (hepsi ÇM, kanon değil)
| Parametre | Başlangıç | Gerekçe | Test fikri |
|---|---|---|---|
| `T_elec` | 4 oyun-yılı (yer tutucu) | Kampanya içinde en az 2-3 seçim oynanabilmeli; gerçek değer AÇIK | 2, 4, 6 ile oturum süresi ve seçim sayısı ölç |
| `campaign_len` | 0.25 x T_elec | Hazırlık penceresi | Kısa sürede oyuncu tepki verebiliyor mu |
| `w_pol, w_perf, w_loc, w_media, w_ally` | 0.30, 0.30, 0.20, 0.10, 0.10 | Hiçbir bileşen tek başına belirleyici olmamalı | Bileşenleri tek tek sıfırla; kazanan değişiyor mu (baskın yol testi) |
| `temp` | 0.5 | Düşük = keskin seçim | Sonuç duyarlılığı |
| `base_turnout` | 0.65 | Yer tutucu | Katılım aralığı |
| `council_friction` | 0.15 | Bürokrasi boğmamalı | Karar gecikme dağılımı |
| `noise` | ±0.05 | Küçük sürpriz | Tohum süpürmesi |
| `party_count` | 2 (brif) | AÇIK; N'e ölçeklenmeli | N=2,3 ile aynı kod |

## 8. Kabul ölçütleri ve senaryolar
- Pozitif: iki oyuncu aynı T0'dan farklı imar kararları verir (biri yoğunlaşma, biri koruma); seçimde kesim bazlı sonuçlar anlamlı biçimde ayrışır ve her fark `local_grievance`/`record` kalemlerine izlenebilir (SIM-10).
- Negatif/başarısızlık: hizmet kapasitesini aşan yoğunluk veren oyuncu bütçe stresi ve hizmet şikâyetiyle seçimi kaybedebilir (SIM-07); `defeated` durumu tetiklenir.
- Determinizm: aynı tohum, aynı karar dizisi, kare hızından bağımsız aynı sonuç.
- Hiçbir UI veya kod yolu `Party` adını sabit string olarak içermez; ad değişince kod değişmez.
- Tek bir toplam "memnuniyet %" hiçbir yerde gösterilmez (SIM-09).
- Sahte HUD yok: gösterilen her sayı `PlayerRecord`/kesim durumundan türer.
- Rekabet/oylama kenar durumları: tek parti, sıfır kesim, eşit oy.
- Dejenere strateji testi: yalnızca en büyük kesimi memnun etmek sürdürülemez olmalı (diğer kesimlerin `grievances` birikimi, oy birikimi dengeleyici).

## 9. Açık sorular (production/QUESTIONS.md'ye yazılır)
Bkz. Q-005 .. Q-008 (partiler, seçim aralığı, başlangıç senaryosu, kaybetme sonucu).
