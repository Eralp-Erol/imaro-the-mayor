# iPad Pro 12,9" (6. nesil) ölçüm kaydı — T-076 (TASLAK, seri sürüyor)

Durum: **KISMİ.** VSync'li DÖRT geçerli demo koşusu ölçüldü (a1, a2, a3-eski, a3-yeni). VSync'siz seri (b1, b2), ısınma, etkileşim ve soğuk açılış HENÜZ YOK. Hedefler `docs/adr/ADR-0010-kare-butcesi-hedefleri-m2.md` Karar 3 (ön hedef).

## Koşul (doğrulanmış, JSON alanlarından)
iPad14,5, iPadOS 26.5.2, release dışa aktarma (`debug_build` false; ham JSON `artifacts/perf/ipad-a*/`, git dışı), Godot Compatibility (`gl_compatibility`, Apple M2 GPU), 120 Hz (`refresh_hz`), `vsync_mode`=1 (VSync AÇIK), `--demo`, 6000 kare, ~50 sn. Kararlı pencere 30. sn'den sonra. Pencere 2732x2048.
Yapı: HEAD 7b155b9 sonrası (B-042 dahil). Başlangıç zamanları (UTC, `started_unix`): a1 21:40, a3-eski 22:09 (önceki seri), a2 00:00, a3-yeni 00:04. İki "a3" dosyası farklı koşular: `artifacts/perf/ipad-a3/ipad-a3.json` (eski) ve `artifacts/perf/ipad-b1/ipad-a3.json` (yeni; pull betiği cihazdaki tüm dosyaları hedef dizine çekiyor). Seri betiği aynı ada sahip eski yerel dosyayı "tamam" saydığı için a3'ün 24 sn'de bittiği görünüyordu; veri yine de gerçek iki ayrı koşu.
**Geçersiz:** a4 (`reason=pause`, 1121 kare, 11 sn) ve b1 (`reason=pause`, 587 kare; ayrıca `vsync_mode`=1, yani VSync'siz istek iOS'ta uygulanmadı). b1 cihaz konsolu: `Audio interruption began` ~30 sn sonra, süreç sonlandı (signal 15). Kesinti nedeni (ekran kilidi/otomatik kilit/bildirim) uzaktan doğrulanamadı. b1 ayrıca `refresh_hz`=60 (p50 16,68 ms) idi; a-serisi 120 Hz idi. Godot iOS'ta Düşük Güç Modu açıkken 60 döndürür: b1 büyük olasılıkla Düşük Güç Modu'nda koştu [TD çıkarımı, doğrulanmadı]. Sonraki koşular şarjda, Düşük Güç Modu kapalı olmalı.

## Sonuçlar (kararlı pencere, ms)
| Koşu | ort | p50 | p95 | p99 | maks | >33 ms | >100 ms | çizim ort | üçgen ort |
|---|---|---|---|---|---|---|---|---|---|
| a1 | 8,33 | 8,34 | 8,62 | 14,18 | 17,39 | 1 | 0 | 302 | 398 288 |
| a2 | 8,34 | 8,34 | 8,64 | 14,39 | 19,11 | 2 | 1 | 302 | 398 290 |
| a3-eski | 8,33 | 8,34 | 8,64 | 13,91 | 18,84 | 1 | 1 | 302 | 398 291 |
| a3-yeni | 8,33 | 8,34 | 8,47 | 13,43 | 16,95 | 1 | 0 | 302 | 398 288 |

>100 ms sayısı (a2, a3: 1) ilk kareyle uyumlu: ilk kare süresi a2 106,5 ms, a3 102,4 ms (`startup.first_frames_ms`); kararlı pencere değil, açılış karesi. [Bu eşleşme sayıdan çıkarım, tek tek kare doğrulaması yapılmadı.]

