# Kullanıcı kararı bekleyen sorular

Yalnızca kanondan çözülemeyen, gerçekten yaratıcı/ürün kararları. Gruplanmış tutulur; her biri için stüdyonun beklerken ne yaptığı yazılıdır. Cevaplar `design/decisions/` altına kullanıcının sözleriyle kaydedilir.

Durumlar:
- **open** — çözülmemiş tasarım kararı; izlenir ama hiçbir görevi engellemez (stüdyo yapılandırılabilir/geri alınabilir biçimde ilerler).
- **blocked** — en az bir görevi durduruyor; `Engellediği` satırında görev kimlikleri yazılır.
- **answered → D-NNN** — kullanıcı karar verdi.

| Q | Konu | Durum | Engellediği |
|---|---|---|---|
| Q-001 | Eski POC referans görselleri | answered → D-001 | — |
| Q-002 | Başlangıç ilçesi | answered → D-002 | — |
| Q-003 | Anderva para birimi | **open** | — (engellemiyor) |
| Q-004 | Platform önceliği | answered → D-003 (+ D-004) | — |
| Q-005 | Protagonist: ad, geçmiş, görünüm, özelleştirme (AS-1) | **open** | — (engellemiyor) |
| Q-006 | Partiler: sayı, ad, ideoloji, eksenler; bağımsız adaylık (AS-2) | **open** | — |
| Q-007 | Seçim takvimi, başlangıç modu (aday / göreve gelmiş / ikisi), seçim kanunu, meclis usulü (AS-4, AS-8) | **open** | — |
| Q-008 | Kaybetme sonucu: kampanya sonu / muhalefet / karma (AS-5, CAN-10) | **open** | — |
| Q-009 | Rakipler, diğer altı metropolün liderleri, hikâye karakterleri; yazılı–sistem olayı dengesi; haber arşivi (AS-3, AS-9, AS-12) | **open** | — |
| Q-010 | İçerik tonu sınırları: yolsuzluk/çıkar çatışması sunumu, şiddet/taciz, etnik-dinsel konular, gerçek figür/olay benzerliği, hiciv (AS-6, AS-10, AS-13) | **open** | — |
| Q-011 | UX: HUD stili, açılış menüsü, istatistik biçimi, zoom akışı (sürekli/ölçek kapısı), tek/iki panel, olay kesintisi + otomatik duraklatma varsayılanı (ux-ia §9, AS-11) | **open** | — |
| Q-012 | Oyun içi takvim biçimi; Türkçe alt başlık istenip istenmediği | **open** | — |
| Q-015 | Ismeral coğrafyasının yaratıcı onayı: T-001 çıktısı (körfez, ada dizisi, D1–D6 yerleşimi, D1 kuzey kıyıda çıkarımı, liman sahası) kullanıcı tarafından onaylandı mı? | **open** | yalnız KALICI koordinata bağlı işler (aşağıda) |
| Q-016 | Sim yapısı eşlemesi ve oynanabilir başlangıç koşulları: ekonomi birimi↔kit katı oranı, inşaat kademesinin görünümü (iskele modülü var mı), başlangıç altyapı kapasitesi/hane talebi, otonom yatırımcı büyümesi oynanabilirde açık mı | **open** | — (engellemiyor) |
| Q-013 | Yapı kiti: dini yapılar var mı; çatı payı oranları; T0'da 12+ kat; saat kulesi hedef boyu (T-025 S1–S4) | **open** | — |
| Q-018 | Varlık kütüphanesi (T-052): insan stilizasyonu, araç kimliği/livery, T0 tramvayı, yol kesiti genişlik ve sınıfları, mevsim, kalabalıkta kimlik işaretleri | **open** | yalnız ilgili kategorinin onayı (T-042 yol kesitleri, T-050 insan/araç); diğer işler engellenmez |
| Q-019 | Görünüm modları: serbest 3D kamera tavanı, strateji haritasının görünümü, 3D↔harita geçişi, en yakın bakış, Anderva ölçeğinin yeri (Q-011 "zoom akışı" maddesini ayrıntılandırır) | **open** | — (engellemiyor; değerler veri) |

