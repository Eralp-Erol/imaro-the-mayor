# Kullanıcı kararı bekleyen sorular

Yalnızca kanondan çözülemeyen, gerçekten yaratıcı/ürün kararları. Gruplanmış tutulur; her biri için stüdyonun beklerken ne yaptığı yazılıdır. Cevaplar `design/decisions/` altına kullanıcının sözleriyle kaydedilir.

## Geri al penceresi · YANITLANDI (2026-11-03, D-017; aşağıdaki kart tarihî bağlam)
Sözün (D-014 §1): "ta ki başka bir yol parçası yapılana kadar geri al seçeneği bulunsun." Bugün kamulaştırmalı yolda geri al, yolun halk tepkisi ilk haftalık taramaya girince (1-7 gün) kapanıyor. Nedenini ölçtüm (`production/log/2026-11-01-b009-b013.md`): tarama yalnız tepki satırı yazmıyor; halkın duygu defterine (başka etkenlerle karışık), gündem öğesine, haber adayına ve gerekçe kayıtlarına da iz bırakıyor. Satırı silmek bunları geri sarmıyor; "hiç yapılmamış gibi" geri alma yarım kalırdı. Yarım geri alma uydurmadım.

**Kart G1 · Geri al, halk tepki verdikten sonra da açık kalsın mı? (Q-030)**
- A) Önerilen: Evet, sözün gibi başka yol yapılana kadar açık kalsın. Geri alınca yol, binalar, açılmış gündem öğesi ve haber kalkar; ama halkın o haftalarda biriken öfkesi silinmez, birkaç haftada kendiliğinden söner ("hiç olmamış gibi" tam değil, dürüstçe böyle yazılır).
- B) Şimdiki: halk tepki verince geri al kapanır, yalnız yıkma kalır. Tam tutarlı ama sözünle çelişir; kart metni "başka yol yapana kadar" demekten vazgeçer ("halk tepki verene kadar" der).
- C) Tam "hiç olmamış gibi": halk, geri al açıkken tepki vermesin; yolu "kesinleştirince" (başka yol ya da yıkım) tepki başlasın. Tam temiz geri alma, ama oyuncu başka yol yapmazsa tepki hiç gelmez; bir süre sınırı (kaç gün?) ayrıca karar ister ve tepki zamanı değişir.
- Karar: kullanıcı “cevabim: bugunku gibi.” dedi; **B**, mevcut davranış korunur (`design/decisions/D-017-geri-al-penceresi-bugunku-kural-2026-11-03.md`).
- Ek (2026-11-03 kod incelemesi): önceki yanlış vaat zaten düzeltilmiş; `expropriation.undo_note` kısa süreyi ve halkın tepkisi işlenince kapanmayı söylüyor. Koruma `tests/ui/expropriation_ui_test.gd:134-138` içinde. Yeni sim kuralı uygulanmadı.

---

## Yol yıkımı · YANITLANDI (2026-11-03, D-018; aşağıdaki kart tarihî bağlam)
Sözün (D-014 §1): "yolu yıkma seçeneği hep olsun." Artık evleri yıkarak geçen yol da yıkılabiliyor. Yol kalkınca çevredeki evler ve arsalar olduğu gibi kalır. Yol yapılırken yıktığı evler geri gelmez; onların yerinde boş bir şerit kalır. Sorulan tek şey: o boş şerit ne olsun? Ben seçmedim.

**Kart Y1 · Yıkılan yolun yerinde kalan boş şerit ne olsun? (Q-031)**
- A) Önerilen: Boş belediye arazisi olarak kalsın. Kimse oraya bina yapmaz. Bugün de böyle; ek iş yok.
- B) Çim ve ağaç olsun. Yalnız görünüş değişir; gerçek park değildir (park kurmak senin kararın). Küçük görsel iş.
- C) Yeniden arsa olsun, yatırımcılar oraya yine bina yapabilsin. Büyük iş: ekonomi ve oyun kaydı değişir.
- Beklerken: A. Seçimin yıkma kuralını değiştirmez; B küçük bir görsel iş, C ayrı bir görev açar.
- Yanıt (D-018): “Boş belediye arazisi olarak kalsın; belediye tekrar imar planiyla orayi arsa veya baska sekilde degerlendirebilir kararla.” Bugünkü boş arazi korunur; sonraki açık imar kararıyla değerlendirme hedefi T-066'dadır, çalışan akış henüz yoktur.

