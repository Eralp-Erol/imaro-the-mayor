# 2026-10-31 · İmar planı meclis eşiği (D-011 Soru 4: "ikisi de, seçenek")

Kullanıcı kararı: küçük planlar doğrudan (birkaç gün sonra yürürlük), BÜYÜK planlar meclise. Eşik/usul kullanıcı tarafından belirtilmedi: sayılar ÇALIŞMA DEĞERİ, kanon değil (D-011 ajan notu).

## Ne yapıldı
- **Karar kuralı** (`PoliticsGate.requires_vote_for`): `requires_council.zoning.propose=false` -> hiçbir plan meclise gitmez. `true` ve eşikler kapalı (ikisi de 0/yok) -> eski davranış, her plan meclise. `true` ve eşik etkin -> plan BÜYÜKSE meclise: parsel sayısı >= `plan_council_min_parcels` YA DA önizleme toplam birimi >= `plan_council_min_units` (birim = `EconomySystem.plan_preview`, yatırımcıyla aynı formül; yoğunluk/yükseklik parametreleri dahil).
- **Veri**: `council` bölümüne isteğe bağlı iki alan (`PoliticsConfig`, 0..sınır doğrulaması). `data/politics/council.json` DEĞİŞMEDİ (alan yok = kapalı). Oynanabilir yama `data/game/playable_politics.json`: `zoning.propose=true`, `plan_council_min_parcels=10`, `plan_council_min_units=40` (gerekçe dosyada `_plan_council_note`: gerçek Ismeral ölçümü 12 parsel = 51 birim, ~4 birim/parsel; tipik oyuncu planı 8 parsel altında kalır). `PlayablePolitics.config()` iki anahtarı kopyaya uygular.
- **Facade**: `ProposalGate.requires_vote_for(state, kind, params)` (varsayılan = tür kuralı); `ZoningProposeHandler` ve `SimFacadeImpl.plan_preview` bunu kullanır -> `PlanPreviewView.council_required` artık O PLANIN gerçek kararı. `PoliticsBootstrap` kapıya ekonomiyi verir (birim ölçütü için).
- **Nedensellik (SIM-12)**: eşik etkinken meclise giden planın oylama kaydına `proposal.route = {reason: "plan.council_large", parcels, units, min_parcels, min_units}` yazılır. Eşik kapalıyken bu anahtar yazılmaz (kayıt/oylama biçimi eski ile aynı).
- Ret yolu mevcut mekanizma: `event.zoning.plan_rejected` + `plan_rejected` durumu (T-043A), değişmedi.
- `precheck` (bekleyen oylamalı parsele yeni teklif reddi) bayrağa bakar, plan boyutuna değil: küçük plan bekleyen oylamalı parsele de reddedilir (oylama sonradan üzerine yazmasın).
- ADR-0005 oynanabilir kurulum satırı güncellendi.

## Değişen dosyalar
`src/sim/politics/{politics_config,politics_gate,politics_bootstrap}.gd`, `src/sim/facade/{proposal_gate,zoning_propose_handler,sim_facade_impl}.gd`, `src/game/playable_politics.gd`, `data/game/playable_politics.json`, `docs/adr/0005-sim-view-ui-contracts.md`, `tests/sim/politics/plan_council_threshold_test.gd` (yeni, 10 test), `tests/game/playable_politics_test.gd`.

