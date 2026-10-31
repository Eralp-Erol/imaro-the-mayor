# T-042b · Gündem sözleşmesi (PE-01 gündemde görünsün) — 2026-10-31

REQ: CAN-03, SIM-05, SIM-12, TEK-01/02 · Karar: D-008 ("halk tepki versin" -> gündemde gör), D-011 · Spec: `design/specs/core-loop-v0.md` adım 4 (4:30-5:00) · Kaynak sorun: `2026-10-31-tepki-ui-metinleri.md` "Açık" / `2026-10-31-tepki-nedensellik.md`.
`tools/verify.sh` koşturulmadı (görev gereği); push yok. `src/world/**` ve `src/game/playable.gd` dokunulmadı (playable.gd 1000 satır, değişmedi).

## Yapılan
**Sözleşme (ADR-0005 Ek F, "Gündem öğeleri sorgusu" maddesi):**
- `SimFacade.agenda_items() -> Array[AgendaItemView]`: soyut OLMAYAN, varsayılan boş (eski/mock uygulamalar çalışır, uydurma öğe yok). Yalnız AÇIK öğeler, kimlik artan, değer kopyası, salt okunur.
- Yeni DTO `src/contracts/agenda_item_view.gd`: `provenance, item_id, template_id (PE-01/PE-04…), delivery, status, region_code, group (ActorRef|null), opened_tick, deadline_tick, title_key, args {topic, stage}, reason_ids, cause_refs`; `ref() = agenda.<id>` (`SimContract.REF_AGENDA`). Toplam skor alanı yok. Seçenek alanı YOK (aşağıda).
- `SimContractChecks.check_agenda/check_agenda_items` (`check_facade` içinde) + `observable_state.agenda`.
- Mock: senaryo etkisi `type: "agenda"` (`item`, `reason_labels`, `expires_after`); `mock_scenario_expropriation.json` yol onayından sonra PE-01 öğesini açar (sahte sayılar). Geri alma öğeyi kaldırmaz (D-011).
- **Sürüm kararı: 1.5 KALIR** (isteğe bağlı ek). Gerekçe: yeni yöntem varsayılanlı (1.5 okuyan güvenle çağırır); 1.5 hâlâ açık tren (dünya/oyun/UI adımları uygulanmadı, 1.5 tüketicisi yok); `VERSION == "1.5"` kilitleyen iki mevcut test korunur. Ek E/G yeni sorgulara MINOR vermişti; 1.5 yayımlanınca benzer ek 1.6 olur. Karar `technical-director` isterse 1.6'ya çevrilmesi tek satır + iki test.

**Sim (SimFacadeImpl):** `PoliticsQuery.agenda_views` (olay motorunun açık öğeleri: `title_key` = şablon `reason_key`, `reason_ids` = ateşleme gerekçesi hâlâ saklanıyorsa, `cause_refs` = ateşleme gerekçesinin ebeveyn kayıtlarındaki `command.N`/`parcel.N` konuları) -> `PoliticsSnapshot.agenda_items` -> `SnapshotProvider.agenda_items` (varsayılan boş) -> `SimFacadeImpl.agenda_items`. YENİ DURUM YOK: tick/hash/kayıt yolu değişmedi; yeni öğe yalnız olay motoru zaten açtığında görünür.

**UI bağdaştırıcısı (ince):** `AgendaModel.derive_all(facade, snapshot)` = mevcut `derive` (meclis oylamaları) + facade öğeleri (tür `displacement` gerekçe zincirinde hane sayısı varsa, yoksa `event`; seçenek/erteleme yok). `AgendaPanel` varsayılan yolu ve `DecisionPanels._update_agenda` (rozet + otomatik duraklatma) `derive_all` kullanır (1 satır değişim). Panelde: meclis kurulu değil ama facade öğesi varsa "kurulmadı" demez; "yalnız meclis oylaması" notu yalnız öğelerin hepsi oylama iken görünür. Yeni UI metni EKLENMEDİ (`agenda.kind.displacement`, `agenda.displacement.*`, `event.pe01.reason` zaten vardı).

