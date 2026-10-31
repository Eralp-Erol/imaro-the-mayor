# Gündem yanıtı: `agenda.respond` sözleşmeye bağlandı — 2026-10-31

REQ: CAN-03, SIM-05, SIM-08, SIM-12, TEK-01/02 · Karar: D-008 ("halk tepki versin"), D-011 · Spec: `design/specs/political-events.md` §1/§8 · Önceki: `2026-10-31-gundem-sozlesmesi.md` ("Yanıt yolu yok"), `2026-10-31-tepki-nedensellik.md`.
UI'ya DOKUNULMADI (`src/ui/**`, `src/game/**`, `src/world/**` aynı). `playable.gd` 1000, `economy_system.gd` 998 satırda, değişmedi. `data/politics/blocs.json` ve diğer veri dosyaları değişmedi (yeni veri/dosya yok). Push yok.

## Bulgu: sim'de yanıt yolu ZATEN vardı
`AgendaRespondHandler` (komut `agenda.respond`), `EventEngine.respond/check_response/option_views` ve `PoliticsBootstrap` kaydı T-017'den beri çalışıyor; yalnız `SimCommand.CATALOG`da yoktu, bu yüzden `facade.submit_command` `unknown_kind` diyordu (eski test bunu kilitliyordu). Yeni oyun mantığı yazılmadı; mevcut yol sözleşmeye bağlandı.

