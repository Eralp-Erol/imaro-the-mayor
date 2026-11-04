# 2026-11-05 · Teknik direktör perf kapısı (M2-CLOSURE madde 4 ve 6)

Yalnız doküman. `src/`, veri, test değişmedi; Godot çalıştırılmadı. Karar metni: `docs/adr/ADR-0010-kare-butcesi-hedefleri-m2.md`.

## Kararlar
- **Hedefler konuldu** (ADR-0010 Karar 2-3). Masaüstünde D-007 (ort ≤ 14 ms, tick'siz p95 ≤ 20 ms) aynen kalır. Eklenenler: p95 ≤ 16,6, p99 ≤ 25 (tavan 33,3), en kötü etkileşim karesi ≤ 50 ms (tavan 100), açılış ≤ 20 sn (tavan 45), örtüsüz tek blok ≤ 1 sn, draw call ≤ 400, üçgen yalnız tanı ölçüsü.
- **iPad:** aynı yapı; ort ≤ 8, p95 ≤ 16,6, ≤ 900k, ≤ 400; ayrıca bellek ve ısıl satırları. Hepsi **ön hedef, cihazda doğrulanmadı**.
- **Masaüstü durumu** (kayıttan): etkileşim karesi dışında tüm satırlar geçiyor. Yol onayı 130-207 ms, 100 ms tavanını aşıyor → FAIL. Açılış uçtan uca ölçülmedi.
- **T-012 K8 / üçgen:** M2-CLOSURE'daki "%9,5" ve "1,27M" bayat. T-012 aynı gün düzeltmiş: K8 %2,59-2,63, standart presetler 466-544k.
  - K8 → kabul (gerileme bekçisi). Üçgen → erteleme (D-007).
  - Bağ: K8, geçiş 1,45 km'ye itilerek düzeldi; çekirdekteki 2,87M üçgen bunun bedeli. Biri mesafeyle düzeltilirse öteki bozulur.
  - K8 ölçüsü, geçiş uzaklaştıkça kendiliğinden düşer (kapsama etkisi). Görsel kabul kanıtı değildir; görsel karar art-director + sahibin.
- **Yol takılması, yön:** en kötü kare, görünüm yenileme süresinin %83-92'si. Aynı karelerde beş görünüm tüketicisi var, her biri "en az bir birim" kuralıyla çalışıyor ve ortak kare bütçesi yok. Hipotez; alt sistem dökümü yok. Temel doğru, yeniden başlangıç gerekmez. Önerilen görev: T-075 (önce ölçüm).
- **B-028 → düzelt:** kanca yalnız `--smoke-save-load` ile çalışsın; smoke betiği bayrağı geçsin.
- **Kare 1 (4 sn):** önce oyuncuya görünüp görünmediği yakalanır.

## Sahibe soru (ADR-0010 §Sahibe soru)
Yol takılması M2'yi bekletsin mi? A (Önerilen): bilinen açık + iPad ölçümüne göre karar · B: şimdi düzelt · C: dokunma.

## Doğrulanmamış
- iPad'in tüm satırları ölçülmedi.
- Açılış uçtan uca ölçülmedi.
- Yol penceresinde alt sistem dökümü yok.
- K8 2026-10-25'ten sonra ölçülmedi.
- Ham `artifacts/perf/` JSON'ları bu oturumda bulunamadı; sayılar kayıtlardan alındı.

## Studio Director'a
`production/M2-CLOSURE.md:9,20`, `production/ROADMAP.md:62` ve `docs/agent-handoff/IMARO_CHECKPOINT.md:97` güncellenmeli. Bu oturum `production/` kapanış dosyalarına dokunmadı.
