# 2026-11-05 · Yıkım -> meclis güveni (D-021) · simulation-engineer

**Sahip kararı (D-021, kart cevabı "Meclis güveni düşsün"):** bir yol yıkımı insanları yerinden ederse meclis üyelerinin oyuncuya güveni düşer ve imar planları reddedilmeye yaklaşır. Büyüklük, eşik ve hangi üyelerin etkilendiği sahibin sözü DEĞİL; çalışma değeri, veride (`data/politics/reactions.json` `council_trust`). Ölçüm kaynağı: `production/log/2026-11-05-bekleme-listesi-meclis-olcum.md` §2, `production/bugs/B-030.md` (zincirde son halka yoktu).

## Ne yapıldı
- `src/sim/politics/council_trust.gd` (yeni, `CouncilTrust`): haftalık tarama (`PoliticsSystem`, `ReactionAgenda.scan` sonrası). Etkin yerinden edilen hane = tepki defteri (`displaced`) satırlarının `window_days` boyunca doğrusal sönen toplamı; evi bulunan aile yalnız kalan tepkisi kadar sayılır (`ReactionRehousing.still_unhoused`, mevcut tek karar noktası; bekleme listesindeki evsiz aileler tam sayılır). Hedef kesinti = (hane - eşik) x hane başına pm, [0, tavan]. Etkilenen üyeler = kesimi `cohorts` listesinde olanlar (veri). Kesinti hedefe hemen iner; hedef düşünce tarama başına en çok `recover_per_scan_pm` toparlanır.
- Kesinti `politics.council_trust = {penalty {üye: pm}, changes}` içinde (yalnız ilk etkide yaratılır), ilişki kaydına YAZILMAZ; tek okuma noktası `CouncilTrust.effective_trust`: oy girdisi (`CouncilEngine.member_factors` `trust_in_player`) ve üye görünümü (`PoliticsQuery.member_view` `stance`).
- Her değişiklik üye adına neden kaydı (SIM-12): `decision.council.displacement_trust` (aktör = üye; etkenler `unhoused_households`, `council_trust_target`, `council_trust_drop`; özne = yolun komutu; kod `displacement_trust` / `displacement_trust_recovery`).
- Veri: `reactions.json` `council_trust` (digest DIŞI: yıkımsız koşuda hash değişmez). Doğrulama `ReactionConfig._council_trust`; durum doğrulaması `PoliticsState._council_trust_problem` (kayıt yüklemede bozuk kayıt reddedilir). Kod varsayılanı KAPALI.
- Probe: `tools/godot/demolition_council_probe.gd` çıktısına `penalty` ve `trust_eff` eklendi (yalnız okuma).
- `data/ui/strings.tr.json`: 5 satır (yeni karar/etken anahtarlarının Türkçe metni). `tests/ui/reason_decision_text_test.gd` ve `reason_raw_keys_test.gd` metinsiz sim anahtarını düşürüyordu; ui-engineer alanı, yalnız metin; panel bağlanmadı (B-081).

## Çalışma değerleri (veri; ayarlanabilir)
`window_days 180`, `threshold_households 10`, `drop_per_household_pm 5`, `cap_pm 200`, `recover_per_scan_pm 25`, `cohorts ["housed"]` (kesimi barınan hane olan üyeler: üye 1, 2, 5; üye 3, 4 etkilenmez). Kesinti yaklaşık 15 marj puanı / 100 pm (güven ağırlığı).

## ÖNCE / SONRA ölçümü (`demolition_council_probe.gd`, gerçek Ismeral D2, 8 sim tohumu, 12 parselli imar, 96 koşu x 2)
Kollar: A yol yok, B kamulaştırmalı yol (42 hane), D en çok hane yerinden eden 6 yol (302 hane). KABUL = oylama geçti (çoğunluk). Önce = kural yok (bu dalın kapalı hali, veri bölümü eklenmeden), sonra = veri açık.

