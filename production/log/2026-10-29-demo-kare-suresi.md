# Demo (`--demo`) kare süresi: 22-36 ms ve 100+ ms sıçramalar · 2026-10-29 (QA, kod değişmedi)

Ham veri + probe betikleri: `artifacts/perf/20261029-demo-frames-run1.json`, `...-run2.json`, `20261029-demo-probes/` (git'te yok). Makine: kullanıcınınki (MacBookPro15,1, i7-8850H, AMD Radeon Pro 560X, Compatibility, Godot 4.7.2, 1600x900).

## `--demo` ne yapıyor (koddan)
- Kamera `start_view`: `home_district` boş -> **core, 18 km, `metro` bandı** (ENV doğrulandı). Oto-gezinti YOK; kamerayı kullanıcı sürer.
- Hız: `set_speed(3)` = fastest = **16 tick/sn** (`core_config.json`; tick = 1 sim günü). Normal oyun 1 tick/sn.
- Tek seferlik kancalar: kare 10 demo imar önerisi; **kare 60 `_smoke_save_load()`** (export+import+tam projector eşitleme).
- Her tick'li karede `hud.poll()` (anlık görüntü + olay şeridi); her karede `status_text()`.
- `PLAYABLE_SMOKE` `delta` kullanır ve Godot delta'yı ~150 ms'de kırpıyor (3 ayrı koşuda tam 150.0): ekrandaki "max" büyük takılmaları eksik gösterir.

## Ölçüm (pencereli, VSync KAPALI, 120 ısınma + 300 kare, iki koşu: sıra a / b; yük 1dk 4,5-7,0)
| Durum (hız 3 = demo, aksi yazılı) | ort ms (k1/k2) | p95 | max | tick'li ort | tick'siz ort / p95 | draw | üçgen |
|---|---|---|---|---|---|---|---|
| başlangıç core 18 km, sim duraklı | 5,5 / 5,6 | 6,4 / 7,9 | 7,1 / 9,0 | - | 5,5 / 6,4 | 331 | 0,43 M |
| core 18 km, sim 1x | 5,5 / 5,6 | 6,6 / 7,9 | 12 | 12,0 | 5,4 / 6,6 | 330 | 0,43 M |
| core 18 km, sim 3x (demo) | 5,7 / 6,2 | 9,3 / 9,6 | 35 / 43 | 10,1 / 11,9 | 5,3 / 6,9 | 330 | 0,43 M |
| district ~3 km, 3x | 6,1 / 5,9 | 9,9 / 9,6 | 35 / 50 | 11,3 / 11,8 | 5,5 / 7,6 | 214 | 0,41-0,50 M |
| neighborhood 500 m, 3x | 13,0 / 11,0 | 14,8 / 14,0 | 50 / 52 | 14,3 / 12,5 | 12,6 / 14,4 | 362-388 | 2,2-2,9 M |
| street 60 m, 3x | 12,3 / 12,7 | 13,7 / 15,6 | 37 / 51 | 13,0 / 15,7 | 12,2 / 13,4 | 353-362 | 2,9 M |
| street 60 m, sim duraklı | 12,2 / 12,5 | 13,8 / 16,4 | 16 / 17 | - | 12,2 / 13,8 | 358 | 2,9 M |
| gezinti (kamera sürekli) street / nbhd, 3x | 10,6-10,9 / 10,7-10,8 | 13,9-15,5 / 18,3-18,4 | 38-56 | 12,8-16,0 | 9,6-10,3 / p95 14,6-15,5 | 351-365 | 1,8-2,2 M |
Üç kamera bandı da D-007 ortalamasını (<=14) ve tick'siz p95'i (<=20) geçiyor. Tick'li karelerin p95'i 18-39 ms.

## Kullanıcının 22-36 ms'si: yeniden üretilen etken (aynı komut, `--quit-after`, VSync varsayılan AÇIK)
| Koşu | ort ms |
|---|---|
| `--demo` yerleşik ekran (screen 0), core başlangıç | 8,5-9,7 (kare 120 penceresi 14,8; max 150 = kırpma) |
| aynı, `--screen 1` (harici LEN 4K, macOS "30,00 Hz") | **18,0-19,0** (ilk pencere 23,9) |
| aynı süreçte ekran/VSync çevrimi, core: s0 kapalı/açık · s1 açık/kapalı | 5,6 / 9,0 · **17,3** / 6,2 |
| aynı, street 60 m: s0 açık · s1 açık/kapalı | 13,1 · **20,1 (p95 34)** / 12,8 |
`perf_probe`/`perf.sh` VSync'i KAPALI zorlar; oyuncu proje varsayılanı (VSync açık) ile oynar. Bu makinede harici ekran 30 Hz ve VSync açıkken ek 11-12 ms (core) / 7 ms (street) geliyor; street + harici + VSync ort 20, p95 34 ms: 22-36 aralığına yakın.

## 100+ ms sıçramalar (ölçülen kaynaklar)
| Kaynak | Süre | Kanıt |
|---|---|---|
| Kare 60 `_smoke_save_load` (`--demo` kancası; `load_resync` tam eşitleme 1,2-1,27 sn) | **1,7 sn** tek sefer (ekranda 150'ye kırpılı) | run1 startup kare 60: 1706 ms; `PLAYABLE_LOAD_RESYNC ms=1203,8` |
| Kare 1: ilk tick `economy_system.on_daily` | 121 ms (+ ilk kare 4,5 sn yükleme) | sim_drive_max 120,7/122,2; `stage_headless` max 120,9 |
| Bir bandın İLK ziyareti (core -> street 60 m, daha önce hiç görülmemiş) | **403 ms**; 2. ziyaret 22 ms; başka sokak 32-46 ms | `jump_probe`; `PLAYABLE_SMOKE` kare 1800'de 149,1 (kırpılı) |
| Ay sınırı tick'i (her 30 gün = 16 tick/sn'de ~2 sn'de bir) `economy_system.on_monthly` | 20,5 ort / 23,2 max | `stage_headless` 24 ay; `tick_headless` mod-30 = 24 ms |
| `hud.poll()` en kötü tick | 21-25 ms (ort 2,8) | `tick_cost.hud_poll_max_ms` 21,5/24,7 |
| `politics_system.on_daily` en kötü | 12,5 ms (ort 0,64) | `stage_headless` |
Sürekli rejimde (ilk 2 sn sonrası) bu probelarda tek kare max 35-56 ms; 100+ ms'lik sürekli tekrar gören kaynak ölçülmedi. Sim tick maliyeti tikler boyunca büyümüyor (headless 1500 tick: ilk 100 ort 4,6 ms, son 100 ort 4,0 ms; HUD 1,6 -> 2,6 ms).

## Doğrulanmış / varsayılan / test edilmemiş
- **Doğrulanmış:** bu makinede, yerleşik ekranda, VSync kapalı: demo kare süresi 5,5-13 ms; kullanıcı komutu birebir yerleşik ekranda 8,5-9,7 ms, `--screen 1`'de 18-19 ms. Harici ekran (30 Hz) + VSync açık kare süresini 2-3 kat artırıyor. Delta kırpması (150 ms). Kare 60 donması 1,7 sn, kare 1 tick'i 121 ms, ilk band ziyareti 403 ms, ay tick'i ~23 ms.
- **Varsayılan (kanıtsız):** kullanıcının penceresi o sırada harici 30 Hz ekrandaydı (sormadım, log'unda ekran yok); 22-36'nın kalan farkı (benim 18-20'ime göre) yük/Düşük Güç Modu/uzun oturumda sim büyümesinden. `pmset` `lowpowermode 1` bu makinede AÇIK (T-070 ölçümü bu durumda mıydı bilinmiyor). Hitch'lerdeki payların HUD/sim dağılımı tek tek tick için; kare başına süre kanıtı yalnız `sim_drive`/`hud_poll` sayaçları.
- **Test edilmedi:** gerçek elle gezinti (kullanıcı hızıyla), uzun (>5 dk) oturum, Intel iGPU'ya düşme, yerleşik ekranın yenileme hızı (API 0 döndürdü), harici ekran 60 Hz, `TIME_PROCESS` sayacı (güvenilmez çıktı, kullanılmadı). Zoom testi geçersiz (mesafe değişmedi). `J_nbhd500_screen0` 7,1 ms açıklanamayan sapma (500 m kamera uygulanmamış olabilir) sonuçtan çıkarıldı.

## En olası nedenler
1. **VSync açık + (varsayımsal) 30 Hz harici ekran**: tek başına 2-3 kat; perf kapıları VSync kapalı ölçüyor, bu yüzden kullanıcının gördüğüyle kapı arasında boşluk var.
2. **`--demo`'nun kare-60 kayıt/yükleme kancası (1,7 sn) + kare-1 tick'i + ilk band ziyaretinde 400 ms**: "100+ ms" sıçramaların açıklanmış kısmı; ekran sayacı 150'ye kırptığı için küçük görünüyor.
3. **Tick işi (16 tick/sn)**: ort +3 ms, ay tick'i ~23 ms + HUD ~3-25 ms tick'li karelerde; ince kare süresini değil kuyruğu (p95 18-39) etkiler.

## Düzeltme adayları (uygulanmadı; maliyet / etki)
| Aday | Maliyet | Etki |
|---|---|---|
| `perf_probe`/smoke'a VSync-AÇIK + hedef ekran bilgisi ekle; `PLAYABLE_SMOKE`ta wall-clock süre kullan, ekran/Hz yazdır | düşük | ölçüm gerçeği (tanı) |
| `--demo` kare-60 smoke'u varsayılan kapat (`--smoke-save-load` ile aç); başsız duman testi bayrakla kalsın | çok düşük | 1,7 sn donma gider |
| Yüklemede ilk tick'i ve street-LOD materyal/MMI ısınmasını gizli kamera ile yap (yükleme ekranı arkasında) | orta | 121 ms + 400 ms ilk-ziyaret sıçraması |
| `economy.on_monthly` (23 ms) işini birkaç tick'e böl; `hud.poll` HUD'u tick başına değil <=10 Hz yenile | orta (sim kuralı: hash değişmemeli) | tick'li kare p95 18-39 -> ~15 |
| Ayarlara VSync/kare sınırı seçeneği; harici ekran için kullanıcıya not | düşük | kullanıcı donanımına uyum |

Kullanıcıya sorulacak tek şey: demo penceresi hangi ekranda (yerleşik mi, harici 4K mı)? Harici ekran 60 Hz'e alınırsa/yerleşike taşınırsa ortalama beklenen ~9 ms.

## Sonuç: ısınma düzeltmesi (2026-10-30)
- `ViewWarmup` (yeni): yükleme sırasında opak örtü altında kamera dar bantları gezer, sonra başlangıç pozuna birebir döner. İlk core->street 60 m çizim aşaması 850-925 ms -> 31-46 ms (aynı makine/yük). Yükleme +1,7-1,9 sn (yüklü makinede; hedef <=1,5 sn, hafif aşım).
- Sim'e dokunulmadı (determinizm); ilk tick (economy.on_daily 121 ms) ayrı oyuncu-görünür takılma değil, ısıtılmadı.
- Demo komutu: `--demo --no-smoke-save-load` (kare-60 kayıt/yükleme smoke'u 1,7 sn dondurur).
- Doğrulama: bağımsız `verify quick` PASS (1864 test, 0 hata). Ölçüm olmayan: sessiz makinede ısınma süresi, soğuk bitki önbelleği, iPad, harici 30 Hz ekran + VSync (ısınma bunu çözmez).
