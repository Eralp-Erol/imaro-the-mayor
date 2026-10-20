# UX veri ihtiyaçları v0 (T-018 ölçüt 4) — SimFacade'dan gerekenler

Statü: ÇALIŞMA MODELİ (TEKNİK sözleşme isteği; kanon değil). Gerçek sözleşme `src/contracts/` (v1.0, contracts hattı, T-023) ve ADR-0005'tir; **çelişkide o kazanır**, bu belge uyarlanır. Aşağıda "v1.0 VAR" etiketli alanlar `src/contracts/` okunarak doğrulandı; "v1.1 TEKNİK istek" etiketliler henüz sözleşmede YOKTUR ve UI bunlara bağımlı kod yazmadan önce sözleşmeye girmesi beklenir (yoksa bölüm gizlenir). UI sim'e **yazmaz**, yalnız `SimFacade` üzerinden okur ve `SimCommand` gönderir. Hiçbir alan platform profiline bağlı değildir (PLT-04).

Genel ilkeler:
1. **Anahtar + argüman, hazır metin değil.** Her açıklayıcı alan `*_key` (string anahtarı) + `args` sözlüğü. Para tutarı birimsiz tamsayı (`Q-003`).
2. **`is_estimate: bool`** her tahmin/öngörü/anket değerinde. UI "tahmin" etiketler; sim vermiyorsa UI hesaplamaz.
3. **`available: bool` / kurulmamış sistem**: DTO `null`/`available=false` döner; UI bölümü gizler ya da `*.not_built` yazar.
4. Her nesne **kararlı ID** (`ref = {kind, id}`) taşır; "Haritada göster" için dünya konumu `WorldData` koordinatından (UI konum uydurmaz).
5. **Mock:** `SimFacade.is_mock() -> bool` (HUD rozeti). `MockSimFacade` aynı DTO şekillerini üretir.
6. Okuma anlık görüntüden (`SimSnapshot`), olaylar `SimEvent` ile; UI sim tick'ini sürmez, kare hızından bağımsızdır.

