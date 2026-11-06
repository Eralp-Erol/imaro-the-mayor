# iPad Pro 12,9" (6. nesil) ölçüm kaydı — T-076 (TASLAK, seri sürüyor)

Durum: **KISMİ.** VSync'li üç demo koşusu ölçüldü (a1, a2, a3). VSync'siz seri (b1, b2), ısınma, etkileşim ve soğuk açılış HENÜZ YOK. Hedefler `docs/adr/ADR-0010-kare-butcesi-hedefleri-m2.md` Karar 3 (ön hedef).

## Koşul (doğrulanmış, JSON alanlarından)
iPad14,5, iPadOS 26.5.2, release dışa aktarma (`debug_build` false; ham JSON `artifacts/perf/ipad-a*/`, git dışı), Godot Compatibility (`gl_compatibility`, Apple M2 GPU), 120 Hz (`refresh_hz`), `vsync_mode`=1 (VSync AÇIK), `--demo`, 6000 kare, ~50 sn. Kararlı pencere 30. sn'den sonra. Pencere 2732x2048.
Yapı: HEAD 7b155b9 sonrası (B-042 dahil); a1/a3 daha erken seriden, a2 bu gecenin yeniden başlatmasından (a3 farklı zamanda koştu: 22:09 UTC, a2: 00:00 UTC, a1: 21:40 UTC).
**Geçersiz:** a4 (`reason=pause`, 1121 kare, 11 sn: oyun kesildi), sayılmaz.

## Sonuçlar (kararlı pencere, ms)
| Koşu | ort | p50 | p95 | p99 | maks | >33 ms | >100 ms | çizim ort | üçgen ort |
|---|---|---|---|---|---|---|---|---|---|
| a1 | 8,33 | 8,34 | 8,62 | 14,18 | 17,39 | 1 | 0 | 302 | 398 288 |
| a2 | 8,34 | 8,34 | 8,64 | 14,39 | 19,11 | 2 | 1 | 302 | 398 290 |
| a3 | 8,33 | 8,34 | 8,64 | 13,91 | 18,84 | 1 | 1 | 302 | 398 291 |

>100 ms sayısı (a2, a3: 1) ilk kareyle uyumlu: ilk kare süresi a2 106,5 ms, a3 102,4 ms (`startup.first_frames_ms`); kararlı pencere değil, açılış karesi. [Bu eşleşme sayıdan çıkarım, tek tek kare doğrulaması yapılmadı.]

## ADR-0010 ön hedefleriyle karşılaştırma (yalnız demo bakışı)
| Ölçü | Ön hedef | Ölçülen (a1-a3) | Durum |
|---|---|---|---|
| Kararlı ort | ≤ 8 ms (tavan 14) | 8,33-8,34 | VSync'li 120 Hz'de kare süresi 8,33 ms'ye kilitli: ort ≤ 8 bu modda **ölçülemez**; gerçek maliyet için VSync'siz seri (b) gerekir. Tavanın (14) içinde. |
| p95 | ≤ 16,6 (tavan 20) | 8,62-8,64 | geçti (demo) |
| p99 | ≤ 25 (tavan 33,3) | 13,9-14,4 | geçti (demo) |
| En kötü etkileşim karesi | ≤ 50 (tavan 100) | demo maks 17,4-19,1 | **etkileşim ölçülmedi** (yol onayı oturumu sahip bekliyor) |
| Draw call / üçgen | ≤ 400 / ≤ 900k | 302 / 398k | geçti (demo bakışı; yoğun çekirdek 2,87M bakışı iPad'de ölçülmedi) |
| Bellek | ≤ ~1,5 GB, sonlandırma yok | tampon 194-200 MB, video 397 MB, fiziksel 7518 MB / boş 2184 MB (a1); sonlandırma yok | geçti (50 sn'lik koşu; uzun koşu yok) |
| Açılış ilk kare | örtüsüz blok ≤ 1 sn | ilk kare 85-107 ms; ilk işlem karesi ~10,5 sn | ilk kare tek blok olarak geçti; "ilk etkileşimli kare ≤ 30 sn" için soğuk açılış kronometresi gerekir (sahip) |
| Isıl | son 2 dk p95 ≤ ilk 2 dk × 1,25 | YOK | ısınma koşusu bekliyor |

## Doğrulanmadı / eksik
- VSync'siz seri (b1, b2): gerçek kare maliyeti.
- 15 dk ısınma koşusu.
- Etkileşim (yol onayı, pan/pinch) en kötü kare.
- Soğuk açılış kronometre, Düşük Güç Modu / şarj durumu / pil kaydı (koşullar sahipten istenecek; JSON'da yok).
- Yoğun çekirdek bakışı üçgen sayısı.
