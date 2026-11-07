# M3 "Yaşayan metropol" — tasarım kapsamı (design-director, 2026-11-07)

Statü: ÇALIŞMA MODELİ (öneri). Kanon değildir, kanonu değiştirmez. Dayanak: D-029, `production/ROADMAP.md` M3 satırı.
Okunanlar: F01 (sütunlar, kampanya, dramatik örnekler), F02 (tümü), F03 (tümü), F04 §Görsel dil/§Kaçınılacaklar, F05 A–E, F06; D-006, D-008, D-010, D-015, D-019, D-021, D-029; `design/CANON.md`, `design/REQUIREMENTS.md`, `production/STATE.md`, `production/M2-CLOSURE.md`, Q-016/Q-018/Q-019; ADR-0002 §3; `data/sim/economy/economy_config.json`, `data/game/playable_economy.json`.
Doğrulanmadı: oyun çalıştırılmadı, test koşulmadı. Aşağıdaki "bugün" tespitleri yalnız veri/kod okumasından gelir.

## 0. Bugünkü durum: M3'ün asıl boşluğu
- Oynanabilir veride `unplanned_land_enabled = 1` (D-010): plansız boş arazide yatırımcı reddeder. Plan yalnız oyuncudan geliyor ve oyuncu yalnız D2'de yetkili (D-021). **Sonuç (okumaya dayalı çıkarım, ölçülmedi): D1, D3–D6'nın boş arazisi fiilen donuk.** Bu, WLD-11 ve F03 "Kent oyuncu bakmıyorken de evrilir" ile çelişir. M3'ün ilk işi bunu ölçüp kanıtlamak.
- Araç/insan yoğunluğu (T-050) bina faaliyetinden türüyor; **trafik sıkışması (yük/kapasite) diye bir sim verisi yok.** Bugünkü araçlar "trafik sorunu" diye gösterilemez.
- `interest_pm` (finansman) yatırımcı kararında sabit bir veri; makro değişken yok. Bütçe hâlâ gösterge (D-010).
- ADR-0002 §3 diğer ilçeleri "toplu modellenir ama tick'lenir" der; bugünkü sim tüm Ismeral'i parsel düzeyinde tutuyor gibi. Toplu ↔ parsel geçişi TEKNİK (technical-director), ama tasarım koşulu aşağıda (§4).

## 1. Bağlayıcı kanon gereksinimleri
| REQ | Etiket | M3 için anlamı | Kaynak |
|---|---|---|---|
| WLD-11 | OY | Diğer ilçeler oyuncu bakmıyorken donmaz; değiştirenler **diğer belediyeler, yatırımcılar, haneler, makro koşullar**. Soyutlama serbest, 3D sokakların hepsinin canlı çalışması zorunlu değil. | F03 "Kent oyuncu bakmıyorken…" |
| CAN-03 | K | Komşu ilçelerde de her özel bina yatırımcı kararıyla doğar. Ne oyuncu ne "komşu belediye" bina koyar; belediyeler yalnız plan/yol/kamu işi yapar. | F01, F03 "Kritik", F05-A |
| F03 yetki | K/OY | İlçe başkanı "diğer ilçeleri istediği gibi yönetemez". İlçeler arası yol/toplu ulaşım metropol yetkisidir (M5). | F03 "Politik gelişme ve yetki" |
| CAN-11, WLD-09 | K/OY | Bakmıyorken biriken değişim kalıcı tarihtir; ileride metropol yetkisi gelince "sıfırla" yok. | F01, F02, F03 |
| WLD-01, TEK-03 | K | Diğer ilçenin değişimi metropol bakışında ve sokakta **aynı veri**dir. Ayrı "büyüme animasyonu", sim'de olmayan bina yok. | F02 "Alt ölçek", F05-A |
| SIM-04 | ÇM | Altyapı gelişmeyi mümkün kılar/kısıtlar; **bakım ve kapasite maliyeti** doğurur. Formül AÇIK. | F03 |
| SIM-06 | ÇM | Makro: ülke ekonomisi, faiz/finansman, fiyat, taşımacılık, turizm, mevzuat; diğer altı metropol soyut. | F03 |
| SIM-07 | OY | Komşuda plan açılması da bina garantisi değil; yatırım gelmeyebilir. | F03 "Kritik" |
| SIM-09 | OY | İlçe karşılaştırması tek skor/not olmaz. | F03 |
| SIM-10 | K/OY | Aynı T0'dan farklı politika → yoğunluk, sektör, ulaşımda anlamlı fark; zorunlu late-game planı yok. | F01 sütun 4, F02 "Gelişmiş durum", F03 "Özgürlük" |
| SIM-11 | OY | Komşuların evrimi her kampanyada aynı zinciri izlemez (tohum + aktör profili). | F01 "Hissiyat…" |
| SIM-12 | OY | "D3'te ne oldu, neden?" ve "yolum neden tıkandı?" dünyada ve panelde okunur. | F01, F03 |
| WLD-03, WLD-05, WLD-06 | K/OY | Otonom büyüme adaya liman/ana sanayi koymaz (ada yalnız ileride **oyuncu kararı**); D1–D6 fiziken birleşmez, körfez doldurulmaz; hiçbir ilçe tek sektöre kaymaz. D4'ün tamamı kendiliğinden kentleşmez. | F02 atlas + "Liman/ada kuralı" |
| CAN-01, F05-D | K/A | Komşu başkan, parti, diğer metropol adı **uydurulmaz**. | F01 "Kesin adlar", F05-D |
| PLT-03/04 | K | Komşu evrimi iPad için kısılmaz; sonuçlar platformdan bağımsız. | D-003 |
| TEK-01/02 | TEK | Kameranın nereye baktığı sim sonucunu değiştirmez; kayıt→yükle→N tick eşit. | ADR-0002 |
| Sahip kuralları | D-029, D-010 | Görünüm/zevk (yağmur, ses, renk) sahibe önce/sonra karesiyle; HUD'da sahte sayı yok; bütçe gösterge (D-010) kararı değişecekse sahibe sorulur. | D-029, D-010, CLAUDE.md |

