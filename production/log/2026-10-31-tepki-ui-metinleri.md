# T-042b · Tepki / yerinden edilme UI metinleri — 2026-10-31

REQ: CAN-03, SIM-09, SIM-12 · Karar: D-011 · Girdi: `2026-10-31-tepki-nedensellik.md`, `2026-10-31-kamulastirma-ui.md`.
`verify` koşturulmadı (görev gereği); push yok. `src/sim`, `src/world`, `playable.gd` dokunulmadı.

## Yapılan
1. **Metinler** (`data/ui/strings.tr.json`, +20 anahtar): `decision.bloc.expropriation_cause.positive|negative`; gerçek tepki kararı `decision.bloc.react.petition|protest|boycott.positive|negative` ("Grup dilekçe verdi / protesto etti / boykota gitti" ve olumsuzları) ve `decision.bloc.support.*`; `reason.factor.displaced_household_count` ("Yerinden edilen hane sayısı"); `bloc.react` etken adları (`grievance_level`, `satisfaction_level`, `media_amplification`, `organizer_capacity`, `trust_in_player`; bunlar gerçek sim kaydında vardı ama metinsizdi); `reason.count_value`; gündem: `agenda.kind.displacement`, `agenda.displacement.households`, `agenda.displacement.why`. `displaced_households` ve `road_proximity` metinleri zaten vardı.
2. **Gerekçe paneli** (`reason_panel.gd`): `displaced_household_count` etkeni sayım olarak çizilir ("11 hane (sayım; karar hesabına girmez)"); aksi halde sabit nokta formatı "0,01" yazardı (değer hane sayısı, binde sinyal değil).
3. **Gündem** (`agenda_model.gd`, `agenda_panel.gd`): öğenin `reason_ids` zincirinde (en çok 4 basamak ebeveyn) `displaced_household_count` etkenini arar; bulursa "Yol yüzünden N hane yerinden edildi." + "Nedenini gör" (gerekçe panelini zincirle açar). Kayıtta sayı yoksa satır ve düğme ÇIKMAZ.
4. **Fixture** (`mock_scenario_expropriation.json`): eski `decision.group.protest` kaldı; yerine gerçek yapı: neden kaydı `decision.bloc.expropriation_cause` (yerinden edilme 40 x 700, yakınlık 20 x 300 tahmin, sayım 11 x 0, eşik 10) + `decision.bloc.react.protest` kaydı (ebeveyn = neden), `GroupReactionView.reason_ids = [neden, tepki]`, şerit olayı tepki kaydına bağlı. Sayılar MOCK/SAHTE.
5. **Test**: yeni `tests/ui/reaction_texts_test.gd` (6 test): metin anahtarları var; sayım "11 hane" olarak görünür; tepki kaydı "Grup protesto etti" gösterir ve ebeveyn zinciri nedene iner; `reason_ids[0]` neden kaydı; gündem öğesi sayıyı neden kaydından okur ve "Nedenini gör" düğmesi tepki zincirini açar; sayı yoksa uydurma satır/düğme yok. Mevcut `expropriation_ui_test` değişmeden geçti (olay metni "halk tepkisi şeritte").

## Sim alanları
Gerekçe: `ReasonRecord.decision_key/outcome/factors[name_key,value,weight,is_estimate]/parent_ids`; gündem hane sayısı: `ReasonFactor(reason.factor.displaced_household_count).value`; tepki: `GroupReactionView.reason_ids/cause_refs`.

## DOĞRULANMIŞ (çalıştırıldı)
- GdUnit doğrudan: `tests/ui` + `tests/contracts` + `tests/game/{road_draw_tool,road_draw_flow,can03_guard,honest_zoning}_test`: **517 test, 0 hata, 0 başarısız** (20 sahipsiz nesne uyarısı, eski testlerden). İlk koşuda `strings_table_test` benim "puan" kelimem yüzünden düştü (yasak kelime), düzeltildi.
- `gdlint` (gdtoolkit 4.5.0): agenda_model, agenda_panel, reason_panel, reaction_texts_test: sorun yok.

## VARSAYILAN
- Gerçek sim kararının `decision_key`i `decision.bloc.react.<basamak>` (ADR Ek F + `ActorDecision` kodundan okundu); gerçek `SimFacadeImpl` ile çalıştırıp metinlerin çözüldüğü doğrulanmadı.
- Bloc.support'un `decision.bloc.support` anahtarı kodda tiersiz okundu, aynı varsayım.
- Kullanıcıya görünen kelime seçimi ("dilekçe verdi", "boykota gitti") tasarım onayı yok.

## TEST EDİLMEDİ / AÇIK
- **Gündem sözleşme boşluğu:** `SimFacade` / `SimSnapshot` gündem öğesi (AgendaItemView) VERMİYOR; sim PE-01 öğesini açıyor ama UI onu okuyamıyor. `AgendaPanel` yalnız meclis oylamasından türetir. Etiket ve "Nedenini gör" yolu `item_provider` ile birim testli; gerçek PE-01 öğesinin gündemde görünmesi için sözleşme + bağdaştırıcı (sim/oyun ajanı, ADR-0005 sürüm kararı) gerekir. Bu adımda UYDURULMADI.
- Pencereli çalışma, ekran görüntüsü, 480/1600 düzeni, iPad dokunma; `verify quick/full`; gerçek sim ile PE-01 yerinden edilme etiketi.
