# Gündem yanıt UI'ı (PE-01 seçenek kartları) — 2026-10-31

REQ: CAN-03, SIM-05, SIM-12, VIS-07 (konsept görselinden kopya yok) · Karar: D-008 · Sim tarafı: `2026-10-31-gundem-yaniti.md` ("UI'ya devredilecek").
`playable.gd` 1000 satır, DEĞİŞMEDİ. `design/foundation` değişmedi. Push yok.

## Yapılan
- `src/ui/flows/agenda_model.gd`: `Option` artık sim'in `AgendaOptionView`ı (id, verb, label_key, available, locked_by, effects); eski bedel/preview_key/`can_defer` alanları kaldırıldı. `Item.agenda_item_id` (komut için sayısal kimlik). `derive_all` `options`ı aynen taşır. `effect_text(effect)`: düz Türkçe önizleme ("Yatırımcı riski artar (bu bölgede); hemen başlar, 180 gün sürer"); sayısal büyüklük YOK. Eski "agenda.respond komutu yok" yorumu güncellendi.
- `src/ui/flows/agenda_panel.gd`: seçenek başına kart: `label_key` başlığı, "tahmin" çipli etki satırları, kilitliyse gri düğme + "Kilitli: ilçe işleri yetkisi gerekir.", "Bu yanıtı ver" -> `facade.submit_command(SimCommand.agenda_respond(item_id, option_id))`. Ret nedeni `args.why` (kısa Türkçe) ya da `UiText.reject_reason(reason_key)` ile kartta. Kabulde "Yanıt gönderildi; sonraki günde işlenir" + öğenin düğmeleri kapanır (çift gönderim yok); öğe SİM'den kalkınca (sonraki tick) listeden kalkar, iyimser silme yok. `handle_event`: tick sınırında `command.rejected` (kendi command_id'miz) kartta nedenle görünür. `options` boşsa düğme YOK. Ölü "Ertele" düğmesi/`deferred` sinyali ve bedel satırı kaldırıldı.
- `src/ui/flows/decision_panels.gd`: olayları agenda paneline de iletir (`handle_event`).
- `data/ui/strings.tr.json`: etki/kapsam/kilit/ret metinleri; kullanılmayan `agenda.defer*`, `agenda.option_cost` silindi; `agenda.derived_note` ("olaylar henüz kurulmadı" yanlışlaşmıştı) düzeltildi. (JSON yeniden yazımında boş satırlar kalktı; içerik değişikliği yalnız `agenda.*`.)
- `scenes/dev/ui_lab.gd`: eski sahte `_dev_option_items` (kaldırılan alanlara bağlıydı ve sahte bedel gösteriyordu) silindi; `--ui-lab-scenario=expropriation --ui-lab-demo=agenda_options` MOCK PE-01 kartlarını açar.

## Okunan sim alanları
`AgendaItemView.{item_id, title_key, deadline_tick, reason_ids, options}`, `AgendaOptionView.{option_id, verb, label_key, available, locked_by, effects[target, scope, direction, delay_days, duration_days]}`; `CommandResult.{status, command_id, reason_key, args.why}`; `SimEvent(command.rejected).{command_id, message_key, args}`. `curve` okunur ama gösterilmez.

## "reverse / Kararı gözden geçir" uyumsuzluğu
Etiket yolun geri alınacağını düşündürür; gerçekte yalnız yatırımcı riskini artırır ve destekleyen kesimlerin memnuniyetini düşürür, yol/parseller geri gelmez (o iş `public_work.undo_last`). Etiket (`event.pe01.opt.reverse`) DEĞİŞTİRİLMEDİ; kartta etiketin altında sabit açıklama var: "Yolu geri almaz; yalnızca yatırımcı riskini ve destekleyen kesimlerin memnuniyetini etkiler." (`agenda.note.revise_decision`, fiil anahtarlı).
**Tasarım kararı gerekir:** (a) etiketi gerçeğe göre yeniden adlandırmak mı (örn. "Tepkiyi kabul et, yatırımcı riskini göze al"), (b) sim'de gerçek geri alma bağlamak mı, (c) seçeneği kaldırmak mı. UI şimdilik açıklamayla dürüst; karar design-director / sahip.

## Testler
DOĞRULANMIŞ (çalıştırıldı):
- `tests/ui` tamamı (37 suite, 380 test): ilk koşuda 1 başarısız (masaüstü profilinde düğme 38, 44 dokunmatik içindir; test dokunmatik profile taşındı), sonra `agenda_facade_adapter_test` + `agenda_real_sim_test` + `decision_panels_test`: 47 test, 0 hata, 0 başarısız. Not: ilk tam `tests/ui` koşusundan sonra yalnız bu üç suite yeniden koşuldu; diğer 34 suite'in son kod hâliyle yeniden tam koşusu `verify quick` içinde (aşağı).
- Mock yolu: seçenekler/kilit/etki metni/gönderim -> öğe sonraki tick'te kalkar/ret nedeni/geç ret olayı/seçeneksiz öğede düğme yok/dokunmatik >= 44.
- Gerçek sim yolu (`agenda_real_sim_test`): yerinden edilmeli yol -> PE-01 öğesi, kartlar sim'in seçenekleriyle birebir, düğme -> gerçek komut, öğe bir tick sonra `agenda_items()`tan çıkar.
- Pencereli kareler (masaüstü 1440x900, iPad dikey 1024x1366 touch): `/private/tmp/claude-501/agenda_respond_screens/` (MOCK veri, sayılar sahte).

VARSAYILAN:
- Gönderimde kabul = "kuyrukta"; gerçek uygulanma sonucu bir sonraki tick'te öğenin kalkmasıdır (gerçek sim testi öğenin kalktığını doğrular, etkilerin zamana yayıldığını UI göstermez).
- Etki önizlemesi yönü sim'in `direction` işaretidir; "Memnuniyet azalır" vb. metinleri bu işarete bağlı.
- Gerçek-sim testinde kilitli seçenek yolu: o dünyada kilitli seçenek yoksa test erken çıkar (kilit yolu mock testinde doğrulanır).

TEST EDİLMEDİ:
- Fiziksel iPad dokunma (yalnız touch profil boyutu + masaüstünde touch profilli kare).
- Gerçek `playable.tscn` penceresinde gündem paneli (kareler ui_lab MOCK ile).
- `bloc.satisfaction`/`media.tone`/`council.friction` hedeflerinin gerçek sim'de görünüşü (yalnız PE-01 gerçek dünyada sınandı; metinler tüm hedefler için var).
- Etki başlangıcından sonra "bekleyen etkiler" izlemesi (sözleşmede sorgu yok; ayrı iş).
- `tools/verify.sh quick`: bkz. kapanış.

## Kapanış (devam oturumu)
Dal güncel tabanla (60453b3) birleştirildi, çatışma yok. Yeniden koşuldu: agenda_facade_adapter (13), agenda_real_sim (6), decision_panels (28), reaction_texts (6): 0 hata/0 başarısız; gdlint temiz. `tools/verify.sh` bu oturumda KOŞULMADI.