Not (precedence): ROADMAP'teki "hava (yağmur)" ve "ortam sesi" foundation'da yok; kaynakları stüdyo yol haritası + sahibin "M3'e başla" onayıdır (D-029). Bu yüzden **kapsamda** ama biçimi AÇIK (Q-018 §7 "mevsim/hava" hâlâ açık).

## 2. Dikey dilim önerisi: "Beş yıl sonra komşuna bak"
Oyuncu D2'de M2'deki gibi oynar (yol, imar, meclis, gündem). M3'te yeni olanlar:

**A. Komşu ilçe bakmıyorken değişir (WLD-11).** Komşu belediyeler oyuncuyla **aynı kurallarla** çalışan adsız aktörlerdir: kendi bölgelerinde imar planı açar/kapatır, kendi yollarını uzatır (kendi yetki alanında). Binaları yine yatırımcı yapar (CAN-03, SIM-07). Her belediyenin veri profili (ör. yoğunlaşma eğilimi, sanayi/konut ağırlığı, temkin) tohumla çeşitlenir; profil F05-C arketiplerine yaslanır ama tek sektör değildir.

Gözlemlenebilirlik (oyuncu bunu nasıl görür):
1. **Dönüş farkı:** Oyuncu 3–5 oyun yılı sonra kamerayı D3'e götürünce yeni yapılar, süren inşaatlar, boşalmış/kapanmış işyerleri 3D'de durur. Hepsi sim parsel durumudur.
2. **İlçe özeti (salt okunur):** herhangi bir ilçeye dokununca "Son 1 yılda/başlangıçtan beri" gerçek sayılar: konut/işyeri birimi, inşaat, kapanış, bekleyen talep + "Neden?" (ör. "Belediye ova kenarını üretime açtı", "Finansman pahalılaştı"). Tek not/puan yok.
3. **Bildirim şeridi:** komşu belediye ve makro haberleri `ambient` düzeyde, modal değil (F03 "kesintisiz akış").
4. **Bana dokunan etki (asıl kanıt):** komşu değişimi D2'de okunur bir sonuç doğurur, ör. D3'te yeni işyeri → D2'den işe gidiş → D2–D3 bağlantı yolunda yük artar → D2'de konut arayan sayısı veya kira baskısı değişir. "Neden?" zinciri komşuya kadar gider. Bağlantı yoksa etki yoktur (negatif durum).
5. Oyuncu D3'te araç kullanmaya çalışırsa düğme gizlenmez, kilitli ve gerekçeli görünür ("Bu ilçe yetki alanınız dışında"), gündemdeki `authority.locked` deseniyle aynı.

**B. Makro koşullar (SIM-06).** Az sayıda gerçek sim değişkeni: finansman maliyeti (bugünkü `interest_pm` değişken olur), ulusal talep, yapım maliyeti. Tohumlu yavaş değişim + nadir şok. Görünür olduğu yer: yatırımcı gerekçesi ("finansman"), ilçe özeti, şerit haberi. Diğer altı metropol yalnız "ulusal talep" kalemine toplu katkı olarak var; adı yok, seçilebilir görünmez.