| gün | imar | kol | KABUL önce→sonra | evet:hayır koltuk (40) | barınan-kesim üye marjı (gürültüsüz, ort.) | kesinti pm | güven üye 1 / 2 / 5 sonra |
|---|---|---|---|---|---|---|---|
| 25 | yeşil | A | 7/8 → 7/8 | 23:17 → 23:17 | 49.7 → 49.7 | 0 | 100 / 0 / 0 |
| 25 | yeşil | B | 7/8 → 7/8 | 23:17 → 23:17 | 52.7 → 34.7 | 135 | -35 / -135 / -135 |
| 25 | yeşil | D | 8/8 → 8/8 | 29:10 → 24:16 | 73.7 → 43.7 | 200 | -100 / -200 / -200 |
| 25 | konut | A | 8/8 → 8/8 | 38:2 → 38:2 | 82.0 → 82.0 | 0 | 100 / 0 / 0 |
| 25 | konut | B | 8/8 → 8/8 | 39:1 → 34:6 | 85.0 → 67.0 | 135 | -35 / -135 / -135 |
| 25 | konut | D | 8/8 → 8/8 | 40:0 → 36:4 | 106.0 → 76.0 | 200 | -100 / -200 / -200 |
| 90 | yeşil | B | 8/8 → 8/8 | 25:15 → 24:16 | 52.3 → 44.0 | 55 | 45 / -55 / -55 |
| 90 | yeşil | D | 8/8 → 8/8 | 30:10 → 24:16 | 73.3 → 43.3 | 200 | -100 / -200 / -200 |
| 90 | konut | B | 8/8 → 8/8 | 38:2 → 37:3 | 85.0 → 76.7 | 55 | 45 / -55 / -55 |
| 90 | konut | D | 8/8 → 8/8 | 40:0 → 37:3 | 106.3 → 76.3 | 200 | -100 / -200 / -200 |

(A kolu ve 90. gün A satırları da koşuldu, yıkım yok => kesinti 0, sonuçlar özdeş; ham çıktı bu repoda tutulmadı.) Okuma: yıkım artık meclisi KOLAYLAŞTIRMIYOR (B-030: önce yıkım marjı +3 / +24 arttırıyordu); en sert kolda (D) yeşil imarın evet koltuğu 29 -> 24 (yıkım yok kolu A ile eşit), konut imarı 40 -> 36. Kesinti 25. günde 135-200 pm, 90. günde B için 55 pm (sönme). Hiçbir koşuda çoğunluk sonucu DEĞİŞMEDİ (KABUL sayıları aynı): ayar "yaklaşır"dır, "reddeder" değil.

**Duyarlılık (SERT, ölçüm için geçici; gönderilen veri DEĞİL):** `cap_pm 400`, `drop_per_household_pm 10`: yeşil imar KABUL 25. gün B 5/8, D 5/8; 90. gün D 4/8 (evet:hayır 20:20); konut imarı 8/8 kalır (koltuk 32:8). Yani tavan ~400 pm ve üstünde en sert yıkımda yeşil imar gerçekten reddedilmeye başlar; 200 pm ise yalnız marjı düşürür. Hangisi isteniyor: sahip/systems-designer kararı (`cap_pm`, `drop_per_household_pm` veri).

## Altın hash etkisi
- GOLDEN_A/B (`tests/sim/m2_query_test.gd`, yıkımsız): DEĞİŞMEDİ (aynı sabit, test yeşil).
- GOLDEN_X (`tests/sim/public_works/golden_expropriation_undo_test.gd`): **DEĞİŞTİ, YENİLENMEDİ.** Eski `c987fb3d...cd4094`, yeni aday `1914f0e131fb087426f0e733162ec7f3b1dfc73a1c2aeb555c268cd37c3abb0d`. Neden: senaryoda kamulaştırmalı yol A' ayakta kalır (D1'de 16 hane yerinden), eşik 10'u aşar => `council_trust` durumu, 3 üye için neden kaydı ve `reason_records` sayacı hash'e girer (bütçe defterindeki `reason_id`ler de kayıt numarası kaydığı için farklı). Kanıt: `tests/sim/public_works/golden_x_council_trust_test.gd` iki iddiayı kilitler: (1) kural KAPALIYKEN aynı senaryo eski `c987fb3d...` değerini bit-bit verir (tek neden kural); (2) açıkken ekonomi + yol işleri durumu ve bütçe defteri (tick, tür, tutar, referans) özdeş, fark yalnız kesinti durumu. Bu dosya eski sabiti kendi içinde taşır; golden dosyasına dokunulmadı, `tests/sim/public_works/golden_expropriation_undo_test.gd::test_state_hash_at_tick_60_is_the_recorded_golden` bu dalda KIRMIZI (bilinçli, sahip onayına kadar).

## Kalan / önerilen
B-080 (olay kaynağı `council.trust_gap` kesintiyi okumuyor), B-081 (UI panel bağı; metin eklendi). Sözleşme sürümü DEĞİŞMEDİ (yeni alan yok; `CouncilBlocView.stance` zaten güven).
