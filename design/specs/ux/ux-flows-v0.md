# Kritik akışlar v0 (T-018 ölçüt 2)

Statü: ÇALIŞMA MODELİ. Kısayol tuşları, adım sayıları ve eşikler ÖNERİDİR; kanon değildir (F05-D). Metin anahtarları `data/ui/strings.tr.json`; sim alanları `ux-data-needs.md` (DTO adları orada).
**Aynı fiiller, iki profil.** Kısaltmalar: **M** = fare/klavye/trackpad (masaüstü), **D** = dokunmatik (iPad). Genel eşleşmeler:

| Fiil | M | D |
|---|---|---|
| Seç | sol tık | dokun |
| Bilgi önizle | hover (gecikme ~300 ms) | YOK → seç, denetçi açılır |
| Bağlam menüsü | sağ tık / Ctrl+tık | uzun bas (~500 ms) |
| Kaydır / Zoom / Döndür | sürükle-pan (orta tuş ya da boşluk+sürükle), tekerlek ya da trackpad pinch, Q/E ya da orta tuş | tek parmak / pinch / iki parmak dönüş |
| Onayla / Vazgeç | Enter / Esc | onay çubuğunda görünür düğmeler (≥44 pt) |
| Geri al | Ctrl/Cmd+Z | `common.undo` düğmesi |
| Çok seçim/nokta | Shift+tık | "Nokta ekle" modu |
Dokunmatikte **jest ile gizlenmiş tek erişim yoktur**; her jestin görünür düğme eşi vardır. Raw dokunma tanıma tek yerde (`_unhandled_input`, kontroller önce tüketir), fare-dokunma çift tetiklenmesi için dokunma emülasyonu kullanılmaz ya da tek yol seçilir (godot-mobile).

Ortak sonuç dili: bir komut gönderilince UI `SimCommand` sonucunu bekler; sonuç `accepted` / `rejected(ReasonRecord)`. **Reddedilen komutun gerekçesi gösterilir** (`state.error.command_rejected`), sessiz hata yok.

---
## A. Yol / kamusal alan çizimi (İnşa) — CAN-04
Araçlar: Yol, Bulvar, Kavşak, Meydan, Park, Belediye tesisi. Çizim "gerçek çizim, konum ve bağlantı önemli" (CAN-04).
| # | Adım | M | D |
|---|---|---|---|
| 1 | Mod = İnşa, araç seç (örn. Yol); sınıf/şerit L3 çubukta | araç düğmesi ya da kısayol (öneri `B` sonra sayı) | araç düğmesi |
| 2 | Başlangıç noktası: yakınlaşma ipucu; mevcut düğüme **yapışma** (görünür halka) | tık; Alt = yapışmayı kapat | dokun; yapışma yarıçapı ≥ 44 pt eşdeğeri |
| 3 | Sonraki noktalar: önizleme şeridi eğri/açı, **canlı maliyet** ve geçerlilik rengi+ikon (yalnız renk değil) | tık ile nokta, Shift = düz hat | dokun = nokta; `draw.remove_point` ile son noktayı sil |
| 4 | Engel/ihlal: eğim, su, yetki dışı, bütçe → **neden metni** (`draw.blocked.reason`) önizlemede, onay devre dışı + `state.disabled_reason` | hover'da ayrıntı | düğme altında kalıcı metin |
| 5 | Bitir | çift tık / Enter | onay çubuğu `draw.finish` |
| 6 | Onay: maliyet + süre özeti; `Onayla` → `SimCommand` | Enter | `common.confirm` |
| 7 | Sonuç: inşaat kuyruğu bildirimi; dünyada inşaat görünür; geri al penceresi (yalnız henüz başlamamış inşaat) | Ctrl+Z | `common.undo` |
| 8 | İptal | Esc / sağ tık | `draw.cancel` |
Notlar: dokunmatikte **sürükle = kaydır** olduğundan çizim *nokta-ekle + onay çubuğu*dur (sürükleyerek çizim kullanılmaz; uzun-bas+sürükle ile mevcut noktayı taşıma opsiyonu). Meydan/Park çokgen kapatma: ilk noktaya dokun/tık. Özel bina aracı yok (`draw.no_private_building`).
Sim: `PublicWorkDraft` doğrulaması (geçerlilik, maliyet, süre, ihlal ReasonRecord), `BudgetView.balance`, `SimCommand.DrawPublicWork`.
Durumlar: maliyet hesaplanamıyorsa `draw.cost_unavailable` (sahte sayı yok); sim yanıtsızsa `state.error.sim_unavailable`.

