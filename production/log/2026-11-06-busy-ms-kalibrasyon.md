# 2026-11-06 · `busy_ms` masaüstü kalibrasyonu (ADR-0010 Karar 3a, TD notu Konu 2 / Sonraki adımlar 1)

Kapsam: yalnız `src/view/perf/perf_logger.gd` (+ `tests/view/perf/perf_logger_busy_test.gd`). Sim, veri, sanat değişmedi; GOLDEN yok. PerfLogger yalnız `--perf-log` ile eklenir; sinyal bağlantısı ve `viewport_set_measure_render_time` yalnız o zaman, oturum bitince çözülür.

## Ne eklendi
- `busy_ms` = karenin ilk `physics_frame`/`process_frame` sinyalinden `frame_post_draw`a; `pre_draw_ms` = kare başı -> `frame_pre_draw`; `render_cpu_ms` = `viewport_get_measured_render_time_cpu(kök)` + `get_frame_setup_time_cpu()` (önceki çizilen kare). Kare k'nın busy'si, k'nın kendi kare süresiyle (`_process`->`_process`) eşlenir. Ölçülemeyen kare -1, özetlere girmez.
- Rapor: üst düzey `busy_ms`/`pre_draw_ms`/`render_cpu_ms`/`utilization`/`busy_over_frame` (tüm oturum); `stable.{busy_ms,pre_draw_ms,render_cpu_ms,utilization}` (kararlı pencere); pencere girdilerinde `busy_ms_p95`, `busy_ms_mean`, `refresh_hz`; `thermal` içinde `busy_first_p95`, `busy_last_p95`, `busy_p95_ratio`, `busy_within_limit`; `refresh_hz_start`, `refresh_hz_seen`, `refresh_hz_changed`. Eski alanlar (`frame_ms`, `stable.frame_ms`, `refresh_hz`, `vsync_mode`, `thermal.p95_ratio`...) aynen.
- `busy_over_frame`: busy'si kare süresini > 0,05 ms aşan kare sayısı (eşleme payı göstergesi; aşağıya bak).

## Koşul
MacBookPro15,1, i7-8850H, Radeon Pro 560X (OpenGL), macOS 24.6, Godot 4.7.2, `gl_compatibility`. **Editör ikilisi = debug yapı** (`debug_build=true`, release değil; ADR-0010 release ister, bu sayılar yalnız yöntemi kalibre eder). Pencereli 1600x900, `playable.tscn -- --demo`, `--perf-log-frames=3000 --perf-log-stable=10` (kararlı evre ilk 10 sn kare süresinden sonra; sahne kurulumu ilk kare 4 sn, ölçüm dışı), `nice -n 19`, tek Godot kilidi. Başka ajanlar makinede çalışıyordu (1 dk yük 3,0-5,9): mutlak ms'ler gürültülü, oranlar karşılaştırılır. Ham JSON: `artifacts/perf/cal/*.json` (git'te yok).

| Koşu | VSync modu | max_fps | kare ort / p95 | busy ort / p95 | pre_draw ort | render_cpu ort | kullanım | busy>kare | kararlı kare |
|---|---|---|---|---|---|---|---|---|---|
| v1 | 1 (açık) | 0 | 6,03 / 8,87 | 5,95 / 8,63 | 0,70 | 4,37 | 0,986 | 236 | 2101 |
| n1 | 0 (kapalı) | 0 | 6,04 / 8,91 | 5,95 / 8,69 | 0,71 | 4,39 | 0,986 | 251 | 2122 |
| v2 | 1 | 0 | 6,03 / 8,93 | 5,95 / 8,72 | 0,71 | 4,35 | 0,986 | 239 | 2084 |
| n2 | 0 | 0 | 6,03 / 8,83 | 5,95 / 8,63 | 0,71 | 4,36 | 0,986 | 237 | 2129 |
| m60 | 1 | 60 (`--max-fps 60`) | 16,66 / 21,88 | 5,30 / 11,47 | 1,41 | 3,45 | 0,318 | 117 | 2664 |
| fs | 1, tam ekran | 0 | 8,41 / 13,02 | 8,32 / 12,82 | 0,86 | 3,20 | 0,989 | 707 | 2355 |

`refresh_hz_changed=false` her koşuda; ama `refresh_hz` **0,0** okundu (bu masaüstü oturumunda `screen_get_refresh_rate` yenileme hızı vermiyor).

