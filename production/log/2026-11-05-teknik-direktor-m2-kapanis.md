# 2026-11-05 · Teknik direktör M2 kapanış incelemesi

- Taban: `05c5a13` (dal `work/td-m2-close`). Yalnız okuma: kod, test, kayıt. **Godot ve testler bu oturumda ÇALIŞTIRILMADI** (tam doğrulama başka oturumda koşuyor, Godot kilidi dolu). `src/`, `tests/`, `data/` değişmedi.
- Etiketler: **[okundu]** kod/diff okundu · **[kayıt]** başka oturumun ölçüm/test kaydından · **[hesap]** aritmetik · **[varsayım]** · **[ölçülmedi]**.

## Karar
**M2 kapanışı: KOŞULLU EVET (GO).** T-076 tek sert açık iş olarak kalabilir. Koşullar:
1. **Şu an koşan `verify full`, kapanış HEAD'inde (>= `05c5a13`) PASS vermeli.** Son tam PASS `34eae42`'de (`artifacts/verify/full-latest.json`); ondan sonra sim davranışı (B-080, GOLDEN_X yenilendi), sözleşme 1.10 (B-052), görünüm (projector) ve UI (çekmece, B-123/B-125) değişti. Bu bir kapı, "iş" değil. FAIL olursa kapanış durur.
2. **T-076 çalıştırılmadan önce görev dosyası düzeltilmeli** (aşağıda "T-076 kapsam düzeltmeleri"). Yoksa ölçüm ADR-0010 Karar 3 tablosunu kapatmaz ve M2 satırı yine "ölçüm yok" kalır.
3. **Kayıtlardaki bayat perf sayıları düzeltilmeli** (Studio Director; yalnız belge). Masaüstü tablosu bugünkü yapıyı anlatmıyor (aşağıda).

Mimari/determinizm/kayıt/sözleşme incelemesi: **PASS WITH FIXES** (düzeltmeler belge ve test kapsamı; kod düzeltmesi yok).
Kare bütçesi: **masaüstü tavanlar geçiyor [kayıt], hedeflerin bir kısmı bugünkü yapıda ölçülmedi; iPad hiç ölçülmedi.**

T-076'da şunlardan biri çıkarsa düzeltme M2'ye girer (ADR-0010 Sahibe soru seçenek A ile aynı kural): etkileşim karesi > 100 ms, iOS'un uygulamayı sonlandırması (bellek ya da açılış), kararlı p95 > 20 ms.

## 1 · Mimari, determinizm, kayıt, sözleşme

### B-080 (sim davranışı, PE-03 `council.trust_gap`) — PASS
- [okundu] `src/sim/politics/event_sources.gd:156-157` artık `CouncilTrust.effective_trust` okur; oy girdisi ve üye görünümüyle aynı tek işlev (`council_trust.gd:79-80`). ADR-0011 Karar B'nin birebir uygulaması; bayrak yok, veri ve sözleşme değişmedi.
- [okundu] Determinizm: tamsayı, rastgelelik yok; üye sırası `ctx.politics.council["members"]` dizisinden (sabit). Negatif toplamda tamsayı bölmesi sıfıra doğru keser, platformdan bağımsız [varsayım: GDScript int bölmesi C++ int64 bölmesi].
- [okundu] GOLDEN_X yenilemesi kurala uygun: ayrı commit `5528eed` yalnız `tests/sim/public_works/golden_expropriation_undo_test.gd`'yi değiştiriyor; eski değer ve neden dosyada yazılı (`1914f0e1…` -> `d28d5633…`, tek fark `politics.events.last_pressure["PE-03"]` 251 -> 252 [kayıt]).
- [okundu] `golden_x_council_trust_test.gd` test 2 körlemesine silinmedi; fark PE-03 anahtarına daraltıldı ve "kesintili koşuda büyük" ayrıca iddia ediliyor. Test 1 (kural kapalı = `c987fb3d…`) değişmedi.
- [okundu] GOLDEN_A/B (`tests/sim/m2_query_test.gd:13-14`) T-040'tan (`cc5bfbb`) beri hiç değişmedi; B-080 ve B-052 dokunmadı. Yeşil olduğu bu oturumda doğrulanmadı [kayıt: B-052 kısmi koşusu 1205 vaka, 0 hata].
- Bilinçli davranış değişikliği: kesinti ortasında kaydedilmiş eski kayıt yeni kuralla sürer (ADR-0011 Risk). Kayıt biçimi aynı, kabul.

