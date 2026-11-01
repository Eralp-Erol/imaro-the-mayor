# 2026-11-01 · Yol görünümü "Out of bounds get index '7369'" (B-020)

- Görev: arayüz ajanı gerçek oyun probe'unda `road_junction.gd` / `road_mesh_builder.gd` OOB gördü; kök neden araştırması. Kapsam yasağı: sim kodu, playable.gd, foundation, blocs.json.
- Kod okuma: yol görünümü `RoadEditSync` ağ değişimini (graph_version + değişim günlüğü) okur, chunk mesh verisini `WorkerThreadPool` işçisinde kurar (`world_busy()` iken ağ yazılmamalı). Mesaj `(on base: 'Dictionary')`: eksik kenar/düğüm kimliği (Array indeksi değil; deneyle doğrulandı).
- Tekrar üretme: mevcut probe'lar 17 koşu 0 OOB (pencereli 9, başsız 8). Hedefli probe (işçi + meşgul önizleme) iki yolla 2/2 üretti, bkz. B-020.
- Kök neden: yıkım önizlemesi `reject_args` yolundan meşgulken de ağı geçici yazıyor (kuru koşu). Geçici deneyle doğrulandı (geri alındı).
- Yapılan (görünüm): `RoadEditSync` ihlal koruması + 2 test, `tools/godot/road_view_race_probe.gd` (+ .uid), B-020.
- Yapılmayan: sim düzeltmesi (yasak kapsam). Öneri B-020'de.
- Doğrulama: gdlint temiz; tests/view/roads 41 test geçti (2 yeni); `tools/verify.sh quick` PASS (KISMİ: 95/293 suite, 931 test, 0 hata; atlanan 198 suite). Hash/GOLDEN etkisi yok (yalnız görünüm + tool).
