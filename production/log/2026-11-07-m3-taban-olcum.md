# T-077 · M3 taban ölçümü (qa-engineer, 2026-11-07)

Kod (`src/`, `data/`) DEĞİŞMEDİ. Eklenenler: `experiments/m3_baseline/` (betik + sarmalayıcı + özetleyici + ham JSON'lar `raw/`) ve bu rapor.
Etiketler: **[ölçüldü]** bu oturumda koşuldu, ham JSON var · **[varsayım]** · **[doğrulanmadı]**.

## 0. Tek cümle

**Donukluk SAYIYLA doğrulandı:** oyuncu yalnız D2'de oynarken 5 oyun yılında D1, D3, D4, D5, D6'da 0 yeni yatırım/inşaat/tamamlanan bina (3 sim tohumu); oyuncu girdisi yokken HİÇBİR ilçede (D2 dahil) 0. Sebep tick bütçesi değil, plan yokluğu: değerlendirme bütçesi (`max_reviews_per_tick` = 8) günlerin %99,9-100'ünde dolu ve tamamı `zoning_unplanned` reddine gidiyor.

## 1. Yöntem

- Kurulum = oyunun `_start_sim` bağı: gerçek Ismeral (dünya tohumu 1467, 40 493 parsel, D1 8 347 · D2 4 522 · D3 4 266 · D4 8 360 · D5 5 674 · D6 9 324), ağ, T0 yerleşimi, `PlayableEconomy` + `PlayablePolitics` (`data/game/playable_*.json`), yol komutları, kamulaştırma köprüsü, gösterge bütçe. Ortak kurulum `tests/sim/perf/qa_world_support.gd` (oyunun `PlayableRoads.attach_commands` ile aynı çağrılar). `SimBuildingProjector` TAKILI DEĞİL (görünüm tarafı, sim durumunu değiştirmez); render yok, başsız.
- Gerçek oyun SimFacade'ı (`SimFacadeImpl`), komutlar `submit_command` ile (oyuncu yolu: `public_work.road`, imar: `zoning.propose zone.mixed`). 1 yıl = 360 gün (12 ay x 30), 5 yıl = 1800 tick.
- **Betikli oyuncu (D2)**: gün 30: 3 yol + her birine 8 parsellik imar önerisi; sonraki 4 yılda (gün 30+360k) yılda 1 yol + 1 imar. Yol: `RoadDraftCheck`'ten geçen, D2 içinde, 150 m içinde en çok boş parselli aday (min 250 m aralıkla). İmar: yola en yakın 8 boş D2 parseli. Toplam 7 yol + 7 plan x 8 = 56 plan parseli, 7/7 yol ve 7/7 plan `queued` (hiçbiri reddedilmedi, meclis oylaması yerine plan yürürlüğe girdi: 24+8x4 `event.zoning.applied` = 56).
- **Olumsuz kontrol (`none`)**: aynı kurulum, aynı tohum, oyuncu komutu YOK.
- Tohumlar: sim tohumu 1467 (oyunun varsayılanı), 7, 31337 (dünya aynı). Senaryo başına ayrı süreç.
- Sayım: günlük `events_since` (`event.investor.develop` = onay, `event.construction.started/completed`; konu parsel -> bölge), aşama sütunu (başlangıç/bitiş), `region_stats` (res_built/com_built), `next_review` artışı (= bölge başına reddedilen değerlendirme), `totals.evaluations`, `review_cursor`.
- Makine: MacBookPro15,1 · Intel i7-8850H 2,6 GHz (6 çekirdek/12 iş parçacığı) · 32 GB · macOS (Darwin 24.6) · Godot 4.7.2 başsız (dummy renderer). Yük (1 dk) koşu başı/sonu: 2,96-7,88 (hepsi <= 8; kapıdan hiçbir koşu atılmadı). Yük altında ölçüm ±%40 oynayabilir (ADR-0001); tek makine, tek kez.
- Tick süresi yalnız `facade.advance(1)` etrafında ölçüldü; gözlem (olay/fark) tick dışında. Gözlemin ölçümü bozmadığı: `--no-diff` koşuları ile farkı ölçüm gürültüsü içinde (aşağıda) ve durum hash'leri bire bir aynı.

## 2. Ölçüt 1 + 3: ilçe başına yeni yapı, 5 oyun yılı [ölçüldü]

**Yeni yatırım onayı = inşaat başlayan = tamamlanan** (üç sayaç her koşuda eşit; durma/stall 0):

| Koşu (3 tohumun üçü de aynı sayı) | D1 | D2 | D3 | D4 | D5 | D6 | Toplam |
|---|---|---|---|---|---|---|---|
| **Oyuncu D2'de** (yol + imar) | 0 | **24** | 0 | 0 | 0 | 0 | 24 |
| **Oyuncu girdisi YOK** (olumsuz kontrol) | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| **Fark** (oyuncu - girdisiz) | 0 | **+24** | 0 | 0 | 0 | 0 | +24 |

- Yapı birimi: D2 `res_built` +94 konut birimi (oyuncu koşusu), `com_built` +0; diğer ilçelerde `res_built/com_built` değişimi 0. Aşama sütunu: D2 `built` 1 927 -> 1 951 (+24); diğer ilçelerde planned/under_construction/built/stalled değişimi 0.
- Yıllara göre D2 onayı (oyuncu): 9 · 3 · 4 · 4 · 4 (=24). Girdisiz koşuda her yıl 0.
- 3 tohum (1467, 7, 31337): ilçe sayıları AYNI (24 / 0); durum hash'leri farklı (aşağıda). Yani tohum bu ölçekte SAYIYI değil yalnız ayrıntıyı değiştiriyor (bkz. §6, SIM-11 notu).
- **Sonuç:** oyuncu girdisi D2'de +24 bina üretiyor (oyuncu D2'de etkili) ama etkisi D2 ile sınırlı, taşma 0. Girdisiz koşuda ise D2 dahil hiçbir ilçe değişmiyor: kenti oyuncudan bağımsız evriltecek hiçbir mekanizma bugün yok. "Donuk" varsayımı çürütülmedi, doğrulandı.
- Yeni yapı 56 plan parselinin 24'üne çıktı; kalan 32 `infrastructure_exhausted` (bitişte D2 boş parsel son kodu; `infra_free_units_max = 0` + yol başına ~94 birim bonus, `playable_economy.json` `_infra_note`). Yani D2'de de çıktı yol kapasitesiyle sınırlı.