## Yapılan
- **Komut:** `SimCommand.KIND_AGENDA_RESPOND` + katalog `{item_id: int, option_id: StringName}` + `SimCommand.agenda_respond(item_id, option_id)`. Sürüm 1.5 KALIR (isteğe bağlı ek; artırma kararı technical-director'un).
- **DTO:** yeni `src/contracts/agenda_option_view.gd` (`AgendaOptionView {option_id, verb, label_key, available, locked_by, effects[{target, scope, direction -1|+1, delay_days, duration_days, curve}]}`); `AgendaItemView.options` (boşken `to_dict` anahtarı YAZMAZ: eski belge/hash bit-bit aynı).
- **Dürüstlük süzgeci (yeni, `src/sim/politics/agenda_options.gd`):** bir seçenek yalnız bu öğede gerçekten uygulanabilecek etkisi varsa listelenir. Etki "ölü" sayılır: konusuz öğede şikâyet/memnuniyet/medya etkisi, bölgesiz öğede yatırımcı riski, destekleyen kesimi olmayan `beneficiary_blocs`, protagonist/hedefi olmayan güven etkisi. Kapsam çözümü `EventEngine.scope_of` (= `_schedule`in kullandığı AYNI çözüm). `defer` etkisizdir: listelenmez ve komutla `invalid_value` / `why=option.no_effect` ile reddedilir (motor `EventEngine.respond` hâlâ kabul eder; eski motor testi aynı). Kilitli seçenek (yetki yok) canlı etkisi varsa gizlenmez: `available=false`, `locked_by`.
- **Ret kodları:** bilinmeyen öğe `invalid_target {ref}`; kapalı öğe `precondition {why: agenda.closed}`; listede olmayan seçenek `invalid_value {param: option_id}`; kilitli `precondition {why: authority.locked, authority}`; şekil hataları ortak (`missing_param`, `bad_param_type`, `invalid_value`, `unknown_param`); siyaset kurulu değilse `precondition {why: system.not_built, system: agenda}` (`SimFacadeImpl.create` siyaset işleyicisi yoksa `UnbuiltCommandHandler` takar; `PoliticsBootstrap` yolunda değişiklik yok).
- **Okuma:** `PoliticsQuery.agenda_views` → `options` (salt okunur; okuma hash'i değiştirmez, test var).
- **Denetim:** `SimContractChecks.check_options` (`check_agenda_items` içinde): kimlik/etiket dolu, yinelemesiz, etkisiz seçenek yok, kilit tutarlı, etki yönü ±1, süreler >= 0, toplam-skor anahtarı yok.
- **Mock:** `MockSimFacade` aynı ret kodlarını verir (hedef yok / kapalı / listede yok / kilitli); geçerli yanıt öğeyi kapatır ve `command.applied` (konu `agenda.N`) yayımlar; mock sayı/etki UYDURMAZ. `tests/fixtures/mock_scenario_expropriation.json` PE-01 öğesine üç seçenek (biri kilitli) eklendi.
- **Belge:** `docs/adr/0005-sim-view-ui-contracts.md` Ek F'ye "Gündem yanıtı" maddesi; `sim_contract.gd` başlık notu.
- **Veri/durum:** yeni durum yok (yanıt kuyruğu/etki kuyruğu zaten `PoliticsState`te, ilk yanıtta dolar); yeni veri dosyası yok. Seçenek içerikleri `data/politics/events/*.json`dan.

## Testler (yeni/değişen)
- Yeni `tests/contracts/agenda_respond_contract_test.gd` (16): katalog/şekil/JSON, DTO gidiş-dönüş, değer kopyası, denetim ihlalleri (8 bozuk biçim), mock ret kodları/kapanış/determinizm/CAN-03.
- Yeni `tests/sim/politics/agenda_respond_facade_test.gd` (22): gerçek sim seçenek listesi (defer yok), önizleme = veri, ölü etki süzülür, kilitli seçenek, okuma hash'i değiştirmez, komut sınırda uygulanır ve öğe kapanır, yanıtlı/yanıtsız ikiz (güven artar), kuru koşu, ret kodları (durum değişmez), kapalı öğe, çift yanıt, şekil hataları, siyasetsiz facade, aynı komut aynı hash + farklı seçim farklı hash, kaydet/yükle (etki kuyruğu doluyken ve komut kuyrukta iken) kesintisiz koşuyla aynı, CAN-03 (3 seçenek x 240 gün; komut tick'inde parseller ikizle aynı; sim binası olan her parselde yatırımcı kararı kaydı; alınan parseller `taken` kalır; olay konuları yalnız `agenda.`/`command.`).
- Değişen: `tests/sim/politics/event_response_test.gd` ("katalogda yok" testi → "katalogda ve facade'tan geçer"); `tests/sim/economy/economy_sim07_can03_test.gd` (katalogdaki HER komut için örnek ister: `agenda.respond` örneği eklendi).

## DOĞRULANMIŞ (çalıştırıldı)
- Kırmızı → yeşil: testler önce ayrıştırma hatasıyla düştü (`AgendaOptionView`, `KIND_AGENDA_RESPOND`, `agenda_respond` yok), uygulamadan sonra yeşil.
- GdUnit doğrudan: `tests/contracts + tests/sim + tests/ui`: 1378 test; tek başarısız `economy_sim07_can03_test::test_every_catalog_command_leaves_development_to_actor_decisions` (katalog yeni komut için örnek ister) → örnek eklendi, o suite yeniden: 14/14 yeşil. `tests/unit + tests/app + tests/game + tests/view`: 602 test, 0 hata/başarısız. Son: `tests/sim/politics + tests/contracts + can03 + m2_query_test`: 371 test, 0 hata/başarısız (GOLDEN A/B `m2_query_test` dahil, değişmeden geçti).
- Mutasyon denemeleri (her biri düştü, geri alındı): (1) `_is_live` her zaman true → 3 başarısız (ölü etki / defer listelendi); (2) işleyicide etkisizlik denetimi kapalı → 2 başarısız + 1 hata; (3) siyasetsiz facade'ta `UnbuiltCommandHandler` kapalı → 1 başarısız; (4) `apply` hiçbir şey yapmaz → 7 başarısız; (5) mock'ta kilit denetimi kapalı → 2 başarısız; (6) CAN-03: işleyici `apply` içinde bir parselin `units/stage` sütununu yazar → 6 başarısız (ikiz karşılaştırma testi dahil). Not: ilk CAN-03 mutasyonu (Packed dizisini kopyaya yazan) etkisizdi ve testler geçti; Packed dizileri değer tipi olduğundan mutasyon düzeltilince (geri yazarak) yakalandı, yani test ikizi gerçekten bir şey sınıyor. Ek: dünyada boş parsel kalmadığı için "yanıt bina doğurmaz" sınaması yalnız var olan parsel sütunlarının ikizle birebir aynılığına ve yatırımcı kararı kaydı denetimine dayanır.
- gdlint (gdtoolkit 4.5.0): `src/contracts src/sim tests/contracts tests/sim/politics` temiz; `tests/sim/economy/economy_sim07_can03_test.gd` değişikliği tek satır.

## VARSAYILAN (kodda var, bağımsız kanıt yok)
- Sürüm 1.5 kalır (önceki ek ile aynı gerekçe); direktör onayı yok.
- Önizleme "yön" = etki büyüklüğünün işareti (hedef değere göre): `bloc.grievance` -1 = şikâyet azalır, `investor.political_risk` +1 = risk artar. Büyüklük sayısı bilerek verilmez (sahte kesinlik yok, spec §8 "beklenen yön").
- Liste yalnız çağrı anındaki duruma göre süzülür; komut uygulanma tick'inde durum değişmişse `command.rejected` olayı gelir (test var).

## TEST EDİLMEDİ / AÇIK SINIRLAR
- `tools/verify.sh quick` aşağıdaki "Kapanış" satırında; `full` koşulmadı (milestone işi). Pencereli çalışma, ekran görüntüsü, gerçek `playable.tscn` akışı yok (UI'ya dokunulmadı).
- **Bedel yok:** şablonlardaki `costs` (siyasi sermaye, bütçe, `time_days`) sim'de DÜŞÜLMÜYOR; bu yüzden DTO'da bedel alanı yok. UI "Telafi: 500 bütçe" gibi bir bedel YAZMAMALI.
- **"Kararı gözden geçir" (`reverse`) yolu GERİ ALMAZ:** etkisi yatırımcı riskini artırmak + destekleyen kesimlerin memnuniyetini düşürmek; yol/parseller geri gelmez (o iş `public_work.undo_last`). PE-01 yerinden edilme dünyasında destekleyen kesim yoksa yalnız risk etkisi listelenir. Etiketin ("gözden geçir") gerçek etkiyle uyumu `design-director`/`ui-engineer` kararı.
- `defer` ("Ertele") listelenmez: sim'de etkisiz (öğe zaten açık kalır, süre dolumu sürer). UI "daha sonra" için düğme koymak istiyorsa bu bir panel kapatma davranışıdır, sim komutu değil.
- Yanıtlanan öğe açık listeden çıkar (`resolved`); "bekleyen etkiler" listesi/sonuç izlemesi (spec §8) için sözleşmede sorgu YOK (etki kuyruğu `PoliticsState`te, facade'a açılmadı) — ayrı iş.
- Yalnız PE-01 gerçek dünyada sınandı; PE-02/03/04/07 seçenekleri aynı süzgeçten geçer ama bu görevde gerçek-sim sözleşme testi yok (motor testleri var).
- `src/ui/flows/agenda_model.gd:69` yorumu hâlâ "agenda.respond komutu yok" diyor (UI alanı, değiştirilmedi).

## UI'ya devredilecek (ui-engineer)
`SimFacade.agenda_items()[i].options` → her `AgendaOptionView` için bir kart/düğme: metin `label_key` (`event.pe01.opt.listen|remedy|reverse` zaten `data/ui/strings.tr.json`'da); `available == false` ise kilitli göster, nedeni `locked_by` (yetki anahtarı; metni UI tanımlar); önizleme `effects` (hedef, yön, gecikme, süre; sayı yok). Gönderim: `facade.submit_command(SimCommand.agenda_respond(item.item_id, option.option_id))`; ret nedeni `CommandResult.reason_key` + `args.why` (`authority.locked`, `agenda.closed`, `system.not_built`, `option.no_effect`). Başarıda öğe bir sonraki tick'te listeden çıkar; etkiler zamana yayılır. `options` boşsa yanıt düğmesi gösterme.

## Kapanış
Dal `worktree-agent-a86e411e8baeeebc6`; commit hash'i teslim mesajında.
