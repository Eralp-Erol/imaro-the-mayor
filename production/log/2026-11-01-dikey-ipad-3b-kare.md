# 2026-11-01 · Dikey iPad yikim onayi + GERCEK 3B kareler (ui-engineer)

Gercek `playable.tscn` (3B dunya, sim, HUD), `--imaro-input-profile=touch`, penceere 1024x768 / 800x600 / 768x1024, `tools/godot/expropriation_game_probe.gd --ui --demolish-card=confirm --map-center=...` (dunya dokunuslari gercek `InputEventScreenTouch`; duğmeler fare tiki). Kareler Read ile gorundu. Kareler: artifacts/screenshots/captures/dikey-3b-*.png (git disi).

## Bulgular (3B karede) ve koklari
1. Dikey alt sayfada (196 px) "Evet, yik / Vazgec" kaydirma gerektiriyordu. Kok: onay kartinda dugmeler aciklama+uyari+maliyetten sonraydi. Duzeltme: dokunmatikte baslik -> dugmeler -> ikincil metin (`road_draw_panel.gd _add_demolish_confirm`). Test: `hud_float_layout_test` artik dikeyde de `_check_confirm_visible` (once kirmizi: 'Evet, yik' y=796 > gorunur alan sonu 809, sonra yesil).
2. GERCEK OYUNDA yol ipucu karti ("1/3 . Yola ya da yol ucuna dokun") bildirim satirlarini ve hiz ipucunu ortuyordu (B-019 UI testinde "cozuldu" idi). Kok: `RoadDrawController.attach` ipucunu `follow_hud`'a baglamiyordu (yalniz testteki elle kurulum cagiriyordu). Duzeltme: `c.tip.follow_hud(hud)`. Test: `road_draw_flow_test.test_cursor_tip_reflows_when_strip_rows_arrive_after_it_was_placed` (kirmizi -> yesil).
3. 800x600 dokunmatikte yol cizildikten sonra "Son yolu yik" dugmesi panelin gorunur alaninin altindaydi (adim 1'de devre disi Onayla/Iptal satiri + uzun plan ipucu yer kapliyordu; probe dugmeye basamadi). Duzeltme: adim 1'de olu Onayla/Iptal satiri cizilmez; yonetim fiilleri (Geri al / Yolu yik) aciklama ve plan ipucundan ONCE; plan ipucu baslik puntosundan duz etikete (B-019 madde 4). Test: `test_demolish_verb_visible_without_scrolling_when_plan_hint_is_shown` (kirmizi: 800x600 ve 768x1024 -> yesil).
4. 800x600'de yikim sonrasi "Yol yikildi ... [Nedenini gor]" satiri, ustundeki dugmesiz "Komut uygulandi" satiri yuzunden gizleniyordu (serit yukseklik siniri). Duzeltme: `NotificationStrip._fit_rows` gerekce dugmeli satiri once korur. Test: `test_strip_height_cap_keeps_the_row_with_the_reason_button` (kirmizi -> yesil).

## Gorulen ve temiz
Yikim seridi satiri ve [Nedenini gor] paneli duz Turkce ("Belediye yolu yikti", "Marj +0,001: esik asildi"); ham anahtar yok. Serit/ipucu/hiz karti/arac cubugu/panel cakismiyor (1024x768, 800x600, 768x1024). Not (dokunulmadi): panelde "Karar veren Belediye 1 / Komut 1 / Komut 2" etiketleri soluk (veri, ham anahtar degil).

## Dogrulama
tests/ui + tests/game: 607 test 0 hata (22 orphan; onceden de vardi). `tools/verify.sh quick`: pass (KISMI; 943 test, 100 suite). gdlint temiz.
Dogrulanmadi: fiziksel iPad dokunusu (probe dugme basisi fare tiki), gercek cihaz guvenli alan (probe'da simule), `full`.
