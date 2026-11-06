# 2026-11-06 · Teknik direktör: iPad `busy_ms` iki kipli (bimodal) — ölçüt, PerfLogger alanı, koşu kitabı

Kapsam: karar notu. Kod, ADR ve test değiştirilmedi. Girdi: `production/log/2026-11-06-ipad-olcum.md` (son iki bölüm), ADR-0010 Karar 3/3a, `production/log/2026-11-06-busy-ms-kalibrasyon.md`, ham JSON `artifacts/perf/ipad-g2/ipad-{d1,d2,d3,e1,f1,e2,f2,g2}.json` (git dışı).

## Karar (özet)
1. **Tek koşu ile karar verilmez.** iPad'de maliyet satırları `busy_ms` ile değil, **`is_ms` = `pre_draw_ms` + `render_cpu_ms`** ile, en az 5 kısa koşunun **en kötü koşusu** üzerinden okunur. `busy_ms` kapı değildir; "bekleme dahil üst sınır + kip tanısı" olarak yazılmaya devam eder. Akıcılık satırları (kare p95/p99, aralığı aşan kare oranı) **kip başına** ve kip sıklığıyla (k/N koşu) raporlanır; geçme/kalma kararını **en kötü kip** verir. Cihaz ısıl/pil durumu Godot'tan okunamadığı için (aşağıda) "cihaz durumu etiketi" = sahibin elle doldurduğu ön koşul listesi + veriden türetilen kip etiketi + Mac'ten `devicectl` yan kaydı.
2. **Ön hedef etiketi KALIR** (Karar 3 ve 3a, tüm iPad satırları). Etiketin kalkması için önce aşağıdaki seri, sonra etkileşim, soğuk açılış ve yoğun çekirdek bakışı ölçülmeli.
3. **15 dk ısıl koşunun `busy_ms` p95 oranı (1,085) maliyet kanıtı sayılmaz** (gerekçe aşağıda). Isıl koşunun kare p95 oranı (1,015) **akıcılık** kanıtı olarak geçerli kalır. Isıl kapı da `is_ms` p95'e taşınmalı.

## Gerekçe (kanıt)

### Doğrulanmış (ham JSON'dan kendim okudum, `stable` blokları)
| Koşu | busy ort / p50 | pre_draw ort | render_cpu ort / p95 | kalan = busy − pre − rcpu | kullanım |
|---|---|---|---|---|---|
| d1 | 10,29 / 8,06 | 0,55 | 2,33 / 4,93 | **7,41** | 0,970 |
| d2 | 10,24 / 8,06 | 0,56 | 2,29 / 4,76 | **7,39** | 0,969 |
| d3 | 10,25 / 8,06 | 0,55 | 2,31 / 4,83 | **7,39** | 0,970 |
| e1 | 1,99 / 1,51 | 0,45 | 1,28 / 1,98 | 0,26 | 0,238 |
| e2 | 9,91 / 8,03 | 0,22 | 0,48 / 0,55 | **9,21** | 0,966 |
| f1 (ölçüm kapalı) | 8,81 / 8,03 | 0,54 | — | (8,27, rcpu yok) | 0,964 |
| f2 (ölçüm kapalı) | 9,84 / 8,06 | 0,57 | — | (9,27, rcpu yok) | 0,969 |
| g2 (15 dk) | 2,15 / 1,45 | 0,35 | 1,03 / 2,11 | 0,77 | 0,258 |