---

## T-065 Aşama 1 · yeniden iskân çalışma sayıları — sahibe 3 kart (2026-11-01; hiçbiri engellemiyor, sayılar veride)
Bunlar karar DEĞİLDİR. Hepsi `data/sim/public_works/road_works.json` `expropriation.resettlement` içinde ayarlanabilir (F05-C); yanıt gelince kullanıcının sözleriyle `design/decisions/D-NNN` yazılır. Politika varsayılan KAPALI; oyuncu açana dek bugünkü oyun aynen sürer.

**Kart R1 · Evi bulunan ailenin tepkisi ne kadar kalsın? (D-016 §2 "duruma göre biraz kalsın"; spec §6)**
Şimdi: tam uygun ev bulunan ailenin tepkisi %20 kalır ve YUKARI yuvarlanır (16 aileden 4 kalır, sıfıra inmez); kira ya da yerden yalnız biri uygunsuz "kısmi ev"de %60 kalır; ev bulunamayan %100.
- A) Önerilen: şimdiki ayar (%20 / %60 / %100).
- B) Daha yumuşak (örn. %10 / %40): taşınan aile neredeyse susar; yeni değerler ölçülmedi.
- C) Daha sert (örn. %40 / %80): taşınma tepkiyi az azaltır; yeni değerler ölçülmedi.
- Bekleyen: `residual_reaction_pm` 200, `partial_relief_pm` 600; yukarı yuvarlama (en az 1 hane kalsın) kod kuralı, veride değil.
- Ek (design-director, 2026-11-01, kod okumasıyla hesap, koşulmadı): "%20 kalır" HANE sayısı içindir. Gündem öğesinin gücü (baskı) için ayrıca "evi yıkılan varsa taban 600/1000" kuralı (D-014 §3, `local.floor_pressure_pm`) var ve en az 1 hane kaldığı için hep işler. Örnek: 34 hanenin hepsine tam ev bulunsa bile (yakında oturan yokken) baskı 940'tan yalnız 670'e iner (~%30 azalma). Yani bugün "biraz kalsın" (D-016 §2) pratikte "çoğu kalsın". Bu kartın sorusu değil, sözünle uyum düzeltmesi: taban ev bulunamayan hane payıyla ölçeklenmeli (stüdyo işi). Ayrıca "duruma göre" bugün yalnız evin uygunluğuna (tam/kısmi) göre; ailenin varlığına/gelirine göre değil (D-015; T-065 Aşama 2).

**Kart R2 · "Yakın ve uygun kira" ne demek? (spec §4; D-015)**
Şimdi: hedef bölgenin kirası kaynaktan en çok %25 pahalı ve hedefin yola en yakın yapılı konutu 800 m içinde ise ev "tam"; ikisi de aşılıyorsa ev sayılmaz. "Yer" ölçüsü yıkılan parselin merkezine değil YOLUN ÇİZGİSİNE göre (ucuz ve belirleyici); bir yol hedefin boş evlerinin en çok %30'unu alır.
- A) Önerilen: şimdiki ayar (%25, 800 m, %30; yol çizgisine uzaklık).
- B) Yıkılan parselin merkezine göre uzaklık: oyuncuya daha sezgisel gelebilir, ama parsel başına hesap gerekir (maliyet ölçülmedi).
- C) Gevşek ya da sıkı eşikler (örn. %50 / 2 km / %50): sayılar ölçülmedi.
- Bekleyen: `rent_tolerance_pm` 250, `max_distance_m` 800, `max_fill_pm` 300.

**Kart R3 · Taşınma bedeli ve yardımı (Q-003 para birimi, T-014 bütçe)**
Şimdi: bedel = taşınan hane x hedef bölgenin aylık konut kirası x 12 ay (gösterge; kasa kısıt değil, hiçbir komutu engellemez); taşınma yardımı 0 (sayı verilmedi). Bedel yol kaleminden AYRI "Yeniden iskân" satırında görünür, geri almada iade edilir.
- A) Önerilen: şimdiki ayar (12 ay, yardım 0); para birimi ve gerçek bütçe kararı gelene dek.
- B) Yardım ekle (hane başına sabit sayı): sayıyı siz söylersiniz; para birimi Q-003 açık.
- C) Bedeli hiç yazma, yalnız hane sayısını göster: bütçe satırı kalkar.
- Bekleyen: `support_months` 12, `move_grant` 0.