### Neden donuk (mekanizma, ölçüldü)

Bitişte boş parsellerin son karar kodu (oyuncu koşusu, tohum 1467):

| Bölge | boş | `zoning_unplanned` | hiç karar yok | `infrastructure_exhausted` |
|---|---|---|---|---|
| D1 | 1 418 | 1 418 | 0 | 0 |
| D2 | 2 571 | 362 | 2 177 | 32 |
| D3 | 1 744 | 1 744 | 0 | 0 |
| D4 | 5 981 | 5 981 | 0 | 0 |
| D5 | 3 178 | 3 178 | 0 | 0 |
| D6 | 1 273 | 1 273 | 0 | 0 |

Girdisiz koşuda: D2 2 595/2 595 `zoning_unplanned`; D4'te 654 ve D5'te 1 135 parsel 5 yılda hiç değerlendirilmedi (bütçe yetmedi).
Toplam sim sayaçları (`totals`, 1800 gün): girdisiz = 14 400 değerlendirme, 0 onay, 14 400 ret (hepsi plansız); oyuncu = 14 394 değerlendirme, 24 onay, 14 370 ret.

## 3. Ölçüt 2: yatırımcı değerlendirme bütçesi [ölçüldü]

| Koşu | cap | gün | gün başına ort. | kullanım | cap'te gün | boş gün | imleç ilerleme/gün | örtük tam tarama |
|---|---|---|---|---|---|---|---|---|
| oyuncu (3 tohum aynı) | 8 | 1 799 | 7,997 | %100 | %99,9 (1 798/1 799) | 0 | 23 parsel | ~1 732 gün (4,8 yıl) |
| girdisiz (3 tohum aynı) | 8 | 1 799 | 8,0 | %100 | %100 | 0 | 21 parsel | ~1 925 gün (5,3 yıl) |