## Testler
Yeni (4 dosya, 25 test): `tests/contracts/agenda_item_contract_test.gd` (9: varsayılan boş, JSON gidiş-dönüş, mock paritesi, değer kopyası/okuma hash'i değiştirmez, geri alma öğeyi silmez, denetim ihlalleri, skor alanı yok), `tests/sim/politics/agenda_items_test.gd` (8: gerçek sim; siyasetsiz facade boş, kamulaştırmasız PE-01 yok, PE-01 alanları, `cause_refs` komut+parsel ve ebeveyn = neden kaydı, `check_facade` temiz, okuma hash'i değiştirmez [ikiz koşu 14+30 gün], kapanan öğe listeden çıkar, kayıt yükleme aynı öğeler), `tests/ui/agenda_facade_adapter_test.gd` (5), `tests/ui/agenda_real_sim_test.gd` (3: GERÇEK sim PE-01 -> `derive_all` -> panel "Yol yüzünden N hane yerinden edildi." + "Nedenini gör"; N = `public_works()[0].displaced_households`).
Mevcut test düzeltmesi: `tests/sim/public_works/expropriation_commands_test.gd::test_the_mock_reaction_reason_uses_the_factor_names_the_real_cause_record_writes` iki dalın birleşiminde (ef25f5c) ZATEN kırıktı (UI fixture'ı `bloc.react` etkenlerini de taşıyor; test tüm `reason` etkilerini neden kaydı sanıyordu). Yalnız `decision.bloc.expropriation_cause` kaydını ve `FACTOR_COUNT`u denetleyecek ve `checked > 0` isteyecek biçimde daraltıldı; kodum değil, birleşme kaynaklı. Ayrıca `tests/ui/reaction_texts_test.gd` başlık yorumu güncellendi.

## DOĞRULANMIŞ (çalıştırıldı)
- Kırmızı -> yeşil: yeni testler önce ayrıştırma hatasıyla düştü (tür/yöntem yok), uygulamadan sonra 25/25 geçti. Mutasyon: `PoliticsSnapshot.agenda_items` geçici `return []` yapılınca gerçek-sim testlerinin 7'si düştü (test sahte yeşil değil), geri alındı.
- GdUnit (doğrudan): `tests/contracts + tests/ui + tests/sim/politics + tests/sim/public_works/expropriation_commands_test.gd`: **700 test, 0 hata, 0 başarısız**, 20 sahipsiz nesne (eski, çıkış 101 = yalnız uyarı). Önceki geniş koşu `tests/sim + tests/unit + tests/app + tests/game`: **1008 test**, tek başarısız yukarıdaki birleşme kırığı (düzeltildi, yukarıdaki koşuda yeşil). `tests/sim/m2_query_test.gd` (GOLDEN A/B), `sim_purity_test`, `sim_facade_impl_test`, politika determinizm/kayıt, `contract_purity_test` bu koşularda değişmeden geçti.
- `gdlint` (gdtoolkit 4.5.0): `src/contracts src/sim src/ui/flows tests/contracts tests/sim/politics` + yeni UI testleri + değişen testler: "no problems found" (mock_sim_facade'e `max-public-methods` kapatma satırı eklendi; SimFacade'de zaten var).
- CAN-03: gündem yolu özel bina yaratmaz (okuma sorgusu, komut yok); yeni durum/hash yok.

## VARSAYILAN (kodda var, bağımsız kanıt yok)
- Sürüm 1.5 kalır (yukarıdaki gerekçe); tasarım/teknik direktör onayı yok.
- Facade öğesinin türü yalnız gerekçe zincirinde hane sayısı varsa `displacement`; PE-04 (medya) öğesi `event` olarak görünür ve etiketsizdir (UI `agenda.kind.event` metni yok; kasıtlı, metin uydurulmadı).
- Gündem satırı süre metni yanıtsız öğe için mevcut "Sonuç N gün içinde" (`council.closes_in`): PE-01 için kelime seçimi tasarım onayı görmedi.
- `args.topic/stage` ham sim değeri; UI şimdilik kullanmıyor.

## TEST EDİLMEDİ / AÇIK
- `verify quick/full` (görev gereği koşulmadı); pencereli çalışma, ekran görüntüsü, 480/1600 düzeni, iPad dokunma; `playable.tscn --demo` ile PE-01 yerinden edilme öğesinin gündem rozetinde (üstteki sayaç + otomatik duraklatma) gerçekten görünmesi (rozet yolu `derive_all` ile bağlandı, yalnız birim testli).
- **Yanıt yolu yok:** `agenda.respond` komutu `SimCommand` kataloğunda değil; oyuncu PE-01 öğesine "dinleme/telafi/geri alma/ertele" seçeneklerini UYGULAYAMAZ, yalnız görür ve "Nedenini gör" ile gerekçeyi açar. D-008 "gündemde gör" için yeterli; "yanıt ver" ayrı MINOR iş (katalog + seçenek DTO + UI kartları; CAN-03 testi gerekir).
- Büyük dünyada `agenda_items()` maliyeti (öğe başına iki `peek`; öğe sayısı <= ~32 kapalı + açık, ihmal edilebilir ama ölçülmedi).
- `PoliticsQuery.agenda_views` başlık anahtarı şablonun `reason_key`i: PE-01 dışı şablonların UI metni `event_text_coverage_test` kapsamında; yeni şablon eklenirse metin gerekir.

## Dal / commit
Dal `worktree-agent-acb8bfe8dbe1f986f` (`agent/handover-imaro-m01-349562fb` ef25f5c üstüne). Commit hash'i aşağıdaki "Commit" satırında / teslim mesajında.