## Doğrulanmış (çalıştırıldı)
- Yeni suite önce KIRMIZI (doğrulayıcı bilinmeyen alanı reddediyordu), sonra `plan_council_threshold_test.gd` 10/10 yeşil: eşik altı doğrudan (oylama yok, `council_required` false), eşik/üstü meclise + `route` kaydı, meclis reddi -> `plan_rejected` + olay + `approvals == 0` (CAN-03), birim eşiği önizleme toplamına göre, bayrak false -> hiç meclis, eşik 0/yok -> eski davranış (ekonomi + oylama kaydı eşit, `route` anahtarı yok), eşik açık küçük plan == meclissiz koşu (ekonomi + oylama kaydı), bekleyen oylama küçük planı da engeller, aynı tohum iki koşuda aynı `state_hash` + kayıt/yükleme (açık oylamayla) bit-eşit, geçersiz eşik değerleri (-1, "3", 2.5, true) doğrulayıcıda reddedilir.
- `tests/game/playable_politics_test.gd` 4/4: oynanabilir yapılandırma geçerli ve eşikli, sim varsayılanında eşik kapalı ve paylaşılan JSON bozulmaz, 1 parsel direkt, 10 parsel meclise + ret kaydı.
- `tests/sim` + `tests/game` + `tests/contracts` birlikte: **979 test, 0 hata, 0 başarısız** (GOLDEN_A/B `tests/sim/m2_query_test.gd` dahil: sim varsayılanı bit-bit aynı). `data/politics/council.json` hiç değişmediği için siyaset `config_digest` de aynı.
- UI: `plan_flow_test`, `zoning_flow_model_test`, `decision_panels_test` birlikte 59/59 yeşil (UI'a dokunulmadı).
- `gdlint src tests`: Success, sorun yok.
- `verify` koşturulmadı (görev gereği).

## Varsayılan / bilinen sınırlar
- **Not**: `state_hash` siyaset `config_digest`ini (ham veri) içerir; yani aynı koşu `plan_council_min_*=0` anahtarını AÇIKÇA eklenmiş veriyle farklı özet verir. Bu yüzden `council.json`'a anahtar eklenmedi (GOLDEN korunur) ve eşitlik testleri tam hash yerine ekonomi durumu + oylama kaydıyla karşılaştırır.
- Eşik sayıları (10 parsel / 40 birim) çalışma değeri; gerçek dünyada birim/parsel ~4 ölçüldü ama dengeyi/oyun hissini kullanıcı sınamadı.
- Birim ölçütü ekonomi kuruluysa ve `plan_preview` ok ise sayılır; ekonomi başlamamışsa birim 0 (yalnız parsel eşiği çalışır).
- Küçük planın "neden doğrudan" kaydı ayrıca tutulmaz (oylama yok = yol yok); yalnız meclise giden planda `route` yazılır.

## Test edilmedi
- Gerçek Ismeral dünyasında (playable sahnesi) büyük plan -> meclis uçtan uca oynanmadı; yalnız fixture dünyasında sim testi + 12 parsel birim ölçümü (probe, `--order=plan_only`).
- Görsel/HUD kontrolü yok (UI dokunulmadı).

## UI için kalan iş (src/ui/** başka ajanda)
- `ZoningFlowModel.council_required()` **boş seçimle** `plan_preview(PackedInt64Array(), &"")` çağırır; yeni kuralda boş plan "küçük" sayılır, yani `council_required` false döner ve oynanabilirde yol metni hep "Planı sun/doğrudan" olur (eski oynanabilir davranışla aynı, gerilemez ama büyük plan için yanlış beklenti). Düzeltme: seçim varsa `preview().council_required` kullan ("Meclise sun" yalnız o plan için). Buton/yol metni plan boyutuna göre değişebilir.
- Plan sonuç metinleri meclis yolunu mevcut olay/durumlardan gösteriyor (`council.vote_opened` -> oylama aşaması, `plan_rejected` ret metni, `vote_ref`); "neden meclise gitti" (büyük plan, eşik) metni YOK. `proposal.route` oylama sözlüğünde var ama `CouncilVoteView`/snapshot'a taşınmadı (sözleşme dosyası değiştirilmedi); "Bu plan büyük olduğu için meclise gitti (N parsel / M birim, eşik X/Y)" açıklaması için `PlanPreviewView`'e eşik alanları (örn. `council_min_parcels`, `council_min_units`) ve/veya oylama görünümüne `route` eklemek ayrı bir sözleşme işi (ADR-0005 ek) olarak açık.
- `data/ui/ui_config.json` `zoning.requires_council` yer tutucusu yalnız sim olmayan kaynak içindir; dokunulmadı.