Not (karar gerektirmeyen): politika paneli konumu UI işidir (`ui-engineer`); sim yalnız `policies()` ve `policy.set` verir. (Güncelleme: konum alt çubuğa yeni bir sekme eklediği için sahibe Kart P1 olarak soruluyor, aşağıda.)

---

## Tasarım sadakati incelemesi · gece teslimi — sahibe 3 yeni kart (design-director, 2026-11-01; hiçbiri engellemiyor, mevcut davranışla ilerler)
Kaynak: D-014 §1/§3, D-015, D-016; kod ve QA turu 3 okuması (`production/log/2026-11-01-qa-oynanis-turu-3.md` §5). Bunlar karar DEĞİLDİR.

**Kart E1 · Ev bulunamayan aileler: tepki ne kadar sürsün, ev sonradan bulunabilsin mi? (Q-032)**
Sözün (D-014 §3): "onlara yeni ev sunulmadığı sürece tepki olsun." Bugün ev, yalnız yolun yapıldığı an aranır; o an yoksa aile sıraya girmez ve tepkisi yaklaşık 1 yılda (360 gün) kendiliğinden söner, ev hiç sunulmasa da. Ayrıca gerçek Ismeral'de bugün hiçbir ilçede boş ev yok (her ilçede konut açığı; QA turu 3 ölçümü): Yeniden iskân açık olsa da şu an hiçbir aileye ev bulamıyor, oyuncu politikanın faydasını göremiyor.
- A) Önerilen: Sıraya girsinler. Politika açıkken bu aileler bekleme listesine girer; yatırımcıların bitirdiği yeni evler önce onlara verilir (belediye bina yapmaz). Ev verilene dek tepki sürer, verilince "biraz kalır". Sözüne en yakın; orta büyüklükte iş.
- B) Şimdiki: ev o an yoksa aile kendi başına kalır, tepki ~1 yılda söner. Ek iş yok, ama bugünkü haritada politika işe yaramıyor.
- C) Ev yoksa kira yardımı: belediye kira yardımı öder, tepki "kısmi ev" kadar azalır. Bedel sayısı ve para birimi (Q-003) ayrıca sorulur.
- Beklerken: B.

**Kart K1 · Yolu yıkmanın bedeli ne kadar olsun? (Q-033)**
Sözün (D-014 §1): "yolu yıkma seçeneği de hep olsun (bu bir cost olacak)." Şimdi: metre başına 15 birim (yer tutucu). 134 m yol yapmak 1.300, yıkmak 1.995: yıkmak yapmaktan pahalı. Kasadan gerçekten düşer, hiçbir işlemi engellemez (gösterge bütçe, T-014).
- A) Önerilen: yapım bedeli kadar (134 m: 1.300). Anlaşılır: "yaptığın kadar ödersin".
- B) Şimdiki: metre başına 15 (yapımdan ~1,5 kat pahalı, caydırıcı).
- C) Yapımın yarısı: yıkmak ucuz, oyuncu daha rahat düzeltir.
- Beklerken: B (`data/sim/budget/budget_config.json` `demolish_cost_per_m`).

**Kart P1 · Politikalar düğmesi nerede dursun? (Q-034)**
Alt çubukta "Yönetim" sekmesi daha önce gizliydi; artık [İnşa | İmar | Yönetim] görünüyor ve Yönetim'in içinde yalnız "Politikalar" var. İlk 5 dakikaya (D-008) bir sekme eklendi.
- A) Önerilen: Böyle kalsın (Yönetim > Politikalar); bütçe ve meclis de ileride buraya gelir.
- B) Yönetim sekmesi ilk kamulaştırmalı yola kadar gizli kalsın; yol kartındaki "Politikalar'dan açabilirsiniz" notu oraya götürsün.
- C) Ayrı sekme olmasın; politika bütçe/meclis panellerinin içinde dursun.
- Beklerken: A.