### Q-001 · Eski 8 POC referans görselinin statüsü  (status: answered → D-001)
- Kullanıcı eski POC'yi referans görselleriyle birlikte sildi; kullanılmaz.

### Q-002 · İlk geliştirilecek (dikey dilim) ilçe  (status: answered → D-002)
- Oyuncu başlangıç ilçesini kendisi seçer; Orven zorunlu değil. Stüdyo, M2 için teknik test alanı seçebilir (Orven/D2) ama bu oyun tasarımı varsayımına dönüşmez.

### Q-003 · Anderva'nın para birimi  (status: open — engellemiyor; kullanıcı 2026-10-20'de bilinçli olarak AÇIK bıraktı)
- Kullanıcı: "Anderva'nın para birimi henüz kararlaştırılmadı. Bu konu OPEN kalacak. Gerekli sistemlerde yapılandırılabilir parametreler kullan; para birimi adı veya sembolü hakkında kanon oluşturma."
- Studio kuralı: para birimi adı/simgesi yalnız yapılandırmadan okunur (`economy.currency_name`, `economy.currency_symbol`); geçici gösterim nötr `¤` simgesidir; hiçbir belge, test veya UI metni ₺ ya da başka bir adı kanon gibi kullanmaz. Simülasyon tutarları birimsiz tamsayıdır.
- Arayüz dili: bu soruda cevaplanmadı; çalışma varsayımı Türkçe varsayılan arayüz, tüm metinler merkezi (ÇM). Şimdilik yeniden sorulmuyor.

### Q-004 · Hedef platform önceliği  (status: answered → D-003, cihaz bilgisi D-004)
- Masaüstü (Windows + macOS) birincil, iPadOS ikincil ama ilk günden mimaride. Uygulama: ADR-0004.

### Q-005…Q-013 · T-015/T-018/T-025 spec turundan gelen açık sorular (status: open — hiçbiri hiçbir görevi engellemez)
Kaynak: design-director canon kapısı (2026-10-20) ve art-director T-025 raporu. Ayrıntı ve gerekçe: `design/specs/characters-npc.md` §14 (AS-1..10), `design/specs/political-events.md` §12 (AS-11..13), `design/specs/ux/ux-ia-v0.md` §8–9, `design/specs/art/building-kit-v0.md` (S1–S4). Hiçbiri kanonlaştırılmadı.
Beklerken stüdyo ne yapar: protagonist `actor.protagonist` + boş `profile_slots`; partiler `party.a/b`, N veridir, M2'de parti yok; `T_elec`/`start_mode`/`election.rule`/`council.size` parametre; `lose_consequence` kancası; yalnız sistem tetikli olaylar, boş kadro şeması; `tone_profile` ılımlı yer tutucu, `corruption` etiketli şablonlar kapalı; HUD A iskeleti nötr tema, yalnız prototip, MOCK rozetli; takvim `{year}. yıl, {day}. gün`, başlık 'Imaro: The Mayor'; kit v0 varsayımları (dini yapı yok, çatı kiremit payı ≤%55 yakın/≤%35 metro, 12+ kat yalnız D1'de az, saat kulesi 23 m).
Tek sert kural: **ad/sayı/senaryo kanon gibi yazılmaz**; cevaplar `design/decisions/` altına kullanıcının sözleriyle kaydedilir.

### Q-014 · İmar önerisi meclisten geçmeli mi? (status: open — engellemiyor)
Kaynak: T-027 sim raporu (SIM-05, CAN-05/06). Şu an çalışma modeli: önerilen imar değişikliği `apply_delay_days=3` sonra otomatik yürürlüğe girer (veri). Gerçek yetki/meclis usulü F05-D'de AÇIK. Beklerken: yapılandırılabilir `requires_council` bayrağı (veri), UI akışı iki yolu da gösterebilir.

