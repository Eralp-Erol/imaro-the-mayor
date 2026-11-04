# T-043B sim yarısı · yol/imar sonrası öncelikli değerlendirme (2026-10-31)

Kapsam: D-010 karar 1 (core-loop-v0 §3 B). Oyun katmanı (C: başlangıç hızı/ipucu) bu kayıtta YOK.

- Tetikleyici: yol onayı (o tick `public_works.works`e eklenen yol) ya da plan yürürlüğü. Olayın `priority_radius_m` (150 m)
  yakınındaki, yürürlükte planı olan + oyuncu yoluna bağlı + boş en çok `priority_max_parcels` (12) parsel `attention_delay_days`
  (2) sonra zorunlu değerlendirme kuyruğuna girer (en yakın önce). Plan yolu: bağlı plan parselleri plan komutuyla kuyruğa,
  K'yı aşan/bağlı olmayanlar eski dikkat yoluna (kaybolmaz). Plansız/bağlantısız parsel girmez; aday yoksa durum yazılmaz.
- Dağıtım: kuyruk `max_reviews_per_tick` bütçesinden ÖNCE yer, periyodik tarama kalanı kullanır (A notu: plansız parselin
  tarama payını yemesi kısalır). Bölge başlangıç sınırı dolarsa giriş ertesi güne kalır.
- Veri: `decision.priority_review_enabled|priority_radius_m|priority_max_parcels` (`economy_config.json` varsayılan 0/150/12;
  `data/game/playable_economy.json` `priority_review_enabled: 1`). Kuyruk yalnız `unplanned_land_enabled` 1 iken çalışır.
- Kayıt: `economy.priority` / `economy.priority_cmd` yalnız ilk girişte yaratılır, bölüm `version` 1 -> 2 (kuyruksuz koşu 1'de
  kalır: t0 ve GOLDEN_A/B değişmedi, YENİ ALTIN DEĞER YOK). `validate_data` 1 ve 2'yi kabul eder; sürüm 1 kayıt yüklenir.
- Ek düzeltme: bayrak açıkken plansız boş parselde `ParcelView.zone` ekonomi durumu kurulmadan önce (tick 0) da boş
  (`EconomySystem.hides_template_zone`, facade `parcel_views`); sözleşme değişmedi.
- Ölçüm (5 tohum, 6 planlı yakın parsel, kapasite 0 -> yol 10 birim ekler, 1500 plansız dolgu parseli): tetikten ilk inşaat
  yol-son 13 gün / plan-son 12 gün, ilk bina 67 / 66 gün (tohumlar arası aynı: ilk onay tohumdan bağımsız; ret dağılımı ayrı
  senaryoda tohumlara göre değişir). Kuyruk kapalı kontrol: plan->yol sırasında ilk inşaat 161 gün, ilk bina 215 gün.
- Kare bütçesi (`tests/sim/perf/t043b_priority_trigger_probe.gd`, 10 000 parsel): kuyruk açık en kötü tick 13.8-14.6 ms (ay
  sınırı tick'i; kuyruksuz da ~13.6), tetik tick'i ~12 ms (yol komutu/ağ maliyeti; kuyruk kapalıyken 12.1 ms: kuyruğun payı
  < 0.5 ms), kuyruk tick'leri 1-2 ms. 16,6 ms içinde.
