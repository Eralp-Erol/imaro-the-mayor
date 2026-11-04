# Yol-altyapı kapasitesinin siyaset yan etkisi · 2026-10-31

Statü: ÇALIŞMA MODELİ (sayılar yer tutucu, kanon DEĞİL). Commit yok. `src/sim/**` DEĞİŞMEDİ (GOLDEN A/B etkilenmez). Önceki iş: `2026-10-31-yol-altyapi-kapasitesi.md` (`infra_free_units_max` -1 -> 0).

## 1. Özet (kısa)
- Oran gerçekten ~%99,9: eski %76,9 (`infra_load_pm` 769), yeni **999** (D2 yük 9316 / kapasite 9317). Yol+plan sonrası D2 = 1000 (dolu, aşmıyor).
- Siyasi olay sıklığı: commit **az** değiştirdi (400 gün, akışsız: grup tepkisi 4 -> 6, gündem 6 -> 7). PE-07 (hizmet aşımı) **hiç tetiklenmedi** (yük > kapasite hiç olmadı).
- Asıl bulgu **commit'ten önce de vardı**: oyuncu hiçbir şey yapmadan barınan-hane kesimi (`actor.bloc.1`) şikâyeti ~50. günde 1000'e doyuyor ve oppose/protest + gündem (PE-01/02/04) üretmeye devam ediyor, çünkü sim varsayılan kesim kuralı altyapı baskısını oran %50'den (lo 500, hi 900) başlatıyor. Yeni veri yalnız bunu biraz hızlandırdı (ilk tepki gün 21 -> 14; 25. günde şikâyet 546 -> 818).
- Düzeltme uygulandı (yalnız oynanabilir veri): altyapı baskısı şikâyeti **yalnız gerçek aşımda** (yük > kapasite) başlar. Sonuç: akışsız 400 günde siyasi olay **0**, şerit olayı **0**.
- Yan etki, sahibin kararı gerek (bkz. §7): düzeltme sonrası D-008'in "halk tepki versin" adımı bu veride **sessiz** (yol+plan sonrası 400 günde grup tepkisi 0). Bu, düzeltmenin değil mevcut veri yapısının sonucu (§5): D2 ölçeğinde inşaat baskı sinyali kesim payı eşiğinin altında kalıyor.

## 2. Kodla doğrulanan zincir (DOĞRULANDI, okundu)
- `EconomyQuery.region_row` `infra_load_pm = ratio_pm(yük, etkin kapasite)` (`economy_query.gd:53`). Kapasite = yük + `min(yük x %30, infra_free_units_max)` + 1 -> 0 sınırında `yük / (yük+1)` = 999 pm (eski: ~769).
- Okuyanlar: `event_sources.gd:180` -> `service.stress_pm`; `bloc_signals.gd:24` -> `infra_stress` (0..2000 kıskaç); `council_engine.gd:299` -> imar oyu "uygulanabilirlik"; `bloc_engine.gd:76` -> `overload_days` (yalnız `> 1000`); `event_engine.gd:230` -> olay bölgesi seçimi (en yüksek yük).
- **PE-07** (`pe-07.json`): sert kapı `service.overload_days >= 14`; gün sayacı yalnız `infra_load_pm > 1000` iken ilerler. Yatırımcı karar kapısı yük > kapasiteyi VETO ettiği için oran >1000 olmaz (ölçüm: en yüksek 1000). `stress_pm` sürücüsü (lo 900, hi 1300, ağırlık 200) tek başına bu kapıyı açamaz. Eşik üstü katkı YOK; ölçüm: `max_service_overload_days = 0` (tüm koşular).
- **Kesim şikâyeti** (`blocs.json` housed): `infra_stress` kuralları lo 500, hi 900, gain 300 (hizmet) + 200 (hareketlilik). 769 -> seviye 672; 999 -> 1000 (doygun). Haftalık girdi x ~10 (decay %10) denge şikâyeti 1000'in çok üstü: **her iki oranda da doyar**; fark yalnız hız. Bu, eşik üstü ve sürekli bir katkıdır (commit öncesi de).
- **Meclis** (`council_engine.gd:299` `realism_of`): yalnız imar oylamasında okunur. Oynanabilir veri `requires_council.zoning.propose=false` (D-010) -> oylama açılmaz. Ölçüm: `council_votes_opened = 0` (tüm koşular). `budget.propose` hâlâ meclise gider ama oylamada uygulanabilirlik bütçe için bağlam değeri okur, altyapı oranını okumaz.
- **Bildirim şeridi** (`notification_strip.gd`): `group.reacted` ve `command.*`/`public_work.*`/`construction*` `PRIO_PLAYER`; yani bölge baskı tepkisi şeritte en yüksek öncelikle görünür ve oyuncunun gerçek eylem satırlarını itebilir (yalnız 3 satır).