### Q-015 · Ismeral coğrafyasının yaratıcı onayı (status: open — kullanıcı kararı bekliyor)
Teknik/görsel kapılar geçti (art-director GEÇER, QA PASS, canon kontrolü temiz) ama kıyı çizgisi, ada sayısı/konumu, D1–D6 yerleşimi ve "D1 kuzey kıyıda" çıkarımı **ÇM/OY** verisidir; kullanıcı onayı verilmedi. T-001 görüntüleri sohbette paylaşıldı (`artifacts/screenshots/captures/*t001-final*`; `world_preview` ile açılır).
Onay gelene kadar kural: **hiçbir görev kalıcı şehir/mahalle/liman/yol/yerleşim koordinatını mevcut araziye sabitlemez**; yerleşim ve ağ yalnız `WorldData` + çapalardan çalışma zamanında türetilir, koordinat içeren üretilmiş veri commit'lenmez; testler topolojik/göreli kalır; kontrol verisi (`data/world/ismeral/*.json`) düzenlenebilir kalır.

### Q-013 ek · Çatı payı kuralı çelişkisi (T-005 raporu, art-director kararı gerekir)
Kit §3.2: küçük merkez/köy/yamaç/tarlada kiremit payı %55–70; aynı spec'te "her 500 m pencerede ≤%55" kuralı var. T-005 yorumu: 500 m kuralı yalnız yoğun/orta yoğun pencereler için geçerli. Onay art-director'da (sanat kuralı), kullanıcı kararı değil. Beklerken: yorum uygulandı.

### Q-018 · Varlık kütüphanesi şablon kararları (T-052; status: open — kontak sayfalarıyla birlikte sorulacak)
Kaynak: art-director, `design/library/README.md` + `design/library/templates-v0.md` (her kategorinin sonunda tam soru listesi). Kullanıcı 2026-10-25: insan, araç, yol çizimi şablonları önceden çizilip onaya sunulacak; dünyada onaysız hiçbir şey yaratılmayacak. Aşağıdakiler kanondan çözülemeyen ve kontak sayfasıyla birlikte sorulacak kararlardır (hiçbiri uydurulmadı):
1. **Onay biçimi:** kimlik bazında mı, aile/kategori bazında toplu onay da olsun mu? Onaylanan bir şablonun görünümü sonradan değişirse yeniden onay gereksin mi (öneri: evet, içerik özetine bağlı)?
2. **İnsan:** stilizasyon seviyesi A piyon / B blok figür (öneri) / C faset; gövde tipi sayısı; kalabalıkta kültürel/dini okunabilecek giyim öğeleri (Q-010 ile bağlı); üniformalı kamu personeli; protagonist/adlı karakterler kütüphane dışı mı (Q-005)?
3. **Araç:** tamamen jenerik mi, dönem karakteri (eski sedan) istenir mi; taksi ayrı mı ve rengi; Ismeral kamu taşıtlarının renk kimliği; vapur gövde rengi; acil durum araçları; sokak yoğunluk hissi.
4. **Ulaşım T0 içeriği:** T0'da tramvay, banliyö treni, araba vapuru var mı? (Bugünkü T0 ağı: yol, yük/ray hattı, D1↔D6 yolcu feribotu; tramvay yok.)
5. **Yol kesitleri:** önerilen genişlikler; yeni sınıflar (`ped`, `boulevard`, `coast`, daraltılmış yamaç sokağı); oyuncu kesit mi sınıf mı seçer; kesit dönüşümü (refüj → tramvay) oynanış mı; bisiklet yolu rengi; park şeridi; promenad içeriği; işaretleme düzeyi.
6. **Bitki/zemin/donatı:** palmiye türü; fıstık çamı; çiçek vurgusu; meydan döşeme tonu; asfalt tonu; donatı metal rengi; kiosk/simit arabası; reklam/tabela; şantiye görünümü (Q-016 iskele sorusuyla birlikte); gece aydınlatması.
7. **Mevsim/hava:** oyunda mevsim var mı (giyim, yaprak)? Karar yoksa yaz görünümü sabit.
Beklerken stüdyo ne yapar: şablonlar katalogda `proposed`; kontak sayfaları üretilir; hiçbir `proposed` şablon oyuna girmez; her seçenek veri (palet satırı, kesit tablosu, sınıf genişliği) olarak tutulur, kullanıcı cevabı yalnız veriyi değiştirir. Cevaplar `design/decisions/` altına kullanıcının sözleriyle kaydedilir.

