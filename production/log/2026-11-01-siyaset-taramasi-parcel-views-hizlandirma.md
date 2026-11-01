# Haftalık siyaset taraması + `parcel_views` hızlandırması (2026-11-01)

Girdi: `docs/adr/proposals/2026-11-01-haftalik-siyaset-taramasi-ve-parcel-views.md` (Seçenek A, §2.3) ve
`production/log/2026-10-31-kare-sicramalari.md`. Davranışı HİÇ değiştirmeyen hızlandırma: GOLDEN_A/B ve büyük dünya
hash'i bit-bit aynı. Sözleşme 1.5 değişmedi.

## Değişenler

- `src/sim/politics/event_causes.gd`: `region_projects(state, ctx, exposure, scan_cache := null)`; bölge başına en iyi
  `cause_cap` aday TEK parsel geçişiyle kurulur (önbellek `BlocEngine.scan` içindeki yerel sözlük; duruma/kayda girmez),
  birleşimin ilk `cap`'i eski tam-tarama sonucuyla aynı. `recent_declines`: `find` (derin kopya) yerine `peek`.
  En ucuz eleme (`reason_id < 1`) döngüde öne alındı.
- `src/sim/politics/bloc_engine.gd`: `scan_cache` tarama başına bir kez kurulup `_scan_bloc` -> `_evaluate` ile geçer.
- `src/sim/politics/event_engine.gd`: `_region_of_event` `by_id` yerine `peek` (tek satır).
- `src/sim/facade/reason_subject_cache.gd` (yeni) + `sim_facade_impl.gd`: `parcel_views` artık günlüğün tamamını taramaz.
  Önbellek TÜM konuların dizinini artımlı tutar (yalnız yeni kayıtlar `peek` ile eklenir), anahtar: durum + günlük örneği +
  limit (+ son kimlik geri giderse / ilk kimlik küçülürse at); budanan kimlikler okumada düşülür; kayıt yüklemede `reset()`.
  `subject_index` ile bit-bit aynı çıktı; hash/kayıt dışı.
- Satır sınırı: `world_network.gd`/`economy_system.gd` dokunulmadı. `sim_facade_impl.gd` 571 -> ~575.

## Testler (yeni)

- `tests/sim/politics/event_causes_equivalence_test.gd` (5): eski kodun referans kopyası ile yeni yol, 3 tohum, eşit
  `reason_id` + farklı parsel sırası (rastgele sütun), `recent_declines`, `_region_of_event`, önbelleğin hash'e girmemesi.
- `tests/sim/parcel_views_reason_cache_test.gd` (7): önbellekli `reason_ids` == `subject_index` (3 tohum x 40 gün),
  yeni kayıt anında görünür / budanan kaybolur, kayıt yükleme, hash nötr, "yeni kayıt başına bir okuma" sayacı,
  rastgele ekle/buda/sorgu dizileri (kapasite 3/7/40, limit 1/2/5), günlük örneği/durum/limit değişince atma.
  Mutasyon denemesi: budama düşmesi kapatılınca iki test kırmızı (geri alındı).

## Bulgu: Packed diziler referansla geçer

ADR önerisi §2.3 "Packed dizi yazınca kopyalanır" diyordu; Godot 4.7'de Packed diziler REFERANSLA geçer. İlk sürümde
önbellekteki dizi `ParcelView.reason_ids`e aynen verildi ve `sim_facade_impl_test.test_returned_dtos_are_copies_ui_cannot_mutate_sim`
kırıldı (ilk `verify quick` FAIL). Düzeltme: `ReasonSubjectCache.lookup` kopya (`duplicate`) döner; birim regresyon testi
(`test_mutating_a_returned_array_does_not_leak_into_the_cache`) kaldırınca kırmızı. ADR önerisindeki cümle düzeltilmeli.

## Hash (büyük dünya, `t043b_real_world_probe.gd` `state_hash`)

| koşu | önce | sonra |
|---|---|---|
| `--days=1500 --no-stop --profile --bands` (tick 1532) | `b5aefb7a160d83796400385d507d96fa2474e56c215ed236352d8fed86cf0c2a` | aynı |
| `--sim-seed=7 --days=700 --no-stop` (tick 732) | `afd33d3446b594a37dff3b0e4f757dfefb90eb9b35b378e651e4a196b3fbd32b` | aynı |
| `--sim-seed=12345 --days=500 --no-stop --rank=2` (tick 532) | `ca1df3c39f326425da4c912f365acca8b9284424817ae01b98c2dc2bf1c530bd` | aynı |
| GOLDEN_A `m2_query_test` | `d66d81a9...48d27ebb2` | aynı (test geçti) |
| GOLDEN_B `m2_query_test` | `3e85ce2c...e33b49d9` | aynı (test geçti) |

## Ölçüm (gürültü uyarısı)

Makine ölçüm boyunca yük altındaydı: `CPU_Speed_Limit` 44-58, yük ortalaması 18-230 (başka ajanlar). Mutlak ms güvenilmez.
Bu yüzden iki yöntem: (1) AYNI koşuda eski ve yeni yol art arda zamanlandı (geçici zamanlayıcı, geri alındı; gürültü her
ikisini aynı etkiler), (2) probe `cal_ms` ile normalize.

| ölçüm | eski | yeni | oran |
|---|---|---|---|
| `region_projects` çağrısı (41 değerlendirme, aynı koşuda) | ort 10,2 ms (maks 18,2) | ort 3,9 ms (maks 7,3) | x0,38 |
| `parcel_views` çağrısı (1531 çağrı, aynı koşuda) | ort 1,55 ms | ort 0,106 ms (maks 13,2 = ilk kurulum) | x0,07 |
| haftalık `politics.daily` (bant ort / cal_ms) | 6,2-9,8 (tek bant 15,2 az örnek) | 4,5-6,7 (tek bant 8,6) | ~ -30% |
| projector çifti ort (ms / cal_ms) | 2,58 / 0,49 = 5,3 | 1,55 / 0,6 = 2,6 | ~ -50% |

Not: `region_projects` tek-geçiş kazancı haftada çoğunlukla 1 kesim değerlendirildiği için sınırlı (41 değerlendirme /
~215 tarama); asıl kazanç eleme sırası (40 bin döngüde `reason_id < 1` önce). Hesap hâlâ O(parsel) ama tarama başına bir kez.
Tick'li kare p95/maks (kare sıçraması) için pencereli ölçüm YAPILMADI.