## 3. Ölçüm (DOĞRULANDI, çalıştırıldı)
Düzenek: `tests/sim/perf/infra_politics_probe.gd` (yeni; t043b probe kurulumu: gerçek Ismeral, tohum 1467, PlayableEconomy + PlayablePolitics, 400 gün, günde 1 tick, yol+plan akışı 30. günde: D2'de 107,8 m yol + 12 parsellik plan). "Şerit" = olay akışından `NotificationStrip.is_unplanned_decline` süzülmüş, şeride giren olay sayısı (3 satır sınırı UI'da). Gizlenen plansız vazgeçme olayları (`actor.decided`, ~3190/400 gün) iki yapılandırmada da aynı sıra büyüklüğü.

### 3.1 Akışsız (oyuncu eylemi YOK), 400 gün
| Ölçü | ESKİ (`-1`) | YENİ (`0`), eski kesim kuralı | YENİ + DÜZELTME |
|---|---|---|---|
| Bölge `infra_load_pm` (hepsi) | 769 | **999** | 999 |
| `infra_stress` sinyali (en yüksek) | 769 | 999 | 999 |
| `service.overload_days` en yüksek | 0 | 0 | 0 |
| `group.reacted` olayı (türler) | 4 (oppose 2, protest 2) | 6 (oppose 3, protest 3) | **0** |
| Gündem açıldı (PE-01 / 02 / 04) | 6 (2/1/3) | 7 (3/1/3) | **0** |
| Gündem kapanış (süresi doldu/lapsed) | 4 | 5 | 0 |
| İlk tepki günü | 21 | 14 | yok |
| Barınan kesim şikâyet G, gün 25 / 50 | 546 / 1000 | 818 / 1000 | **0 / 0** (en yüksek 0) |
| Konut arayan kesim G (talep sıkıntısı), 400. gün | 404 | 404 | 404 (aynı; altyapıyla ilgisiz) |
| Siyasi olay toplamı (`group.*`+`politics.*`) | 14 | 18 | **0** |
| Şerit olayı toplam (günde) | 18 (0,05) | 24 (0,06) | **0** |
| Şerit önceliği (arka plan/normal/oyuncu) | 0/14/4 | 0/18/6 | 0/0/0 |
| Meclis oylaması açıldı | 0 | 0 | 0 |
| Ham olay (günde) | 3219 (8,05) | 3225 (8,06) | 3200 (8,00) |

### 3.2 Yol -> plan (D-008), D2, 400 gün
| Ölçü | ESKİ (`-1`) | YENİ, eski kesim kuralı | YENİ + DÜZELTME |
|---|---|---|---|
| D2 yük / kapasite / oran sonda | 9367 / 12121 / 772 | 9327 / 9327 / **1000** | 9327 / 9327 / 1000 |
| `parcel.changed` olayı (bina evreleri) | 36 | 18 | 18 |
| `group.reacted` | 4 | 6 | **0** |
| Gündem açıldı | 6 | 7 | **0** |
| Şerit olayı toplam (günde) | 69 (0,17) | 57 (0,14) | **33** (0,08; hepsi oyuncu/inşaat) |
| Şerit önceliği (arka plan/normal/oyuncu) | 0/14/55 | 0/18/39 | 0/0/33 |
| Konut arayan kesim G en yüksek | 404 | 404 | 404 |
| Barınan kesim G en yüksek | 1000 | 1000 | **0** |
| `service.overload_days` | 0 | 0 | 0 |
- Yol+plan akışında tepki olayları (eski ve yeni kural) `cause_refs`'te plan parsellerini gösteriyordu (son parsel olayları) ama tetikleyen baskı altyapı oranıydı (akışsız koşuda aynı tepkiler, aynı günler 21/70/154/294 -> 14/56/196/252 var): **yanlış nedensellik** (SIM-12 ruhuna aykırı).
- Kare bütçesi/yük: probe duvar saati ölçümü değildir; sim tick değişmedi.

