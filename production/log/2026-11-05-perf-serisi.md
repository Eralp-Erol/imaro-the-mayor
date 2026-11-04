# 2026-11-05 · Sakin makinede perf serisi (M2-CLOSURE madde 4)

Yalnız SAYI toplama. Bütçe hedefi yok (teknik direktör). `src/` değişmedi. Ham JSON'lar `artifacts/perf/` (git'te yok).

## Koşul
- MacBookPro15,1, Intel i7-8850H (12 mantıksal çekirdek), 32 GB, Radeon Pro 560X (+ Intel UHD 630), macOS Darwin 24.6.
- Godot 4.7.2, Compatibility (`gl_compatibility`), pencereli 1600x900, VSync KAPALI (perf_probe zorlar), nice YOK, ölçüm sırasında başka ağır iş yok; Godot yalnız `/tmp/imaro-godot.lock` ile.
- HEAD `df158a7` (main'e ff). İlk `--import` ayrıca koşuldu (ölçüme dahil değil).
- Her koşu öncesi/sonrası `uptime` (1 dk yük): hepsi 2,3-5,0, eşik 8 hiç aşılmadı, hiçbir koşu "gürültü" işaretlenmedi.

| Koşu | Yük önce -> sonra | Not |
|---|---|---|
| demo-a1 | 4,77 -> 3,93 | perf.sh, `--demo`, 6000 kare |
| demo-a2 | 3,51 -> 3,95 | aynı |
| demo-a3 | 3,58 -> 3,23 | aynı |
| demo-a4 | 3,23 -> 3,78 | aynı |
| road-r1 | 2,31 -> 2,98 | yol-gönderimi probu (`--demo --engine`, gün 835) |
| road-r2 | 2,88 -> 4,26 | aynı |
| road-r3 | 4,26 -> 5,03 | aynı (yük koşu sırasında yükseldi; yol süresi bu koşuda en yüksek) |
| b-nosmoke / b-nowarm / b-noveg | 3,87->4,23 / 4,23->3,75 / 3,31->3,77 | 1500 kare A/B (neden arama) |

## A. `tools/perf.sh` + `playable.tscn --demo` (warmup 0, 6000 kare ~43 sn; `--frames-out` ham seri)
Sahne kurulumu (instantiate+add_child, ölçüm DIŞI) **31,4 / 32,2 / 32,5 / 35,4 sn** (post_terrain ~16,9 sn, arazi 2,3 sn, dünya 1,3 sn).

| Kesit (ms) | a1 | a2 | a3 | a4 |
|---|---|---|---|---|
| TÜM ort / p95 / p99 / en kötü | 7,13 / 8,81 / 11,13 / 3912,87 | 7,14 / 8,85 / 11,21 / 3909,90 | 7,21 / 8,81 / 11,12 / 4121,21 | 7,14 / 8,86 / 11,35 / 3926,25 |
| İlk 30 sn (ölçüm başından) ort / p95 / p99 / maks | 7,72 / 8,81 / 11,06 / 3912,87 | 7,73 / 8,85 / 11,01 / 3909,90 | 7,88 / 8,83 / 10,88 / 4121,21 | 7,75 / 8,90 / 11,33 / 3926,25 |
| 30 sn sonrası ort / p95 / p99 / maks | 6,04 / 8,81 / 11,59 / 19,63 | 6,05 / 8,86 / 11,40 / 18,27 | 6,04 / 8,78 / 11,55 / 18,83 | 6,03 / 8,73 / 11,42 / 18,02 |
| >50 ms kare sayısı (hepsi ilk 7 sn) | 6 | 6 | 6 | 6 |

Tekrarlanan tekil sıçramalar (kare no: ms; 4/4 koşuda aynı kareler): kare 1: **3910-4121**; kare 6: **699-751**; kare 60: **1645-1821**; kare 10: 96-98; kare 2/5: 55-61.
Tick'li kare (146 adet) ort ~11,2-11,4, p95 13,8-14,3, maks 55-60; tick'siz ort 7,03-7,11.
Çizim (steady, 4 koşuda aynı): draw call ort **315,3**, maks **343**; üçgen ort **430.937**, maks **1.001.253** (tek kare tepe); obje maks 1491. GPU süresi Compatibility'de ölçülemedi (0).
Bellek (Godot monitörü, MB): static 532,1; video 353-361; doku 155,2; buffer 198-206; düğüm 5624. İşlem RSS (ps, 2 sn örnek): tepe **1463-1479 MB**.

## B. Yol gönderimi (gerçek `--demo`, motor delta, en hızlı hız, gün 835'te tek yol; ~10-11k kare, gün 1100'e kadar)
Senaryo/yol adayı 2026-11-03 ile aynı betik (`tmp/perf-seri/road_series_probe.gd`, git'te yok; demo_frame_probe'a dayanır, kare serisi eklendi).

| | r1 | r2 | r3 |
|---|---|---|---|
| Komut gönderimi (ms) | 0,93 | 1,11 | 1,35 |
| Yerel yenileme "road_sync" (ms, 1 chunk) | 141,4 | 188,2 | 248,8 |
| Yol penceresinde en kötü TEK kare (ms) / gönderimden kaç kare sonra | **129,6** / 33 | **171,5** / 39 | **207,1** / 36 |
| Ardışık ağır kareler (>50 ms) | 129,6; 71,2; 57,3; 54,3 | 171,5; 87,3; 69,6; 69,3; 63,9 | 207,1; 100,0; 83,3; 83,5; 77,1 |
| 63 karelik yol penceresi toplamı (ms) | 730 | 881 | 1114 |
| TÜM koşu kare ort / p95 / p99 / maks | 6,11 / 10,21 / 12,32 / 129,57 | 6,33 / 11,07 / 15,02 / 171,51 | 6,85 / 12,60 / 18,61 / 207,09 |
| Tick'siz kare ort / p95 / p99 | 5,62 / 8,36 / 8,96 | 5,71 / 8,35 / 9,25 | 6,05 / 8,68 / 10,97 |
| >33 ms / >16,6 ms kare sayısı | 5 / 13 | 5 / 49 | 6 / 217 |
| Bellek static MB / draw / üçgen (son kare) | 582,8 / 325 / 430.651 | 581,7 / 325 / 430.651 | 579,4 / 325 / 430.651 |

Yol sıçraması her koşuda yalnız yolun yenilendiği pencerede; **>= 1 sn'lik tek kare YOK** (en kötü 207 ms). 2026-11-03 değeri (117,92 ms / 130,7 ms) bu aralığın altında kalıyor; r3'te yük 4,3->5,0 yükselirken sıçrama büyüdü (yük ilişkisi hipotez: 3 örnek).

## C. Neden arama (kare 60 / 1 / 6) -> `production/bugs/B-028.md`
- Kare 60 (~1,6-1,8 sn) = `--demo` kayıt/yükleme smoke kancası: `--no-smoke-save-load` ile YOK (A/B kanıtlı).
- Kare 6 (~0,7 sn) = ViewWarmup başlangıcı (`--no-view-warmup` ile YOK).
- Kare 1 (~3-4 sn): üç kapatmayla da sürüyor (bitki yoksa 3,06 sn); nedeni BULUNAMADI (hipotez: ilk çizim gölgelendirici/doku).

## Doğrulanmadı / sınırlar
iPad ve fiziksel cihaz ölçülmedi. Hareketli kamera / oyuncu etkileşimi yok (otomatik demo, sabit `core` kamera). GPU süresi ölçülemedi. Görsel kareler alınmadı. Sahne kurulum 31-35 sn'nin oyuncunun gördüğü açılış süresi olup olmadığı (pencere/örtü) bu turda GÖRÜLMEDİ. Yük 2,3-5,0 arasında değişti; "tam sakin" (yük<2) koşu yok.
