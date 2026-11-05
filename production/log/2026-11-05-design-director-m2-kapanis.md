# 2026-11-05 · M2 kapanış: tasarım sadakati incelemesi (design-director, salt okuma)

Kapsam: F03 "Oyun hissi için doğrulanması gereken kabul ölçütleri" (7 madde, `design/foundation/docs/03_GAMEPLAY_AND_SIMULATION.md` §72-84) + `production/ROADMAP.md` M2 satırındaki ek koşullar; önceki incelemeden (`production/log/2026-11-05-design-director-m2.md`, HEAD `df158a7`) bu yana gelenler: D-021 meclis güveni, B-080, B-081, D-022, D-023, D-024, D-025, B-052, B-123/B-125.
Yöntem: belge, veri, kod ve git geçmişi okuması, HEAD `05c5a13`. **Godot ve test KOŞULMADI** (full verify başka oturumda koşuyor, Godot kilidi alınmış). Runtime kanıtı yalnız mevcut QA/ölçüm kayıtlarından alındı.

## Hüküm: FAITHFUL WITH FIXES

Son değişikliklerin hiçbiri kanonu bozmuyor ve AÇIK bir kararı kapatmıyor. CAN-03 sağlam: oyuncu komutları `zoning.propose`, `budget.propose`, `public_work.road/undo_last/demolish`, `policy.set`, `agenda.respond`. Bina üreten komut yok (`src/contracts/sim_command.gd:84-125`). D-021 zinciri (yıkım -> meclis güveni) sahibin sözüyle sınırlı ve büyüklüğü veride. D-024/D-025 sahip zevkidir ve öncelik kuralı 1'e göre sanat direktörü itirazından üstündür. M2 yine de **kapanmış değildir**. Eksik olanlar sahip eylemi (iPad ölçümü, masaüstü kabulü), bir kanıt boşluğu ("≥2 grup tepkisi") ve bayat kayıtlar.

## F03 ölçütleri

| # | Ölçüt | Hüküm | Doğrulanmış (dosya/test) | Varsayılan / test edilmedi |
|---|---|---|---|---|
| 1 | Yerleşim dokusu ve topografya hissedilir | KISMEN | T0 üreteci ve sanat kapıları kayıtlı (T-056..T-059 QA). Işık: art-director GEÇTİ (`2026-11-05-art-director-m2.md`). Boş arazi ve çatı görünümüne sahip karar verdi (D-024, D-025). Geri almalar birebir doğru: `git diff 3bc6e49~1 HEAD` `terrain_land.gdshader`, `mat_hero_variety.gdshader`, `building_variety.json/.gd`, `hero_mesh_loader.gd` için boş. | Sahibin genel görsel kabulü yok. Art F3 (yuvarlak leke sınırı) açık. VIS-04 kapısı açık. |
| 2 | Yol/imar/kamu alanı kararı fiziksel 3D dünyada | KARŞILANDI (masaüstü) | Yol çiz -> kamulaştır -> imar döngüsü, pencereli QA turları 2-3, T-066 kareleri (`2026-11-04-t066-pencereli-qa.md`), imar etiket/vurgu 15/15 halka (`2026-11-05-imar-etiket-vurgu-qa.md`). | iPad'de parmakla denenmedi. |
| 3 | Yatırımcı/hane yanıtı ilişkili ama otomatik değil | KARŞILANDI | T-066: 3/15 parsel `infrastructure_exhausted` ile ret aldı. Bekleme listesinin gerçek Ismeral ölçümü (`2026-11-05-bekleme-listesi-meclis-olcum.md`): imar yoksa 0 yeni konut, imar varsa yatırımcı bitirir. `m2_start_district_test.gd` mevcut. | M2-CLOSURE dayanağı hâlâ T-040 (10-23); güncellenmeli. |
| 4 | Nüfus/iş/ulaşım/bütçe değişimi anlamlı ve görünür | KISMEN -> iyileşti | D-023 ile Bütçe ve Meclis Yönetim modunda erişilebilir (`src/ui/flows/decision_panels.gd:103-112`). Bütçe yalnız gösterge (D-010) ve para birimi `¤` (Q-003 açık): `data/sim/budget/budget_config.json` başlığı ÇM diye etiketli, gerçek sim verisi okunuyor. | Kalabalık/yoğunluk görsel kabulü sahipte. Bütçe panelinin pencereli karesi D-023 sonrası görülmedi. |
| 5 | En az bir karar gerçek siyasi/toplumsal tepki üretir | KARŞILANDI (sim + UI testi) | Yıkım -> PE-01 mahalle gündemi -> meclis güveni (D-021). Ölçüm: 96x2 koşu, marj 73,7 -> 43,7, çoğunluk sonucu hiç değişmedi (`2026-11-05-meclis-guveni-yikim.md`). B-080: PE-03 etkin güveni okuyor (`tests/sim/politics/council_trust_event_source_test.gd`). B-081: HUD satırı gerçek neden kaydından (`tests/ui/council_trust_notice_test.gd`). RED yolu `tests/game/council_red_scenario_test.gd` ile kanıtlı. | Güven satırının ve RED'in pencereli karesi yok. "Hafif: ret çıkmaz" iddiası 8 tohumluk ölçüme dayanıyor; RED sınırındaki (yeşil + dolu altyapı) planlarda kesinti bir oyu çevirebilir, bu ölçülmedi. |
| 6 | Aynı alan farklı zoom'larda aynı dünya | KARŞILANDI (kayıtla, masaüstü) | Çok ölçekli kamera (T-003) tek dünya verisinden çalışıyor (WLD-01/TEK-03). K8 LOD farkı %2,6 ve bekçi olarak duruyor (M2-CLOSURE satır 9). | Bu oturumda yeniden ölçülmedi. iPad'de zoom geçişleri görülmedi. |
| 7 | Örnek ilçe zorunlu başlangıç olmaz | KARŞILANDI (mimari) / OYUNDA ERTELENDİ (D-021) | ROADMAP M2 bu ölçütü "oyuncu başlangıcı veri parametresi + en az iki ilçe kimliğiyle başlatma testi" diye tanımlıyor. Veri parametresi `data/world/ismeral/network.json:71` `jurisdiction_regions`. Test `tests/game/m2_start_district_test.gd` 6 ilçede ve 2 tohumda çalışıyor. Sahip, çakışmayı gösteren kartla (Q-035) "Şimdilik D2, ilçe seçimi sonra" dedi (D-021). Öncelik kuralı 1 bunu geçici olarak çözüyor. CAN-08 hedef olarak kalıyor. | Pencereli D2 dışı kanıt yok (gerekmez). |