Ham çıktılar: `/private/tmp/claude-501/-Users-eralperol-Documents-Projects-imaro-the-mayor-handover-imaro-m01-349562fb/4befd413-b71d-4411-9c44-6e96f796ef86/scratchpad/{r,f}_*.txt` (geçici, repoda yok). Durum özeti (state_hash) yapılandırmalar arasında doğal olarak farklı; aynı yapılandırma + tohum + komut akışı iki koşuda aynı hash verdi (düzeltmeli yol+plan).

## 4. Değişiklik (veri güdümlü, yalnız oynanabilir; sim varsayılanı DEĞİŞMEZ)
`data/game/playable_politics.json` + `src/game/playable_politics.gd`:
- Yeni anahtar `blocs_grievance_rule_overrides: [{signal: "infra_stress", lo: 1000, hi: 1300}]`: oynanabilir yapılandırmada her kesimin `infra_stress` şikâyet kuralının `lo/hi` değeri yamalanır (kopya sözlük; `data/politics/blocs.json` dosyası ve sim varsayılanı aynı kalır; mevcut "dosyalar kopyalanır, yama kopyaya uygulanır" deseni).
- Anlamı: tam dolu (oran 1000) = baskı 0; baskı yalnız **yük > kapasite** olunca (ör. yol geri alınınca, T-042b) yükselir; 1300 = PE-07 `stress` sürücüsü ile aynı ölçek.
- Kapsam dışı bırakılan: `blocs.json` (sim), `economy_config`, `infra_free_units_max` (yol nedenselliği için gerekli, dokunulmadı), `construction_burden`/`min_share_pm` (bkz. §5-§7), olay şablonları.
- Geri alma: tek anahtar (`blocs_grievance_rule_overrides`) silinirse eski davranış (yeni oranla) geri gelir.

## 5. Önemli keşif: D2'de inşaat baskısı kesime hiç ulaşmıyor (DOĞRULANDI, ölçüm; DEĞİŞMEDİ)
Probe `max_construction_burden_signal = 0` (yol+plan, hem 108 m hem 248 m yol: 3 / 7 bina). Sebep (kod okuma, varsayım): `blend.mode = peak`, `min_share_pm = 100`: kesim sinyali yalnız kesim payı %10 ve üstü bölgelerden alınır; D2 barınan hane payı ~%7,5 (9316 / ~123k yük birimi; yaklaşık). Yani D2'deki inşaat (en küçük bölgelerden biri) hiçbir kesimi harekete geçirmez; bölge >= %10 payda (D1, D6) ise inşaat baskısı yalnız o bölgelerde işlenir. Bu **düzeltmenin değil** mevcut sim kuralı + gerçek bölge boyutlarının sonucu; `min_share_pm` ve `construction_burden` aralığı (lo 20, hi 200 pm; 3 bina ~ yük/hane oranı çok küçük) denge kararı.