### B-052 (sözleşme 1.10, `sim_developed_parcel_ids`) — PASS
- [okundu] Sorgu salt okunur: `EconomyState.developed_parcel_ids` paketli sütun taraması, yeni dizi döner, durum yazmaz. `developed_by_sim` tanımı tek işlevde (`economy_state.gd:122-123`, tarama `:129`), `decorate_view` aynısını çağırıyor: iki tanım kayamaz.
- [okundu] Taban `SimFacade.sim_developed_parcel_ids()` soyut değil ve doğru (dilimli `parcel_views` süzgeci); mock/eski uygulamalar doğru sonuç verir, tüketici yeteneğe göre dallanmaz.
- [okundu] Sürüm: `VERSION_MINOR := 10`, `VERSION := "1.10"`. `is_compatible` tamsayı ayrıştırıyor (`sim_contract.gd:60-64`), mock yükleyici ve `SimSnapshot` aynı işlevi kullanıyor. `src/`, `tools/`, `tests/` içinde dizgi/float sürüm karşılaştırması bulunmadı (grep). Kilitli testler 1.10'a çekilmiş, eski sürümler ("1.0".."1.9") hâlâ uyumlu iddiası var.
- [okundu] `SimSave.VERSION` 2, değişmedi. ADR-0005 Ek M yazılmış.
- [okundu] `SimContractChecks.check_developed_ids` yalnız testlerden çağrılıyor (`check_facade` çalışma anında çağrılmıyor, grep): çalışma anı maliyeti yok.
- [okundu] Projector: T0 süpürmesi ve `_t0_occupied` tamamen kalktı, artık çağıran yok (grep `sweep_pending|SWEEP_BUDGET_US|t0_sweep` boş). `_full_sync` listede olmayanı hemen unutur, `_plans` önbelleği de budanır (bellek sızıntısı kapalı).
- Ölçüm [kayıt, Intel Mac, tek koşu]: yükleme sonrası eşitleme 1478-1554 ms -> 15-21 ms; süpürme kareleri 0. ADR-0011 hedefi (<= 100 ms) sağlandı.

### Ayrılık ve tek dünya (TEK-01..03) — PASS
- Bu aralıktaki tüm görünüm/UI değişiklikleri (`src/view/buildings`, `src/ui/flows`, `src/ui/hud`) sim'i yalnız facade üzerinden okuyor [okundu]. Sim tarafındaki tek davranış değişikliği B-080.

### Bulgular (düzeltme belge/test düzeyinde)
| # | Yer | Bulgu | Neden önemli |
|---|---|---|---|
| A1 | `artifacts/verify/full-latest.json:4` | Son tam PASS `34eae42`; `05c5a13`'e kadar sim + sözleşme + görünüm değişti | Kapanış "tam doğrulandı" ancak yeni tam koşu ile denebilir (Karar koşul 1) |
| A2 | `src/ui/flows/decision_panels.gd:20,255-262` (B-042 hafifletmesi) | ~22 ms'lik `CouncilTrustNotice.affected_members` artık 7 günde bir koşuyor, kök neden (her meclis bloğu için tüm gerekçe kaydının taranması) duruyor. Önbellek anahtarı gün farkı: aynı ya da yakın güne kayıt yüklenirse önceki oturumun sonucu en çok 6 gün gösterilebilir; sim taramasıyla fazı hizalı değil, şerit 6 güne kadar geç kalabilir | Bayat da olsa gerçek sim verisi (sahte sayı değil), ama "görünen neden = işleyen neden" (SIM-12) gecikmeli. Ayrıca en hızlı hızda kare bütçesi (aşağıda §2) |
| A3 | `production/bugs/B-042.md` | Düzeltme "pencereli ölçüm yok" ile kapandı | Düzeltmenin kare etkisi ölçülmedi |
| A4 | `production/bugs/B-028.md:3` | Durum hâlâ "AÇIK"; düzeltme `a38c3a7`'de yapıldı | Kayıt tutarlılığı |
| A5 | `production/bugs/B-030.md` | D-021 ("yıkım meclis güvenini düşürür") sonrası gözlem bayat olabilir | Kapanış listesinde yanlış "açık" görünür |

## 2 · Kare bütçesi (ADR-0010) — bugünkü durum