## ROADMAP M2 ek koşulları

| Koşul | Hüküm | Dayanak |
|---|---|---|
| Test alanı Orven/D2, başlangıç veri parametresi, ≥2 ilçe başlatma testi | KARŞILANDI | Ölçüt 7 ile aynı. |
| Yatırımcı gerekçeli, olumlu + olumsuz senaryo | KARŞILANDI | T-066 (12 kabul / 3 ret, gerekçeli). |
| İnşaat zamanla ilerler, hane/işyeri, bütçe | KARŞILANDI (kayıt) | Değişim akışı ve bütçe göstergesi, bekleme listesi ölçümü. |
| **≥2 grup tepkisi** + küçük meclis | **KISMEN (yeni bulgu)** | Meclis var ve gruplar farklı oy veriyor (23:17 vb.). Ancak gerçek Ismeral'de kesim tepkisi olayı `group.reacted` hiçbir ölçümde ateşlenmedi (`2026-10-31-meclis-tepki-gercek-olcum.md:94`, `2026-11-01-yikim-tepkisi-yuksek-ilce-az.md:38`, `2026-11-05-bekleme-listesi-meclis-olcum.md:16`). Tepki veren: yerinden edilen mahalle (PE-01, `housed`), bazen medya (PE-04, tohuma bağlı, nedeni araştırılmadı) ve D-021 ile aynı kesimin meclis üyeleri. Tek bir kararın iki AYRI halk grubunda tepki doğurduğuna dair kayıt yok. |
| Oyuncu aynı alanı farklı zoom'larda inceler | KARŞILANDI (masaüstü) | Ölçüt 6. |
| Masaüstü profiliyle kabul | AÇIK | Sahip kabulü yok. |
| iPad'de aynı dilim cihazda oynanır (dokunmatik, ölçüm) | KISMEN | Açılış sahip bildirimiyle kanıtlı (`2026-11-04-ipad-gercek-cihaz.md`). T-076 `ready` durumda, ölçüm yok. Çekmece D-021/D-022/D-023 yalnız gerçek sahne testinde ve pencereli probe'da sınandı (`2026-11-05-cekmece-gercek-sahne-qa.md`); parmakla denenmedi. B-123: gündemde "Bu yanıtı ver" iPad yarı çekmecesinde kaydırma altında kalıyor (D-008 "halk tepki versin" eylemi, PLT-02). |
| Performans | KISMEN | Masaüstü ölçüldü ve ADR-0010 hedefleri konuldu. iPad cihaz ölçümü yok. |

