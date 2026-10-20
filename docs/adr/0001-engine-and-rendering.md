# ADR-0001 · Motor, dil, renderer ve performans bütçesi

- Durum: kabul · Tarih: 2026-10-20 · Karar veren: technical-director (Studio Director, Opus) — foundation F06 teknolojiyi geliştirme liderine bırakır
- Karşıladığı gereksinimler: WLD-01, TEK-01, TEK-03, TEK-04, TEK-05, VIS-01, VIS-04; F06 "özgürlük sınırsız değil" (oyunun ana vaadini gösterebilmeli)

## Bağlam
İhtiyaçlar (foundation): ülke → metropol (~40 km körfez) → ilçe → sokak ölçeğinde **tek** 3D dünya; low-key low-poly, mat, flat-shaded estetik; metroda on binlerce yapı; deterministik, başsız test edilebilir simülasyon; oyuncunun çizdiği yollar ve prosedürel parsel üretimi; dokunmatik öncelikli (platform AÇIK, Q-004). Kısıtlar: 2019 Intel MacBook Pro (Radeon Pro 560X) geliştirme makinesi, yapay zekâ ajanlarının CLI ile süren üretimi, ücretli servis/asset yok, tek geliştirici.

## Karar
1. **Godot 4.7.2 (stable), GDScript**, statik tipli. Sürüm `tools/godot.sh` ile doğrulanır. 4.8 kararlı çıkınca ayrı bir ADR ile değerlendirilir (şu an beta1).
2. **Varsayılan renderer: GL Compatibility.** Hedef estetik ileri ışıklandırma gerektirmez; Intel Mac'te ve iOS Simulator'da çalışan tek renderer budur; eski iPad'lere en geniş uyumu verir. **Mobile renderer** (iOS'ta Metal) hedef cihaz testinde (Q-004) yeniden ölçülür; ölçüm Compatibility'den belirgin iyi çıkarsa bu ADR güncellenir. Forward+ kullanılmaz.
3. **Render mimarisi** (ADR-0002 görünüm katmanı): 1 km chunk başına `MultiMeshInstance3D` (tür başına), örnek başına renk/ölçek; `visibility_range` ile chunk proxy'leri (HLOD). Metro görünümü için ikinci HLOD kademesi (birleştirilmiş bölge kütleleri) gereklidir — ilk ölçeklenme darboğazı budur. Proxy geçişlerinde fade/hysteresis (benchmark'ta sert "pop" görüldü).
4. **Simülasyon dili:** GDScript + Packed*Array sütunları; ağır sistemler `WorkerThreadPool` ile dilim-yaz/sıralı-birleştir deseninde (deterministik olduğu ölçüldü). Kare içinde tick çalıştırılmaz: günlük tick ya iş parçacığında ya da karelere bölünerek yürür. GDExtension (godot-cpp) yalnız profiler kanıtıyla.
5. **Koordinatlar:** metre, tek dünya; görünümde origin rebasing (ADR-0002 §2). Double-precision derleme yok.

## Performans bütçesi (başlangıç; Q-004 cevabı ve cihaz ölçümüyle güncellenir)
| Ölçü | Bütçe | Dayanak |
|---|---|---|
| Kare süresi, geliştirme Mac'i, Compatibility, 1366×1024 | ort. ≤ 8 ms, p95 ≤ 16,6 ms (her preset) | Benchmark: 60k yapıda ort. 4–10 ms, metroda p95 16 ms → sınırda |
| Draw call, metro preset | ≤ 600 (hedef ≤ 400) | 60k'da 398; 327k'da 579 |
| Yapı üçgeni, ilçe LOD | ≲ 600 / orta katlı blok; proxy ≤ 12 | Blender hattı smoke: 5 katlı blok 208 üçgen |
| Simülasyon tick'i (metro ölçeği, 60k parsel + 20k kohort) | ≤ 50 ms / oyun günü, kare dışı | Ölçülen: seri ~70 ms, 4 iş parçacığı ~40 ms |
| Sahne kurulumu | ≤ 5 s metro yüklemesi | 60k'da 1,2 s; 240k'da 10 s → büyük N için artımlı/arka plan kurulumu |
Masaüstü rakamları **iPad performans kanıtı değildir** (TEK-04).

## Alternatifler
| Seçenek | Artı | Neden reddedildi |
|---|---|---|
| Unity 6.x (DOTS) | Olgun ECS, iOS | Intel Mac desteği 6.7 LTS'te biter (6.8+ yok) → geliştirme makinesi çıkmaza girer; ağır editör; GUID'li YAML ajan dostu değil; ECS'de süren değişiklikler |
| Unreal 5.8 | En güçlü büyük dünya araçları | macOS'ta yalnız Apple Silicon; Blueprint/uasset ikili → ajanlarla yönetilemez; iPad'de ağır |
| Bevy 0.20 | Saf Rust deterministik sim | Editör yok, ~4 ayda bir kırıcı sürüm, iOS durumu belirsiz, Intel Mac'te yavaş derleme, arazi/yol ekosistemi yok |
| Web (three.js/Babylon + TypeScript) | En iyi CLI/test deneyimi, iPad Safari'de WebGPU | **Ciddi aday, yedek seçenek.** Reddedilme nedeni: iPad sekme belleği riski, yerel uygulama kalitesi/paketleme belirsizliği, editör/inspector kaybı; Godot'un headless test + capture hattı burada zaten doğrulandı. Godot ölçek bütçesini cihazda tutturamazsa yeniden açılır. |
| Godot Forward+ / Mobile varsayılan | Daha zengin ışık, GPU zaman ölçümü | Estetik gerektirmiyor; Intel Mac'te MoltenVK; iOS Simulator yalnız Compatibility |

## Sonuçlar ve riskler
- Godot'ta yayımlanmış büyük ölçekli şehir kurma örneği bulunamadı; ölçek riski bizim ölçümlerimizle yönetilir (her milestone'da perf kapısı).
- Simülasyon CPU'su render'dan daha sıkı sınır: sistem tasarımı kohort/toplu modelle başlamalı (ADR-0002 §3).
- Yeniden açma tetikleyicileri: hedef cihazda bütçe aşımı; Godot 4.8 kararlı sürümü; Q-004 cevabı (platform); GDScript tick bütçesinin GDExtension olmadan tutmaması.

## Kanıt
- `experiments/scale-bench/RESULTS.md` (+ `results/*.json`, temsilî kareler `experiments/scale-bench/evidence/`, **sanat referansı değildir**). Ölçüm koşulları: Godot 4.7.2 editör ikilisi, Radeon Pro 560X, VSync kapalı, MSAA 2×, makine dış yük altında (load 5–25) → ±%40 gürültü. Üç renderer da bu makinede başladı.
- Determinizm: aynı tohum → aynı SHA-256 (seri ve 4 iş parçacığı), farklı tohum → farklı.
- Asset hattı: `experiments/asset-pipeline-smoke/` (Blender → glTF → Godot, ölçü ve materyal doğrulandı).
- Doğrulanmamış: iPad/Metal davranışı, export şablonuyla performans, render+sim birlikte çalışırken kare süresi, yol/ağaç/UI eklenmiş gerçek sahne.
