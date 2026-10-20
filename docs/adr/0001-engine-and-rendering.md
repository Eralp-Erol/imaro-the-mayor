# ADR-0001 · Motor, dil, renderer ve performans bütçesi

- Durum: kabul · Tarih: 2026-10-20 · Karar veren: technical-director (Studio Director, Opus) — foundation F06 teknolojiyi geliştirme liderine bırakır
- Güncelleme: platform hedefleri, renderer profilleri ve performans bütçesinin okunuşu ADR-0004 (D-003) ile güncellendi.
- Karşıladığı gereksinimler: WLD-01, TEK-01, TEK-03, TEK-04, TEK-05, VIS-01, VIS-04; F06 "özgürlük sınırsız değil" (oyunun ana vaadini gösterebilmeli)

## Bağlam
İhtiyaçlar (foundation): ülke → metropol (~40 km körfez) → ilçe → sokak ölçeğinde **tek** 3D dünya; low-key low-poly, mat, flat-shaded estetik; metroda on binlerce yapı; deterministik, başsız test edilebilir simülasyon; oyuncunun çizdiği yollar ve prosedürel parsel üretimi; dokunmatik öncelikli (platform AÇIK, Q-004). Kısıtlar: 2019 Intel MacBook Pro (Radeon Pro 560X) geliştirme makinesi, yapay zekâ ajanlarının CLI ile süren üretimi, ücretli servis/asset yok, tek geliştirici.

## Karar
1. **Godot 4.7.2 (stable), GDScript**, statik tipli. Sürüm `tools/godot.sh` ile doğrulanır. 4.8 kararlı çıkınca ayrı bir ADR ile değerlendirilir (şu an beta1).
2. **Renderer: başlangıç (geliştirme) renderer'ı GL Compatibility — tüm platformlar için değişmez karar değildir (D-004).** Bugün tek kanıtlı yol bu (Intel Mac'te çalışıyor, iOS Simulator'da tek seçenek). Platforma ve kalite profiline göre renderer seçimi gerçek cihaz ölçümüyle yapılır (T-010): macOS Intel (Compatibility / Mobile / Forward+ — MoltenVK), iPad Pro M serisi (Compatibility / Mobile / Forward+ — Metal), Windows (cihaz gelince: Compatibility / Mobile / Forward+ — D3D12/Vulkan). Sonuç ADR-0004'teki grafik profillerine yazılır; Godot'ta renderer başlangıçta seçildiği için profil = proje ayarı özellik geçersiz kılması + başlangıç bayrağı.
3. **Render mimarisi** (ADR-0002 görünüm katmanı): 1 km chunk başına `MultiMeshInstance3D` (tür başına), örnek başına renk/ölçek; `visibility_range` ile chunk proxy'leri (HLOD). Metro görünümü için ikinci HLOD kademesi (birleştirilmiş bölge kütleleri) gereklidir — ilk ölçeklenme darboğazı budur. Proxy geçişlerinde fade/hysteresis (benchmark'ta sert "pop" görüldü).
4. **Simülasyon dili:** GDScript + Packed*Array sütunları; ağır sistemler `WorkerThreadPool` ile dilim-yaz/sıralı-birleştir deseninde (deterministik olduğu ölçüldü). Kare içinde tick çalıştırılmaz: günlük tick ya iş parçacığında ya da karelere bölünerek yürür. GDExtension (godot-cpp) yalnız profiler kanıtıyla.
5. **Koordinatlar:** metre, tek dünya; görünümde origin rebasing (ADR-0002 §2). Double-precision derleme yok.

## Performans: ölçülenler ve kanıtlanmamış hedefler
Üç yük **ayrı ayrı** ölçülür ve ayrı raporlanır; biri diğerinin kanıtı sayılmaz:
- **Render kare süresi** — simülasyon durdurulmuşken, standart kamera preset'lerinde (ms ort./p95, draw call).
- **Simülasyon tick süresi** — başsız, sistem başına, oyun günü başına (ms).
- **Birleşik oyun yükü** — render + simülasyon belirli oyun hızında birlikte koşarken kare süresi p95 ve tick gecikmesi (oyun hızı hedefe yetişiyor mu).

### Bugüne kadar ölçülen (sentetik, geliştirme Mac'i, `experiments/scale-bench`)
| Ölçü | Sonuç | Niteliği |
|---|---|---|
| Render, 60k yapı, Compatibility | ort. 4–10 ms; metro p95 ≈ 16 ms; 398 draw call (metro) | Sentetik kutular (12–24 üçgen), yol/ağaç/UI yok; makine dış yük altında (±%40) |
| Render, 327k yapı | en kötü ort. 12,9 ms (≈77 fps) | Aynı sentetik sahne |
| Sim tick, 60k parsel + 20k kohort | seri ~70 ms, 4 iş parçacığı ~40 ms / oyun günü | Sentetik iş yükü; gerçek sistem kuralları yok |
| Birleşik yük | **ölçülmedi** | — |