Karar gerektirmeyen sapmalar (stüdyo düzeltir; kullanıcı sözü açık):
- D-014 §1 "yolu yıkma seçeneği hep olsun": arayüz yalnız EN SON yolu yıkabiliyor (`road_draw_panel.gd` `tool.last_road()`); daha eski bir oyuncu yolunu seçip yıkmanın yolu yok. Sim her ayakta yolu kabul ediyor (`public_work_demolish_handler.gd` `standing_road`), eksik yalnız seçim arayüzü. (T0'dan kalan şehir yollarının yıkılıp yıkılamayacağı sorulmadı; şimdilik yalnız oyuncu yolları.)
- R1 ekindeki baskı tabanı (D-016 §2 "biraz").
- G1 ekindeki onay kartı vaadi.
- Eski metinler hâlâ D-014 §3'ün "sunulursa hiç olmasın" sözünü anıyor (`data/politics/reactions.json` `_notes`, `reaction_rehousing.gd` başlığı); davranış D-016 §2'ye uygun, yalnız açıklama bayat.

## EN GÜNCEL: sahibe 4 kart — 2026-11-01 CEVAPLANDI → D-014 (aşağıdaki metin tarihî kayıt)
Bunlar karar DEĞİLDİR; yanıtlanınca kullanıcının sözleriyle `design/decisions/D-NNN` yazılır. Sayılar yalnız kayıtlardan; "ölçülmedi" yazan yerde ölçüm yok. Aşağıdaki eski "Kart 2 (Q-025)" ve "Kart 3 (Q-014)" bunlarla örtüşür: Kart B, Q-014'ün güncel hâlidir; Kart C, Q-025'in "yolun yıkımı" kısmını somutlar.

**Kart A · "Kararı gözden geçir" seçeneği yolu geri almıyor (Q-027)**
Gündem kartındaki bu seçenek adı yüzünden yolun geri alınacağını düşündürüyor; gerçekte yalnız yatırımcı riskini artırır ve destekleyen kesimlerin memnuniyetini düşürür, yol/parseller kalır. Şimdilik kartta "Yolu geri almaz..." açıklaması var.
- A) Önerilen: Adı gerçeğe uydur (örn. "Tepkiyi kabul et, yatırımcı riskini göze al"). Oyuncu ne yaptığını yanlış anlamadan seçer; en ucuzu.
- B) Gerçekten geri alsın (yolu söker). Oyuncu hatasını düzeltebilir ama "yıkımlı yol geri alınsın mı" sorusuyla (Kart 1 alt sorusu, Q-017) birlikte karar gerekir; halkın tepkisi geri gelmez.
- C) Seçeneği kaldır. Kart sadeleşir; oyuncunun tepkiye "geri adım" diyecek yolu kalmaz.
- Bekleyen: gündem kartı metni (`event.pe01.opt.reverse`), `agenda_model`/`agenda_panel`; şimdilik açıklama notu duruyor.
- Kaynak: `production/log/2026-10-31-gundem-yanit-ui.md` "reverse / Kararı gözden geçir uyumsuzluğu".

**Kart B · İlk büyük imar planı meclise gitsin mi? (Q-028, Q-014'ün güncel hâli)**
Şimdi 10 parsel ya da 40 birim ve üstü plan meclise gidiyor. Gerçek Ismeral D2'de 12 parsel = 51 birim; meclis 18 oylamanın 18'ini kabul etti (13'ü 3-2) ama uygulama 3. gün yerine 17. güne kayıyor (ilk inşaat 15 yerine 29, ilk bina 69-72 yerine 83). 9 parsel (36 birim) doğrudan işleniyor; reddedilen oyuncu planı 9 parsele bölüp meclisi atlayabiliyor.
- A) Önerilen: Eşikler olduğu gibi (10 parsel / 40 birim). Büyük plan siyasi bir an olur, birkaç gün bekler ve ince marjla geçer; hedef (ilk inşaat <=40, ilk bina <=100 gün) tutuyor (29 / 83).
- B) Eşiği yükselt (daha büyük planlar meclise). İlk plan beklemeden başlar, meclis daha nadir görünür; yeni eşik ölçülmedi.
- C) Meclis hiç olmasın. Her plan birkaç günde yürürlüğe girer; siyasi gerilim ve ret ihtimali yok olur (`requires_council` bayrağı zaten var).
- Bekleyen: `plan_council_min_parcels` 10, `plan_council_min_units` 40 (`data/game/playable_politics.json`); T-043B/D-011 Soru 4 ayarı.
- Kaynak: `2026-10-31-meclis-tepki-gercek-olcum.md` §0 madde 1, §2 tablo, §2.1, §3 (`small9`); `2026-10-31-plan-meclis-esigi.md`.