### Q-016 · Sim yapısı eşlemesi ve oynanabilir başlangıç koşulları (T-040; status: open — engellemiyor)
Kaynak: T-040 render payı (godot-engineer). Hiçbiri kanonlaştırılmadı; hepsi yapılandırılabilir ÇM verisidir.
- **Birim↔kat oranı:** `data/view/sim_building_mapping.json` `units_per_floor = 1` (T0 stok adaptörüyle aynı sözleşme: stokta birim = kat). Ekonomi biriminin (hane/dükkân) kit katına gerçek karşılığı F05-D'de AÇIK.
- **İnşaat kademesi:** kitte iskele/inşaat modülü yok; yapı, nihai modülün ailesindeki daha az katlı modüllerle kat kademesi olarak görünür (aile içinde küçük modül yoksa nihai modül başta görünür). Art-director: iskele/şantiye görseli ister mi (yeni modül = sanat kararı, uydurulmadı)?
- **Başlangıç koşulları:** varsayılan ekonomi yapılandırmasında bölge başına altyapı kapasitesi 1000 birim, gerçek T0 stoğu 4-55 bin birimdir → her yatırım `infrastructure_exhausted` ile reddedilir. `data/game/playable_economy.json` kapasiteyi (+%30) ve gizli hane talebini (+%25 konut stoğu) T0 stoğundan türetir (yalnız oynanabilir sahne; sim yapılandırması değişmedi). Doğru ölçek/başlangıç dengesi F05-D'de AÇIK.
- **Otonom büyüme:** varsayılan sim yapılandırmasında `review_enabled = 1`: yatırımcılar oyuncu komutu olmadan da boş parselleri değerlendirir (yapı yine yalnız sim kararından doğar; CAN-03 ihlali değil ama "oyuncu komutu vermeden yapı oluşmaz" yalnız `review_enabled = 0` iken doğrudur). Oynanabilirde otonom büyüme açık mı kalsın? (`--m2-isolate` yalnız dev/yakalama.)
- **GEÇİCİ TEMPO (2026-10-24, kare bütçesi gerekçesi; denge kararı kullanıcıya AÇIK):** sim varsayılanı `max_reviews_per_tick = 60` günde ~57 yatırımcı kararı (%98'i ret) üretir ve sim tick'ini ort ~17 ms (tepe 60+ ms) yapar; kare bütçesi (16,6 ms) aşılır. `data/game/playable_economy.json` `decision.max_reviews_per_tick = 8` (yalnız oynanabilir; sim varsayılanı/kural değişmedi): günde ~8 karar, tick ort 4,3 ms (gün 10-45; 15 ile 6,9 ms, 60 ile 15+ ms); 180 günde onay 105 -> 69, ret 9181 -> 1297. Oyuncu imar önerisi sonrası gelişme zamanı DEĞİŞMEDİ (8 parsel: gün 40 inşaat, gün 100'de 7/8 yapıldı). Gerçek denge (günde kaç karar, otonom büyüme hızı) F05-D'de AÇIK; sim hızı/tick maliyeti düşerse değer yükseltilebilir.
- **Demo imarı:** salt ticaret önerisi (`zone.commercial`) T0 dükkân arzı hane ihtiyacının çok üstünde olduğundan talep nedeniyle reddedilir; demo `zone.mixed` kullanır.
Beklerken stüdyo ne yapar: tüm sayılar veri dosyalarında; test ve yakalamalar bu değerlere değil davranışa (olumlu/olumsuz yol, kademe, hücre-yerel) bağlıdır.

### Q-017 · Yıkım / yeniden yapılaşma / dönüşüm kuralı ve "yeşil alan/park" kimin işi? (T-047; status: open — engellemiyor; karar BEKLİYOR, uygulanmaz)
Kaynak: T-047 (ui-engineer), kullanıcının gerçek oyun denemesi (2026-10-25: yapılı parsele "Yeşil alan" imarı verildi, 11 oyun yılı sonra bina yerinde; arayüz "yürürlükte" demişti). Kanon "dönüşüm"e atıf yapar (kanon belgeleri 01, 02, 03: "dönüşüm ve yeni lojistik gelişimi", "Oyuncunun dönüştürebildikleri: … sanayi kapasitesi ve dönüşümü … Tarihî yapıların değişimi varsa politik/hukuki/ekonomik bağlamda anlamlı olmalıdır", "yoğunluk ve dönüşüm") ama kural tanımlamaz. Şu anki sim gerçeği (kodda doğrulandı, değiştirilmedi): imar komutu yalnız parselin imar etiketini (bekleyen imar) değiştirir; yatırımcı yalnız BOŞ parselleri değerlendirir; yıkım/yeniden yapılaşma yoktur; `zone.green` izinli özel kullanım içermez (`uses: []`).
Sorular (gruplu):
1. **Mevcut yapı imarla uyumsuz hale gelirse ne olur?** (a) Hiçbir şey: yapı "mevcut kullanım hakkı" ile kalır, yalnız yeniden gelişmede yeni imar geçerli (bugünkü davranış). (b) Yatırımcı kararı: sahip, getiri/talep yeterliyse yıkıp yeniden yapar (yeni sim kararı, gerekçeli). (c) Belediye kamulaştırma + yıkım: bütçe/siyasi maliyet, grup tepkisi (CAN-05). (d) Zorunlu yıkım emri (hukuki süreç, süre, itiraz).
2. **"Yeşil alan/park" kimin eylemi?** (a) Yalnız imar etiketi (bugün; özel yatırım olmaz ama alan kendiliğinden park olmaz). (b) Belediye inşası: CAN-04 kamusal yapı/mekân; bütçe harcamasıyla park yapılır (İnşa modunun ilk gerçek aracı). (c) İkisi: etiket + belediye isteğe bağlı park inşa eder.
3. **Dönüşümde bedel/gecikme/tepki:** yıkım bedeli kimin, süre, hangi grup nasıl tepki verir (SIM-12 gereği gerekçeli; tarihî yapı, işçi mahallesi)?
ÖNERİLEN VARSAYILAN (yalnız öneri, kanon değil): 1(a) şimdilik + arayüzde dürüst uyarı (T-047 uyguladı); ileride 1(b) "yatırımcı kararı" (yeni gerekçeli karar anahtarı), belediye kamulaştırması ayrı ve pahalı seçenek 1(c); 2(b): park/yeşil alan belediye inşası olarak CAN-04 altında (etiket tek başına park yaratmaz).
Beklerken stüdyo ne yapar: hiçbir yıkım/yeniden yapılaşma mekaniği kurulmaz; imar akışı yapılı parselde "mevcut yapıyı KALDIRMAZ" der; kullanıcı yanıtlayınca `design/decisions/` altına kendi sözleriyle kaydedilir.

### Q-019 · Görünüm modları: kamera tavanı, strateji haritası, geçiş, en yakın bakış, ülke ölçeği (status: open — engellemiyor)
- Context: Creative Director (sohbette, 2026-10-28, Studio Director aktardı): "bu kadar zoom out yapamamalısın; o başka bir mod olabilir". Bugün açılış görüntüsü 58 km'den 40 km'lik Ismeral kutusunu boşlukta bir ada gibi gösteriyor (hesap: dünya ekran genişliğinin ~%53'ü, dört kenar kadrajda); bu, F01/WLD-10'daki kesintisiz ana karayı görsel olarak yalanlıyor. Ayrıntı ve hesaplar: `design/specs/ux/VIEW-MODES-AND-DESIGN-SYSTEM.md` §A, §D. Etkilenen: T-041 (ölçüt 3 zoom bantları), T-043 (açılış kamerası), önerilen T-063/T-064/T-068/T-069. Q-011'in "zoom akışı (sürekli/ölçek kapısı)" maddesini ayrıntılandırır.
- Options:
  1. Serbest 3D tavanı: A) metropol çekirdeği ~18 km, dünya kenarı asla kadrajda değil, metropol bütünü yalnız haritada · B) ~31 km "metropol sığar" (kenar payı küçülür, ada etkisi kısmen geri gelir) · C) yalnız açılış görüntüsü değişir, tavan kalır.
  2. Strateji haritasının görünümü: A) aynı 3D dünyanın tepeden sadeleştirilmiş görünümü + sembol katmanı · B) aynı veriden 2D kartografik ("kâğıt") harita · C) metropolde A, ülke ölçeğinde Ref A yönünde kuşbakışı.
  3. 3D → harita geçişi: A) yalnız düğme/kısayol · B) tavanda uzaklaştırmayı sürdürünce otomatik geçiş · C) düğme + tavanda tek dokunuşluk ipucu, otomatik değil.
  4. En yakın bakış: A) ~50 m "balkon" bakışı, göz hizası yok · B) bugünkü göz hizası (~25 m) · C) A + ileride ayrı "yakından bak" modu.
  5. Anderva ülke ölçeği: A) yalnız strateji modunda, M2 sonrası, önce Ismeral'i aynı koordinatla içeren ülke verisi · B) serbest 3D'den de erişilir (1. soruyla çelişir).