- "Kötü" kipteki fazla süre **ölçtüğümüz CPU işinde değil**: `pre_draw + render_cpu` her koşuda ort ≤ 2,9 ms, p95 ≤ ~5,5 ms. Fark, iki döküm parçasının dışında kalan "kalan" dilimde (7,4-9,2 ms).
- Kötü kipte `busy` p50 **8,03-8,06 ms**, p95 **16,38-16,45 ms**: 120 Hz aralığının (8,33) ve iki katının hemen altı. Yavaş CPU sürekli bir dağılım verirdi; yenileme aralığına kilitlenmiş değerler **bekleme** imzasıdır.
- g2 (15 dk) pencereleri tek koşu içinde kip değiştiriyor: pencere `busy_ms_mean` 2,9 → 0,67-0,75 (11-12,5. dk, p95 ≈ ort) → **7,07** (13,5. dk, pencere kare p99 16,68) → 2,2. Yani kip koşu başında sabitlenmiyor.
- g2'nin ilk/son 2 dk `busy` p95 değerleri (7,98 / 8,66) de aralığa yakın; ısıl oran bu yüzden işi değil bekleme payını karşılaştırıyor (Karar 3 yukarıda).
- Godot 4.7.2'de (kurulu ikili, `ClassDB` taraması: OS, DisplayServer, Engine, Performance, RenderingServer, Time) **ısıl durum, pil, şarj, Düşük Güç Modu, çekirdek türü için API YOK.** Var olanlar: `OS.get_processor_count()`, `OS.get_processor_name()` (statik, kip ayırmaz), `DisplayServer.screen_get_refresh_rate()` (Düşük Güç Modu için tek dolaylı gösterge, zaten yazılıyor), `RenderingServer.viewport_get_measured_render_time_cpu` / `get_frame_setup_time_cpu` (zaten kullanılıyor). `docs/engine-reference/godot/` bu konuda bilgi içermiyor.
- `xcrun devicectl device info` alt komutları (Mac'te `--help`): `details`, `displays`, `lockState`, `processes` var; ısıl/pil alt komutu yok.

### Varsayılan / hipotez (doğrulanmadı)
- "Kalan" dilim büyük olasılıkla sunum/takas (`swap_buffers` → iOS sunumu) ya da GL sürücüsünün GPU'yu beklemesidir; `frame_post_draw` takastan sonra yayıldığı için (kalibrasyon notu, kaynak okuması) bekleme busy'ye girer. Kötü kipte gerçekten kare kaçıyor (kare p95 16,7-16,8; ort 10,6'dan hesapla karelerin ~%27'si 16,7 ms [hesap, kare dağılımı iki değerli varsayılarak]).
- Kipin nedeni için adaylar: GPU saat durumu (DVFS) ya da sistem birleştiricisinin (bildirim, kontrol merkezi, uygulama başlatma kalıntısı) sunum yolunu değiştirmesi. CPU saat düşüşü verilerle desteklenmiyor (CPU döküm parçaları iki kipte benzer), ama dışlanmış da değil.
- g2'de 0,67 ms'lik pencereler, oturum ortalaması 1,03 ms olan `render_cpu`dan küçük: iOS'ta busy penceresinin sınırları render işinin tamamını kapsamıyor olabilir. Pencere başına döküm olmadığı için açıklanamadı; aşağıdaki A1 alanı bunu çözer.
- `is_ms` de saf iş değil (GL çağrılarındaki bloklama `render_cpu`ya girer; masaüstünde busy'nin ~%85'i). Bu yüzden "üst sınır değil, en iyi tahmin" diye etiketlenir.
- Apple tarafında `ProcessInfo.thermalState`, `isLowPowerModeEnabled`, `UIDevice.batteryState/Level` var [genel bilgi, bu oturumda Apple belgesinden doğrulanmadı]; Godot'tan okumak yerel iOS eklentisi (yeni bağımlılık + dışa aktarma hattı değişikliği) ister.

### Reddedilen seçenekler
- **Tek koşu:** 7 kısa koşunun 1'i iyi, 6'sı kötü kipteydi; uzun koşu kip değiştirdi. Tek koşu rastgele bir kip örneğidir.
- **Çoklu koşuda `busy_ms` en kötü kipi:** kötü kipte busy beklemeyi ölçüyor; "en kötü busy" maliyeti değil sunum davranışını cezalandırır ve yanlış optimizasyona (CPU işi azaltma) götürür.
- **Şimdi iOS yerel eklentisi (ısıl/pil):** yeni bağımlılık; mevcut veri CPU saatini birincil şüpheli göstermiyor. Önce bedava alanlar; CPU yoklaması iki kipte farklı çıkarsa eklenti `experiments/` altında denenir.

## Akıcılık hedefi için not (öneri, ADR değişikliği ana oturum/TD onayıyla)
120 Hz'de kare süresi aralığın katlarına kuantalı: iki aralık = 16,67 ms. "p95 ≤ 16,6" hedefi, karelerin %5'inden fazlası bir kez kaçarsa 0,07 ms farkla kalır (kötü kip: 16,70-16,83, tavan 20'nin içinde). 120 Hz'de akıcılık satırının birincil sayısı **aralığı aşan kare oranı** (> 1,5 × aralık) olmalı; ms satırları tanı olarak yazılır. Eşik değeri hiss/ürün sorusuna bağlı (aşağıda sahip sorusu adayı).

## (2) PerfLogger'a eklenecek ucuz alanlar (öncelik sırasıyla; `src/view/perf/perf_logger.gd`, yalnız `--perf-log` altında)
- **A1 · Pencere dökümü (yeni API yok, yalnız toplama):** her pencere girdisine `pre_draw_ms_mean`, `render_cpu_ms_mean`/`p95`, `is_ms_mean`/`p95` (= pre + rcpu; rcpu önceki çizilen kareye ait olduğundan pencere ortalaması üzerinden), `rest_ms_mean` (= busy − is), `busy_near_interval_frac` (busy ≥ 0,85 × 1000/`refresh_hz` olan kare oranı), `over_interval_frac` (kare > 1,5 × aralık). Üst düzeye ve `stable`e aynıları + `thermal` içinde `is_first_p95`, `is_last_p95`, `is_p95_ratio`. Eski alanlar aynen (rapor biçimi geriye uyumlu, `format` artar).
- **A2 · Kip etiketi (veriden):** pencere başına `mode` = "A" (`busy_near_interval_frac` < 0,2 ve kullanım < 0,5), "B" (aksi), üst düzeyde `mode_windows` {A: n, B: n}. Eşikler sabit olarak dosyada, testli.
- **A3 · CPU hız yoklaması:** saniyede bir, ana iş parçacığında sabit, deterministik GDScript döngüsü (~0,1-0,3 ms; `Time.get_ticks_usec()` ile), pencere başına `cpu_probe_us_min`/`_p50`. O karenin busy'sinden düşülür ya da kare özetten atılır (ölçüm kendi ölçtüğünü kirletmesin). Simülasyona dokunmaz, sim saflık testini etkilemez. İki kipte yoklama aynıysa CPU saati neden değildir.
- **A4 · Mac yan kaydı (oyun kodu yok, betik):** her koşudan önce/sonra `xcrun devicectl device info displays|lockState|processes --json-output` → koşu dizinine. İçeriğin bu cihazda ne döndürdüğü doğrulanmadı; arka plan süreçleri ve ekran durumu için ucuz.
- Godot'tan **okunamayan** (doğrulandı, yukarıda): ısıl durum, pil/şarj, Düşük Güç Modu (yalnız `refresh_hz`=60 dolaylı), çekirdek türü. Uydurma alan eklenmez.
- Test: A1/A2 için `tests/view/perf/perf_logger_busy_test.gd`'ye sentetik dizilerle (kip A, kip B, karışık) birim testleri. Uygulama: `godot-engineer` (sonnet), küçük iş.

## (3) Sonraki iPad koşu kitabı
**Ön koşul (sahip, cihazda; koşu kaydına elle yazılır, eksikse koşu geçersiz):** şarj kablosu takılı (şarj %'si ekrandan yazılır), Düşük Güç Modu kapalı, Otomatik Kilit "Hiçbir Zaman", Odak "Rahatsız Etme" açık (bildirim + b1'deki ses kesintisi), arka planda başka uygulama yok (uygulama değiştiriciden kapatılmış), koşu sırasında ekrana dokunulmaz, cihaz düz zeminde, kılıf durumu seri boyunca aynı, oda sıcaklığı.
**Yapı:** A1-A4 eklenmiş tek release yapısı, seri boyunca değişmez; commit kimliği kayda yazılır. Betik: benzersiz koşu adı (seri ön eki + sıra + saat) ve çekilen dosyanın `started_unix`i başlatma saatinden sonra değilse "bitti" sayılmaz (eski aynı-ad dosya hatası iki kez yaşandı).

| Adım | Koşu | Koşul | Amaç |
|---|---|---|---|
| 0 | — | uygulama kapalı, cihaz şarjda 15 dk boşta | soğuk başlangıç |
| 1 | S1-S5 | 5 × kısa demo (6000 kare), render ölçümü AÇIK, aralarda uygulama sonlandırılır + 60 sn bekleme | kip sıklığı (k/5), `is_ms` en kötü koşu |
| 2 | S6 | 1 × kısa, render ölçümü KAPALI | araç yükü kontrolü (A1'in pre/rest alanlarıyla) |
| 3 | U1 | 1 × 300 sn demo (`--perf-log-thermal` süre 300), tek açılış | koşu içinde kip değişimi |
| 4 | I1 (isteğe bağlı) | bir koşu B kipindeyken 30 sn Instruments (xctrace, GPU/Metal izi) | GPU süresi ve sunum beklemesini doğrudan görmek; xctrace'in Compatibility/GL yolunda ve ağ bağlantısında çalıştığı DOĞRULANMADI, çalışmazsa seri bekletilmez |
| 5 | S7-S9 | U1'den hemen sonra 3 × kısa (sıcak cihaz) | sıcak/soğuk farkı |

Toplam ~10 koşu, ~35-40 dk (çoğu gözetimsiz). Rapor tablosu her koşu için: kip etiketi (pencere sayımı), `is_ms` ort/p95, `rest_ms` ort, busy ort, kare p95, aralığı aşan oran, CPU yoklaması, ön koşul listesi.
**Okuma kuralı:** maliyet satırları = 9 kısa koşunun en kötü `is_ms`i; akıcılık = kip başına, kararı en kötü kip verir, kip sıklığı yazılır. Bugünkü verilerle `is_ms` en kötü ort 2,9 / p95 ~5,5 ms (≤ 8 / 16,6 ön hedefin içinde) [doğrulanmış sayı, yeni tanımla resmi ölçüm değil].
**Sonraki karar dalı:** (a) CPU yoklaması iki kipte aynı ve fark `rest_ms`teyse → kipler sunum/GPU kaynaklı; maliyet satırları `is_ms` ile kapatılır, B kipi bir **akıcılık hatası** olarak `godot-engineer`e gider (iOS kare temposu; 60/120 seçimi sahibe). (b) Yoklama B kipinde belirgin yavaşsa → CPU saat/çekirdek; ısıl/güç durumunu okumak için yerel iOS eklentisi `experiments/` altında denenir (üretime alınmaz, ADR gerekir).

## Takip önerileri (kimlikleri Studio Director atar)
- PerfLogger A1-A3 + testler (`src/view/perf/perf_logger.gd`, `tests/view/perf/perf_logger_busy_test.gd`); A4 + ad/zaman düzeltmesi (`tools/ipad-pull-perf.sh` ve seri betiği).
- ADR-0010 Karar 3a güncellemesi (bu not kabul edilirse): maliyet satırı `busy_ms` → `is_ms`; ısıl satırı `is_ms` p95; 120 Hz akıcılık için aralığı aşan oran birincil; çoklu koşu + en kötü kip kuralı; Karar 3 ölçülen paragrafındaki "ısıl busy oranı GEÇTİ" ifadesine "akıcılık için geçerli, maliyet kanıtı değil" notu.

## SAHİP SORUSU ADAYI
1. (Seriden sonra, B kipi sık çıkarsa) iPad'de "120 Hz, arada kare düşüşü (kötü kipte karelerin ~%27'si)" mi, yoksa "60 Hz'e kilitli, sabit" mi daha iyi hissettiriyor? Bu bir his/ürün tercihi (ADR-0004 iPad profili); öneri: önce seriyi bitir, sonra iki ayarlı demoyu sahibe aç, kendisi seçsin.
2. (Lojistik, karar değil) seri için ~40 dk cihaz ayrılması ve koşu süresince "Rahatsız Etme" açık tutulması.