**Kart C · Yıkım yapan yolun halk tepkisi ne kadar güçlü olsun? (Q-029)**
Yıkımlı yol artık yerinden ettiği hane sayısına göre yol başına tek gündem öğesi açıyor (mahalle 200 hane varsayıldı; 20 pm = 4 hane'den itibaren tepki, 200 pm = 40 hane'de tavan). D2'de 150 yol denemesinden 127'si geçerli: yerinden edilen hane medyan 6, p90 38, en çok 72. Baskı: q50 = 170, q90 = 975, en büyük yol 1000 (tavan). Yani orta yol hafif, büyük yollar tavana sıkışıp birbirinden ayırt edilmiyor. Mahalle büyüklüğü bir tahmin (gerçek mahalle verisi yok).
- A) Önerilen: Şimdiki ayar kalsın (200 hane, eşik 20 pm, tavan 200 pm). Küçük yol hafif, büyük yol (yaklaşık 40+ hane) en sert tepkiyi alır.
- B) Daha yumuşak (tavan daha yüksek / mahalle daha büyük). Büyük yollar da kademeli ayırt edilir, ama tepki geç ve zayıf başlar; yeni değerler ölçülmedi.
- C) Daha sert (mahalle daha küçük / eşik düşük). Orta yol bile belirgin tepki alır, oyuncu ilk yıkımda cezalandırılmış hisseder; yeni değerler ölçülmedi.
- Bekleyen: `data/politics/reactions.json` `local.neighborhood_households` 200, `min_displacement_pm` 20, `full_displacement_pm` 200. Oynanabilir oyunda yıkımlı yol artık çizilebiliyor (`playable_roads.gd` köprüsü takılı, 2026-10-31); yine de Kart 1 (yıkım kapsamı) cevabı gelmeden ölçek ayarı erken.
- Kaynak: `2026-10-31-yerinden-edilme-mahalle-olcegi.md` (Önce/sonra tablosu, "Doğrulanmadı"); `2026-10-31-meclis-tepki-gercek-olcum.md` §0 madde 2-3, §4.

**Kart D · Şehirde kaç araç/yaya görünsün? (Q-026, güncel)**
Sayı gerçek faaliyetten türüyor (faaliyet yoksa araç/yaya yok). Şimdiki ayarda 100 m sokakta medyan araç: ana yol 1,2, toplayıcı/yerel 2,5; yaya 1,0 / 3,5 / 3,5 (p90 araç 4,3 / 5,7 / 5,6). Menzilde ~1000 araç, ~1400 yaya. Araçlar tek model, çoğu krem/bej; sanat kabulü yok. 2x için kare maliyeti ölçülmedi.
- A) Önerilen: Şimdiki seyrek his ("yaşam belirtisi", okunaklı); mevcut ayar ölçülmüş.
- B) 2x kalabalık. Şehir daha canlı görünür; kare maliyeti ve profil tavanı (araç 1600 / insan 1400) yeniden ölçülmeli.
- C) Çok seyrek, yalnız ana yollarda. En hafif; sokaklar boş görünür.
- Bekleyen: `data/view/life.json` yoğunluk/ağırlık; araç renk çeşitliliği ve tip Q-018 madde 3 ile.
- Kaynak: `2026-10-31-T-050-yasam-belirtisi.md` Kalibrasyon ve Doğrulanmamış bölümleri.

---

## Şimdi kullanıcıya sorulacaklar (2026-10-31; en fazla 3 karar; hiçbiri engellemiyor, stüdyo beklerken geri alınabilir varsayılanla ilerler)
Sahip modu: seçenekli kart, öneri ilk. Bunlar karar DEĞİLDİR; kullanıcı yanıtlayınca kararlar klasörüne (D-NNN) kendi sözleriyle yazılır.