### Simülasyon frekansı: 40 ms neye göre?
40 ms, **bir oyun günü tick'inin** (ADR-0002 §4) maliyetidir; hedef frekansa göre değerlendirilmemiştir, çünkü oyun zamanının gerçek zamana oranı **ÇM/AÇIK**tır (F03 "Oyun temposu", F05-C). Değerlendirme formülü: simülasyonun gerçek zamandaki yükü = tick_ms × (oyun günü / gerçek saniye). Örnek (yalnız hesap, hedef değil): 1 gün/sn → 40 ms/sn (%4 iş parçacığı süresi); 10 gün/sn → 400 ms/sn — iş parçacığında kareyi bloklamadan sürdürülebilir olup olmadığı birleşik yük ölçümüyle gösterilmelidir. Tick kare içinde çalıştırılmaz (karar 4).

### Hedefler (başlangıç; **hiçbiri karşılanmış sayılmaz**)
| Ölçü | Hedef | Durum |
|---|---|---|
| Render, masaüstü referans (geliştirme Mac'i), her preset | ort. ≤ 8 ms, p95 ≤ 16,6 ms | Sentetikte yakın; gerçek sahnede kanıtlanmadı |
| Draw call, metro | ≤ 600 (hedef ≤ 400) | Sentetikte tuttu; gerçek sahnede kanıtlanmadı |
| Sim tick | en yüksek oyun hızında gerçek zamana yetişmeli, kare p95'ini bozmamalı; sayısal bütçe zaman ölçeği belirlenince yazılır | Kanıtlanmadı |
| iPad (M serisi) | cihaz ölçümünden sonra yazılır (T-008, T-010) | Ölçülmedi |
| Windows | cihaz gelince | Ölçülmedi |
Simülasyon kapsamı bu hedeflere göre kısılmaz (PLT-03); aşım olursa önce optimizasyon (iş parçacığı, toplu model, GDExtension), sonra ölçümle kullanıcıya rapor.

## Alternatifler
| Seçenek | Artı | Neden reddedildi |
|---|---|---|
| Unity 6.x (DOTS) | Olgun ECS, iOS | Intel Mac desteği 6.7 LTS'te biter (6.8+ yok) → geliştirme makinesi çıkmaza girer; ağır editör; GUID'li YAML ajan dostu değil; ECS'de süren değişiklikler |
| Unreal 5.8 | En güçlü büyük dünya araçları | macOS'ta yalnız Apple Silicon; Blueprint/uasset ikili → ajanlarla yönetilemez; iPad'de ağır |
| Bevy 0.20 | Saf Rust deterministik sim | Editör yok, ~4 ayda bir kırıcı sürüm, iOS durumu belirsiz, Intel Mac'te yavaş derleme, arazi/yol ekosistemi yok |
| Web (three.js/Babylon + TypeScript) | En iyi CLI/test deneyimi, iPad Safari'de WebGPU | **Ciddi aday, yedek seçenek.** Reddedilme nedeni: iPad sekme belleği riski, yerel uygulama kalitesi/paketleme belirsizliği, editör/inspector kaybı; Godot'un headless test + capture hattı burada zaten doğrulandı. Godot ölçek bütçesini cihazda tutturamazsa yeniden açılır. |
| Godot Forward+ / Mobile | Daha zengin ışık, Metal/D3D12, GPU zaman ölçümü | **Reddedilmedi, ertelendi:** platform/kalite profili başına T-010 cihaz ölçümüyle seçilecek (D-004) |

## Sonuçlar ve riskler
- Godot'ta yayımlanmış büyük ölçekli şehir kurma örneği bulunamadı; ölçek riski bizim ölçümlerimizle yönetilir (her milestone'da perf kapısı).
- Simülasyon CPU'su render'dan daha sıkı sınır: sistem tasarımı kohort/toplu modelle başlamalı (ADR-0002 §3).
- Yeniden açma tetikleyicileri: T-010 renderer karşılaştırması; hedef cihazda bütçe aşımı; Godot 4.8 kararlı sürümü; Windows/iPad cihaz ölçümleri (ADR-0004); GDScript tick bütçesinin GDExtension olmadan tutmaması.

## Kanıt
- `experiments/scale-bench/RESULTS.md` (+ `results/*.json`, temsilî kareler `experiments/scale-bench/evidence/`, **sanat referansı değildir**). Ölçüm koşulları: Godot 4.7.2 editör ikilisi, Radeon Pro 560X, VSync kapalı, MSAA 2×, makine dış yük altında (load 5–25) → ±%40 gürültü. Üç renderer da bu makinede başladı.
- Determinizm: aynı tohum → aynı SHA-256 (seri ve 4 iş parçacığı), farklı tohum → farklı.
- Asset hattı: `experiments/asset-pipeline-smoke/` (Blender → glTF → Godot, ölçü ve materyal doğrulandı).
- Doğrulanmamış: iPad/Metal davranışı, export şablonuyla performans, render+sim birlikte çalışırken kare süresi, yol/ağaç/UI eklenmiş gerçek sahne.
