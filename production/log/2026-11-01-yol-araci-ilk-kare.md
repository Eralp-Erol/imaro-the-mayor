# Yol aracı ilk tık / ilk hover kare sıçraması · ölçüm ve düzeltme (2026-11-01)

Hedef: `click_a` ~48 ms ve ilk hover ~68 ms (pencereli). Donanım: MacBookPro15,1 (i7-8850H, Radeon Pro 560X, OpenGL
Compatibility). **iPad sayısı DEĞİL.** Makine ölçüm sırasında çok gürültülüydü (`CPU_Speed_Limit` 23-60, yük ortalaması
14-257; diğer ajanların başsız koşuları). Bu yüzden her karede probe kalibrasyonu (`cal`, nominal 0,35 ms) alındı ve
`norm = ms / (cal / 0,35)` verildi.

## Kök neden (ölçüldü)

Sıçrama yol aracında DEĞİL; **bitki leke parçalarının (`VegetationView._poll_blobs` -> `_install_blob`) kurulumunda**.
Kamera yola odaklanınca ~20 leke parçası arka thread'de üretilir; hepsi birlikte bitince `_poll_blobs` bitenlerin TÜMÜNÜ aynı
karede kuruyordu (`ArrayMesh.add_surface_from_arrays` ~0,2 ms / 1000 köşe; en büyük parça ~125 bin köşe = 20-30 ms yük altında).
Geçici zamanlayıcılarla (geri alındı) yakalanan kareler:

| kare | `track_camera` | ayrıntı |
|---|---|---|
| `click_a#2` | 111,7 ms (`blob_poll_flush`) | 13 biten parça tek karede |
| `hover#0/#1` | 14,3 / 41,6 ms | kalan parçalar |
| tek parça kurulumu | `add_surface` 0,2 ms/1000 köşe | `node`/`close`/`add_child` toplamı < 0,2 ms |

Sıçramanın "ilk tık / ilk hover"a denk gelmesi tesadüf değil: probe odaklamadan 20 kare sonra tıklıyor, parça işçileri tam o sırada
bitiyor; gerçek oyunda da kamera hareketinden sonraki ilk saniyelerde aynı patlama olur (ilk-kullanım değil, bekleyen iş birikimi).
Aynı patlama koşudan koşuya farklı kareye düştü (bir koşuda `tool_open#5`, bir başkasında `click_a#2`).

Yol aracının kendi payı (ilk-kullanım maliyeti DEĞİL, sürekli adım maliyeti): `tap_at` ~12-16 ms (panel yeniden çizimi 8-10 ms +
önizleme ağı 3 ms), imleç adımı `RoadDrawTool._revalidate` (sim kuru koşusu, kamulaştırma teklifi) 12-17 ms. Bunlar zaten
`HOVER_COST_FACTOR` ile seyreltiliyor; sim koduna dokunulmadı (GOLDEN korunur).

## Düzeltme

1. `VegetationView._poll_blobs`: kurulum **kare dilimli** (`blob_install_budget_ms`, varsayılan 2 ms, karede en az 1 parça).
   Biten ama kurulmamış parça `_blob_jobs`ta kalır (maske yazımı için "çalışıyor" sayılmaz); eskimiş/gereksiz parçalar bütçe
   yemeden atılır; `settle()` (`_unlimited`) eski davranışı korur. Ayar `data/view/vegetation_view.json` -> `blob.install_budget_ms`.
2. `RoadDrawController`: imleç önizlemesinin karesinde panel yeniden çizimi yapılmaz, bir sonraki kareye kayar
   (`_hover_frame`); ilk hover karesinde sim kuru koşusu + önizleme ağı + panel düğüm kurulumu tek karede biniyordu.
3. Ölçüm: `tools/godot/expropriation_game_probe.gd` kare başına kalibrasyon (`cal`, `norm`), `--mark`, `--settle-veg`,
   `--veg-install-ms=N` (A/B; çok büyük değer = eski bütçesiz davranış).

Dokunulmayanlar: `playable.gd` (1000), `world_network.gd`, `economy_system.gd`, sim kodu, `blocs.json`, `design/foundation`.

## Önce / sonra (pencereli, `expropriation_game_probe.gd --ui --trace=6`, aşama başına en yüksek adım: ham ms / norm ms)

old1-3 = ÖNCE (bütçesiz leke kurulumu, `--veg-install-ms=1000000`; o koşularda panel erteleme kodu da yoktu = eski davranış).
new1-3 = yalnız leke bütçesi (varsayılan 2 ms). fin4-6 = leke bütçesi + panel erteleme (son kod). old/new koşuları sıralı
serpiştirildi (old1,new1,old2,new2,old3,new3); fin4-6 sonradan, ayrı seride koştu.

| koşu | click_a ham / norm | hover ham / norm | cal medyan |
|---|---|---|---|
| old1 | 57 / 19 | 67 / 43 | 0,74 |
| old2 | 65 / 21 | 94 / 66 | 0,89 |
| old3 | 98 / 74 | 41 / 31 | 0,68 |
| new1 | 24 / 10 | 39 / 32 | 0,44 |
| new2 | 23 / 9 | 46 / 35 | 0,56 |
| new3 | 22 / 7 | 29 / 13 | 0,78 |
| fin4 | 30 / 20 | 51 / 26 | 0,91 |
| fin5 | 17 / 6 | 23 / 9 | 0,85 |
| fin6 | 21 / 10 | 36 / 25 | 0,64 |

Medyan (3 koşu, ham ms): click_a 65 -> 23 (yalnız leke) -> 21 (son kod); ilk hover/hover aşaması 67 -> 39 -> 36. Tek karede en büyük leke kurulumu:
~119 ms (eski, 17 parça) -> tek parça (yük altında 20-30 ms; kuru makinede ~9 ms tahmini, ölçülmedi).
Aynı koşuda en kötü karenin tavanı artık en büyük TEK parçanın kurulumu; daha aşağısı parçayı birden çok yüzeye bölmeyi
(+draw call) ya da iş parçacığında mesh üretmeyi gerektirir (aşağıya bkz.).

## Doğrulandı / varsayıldı / test edilmedi

**Doğrulandı:** kök neden (zamanlayıcı çıktısı: `blob_poll_flush` 111,7 ms, 13 iş); önce/sonra tablo (9 pencereli koşu);
GdUnit: `tests/view/vegetation` (10 vaka dahil yeni `test_blob_installs_are_time_sliced_and_converge_to_the_unbudgeted_result`;
kırmızı-yeşil doğrulandı: bütçe 1e6 ms iken test düşer), `tests/game/road_draw_flow_test.gd` (18 vaka, yeni
`test_hover_defers_the_panel_rebuild_to_the_next_frame`), `road_hover_interval_test.gd` — 81 vaka, 0 hata (başsız);
gdlint temiz (6 dosya).
**Varsayıldı:** kullanıcı makinesinde de aynı birikim var (kamera hareketi sonrası ilk saniyeler); tek parça kurulumunun
kuru makinede ~9 ms olması (köşe sayısından ölçekleme).
**Test edilmedi:** iPad; çok binalı şehir; sürekli kamera hareketinde parça akışı (yalnız bir odaklama + tık dizisi);
mesh üretiminin iş parçacığına taşınması (`RenderingServer` iş parçacığı modeli bu projede doğrulanmadı, denenmedi);
büyük parçaları çok yüzeye bölmek (draw call artar, ADR-0001 bütçesiyle uyumu ölçülmedi). Önce/sonra karşılaştırması
gürültülü makinede n=3; yön tutarlı ama mutlak ms'ler kesin değil.
