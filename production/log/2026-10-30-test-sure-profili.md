# Test süre profili (2026-10-30)

Amaç: `tools/verify.sh quick`in 20-23 dk sürmesinin nedenini ölçmek ve hızlı modu buna göre tasarlamak. Ölçüm: `tools/godot.sh --headless ... GdUnitCmdTool.gd -a res://tests -c --ignoreHeadlessMode` (tek Godot, tüm testler; `verify.sh`in GdUnit adımıyla aynı komut), suite süreleri GdUnit konsol çıktısındaki `Statistics: ... PASSED <süre>` satırlarından.

## Koşul (güvenilirlik sınırı)
- Makine: 12 çekirdek, macOS; **başka ajanlar aynı anda Godot/uvx koşuyordu**. Yük ortalaması (1 dk) koşu boyunca 30 sn örnekle: en düşük 4.7, ortanca 6.6, en yüksek 19.6 (örnek sayısı 48). Süreler bu yüzden **şişik**; sakin makinede daha kısa beklenir (kesin sayı ölçülmedi).
- Koşu: 2026-10-30 20:25-20:49, duvar süresi **1415 sn (23.6 dk)**, çıkış 0, **2031 test, 187 suite, 0 hata**. Suite sürelerinin toplamı 1376 sn (kalan ~40 sn Godot açılışı/keşfi).
- Aynı çalışma ağacında başka ajanlar `src/view/vegetation`, `src/ui`, `src/game` üzerinde çalışıyordu; koşu sırasında bu dosyalar değişmiş olabilir (ölçüm anlık görüntü değildir).
- Ham veri: yalnız bu belgedeki tablolar (ham günlük depoya konmadı; yeniden üretmek için aynı komut).

## Bulgular
1. Sürenin **%69'u 15 suite'te, %81'i 30 suite'te**. 73 suite 1 sn'nin altında (toplam 36 sn = %2.6).
2. En büyük tek kalem bitki: `tests/world/vegetation` + `tests/view/vegetation` = 455 sn (%33). Tek test bile 40 sn (`test_tiny_budget_caps_the_total...`). Gerçek Ismeral dünyasını test başına yeniden üretiyor olmaları muhtemel (varsayım; neden profillenmedi).
3. `tests/sim/parcel_changes_test.gd` tek başına 133 sn (%9.7) ve `tests/game/m2_change_feed_projector_test.gd` 53 sn: ikisi de dünya+simülasyon kurup uzun koşuyor.
4. Dünya üretimi (`tests/world/*`: vegetation, settlement, network, topology_map, kök) toplam 654 sn (%47).
5. UI testleri (25 suite, 286 test) yalnız 43 sn; kamera/görünüm kökü 82 sn; sözleşme (96 test) 3 sn; uygulama 3 sn.

## En yavaş 15 suite
| # | Suite | Test | Süre (sn) | Toplamın % |
|---|---|---:|---:|---:|
| 1 | `tests/world/vegetation/vegetation_placement_test.gd` | 10 | 226.8 | 16.5% |
| 2 | `tests/sim/parcel_changes_test.gd` | 17 | 133.5 | 9.7% |
| 3 | `tests/view/vegetation/vegetation_cache_test.gd` | 6 | 111.3 | 8.1% |
| 4 | `tests/world/network/network_generation_test.gd` | 26 | 73.1 | 5.3% |
| 5 | `tests/world/vegetation/vegetation_invariants_test.gd` | 13 | 72.2 | 5.2% |
| 6 | `tests/world/settlement/settlement_generation_test.gd` | 31 | 58.6 | 4.3% |
| 7 | `tests/game/m2_change_feed_projector_test.gd` | 11 | 52.7 | 3.8% |
| 8 | `tests/world/topology_map/topology_seeds_test.gd` | 3 | 34.7 | 2.5% |
| 9 | `tests/world/settlement/settlement_organic_test.gd` | 8 | 32.2 | 2.3% |
| 10 | `tests/view/vegetation/vegetation_cell_builder_test.gd` | 5 | 31.9 | 2.3% |
| 11 | `tests/world/topology_map/topology_model_test.gd` | 13 | 30.5 | 2.2% |
| 12 | `tests/view/terrain_mesh_builder_test.gd` | 25 | 30.1 | 2.2% |
| 13 | `tests/view/camera_k1_test.gd` | 16 | 21.7 | 1.6% |
| 14 | `tests/world/settlement/settlement_industry_fit_test.gd` | 9 | 20.1 | 1.5% |
| 15 | `tests/world/settlement/settlement_hero_mapping_test.gd` | 12 | 18.9 | 1.4% |


## Dizin toplamları
| Dizin (doğrudan, alt dizinler ayrı satır) | Suite | Test | Süre (sn) | Toplamın % |
|---|---:|---:|---:|---:|
| `tests/world/vegetation` | 3 | 32 | 299.7 | 21.8% |
| `tests/sim` | 21 | 267 | 170.5 | 12.4% |
| `tests/view/vegetation` | 8 | 48 | 155.0 | 11.3% |
| `tests/world/settlement` | 7 | 85 | 146.4 | 10.6% |
| `tests/world/network` | 8 | 136 | 102.0 | 7.4% |
| `tests/sim/politics` | 11 | 122 | 93.1 | 6.8% |
| `tests/view` | 21 | 231 | 81.7 | 5.9% |
| `tests/game` | 9 | 72 | 70.3 | 5.1% |
| `tests/world/topology_map` | 8 | 55 | 69.4 | 5.0% |
| `tests/ui` | 25 | 286 | 42.7 | 3.1% |
| `tests/world` | 3 | 82 | 36.4 | 2.6% |
| `tests/view/buildings` | 13 | 113 | 24.3 | 1.8% |
| `tests/sim/economy` | 13 | 125 | 23.3 | 1.7% |
| `tests/sim/public_works` | 4 | 47 | 16.1 | 1.2% |
| `tests/sim/actors` | 8 | 87 | 12.8 | 0.9% |
| `tests/art` | 3 | 37 | 12.7 | 0.9% |
| `tests/library` | 4 | 28 | 10.8 | 0.8% |
| `tests/view/roads` | 2 | 25 | 3.5 | 0.3% |
| `tests/contracts` | 10 | 96 | 3.1 | 0.2% |
| `tests/app` | 5 | 54 | 2.6 | 0.2% |
| `tests/unit` | 1 | 3 | 0.1 | 0.0% |
| **Toplam** | 187 | 2031 | 1376.4 | 100% |
## Sonuç (hızlı mod tasarımına girdi)
- Günlük doğrulamada koşulması gerekmeyen şey: yavaş dünya/bitki/parsel-değişim suite'leri, ilgili alan değişmedikçe.
- Küçük ama değerli çekirdek: determinizm/GOLDEN hash, saflık, CAN-03, kayıt gidiş-dönüş, sözleşmeler ≈ 28 suite, ~288 test, ~40 sn (bu aynı yük altında).
- Tasarım ve ölçülen hızlı süreler: `tools/README.md` (verify), `tools/verify-areas.tsv`, `production/log/2026-10-30-verify-quick-hizli-mod.md`.
- Tavsiye (ayrı iş, yapılmadı): `vegetation_placement_test`, `vegetation_cache_test`, `parcel_changes_test`, `terrain_mesh_builder_test` dünya/mesh'i test başına yeniden üretiyor olabilir; paylaşılan fixture ile suite başına bir kez üretmek `full` süresini ciddi düşürür. Bunlar bitki/dünya ajanlarının dosyaları; dokunulmadı.