- `max_reviews_per_tick = 8` HER GÜN doluyor; aşan gün yok. Yapılandırılmış tarama payı tick başına 4 050 parsel (n/10) ama imleç bütçe bittiği için günde yalnız ~21-23 parsel ilerliyor: `review_period_days = 10` "~10 günde bir görülür" niyeti gerçekte **~5 yılda bir**.
- Bütçe sonucu: girdisiz koşuda 14 400 değerlendirmenin 14 400'ü ret (hepsi `zoning_unplanned`); oyuncu koşusunda 14 394'ün 24'ü onay, 14 370'i ret (bir kısmı D2 plan parsellerinin tekrarlanan `infrastructure_exhausted` retleri, kalanı plansız; ikisinin tam oranı ayrı sayılmadı) [ölçüldü: `totals` + bitiş kodları]. Bölge bazlı dağılım `next_review` artışından türetildi (`raw/*.json` `declined_evals_by_year`).
- TD R1 ("diğer ilçeler canlanınca oyuncunun ilçesi yavaşlar") için sayı: bütçe şu an zaten %100; bir komşu aktör plan açarsa o parseller aynı 8/gün'ü paylaşır.

## 4. Ölçüt 2: tick süresi [ölçüldü, i7-8850H, başsız, yük 3-8]

`facade.advance(1)` süresi, ms, ilk tick hariç, 1 799 tick/koşu. İlk tick ayrı yazıldı.

| Koşu | ilk tick | ort | medyan | p95 | p99 | maks | ay sonu ort / p95 / maks (n=40) | çeyrek sonu ort / maks (n=20) | >8,33 ms | >16,6 ms |
|---|---|---|---|---|---|---|---|---|---|---|
| oyuncu s1467 | 4,3 | 3,11 | 2,36 | 6,65 | 9,67 | 11,5 | 7,42 / 10,6 / 11,2 | 7,09 / 8,9 | 47 | 0 |
| oyuncu s7 | 2,4 | 3,19 | 2,36 | 6,93 | 9,89 | 16,0 | 7,21 / 9,9 / 15,1 | 6,55 / 8,8 | 44 | 0 |
| oyuncu s31337 | 2,3 | 3,13 | 2,32 | 7,04 | 9,49 | 11,6 | 7,13 / 9,0 / 9,0 | 7,11 / 10,1 | 50 | 0 |
| girdisiz s1467 | 3,3 | 3,05 | 2,19 | 6,97 | 9,42 | 17,8 | 7,27 / 11,4 / 12,5 | 7,12 / 9,7 | 43 | 1 |
| girdisiz s7 | 2,5 | 2,69 | 2,19 | 6,09 | 7,89 | 10,7 | 6,69 / 9,8 / 10,7 | 6,18 / 8,3 | 8 | 0 |
| girdisiz s31337 | 2,3 | 2,95 | 2,16 | 6,54 | 8,93 | 13,4 | 7,04 / 11,4 / 12,0 | 6,50 / 8,8 | 26 | 0 |
| oyuncu s1467 `--no-diff` | 3,8 | 3,34 | 2,72 | 7,61 | 9,63 | 13,5 | 7,94 / 10,4 / 11,2 | 7,88 / 12,8 | 52 | 0 |
| girdisiz s1467 `--no-diff` | 2,5 | 2,92 | 2,14 | 6,32 | 8,58 | 12,2 | 6,84 / 10,2 / 10,7 | 6,55 / 10,4 | 21 | 0 |

