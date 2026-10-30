# Çekirdek döngü v0: yol çiz, bina çıksın, halk tepki versin

Statü: **ÇALIŞMA MODELİ** (her bölüm). Sayılar kanon değil, tümü veridir. Para birimi yok (Q-003): "birim".
REQ: CAN-03, CAN-04, CAN-05, CAN-06, SIM-02, SIM-04, SIM-05, SIM-07, SIM-08, SIM-09, SIM-10, SIM-12, TEK-01/02 · Kararlar: D-008, D-009 · Bağlı: `economy-core-v0.md`, `political-events.md`, T-042-PLAN, Q-017/020/021/022.
Etiketler: [okundu] kodda/veride görüldü · [ölçülü] log'dan · [hesap] bu belgede · [tahmin] doğrulanmadı.

## 1. İlk 5 dakika (ÇM)
Hedef: oyuncu **bölgenin neden bina almadığını okur, yol çizer, yatırımcının kararını ve halkın tepkisini kendi eylemine bağlar.** Kaçınılacak: bina anında çıkması, hiçbir şeyin olmaması, anlaşılmaz ret.
Varsayım: oyun hızı "hızlı" (4 gün/sn); başlangıç Orven kenarı açık arazi (T-043; [ölçülü] D2'de yola ≤150 m açık arazi ≈5 km², ~160 çıkış kenarı).
| Dakika | Oyuncu | Görür | Hareket eden sayı |
|---|---|---|---|
| 0:00-0:40 | Haritada bölgeyi seçer, denetçiyi açar | "Yatırım yok: altyapı kapasitesi yetersiz" gerekçesi (SIM-12) | bölge kapasitesi/yük, boş parsel sayısı |
| 0:40-1:30 | İnşa > Yol: mevcut yola dokunur, uzatır | yapışma halkası, yeşil/uyarı önizleme, ret metni; panelde uzunluk, "Altyapı kapasitesi +N", "Maliyet: henüz kurulmadı" | önizlemede +N kapasite |
| 1:30 | Onaylar | yol 3D'de belirir | kapasite +N (komut referanslı) |
| 1:30-2:30 | Zamanı izler | yakın parsellerde karar satırı: "Altyapı kapasitesi ← Yol (gün N)"; bazısı onay, bazısı ret (getiri/talep) | onay/ret sayısı, planlı birim |
| 2:30-4:00 | İskeleli kademe, sonra bina | gerçek 3D yapı (kat kademesi) | konut/dükkân birimi, hane, arsa değeri, kira endeksi |
| 4:00-5:00 | Gündeme bakar | PE-01/PE-04/PE-07 tipi bir öğe, `cause_refs` zinciri yol -> bina -> tepki; seçenekler | kesim şikâyeti (tek skor değil, SIM-09), hizmet doluluğu |
Döngü (F03): oyuncu kararı -> kapasite -> yatırımcı kararı (gerekçe) -> bina -> hane/kira/arsa -> kesim tepkisi -> yeni gündem (2. yol, imar, geri alma). Yanlış yolda (bağlantısız, dik, parsel kesen) ret gerekçesi görünür ve **hiçbir şey olmaz**; başarısızlık da oyundur (SIM-07). İki oyuncu farklı yön seçebilir (SIM-10).
**Önkoşul:** [okundu] oynanabilirde kapasite +%30 payla başlıyor (`playable_economy.json`); pay açıkken yol hiçbir şeyi açmaz, nedensellik görünmez. Yol bölgesinde başlangıç boş kapasite dar olmalı (`--infra-free` dev senaryosu bunu yapıyor [okundu]); değer ÇM, §5 gözlem 1 ile ayarlanır.

## 2. Tempo (ÇM)
Veri [okundu]: `core_config.json`: 1 tick = 1 sim günü; hızlar 1/4/16 tick/sn; demo `set_speed(3)` = en hızlı. Ekonomi: `plan_days` 10, inşaat 45 + 3·birim gün (4 birim: 57), `attention_delay_days` 2, tarama `review_period_days` 10, oynanabilir `max_reviews_per_tick` 8.
Hesap [hesap]: 330 gün = 5,5 dk (normal) · 82 sn (hızlı) · 20,6 sn (demo 16 gün/sn). Sabit boru hattı ≈ 10+57 = 67 gün; kalan ~260 gün **değerlendirmeyi beklemek** [tahmin: 330 ajan bulgusu, kırılımı doğrulanmadı]. Q-016 [ölçülü]: imar önerisi yolunda (zorunlu dikkat) gün 40 inşaat, gün 100'de 7/8 bitmiş: yani hızlı yol zaten var, yol komutu onu kullanmıyor.
**Önerilen hedef** [ÇM]: onaydan ilk inşaat ≤40 gün (hızlıda 10 sn), ilk tamamlanan bina ≤100 gün (hızlıda 25 sn; normalde 100 sn). Hepsi onay değil: ret dağılımı kalır.
| Seçenek | Ne yapar | Determinizm / altın hash | Risk |
|---|---|---|---|
| A. Sıklık artır | `max_reviews_per_tick` 8 -> 15/60, `review_period_days` kısalt | Kod aynı, yalnız veri. GOLDEN_A/B (varsayılan yapılandırma) değişmez; oynanabilir koşu/yakalama hash'leri değişir; eski kayıt/yapılandırma uyumu [doğrulanmadı] | Tick 4,3 -> 6,9 -> 15+ ms [ölçülü, Q-016]: kare bütçesi 16,6 ms; bekleme yine rastgele |
| B. Yol sonrası öncelikli değerlendirme | Yol kabulünde, yola ≤R m en çok K boş parsel `attention_delay_days` sonra **zorunlu** değerlendirilir (imar yolunun aynısı, ön eleme yok), gerekçe `command.N` taşır | Yeni durum (kuyruk) yalnız ilk yolda yaratılır (T-042 deseni): yolsuz koşuda t0/GOLDEN değişmez; yollu koşu yeni ama tekrar oynatmada bit-eşit; kayıt sürümü artar | K, R yeni sayılar (§6); bol K tek tick'te maliyet: kuyruk `max_reviews_per_tick` ile dağıtılır |
| C. Zaman hızı | Başlangıç hızı "hızlı", yol sonrası ipucu | Hız durumun parçası değil: hash etkisi yok | Gecikmeyi gizler (SIM-08); normal hızda 5,5 dk kalır |
Öneri: **B + C**, A yok (kare bütçesi). Q-020.

## 3. Eksik temel veriler: en küçük işe yarar v0 (ÇM)
| Veri | Bugün | v0 türetme (yeni sayı yok / en az) | Kullanıcı kararı |
|---|---|---|---|
| Başlangıç arsa değeri | 0 [okundu: görev girdisi]. Hipotez [tahmin]: `_update_land_values` çarpansal olduğundan taban 0 iken spekülasyon (SIM-07) hep 0; ayrıca `outlay` yalnız inşaat maliyeti olup getiri şişer | `L = land_share_pm · units_potential · cost_per_unit(kullanım)` / 1000. Mevcut `cost_per_unit`, `units_per_1000m2`, parsel alanından; tek yeni oran `land_share_pm`. Tuzak: "artık değer" (kira/faiz − maliyet) mevcut sayılarla 1400/birim verir, net getiri = faiz olup **hiç bina gelmez** [hesap] | Bölge farkı (merkez pahalı) istenir mi; yol arsa değerini artırsın mı (mevcut `access_pm` yolu ile ayrı adım) |
| T0 imarı | Boş parselde imar yoksa `zoning` reddi; aktarım [doğrulanmadı] | Çevre yapıların çoğunluk kullanımı (bağlı blokta/komşu parselde), eşitlikte `zone.mixed`; "başlangıç durumu", komut değil (T0 stok gibi) | **Q-021** |
| Belediye bütçesi | T-014 kurulmadı; `BudgetView` sözleşmesi var [okundu] | Gelir = bina birimi · `rent_per_unit_month` · `tax_rate_pm` aylık (mevcut kira, yeni oran); gider = yol: eklenen altyapı birimi · `cost_per_unit` · `public_cost_share_pm`; kasa yalnız gösterge | **Q-022**; vergi oranı, başlangıç kasası, kısıt olup olmaması |
| Yolun etkisi | `infra_units_per_km` yok | `= K_proje · medyan_birim / 0,3 km` (K_proje ≈3 bina; medyan parsel birimi world-engineer ölçer) | — |
Kural: HUD'a yalnız hesaplanan sayı girer; bütçe kurulana kadar "henüz kurulmadı" (sahte sayı yok).

## 4. Kamulaştırma (T-042b) oyuncu yüzü (ÇM; hepsi seçenek)
D-009 yönü (kullanıcı): yol binaların içinden de geçebilir. Q-017 kuralı AÇIK: yıkım, yeniden yapılaşma, süre, bedel, tarihî yapı. **Hiçbiri uygulanmaz**; v0 ret metni "kamulaştırma henüz yok" kalır. Sim parsel kümesi statik [okundu]: kamulaştırma kümeyi değiştirecek (ayrı ADR).
| Eksen | Seçenekler (öneri ilk) |
|---|---|
| Hangi bina | (1) Eksenin kestiği parsellerin tamamı, boşalıp açık arazi olur · (2) yalnız koridor şeridi, parsel bölünür (karmaşık) · (3) oyuncu parsel parsel seçer |
| Maliyet | (1) arsa + yapı değeri + `premium_pm` · (2) yalnız arsa · (3) sabit/parsel |
| Önizleme | Onaydan önce: kaç parsel, kaç hane yerinden olur, bedel, hangi kesim etkilenir (kesim adı veriden, uydurma yok) |
| Tepki | Yerinden olan hane -> kesim şikâyeti (PE-01), medya (PE-04); direnç aynı yolda tekrarlanırsa artar |
| Geri alma | Teklif aşamasında serbest · onaydan sonra N günlük itiraz penceresi (geri çekilir) · yıkım başlayınca geri alınamaz (bedelsiz yok) |
| Yetki | Meclis onayı gerekir mi: Q-014 ile bağlı |
Q-017 ilişkisi: kamulaştırma = Q-017 seçenek 1(c); D-009 yönü kısmen cevaplıyor, kalan (bedel, süre, tarihî yapı, kim park/yeşil yapar) AÇIK. Sıra: önce §2-3 (açık arazi), sonra bu.

## 5. Denge ve his test planı (ilk oturum, 3-5 kişi, açıklamasız)
| # | Gözlem | Geçti | Kaldı |
|---|---|---|---|
| 1 | Neden: oyuncu "bölge neden bina almıyor"u söyler | ≥4/5 ilk 90 sn'de kapasiteyi söyler ve yol çizer | ≥2/5 nedene bakmadan rastgele çizer |
| 2 | Tempo: onaydan ilk inşaat, ilk bina | ≤40 gün / ≤100 gün (hızlıda ≤30 sn, ölçülür) | ilk bina >60 sn (hızlı) |
| 3 | Sapma/başarısızlık: aynı yol 5 tohum | bina sayısı tohumlar arası farklı; ≥1 görünür ret gerekçesi | hep hepsi onay ya da hiç bina |
| 4 | Tepki: 5 dk içinde bir gündem öğesi, nedeni yola zincirli | ≥1 öğe, ≤2 kesinti, zincir okunur | hiç tepki ya da ≥3 kesinti (`interrupt_budget`) |
| 5 | Sayı gerçekliği: kötü yol (bağlantısız) denenir | ret anlaşılır (≥%80), hiçbir sayı oynamaz; iyi yolda ≥3 sayı oynar, oyuncu "ne değişti"yi doğru söyler | sahte hareket, anlaşılmaz ret |
Otomatik karşılıkları (qa-engineer): 5 tohumlu çift senaryo (T-042-PLAN §4), kayıt/yükleme sonrası N tick hash eşit, GOLDEN değişmez.
Test senaryoları: **olumlu** dar kapasiteli bölgede bağlı yol -> ≥1 parsel `approved`, etken `source_ref=command.N`. **Olumsuz** aynı bölgede bağlantısız yol -> ret, kapasite ve hash komutsuz koşuyla aynı. **Uç** yol geri alınır -> kapasite düşer, yük aşarsa `stalled`.

## 6. Parametre tablosu (hepsi ÇM, test fikri)
| Parametre | Öneri | Gerekçe / test |
|---|---|---|
| `road_priority_radius_m` (R) | 150 | Ölçüm tablosundaki "yola bitişik" eşiği; K=0 ve R değişince gözlem 2 |
| `road_priority_max_parcels` (K) | 12 | Q-016 imar testi 8 parsel; hız/maliyet dengesi; tick maliyeti ölçülür |
| `infra_units_per_km` | §3 formülü | Gözlem 1: ilk yol ≥1 ama hepsini değil açsın |
| başlangıç boş kapasite (yol bölgesi) | dar | `infra_headroom_pm` 300 yerine yola bağlı değer |
| `land_share_pm` | 250 | Net getiri > 0 ama faizi aşmayan aralık; 5 tohumda onay oranı %20-80 |
| `tax_rate_pm`, `public_cost_share_pm`, `premium_pm` | yer tutucu, kullanıcı kararı | Q-022 |
| başlangıç oyun hızı | "hızlı" | Gözlem 2; görünüm ayarı |

## 7. Açık sorular
Q-020 tempo hedefi · Q-021 boş arazi imarı · Q-022 bütçe/kamulaştırma ilk sürümü · Q-017 yıkım kuralı · Q-014 meclis onayı · Q-003 para birimi. Hiçbiri başlangıç noktasını (Orven vs diğer, Q-015/D-002) önceden seçmez.