- Recommendation: 1A (itirazı doğrudan karşılar, ada görüntüsünü yapı gereği engeller), 2A (aynı kıyı/yol geometrisini ve sanat gramerini garanti eder, WLD-01/VIS-01), 3C (istem dışı mod değişimi yok), 4A (sokak hayatı okunur kalır; en pahalı yakın kademeler M2'den çıkar; street perf tabanı zaten bütçe sınırında), 5A.
- Meanwhile: tüm sınırlar veri dosyasında ÇALIŞMA DEĞERİ (öneri değerleri: tavan 18 km, alt sınır 50 m / 12°, kenar payı 1,5 km); "kadraj dünya içinde" kuralı teknik karar olarak (ADR-0007) uygulanır; açılış ve Home başlangıç ilçesine (`start_district_id`, D-002); harita modu yapılırsa aynı WorldData'dan ve nötr görünümle; hiçbir değer kanon gibi yazılmaz. Yanıt yalnız veri değerlerini ve harita görünümünü değiştirir; kullanıcının sözleri `design/decisions/` altına kaydedilir.

### Q-020 · Yoldan sonra ilk bina ne kadar sürede çıksın? (status: answered → D-010: A + hızlı zaman; uygulama T-043B)
- Context: D-008 ilk 5 dakika. Ölçüm: 1 sim tick = 1 gün; hızlar normal 1 / hızlı 4 / en hızlı (demo) 16 gün/sn. Yol sonrası bina ~330 gün = normal hızda 5,5 dk, hızlıda 82 sn, demoda 21 sn. Ayrıntı: `design/specs/core-loop-v0.md` §2.
- Options: A) Yol sonrası yakındaki boş parseller öncelikli değerlendirilsin; hedef ilk inşaat ≤40 gün, ilk bina ≤100 gün (oyun hızı "hızlı" ile ~25 sn). B) Yalnız tarama sıklığı artsın (kare maliyeti artar, yine rastgele bekleme). C) Yalnız zaman hızı artsın (gecikme gizlenir, SIM-08 etkisi zayıflar).
- Recommendation: A + oynanabilirde başlangıç hızı "hızlı"; yatırım yine gelmeyebilir (SIM-07), yalnız beklemenin kendisi çıkarılır.
- Meanwhile: sayılar veri; hiçbir şey uygulanmaz.

