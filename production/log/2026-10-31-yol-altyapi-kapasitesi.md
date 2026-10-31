# Yol -> bölge altyapı kapasitesi nedenselliği (D-009, D-010) · 2026-10-31

Statü: ÇALIŞMA MODELİ (sayılar yer tutucu, kanon DEĞİL; Q-024/Q-017 AÇIK, dokunulmadı). Commit yok. Sim kuralları (`src/sim/**`) DEĞİŞMEDİ; yalnız oynanabilir yapılandırma verisi + yapılandırma türeten `PlayableEconomy`.

## 1. Kök neden (DOĞRULANDI, ölçüldü)
Gerçek Ismeral D2 (tohum 1467, probe `tests/sim/perf/t043b_real_world_probe.gd`, `infra_before/after` eklendi):
- Bölge yükü (T0 stoğu) **9316 birim**; oynanabilir kapasite = yük + %30 pay + 1 = **12111** -> boş kapasite ~**2795 birim**.
- 12 parselin planı toplam **51 birim** ister (`plan_preview`); 108 m yol (`infra_units_per_km` 100) bölgeye **+10 birim** ekler.
- Yatırımcı kararı altyapıyı yalnız `headroom < 0` iken VETO eder (`investor_decision.gd:43-45`); 2795 birim boşlukta 10 birimlik yol hiçbir kararı değiştirmez. Yolsuz de plan 12/66 gün; yollu da 12/66 gün (önceki log).
- Küçük fixture ile aynı kök neden birim testte de görülür: kontrol (`infra_free_units_max: -1`) yolsuz plan, 4000 birimlik bölgede 14 bina onayı verir; aynı senaryo yeni veriyle 0.
- İkinci bulgu (değişiklik tasarımını belirledi): altyapı etkeni VETO'dan ayrı olarak skora `min(infra_bonus_max=150, headroom/kapasite)` puan ekler. Binlerce birimlik bölgede 10 birimlik yol bu oranı 0'a yuvarlar. Yalnız kapasiteyi daraltmak (bonus açıkken) yol+plan'da 12 parselden **1** onay verdi (kapasite 7 birim boş kaldığı halde: skor eşiğin altına düştü, ret kodu altyapı değil getiri/talep görünürdü, nedensellik okunmaz olurdu).