**C. Trafik ve altyapı (SIM-04).** Yol parçası başına sim yükü/kapasitesi (TEKNİK model, TD seçer). Sıkışma 3D'de (araç yoğunluğu/yavaşlığı **bu veriden**) ve isteğe bağlı yol yükü katmanında görünür; parsel/yol denetçisinde "Neden?". Oyuncunun cevabı D2 içinde: paralel yol, imar karışımı (iş yakına), meclis/gündem. Bakım maliyeti: ağ uzunluğu/kapasitesinden gerçek gider satırı; aşırı yol = aşırı bakım (F03 "yanlış yoğunluk bütçeyi zorlar").

**D. Ayrışan şehirler (SIM-10/11).** Aynı T0'dan iki strateji (yoğun karma merkez / yayılmış düşük yoğunluk) 10 oyun yılında yoğunluk, sektör payı, yol yükü bakımından ölçülebilir ve metropol karesinde gözle ayrışır. Aynı strateji, farklı tohum → komşular farklı evrilir.

**E. Yağmur ve ortam sesi (başlangıç).** Yağmur metropol ve sokak bakışında aynı anda aynı yerde (WLD-01); low-key low-poly, hiperreal değil (VIS-01/05). Ses: kent uğultusu, deniz, yağmur; kaynak dünyadaki gerçek durum (inşaat sesi yalnız gerçek şantiyede). Müzik yok. İkisi de kapatılabilir.

Dilim dışında (bilinçli): seçim/parti (M4), ilçeler arası proje ve metropol yetkisi (M5), toplu taşıma inşası, mevsimler, ülke haritası modu (Q-019).

## 3. AÇIK kararlar ve geri alınabilir varsayılanlar
| # | Açık konu | Kaynak | Varsayılan (veri, geri alınır) |
|---|---|---|---|
| A1 | Komşu belediyelerin kimliği (başkan, parti, ad) | F01, F05-D, CAN-01 | Adsız: "D3 Belediyesi" gibi çalışma kodu; parti yok; profil veride. |
| A2 | Komşuların oyuncu gibi plan açması mı, yalnız toplu büyüme mi | WLD-11 (OY, yöntem serbest), D-010 | Oyuncuyla aynı plan/imar kuralı (simetri); meclis süreci komşuda soyut (kendi kendine kabul oranı veri). **Q-043** |
| A3 | Komşuyla etkileşim (iş birliği, çatışma, ortak proje) | F03 mod 3, F05-D (yetki açık) | M3'te yok; yalnız etki + haber. |
| A4 | Makro değişkenler, büyüklükleri, şok sıklığı; mevzuat değişimi | F03 "ekonomik matematik", F05-D | 3 değişken (finansman, ulusal talep, yapım maliyeti), küçük genlik; mevzuat değişimi YOK (yetki modeli açık). |
| A5 | Bütçe kısıt olsun mu, bakım nasıl ödenir | D-010 (gösterge), F05-D (bütçe formülü) | Bakım gerçek gider satırı, kasa eksiye düşebilir, inşa engellenmez. **Q-044** |
| A6 | Komşular aynı hızda mı evrilir | F03 tempo (ÇM) | Aynı gün tick'i; komşu karar sıklığı veri. |
| A7 | Q-016 "oynanabilirde otonom büyüme açık mı" | Q-016 | Komşularda açık (WLD-11 gereği); D2'de bugünkü davranış korunur. |
| A8 | Hava: var mı, sim etkisi, mevsim | Q-018 §7 | Yağmur yalnız görünüm+ses, sim'e etkisi 0; mevsim yok (yaz). **Q-045** |
| A9 | Ses yönü (karakter, müzik) | kanonda yok; zevk | Ortam sesi, müzik yok, düşük seviye; sahip dinler. **Q-045** |
| A10 | Trafik/ulaşım T0 içeriği (tramvay, vapur) | Q-018 §4 | Bugünkü T0 ağı (yol, yük hattı, D1↔D6 yolcu feribotu); yeni hat icat edilmez. |
| A11 | Diğer metropollerin adı/karakteri | F05-D | Adsız toplu "ulusal" kalemi. |
| A12 | Para birimi | Q-003 | `¤`, değişmez. |