### Q-021 · Boş arazinin ilk imarını kim verir? (status: answered → D-010: oyuncu imar planı teklifi sunar, çevreden türetme YOK; uygulama T-043A; ayrıntı Q-023/Q-024)
- Context: yatırımcı imarsız parselde `zoning` ile reddeder; "yol çiz, bina çıksın" akışında imar adımı yok. T0 boş parsel imarının sim'e aktarımı bugün doğrulanmadı (`core-loop-v0.md` §3).
- Options: A) T0 başlangıç durumu: boş parselin imarı çevredeki mevcut yapıların çoğunluk kullanımından türetilir (oyuncu adımı yok). B) Oyuncu önce imar verir (akış iki adım: imar + yol; CAN-05 ile tam uyumlu). C) Yol çizilen her yer otomatik karma.
- Recommendation: A (D-008 akışına uyar; imar değişikliği oyuncu aracı olarak kalır).
- Meanwhile: türetme kuralı veri olarak önerilir, uygulanmaz.

### Q-022 · Bütçe ve kamulaştırmanın ilk sürümü (status: answered → D-010: önce gösterge bütçe, kamulaştırma sonra; kısıt/bedel/yıkım hâlâ AÇIK; uygulama T-043C, T-042b)
- Context: yol maliyeti "henüz kurulmadı"; D-009 kamulaştırma hedefi; Q-017 (yıkım kuralı) AÇIK; Q-003 para birimi AÇIK.
- Options: A) Önce gösterge bütçe (vergi geliri + yol maliyeti görünür, kasa kısıt değil), kamulaştırma sonraki adım (T-042b). B) Bütçe kısıt olsun (kasa yetmezse yol reddedilir), kamulaştırma sonra. C) Bütçe + kamulaştırma birlikte.
- Recommendation: A (ilk 5 dakikayı bozmadan sayıyı görünür kılar; kısıt eklemek ayrı denge kararıdır).
- Meanwhile: yol maliyeti "henüz kurulmadı" gösterilmeye devam eder; yıkım uygulanmaz.