## Önceki incelemeden bu yana: kanon kontrolü

- **D-021 meclis güveni:** CLEAR. Sahibin sözü yalnız yönü veriyor ("Meclis güveni düşsün", "Hafif kalsın", "İmar ve bütçe birlikte"). Büyüklük `data/politics/reactions.json` `council_trust` içinde ve ÇM olarak etiketli. Kod varsayılanı kapalı, digest dışı, GOLDEN_A/B değişmedi, GOLDEN_X bilinçli yenilendi, her değişiklik SIM-12 neden kaydı yazıyor. Etkilenen üyeler verideki `cohorts` listesinden geliyor, kanona konmadı.
- **B-080 (ADR-0011 Karar B):** CLEAR. Ayrı bir yaratıcı karar değil, D-021 sözünün tutarlı uygulaması. Aynı kavramın üç okuyucusu artık aynı değeri okuyor (SIM-12). Etki tavanı +36 pm ve PE-03 sert koşula bağlı. D-021 dosyasındaki "B-080 sahibe sorulmadı; açık" notu artık ADR-0011 ile kapandı. Design-director de sahip sorusu gerekmediğine katılıyor.
- **B-081 HUD satırı:** CLEAR. Sayı gerçek üye sayısı, güven değeri gösterilmiyor, sahte sayı yok. Risk (hipotez): B-027 gerekçe budaması kesinti sürerken kaydı düşürürse satır erken kaybolur. Haftalık yeni kayıt yazıldığı için olasılığı düşük, ölçülmedi.
- **D-022 çekmece yüksekliği:** CLEAR. Değerler veride (`data/ui/ui_tokens.json`), masaüstü etkilenmiyor.
- **D-023 Meclis/Bütçe/Gündem düğmeleri:** CLEAR. Yeni sim sistemi eklenmedi, var olan sistemler görünür oldu. F05-D "bütçe formülleri, vergiler, belediye meclisi mekanikleri" AÇIK kalıyor: meclis usulü (`data/politics/council.json` "VERIDIR, kanon degil", 5 üye yer tutucu) ve bütçe sayıları ÇM etiketli. Koşul: bu paneller artık oyuncunun önünde olduğu için hiçbir metin bu sayıları kesin kural gibi sunmamalı. Bu oturumda metin taraması yapılmadı.
- **D-024/D-025 boş arazi ve çatı:** CLEAR. Sahip zevki, öncelik kuralı 1 (`design/CANON.md`). Yalnız F1/F2/F4/F5 rötuşları geri alındı. D-021'in "kuru ot ve toprak" (B-090) ve "kiremit + düz çatı karışık" (b5523a7, `building_variety.json` `roof_tile_keep` 0,7) yönleri yerinde, yani D-021 ile çelişki yok. Sahip `cmp-r-120` karesinde soldakini (D-021 karışımı dahil) seçti. Varsayım: sahibin "düz boyalı çatı" itirazı yalnız F4 rötuşunu hedefliyor, D-021'in beton çatı payını değil.
- **B-052 yükleme eşitlemesi:** TEKNİK, CLEAR. Salt okuma sorgusu (sözleşme 1.10), oyun kuralı değişmiyor, TEK-03'e uygun (otorite sim). Ölçüm `2026-11-05-b052-yukleme-olcum.md` (`MISSING_sim=0`). GOLDEN eşitliği kayda dayanıyor, bu oturumda koşulmadı.
- **B-123 gündem düzeni:** Ana oturum, etki önizlemesini düğmenin altına alan düzeni almadı (oyuncu etkiyi okumadan basabilirdi). Bu kanona uygun bir tercih (SIM-12). Kalan iPad erişilebilirliği ürün sorusu, aşağıda S3.

## DÜZELTME GEREKİR (stüdyo işi, karar gerekmez)