## 6. Testler
Yeni: `tests/game/playable_politics_infra_pressure_test.gd` (3 test): (1) dolu ama sığan bölge + oyuncu eylemi yok -> barınan kesim şikâyeti 0 ve tepki yok (sinyal 990..1000 doğrulanır); (2) kontrol: sim varsayılan kesim verisi aynı bölgede şikâyet biriktirir ve tepki verir (testin başarısız olabildiğini gösterir); (3) gerçek aşım (kapasite yükün %70'i, oran >1000) oynanabilir veride de şikâyet üretir.
Kırmızı -> yeşil: kod öncesi 3 testten 2 başarısız (şikâyet >0; tepki >0); anahtar + kod sonrası 1 başarısız (test hatası: konut arayan kesimin talep tepkisini de sayıyordu, ilgisiz); testi barınan kesimle sınırlayıp 3/3 yeşil.

## 7. Doğrulanmış / varsayılan / test edilmemiş
**Doğrulanmış (çalıştırıldı):**
- Probe: (eski/yeni) x (akışsız/yol+plan) = 4 koşu + düzeltmeli 2 koşu + düzeltmeli yol+plan 2 yeniden koşu (108 m ve 248 m yol, inşaat baskısı ölçümü); yukarıdaki tablolar bu çıktılardan. Tekrarlanabilirlik: düzeltmeli yol+plan koşusu iki kez aynı `state_hash` (82b213766b5d).
- `tests/game/playable_politics_infra_pressure_test.gd` 3/3; `tests/game` + `tests/ui/plan_flow_test.gd` + `tests/sim/politics` + `tests/sim/m2_query_test.gd` + `tests/sim/parcel_changes_test.gd` (GOLDEN A/B taşıyan suite'ler) birlikte: **291 test, 0 hata, 0 başarısız, 0 yetim** (çıkış kodu 0).
- `git diff`: `src/sim/**` boş (yalnız `src/game/playable_politics.gd` + `data/game/playable_politics.json`) -> sim varsayılanı/GOLDEN A/B bit-bit aynı; CAN-03 etkilenmez (komut/yatırım yolu değişmedi, yalnız kesim şikâyet eşiği).
- `uvx --from gdtoolkit==4.5.0 gdlint` yeni/değişen 3 `.gd` dosyada temiz.
**Varsayılan:**
- Sayılar (`lo 1000, hi 1300`) çalışma değeri; PE-07 ölçeğiyle uyumlu seçildi, ayrıca denenmedi (1000 vs 1100 gibi).
- D2 payının ~%7,5 olduğu (§5) okunan koddan çıkarım; payı doğrudan yazdırmadım.
- Aşırı yük senaryosunda (yol geri alma) PE-07'nin gerçekten tetikleneceği: kural okundu, oynanabilir sahnede yol geri alma akışıyla ölçülmedi.
**Test edilmemiş / riskler:**
- `verify quick/full` ÇALIŞTIRILMADI (isteğe göre); `tests/app`, `tests/view`, `tests/world`, `tests/art`, `tests/library` koşulmadı.
- Yalnız D2, tek dünya tohumu (1467), sim tohumu 1467; diğer sim tohumları ve diğer bölgelerde yol akışı ölçülmedi. Bütçe önerisi (`budget.propose`) yolundaki siyaset etkisi ölçülmedi (oyuncu bütçe eylemi yok).
- Pencereli/gerçek HUD: bildirim şeridi sayısı olay akışından hesaplandı (aynı statik fonksiyonlar), ekranda görülmedi.
- **Sahip kararı (D-008 "halk tepki versin"):** düzeltmeden sonra yol+plan akışında 400 günde halk tepkisi görünmüyor (önce de gerçek nedeni yoktu, ama tepki görünüyordu). Seçenekler (öneri sırasıyla): (a) şimdilik böyle bırak, sahte tepki yok; tepki adımı için "neye tepki versin?" kararı gelince `construction_burden`/`min_share_pm` ayarlanır (önerilen, §5); (b) playable veride D2 gibi küçük bölgeler için `min_share_pm` düşür (kesimlerin tüm bölgelere tepkisi artar, başka tepkiler de açılır); (c) düzeltmeyi geri al (eski sahte tepkiler döner). Soru `production/QUESTIONS.md`'ye EKLENMEDİ (sahip bu mesajı okuyacak).

## 8. Değişen dosyalar
- `data/game/playable_politics.json` (`blocs_grievance_rule_overrides`, `_infra_pressure_note`)
- `src/game/playable_politics.gd` (`_override_grievance_rules`, başlık yorumu)
- `tests/game/playable_politics_infra_pressure_test.gd` (+ `.uid` Godot ilk koşuda üretirse) yeni
- `tests/sim/perf/infra_politics_probe.gd` yeni (ölçüm aracı; test paketi değil)
- Bu log.