- **Günlük tick (oyuncu, 3 koşu): ort 3,1-3,2 ms · p95 6,6-7,0 ms · maks 11,5-16,0 ms.** Girdisiz: ort 2,7-3,1 · p95 6,1-7,0 · maks 10,7-17,8. Oyuncu girdisi tick'i ~%5-10 yavaşlatıyor (aktif proje sayısı); koşular arası dalgalanma da bu büyüklükte, ayrım zayıf.
- **Ay sonu tick'i: ort ~6,7-7,9 ms · p95 9,0-11,4 · maks 9,0-15,1.** Çeyrek sonu: ort 6,2-7,9 · maks 8,3-12,8. Normal gün (oyuncu s1467): ort 2,96, p95 5,69.
- Yıllara göre ort (oyuncu s1467): 2,85 · 3,06 · 3,22 · 3,24 · 3,16 ms: yavaş artış (+%10-13, 5 yılda); oyuncu s7: 2,97 -> 3,42. D2 dışı nüfus/bina büyümediği için M3 yükünü temsil etmez (§6).
- `--no-diff` (gözlem yükü en düşük) ile farkı gürültü içinde (girdisiz 2,92 vs 3,05; oyuncu 3,34 vs 3,11, yön tutarsız). Hash'ler bire bir aynı (aşağıda).
- Eski kayıtla çapraz kontrol: `tests/sim/perf/t043b_real_world_probe.gd` (2026-10-31 aynı probe) bugünkü HEAD'de: ort **3,21 ms**, p95 6,58, maks 19,05 (kayıt: ort 3,24); `raw/t043b-crosscheck.json`. 2026-10-31 sayısı bugünkü yapıda **geçerli** (bu probe için); TD notundaki "ESKİ yapı" şüphesi bu ölçüt için çürütüldü.
- Sistem profili (`--profile`, oyuncu s1467, ms; profil adımı toplamı biraz şişirir): `economy.daily` ort 2,31 (maks 7,9) · `politics.daily` 0,38 (maks 7,95) · `economy.monthly` 3,47 (maks 4,16) · `budget.monthly` 0,77 (maks 2,2) · `actors/parcels/budget.daily` ~0,04 her biri. Ekonominin günlük bölümü maliyetin ~%75'i, ayrıntısı (neden 8 değerlendirme için 2,3 ms) incelenmedi [doğrulanmadı].
- İlk tick bu kurulumda 2,2-4,3 ms; 2026-10-31 kaydındaki "ilk tick 109-119 ms" burada ve çapraz kontrol probe'unda gözlenmedi (nedeni araştırılmadı) [doğrulanmadı].

**TD'nin M3 ön hedefleriyle (`teknik-direktor-m3-mimari` §5, öneri; ADR-0013 kesinleştirir):** günlük tick p95 <= 4 ms / tek tick maks <= 8 ms. Bugünkü sayılar bunu AŞIYOR (p95 6-7 ms, maks 10-18 ms) ve ay sonu ort ~7 ms ile hedefin sınırında; yani M3 sistemleri eklenmeden önce bile ön hedef tutmuyor [ölçüldü, masaüstü dev Mac; iPad ölçülmedi].

## 5. Ek deney (kapsam dışı, ucuz): aynı girdi D3'te verilirse? [ölçüldü, NE-OLUR]

`--region=D3 --jurisdiction-all`: yol yetki kısıtı kapatıldı (oyunun verisi değil, `qa_world_support.set_jurisdiction_all`), aynı betik D3'e uygulandı.
Sonuç: D3'te 20 onay = 20 inşaat = 20 tamamlanan (8 · 3 · 3 · 3 · 3), diğer ilçeler 0, D3 `res_built` +94, D3 gizli talep (`latent_hh`) 8 820 -> 21 548.
Anlamı: ekonomi motoru D3'te de çalışıyor; engel hesap/bütçe değil **plan + yol girdisi yok** (ve yol için yetki alanı kuralı). Bu, M3 "komşu belediye aktörü" (T-078 vb.) için gerekli minimum girdinin plan + yol olduğunu gösterir. D2 sonucuyla birlikte: komşu belediye yalnız imar açsa yol olmadan çıktı `infrastructure_exhausted` ile sınırlı kalır (`infra_free_units_max = 0`; D2'de yola bağlı 56 plan parselinin 32'si bu yüzden bekliyor).

## 6. Gözlemler ve dürüstlük notları