## Kabul ölçütleri (TD notu)
1. **V-Sync kapalı: kararlı busy ort, kare süresi ort'unun ±%10'u içinde. GEÇTİ.** n1: 5,95 / 6,04 (-1,5 %), n2: 5,95 / 6,03 (-1,3 %). (VSync "açık" v1/v2'de de -1,3 %.)
2. **V-Sync açık: busy ort, kapalı değerin ±%10'u içinde. Sayısal olarak GEÇTİ (5,95 / 5,95, fark %0), AMA KANITLAMAZ.** Bu Mac'te pencereli `vsync_mode=1` iken bile kare beklemedi: 166 kare/sn (6,03 ms), `refresh_hz` 0. v-koşuları n-koşularından ayırt edilemez, yani sunum beklemesi hiç oluşmadı; "sunum beklemesi dışarıda kalıyor" iddiası bu veriyle desteklenmez ve çürütülmez. Tam ekran (fs) denemesi de VSync'e kilitlenmedi (kare ort 8,41 ms, p50 9,02; 60 Hz'de 16,7 beklenirdi).
3. **Yan deney (kare tavanı, VSync değil):** `--max-fps 60` ile kare 16,66 ms'e kilitlendi, busy 5,30 kaldı (kare süresine değil işe bağlı, kullanım 0,318). Yani ana döngüdeki tavan beklemesi busy'ye girmiyor; bu doğrulandı. Kapalı değere (5,95) göre -%10,9: ±%10'un hemen dışında. Hipotez (doğrulanmadı): tempolu karede GPU karenin başında boşta olduğundan GL çağrıları daha az bloklanıyor (`render_cpu` 4,37 -> 3,45); yani GL'de busy saf CPU işi değil, sürücü geri basıncını (GPU'yu beklemeyi) içeriyor.

Sonuç: ölçüt 1 tutuyor; ölçüt 2 bu makinede **sınanamadı** (VSync bağlayıcı değil). Ölçüt 2'nin asıl sorusu (sunum `swap_buffers` bloklar mı, `frame_post_draw` ondan önce mi sonra mı) cihazda (iPad) ya da gerçekten VSync'e kilitlenen bir ekranda yeniden sorulmalı.

## Sinyal sırası
- Deneyle ölçülemedi (VSync bağlayıcı olmadığı için `swap_buffers` hiç bloklamadı).
- Kaynaktan [4.7.2-stable, `rendering_server_default.cpp` ve `rasterizer_gles3.cpp`, okuma web özeti üzerinden, kendim satır satır doğrulamadım]: `frame_pre_draw` `RenderingServer::draw()` başında, `_draw()` (begin_frame, draw_viewports, end_frame) sonrası `frame_post_draw` `_run_post_draw_steps()` sonunda; GLES3'te `swap_buffers` `gl_end_frame` içinde. Bu, `frame_post_draw`un takas ÇAĞRISINDAN SONRA yayıldığını gösterir: takas bloklarsa busy VSync beklemesini içerir (TD'nin "güvenli yönde hata" riski). iOS Compatibility'de `presentRenderbuffer` davranışı hâlâ doğrulanmadı.

## Ek bulgular
- **Döküm yedek ölçü olarak tutarlı:** `pre_draw` + `render_cpu` = 0,70+4,37 = 5,07 ms, busy 5,95'in %85'i (kalan ~0,9 ms çizim sonrası/takas; yedek ölçü busy'yi ~%15 düşük verir).
- **Bu demoda iş çizim ağırlıklı:** kare başı->`frame_pre_draw` 0,7 ms, render CPU 4,4 ms. Sim/betik payı küçük.
- **`busy_over_frame` ~%11 (236-251/2100):** fizik adımları karenin başında (kare başı sinyali `physics_frame`), kare süresi `_process`'ten ölçüldüğünden eşleme kaymasından bazı karelerde busy > kare görünür. Toplamda (Σbusy/Σkare = 0,986) etkisi yok. Hipotez, ayrı doğrulanmadı.
- **fs koşusunda** busy ~ kare (0,989): GPU'ya bağlı kare, GL çağrılarındaki bekleme busy'ye giriyor. TD'nin "GPU'ya bağlı darboğaz yalnız GL bekleme kadar görünür" riskiyle uyumlu.

## Doğrulanmamış
Release yapı; VSync'e gerçekten kilitlenen bir ekran; iPad (CADisplayLink, `presentRenderbuffer`); `viewport_set_measure_render_time` açıkken ölçüm maliyeti (ayrıca karşılaştırılmadı); `refresh_hz` 0,0 okuması (bu oturumda).