## ADR-0010 ön hedefleriyle karşılaştırma (yalnız demo bakışı)
| Ölçü | Ön hedef | Ölçülen (a1-a3) | Durum |
|---|---|---|---|
| Kararlı ort | ≤ 8 ms (tavan 14) | 8,33-8,34 (4 koşu) | VSync'li 120 Hz'de kare süresi 8,33 ms'ye kilitli: ort ≤ 8 bu modda **ölçülemez**; gerçek maliyet için VSync'siz seri (b) gerekir. Tavanın (14) içinde. |
| p95 | ≤ 16,6 (tavan 20) | 8,62-8,64 | geçti (demo) |
| p99 | ≤ 25 (tavan 33,3) | 13,9-14,4 | geçti (demo) |
| En kötü etkileşim karesi | ≤ 50 (tavan 100) | demo maks 17,4-19,1 | **etkileşim ölçülmedi** (yol onayı oturumu sahip bekliyor) |
| Draw call / üçgen | ≤ 400 / ≤ 900k | 302 / 398k | geçti (demo bakışı; yoğun çekirdek 2,87M bakışı iPad'de ölçülmedi) |
| Bellek | ≤ ~1,5 GB, sonlandırma yok | tampon 194-200 MB, video 397 MB, fiziksel 7518 MB / boş 2184 MB (a1); sonlandırma yok | geçti (50 sn'lik koşu; uzun koşu yok) |
| Açılış ilk kare | örtüsüz blok ≤ 1 sn | ilk kare 85-107 ms; ilk işlem karesi ~10,5 sn | ilk kare tek blok olarak geçti; "ilk etkileşimli kare ≤ 30 sn" için soğuk açılış kronometresi gerekir (sahip) |
| Isıl | son 2 dk p95 ≤ ilk 2 dk × 1,25 | YOK | ısınma koşusu bekliyor |

## Doğrulanmadı / eksik
- VSync'siz seri (b1, b2): **İPTAL** (iOS'ta uygulanamaz; teknik direktör notu `production/log/2026-11-06-teknik-direktor-b027-vsync.md`). Önceki gerekçe: İstek (`--perf-log-novsync`) bu iOS yapısında uygulanmıyor (`vsync_mode` hep 1; kodda "iOS yok sayabilir" notu var) ve cihaz ~30 sn sonra "Audio interruption" ile uygulamayı kesiyor. Gerçek kare maliyeti için başka yol gerekir (örn. kare süresi yerine CPU/GPU zamanı), teknik karar.
- 15 dk ısınma koşusu.
- Etkileşim (yol onayı, pan/pinch) en kötü kare.
- Soğuk açılış kronometre, Düşük Güç Modu / şarj durumu / pil kaydı (koşullar sahipten istenecek; JSON'da yok).
- Yoğun çekirdek bakışı üçgen sayısı.

## busy_ms koşuları (2026-11-06 10:30-10:45, yeni release, `busy_ms` PerfLogger) — GEÇERSİZ (60 Hz)
Bağlantı bulgusu (doğrulanmış): iPad `connected` yalnız bir `devicectl` komutu tüneli açtığı sürece görünüyor, sonra `available (paired)`e düşüyor (taşıma: localNetwork). Önceki otomasyon yalnız listeye baktığı için ekran açıkken bile hiç yakalayamadı; betik artık önce `devicectl device info details` ile cihazı uyandırıp sonra yokluyor.

| Koşu | complete | refresh_hz | busy ort | busy p95 | busy p99 | kullanım | kare p50 / p95 |
|---|---|---|---|---|---|---|---|
| c1 | true (6000 kare) | **60** | 4,70 | 12,74 | 15,55 | 0,287 | 16,67 / 24,16 |
| c2 | true (6000 kare) | **60** (değişmedi) | 4,81 | 14,01 | 15,41 | 0,292 | 16,68 / 24,58 |

Geçerlilik: kural gereği `refresh_hz`=120 beklenir; 60 çıktığı için ADR-0010 hedefleriyle KARŞILAŞTIRILMADI. Neden: Düşük Güç Modu şüphesi (TD çıkarımı), cihazdan uzaktan okunamadı; DOĞRULANMADI. Sayılar yalnız gösterge (CPU meşgul ort ~4,7-4,8 ms, kullanım ~%29 bu modda). c3 (betik) ve 15 dk ısıl koşu 60 Hz'de çalıştırılmadı/iptal: mod düzelmeden anlamlı değil. Bekleyen: sahip iPad'de Düşük Güç Modu'nu kapatıp şarja takacak; sonra c1-c3 + ısıl yeniden.

## 120 Hz'li busy_ms koşuları ve A/B (2026-11-06 12:42-13:32) — GEÇERLİ koşu koşulu (120 Hz sabit, complete), SONUÇ BİMODAL
Sahip Düşük Güç Modu'nu kapattı (12:40; 60 Hz nedeni buydu, doğrulandı: kapanınca ilk yoklama 120.0). Not: seri betiği cihazdaki eski aynı-ad dosyayı "bitti" saydı (c1 18 sn'de, 60 Hz değerleriyle); bu koşu GEÇERSİZ, silindi/sayılmadı; yeni koşulara benzersiz ad (d1-d3, e/f) verildi.

| Koşu | Saat | render ölçümü | kare ort | kare p95 | busy ort | busy p50 | busy p95 | kullanım |
|---|---|---|---|---|---|---|---|---|
| d1 | 12:42 | açık | 10,60 | 16,82 | 10,29 | 8,06 | 16,45 | 0,933 |
| d2 | 12:45 | açık | 10,57 | 16,83 | 10,24 | 8,06 | 16,45 | 0,933 |
| d3 | 12:48 | açık | (d1-d2 ile tutarlı) | | 10,25 | | | 0,932 |
| e1 | 13:25 | açık | **8,34** | 8,53 | **1,99** | 1,51 | 3,48 | **0,244** |
| f1 | 13:28 | KAPALI | 9,13 | 16,70 | 8,81 | 8,03 | 16,38 | 0,868 |
| e2 | 13:30 | açık | 10,26 | 16,70 | 9,91 | 8,03 | 16,39 | 0,919 |
| f2 | 13:32 | KAPALI | 10,16 | 16,81 | 9,84 | 8,06 | 16,44 | 0,922 |
Hepsi: 120 Hz sabit (`refresh_hz_changed` false), 6000 kare, çizim 302, üçgen ~398k (sahne aynı).

Doğrulanmış:
- Ölçüm aracının render süresi ölçümü (`viewport_set_measure_render_time`) yükü NEDEN DEĞİL: kapalı (f) ve açık (e) koşular aynı bozuk değerlere de aynı iyi değere de düşüyor (e1 iyi, e2 kötü). Bayrak: `--perf-log-no-render-measure` (commit 3572092, testli).
- Oyun kodu a-serisinden bu yana fonksiyonel olarak aynı (yalnız HUD çekmece düzeni 9 satır + perf_logger). Çizim/üçgen sayıları aynı.
- Aynı yapı, aynı sahne: CPU meşgul süresi koşudan koşuya ~2 ms (e1) ile ~10 ms (diğerleri) arasında; "iyi" durumda kare 8,34 ms'de kilitli (kullanım %24), "kötü" durumda kare süresi 16,7 ms'ye düşen kareler (p95) ve kullanım %87-93.
Doğrulanmadı (HİPOTEZ): iPad'in güç/ısıl politikası ya da çekirdek planlaması (şarj ısınması, arka plan etkinliği) CPU hızını koşular arasında değiştiriyor. Isıl durum JSON'a yazılmıyor; ayrım yapılamıyor.
Sonuç: tek bir "iPad maliyeti" sayısı vermek DOĞRU OLMAZ. Hedef karşılaştırması (ADR-0010 Karar 3a) için koşulların cihaz durumuyla (ısıl durum, şarj, soğuk/sıcak) etiketlenmesi ya da çoklu koşuda en kötü durumun raporlanması gerekir; teknik direktör kararı.
Isıl (15 dk) koşu: ilk deneme 144 sn'de `reason=pause` ile kesildi (cihaz uygulamayı durdurdu; Otomatik Kilit "Hiçbir Zaman" değilse bu beklenir, doğrulanmadı) -> GEÇERSİZ. Tüm pencereler "kötü" durumdaydı (p95 16,8).

## 15 dk ısıl koşu (g2, 2026-11-06 16:54-17:09) — GEÇERLİ
Koşu koşulu: release, `--demo --perf-log-thermal` (900 sn), `complete=true`, `reason=complete`, 107 783 kare, `refresh_hz` 120 sabit (`seen`=[120.0], `changed`=false). (İlk iki ısıl deneme geçersizdi: 144 sn'de `pause`; sonra cihaz kilitliydi, başlatma reddedildi. Betik kilit açılınca 16:54'te başlattı.)
| Ölçü | İlk 2 dk | Son 2 dk | Oran | Sınır | Sonuç |
|---|---|---|---|---|---|
| Kare p95 (ms) | 8,65 | 8,78 | 1,015 | ≤ 1,25 | GEÇTİ (`within_limit` true) |
| `busy_ms` p95 (ms) | 7,98 | 8,66 | 1,085 | ≤ 1,25 | GEÇTİ (`busy_within_limit` true) |
Toplam: kare ort 8,35 / p95 8,66 / p99 13,36 / maks 24,16 ms; >33 ms: 1, >100 ms: 1 (açılış karesi, ilk pencerede maks 106,6); `busy_ms` ort 2,15 / p95 8,24; kullanım 0,261; bellek tamponu 186,2 -> 194,5 MB (büyüme 8,2 MB), düğüm 5540 -> 5645, sonlandırma yok.
Notlar [doğrulanmış sayılar, yorum hipotez]: Bu uzun koşu bütünüyle önceki "iyi" durumdaydı (kullanım ~%26; e1 ile aynı), 12:42-13:32 koşularındaki "kötü" durum (kullanım %87-93) görülmedi; bimodallik açıklanmadı. Isıl kısma bu demo bakışında ve bu koşulda (şarjda varsayılır, ölçülmedi) GÖRÜLMEDİ. Yoğun çekirdek bakışı ve etkileşim yükünde ısıl ölçülmedi.