## B. İmar değişikliği önerisi (İmar) — CAN-05, CAN-03
Belediye bina yaratmaz; **koşul** önerir. Sonuç yatırımcı kararlarıyla gelir.
| # | Adım | M | D |
|---|---|---|---|
| 1 | Mod = İmar → "İmar önerisi" | araç düğmesi | aynı |
| 2 | Alan seç: parsel(ler)i boya ya da çokgen çiz | tık / fırça sürükleme (Shift = ekle) | parsele dokun = ekle; "Alan düzenle" modunda fırça; `Nokta ekle` çokgeni |
| 3 | Form (L2): arazi kullanımı, yoğunluk, en yüksek yükseklik, gelişme koşulları (`zoning.*`) | form alanları, klavye | büyük seçici düğmeler, kaydırıcı yerine +/− adımlayıcı |
| 4 | **Etki önizlemesi** (tahmin etiketli, `zoning.preview.estimate_note`): altyapı kapasitesine karşı, tahmini yatırımcı ilgisi — sim `ZoningPreview` verirse gösterilir, vermezse bölüm gizlenir | canlı güncellenir | `Önizle` düğmesiyle güncellenir (hover yok) |
| 5 | Gönder: meclis gerekiyorsa `Meclis'e sun` (akış E), gerekmiyorsa `Uygula` | Enter | düğme |
| 6 | Sonuç: karar bildirimi; boş parsel dünyada **bina oluşturmaz**; yatırımcı tepkisi zamanla gelir ve "Neden?" (akış D) ile okunur | — | — |
Sim: `ParcelView.zoning`, `ZoningProposal`, `ZoningPreview` (opsiyonel), `SimCommand.ProposeZoning`, `CouncilView`.

## C. Parsel / ilçe denetçisi — SIM-12 girişi
| # | Adım | M | D |
|---|---|---|---|
| 1 | Aç | Denetçi aracı ya da herhangi bir araçla boş alana tık; **hover önizleme baloncuğu** (kısa 3 satır) | dokun = seç → L2 panel açılır |
| 2 | İçerik: parsel kimliği, ilçe kodu (`district.code`), mülkiyet, kullanım, imar durumu, altyapı erişimi, **yatırımcı ilgisi ve son karar + "Neden?"** | tek panel sekmeleri (Genel / İmar / Altyapı / Geçmiş) | aynı sekmeler, büyük başlıklar |
| 3 | İlçe ölçeğinde: ilçe kartı (kesim bazlı göstergeler, açık şikâyetler, bütçe payı) — **tek skor yok** | aynı panel | aynı |
| 4 | Çapraz bağlantı: "Neden?", "Haritada göster", "İmar öner" | düğme/kısayol | düğme |
| 5 | Kapat/sabitle | Esc / pin | kapat düğmesi; haritaya dokunmak seçimi değiştirir |
Boş durum: `inspector.nothing_selected`. Veri yoksa alan **gizlenir** ya da `common.unknown`; uydurma değer yok.
Sim: `ParcelView` (+ `DistrictView`), `ReasonRecord` referansları.

## D. Nedensellik paneli — SIM-12 (çekirdek)
Hedef: "neden yatırım gelmedi / protesto oldu?" sorusuna **gerekçe zinciri, etken ağırlıkları, zaman**.
| # | Adım | M | D |
|---|---|---|---|
| 1 | Giriş: bildirimdeki "Nedenini gör", denetçideki "Neden?", dünyadaki olay ikonu | tık, kısayol `N` (öneri) | dokun |
| 2 | **Üst satır**: sonuç (`reason.outcome.*`), kim/nerede/ne zaman | — | — |
| 3 | **Etkenler listesi**: her etken = ad + yön (lehte/aleyhte, ikon+metin, yalnız renk değil) + **ağırlık çubuğu ve sayı** + kaynak bağlantısı (parsel/bütçe/grup) | hover: etken ayrıntısı | dokun: satır genişler |
| 4 | **Karar zinciri**: önceki karar → tepki → fiziksel değişim → etki (F03 döngüsü), her halka tıklanabilir (`parent_ids`) | tık ile gez | dokun ile gez; geri düğmesi |
| 5 | **Zaman içinde**: aynı özne için önceki kayıtlar (küçük zaman çizelgesi); eğilim oku+metin (`a11y.trend_*`) | hover'da değer | dokun |
| 6 | "Haritada göster": ilgili parsel/hat vurgulanır | tık | dokun |
| 7 | Eylem önerisi (varsa sim `suggested_actions` verir): örn. "altyapı kapasitesi ekle" → ilgili araca götürür; **sim vermezse UI öneri uydurmaz** | — | — |
Dürüstlük: `is_estimate` etkenler `reason.estimate` ile etiketli; kayıt yoksa `reason.none_recorded`; süresi dolmuşsa `reason.expired`. Ağırlıklar toplamı %100 olarak gösterilmez (sim vermedikçe); sim'in verdiği biçim neyse o.
Sim: `ReasonRecord{outcome, subject, factors[], parent_ids[], tick, is_estimate}` + `SimQuery.reasons_for(subject_ref)` / `reason_history(subject_ref)`.