**Kart 1 · Yol binanın içinden geçerse ne olsun? (Q-017 + T-042b ilk sürüm; sorular `production/tasks/T-042b-PLAN.md`)**
- A) Önerilen: yol geçtiği arsayı bütünüyle alır, bina yıkılır, sakinler yeniden ev arar, mahalle tepki verir; tarihî yapılar korunur; bedel yalnız gösterge (gerçek para yok). Yıkımlı yol onaydan sonra kalıcı (onaydan önce iptal edilir).
- B) Önce yalnız boş arsalardan geçsin; binalı arsa sonra.
- C) Bedel + süre + itirazla tam süreç (en uzun; bütçe kısıtı T-014 gerekir).
- Alt soru: yıkımlı yol geri alınabilsin mi? Önerilen: hayır. Alternatif: evet, binalar geri gelir ama halk tepkisi geri gelmez.
- Beklerken: kamulaştırma kurulmaz; ret metni "kamulaştırma henüz yok".

**Kart 2 · Halk neye tepki versin? (Q-025)**
- A) Önerilen: şimdilik sessiz kalsın, sahte tepki yok; "ne olunca tepki gelsin" kararını verince eklenir.
- B) Yeni binalara tepki: çevrede yeni inşaat olunca komşu kesimler sesini duyurur (küçük bölgelerde de çalışsın diye eşik düşer).
- C) Yol ve plan kararının kendisine tepki: yolun geçtiği mahalle ve plan komşuları onay/itiraz eder, kimin kazandığı görünür.
- D) Eski hale dön: altyapı dolunca tepki gelsin (yanlış nedenli; önerilmez).
- Beklerken: tepki yok; yalnız gerçek aşımda (yük > kapasite) altyapı şikâyeti çıkar.

**Kart 3 · İmar planı meclisten geçsin mi? (Q-014; D-010'da "ya da daha doğrusu meclisin" dedin, zorunlu mu belli değil)**
- A) Önerilen: şimdilik meclis yok, plan birkaç gün sonra yürürlüğe girer.
- B) Meclis olsun: plan oylanır, reddedilebilir; ilk 5 dakika bir adım uzar, daha siyasi.
- C) İkisi de: seçenek olarak (ör. büyük planlarda meclis).
- Beklerken: kod iki yolu da destekliyor (`requires_council` bayrağı); oynanabilirde "meclis yok".