**Önemli: ADR-0010 Karar 2 tablosundaki "Ölçülen" sütunu `121ff46` (2026-11-05 00:21) yapısından.** Ondan sonra B-040, B-081 (her tick'li karede +~22 ms gerilemesi), B-041, B-042, B-052, iPad çekmecesi ve D-023 girdi. Bugünkü yapının kararlı evresi masaüstünde **yeniden ölçülmedi**.

| ADR-0010 satırı (masaüstü) | En son ölçüm | Yapı | Bugünkü durum |
|---|---|---|---|
| Kararlı ort <= 14 / tick'siz p95 <= 20 (D-007) | 6,04 / 8,35-8,68 ms | `121ff46` [kayıt] | Geçmesi beklenir [varsayım]; HEAD'de ölçülmedi |
| Kararlı p95 <= 16,6 (tavan 20) | 8,73-8,86 ms | `121ff46` [kayıt] | HEAD'de ölçülmedi |
| Kararlı p99 <= 25 (tavan 33,3) | 11,40-11,59 ms | `121ff46` [kayıt] | **Risk:** en hızlı hızda tick'li kare ~her 3,4 karede bir [kayıt, B-042]; güven şeridi 7 tick'te bir -> karelerin ~%4'ü ~28-30 ms [hesap] -> p99 ~28-30 ms, hedefin üstünde, tavanın altında. Normal hızda (tick'li kare %2,4) bu kareler ~%0,35 -> p99 etkilenmez [hesap]. Ölçülmedi |
| Eylemsiz tek kare maks <= 33,3 (tavan 66,6) | 18-20 ms | `121ff46` [kayıt] | B-081 sonrası tick'li kare 33-36 ms ölçüldü (B-042 öncesi) [kayıt]; B-042 sonrası ölçülmedi |
| En kötü etkileşim karesi <= 50 (tavan 100); >33,3 ms kare <= 3 | 47-57 ms; >33,3 ms kare 5-54 (HUD dahil, yük 3,7-5,1) | `04375fb` (B-041, B-042 öncesi) [kayıt] | **Tavan geçiyor, hedef geçmiyor** (o yapıda). HUD şeridi kapalı tanı koşusunda 34-47 ms, <= 2 kare: B-042'nin bunu sağlaması beklenir [varsayım]. `production/M2-CLOSURE.md:43`'teki "~24 ms" B-081 öncesi sayıdır, bugünü anlatmaz |
| Açılış uçtan uca <= 20 sn; örtüsüz tek blok <= 1 sn | ölçülmedi; parçalar >= ~36-40 sn [hesap, ADR-0010] | — | **Açık.** M2 sert koşulu değil; T-076 cihazda açılışı kaydetmeli |
| Draw call <= 400; RSS < 1,8 GB | 315/343; 1,46-1,48 GB | `121ff46` [kayıt] | HEAD'de ölçülmedi (çekmece/HUD çizim çağrısını artırabilir [varsayım]) |
| Yükleme sonrası eşitleme (ADR-0011) <= 100 ms | 15-21 ms | B-052 [kayıt] | Geçiyor (tek koşu) |

**iPad (ADR-0010 Karar 3): hiçbir satır ölçülmedi.** Yalnız sahibin "açıldı, çalışıyor" bildirimi var (debug kurulum, ölçüm değil).