1. **"≥2 grup tepkisi" kanıtı.** Tek bir kararın (ör. kamulaştırmalı yol veya büyük imar) en az iki ayrı halk grubunda gerçek tepki doğurduğunu gösteren bir prob veya test yazılmalı. Doğurmuyorsa bu bir ürün sorusudur ve ancak o zaman sahibe gider. Sahte tepki eklenmez.
2. **`production/M2-CLOSURE.md` bayat.** Ölçüt 2'deki "arazi görünümü YENİDEN YAPILMALI" D-024 ile sahip kararı oldu, ham numaralar B-031 ile düzeldi. Ölçüt 3'ün dayanağı T-040. Ölçüt 5 ve §Ölçümler'deki "tepki -> meclis bağı yok, Q-036 SAHİBE SOR" D-021, B-080 ve B-081 ile bayatladı. §Yönetici incelemeleri'nde "Q-035 SAHİBE SOR" duruyor. Ölçüt 7 yukarıdaki tabloya göre yazılmalı. D-021..D-025, B-080 ve B-052 dosyada hiç geçmiyor.
3. **`production/QUESTIONS.md` Q-039 durumu** "çatı AÇIK" diyor, oysa D-025 çatıyı cevapladı. Doğrusu "answered -> D-024/D-025". STATE checkpoint'teki "Q-039 yalnız çatı kapandı" ifadesi de ters okunuyor.
4. **`design/REQUIREMENTS.md` CAN-08 / WLD-12** hâlâ yalnız D-002'yi anlatıyor. "Geçici: D-021 (şimdilik D2, ilçe seçimi sonra)" notu eklenmeli (canon-check adım 5). `network.json` `jurisdiction_regions` notu da aynı karara bağlanmalı.
5. **D-020 ajan notu** "Q-014/Q-028 açık kalır" diyor ve D-014 §2 ile çelişiyor (önceki incelemenin 3. maddesi). Kullanıcı alıntısı değiştirilmeden, düzeltme notu olarak işlenmeli.
6. **B-027** (gerekçe ~100 günde düşüyor) açık. SIM-12 riskidir, karar technical-director'da. M2'yi engellemez, kapanış kaydında "bilinen sınır" diye yazılmalı.

## SAHİBE SOR (en çok 3; kart olarak, önerilen ilk)

**S1 · M2'yi kapatmadan önce siz bir kez oynar mısınız?** M2'nin iki koşulu sizin elinizde: masaüstünde "evet, M2 bu" demeniz ve iPad'de ölçüm.
- A) *Önerilen:* Masaüstünde ve iPad'de birer kez 10 dakika oynayın. iPad ölçümü kendiliğinden kaydedilir (T-076). Sonra M2 kapanır.
- B) Yalnız masaüstünde oynayın, M2 kapansın. iPad ölçümü bir sonraki aşamanın ilk işi olur.
- C) Oynamadan, kayıtlara dayanarak kapatın.

**S2 · iPad'de halk tepkisine yanıt düğmesi.** Gündemde "Bu yanıtı ver" düğmesine ulaşmak için iPad'de paneli bir kez kaydırmak gerekiyor.
- A) *Önerilen:* Böyle kalsın. Önce kararın etkisi yazıyor, düğme altında; kaydırma oyuncunun etkiyi okumasını sağlıyor. iPad'de deneyince yeniden bakarız.
- B) Düğme ilk ekranda olsun, etki yazısı düğmenin altına insin.
- C) Gündem paneli iPad'de hep tam boy açılsın.

(S3 açılmadı. "≥2 grup tepkisi" önce stüdyoda ölçülecek, gerekirse sonra sorulur.)

## Doğrulanmış / varsayılan / test edilmedi

- **Doğrulandı (bu oturumda dosya ve git okuması):** komut yüzeyi (`sim_command.gd`). D-024/D-025 geri almalarının birebirliği (`git diff 3bc6e49~1 HEAD` boş). `council_trust` verisi ve ÇM etiketi. Bütçe yapılandırmasının ÇM/gösterge etiketi. `jurisdiction_regions: ["D2"]`. Adı geçen testlerin dosya olarak varlığı (`m2_start_district_test`, `council_red_scenario_test`, `council_trust_notice_test`, `drawer_real_scene_test`, `golden_x_council_trust_test`, `council_trust_event_source_test`, `developed_ids_contract_test`). Bug ve görev durumları (B-052, B-080 çözüldü; B-122 açık; B-123 kısmen; T-076 ready).
- **Varsayıldı (kayıtlara dayanıyor, yeniden koşulmadı):** tüm ölçüm sayıları, GOLDEN_A/B/X sonuçları, verify full PASS @ `34eae42`. B-080, B-052 ve B-123/B-125 sonrası full doğrulama şu an koşuyor ve sonucu bilinmiyor.
- **Test edilmedi:** hiçbir Godot koşusu ya da test. Pencereli kareler açılıp bakılmadı. iPad'de parmakla hiçbir şey. D-023 sonrası Meclis/Bütçe panel metinlerinin ÇM sayıları kesin kural gibi sunup sunmadığı (metin taraması yapılmadı).