Sonra (henüz sorulmaz): para birimi (Q-003); yol etkisi 100 mü 160 mı birim/km (ölçümle gelir, denge); bütçe kısıtı olsun mu (T-014).

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
| Q-025 | Halk neye tepki versin? (D-008 son adımı, bugün sessiz) | answered → D-011 (parametreler çalışma değeri) | — |
| Q-026 | Şehirde kaç araç/yaya görünsün? (T-050 yaşam belirtisi yoğunluğu, araç renk çeşitliliği) | answered → D-014 | — |
| Q-027 | Gündem Kararı gözden geçir seçeneği yolu geri almıyor (etiket / gerçek geri alma / kaldır) | answered → D-014 | — |
| Q-028 | İlk büyük imar planı meclise gitsin mi (10 parsel / 40 birim; Q-014'ün güncel hâli) | answered → D-014 | — |
| Q-029 | Yıkım yapan yolun halk tepkisi gücü (mahalle 200 hane, eşik 20 pm, tavan 200 pm) | answered → D-014 | — |
| Q-030 | Geri al penceresi: **B, bugünkü gibi** — halkın tepkisi işlenince geri al kapanır | **answered** | D-017 (2026-11-03) |
| Q-031 | Boş belediye arazisi; sonraki imar kararıyla yeniden değerlendirilebilir | **answered** | D-018 (2026-11-03); akış takibi T-066 |
| Q-032 | Ev bulunamayan aileler: bekleme listesi / ~1 yılda söner (bugünkü) / kira yardımı (Kart E1) | **open** | — (engellemiyor) |
| Q-033 | Yolu yıkmanın bedeli: yapım kadar / metre başı 15 (bugünkü) / yapımın yarısı (Kart K1) | **open** | — (engellemiyor) |
| Q-034 | Politikalar düğmesinin yeri: Yönetim sekmesi (bugünkü) / ilk kamulaştırmaya kadar gizli / bütçe-meclis içinde (Kart P1) | **open** | — (engellemiyor) |
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

### Q-014 · İmar önerisi meclisten geçmeli mi? (status: answered → D-011 + D-014 (Q-028); eşik/ağırlık parametreleri çalışma değeri, sahip onayı yok)
Kaynak: T-027 sim raporu (SIM-05, CAN-05/06). Şu an çalışma modeli: önerilen imar değişikliği `apply_delay_days=3` sonra otomatik yürürlüğe girer (veri). Gerçek yetki/meclis usulü F05-D'de AÇIK. Beklerken: yapılandırılabilir `requires_council` bayrağı (veri), UI akışı iki yolu da gösterebilir.

### Q-015 · Ismeral coğrafyasının yaratıcı onayı (status: open — kullanıcı kararı bekliyor)
Teknik/görsel kapılar geçti (art-director GEÇER, QA PASS, canon kontrolü temiz) ama kıyı çizgisi, ada sayısı/konumu, D1–D6 yerleşimi ve "D1 kuzey kıyıda" çıkarımı **ÇM/OY** verisidir; kullanıcı onayı verilmedi. T-001 görüntüleri sohbette paylaşıldı (`artifacts/screenshots/captures/*t001-final*`; `world_preview` ile açılır).
Onay gelene kadar kural: **hiçbir görev kalıcı şehir/mahalle/liman/yol/yerleşim koordinatını mevcut araziye sabitlemez**; yerleşim ve ağ yalnız `WorldData` + çapalardan çalışma zamanında türetilir, koordinat içeren üretilmiş veri commit'lenmez; testler topolojik/göreli kalır; kontrol verisi (`data/world/ismeral/*.json`) düzenlenebilir kalır.

### Q-013 ek · Çatı payı kuralı çelişkisi (T-005 raporu, art-director kararı gerekir)
Kit §3.2: küçük merkez/köy/yamaç/tarlada kiremit payı %55–70; aynı spec'te "her 500 m pencerede ≤%55" kuralı var. T-005 yorumu: 500 m kuralı yalnız yoğun/orta yoğun pencereler için geçerli. Onay art-director'da (sanat kuralı), kullanıcı kararı değil. Beklerken: yorum uygulandı.

### Q-018 · Varlık kütüphanesi şablon kararları (T-052; status: open — kontak sayfalarıyla birlikte sorulacak)
Kaynak: art-director, `design/library/README.md` + `design/library/templates-v0.md` (her kategorinin sonunda tam soru listesi). Kullanıcı 2026-10-25: insan, araç, yol çizimi şablonları önceden çizilip onaya sunulacak; dünyada onaysız hiçbir şey yaratılmayacak. Aşağıdakiler kanondan çözülemeyen ve kontak sayfasıyla birlikte sorulacak kararlardır (hiçbiri uydurulmadı):
1. **Onay biçimi:** kimlik bazında mı, aile/kategori bazında toplu onay da olsun mu? Onaylanan bir şablonun görünümü sonradan değişirse yeniden onay gereksin mi (öneri: evet, içerik özetine bağlı)?
2. **İnsan:** [stilizasyon seviyesi KARARA BAĞLANDI: B blok figür, D-013, 2026-10-31; kalanlar AÇIK] stilizasyon seviyesi A piyon / B blok figür (öneri) / C faset; gövde tipi sayısı; kalabalıkta kültürel/dini okunabilecek giyim öğeleri (Q-010 ile bağlı); üniformalı kamu personeli; protagonist/adlı karakterler kütüphane dışı mı (Q-005)?
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


### Q-025 · Halk neye tepki versin? (D-008 "halk tepki versin" adımı; status: answered → D-011 (kullanıcı kart cevabı); tepki parametreleri çalışma değeri)
- Context: ölçüm `production/log/2026-10-31-altyapi-siyaset-yan-etkisi.md`. Eski tepkinin gerçek nedeni "altyapı doluluğu %50'den itibaren şikâyet" idi (oyuncu hiçbir şey yapmasa da çıkıyordu; `cause_refs` yanlışlıkla plan parsellerini gösteriyordu: yanlış nedensellik). Oynanabilirde şikâyet artık yalnız yük > kapasite iken başlıyor; yol+plan sonrası 400 günde grup tepkisi ve gündem 0 (D2, tek tohum). İnşaat baskısı D2'de hiçbir kesime ulaşmıyor (kesim payı ~%7,5 < `min_share_pm` %10). Bkz. `design/specs/core-loop-v0.md` §9.
- Options: bkz. "Şimdi kullanıcıya sorulacaklar" Kart 2 (A sessiz / B yeni bina tepkisi / C yol-plan kararına tepki / D eski hale).
- Recommendation: A; kullanıcı B/C seçerse `construction_burden`, `min_share_pm` ya da olay kaynağı veri olarak ayarlanır; sahte tepki eklenmez (SIM-12).
- Meanwhile: tepki yok; HUD yalnız gerçek veriyi gösterir; bina sayısı, ret ve gerekçeler yol+plan etkisini okunur kılar.


### Q-026 · Şehirde ne kadar araç ve yaya görünsün? (T-050; status: answered → D-014)
- Context: araç/yaya sayısı gerçek sim verisinden türer (hane/işyeri/inşaat birimi x doluluk; aktivite yoksa sahte trafik yok). Ama "birim başına kaç araç/yaya" ve sınıf tavanları çalışma değeri (`data/view/life.json`). Ölçüm: `production/log/2026-10-31-T-050-yasam-belirtisi.md`.
- Options: A) Mevcut seyrek his (100 m'de medyan araç ana 1,2 / toplayıcı-yerel 2,5, yaya 1,0 / 3,5 / 3,5; "yaşam belirtisi", okunaklı). B) Daha kalabalık (2x). C) Çok seyrek, yalnız ana yollarda.
- Recommendation: A (kare süresi ve okunurluk dengeli); renk çeşitliliği/araç tipi (taksi, kamu aracı) Q-018 madde 3 ile birlikte.
- Meanwhile: A; kullanıcı değiştirirse yalnız `life.json` yoğunluk/ağırlık değeri değişir.


### Q-035 · "Oyun hep D2'den başlasın" (D-020) kanonla çakışıyor mu? (status: open — engellemiyor; design-director 2026-11-05)
- Context: D2 = Orven. Kanonda "Orven'i zorunlu başlangıç yapmak" bilerek reddedildi; D-002 "test alanı seçimi oyun tasarımı kararına dönüşmesin" diyor. D-020 kartı bu çakışmayı göstermedi ve "şimdilik" sözüyle "hep"i birlikte taşıyor. Sonraki sahip kararı kazanır, ama bilgilendirilmiş olması gerekir.
- Options: A) Şimdilik D2; ilçe seçimi hedef olarak kalır, T-043 bekler. B) Kalıcı: oyun hep Orven'den başlar (D-002 ve kanondaki ret bilerek geçersiz olur). C) İlçe seçimi M2 kapanmadan gelsin (T-043).
- Recommendation: A.
- Meanwhile: gönderilen oyun D2'de yol çizdirir; B-026 karar gereği kapalıdır, ama Q-035 B/C'ye dönerse yeniden açılır.