- Bölge gizli talebi (`latent_hh`) her ilçede 5 yılda ~2,4 kat büyüyor (D1 38 000 -> 92 841, D6 49 302 -> 120 454, D4 6 580 -> 16 075) ve talep endeksi her yerde 1 000 ‰ (tavan) iken hiçbir şey yapılmıyor: donuk ilçelerde bekleyen talep ölçülebilir şekilde birikiyor [ölçüldü: `region_stats`]. Girdisiz koşuda da aynı.
- Yetki sınırı: D3'te yol komutu `public_work.reject.outside_jurisdiction` ile reddedildi (kilit çalışıyor). Ama D3 parselleri için `zoning.propose` `validate_command` -> `valid` döndü: **simde imar için yetki alanı denetimi yok** (yalnız yolda var). Oyun arayüzünün imar aracını D2 ile sınırlayıp sınırlamadığına bakılmadı [doğrulanmadı]; M3 "gerekçeli kilit" işi (kapsam §2-A.5) bunu bilmeli. Ölçümde oyuncu YALNIZ D2'ye imar önerdi.
- Sim tohumu etkisi: üç tohumda ilçe sayıları ve ret dağılımı birebir aynı, hash'ler farklı. Bu ölçekte tohum çıktıyı çeşitlendirmiyor; SIM-11 için TD R4 kaygısını destekler ama yeni tohum tasarımı bu görevin konusu değil [gözlem].
- Determinizm: `--no-diff` ve `--profile` koşularının `state_hash` değeri normal koşuyla bire bir aynı (oyuncu s1467 `fabe9fff…bbdcf0`, girdisiz s1467 `87d18222…ccb5`); yeniden koşu (`player-s1467-rerun`) aynı hash. Yani gözlem ve profil adımı sim'i değiştirmiyor.
- Betikli oyuncu TEK bir oyuncu: farklı yol/imar tercihi D2 sayısını (24) değiştirir; "komşularda 0" sonucu ise oyuncu eylemine bağlı değil (girdisizde de 0).
- Ölçülmeyenler [doğrulanmadı]: iPad; pencereli/render'lı kare süresi (başsız, projector yok); gerçek bir oyuncunun UI üzerinden akışı; farklı dünya tohumu (yalnız 1467); 5 yıldan uzun ufuk; yük 8'e yakın koşuda (profil koşusu 7,88) gürültü payı; yatırımcı değerlendirme sayısının bölge bazında doğrudan sayacı yok, `next_review` artışından türetildi (onaylar olaylardan).

## 7. Çıkarım (kanıta dayalı, öneri DEĞİL karar)

1. M3'ün asıl varsayımı doğru: D1, D3-D6 fiilen donuk, ve bunun nedeni "plan yok => bütçe sonuçsuz retlere gidiyor".
2. Komşu aktör yalnız plan açarsa bütçe kapasitesi (8/gün, şehir geneli, tek imleç) ve yol/kapasite (`infrastructure_exhausted`) ikinci darboğaz olarak çıkar; T-078/ilçe başına bütçe bu iki noktayı tasarımda hesaba katmalı.
3. Tick tabanı: ort ~3 ms, p95 ~7 ms, maks 10-18 ms, ay sonu ~7 ms. TD'nin önerdiği hedefler (p95 <= 4, maks <= 8) M3 öncesi de tutmuyor; ADR-0013 hedefi ya gevşemeli ya da ay/çeyrek işleri ve `economy.daily` incelenmeli (T-086 alanı).

## Dosyalar

- Betik: `experiments/m3_baseline/m3_baseline_probe.gd` · sarmalayıcı (kilit + yük kapısı + uptime): `run_baseline.sh` · toplu koşu: `run_all.sh` · özet: `summarize.py` (`python3 -I experiments/m3_baseline/summarize.py`)
- Ham JSON/günlük/uptime: `experiments/m3_baseline/raw/` (`player-s{1467,7,31337}`, `none-s…`, `*-nodiff`, `player-s1467-profile`, `player-s1467-rerun`, `player-D3proxy-s1467`, `t043b-crosscheck`)
- Not: probe `run_all.sh` koşusundan SONRA `--region` / `--jurisdiction-all` bayraklarıyla genişletildi (varsayılan yol aynı); `player-s1467-rerun` aynı hash'i verdi (`fabe9fff…`).
- Çalıştırma: `experiments/m3_baseline/run_baseline.sh <ad> -- --mode=player|none --sim-seed=1467 --years=5`

## Doğrulama kapısı

`tools/verify.sh quick` (HEAD 50b5e27, 20:09): **PASS**: canon-check 11/11, studio-check, area-map, gdlint (değişen .gd yok denildi; `experiments/m3_baseline` ayrıca `gdlint` 4.5.0 ile temiz), import, unit-gdunit 366 test 0 hata/0 başarısızlık (35/326 suite). **TAM DOĞRULAMA DEĞİL**: 291 suite ATLANDI (alan eşlemesi "değişiklik yok" çıktı: yalnız experiments/ + belge eklendi, kod değişmedi). `verify full` koşulmadı.