## E. Meclis oylaması — SIM-05, CAN-06
| # | Adım | M | D |
|---|---|---|---|
| 1 | Öneri sunulur (imar/bütçe); L4 küçük onay: ne sunuluyor, hangi etki | Enter | düğme |
| 2 | Oylama başlar; **duraklatma yok**, oyun akar. L2 Meclis paneli: koltuk dağılımı, grup bazlı beklenen/verilen oy, `player_bloc_support` | panel, hover'da grup gerekçesi | satıra dokun |
| 3 | Oyuncu fiili (sim destekliyorsa): destek arama / taviz (komut kümesi sim spec'ine bağlı — AÇIK) | düğmeler | aynı |
| 4 | Sonuç: `council.outcome.*` + **gerekçe** (`council.reasons_for_bloc` → akış D) | bildirim + panel | aynı |
| 5 | Gecikme/kısmen uygulama: ne kaldı, ne zaman yeniden denenir | metin | metin |
Kurulmamışsa (`CouncilView` yoksa) Yönetim sekmesinde `council.not_built` ile etiketli ya da gizli. Sim: `CouncilView{seats[], votes[], pending[]}`, `SimEvent.CouncilVoteResolved`.

## F. Bütçe — CAN-06
| # | Adım | M | D |
|---|---|---|---|
| 1 | Yönetim → Bütçe (L2) | `Y` ardından bütçe düğmesi | aynı |
| 2 | Özet: gelir, gider, bakiye (`format.money`), kategori kırılımı, öngörü (tahmin etiketli) | tablo + küçük grafik | kartlar |
| 3 | Hizmet kapasitesi ve kullanımı (yoğunluk bütçeyi/hizmeti aşıyor mu — SIM-07) | çubuk+sayı | çubuk+sayı |
| 4 | Öncelik/tahsis değişikliği: adımlayıcı ya da kaydırıcı; **bekleyen değişiklik** farkı gösterilir | kaydırıcı/sayı alanı | +/− adımlayıcı (kaydırıcı opsiyonel, 44 pt tutamak) |
| 5 | Uygula: meclis gerekiyorsa akış E, gerekmiyorsa komut | Enter | düğme |
Tüm tutarlar `¤` yapılandırmasından biçimlenir; para simgesi/adı metin tablosunda yoktur (Q-003). Sim: `BudgetView`, `SimCommand.SetBudgetAllocation`.

## G. Zaman kontrolü — TEK-01
| Fiil | M | D |
|---|---|---|
| Duraklat/Sürdür | Boşluk | üst şeritte büyük düğme |
| Hız 1×/2×/3× | 1/2/3 (öneri) | üç düğme (aktif olan seçili ikon+metinle) |
| Tarih/saat | üst şeritte `clock.date_ingame` | aynı |
Yalnız sim'in desteklediği hızlar gösterilir (`ClockView.available_speeds`; profil `max_game_speed` ile kısıtlıysa `clock.speed_capped`). Duraklıyken komutlar verilebilir (ayarla/çiz), uygulama sim tick'inde. Sim: `ClockView{tick, paused, speed, available_speeds}`, `SimCommand.SetSpeed/TogglePause`.

## H. Seçim / sicil — SIM-09, CAN-10
Tek "Mutluluk %" yoktur. Sicil ayrı göstergelerdir; seçim kesim bazlıdır (politics-elections.md §3-6; tüm adlar/süreler ÇM, AÇIK).
| # | Adım | M | D |
|---|---|---|---|
| 1 | Yönetim → Sicil (L2) | düğme | düğme |
| 2 | Göstergeler yan yana: `delivery, fiscal, service, equity, reputation_by_group, media_tone, ally_support` — her biri ayrı, **birleştirilmemiş**; `record.no_single_score` notu | tablo | kartlar |
| 3 | Grup bazlı tepki: grup adı (yer tutucu `record.group.placeholder`), şikâyetler, **tepkinin nedeni** → akış D | satır tık | satır dokun |
| 4 | Seçim aşaması: aşama, kalan süre, anket tahmini **belirsizlik aralığıyla** (`election.poll_range`) | şerit | şerit |
| 5 | Seçim gecesi (L4): bölge/grup bazlı sonuç, "sonucun dökümü" (neden), kayıpta `election.defeated` sonuç ekranı | animasyon azaltma desteği | aynı |
Kurulmamışsa `election.not_built`. Parti adları sabit string değil; `election.party.placeholder` ya da sim `display_key` (politics-elections §8). Sim: `PlayerRecordView`, `GroupReactionView`, `ElectionView`.

## Ortak: bildirim şeridi
Sim olayları (`SimEvent`) → şerit: kısa metin (anahtar+argüman) + "Nedenini gör". Modal yok. Aynı türden olaylar toplulaşır. Geçmiş: `alert.feed_title` listesi. Şerit **sayı sahte değil**: yalnız gelen olaylar.
