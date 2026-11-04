# T-067 · yeniden iskân bekleme listesi (sim + sözleşme 1.9), 2026-11-04, simulation-engineer

Dal `worktree-agent-ad2b9cc1162b04d1c` (taban `931b3e5`, main'e ff). Push yok, main'e merge yok. UI yok.

## Ne yapıldı
- Liste TÜRETİLİR: bekleyen aile = yolun yeniden iskân kaydındaki `unplaced_by`; sıra yol sırası, sonra bölge kodu. Ayrı kuyruk nesnesi yok.
- "Yeni ev" = `res_built` artışı; `systems["policy"].resettlement_queue.built_mark` yalnız bekleyen aile varken vardır (politika hiç açılmadıysa hiçbir şey yaratılmaz).
- `ResettlementQueueSystem` (ekonomiden sonra, günlük) -> `ResettlementQueue.serve`: yalnız politika AÇIKKEN; verilen hane yeni birimi ve gerçekten boş birimi aşmaz; T-065 ile aynı kapasite/kira/yer kuralı (`ResettlementPlanner.candidates`), `max_fill_pm` hariç.
- Tepki: kayıtta `weight_by`/`effective` güncellenir (bekleyen 1000, tam ev `residual_pm`, kısmi ev `max(residual, 1000 - partial_relief)`); okuma yine tek noktada `ReactionRehousing`.
- Kayıt: `served` + `weight_by` (isteğe bağlı), doğrulama `PublicWorksState._resettlement_problem`; `SimSave.VERSION` 2 kalır.
- Geri al: verilmiş evler de geri sarılır. Politika değişince ve yol uygulanınca/geri alınınca `built_mark` eşitlenir.
- Sözleşme 1.9: `PolicyView.waiting_households/waiting_by_region/served_households`, ADR-0005 Ek L, kilitli sürüm testleri.
- Bayat metin: `data/politics/reactions.json` `_notes`, `reaction_rehousing.gd` başlığı, `expropriation_rehousing_test.gd` başlığı D-016 §2 davranışına çekildi.

## Varsayımlar (sahip onayı YOK; hepsi veri/kural, kolay değişir)
- Politika kapatılınca liste durur (atama yok), aileler listede ve tepki yerinde kalır; yeniden açılınca kapalıyken biten evler "yeni" sayılmaz.
- Sıradan verilen evin göstergesi bütçeye yazılmaz (gerçek para kısıtı T-014/Q-003 açık).
- Hane kaderi `return_to_latent` iken aynı bölgede biten ev de listeyi karşılar (aile zaten o bölgenin talebinde; üst sınır yeni birim ve ev arayan hane).
- "Eve kavuştu" için yeni olay türü eklenmedi (sözleşmeyi büyütmemek); UI `policies()` verisini yoklayarak gösterebilir. Gerekirse 1.10.
- `decision.municipal.resettlement_queue` ve üç `reason.factor.queue_*` anahtarının metin tablosu girdileri ui-engineer işi.

## Doğrulama
Rapor ve komut çıktıları görev dosyası `production/tasks/T-067.md` "Kanıt" bölümündedir.