## 3 · T-076 kapsam düzeltmeleri (çalıştırmadan önce; `production/tasks/T-076.md`)
T-076'nın sonda kalması doğru: ölçüm her şey bittikten sonraki yapıyı ölçmeli. Ama görev dosyası şu haliyle ADR-0010 Karar 3'ü kapatmaz:
1. **Bağımlılık bayat:** "T-075" görevi hiç açılmadı; işi B-040/B-041/B-042 yaptı. Bağımlılık "B-040..B-042 + kapanış HEAD'inde verify full PASS" olmalı.
2. **Karşılaştırma tabanı bayat:** kabul 2 ve 3 `121ff46` sayılarını (ort ~7,1, yol 130-207 ms) veriyor. **Aynı yapı masaüstünde de koşulmalı** (`--demo --perf-log`, 3 koşu, ADR-0010 Karar 1 kuralı) ve iPad onunla karşılaştırılmalı. Bu, masaüstü tablosunu da günceller; ayrı bir iş açmaya gerek yok.
3. **Sürüm türü çelişkisi:** T-076 "release sürüm kapsam dışı" diyor; ADR-0010 Karar 3 ölçümü release ister, debug ayrı etiketlenir. En az: debug ölçümü `debug_build: true` etiketiyle yazılır ve "ön ölçüm" sayılır; release ölçümü M3'e değil T-076'ya aittir, imza/ikon yine kapsam dışı kalabilir.
4. **Hata ayıklayıcısız soğuk açılış:** iOS'un açılışta yanıt vermeyen uygulamayı sonlandırması hata ayıklayıcı bağlıyken devre dışı kalabilir [varsayım, Apple davranışı doğrulanmadı]. Masaüstünde sahne kurulumu 31-35 sn [kayıt]. Sahibin "açıldı" bildirimi bu riski kapatmaz. Kabul ölçütüne ekle: Xcode/devicectl bağlı olmadan ana ekrandan soğuk açılış, ilk etkileşimli kareye süre (kronometre yeter).
5. **Bellek satırı yok:** `src/view/perf/perf_logger.gd` bellek yazmıyor [okundu: alan yok]. ADR-0010 Karar 3 bellek satırı için `Performance.MEMORY_STATIC` (ya da eşdeğeri) özete eklenmeli [Godot API'si `docs/engine-reference/godot/` ile doğrulanmadı] ve iOS bellek uyarısı/sonlandırması kayda geçmeli.
6. **Etkileşim karesi cihazda:** `--demo` cihazda yol göndermez (yol probe'u masaüstü aracı). Yeterli vekil: sahip cihazda bir yol çizer, PerfLogger'ın "en kötü 20 kare"si tüm oturumun en kötüsünü verir; **oturumun en kötü karesi <= 100 ms ise etkileşim tavanı da geçer** (daha sıkı). > 100 ms ise kare numarası/günü ile ayrıştırılır.
7. **Isıl:** ADR-0010 "15 dk, son 2 dk p95 <= ilk 2 dk p95 × 1,25" ister; görevde yalnız 10 dk sahip gözlemi var. PerfLogger'ın aralıklı yazımı (3600 kare) bunu zaten ölçebilir: 15 dk koşu, ilk/son pencere p95.
8. Ekran yenileme hızı (60/120 Hz) ve Düşük Güç Modu kayda yazılır (PerfLogger `refresh_hz` yazıyor [okundu]).

T-076 öncesi **önerilen, sert değil:** B-042'nin kök düzeltmesi (ui-engineer, küçük): güven şeridi sonucunu gün farkıyla değil, gerekçe kaydı sayacı/`last_event_seq` değişince yenile (B-042'nin kendi önerisi). Hem 22 ms'yi çoğu tick'ten kaldırır hem A2'deki bayatlığı kapatır; T-076 da gerçek son durumu ölçer. Yapılmazsa T-076'da en hızlı hızda p99 hedefi kaçabilir (§2) ve bu ölçümün yorumuna yazılır.

## 4 · Açık kalan teknik borç (M2'yi bekletmez)
| Borç | Kayıt | Ne zaman ele alınır |
|---|---|---|
| Güven şeridi kök maliyeti (gerekçe kaydının blok başına taranması) | B-042, A2 | T-076 öncesi önerilir; yoksa M3 başı |
| Yol penceresi kalan payları (bitki koridoru 9-14 ms tek kare, `step_far` 5-8 ms × ~10 kare) | B-041 | iPad ölçümü 50 ms'yi aşarsa |
| Yakın bina mesafesi ↔ üçgen (çekirdek 2,87M) ve K8 bekçisi | ADR-0010 Karar 4, T-071 | iPad ölçümünden sonra art-director + sahip |
| Açılış uçtan uca ölçülmedi; kare 1 ~4 sn'nin oyuncuya görünüp görünmediği yakalanmadı | ADR-0010 Karar 6 | T-076 cihaz açılışı + masaüstü yakalama (M3) |
| İmar/yıkım/geri al etkileşim pencereleri ölçülmedi (yalnız yol) | ADR-0010 R3, B-040 | M3 perf turu |
| Yükleme sonrası tek kare 60,7 ms (nedeni ayrıştırılmadı) | B-052 | Yükleme örtü altındaysa kabul; değilse M3 |
| Gerekçe kaydı ~100 günde düşüyor; güven şeridi bu kayda dayanıyor | B-027, B-081 | Tasarım sorusu (systems-designer); şeridin uzun oyunda kaybolup kaybolmadığı ölçülmedi |
| Açık UI hataları (belediye arazisi etiketi/taşma) | B-022, B-023, B-024 | UI, teknik engel değil |

## 5 · Doğrulanan / varsayılan / test edilmeyen
- **Doğrulandı (okuyarak, `05c5a13`):** `git diff 34eae42 05c5a13` sim/sözleşme/görünüm kısmı; commit kapsamları (`5528eed`, `81383d3`, `96102ae`); GOLDEN_A/B dosya geçmişi; sürüm tüketicileri (grep); kaldırılan süpürme sembollerinin çağıranı yok (grep); `check_facade` çalışma anında çağrılmıyor (grep); `decision_panels.gd` önbellek kodu; `perf_logger.gd` başlığı ve alanları; ADR-0010, ADR-0011, M2-CLOSURE, B-040/041/042/052/080, B-041 ölçüm kaydı, T-076, `full-latest.json`, STATE.
- **Kayıttan alındı, yeniden koşulmadı:** tüm perf sayıları; B-052 ve B-080 test sonuçları; GOLDEN_X yeni değeri; `34eae42` tam PASS.
- **Varsayıldı:** GDScript tamsayı bölmesinin platformdan bağımsızlığı; B-042 sonrası etkileşim karesinin tanı koşusu düzeyine (34-47 ms) ineceği; iOS açılış sonlandırmasının hata ayıklayıcıyla devre dışı kaldığı; `Performance.MEMORY_STATIC`'in iOS'ta anlamlı değer verdiği.
- **Test edilmedi:** hiçbir test, hiçbir Godot koşusu bu oturumda; bugünkü HEAD'in masaüstü kararlı evresi; iPad'in tüm satırları; B-042 sonrası kare etkisi.
