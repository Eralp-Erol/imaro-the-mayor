# M2 kapanış listesi (taslak) — 2026-11-04

> **GÜNCEL DURUM (2026-11-06 gece-2):** `verify full` PASS @ HEAD ~6940ed0 öncesi (3140 test, 0 hata, B-122 dahil); yerel main güncel (push yok). B-042, B-130/D-026, B-122 çözüldü/uygulandı. iPad: KISMİ ölçüm (4 geçerli VSync'li koşu, ort 8,33 ms, p99 ≤ 14,4, çizim 302, üçgen ~398k); ısıl, etkileşim, soğuk açılış, VSync'siz maliyet YOK (cihaz uygulamayı ~30 sn sonra kesiyor + iOS VSync'i kapatmıyor; `production/log/2026-11-06-ipad-olcum.md`). Sahipte: Q-041 (iki grup ölçütü), Q-042 (gündem düğmesi konumu), iPad Otomatik Kilit + soğuk açılış/yol onayı/ısınma adımları. Sanat direktörü incelemesi zevk kararı bekliyor. Aşağıdaki 2026-11-05 satırı geçmiş kayıttır.
>
> **(Önceki) 2026-11-05 gece:** `verify full` PASS @ 05c5a13 (3111 test, 0 hata). Tasarım direktörü FAITHFUL WITH FIXES (`production/log/2026-11-05-design-director-m2-kapanis.md`), teknik direktör KOŞULLU EVET (`production/log/2026-11-05-teknik-direktor-m2-kapanis.md`). Sahip kararları işlendi: D-021 (D2 başlangıç, yıkım→meclis güveni, iPad panelleri), D-022 (çekmece yüksekliği), D-023 (Meclis/Bütçe düğmeleri görünür), D-024/D-025 (boş arazi ve çatı ESKİ görünüşe döndü; zevk sahibindir). Q-035/Q-036/Q-038 yanıtlandı. **Tek sert bekleyen: iPad cihaz ölçümü (T-076; sahip: EN SONA).** Kalan hazırlık işleri: B-042 asıl çözüm, T-076 hazırlık, ≥2 grup tepkisi ölçümü (tasarım direktörü bulgusu), pencereli RED karesi (isteğe bağlı), sahibin demoyu oynayıp kabulü. B-027 (gerekçe ~100 günde günlükten düşer) BİLİNEN SINIRDIR, hata değil karar bekler. Aşağıdaki ayrıntılar 2026-11-04/05 öğleden kalma olup yer yer bayattır; yukarıdaki satır önceliklidir.

M2 = "İlk nedensel döngü (dikey dilim)", `production/ROADMAP.md`. Ölçüt: F03 "Oyun hissi için doğrulanması gereken kabul ölçütleri" (7 madde) + M2 satırındaki ek koşullar. Bu dosya KAPANIŞ DEĞİLDİR; neyin kanıtlı, neyin açık olduğunu ayırır. Kanıt yoksa "kanıt aranmadı" yazılır, "geçti" denmez. Karar yetkisi: sahip + director'lar.

## F03 ölçütleri

| # | Ölçüt | Durum | Dayanak / eksik |
|---|---|---|---|
| 1 | Mevcut yerleşim dokusu ve topografya hissedilir (boş grid değil) | KISMEN | T0 üreteci ve sanat kapıları kayıtlı (T-005, T-056..T-059 QA). Sahip görsel kabulü ve M1 açık ölçütleri: T-012 K8 LOD farkı düzeltilmiş (%2,6; bekçi olarak kalır), üçgen tavanı D-007 gereği ertelendi (ADR-0010; sayılar kayıtlardan, yeniden ölçülmedi); low-key ışık onayı ve VIS-04 görsel kapı açık. |
| 2 | Yol/imar/kamu alanı kararı fiziksel 3D dünyada uygulanır | KANITLI (masaüstü) | Çalışan döngü: yol çiz → kamulaştır → imar; pencereli QA turları 2-3. Yeni "belediye arazisini imara aç" girişi pencerede görüldü (T-066 kareleri; art-director: arazi görünümü ve liste ham numaraları YENİDEN YAPILMALI). |
| 3 | Yatırımcı/hane yanıtı kararla ilişkili ama otomatik değil | KANITLI | T-040 bağımsız QA 3. tur PASS; gerekçeli ret/kabul; CAN-03 testleri. |
| 4 | Nüfus/iş/ulaşım/bütçe değişimi anlamlı ve görünür | KISMEN | Değişim akışı ve bütçe göstergesi var. Kare/perf kanıtı sakin makinede tam değil. Q-003 para birimi açık ("gösterge"). Kalabalık/yoğunluk görsel kabulü sahipte. |
| 5 | En az bir karar gerçek siyasi/toplumsal tepki üretir | KANITLI (sim) / KISMEN (görüş) | Yol/yıkım tepkisi, gündem kartı, meclis var. Meclis RED yolu artık testle KANITLI (`tests/game/council_red_scenario_test.gd`: yeşil imar + dolu altyapı + ≥10 parsel, gürültüyle ~%5-8; UI/olay akışı hatasız); D-020: RED nadir kalsın. Pencereli RED karesi alınmadı. |
| 6 | Aynı alan farklı zoom'larda aynı dünya | KISMEN | Çok ölçekli kamera (T-003) var. Zoom geçişlerinde LOD farkı ölçütü açık (bkz. 1). |
| 7 | Örnek ilçe zorunlu başlangıç yeri olmaz | AÇIK (design-director: önceki ifade aşırı iyimserdi) | Mimari hazır, oyunda yok: başsız test (`tests/game/m2_start_district_test.gd`) yetki alanını ELLE değiştirerek 6 ilçede ve 2. tohumda döngüyü gösterdi (CAN-03, determinizm); gönderilen oyunda D2 dışında yol çizilemiyor. D-020: sahip "Hep D2'den başlasın" dedi — B-026 (yol yetkisi yalnız D2) karar gereği kapandı; ölçüt 7 D2 başlangıcıyla KISMEN. Pencereli kanıt yok. |

## M2 satırındaki ek koşullar
- **iPad'de aynı dilim cihazda oynanır (dokunmatik profil, ölçüm):** KISMEN. 2026-11-04 fiziksel iPad Pro 12,9" (6. nesil) üzerinde debug sürüm kuruldu ve oyun açıldı; sahip "istenildiği gibi çalışıyor" dedi (bildirim, ölçüm değil). Ölçüm (kare süresi, dokunma hassasiyeti, ısınma) YOKTU; 2026-11-06 gecesi KISMİ ölçüm alındı: release, 120 Hz, VSync'li demo 3 geçerli koşu, kararlı ort 8,33 ms, p95 8,6, p99 14, çizim ~302, üçgen ~398k (`production/log/2026-11-06-ipad-olcum.md`). Isınma, etkileşim, VSync'siz maliyet ve soğuk açılış HENÜZ YOK. Eski ayrıntı: `production/log/2026-11-04-ipad-gercek-cihaz.md`.
- **Masaüstü profiliyle kabul:** kısmen; sahip kabulü yok.
- **Performans:** sakin makinede masaüstü serisi ÖLÇÜLDÜ (2026-11-05, i7-8850H/Radeon 560X, 1600x900, `--demo`, 4×6000 kare): ort ~7,1 ms, p95 ~8,8, p99 ~11,2; yol gönderimi anında en kötü kare 130-207 ms; çizim ~315 çağrı, ~431k üçgen (tepe 1,0M). `--demo` açılışında tekil donmalar (kare 1 ≈ 4 sn, kare 60 ≈ 1,7 sn = B-028 demo kayıt/yükleme kancası). iPad cihaz ölçümü bu satır yazıldığında YOKTU (şimdi kısmi, bkz. iPad satırı); kare bütçesi hedefleri ADR-0010 ile sonradan konuldu. Ayrıntı: `production/log/2026-11-05-perf-serisi.md`.

## Kapanış için yapılacaklar (sırayla)
1. İki ilçe/başka tohumla başlatma: TEST YAZILDI (sim yarısı geçti). Başlangıç ilçesi: D-020 (hep D2) ile karara bağlandı.
2. Pencereli QA turu: yeni imar akışı (sürüyor), eski yolu yıkma ekranı (sürüyor), sonuç kareleri.
3. Meclis RED: senaryo bulundu ve test yazıldı (`production/log/2026-11-04-meclis-red-senaryosu.md`). Sahip kararı D-020: RED nadir kalsın. Kalan: pencereli RED karesi (isteğe bağlı).
4. Perf serisi YAPILDI (bkz. yukarı). Kare bütçesi hedefleri ADR-0010 ile konuldu (iPad satırları ön hedef, cihazda doğrulanmadı). B-028 düzeltildi (aşağıda). Kalan: iPad cihaz ölçümü (T-076), yol onayı takılması (T-075, sahip sorusu).
5. iPad: AÇILIŞ KANITLI (sahip bildirimi). Kalan: cihazda kare süresi/dokunma ölçümü, release sürüm, gerçek ikon ve iOS ana sahne düzeni.
6. M1'den taşınan görsel ölçütler (LOD farkı, üçgen bütçesi): art-director + technical-director kararı.
7. Üç yönetici incelemesi (design / art / technical director) + `verify full` + kapanış kaydı.

## Yönetici incelemeleri (2026-11-05)
- **Teknik direktör:** `docs/adr/ADR-0010-kare-butcesi-hedefleri-m2.md`, `production/log/2026-11-05-teknik-direktor-perf.md`.
- **Tasarım direktörü:** FAITHFUL WITH FIXES (`production/log/2026-11-05-design-director-m2.md`): CAN-03 ve D-017..D-019 sadık. Düzeltmeler: ölçüt 7 (yapıldı); bekleme listesi (T-067) oyuncuya görünmüyor (UI yok) ve gerçek Ismeral'de çalışıp çalışmadığı ÖLÇÜLMEDİ; halk tepkisinin meclise etkisi ölçülmedi; D-020 'Hep D2' kanonun 'Orven zorunlu başlangıç değil' reddiyle çakışıyor -> Q-035 (YANITLANDI → D-021).
- **Sanat direktörü:** PASS WITH FIXES / KABUL EDİLEBİLİR (`production/log/2026-11-05-art-director-m2.md`): ışık GEÇTİ; yıkılan yol/boş arazi düz hardal sarısı lekesi ve imar paneli ham parsel numaraları YENİDEN YAPILMALI; dokunmatik HUD şehrin ~%60'ını örtüyor; 800x600 ve 768x1024 için karar verilemedi (kare yok). Sahibe sorulacak zevk kararları: çatı paleti, boş arazinin görünüşü, dokunmatik panel yeri.
- QUESTIONS.md durumları gözden geçirildi (2026-11-05): Q-014, Q-025, Q-026 kayıtta artık "answered" (D-011/D-014); parametreler çalışma değeri olarak açık.

## Ölçümler (2026-11-05, `production/log/2026-11-05-bekleme-listesi-meclis-olcum.md`)
- **Bekleme listesi çalışıyor (gerçek Ismeral D2, 2 dünya tohumu, 200 gün):** yola yakın boş parsellere konut imarı verilince yatırımcı bitirdi, bekleyen ailelerin tamamı ev aldı (56/56, 42/42, 12/12; ikinci dünyada 72/72, 32/32, 12/12). İmar yoksa 0 yeni konut ve liste sabit kalır (CAN-03 gereği). Tasarım direktörünün 'sınır listeyi hep kapatır' hipotezi gönderilen veride YANLIŞ; yalnız `leave_region` kaderinde (gönderilmiyor) ölü (B-029).
- **Yıkım -> meclis (8 tohum, 144 koşu):** yıkım meclis üyesi güvenini DÜŞÜRMÜYOR; oylamayı hafifçe kolaylaştırıyor (altyapı yükü düştüğü için). Tepki -> meclis bağı yok (B-030, Q-036: YANITLANDI → D-021).
- Gerekçe kaydı ~100 günde düşüyor (B-027); bekleme listesi gerekçeleri de etkileniyor (12 yazıldı, 200. günde 9).

## Sahip kararları (M2'yi engellemez, ama kapanış kartında sorulur)
Yol onayında takılma (130-207 ms): KAYNAK bulundu = Yaşam görünümünün tek karede yeniden kurulması (ADR-0010 Karar 5 hipotezi çürüdü); görünüm tarafında kare dilimine yayıldı (B-040): en kötü yol karesi ~217 ms → ~24 ms (masaüstü, pencereli, yük 3-6; iPad DEĞİL, tam sakin makine değil). Kalan 20-36 ms için B-041 önerileri. Sahip kararı gerekmiyor (sim sınırı değişmedi); iPad ölçümü T-076.
Q-003 para birimi · Q-015 Ismeral coğrafya onayı · Q-018 sanat kütüphanesi şablonları · R1-R3 yeniden iskân varsayımları · T-065 Aşama 2.

## Doğrulanmadı
Bu liste dosya okumasından derlendi; testler koşturulmadı. Durum sütunundaki "KANITLI" ifadeleri ilgili QA kayıtlarına dayanır, bu oturumda yeniden doğrulanmadı.