### Q-036 · Yıkım ve yerinden etme meclisin oyuncuya güvenini etkilesin mi? (status: open — engellemiyor; ölçüm B-030, 2026-11-05)
- Context: 144 koşuluk ölçümde yol yıkımı/kamulaştırma yüzünden evinden olan hane sayısı 42 ya da 302 olsa da meclis üyelerinin güven/kızgınlık değerleri HİÇ değişmiyor; yıkım oylamayı hafifçe kolaylaştırıyor (altyapı yükünü düşürdüğü için). Halk tepkisi var ama meclise ulaşmıyor. D-008 "halk tepki versin" ve siyasi kariyer çekirdeğiyle ilgili; kanonda (D-014) tepki dağılımı var, meclise bağlanması belirsiz.
- Options: A) Böyle kalsın: halk tepkisi görünür ama meclis yalnız teklifin kendi değerine bakar (önerilen, ölçülmüş çalışan davranış; sonra istenirse açılır). B) Yerinden edilen hane çoksa meclis güveni bir miktar düşsün (veri ağırlığı; meclis eşiği ve GOLDEN'a dokunur). C) Tepki yalnız kesim baskısı (bloc_pressure) olarak ağırlaşsın.
- Recommendation: A (karar ürün yönüne ait; sahte nedensellik eklenmez).
- Meanwhile: bağ yok; HUD yalnız gerçek veriyi gösterir.