TEKNİK (stüdyo karar verir, sahibe sorulmaz): toplu ↔ parsel modeli, trafik yük modeli, yağmurun sim durumunda mı görünümde mi tutulacağı (öneri: hava durumu sim'de tohumlu tutulsun ki ileride A8-B yalnız veri değişikliği olsun; GOLDEN yenilemesi TD kapısıyla), perf bütçesi (ADR-0010).

### Sahibe sorulacak 3 soru (QUESTIONS.md biçimi; Studio Director ekler, ben eklemedim)

### Q-043 · Komşu ilçeler siz bakmıyorken nasıl değişsin?  (status: open)
- Context: M3 / WLD-11. Bugün D2 dışındaki boş araziler fiilen donuk (imar planını yalnız siz açıyorsunuz).
- Options: A) **(Önerilen)** Komşu belediyeler de sizin gibi imar planı açar, yatırımcılar karar verip bina yapar; siz dönüp bakınca yeni binaları ve "neden"ini görürsünüz, onların kararları sizin ilçenize de dokunur (işe gidiş, trafik, ev talebi). Adları/partileri yok. B) Komşular yalnız sessizce büyür (bina çıkar), belediye kararı ve size etkisi yok. C) A + komşu belediye haber/rakip gibi konuşur (ad/parti sonra karar).
- Recommendation: A — kanondaki "komşu belediye farklı kararlar verip dengeyi değiştirebilir" vaadini isim uydurmadan karşılar.
- Meanwhile: A veriyle kurulur, komşu karar sıklığı bir sayı; B'ye dönüş tek bayrak.

### Q-044 · Yol bakımı kasadan düşsün mü?  (status: open)
- Context: SIM-04 bakım maliyeti; D-010 bütçe bugün yalnız gösterge.
- Options: A) **(Önerilen)** Bakım her ay gerçek gider olarak düşer; kasa eksiye inebilir ama yol yapmanız engellenmez; eksi kasa meclis/gündemde konu olur. B) Kasa gerçek sınır: para yoksa yeni yol yok. C) Bakım yalnız gösterilir, kasa gösterge kalır.
- Recommendation: A — maliyeti hissettirir, inşa akışını kesmez (F03 "bürokrasi inşayı boğmaz").
- Meanwhile: C gibi davranır (gösterilir, kasa gösterge) ta ki yanıt gelene dek; geçiş tek ayar.

### Q-045 · Yağmur ve ortam sesi ne yapsın?  (status: open)
- Context: ROADMAP M3; Q-018 §7 (mevsim/hava) açık; görünüm sahibin zevkidir (D-029).
- Options: A) **(Önerilen)** Yağmur yalnız görünür ve duyulur, oyunu etkilemez; mevsim yok. Ses: kent uğultusu, deniz, yağmur; müzik yok. Önce/sonra karesi ve kısa ses örneği size gelir. B) A + yağmur trafiği yavaşlatır (oyuna etkisi var). C) Yağmur ve ses M3'ten çıkarılsın.
- Recommendation: A — en küçük, geri alınır adım; B sonra tek veri değişikliğiyle eklenebilir.
- Meanwhile: hiçbir görünüm/ses sizin onayınız olmadan ana dala girmez; iş dalda hazırlanır.

## 4. Yapılmaması gerekenler
- **CAN-03:** oyuncuya veya komşu belediyeye bina koyma; "ilçeyi büyüt", "yatırımcı çağır" düğmesi; altyapı → otomatik doğru bina.
- **Yetki:** oyuncu M3'te D2 dışında yol/imar/politika uygulayamaz; ilçeler arası yol/ulaşım (metropol yetkisi) yok. Kilitli araç gizlenmez, gerekçeli kilitli görünür.
- **Sahte evrim:** sim'de olmayan büyüme görünümü, görünüme özel "timelapse", haritada ayrı ve 3D'de ayrı büyüme (WLD-01/TEK-03). Toplu model 3D'ye yansıyorsa parsel durumuyla birebir olmalı; metropol yetkisi gelince tarih silinmez (CAN-11).
- **Sahte sayı:** ilçe özetinde, trafik katmanında, makro satırında sim'den gelmeyen sayı; aktiviteden türeyen araç yoğunluğunu "sıkışma" diye sunmak.
- **Tek skor:** ilçe notu, "ilçe mutluluğu %", sıralama tablosu (SIM-09).
- **Zorunlu gelecek:** komşuların seçili olgun görsele doğru senaryolu ilerlemesi (F05-E "aynı bitmiş şehri dayatmak"); adaya liman/sanayi taşıyan otonom büyüme (WLD-03); D1–D6'yı birleştiren/körfezi dolduran büyüme (WLD-05); tek sektöre kayan ilçe (WLD-06); D4'ün tamamen kentleşmesi.
- **Ad uydurma:** komşu başkan, parti, diğer metropol, kurum adı (CAN-01, F05-D). Seçim/oy kampanyası yok (M4).
- **Pop-up yağmuru:** makro/komşu haberleri modal olmaz, oyunu durdurmaz (F03 tempo).
- **Görsel ret listesi:** hiperreal/sinematik yağmur, parlak oyuncak efekt (VIS-01/05); sahip onaysız palet/ses (D-029).
- **iPad için kısma:** komşu evrimi veya makro iPad'de daha sığ olmaz (PLT-03); sonuç farkı yok (PLT-04).
- **Sessiz GOLDEN değişimi:** yeni sim sistemi bayrakla gelir, kapalıyken mevcut hash'ler aynı kalır; açılınca bilinçli yenileme + TD.
- **Siyaseti kopuk kart oyununa çevirmek:** her haber dünyada bir yere ve bir nedene bağlı (F01 sütun 2, F05-E son madde).