## 2. Değişiklik (veri güdümlü, en küçük)
`data/game/playable_economy.json` (+ `src/game/playable_economy.gd`):
| Anahtar | Önce | Sonra | Anlamı |
|---|---|---|---|
| `infra_free_units_max` (yeni) | yok | **0** | Bölgenin BAŞLANGIÇ boş kapasitesi `min(yük x infra_headroom_pm/1000, bu sayı)` + 1 (mutlak birim). -1 = sınırsız (eski, kontrol koşusu) |
| `decision.infra_bonus_max` | 150 (sim varsayılanı) | **0** | Oran bonusu kapalı: altyapı yalnız "sığar/sığmaz" kapısı (VETO -> `infrastructure_exhausted`, gerekçede yol komutu `source_ref`) |
| `decision.base_threshold` | 450 | **300** | `450 - 150`: boş bölgede skor ESKİSİYLE AYNI (test: `base_threshold - infra_bonus_max` sim varsayılanıyla eşit) |
- `infra_headroom_pm` 300 KORUNDU (küçük bölgeler `min(pay, sınır)` ile eski değerini korur). `config_for` `patch["playable"]` ile bu ayarları geçersiz kılabilir (kontrol koşuları).
- Yol katsayısı (`road_works.json` 100 birim/km) DEĞİŞMEDİ (sim varsayılanı, yol testleri). core-loop-v0 §4'ün K·medyan/0,3 km formülü 160/km verir (ölçüldü: bkz. §4 satır "160/km"); karar veriye bırakıldı.
- Yeni durum/anahtar/komut YOK: `infra_cap` zaten durum sütunu (config'ten); yolun bonusu zaten `PublicWorksState` (yalnız ilk yolda yaratılır, T-042). Sim varsayılanı + GOLDEN_A/B etkilenmez (`PlayableEconomy` sim varsayılanında kullanılmaz; sim dosyası değişmedi).
- Test desteği: `tests/game/m2_render_support.gd` fixture'ları yatırımcı->projector zincirini sınar (yol nedenselliğini değil); `ISOLATE`/`handle` varsayılanı `infra_free_units_max: -1` olur (fixture D1 yükü 5290 birim, %30 pay 1587: sınırsız eski davranış).

## 3. Öncesi / sonrası (gerçek Ismeral D2, 12 parsellik plan, 108 m yol, tohum 1467, kuyruk açık; gün = yol+plan tamamlandığı son olaydan)
| Senaryo | ÖNCE (eski veri) ilk inşaat / ilk bina / başlayan | SONRA ilk inşaat / ilk bina / başlayan |
|---|---|---|
| yol -> plan (D-008) | 12 / 66 / 12 parsel | **12 / 66 / 3 parsel** (başlangıçlar 12,12,13; tamamlanma 66,69,70) |
| yalnız plan (yol yok) | 12 / 66 / 12 parsel | **inşaat YOK, bina YOK** (200 gün; 0 onay) |
| yalnız yol (plan yok) | inşaat yok | inşaat yok (0 onay) |
| plan -> yol | 12 / 66 (yalnız-plan ile aynı) | **12 / 66 / 3 parsel** (plan yürürlükte, yol sonra: yol gelince başlar) |
- Yol+plan ile yalnız-plan artık anlamlı biçimde farklı: 3 bina vs 0. 12 parselin 9'u kapasiteye sığmadı (yol 10 birim + 1 artık; 3 bina 11 birim: bölge `yük 9327 / kapasite 9327`).
- Duyarlılık (tek koşu, aynı veri): sim tohumu 2 -> aynı günler ve sayılar (12/66, 3 bina; yalnız durum özeti değişir). Daha uzun yol (rank 1, 248 m, 24 birim, 43 birimlik plan) -> **7 bina** (12/66, başlangıçlar 12..15): yol uzunluğu = bina sayısı. Yalnız-plan tohum 2 de 0.
- Öncelik kuyruğu açık/kapalı (kabul c): ilk inşaat 12 / ilk bina 66 ikisinde aynı, onay sayısı 3/3 aynı. Fark yalnız başlangıçları yaymak: açık 12,12,13 (tamamlanma 66,69,70) vs kapalı 12,12,12 (66,69,69); durum özeti farklı (kuyruk çalışıyor), gün sayıları pratikte aynı. Önceki log'daki bulgu (kuyruk gerçek veride hızı değiştirmiyor) SÜRÜYOR; kuyruğun değeri bu veride yalnız yayılım.
- Gerçek saniye (4 gün/sn, hesap): ilk inşaat 3,0 sn, ilk bina 16,5 sn (değişmedi).
- Karşılaştırma: ham çıktılar `/private/tmp/claude-501/scratch_yol/` (geçici, repoda yok).

## 4. Yol katsayısı duyarlılığı (karar değil, ölçüm; kodda DEĞİŞMEDİ)
108 m yol: 100/km -> 10 birim -> 3 bina; **160/km -> 17 birim -> 4 bina** (deneme; `--km-units=160`). Yol uzunluğu bina sayısını belirler. Hangi katsayının "doğru" olduğu denge kararı (systems-designer / Q-024 civarı).

## 5. Birim testler
Yeni: `tests/game/playable_infra_capacity_test.gd` (8 test): (1) veri sınırı dar ve büyük bölgede kapasite = yük + sınır + 1; (2) `min(pay, sınır)` formülü, küçük bölge eski değerini korur; (3) -1 ile eski davranış; (4) eşik - azami bonus sim varsayılanıyla eşit; (5) yolsuz plan: yatırımcı bakar, 0 onay, ret gerekçesi altyapı VETO (SIM-12); (6) yol sonrası bina var, yazılan birim <= 11, 14 parselin hepsi sığmaz, onay gerekçesinde kapasite kaynağı yol komutu; (7) yalnız yol: 0 bina (D-010, CAN-03); (8) kontrol: sınırsız eski veri yolsuz bina verir (testin başarısız olabildiğini gösterir).
Kırmızı->yeşil: kod öncesi 7 testten 3 başarısız + 2 hata (anahtar yok; yolsuz plan 14 onay verdi); sonra yeşil (8/8 son halde).

## 6. Doğrulanmış / varsayılan / test edilmemiş
**Doğrulanmış (çalıştırıldı):**
- Probe 8 koşu (§3) ve 3 deney koşusu (kapasite yalnız; kapasite + bonus kapalı; 160/km).
- `tests/game/playable_infra_capacity_test.gd` 8/8 PASS; `tests/game` + `tests/ui` birlikte: 431 test, 0 hata, 0 başarısız (10 yetim düğüm uyarısı, çıkış kodu 101, yeni suite tek başına koşuda 0 yetim).
- `uvx --from gdtoolkit==4.5.0 gdlint` değişen/yeni dosyalar temiz.
- `tools/verify.sh quick`: PASS (canon, studio, area-map, gdlint, import; unit-gdunit 126/212 suite, **1290 test, 0 hata, 0 başarısız**, 10 yetim uyarısı; koruma çekirdeği = GOLDEN_A/B hash, determinizm, CAN-03, kayıt dahil). KISMİ: tests/app, art, library, view, world (86 suite) ATLANDI; tam doğrulama (`full`) çalıştırılmadı.
**Varsayılan:**
- Sayılar (`infra_free_units_max` 0, eşik 300/bonus 0, 100 birim/km) çalışma değeri, kanon değil; Q-024 ve denge kararı AÇIK.
- "Boş bölgede skor eskisiyle aynı" eşitliği eşik-bonus farkıyla (450-150) kanıtlandı; bonusun kısmi (0 < oran < 150) olduğu bölgelerde karar artık biraz daha kolay (bonus 0 + eşik 300; önceden bonus < 150 iken skor daha düşüktü). Oynanabilir gerçek bölgelerin hepsi başta %30 payla bonus doygunluğundaydı (>= %15 boşluk), bu yüzden pratik fark yok [varsayım: 3 bölge ölçülmedi].
**Test edilmemiş / riskler:**
- Yalnız D2, tek dünya tohumu, 108 m ve 248 m yol; çok yollu zincir ve diğer bölgeler ölçülmedi.
- **Siyaset yan etkisi:** bölge yükü/kapasite oranı artık ~%100 (`infra_load_pm` ~ 999; önceki ~%77). Siyaset katmanı bu oranı baskı sinyali olarak okur (`event_sources.gd:180` `service.stress_pm`, `bloc_signals.gd:24` `infra_stress`, `council_engine.gd:299`). Sinyal tüm bölgelerde başlangıçtan yüksek; siyaset olayı sıklığı/oy gerçekçiliği değişmiş olabilir. `tests/game/playable_politics_test.gd` ve m2_causal_loop geçti ama siyasi olay dağılımı oynanabilir veride ölçülmedi. Probe olay sayıları farklı ufuklarda (koşu uzunluğu farklı) alındığı için öncesi/sonrası karşılaştırması YAPILMADI.
- Altyapıyı aşan parseller için oyuncuya "daha fazla yol gerek" ipucu UI'ı bu işte yok (HUD'a dokunulmadı); gerekçe paneli zaten `infrastructure_exhausted` + yol komutunu gösterir (ui-engineer doğrular).
- Kamulaştırma/yol geri alma (T-042b) etkisi: geri alınan yol bonusu düşürür (mevcut davranış), bu işte test edilmedi.
- Yol uygulama maliyeti (graph_hash 32 ms) bu işin kapsamı dışı, dokunulmadı.
- `playable.gd`, `src/view/**` dokunulmadı. `--infra-free=N` dev bayrağı değişmedi.

## 7. Değişen dosyalar
- `data/game/playable_economy.json` (`infra_free_units_max`, `decision.infra_bonus_max/base_threshold`, `_infra_note`, `_unplanned_note` güncellendi)
- `src/game/playable_economy.gd` (`infra_free_units_max`, `patch["playable"]`)
- `tests/game/playable_infra_capacity_test.gd` (+ `.uid`) yeni
- `tests/game/m2_render_support.gd` (`NO_INFRA_CAP`, `ISOLATE`/`handle` varsayılanı)
- `tests/sim/perf/t043b_real_world_probe.gd` (`--infra-cap`, `--decision`, `--km-units`, `infra_before/after`, `plan_detail`; hâlâ izlenmeyen)
- Bu log.
