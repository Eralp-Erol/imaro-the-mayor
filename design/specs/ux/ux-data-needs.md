# UX veri ihtiyaçları v0 (T-018 ölçüt 4) — SimFacade'dan gerekenler

Statü: SÖZLEŞME İSTEĞİ (ADR-0005 / T-023'e girdi; koordinatör v1.1'e taşır). `src/contracts/` bu yazım sırasında **henüz yoktu** (ls: yok; `docs/adr/0005-*` yok) → adlar T-023 taslağına göre **eşlenebilir önerilerdir**; gerçek DTO gelince `ux-data-needs` düzeltilir (uyum raporu aşağıda §6). UI sim'e **yazmaz**, yalnız `SimFacade` üzerinden okur ve `SimCommand` gönderir. Hiçbir alan platform profiline bağlı değildir (PLT-04).

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
| `SimSnapshot` | `tick:int`, `clock:ClockView`, `budget:BudgetView?`, `council:CouncilView?`, `record:PlayerRecordView?`, `election:ElectionView?`, `is_mock:bool` | `?` = kurulmamış olabilir |
| `ClockView` | `tick`, `day:int`, `year:int` (takvim AÇIK; yalnız gün sayacı yeterli), `paused:bool`, `speed:int`, `available_speeds:Array[int]` | G akışı |
| `ReasonRecord` | `id`, `outcome:StringName` (enum→`reason.outcome.*`), `subject:Ref`, `tick:int`, `factors:Array[ReasonFactor]`, `parent_ids:Array[id]`, `summary_key`, `summary_args`, `is_estimate`, `expires_tick?` | SIM-12 çekirdeği |
| `ReasonFactor` | `key` (→`reason.factor.<key>`), `direction:int` (−1 aleyhte, +1 lehte), `weight:int` (binde; sim tanımlı, UI normalize etmez), `args:Dictionary`, `source:Ref?`, `is_estimate`, `trend:int` (−1/0/+1) | |
| `Ref` | `kind:StringName` (parcel, district, group, proposal, road, facility, council_bloc), `id` | |
| `SimEvent` | `id`, `tick`, `kind`, `text_key`, `args`, `subject:Ref`, `reason_id:id?`, `severity:int` | bildirim şeridi |

## 2. Akış bazında istekler
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
`CommandResult{accepted:bool, reason:ReasonRecord?}`; reddedilen komut her zaman gerekçe verir. UI tahmini yapıp "kabul edildi" göstermez; sonucu bekler (duraklıyken komut sıraya girer, `queued`).

## 4. Sözleşmeye v1.1 istekleri (özet)
1. `ReasonRecord`/`ReasonFactor` alanları yukarıdaki biçimde (anahtar+argüman, `parent_ids`, `weight`, `direction`, `is_estimate`).
2. `*_preview` sorguları (`preview_public_work`, `preview_zoning`) — yan etkisiz, deterministik.
3. `SimFacade.is_mock()`, `SimSnapshot` içinde `?` ile kurulmamış sistemler (`available`).
4. `ParcelView`/`DistrictView`/`GroupReactionView`/`BudgetView`/`CouncilView` alanları §2'deki gibi; `PlayerRecordView`'de **toplam skor alanı yok** (SIM-09'u sözleşme düzeyinde garanti).
5. `SimEvent.reason_id` zorunlu (her olay "Neden?" ile açılabilir); `CommandResult.reason`.
6. `Ref{kind,id}` + WorldData konum çözümü (`WorldData` API'si, ADR-0005 §WorldData).
7. Yapılandırma sorguları: `currency_symbol/name`, `available_speeds`, `ZoningOptions` (veri-odaklı seçenek listesi; UI sabit liste gömmez).
8. Olay/komut adları `StringName` enum karşılıklarıyla; yeni bir değer UI'da kod değişikliği gerektirmez (anahtar tablosu).

## 5. UI'nin sim'den İSTEMEDİĞİ şeyler
Hazır Türkçe metin, tek memnuniyet/popülerlik skoru, piksel/ekran koordinatı, platform profili bilgisi, kare hızına bağlı değer.

## 6. Contracts uyum raporu
`src/contracts/` ve ADR-0005 bu yazımda mevcut değil → **uyum doğrulanamadı**. Entegrasyonda: (a) adlar `SimFacade/SimSnapshot/SimCommand/SimEvent/ReasonRecord/ParcelView/BudgetView/GroupReactionView/CouncilView` ile birebir kullanıldı; ek istek DTO'lar: `ClockView, PlayerRecordView, ElectionView, ProposalView, DistrictView, PublicWorkPreview, ZoningPreview, ZoningOptions, Ref, ReasonFactor, CommandResult`; (b) fark çıkarsa bu belge değil ADR-0005 kazanır, UX belgeleri güncellenir.
