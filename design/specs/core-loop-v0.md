# Çekirdek döngü v0: yol çiz, imar planı sun, yatırımcı inşa etsin, halk tepki versin

Statü: **ÇALIŞMA MODELİ** (her bölüm). Sayılar kanon değil, tümü veridir. Para birimi yok (Q-003): "birim".
REQ: CAN-03, CAN-04, CAN-05, CAN-06, SIM-02, SIM-04, SIM-05, SIM-07, SIM-08, SIM-09, SIM-10, SIM-12, TEK-01/02 · Kararlar: D-008, D-009, **D-010** · Bağlı: `economy-core-v0.md`, `political-events.md`, T-042-PLAN, T-042b-PLAN, T-043A/B/C · Sorular: Q-014 AÇIK, Q-017 AÇIK, Q-003 AÇIK, Q-023/Q-024 yanıtlandı (D-010), Q-025 (halk tepkisi) yeni.
Etiketler: [okundu] kodda/veride görüldü · [ölçülü] log'dan · [hesap] bu belgede · [tahmin] doğrulanmadı · [KARAR] kullanıcı kararı (D-010).
Revizyon 2026-10-30: D-010 işlendi. Önceki "yol -> bina" akışı kaldırıldı; yol tek başına bina çıkarmaz.
Revizyon 2026-10-31: T-043A/B/C uygulandı; §1-§7 gerçek Ismeral ölçümlerine (D2, dünya tohumu 1467, başsız probe; kaynak `production/log/2026-10-31-*.md`) göre uyumlandı. **Kullanıcı kararları (D-008..D-010) değişmedi.** Bu belgedeki her sayı **çalışma değeri, kanon değil**; `[ölçülü 10-31]` etiketi yalnız o tek bölge/tohum için geçerlidir. Bölüm sonunda §9: "bugün ne var / ne yok".

## 0. Akış (D-010 ile bağlayıcı yön; ayrıntılar ÇM)
```
yol çiz -> altyapı kapasitesi -> imar planı teklifi (oyuncu) -> (meclis: Q-014 AÇIK) -> yatırımcı değerlendirir -> inşa -> hane/kira/arsa -> kesim tepkisi -> yeni gündem
```
- **[KARAR] Boş arazinin imarı çevreden TÜRETİLMEZ.** Oyuncu (belediye başkanı) imar planı teklifi sunar; yatırımcılar bu karardan ve (varsa) meclisten geçtikten sonra inşa eder. Eski Q-021 önerisi A (çevreden türetme) ve "T0 imarı" türetme satırı **iptal**.
- Yol yalnız **erişim/kapasite** koşuludur; imar yalnız **izin** koşuludur; ikisi birlikte yatırımcı kararının girdisidir (SIM-04). Biri eksikse gerekçe hangisi olduğunu söyler, ikisi de eksikse ikisini de söyler (çoklu neden).
- Oyuncu özel bina yerleştirmez (CAN-03): plan bir izin/koşuldur, "yatırımcı gelmeyebilir" (SIM-07). Oyuncuya "Konut yap" düğmesi yok; sunulan şey plandır (CAN-05).
- Mevcut mekanizma [okundu]: `zoning.propose` komutu (CAN-03 beyaz liste) parsele `pending_zone` + `due_tick` yazar (`parcel_zoning_system.gd`); `requires_council` veri bayrağı `data/politics/council.json` (`zoning.propose: true`, yer tutucu) ve `ui_config.json` (`false`); UI'da Z tuşu / `DecisionPanels` / `zoning_flow_*`. Plan teklifi **aynı komutu** kullanır; yeni komut türü gerekmez.