## 5. Çıkış ölçütü önerisi (hepsi gözlemlenebilir; her biri olumlu + olumsuz durum)
1. **Bakmıyorken değişim (WLD-11):** yeni oyun, yalnız D2'de 5 oyun yılı (hızlı); kamera D3/D4'e hiç gitmez. Sonra gidilince 3D'de yeni yapı/inşaat/kapanış vardır, sayısı ilçe özetiyle ve sim parsel durumuyla birebir. *Olumsuz:* durgun profilli ya da pahalı finansmanlı tohumda komşu az/hiç büyümez, gerileyebilir ve özet nedenini yazar.
2. **Bakmak sonucu değiştirmez (TEK-01/02):** aynı tohum, (a) kamera hep D2'de, (b) kamera tüm ilçeleri geziyor → N tick sonra durum hash'i eşit; ortada kaydet→yükle → eşit. Platformlar arası eşit (PLT-04).
3. **Komşu bana dokunur (SIM-12):** en az bir komşu kararı D2'de okunur bir değişiklik doğurur ve "Neden?" zinciri komşuya kadar gider. *Olumsuz:* bağlantı yolu yoksa/kesilirse aynı etki oluşmaz.
4. **Makro (SIM-06/07):** finansman pahalılaşınca yatırım retleri "finansman" gerekçesiyle artar, ucuzlayınca azalır; iki makro tohumu aynı oyuncu girdisiyle farklı sonuç verir. Hiçbir makro sayı sim dışından gelmez.
5. **Trafik (SIM-04):** büyüyen mahallenin bağlantı yolunda sim yükü kapasiteyi aşınca sıkışma 3D'de ve denetçide görünür; paralel yol çizilince ölçülen yük düşer. *Olumsuz:* hiçbir şey yapılmazsa sıkışma sürer/büyür ve en az bir grup tepkisine/gündeme yansır.
6. **Altyapı maliyeti (SIM-04):** bakım satırı ağ uzunluğu/kapasiteden hesaplanır; yol eklemek bakımı artırır, yıkmak azaltır; kapasite dolunca yatırım "altyapı" gerekçesiyle reddedilir.
7. **Ayrışan şehirler (SIM-10/11):** aynı T0, iki betikli strateji, 10 oyun yılı → yoğunluk, sektör payı ve yol yükünde fark, aynı stratejinin tohumlar arası farkından büyük; metropol karesinde gözle ayrışır. Aynı strateji, 3 tohum → komşuların evrimi aynı değildir.
8. **Kanon bekçileri:** otonom büyüme T0 sonrası adalarda liman/ana sanayi üretmez; D1–D6 birleşmez; tek sektörlü ilçe yok; oyuncu D2 dışında araç kullanamaz (gerekçeli kilit); CAN-03 testleri yeşil.
9. **Yağmur/ses:** yağmur aynı anda metropol ve sokak bakışında tutarlı; ses dünyadaki gerçek duruma bağlı; sahip önce/sonra karesini ve ses örneğini onaylamadan ana dala girmez.
10. **Performans:** komşu evrimi + trafik açıkken ADR-0010 kare bütçesi masaüstünde ve iPad'de ölçümle (varsayımla değil) tutar; aşan değişiklik kanıtla gerekçelenir.
11. **Sahip kabulü:** sahip demoda D2'de oynar, sonra komşuya bakıp "değişmiş, nedenini görüyorum" der. Build/test geçmesi tek başına M3 kanıtı değildir.

Önerilen sıra: (1) donukluğu ölç → (2) komşu belediye aktörü + ilçe özeti (Q-043 A varsayımıyla, bayraklı) → (3) makro → (4) trafik yükü + bakım → (5) SIM-10 iki strateji testi → (6) yağmur/ses dalda, sahip onayına.
