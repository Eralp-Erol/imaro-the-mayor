# Yol çizimi maliyeti ve onay görünürlüğü (2026-10-30, kullanıcı denemesi sonrası)

Kaynak gözlem (kullanıcının gerçek demosu, commit 57bd940): (1) iki kez `ERROR: Condition "!is_inside_tree()" is true. at: grab_focus`; (2) Yol çiz açıkken `avg_frame_ms` 28 -> 69; onayda `PLAYABLE_ROADS ... ms=1317.4`; (3) kullanıcı yolun iki ucunu tıklayınca onayı bulamadı.

## 1. `grab_focus` hatası: kök neden ve düzeltme
- Yeniden üretildi (`tests/ui/flow_focus_restore_test.gd`, düzeltmeden ÖNCE kırmızı: aynı `ERROR: Condition "!is_inside_tree()" ... grab_focus (scene/gui/control.cpp:3001)`).
- Neden: `FlowPanel._restore_focus` odağı `b.grab_focus.call_deferred()` ile veriyordu. Aynı karede panel iki kez yeniden çizilirse (parsel seçimi: sonuç/denetçi/olay) ilk çizimin ertelenmiş çağrısı, ikinci çizimde `remove_child` + `queue_free` edilen ESKİ düğmeye düşer.
- Düzeltme (`src/ui/flows/flow_panel.gd`): erteleme düğmeyi değil ROLÜ saklar (`_pending_focus_role`); ertelenmiş `_apply_pending_focus` o anki düğmeyi bulur ve yalnız ağaçta/görünür/etkinse odaklar (`focus_button_if_alive`); ikinci çizim bekleyen rolü devralır (odak kaybolmaz). Panel testleri (403 test: game + ui + view/roads) yeşil.

## 2. Kare süresi ve 1,3 sn: ölçüm (`tools/godot/road_ux_probe.gd`, GERÇEK Ismeral dünyası, ana iş parçacığı, başsız)
Makine yük altındaydı (yük ort. ~9, 12 çekirdek): mutlak değerler şişik olabilir, oranlar anlamlıdır.
| Ölçüm | Sonuç |
|---|---|
| `RoadDraftCheck.check`, geçerli taslak (n=22) | ort. 9,1 ms, p95 15,3, en çok 19,6 |
| `RoadDraftCheck.check`, reddedilen (n=178) | ort. 1,4 ms, p95 4,0 |
| İmleç adımı (1 m), `hover_at` toplam, panel yeniden çizimi DAHİL (sentetik dünya, gerçek sim facade) | ort. 12,5 ms, p95 17,7 |
| ... bunun panel kısmı (`RoadDrawPanel.refresh`, her adımda yeniden kuruluyor: 120/120) | ort. 6,6 ms |
| Yol onayı: `add_road` (tick içinde, ana iş parçacığı) | ort. 21,3 ms, en çok 44 |
| `RoadEditSync.begin_async` (ana iş parçacığı) | ort. 0,6 ms |
| Arka plan chunk verisi (ana iş parçacığını BEKLETMEZ) | ort. 137 ms, p95 300 |
| `poll`/`install` (ana iş parçacığı) | ort. 2,2 ms, en çok 5,4 |
| Toplam duvar (`PLAYABLE_ROADS ms=` buna karşılık) | ort. 161 ms, p95 325 |

Okuma:
- **1,3 sn ana iş parçacığı değildir.** `ms`, `begin_async`ten `install`a kadar DUVAR süresidir (arka plan işi + işçi bekleme + kare aralıkları); ana iş parçacığı payı ~24 ms (add_road tick içinde + 3 ms). Kullanıcı denemesinde işçi havuzu bitki yerleşimi/başka Godot koşularıyla paylaşıldığı için 1,3 sn'ye çıkmış olabilir (varsayım, o koşu yeniden ölçülmedi). Yol onayında kare duraksaması beklenen: tek `add_road` ≈ 21-44 ms (tick'li kare).
- **Kare süresi artışının nedeni imleç önizlemesi.** Her fare hareketi (>0,5 m) sim kuru koşusu + panel yeniden çizimi + önizleme ağı kuruyordu (~12 ms/adım, fare olayı başına; yüksek örnekleme hızında kare başına birden çok). `RoadDraftCheck.check` her kare değil yalnız hareketle çalışıyordu ama hareket sınırı fazla küçüktü.
- Düzeltme: imleç önizlemesi en çok 50 ms'de bir uygulanır (`RoadDrawController.HOVER_INTERVAL_MSEC`), aradaki hareketler birleşir, son konum `process`te uygulanır; tıklama bekleyen hareketi ezer. Yan panel imleç önizlemesinde en çok 250 ms'de bir yeniden kurulur (adım başına ~6,6 ms düğüm kurma; dokunuş/onay/iptal adımlarında hemen). (Testler: `test_rapid_mouse_motion_is_coalesced_and_the_last_position_wins`, `test_side_panel_is_not_rebuilt_on_every_hover_step_but_catches_up`.) Beklenen etki: imleç hareketi başına ~12 ms'lik iş en çok 20 Hz'e iniyor ve panel kısmı 4 Hz'e; kare süresine gerçek etkisi pencereli ölçülmedi.
- Ölçülmeyen: önizleme ağının (`RoadDraftPreview._build`) kendi süresi ve gerçek pencerede kare süresi (başsız çalışma render etmez).

## 3. Onay görünürlüğü (kullanıcı: "Onayla yalnız sağ paneldeki küçük kutuda, çok zor anladım")
- Yolun bitiş ucunda büyük birincil renkli işaret `RoadConfirmChip`: "Onaylamak için Enter ya da buraya tıkla · Esc iptal" (dokunmatik: "Onaylamak için buraya dokun"); yalnız yol yapılabilirse (Adım 3/3); tıklama onaydır.
- Enter onaylar (Boşluk DEĞİL; `RoadDrawKeys`); aynı noktaya yeniden tıklamak onaylar; başka yere tıklamak bitişi değiştirir.
- Panel Adım 3/3: üstte tek satır yönerge ("Yolu onaylamak için Enter'a bas ya da Onayla'ya tıkla."), hemen altında büyük, vurgu renkli Onayla (>= 56 px, dokunmatikte >= `target_primary`), kart altta.
- İmleç etiketi her adımda: "1/3 · Yola ya da yol ucuna tıkla", "2/3 · Bitişi tıkla", "3/3 · Onayla: Enter ya da işarete tıkla".
- Kare: `artifacts/screenshots/captures/20261030-213500-m2-t042-fix-confirm.png` (REVIEW, geçerli yol; dev bayrağı `--road-preview`, 1600x900, bitki kapalı; Read ile açıp baktım).
- Doğrulanmadı: gerçek fare/dokunma cihazı, gerçek klavye Enter (testler `Viewport.push_input` sentetik olaylar), aynı-noktaya-yeniden-tıklamanın kazara çift tıklamada onaylaması (geri alınabilir: "Son yolu geri al").
