# T-042b · UI adımı (kamulaştırma / yıkım) — 2026-10-31

REQ: CAN-03, CAN-04, SIM-05, SIM-12, WLD-09 · Karar: D-011 · Plan: `production/tasks/T-042b-PLAN.md` §4 adım 4 · Sözleşme: ADR-0005 Ek F (v1.5).
Dal: `worktree-agent-adbf4125ba4373cb3`. Dünya bağdaştırıcısı YOK: her şey MOCK fixture (`tests/fixtures/mock_scenario_expropriation.json`) ile. `verify` koşturulmadı (görev gereği); push/merge yok. `playable.gd` dokunulmadı.

## Ne yapıldı
- **Teklif** (`crosses_parcels` reddi): ret args'ı alınacak arsa sayısı (`taken_parcels` > 0) taşıyorsa panel "Bu yol arsaların içinden geçiyor" + "N bina yıkılacak, M hane yerinden edilecek." + "Bedel: henüz kurulmadı." + ayrıntı (alınan/yapılı arsa, konut/ticaret birimi, iptal olan proje, bölge başına arsa) + yakınlık satırı (`nearby_*`) + "Halk en çok yerinden edilmeye tepki verir." ve birincil "Kamulaştırarak geç" düğmesi. Teklif varken ölü "Onayla" düğmesi yok. Args'ta teklif yoksa (kamulaştırma kapalı) teklif görünmez ve ret metni "kamulaştırma henüz yok" kalır.
- **İki adımlı onay**: (1) "Kamulaştırarak geç" taslağı `expropriate: true` ile sim'e yeniden sordurur; sayılar sim önizlemesinden. (2) Yıkım/yerinden edilme/proje kaybı varsa onay düğmesi "Yıkımı onayla" olur; aynı noktaya yeniden dokunuş yıkımlı yolu ONAYLAMAZ (kazara dokunuş); Enter ve bitiş işareti çalışır, işaret "Yıkımı onaylamak için ..." der; imleç etiketi yıkım sayılarını söyler. Bitiş değişince kabul düşer; "Kamulaştırmaktan vazgeç" düğmesi teklife döner. Onay anında `expropriation_changed` gelirse kabul düşer, teklif yeni sayılarla yeniden çıkar.
- **Ret metinleri**: `protected_structure`, `expropriation_disabled`, `expropriation_changed`, `economy_not_started` (+ teklif taşıyan `crosses_parcels` için ayrı cümle).
- **Denetçi**: alınan parselde "Kamulaştırıldı ← Yol (1. yıl, N. gün)" (gün = `taken_by_command` ile eşleşen `public_works()` kaydının tick'i; kayıt yoksa komut etiketi), mülkiyet satırı "Yok (kamulaştırıldı)", `reason_ids` varsa "Nedenini gör". `m2_result_panel` aşama satırı ve `zoning_flow_model` (taken = yapı değil) uyumlandı.
- **Geri alma onayı**: son yol kamulaştırmalıysa "Son yolu geri al" ikinci adım ister: "Yıkımlı yolu geri almak binaları geri getirir, halkın tepkisi geri gelmez." + "Geri gelecek: N bina, ..." (önizlemenin `restored_*` alanı, yoksa yolun sim kaydı). Düz yol tek adım kalır.
- **Şerit**: `public_work.expropriated` ve `public_work.restored` olay metinleri; aynı komutun "Yol yapıldı" satırına "N bina yıkıldı, M hane yerinden edildi" eklenir (tek satır, gürültü yok). Halk tepkisi (`group.reacted`) mevcut oyuncu-öncelikli yoldan şeride düşer ("Nedenini gör"). Gerekçe panelinde yeni etken/karar anahtarları için Türkçe metin eklendi.

## Sim alanları (hangi öğe ne okur)
- Teklif/önizleme: `CommandResult.args` `taken_parcels, taken_built_parcels, taken_project_parcels, taken_res_units, taken_com_units, displaced_households, taken_regions, nearby_households, nearby_parcels, cost_available`.
- Geri alma: `validate_command(undo_last).args.restored_*` (yoksa `PublicWorkView.taken_*`), `PublicWorkView.expropriated`.
- Denetçi: `ParcelView.development == taken`, `taken_by_command`, `reason_ids`; `PublicWorkView.command_id/tick`.
- Şerit: `SimEvent.kind/command_id/args` (`built_parcels, households, parcels`).

## Dosyalar
Yeni: `src/ui/flows/expropriation_text.gd`, `tests/ui/expropriation_ui_test.gd` (+ .uid). Değişen: `src/ui/flows/{road_draw_panel,m2_result_panel,zoning_flow_model}.gd`, `src/ui/hud/{notification_strip,road_confirm_chip}.gd`, `src/ui/panels/inspector_panel.gd`, `src/ui/core/ui_text.gd`, `data/ui/strings.tr.json` (51 anahtar), `src/game/road_draw_tool.gd` (+ `expropriate`, `offer/accept_offer/withdraw_offer/demolishes/last_road`; ek, UI aracın durum makinesine bağlı), `src/game/road_draw_controller.gd` (+3 satır: işaret metni, imleç etiketi).

## DOĞRULANMIŞ (çalıştırıldı)
- GdUnit (doğrudan, `verify` DEĞİL): `tests/ui` + `tests/game/{road_draw_tool,road_draw_flow,can03_guard,honest_zoning}_test` + `tests/contracts`: **499 test, 0 hata, 0 başarısızlık** (20 sahipsiz nesne uyarısı, eski testlerden). Yeni `expropriation_ui_test.gd`: 22 test (teklif sayıları args'tan, bedel satırı, para simgesi yok, teklif yokken teklif yok + "henüz yok", iki adım, tek dokunuşla onay yok, vazgeç, dokunmatik hedef >= 44, ret/olay/etken metinleri, geri alma iki adım + düz yol tek adım, denetçi satırı, şerit birleştirme, halk tepkisi şeritte, CAN-03 metin taraması).
- `gdlint` (gdtoolkit 4.5.0) `src/ui src/game/road_draw_{tool,controller}.gd tests/ui`: sorun yok.

## VARSAYILAN
- Teklif tanıma: `crosses_parcels` + `taken_parcels > 0`. Fixture ret args'ında `expropriate` yerine `expropriation_offered` var; gerçek sim `ExpropriationSummary.preview_args` ile `expropriate: true` + `taken_parcels` yazar. İkisi de `taken_parcels`ta eşleşir. (Sim ekibi için not: fixture ile gerçek ret anahtarı bire bir değil.)
- "Bina" = `taken_built_parcels` (yapılı arsa başına bir bina varsayımı; sözleşme "built_parcels: bina yıkılır" diyor).
- Yıkımlı sayılan eşik: bina > 0 ya da yerinden edilen hane > 0 ya da iptal olan proje > 0.

## TEST EDİLMEDİ
- Gerçek dünya/sim bağdaştırıcısı, gerçek `SimFacadeImpl` ile kamulaştırmalı yol, pencereli runtime ve ekran görüntüsü (dünya adımı yok; headless dummy renderer görüntü alamaz). 480/1600 px düzen çakışması bu adımda ölçülmedi (dar panel testi yalnız dokunmatik hedefi sınadı).
- iPad dokunma; `verify quick/full`.
- **Boşluk (sim):** gerçek `BlocEngine` tepki gerekçesine `displaced_households` / `road_proximity` etkenlerini yazmıyor (yalnız mock fixture yazıyor); bu yüzden "Nedenini gör" panelinde yerinden edilme/yakınlık etkeni gerçek sim'de görünmez. Metinleri hazır (`reason.factor.displaced_households|road_proximity`). Tepkiyi yerinden edilmeye bağlayan nedensellik kaydı sim'den gelmeli (UI uydurmaz).
- Gündem panelinde tepkiye özel satır eklenmedi (sim tepki için gündem maddesi üretmiyor).