## 1. İlk 5 dakika (ÇM)
Hedef: oyuncu **bölgenin neden bina almadığını okur (iki neden olabilir: altyapı, plan yok), yol çizer, plan sunar, yatırımcının kararını ve halkın tepkisini kendi eylemine bağlar.** Kaçınılacak: bina anında çıkması, hiçbir şeyin olmaması, hangi eksiğin kaldığının anlaşılmaması.
Varsayım: oyun hızı "hızlı" (4 gün/sn); başlangıç Orven kenarı açık arazi (T-043; [ölçülü] D2'de yola ≤150 m açık arazi ≈5 km²).
| Dakika | Oyuncu | Görür | Hareket eden sayı |
|---|---|---|---|
| 0:00-0:40 | Haritada bölgeyi seçer, denetçiyi açar | "Yatırım yok: plan yok" ve/veya "altyapı kapasitesi yetersiz" (SIM-12); parsel "Plansız" etiketi | boş/plansız parsel sayısı, bölge kapasitesi/yük |
| 0:40-1:30 | İnşa > Yol: mevcut yola dokunur, uzatır | yapışma halkası, önizleme, ret metni; "Altyapı kapasitesi +N"; maliyet (gösterge bütçe, T-043C) | önizlemede +N kapasite, yol maliyeti |
| 1:30 | Onaylar | yol 3D'de belirir | kapasite +N (komut referanslı); **yatırımcı henüz gelmez** ("plan yok" gerekçesi sürer) |
| 1:30-2:30 | Plan: Z / imar planı teklifi — parsel(ler)i seçer, kullanım + yoğunluk seçer, önizlemeyi okur ("ne kadar iyi şey olacak": beklenen birim, kapasite yükü, hangi kesim kazanır/kaybeder) | önizleme sim sayısıyla; gönderince "teklif verildi (gün N)"; meclis yolu açıksa oylama kartı | bekleyen plan sayısı |
| 2:30-3:30 | Zamanı izler | plan yürürlüğe girer; **o andan sonra** ≤40 gün: yakın parsellerde karar satırı "İmar planı ← teklif (gün N)", "Altyapı kapasitesi ← Yol"; bazısı onay, bazısı ret (getiri/talep) | onay/ret sayısı, planlı birim |
| 3:30-4:30 | İskeleli kademe, sonra bina (≤100 gün) | gerçek 3D yapı | konut/dükkân birimi, hane, arsa değeri, kira endeksi |
| 4:30-5:00 | Gündeme bakar | PE-01/PE-04/PE-07 tipi öğe, `cause_refs` zinciri yol/plan -> bina -> tepki | kesim şikâyeti (tek skor değil, SIM-09) |
**Gerçek ölçüm [ölçülü 10-31, D2, 108 m yol, 12 parselik `zone.mixed` planı]:** plan yürürlüğünden ilk inşaat **12 gün**, ilk bina **66 gün**, 12 parselin sonuncusu 81-86 gün; 4 gün/sn'de 3,0 sn / 16,5 sn / ~21 sn. Yani tablodaki "≤40 / ≤100 gün" ölçütü tutuyor; ama "2:30-3:30" ve "3:30-4:30" satırları gerçekte ~20 sn'ye sıkışıyor (his testinde bu çok hızlı bulunabilir: tempo veri, ayarlanır). Yol 108 m'de yalnız **3 parsel** inşa edilir, 248 m'de **7**: geri kalanı altyapı kapasitesine sığmaz (ret `infrastructure_exhausted`, gerekçede yol komutu). "4:30-5:00 halk tepkisi" satırı bugün **sessiz** (§9).
Not: bu akış eski akıştan **bir oyuncu adımı uzundur**; 5 dakikaya sığması B+C tempo ölçütlerine (§2) ve plan teklifinin 1-2 dokunuşta verilebilmesine bağlıdır [tahmin: his testi §5 gözlem 6 ile doğrulanır].
Döngü (F03): oyuncu kararı (yol, plan) -> kapasite + izin -> yatırımcı kararı (gerekçe) -> bina -> hane/kira/arsa -> kesim tepkisi -> yeni gündem (2. yol, farklı plan, geri alma). Yanlış yolda ret gerekçesi görünür ve **hiçbir şey olmaz**; yanlış planda (talep/getiri yok) plan geçer ama yatırımcı gelmez (SIM-07); başarısızlık da oyundur. İki oyuncu farklı plan/yol seçebilir (SIM-10).

## 2. "Plansız arazi" durumu (ÇM)
**Bugün [okundu]:** parselin imarı kaynak şablondan (`_base_zone`) gelir; oynanabilir şablonda boş parseller placeholder `zone.residential` ile başlar (`economy_config.json`: izinli kullanım `residential`) ve oynanabilir altyapı kapasitesi +%30 payla (`playable_economy.json`). Sonuç: yatırımcı **plan olmadan da** konut inşa edebilir; "plan yok" gerekçesi hiç görünmez; yol, pay açıkken hiçbir şeyi açmaz. D-010 bu placeholder'ı nedensellik dışı bırakır.
**Önerilen model (veri bayrağı `unplanned_land.enabled`):**
| Parsel durumu | Tanım | Yatırımcı davranışı | Görünürlük |
|---|---|---|---|
| `unplanned` | T0'da gelişmemiş + yürürlükte bir oyuncu planı yok (`parcels.overlay` kaydı yok / yürürlükte imar yok) | **değerlendirmez / `zoning.unplanned` gerekçesiyle reddeder**; placeholder imar yok sayılır | haritada nötr "plansız" doku/etiket (renk kodu ui-engineer), denetçide gerekçe |
| `proposed` | teklif verildi, `pending_zone` var, `due_tick` gelmedi (veya oylama sürüyor) | inşa etmez ("plan bekleniyor") | "Teklif verildi, yürürlük gün N" |
| `planned` | plan yürürlükte | normal karar (kapasite, getiri, talep, finansman) | kullanım + yoğunluk |
| `plan_rejected` | meclis yolu açıkken oylama reddetti | `unplanned` gibi; yeniden teklif edilebilir | oylama sonucu kartı |
| T0'da yapılı | mevcut yapı | **mevcut imarı korur** (değişmez); Q-017 gereği yıkım yok | bugünkü davranış |
Kurallar:
- `unplanned_land.enabled=false` (varsayılan yapılandırma) = bugünkü davranış bit-eşit (GOLDEN_A/B ve t0 hash'i değişmez). Oynanabilir yapılandırma `true` yapar. Yeni durum sütunu/anahtarı **yaratılmaz**: durum mevcut `parcels.overlay` kayıtlarından türer (yalnız dokunulan parsel girer; T-042 deseni). "T0'da gelişmemiş" bilgisi `_cache_static` / T0 stokundan [doğrulanmadı: world/economy-engineer teyit eder].
- Yatırımcı `zoning` bileşeni mevcut `w_zoning` yolundan geçer; ret nedeni `unplanned` ayrı gerekçe anahtarı olarak kaydedilir (`reason_log`), UI metni `strings.tr.json`'a ui-engineer ekler.
- Plan hakkı: oyuncu aynı parsel için yeniden teklif verebilir; yürürlükteki planı değiştirme (yapılıysa yıkım yok) Q-017 kapsamıdır, bu belge dışı.
- Bekleyen plan sayısı ve gündem yükü: toplu teklifte tek oylama/tek komut (komut başına parsel listesi; üst sınır veri `plan_max_parcels_per_proposal`, öneri 40).
**Sonuçlar (bilinçli):**
1. Başlangıçta oyuncu hiçbir şey yapmazsa (yol ve plan yok) **hiç bina çıkmaz**; bu bir başarısızlık değil, D-010'un doğrudan sonucudur. T0 yapıları kalır, ekonomi mevcut yapılarla işler.
2. Yaşayan dünya hissi riski: bütün boş arazi donuk kalır; mevcut mahalleler çalışmaya devam eder (kira, hane). Bu risk his testi §5 gözlem 6 ile izlenir; çare "otomatik plan" olmaz (D-010'a aykırı), sunum/gündem ipuçları olur.
3. ~~Placeholder +%30 kapasite payı yol nedenselliğini gizler.~~ **Çözüldü (veri, 2026-10-31):** oynanabilir başlangıç boş kapasite `min(yük x %30, infra_free_units_max=0) + 1` birim; yük/kapasite oranı ~%99,9 ve altyapı bonusu kapalı (`infra_bonus_max=0`, `base_threshold=300`: boş bölgede skor eskisiyle aynı). [ölçülü 10-31, D2] önce: boş kapasite ~2795, yolsuz plan 12 bina (yol hiçbir şeyi değiştirmiyordu); sonra: yolsuz plan **0 bina**, yol+plan **3 bina**. Kontrol (`-1` = sınırsız) eski davranışı verir; sim varsayılanı/GOLDEN değişmedi. Sayı çalışma değeri, kanon değil; "dar başlangıç" bir denge kararıdır (§7).
4. Altın/hash etkisi: yalnız `unplanned_land.enabled=true` koşularda (oynanabilir config, kayıtlı yakalamalar) davranış değişir; kontrollü yeniden tabanlama T-043A içinde (görev dosyasında plan).
5. T-041 / T-043 demo ve yakalamaları (ör. imar demosu) plan akışına göre yeniden çekilecek; "Konut yap" benzeri kısayol eklenmez.

## 3. Tempo (ÇM, [KARAR] B+C seçildi)
Veri [okundu]: `core_config.json`: 1 tick = 1 sim günü; hızlar 1/4/16 tick/sn; demo `set_speed(3)` = en hızlı. Ekonomi: `plan_days` 10, inşaat 45 + 3·birim gün, `attention_delay_days` 2, tarama `review_period_days` 10, oynanabilir `max_reviews_per_tick` 8. [ölçülü] Q-016: zorunlu dikkat yolunda (imar önerisi) gün 40 inşaat, gün 100'de 7/8 bitmiş. **[ölçülü 10-31, gerçek dünya]** B kuyruğu açık: ilk inşaat 12 / ilk bina 66 gün (hedef 40/100 tutuyor). Ama kuyruk **bu veride hızı değiştirmiyor**: kuyruk kapalı da 12/66; fark yalnız başlangıçları 12-17. güne yaymak. Gerçek faydası "bekleme rastgele olmasın" garantisi ve plan->yol sıralamasında (sentetik testte kuyruksuz 161/215 gün); gerçek veride bu fark gözlenmedi. Tohum 1467/2/3 aynı günler. Sim maliyeti [ölçülü 10-31]: yol onay tick'i 9-12 ms (önce 62-88), ay sınırı <=8 ms, ilk tick 3,2 ms, ortalama tick ~3 ms; demo karesi 45,2 -> 14,6 ms (gerekçe paneli düzeltmesi). Başsız, i7-8850H; iPad ölçülmedi.
**Ölçütler [KARAR yönü, sayılar ÇM]:** *tetikleyici olaydan* (bölgenin hem erişimi hem planı tamamlandığı SON olay: yol onayı veya plan yürürlüğü) ilk inşaat ≤~40 gün, ilk tamamlanan bina ≤~100 gün; "hızlı" hızda ~25 sn (100 gün ÷ 4). Hepsi onay değil: ret dağılımı kalır.
| Parça | Ne yapar | Katman | Hash/determinizm |
|---|---|---|---|
| **B. Öncelikli değerlendirme** | Tetikleyicide, olayın `R` m yakınındaki en çok `K` uygun boş parsel `attention_delay_days` sonra zorunlu değerlendirilir (ön eleme yok); `max_reviews_per_tick` ile dağıtılır; gerekçe `command.N` taşır. Uygunluk: yürürlükte plan VE bağlı yol; plansız parsel kuyruğa girmez | sim | Kuyruk yalnız ilk tetikte yaratılır (T-042 deseni): yolsuz/plansız koşuda t0/GOLDEN değişmez; kayıt sürümü artar; tekrar oynatma bit-eşit |
| **C. Zaman hızı** | Başlangıç hızı "hızlı"; yol/plan sonrası ipucu | oyun | Hız durumun parçası değil; hash etkisi yok |
| A (sıklık artır) | YOK | — | Kare bütçesi (4,3 -> 15+ ms [ölçülü]) |
Tetikleyicisi iki olay olduğundan: plan yürürlüğe girdiğinde yol zaten varsa B kuyruğu planın komut kimliğiyle açılır; yol sonra gelirse yolun komut kimliğiyle. Gerekçede iki kaynak da görünür.
Gizleme riski (SIM-08): C yalnız hızı seçer; bekleme süresini saklamaz (gün sayacı görünür).

## 4. Eksik temel veriler: en küçük işe yarar v0 (ÇM)
| Veri | Bugün | v0 | Karar |
|---|---|---|---|
| Başlangıç arsa değeri | 0 [okundu: görev girdisi]; çarpansal güncelleme taban 0'da hep 0 [tahmin] | `L = land_share_pm · units_potential · cost_per_unit(kullanım)` / 1000; planlı olmayan parselde kullanım yoktur: arsa değeri **plan yürürlüğe girince** tanımlanır (plan = arsa değerini açar; spekülasyon SIM-07 için doğal kapı) [tahmin, ekonomi-engineer teyit eder]. Tuzak: "artık değer" mevcut sayılarla hiç bina üretmez [hesap] | bölge farkı, yolun arsa etkisi sorulmadı |
| T0 imarı | ~~çevreden türetme~~ **İPTAL** (D-010) | yapılı parsel: mevcut; boş parsel: `unplanned` | kapandı |
| Belediye bütçesi | **T-043C kuruldu (2026-10-30)**: sim `src/sim/budget/`, `BudgetPanel` gerçek veriyle, yol önizlemesinde "Maliyet: N birim". Kasa yalnız gösterge; kısıt, tahsis (`budget.propose` hâlâ kurulmadı), hizmet kapasitesi YOK (T-014'ün kalanı) | **Gösterge bütçe** (uygulandı; yer tutucu `initial_balance` 50000, `tax_rate_pm` 100, `public_cost_share_pm` 100, çalışma değeri): gelir = bina birimi · `rent_per_unit_month` · `tax_rate_pm` aylık; gider = yol: eklenen altyapı birimi · `cost_per_unit` · `public_cost_share_pm`; kasa yalnız gösterge, hiçbir komutu reddetmez | [KARAR] önce gösterge; vergi oranı/başlangıç kasası yer tutucu |
| Yolun etkisi | uygulandı: `road_works.json` `infra_units_per_km` | **çalışma değeri 100 birim/km** (sim varsayılanı; formül yerine sabit). [ölçülü 10-31, D2] 108 m -> 10 birim -> 3 bina; 248 m -> 24 birim -> 7 bina; deneme 160/km (eski `K·medyan/0,3 km` formülünün verdiği) -> 108 m'de 4 bina. Yol uzunluğu bina sayısını belirler (SIM-10 için iyi; "yol çok kısa" ise ret gerekçesi altyapı). Değer kanon değil; 100 mü 160 mı denge kararı | — |
| Başlangıç boş kapasite (yol bölgesi) | pay %30 | `infra_free_units_max` = **0** (mutlak birim; +1 artık), `infra_headroom_pm` 300 korundu (küçük bölge eski değeri `min(pay, sınır)` ile korur) | çalışma değeri; kontrol `-1` |
| Plan önizlemesi ("ne kadar iyi şey olacak") | yok; yalnız `proposal_effects` tabloları (meclis için) [okundu] | önizleme sim sorgusundan: seçili parsellerin potansiyel birimi, kapasite yükü, `proposal_effects` kesim yarar/zarar işareti | içerik düzeyi Q-024 |
Kural: HUD'a yalnız hesaplanan sayı girer; sim'de hesabı olmayan alan "henüz kurulmadı" (sahte sayı yok).

## 5. Kamulaştırma (T-042b) oyuncu yüzü (ÇM; hepsi seçenek)
[KARAR] sıra: **önce gösterge bütçe, kamulaştırma sonra** (D-010). D-009 yönü: yol binaların içinden de geçebilir. Q-017 kuralı AÇIK; **hiçbiri uygulanmaz**; v0 ret metni "kamulaştırma henüz yok". Teknik plan: `production/tasks/T-042b-PLAN.md` (A: sabit küme + `STAGE_TAKEN`, ÖNERİLEN, commit'siz ADR Ek F). Plan akışı ile ilişki: kamulaştırılan boş arazi sonra `unplanned` olur ve yeniden plan ister [tahmin].
| Eksen | Seçenekler (öneri ilk) |
|---|---|
| Hangi bina | (1) eksenin kestiği parsellerin tamamı · (2) yalnız koridor, parsel bölünür · (3) oyuncu parsel parsel |
| Maliyet | (1) arsa + yapı + `premium_pm` · (2) yalnız arsa · (3) sabit |
| Önizleme | kaç parsel, kaç hane, bedel, hangi kesim (veriden) |
| Tepki | yerinden olan hane -> PE-01, medya PE-04; direnç tekrarlanırsa artar |
| Geri alma | teklifte serbest · itiraz penceresi · yıkım başlayınca yok |
| Yetki | meclis gerekir mi: Q-014 |

## 6. Denge ve his test planı (ilk oturum, 3-5 kişi, açıklamasız)
| # | Gözlem | Geçti | Kaldı |
|---|---|---|---|
| 1 | Neden: "bölge neden bina almıyor" | ≥4/5 ilk 90 sn'de en az bir nedeni söyler (plan yok / kapasite) | ≥2/5 nedene bakmadan rastgele çizer |
| 2 | Tempo: tetikleyiciden ilk inşaat, ilk bina | ≤40 gün / ≤100 gün (hızlıda ≤~30 sn) | ilk bina >60 sn |
| 3 | Sapma/başarısızlık: aynı yol+plan 5 tohum | bina sayısı tohumlar arası farklı; ≥1 görünür ret | hep hepsi onay ya da hiç bina |
| 4 | Tepki: 5 dk içinde nedeni zincirli gündem öğesi | ≥1 öğe, ≤2 kesinti | hiç ya da ≥3 kesinti |
| 5 | Sayı gerçekliği: kötü yol (bağlantısız) | ret anlaşılır (≥%80), sayı oynamaz | sahte hareket |
| 6 | **Plan adımı:** oyuncu yoldan sonra plan vermesi gerektiğini ipucu sormadan bulur ve planı ≤2 dk içinde gönderir | ≥3/5 | ≥3/5 "neden bina çıkmadı"da takılır (ipucu/akış yetersiz) |
| 7 | **Plansız arazi:** yol çizip plan vermeyen oyuncu | "plan yok" gerekçesini okur (≥%80) | "oyun bozuk/bekliyor" yorumu |
**Durum [10-31]:** gözlem 1-7 **insanlarla HİÇ denenmedi** (his testi yapılmadı). Otomatik/probe karşılığı olanlar: gözlem 2 tempo (ölçüldü, geçer: 12/66 gün), gözlem 3 (tohumlar arası aynı gün sayıları ama farklı durum hash'i; "bina sayısı tohumlar arası farklı" **kanıtlanmadı**, tohum 2 ve 3'te de 3 bina), gözlem 4 tepki (**bugün kalır**: yol+plan sonrası 400 günde grup tepkisi 0, §9), gözlem 5/7 (plansız ve yolsuz plan reddi testli).
Otomatik karşılıklar (qa-engineer): 5 tohumlu çift senaryo, kayıt/yükleme sonrası N tick hash eşit, GOLDEN_A/B (`enabled=false`) değişmez, oynanabilirde yeni tabanlı hash tekrar oynatmada eşit.
Test senaryoları: **olumlu** yol + plan -> tetikleyiciden ≤40 gün içinde ≥1 parsel `approved`, etken `source_ref` plan komutu ve yol komutu. **Olumsuz 1** yol var plan yok -> tüm boş parsellerde `zoning.unplanned` reddi, bina 0, kapasite +N. **Olumsuz 2** plan var yol/kapasite yok -> `infra` reddi, bina yok. **Uç** plan meclis yolunda reddedilir -> `plan_rejected`, yeniden teklif edilebilir; yol geri alınır -> `stalled`.

## 7. Parametre tablosu (hepsi ÇM, test fikri)
| Parametre | Öneri | Gerekçe / test |
|---|---|---|
| `unplanned_land.enabled` | varsayılan false; oynanabilir true | altın korunumu; iki durumda kontrol testi |
| `decision.priority_radius_m` (R) / `decision.priority_max_parcels` (K) | 150 / 12 (uygulandı: `priority_review_enabled`=1 oynanabilirde) | gözlem 2; gerçek veride kuyruk yalnız başlangıçları yayıyor (§3), gün sayısı değişmiyor; K=12 ile 30 parselde son bina 87. gün |
| `plan_max_parcels_per_proposal` | 40 | UI/oylama yükü; gözlem 6 |
| `requires_council` (zoning.propose) | oynanabilirde false ("meclis yok"), bayrakla true | Q-014 AÇIK; iki yol da test |
| `infra_units_per_km` | **100** (uygulandı) | 108 m=3 bina, 248 m=7 bina; 160 deneyi 4 bina; karar sahibi: denge |
| `infra_free_units_max` (başlangıç boş kapasite üst sınırı) | **0** (uygulandı; -1 = sınırsız kontrol) | yolsuz plan 0 bina, yol+plan 3 bina; gözlem 1 |
| `decision.infra_bonus_max` / `base_threshold` | **0 / 300** (uygulandı; 150 / 450 ile boş bölgede skor eşit) | altyapı yalnız sığar/sığmaz kapısı; ret gerekçesi okunur |
| `blocs_grievance_rule_overrides` (`infra_stress` lo/hi) | **1000 / 1300** (yalnız oynanabilir) | baskı yalnız gerçek aşımda (yük > kapasite); eski kuralda yol+plan olmadan da şikâyet 1000'e doyuyordu (yanlış nedensellik) |
| `land_share_pm` | 250 | 5 tohumda onay %20-80 |
| `tax_rate_pm`, `public_cost_share_pm`, başlangıç kasası | 100 / 100 / 50000 (uygulandı, yer tutucu) | Q-003 para birimi AÇIK; kasa gösterge, kısıt değil |
| `premium_pm` (kamulaştırma) | uygulanmadı | Q-017, T-042b |
| başlangıç oyun hızı | "hızlı" (4 gün/sn, uygulandı) + hız ipucu | gözlem 2; 12/66 gün = 3,0/16,5 sn çok hızlı bulunursa hız ya da `attention_delay_days` ayarlanır |

## 8. Açık sorular
- ~~Q-023~~ "Zoomlarda" aslında "zone'larda" (D-010 düzeltmesi): oyuncu imar bölgesi (zone) seçerek parsellerin ne olacağını belirler; zoom ile ilgisi yok.
- **Q-024** İmar planı teklifinin içeriği ve önizlemesi ("ne kadar iyi şey olacak").
- Q-014 meclis onayı (AÇIK; "meclis" ifadesi D-010'da geçti ama zorunluluk açıkça söylenmedi) · Q-017 yıkım · Q-003 para birimi · Q-015/D-002 başlangıç noktası.
- Q-020/Q-021/Q-022 D-010 ile yanıtlandı (kayıtları güncellendi).

## 9. Bugün ne var, ne yok (2026-10-31; ÇM)
**Çalışıyor [doğrulandı: `verify full` PASS @ b6fa635, 2225 test, 0 hata; sonrası yalnız `quick` 920, kısmi]:** yol çiz (D-009 kuralları, geri alma) -> bölge altyapı kapasitesi (+N birim) -> plansız arazi + plan teklifi (kullanım + yoğunluk, sim önizlemesi) -> yatırımcı değerlendirmesi (plan VE kapasite şartı, gerekçe iki kaynağı birlikte) -> iskele kademeli 3D bina -> hane/kira/arsa -> gösterge bütçe. Olumsuz yollar testli: yalnız yol 0 bina, yalnız plan (yolsuz) 0 bina, kapasiteyi aşan parseller ret.
**Eksik / sessiz (bilerek):**
| Parça | Durum | Neden / bağ |
|---|---|---|
| Halk tepkisi (D-008 son adımı) | **Sessiz.** Altyapı baskısı şikâyeti yalnız gerçek aşımda (yük > kapasite) başlıyor; yol+plan 400 günde grup tepkisi 0, gündem 0 [ölçülü 10-31]. İnşaat baskısı D2'de kesime ulaşmıyor (kesim payı ~%7,5 < `min_share_pm` %10) | Önceki "tepki" yanlış nedenseldi (akışsız da aynı tepkiler). Tepki ne tetiklesin? Karar bekliyor: `production/QUESTIONS.md` Q-025 |
| Meclis | Yok (`requires_council.zoning.propose=false`; iki yol testli) | Q-014 AÇIK |
| Bütçe | Gösterge: kısıt yok, tahsis/oylama yok, hizmet kapasitesi yok | T-014'ün kalanı; Q-022 kalan, Q-003 |
| Kamulaştırma/yıkım | Yok; ret metni "kamulaştırma henüz yok"; yapılı parsel imarı değişmez | T-042b, Q-017 |
| PE-07 (hizmet aşımı) | Hiç tetiklenmedi (yük hiç kapasiteyi aşmadı) | yol geri alma akışı ile ölçülmedi |
**Test edilmemiş:** başka bölgeler (D1, D3-D6) ve dünya tohumları; çok yollu zincir; ikinci plan; insanlarla his testi (§6); iPad; pencereli kare süresi yol tick'i/`RoadDraftCheck` (rank 1 gönderim ~14 ms) dahil; yol geri alma sonrası siyaset etkisi.
**Tasarım riski (açık):** yol+plan ile hızlı ve her seferinde aynı sayıda bina (tohumlar arası fark yok) SIM-10'a (sapma) zayıf; çare tohum başına getiri/talep/finansman varyansı, bu veride ölçülmedi.