### Q-023 · "Zoomlarda belirleyebilmeliyim" ne demek? (status: answered → D-010 düzeltmesi: "zoom" değil "zone'lar" demişti; imar bölgesi seçerek belirler)
- Context: D-010 soru 2, kullanıcının sözü: "…parselleri ne olacağına da karar verebilmeyim yani böyle Zoomlar belirleyebilmeliyim…". Anlamı belirsiz; ajanlar yorumlamadı. İmar planı teklifinin ÇİZİM/SEÇİM biçimini etkiler (`core-loop-v0.md` §2, T-043A).
- Options: A) Ölçeğe göre ayrıntı: uzaktan bölge/blok seçip tek planla (ör. "bu bölge konut"), yakından tek parsele karar; plan her ölçekte aynı dünya verisinden. B) Yalnız parsel seçimi; zoom sadece neyi gördüğünü değiştirir (bilgi katmanı), seçim biçimi değişmez. C) Zoom düzeyine göre plan ayrıntısı artsın (uzakta yalnız genel yön, yakında yoğunluk/kat/kullanım karışımı).
- Recommendation: A (kanondaki tek dünya/ölçek sözleşmesine uyar, WLD-01; toplu teklif zaten komut başına parsel listesi).
- Meanwhile: T-043A mevcut parsel seçimi ile çalışır, toplu seçim üst sınırı veri; hiçbir zoom bağlı seçim kurulmaz.

### Q-024 · İmar planı teklifi ne içersin ve "ne kadar iyi şey olacak" nasıl görünsün? (status: answered → D-010: kullanım + yoğunluk, yalnız hesaplanabilir sayılar)
- Context: D-010: oyuncu plan sunar, "ne kadar iyi şey olacak vesaire". Plan içeriği ve önizleme derinliği T-043A UI'sını ve sim sorgusunu belirler (CAN-05, SIM-12).
- Options: A) Plan = kullanım + yoğunluk; önizleme yalnız hesaplanabilir sayılar (potansiyel birim, kapasite yükü, hangi kesim kazanır/kaybeder), "iyi olacak" iddiası yok. B) Yalnız kullanım etiketi, önizleme yok. C) Parsel başına karışım (konut/dükkân oranı, kat sınırı) ve ayrıntılı tahmin.
- Recommendation: A (mevcut `zoning.propose` alanlarıyla uyumlu, sahte sayı yok; C sonra).
- Meanwhile: v0 = A; sim'de karşılığı olmayan önizleme alanı "henüz kurulmadı".

