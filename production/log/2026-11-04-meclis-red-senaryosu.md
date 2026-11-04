# 2026-11-04 · Meclis RED senaryosu (M2-CLOSURE madde 3, F03 ölçüt 5)

Karar gerektirmez: eşik, ağırlık, üye duruşu, `blocs.json`, `src/sim` DEĞİŞMEDİ. Yeni: `tests/game/council_red_scenario_test.gd` (11 test). Dal `worktree-agent-a8fd847cde3b2465b` (taban: `agent/handover-imaro-m01-349562fb` @ 0008fc5, ff).

## Sonuç
RED **üretilebilir ve doğal**; ama **yapısal değil, oy gürültüsüne bağlı** (nadir). Üç koşul birlikte gerekir:
1. **Yeşil imar** (`zone.green`): üye duruşlarıyla uyum en düşük (+597 net; karma +591 ama bloc_pressure +63..70, yeşilde -24..-31; konut +1039, ticari +897).
2. **Bölge altyapısı ~%100 dolu** (oyunun varsayılan başlangıcı, `infra_free_units_max: 0`): `budget_realism` her üyeden ~-99 (5/5 aleyhe, net ≈ -495). Boş altyapı payıyla (eski %30) aynı tohumda yeşil KABUL.
3. **Plan meclise gidecek kadar büyük** (>= 10 parsel ya da >= 40 birim, `playable_politics.json`). Daha küçük plan oylamaya hiç gitmez.
Yine de gürültüsüz (noise-free) `CouncilEngine.forecast` KABUL (3-2) verir; RED yalnız Meclis 4 (taban skor ~+32) ve Meclis 5 (~-15) gürültüyle "hayır"a döndüğünde çıkar. Meclis 1-2 hep evet, Meclis 3 hep hayır. Tahmini oran ~%5-8.

## Kanıt (koşuldu)
Gerçek Ismeral D2 (`qa_council_reject_probe.gd --only=green_r0`, HEAD @ 0008fc5, dünya tohumu 1467, 12 parsel, yeşil): **RED 2-3**, 12/12 `plan_rejected`, `vote_failed` ve `plan_rejected` birer kez, D2 yük binde 998, panel/ReasonPanel hatasız; 102 kontrol, 0 başarısız (B-006 düzelmiş). Süre ~5 dk.
Hızlı, testlenebilir kopya (küçük gerçek dünya `M2RenderSupport`, oynanabilir ekonomi+siyaset, D1 yük binde 999): 60 tohumda (1000-1059) yeşil 12 parsel: **3 RED** (1020: 2-3; 1025: 2-2 eşitlik = `tie_result: fail`; 1037: 2-3); 24 tohumda karma/konut/ticari: 0 RED. Süre: 60 tohum 8 sn.
`council_red_scenario_test.gd` (11 test, 0 hata; yanında `plan_council_test` + `council_why_test` toplam 28 test 0 hata):
- RED (tohum 1020): oy dökümü = üye gerekçeleri, Σ etken net = Σ üye skoru, altyapı etkeni 5/5 aleyhe, duruş uyumu lehe; 12 parsel `plan_rejected`, bölge/bekleyen imar boş, bina/onay yok (CAN-03); yeniden teklif mümkün.
- Karşı örnekler (aynı tohum, tek değişken): diğer 3 imar türü KABUL; boş altyapı payı KABUL; 9 parsel oylamaya gitmez; gürültüsüz tahmin KABUL.
- 40 tohum: RED var ama < %25 (yapısal değil). Determinizm: aynı hash, farklı tohum farklı hash, kayıt-yükle sonrası aynı RED.
- UI/olay akışı: `CouncilPanel` ("Reddedildi", sayım, "Hayıra çeken etkenler", altyapı satırı, ham anahtar/yasak sözcük yok, `refresh` kararlı); olay metinleri; `PlanStateText`; gerçek `HudRoot` + `DecisionPanels` yolu (panelden gönder -> RED -> bildirim şeridi satırı -> meclis ve gündem panelleri -> aynı parsellere yeniden teklif); `UiText.missing_keys()` boş; çıktıda `ERROR` satırı 0.
- Kırmızı-yeşil: `SEED_RED` 1021'e çevrilince 7 test düştü (51 assertion), geri alınca geçti.

## Pencereli oyunda neden 81/81 kabul?
VARSAYIM (pencereli koşu bu oturumda yapılmadı): turlar 2-3'te yeşil imar yalnız bir kısmıydı (4 imar türü x D1-D6, çeşitli ofset); oranı ~%5-8 olan olayın az sayıda yeşil denemede görülmemesi beklenir (örn. 20 yeşil denemede hiç RED olasılığı ~%20-35). Ek olarak ≥ 10 parsel eşiği altında oylama hiç açılmaz. Gerçek oyunda RED görmek için: dünya tohumu 1467 / sim tohumu 1467 ya da 3, yol çiz, yola en yakın 12 boş parsele yeşil imar (probe senaryosu).

## Sahibe (rapora yazıldı, QUESTIONS.md'ye EKLENMEDİ)
Meclis RED'i oyuncuya "yapısal" mı gösterilsin, şans payında mı kalsın? (A) Böyle kalsın: nadir, gürültüye bağlı (şu an). (B) Yeşil/koruma imarı altyapısı doluyken belirgin daha zor geçsin (veri ağırlığı; Q-014/Q-028 usulü ve GOLDEN etkisi var). (C) Meclis RED'i sahne için "demo"da gösterilen sabit bir senaryo olsun (CAN-03 ve sahte sonuç yok kuralı nedeniyle önerilmez). Öneri: A ile devam, RED'i QA/demo için tohumla göster.

## Doğrulanmış / varsayılan / test edilmemiş
**Doğrulanmış:** yukarıdaki probe ve test koşuları (Godot 4.7.2 başsız, macOS Intel, makine paylaşımlı); gdlint temiz (yeni dosya).
**Varsayılan:** pencereli 81 oylamanın nedeni (yukarı); "yoğun tepki/yıkım sonrası" üye güveninin RED'i yapısal hale getirmediği: kod okumasıyla `relation.trust` etkileri küçük (pe-01 +60, pe-03 +80 magnitude) ve Meclis 1-2 marjları (+38/+132) gürültü payının üstünde; ölçülmedi.
**Test edilmedi:** `verify quick/full`; pencereli gerçek oyunda RED karesi (ekran görüntüsü yok); dokunmatik profil; iPad; D2 dışı bölge; yıkım sonrası meclis oylaması koşusu.