## 1. Ortak DTO'lar (istek)
| DTO | Alanlar | Not |
|---|---|---|
| `SimSnapshot` (**v1.0 VAR kısmen**) | `clock`, `budget`, `council`, `group_reactions`, `last_event_seq`, `parcel_count`, `extensions`, `is_mock()`. `record`/`election` yok: **v1.1 TEKNİK istek** (şimdilik `extensions`) | kurulmamış sistem = alan boş/varsayılan; UI `*.not_built` yazar |
| `ClockView` (**v1.0 VAR kısmen**) | `tick`, `speed`, `available_speeds`, `is_paused()`. `day/year` sözleşmede YOK: **v1.1 TEKNİK istek** (takvim AÇIK, `tick`ten türetim sim'in işi) | G akışı; tarih alanı gelene dek `clock.date_ingame` gösterilmez, yalnız tick/gün sayacı varsa o |
| `ReasonRecord` (**v1.0 VAR**) | `id`, `tick`, `actor:ActorRef`, `decision_key` (karar metin anahtarı, örn. `decision.investor.develop`), `outcome` (`positive`\|`negative`: karar eylemi GERÇEKLEŞTİ / gerçekleşmedi), `factors:Array[ReasonFactor]`, `threshold`, `score`, `scoring` (`linear`), `subjects:PackedStringArray` (`parcel.12`…), `parent_ids:PackedInt64Array`, `provenance`. Değişmez: `score == Σ katkı`, `outcome` ⇔ `score >= threshold` | SIM-12 çekirdeği. UI başlığı `decision_key` + `outcome` birleşiminden anahtar türetir (`reason.outcome.*` UI eşleme tablosu: karar anahtarı × positive/negative; UI `match` yazmaz, veri tablosu) |
| `ReasonFactor` (**v1.0 VAR**) | `name_key` (→`reason.factor.<..>`), `value:int`, `weight:int` (sabit noktalı; katkı = `contribution()`), `is_estimate:bool`, `source_ref:StringName` | Yön (lehte/aleyhte) UI'da **katkı işaretinden** türetilir (`contribution()` ≥ 0 lehte); sim ayrı alan vermedikçe UI yön uydurmaz |
| **v1.1 TEKNİK istek** (ReasonRecord) | `summary_key` + `summary_args` (kısa gerekçe cümlesi), `cause_refs` (zincirin dışındaki neden varlıkları), `expires_tick?` | Hepsi isteğe bağlı; yoksa UI etken listesinden özet kurar, uydurmaz |
| **v1.1 TEKNİK istek** (ReasonFactor) | `direction` (−1/+1, açık yön), `trend` (−1/0/+1), `args:Dictionary` | `trend` yoksa `a11y.trend_*` göstergesi gizlenir; `reason_history` ile UI iki kayıt karşılaştırıp eğilim türetebilir (hesap açıkça "UI türetimi" etiketli değil, gizli kalır) |
| `Ref` | `kind:StringName` (parcel, district, group, proposal, road, facility, council_bloc), `id` | |
| `SimEvent` (**v1.0 VAR**) | `seq`, `tick`, `kind`, `actor`, `subjects`, `message_key`, `args`, `reason_ids`, `command_id`, `provenance` | bildirim şeridi. Önceki istekteki `text_key`/`subject`/`reason_id`/`severity` sözleşmede `message_key`/`subjects`/`reason_ids`; `severity` **v1.1 TEKNİK istek** (yoksa şerit sırası `seq`) |

## 2. Akış bazında istekler
Bu tablo **istek dilidir (v1.1 TEKNİK istek, aksi belirtilmedikçe)**; v1.0 karşılıkları farklı adlıdır ve hizalanacaktır: `ParcelView.zoning{…}` ↔ v1.0 `zone`/`pending_zone`/`development`/`owner`/`land_value`/`reason_ids`; `ParcelView.district` ↔ `region_code`; `BudgetView.{income_total,expense_total,by_category}` ↔ `revenue`/`balance`/`lines[BudgetLineView]`/`pending_vote_id`; `CouncilView.seats` ↔ `seats_total`/`blocs`/`votes`; `GroupReactionView.complaints` ↔ `reaction`/`intensity`/`cause_refs`/`reason_ids`; `reason_id` ↔ `reason_ids`. Henüz sözleşmede olmayan alanlar (önizleme sorguları, `PlayerRecordView`, `ElectionView`, `ZoningOptions`, `DistrictView`) UI'da bölüm gizleme/`*.not_built` ile ele alınır.
| Akış | Okuma (View/Query) | Komut | Olay |
|---|---|---|---|
| **A Yol/kamu alanı çizimi** | `PublicWorkPreview{valid:bool, cost:int?, duration_days:int?, violations:Array[ReasonRecord], snapped_to:Ref?}` ← `SimQuery.preview_public_work(PublicWorkDraft)`; `BudgetView.balance`; yetki alanı: `ParcelView.in_authority:bool` | `DrawPublicWork{kind, class, polyline(WorldData koord.), draft_id}`; `CancelPublicWork{ref}` | `PublicWorkQueued`, `PublicWorkStarted`, `PublicWorkCompleted`, `CommandRejected{reason_id}` |
| **B İmar önerisi** | `ParcelView.zoning{use, density, max_height, conditions[]}`; `ZoningPreview?{capacity_load, investor_interest_estimate, is_estimate}` ← `SimQuery.preview_zoning(ZoningProposalDraft)`; izinli değer listeleri (`ZoningOptions`: kullanım/yoğunluk/yükseklik adımları — veri-odaklı) | `ProposeZoning{area:Array[parcel_id]|polygon, use, density, max_height, conditions}`; `ApplyZoning` (meclis gerekmiyorsa) | `ZoningDecided`, `InvestorReacted{reason_id}` |
| **C Denetçi** | `ParcelView{id, district, owner_kind(public/private), use, zoning, infra_access{kind→bool/level}, investor_interest?{level, last_decision, reason_id}, world_ref}`; `DistrictView{code, groups:Array[GroupReactionView], budget_share, open_complaints:int, population?}` | — | `ParcelChanged` |
| **D Nedensellik** | `SimQuery.reasons_for(Ref)->Array[ReasonRecord]`, `reason(id)`, `reason_history(Ref, from_tick)`; zincir `parent_ids` | — | `ReasonRecorded` |
| **E Meclis** | `CouncilView{seats:Array[{bloc_id, display_key, seats:int, stance:Enum, stance_reason_id?}], pending:Array[ProposalView], player_bloc_support:int, last_results}`; `ProposalView{id, kind, subject, vote_state, result?, reason_id?, retry_tick?}` | `SubmitToCouncil{proposal_id}`; oyuncu fiilleri (destek/taviz) **sim spec'ine bağlı, AÇIK** | `CouncilVoteResolved{proposal_id, outcome, reason_id}` |
| **F Bütçe** | `BudgetView{balance, income_total, expense_total, by_category:Array[{key, amount}], priorities:Array[{key, level}], service_capacity:Array[{service_key, capacity, used}], forecast?{...,is_estimate}, pending:Array[...], strain?:Enum}` | `SetBudgetAllocation{category_key, level|amount}` | `BudgetChanged`, `BudgetStrain{reason_id}` |
| **G Zaman** | `ClockView` | `SetSpeed{n}`, `TogglePause` | `SpeedCapped` |
| **H Sicil/seçim** | `PlayerRecordView{delivery, fiscal, service, equity, reputation_by_group:Array[{group_ref, value}], media_tone, ally_support:Array[{ref, value}]}` (**her gösterge ayrı alan; toplam alan YOK**), `GroupReactionView{group_ref, display_key, stance, complaints:Array[{key,args,reason_id}], size?}`, `ElectionView{stage, next_election_tick, days_left, poll?{low, high, is_estimate}, result?{by_group[], winner_ref, explain_reason_id}, defeated:bool}` | `Pledge{...}` / kampanya fiilleri **AÇIK** | `ElectionStageChanged`, `ElectionResult` |
| Bildirim | `SimEvent` akışı + `EventLog.recent(n)` | — | — |
| Yapılandırma | `economy.currency_symbol/name` (`¤`), `max_game_speed` (profil), `ZoningOptions` | — | — |

## 3. SimCommand sonucu
`CommandResult` (**v1.0 VAR**: `command_id`, `kind`, `status`, `reason_key`, `args`, `reason_ids`, `tick`, `apply_tick`); reddedilen komut gerekçe anahtarı + `reason_ids` verir (önceki istekteki `accepted/reason:ReasonRecord` bu biçime uyarlandı). UI tahmini yapıp "kabul edildi" göstermez; sonucu bekler (duraklıyken komut sıraya girer, `queued`).

## 4. Sözleşmeye v1.1 istekleri (özet)
1. `ReasonRecord`/`ReasonFactor` v1.0'a EK alanlar yalnız: `summary_key/args`, `cause_refs`, `expires_tick`, `direction`, `trend`, `args` (§1 tablosu). `parent_ids`, `weight`, `is_estimate` v1.0'da zaten VAR.
2. `*_preview` sorguları (`preview_public_work`, `preview_zoning`) — yan etkisiz, deterministik.
3. `SimFacade.is_mock()`, `SimSnapshot` içinde `?` ile kurulmamış sistemler (`available`).
4. `ParcelView`/`DistrictView`/`GroupReactionView`/`BudgetView`/`CouncilView` alanları §2'deki gibi; `PlayerRecordView`'de **toplam skor alanı yok** (SIM-09'u sözleşme düzeyinde garanti).
5. `SimEvent.reason_id` zorunlu (her olay "Neden?" ile açılabilir); `CommandResult.reason`.
6. `Ref{kind,id}` + WorldData konum çözümü (`WorldData` API'si, ADR-0005 §WorldData).
7. Yapılandırma sorguları: `currency_symbol/name`, `available_speeds`, `ZoningOptions` (veri-odaklı seçenek listesi; UI sabit liste gömmez).
8. Olay/komut adları `StringName` enum karşılıklarıyla; yeni bir değer UI'da kod değişikliği gerektirmez (anahtar tablosu).

## 4b. Gündem (akış I) — v1.1 TEKNİK istek
Sözleşmede henüz yok; `political-events` şablonlarından (`delivery: ambient|agenda|decision`) beslenir. İstenen: `AgendaItemView{id, template_key, delivery, deadline_tick, options:[{id, label_key, cost, preview?{..., is_estimate}}], can_defer, reason_ids}`, komut `RespondAgenda{item_id, option_id|defer}`, olay `AgendaItemExpired`. `decision` öğesi modal değildir; otomatik duraklatma **UI ayarıdır**, sim'e varsayılan dayatılmaz (varsayılan AÇIK SORU, AS-11).

## 4c. Oynanabilir ilçe listesi — v1.1 TEKNİK istek
Açılış menüsü (CAN-08) için `WorldData`/senaryo sorgusu: `playable_districts() -> Array[{region_code, name_key?, playable:true}]`; UI `playable=true` olmayanı **listelemez**, hiçbirini varsayılan seçmez. Metropol/ilçe sayısı sabitlenmez (D1..Dn).

## 5. UI'nin sim'den İSTEMEDİĞİ şeyler
Hazır Türkçe metin, tek memnuniyet/popülerlik skoru, piksel/ekran koordinatı, platform profili bilgisi, kare hızına bağlı değer.

## 6. Contracts uyum raporu
`src/contracts/` v1.0 okundu (değiştirilmedi; T-023 hâlâ yazılıyor, yeniden hizalama gerekebilir). Doğrulanan: `ReasonRecord`, `ReasonFactor`, `SimEvent`, `ClockView`, `SimSnapshot`, `CommandResult`, `GroupReactionView`, `ParcelView`, `BudgetView`, `CouncilView` (alan adları yukarıdaki tablolarda v1.0 etiketli). Henüz sözleşmede olmayan her şey v1.1 TEKNİK istektir. Eski taslak notu: Entegrasyonda: (a) adlar `SimFacade/SimSnapshot/SimCommand/SimEvent/ReasonRecord/ParcelView/BudgetView/GroupReactionView/CouncilView` ile birebir kullanıldı; ek istek DTO'lar: `ClockView, PlayerRecordView, ElectionView, ProposalView, DistrictView, PublicWorkPreview, ZoningPreview, ZoningOptions, Ref, ReasonFactor, CommandResult`; (b) fark çıkarsa bu belge değil ADR-0005 kazanır, UX belgeleri güncellenir.
