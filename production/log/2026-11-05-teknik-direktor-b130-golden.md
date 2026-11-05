# 2026-11-05 · Teknik direktör · B-130 / D-026 golden yenilemesi incelemesi

İncelenen: dal `work/b130` commit'leri 3e5cd2c, 47e382c, 9b293ed, 49e80c7, c74001b (inceleme dalı `work/td-b130`).
Godot ve testler ÇALIŞTIRILMADI (Godot kilidi başka ajanlarda); aşağıdaki her şey kod/veri okumasıdır.

## Karar: APPROVE WITH CHANGES (golden yenilemesi)

Eşik değişikliği (decision_tables.json `bloc.react` petition 250 -> 190, global) sahibin D-026 "A" kararının en küçük
uygulamasıdır ve değişmez kuralları bozmuyor. GOLDEN_A/B/X yenilemesi bu kararın kaçınılmaz sonucudur; kesim başına
eşik baz çizgileri korumazdı (aşağıda 2). Birleştirmeden önce iki küçük düzeltme gerekli (bkz. "Gerekli değişiklikler").

## 1. Veri-yalnız eşik değişikliği doğru mu, değişmez kural bozuluyor mu?

Doğrulandı (okuyarak):
- `main...work/b130` farkında `src/sim` altında tek değişiklik B-042'nin salt okunur `ReasonLatestCache`'i
  (`src/sim/facade/reason_latest_cache.gd`, `sim_facade_impl.gd` +9 satır): durum/hash/kayıt dışı, `GameState`e yazmaz.
  B-130 commit'leri `src/` dosyasına dokunmuyor; davranış değişikliği yalnız `data/actors/decision_tables.json`.
- Eşik kodda sabit değil: `ActorDecision.evaluate` basamak eşiğini tablodan okur (`src/sim/actors/actor_decision.gd:157-166`).
- Determinizm: gürültü (tick, aktör, karar) anahtarlı, akış tüketmez (`actor_decision.gd:89-94`); veri değişikliği sırayı
  ya da RNG akışlarını etkilemez.
- SIM-12: her basamak AYRI kayıt yazar, kayıt yazılamazsa karar uygulanmaz (`actor_decision.gd:170-176`); sonuç kayıtlı
  tamsayı skordan türer, kayıt-karar ayrışamaz. Eşik düşünce yalnız olumlu kayıt sayısı ve bir üst basamak kaydı artar.
- CAN-03: kesim tepkisi bina yaratmaz; yatırımcı tarafına etkisi (varsa) yatırımcının kendi kayıtlı kararı üzerinden.
  Belediye komut yolu değişmedi.
- Kayıt/hash: `decision_tables.json` `ActorConfig.digest`e girer (`src/sim/actors/actor_config.gd:13-15, 145`), digest
  `systems.actors.config_digest` olarak durumda saklanır (`actor_store.gd:46`) ve `GameState.state_hash` `systems`i
  hash'ler (`src/sim/core/game_state.gd:107-118`). `config_matches` üretim kodunda yükleme kapısı olarak çağrılmıyor
  (yalnız `tests/sim/actors/actor_relation_test.gd:28`): eski kayıtlar yüklenir, yeni eşikle devam eder. Kayıt biçimi
  değişmedi; yeni durum alanı yok.

Global mi, kesim başına mı: global değişiklik bloc.1'in eşiğini de düşürür ama bloc.1'in ölçülen tepesi 73 (B-130), etki
yok. Kesim başına eşik kod gerektirir (aşağıda 2) ve baz çizgilerini yine de korumaz. Global = doğru en küçük değişiklik.

## 2. GOLDEN_A/B neden değişti; yenileme kabul edilebilir mi?

Doğrulandı (okuyarak): A ve B'nin hash'i İKİ yoldan değişir, ajanın açıklaması yalnız birini söylüyor:
1. `systems.actors.config_digest`: `decision_tables.json`un TAMAMININ (`_notes` metni dahil) StateHash'i. Bu dosyada
   tek bayt değişse (yalnız not bile) aktör başlatan her senaryonun hash'i değişir. Yani B'de "yalnız kayıtlardaki eşik
   alanı değişti" açıklaması EKSİK: digest de değişti.
2. Gerekçe kayıtları `threshold` taşır (`actor_decision.gd:170`), ReasonLog hash'e girer (`game_state.gd:113`).

A'daki 60 -> 61 kayıt / olumlu 3 -> 4 / `group.reacted` 2 -> 2 tutarlı bir mekanizmaya oturuyor (HİPOTEZ, kodla
tutarlı, çalıştırılmadı): bir değerlendirmede skor [190,250) aralığında -> petition artık olumlu -> bir üst basamak
(protest) değerlendirilir ve olumsuz kayıt yazar (+1 kayıt, +1 olumlu). Olay sayısının aynı kalması, o kesimin destek
skorunun basamak skorundan yüksek olduğu durumda `_reaction_of` sonucunun değişmemesiyle açıklanır
(`src/sim/politics/bloc_engine.gd` `_reaction_of`: `tier_score >= support score` değilse "support" kalır, tepki/basamak
değişmediği için `_publish` çağrılmaz). A senaryosu "zıt yönde iki tepki" senaryosu (`m2_query_test.gd:319`) olduğu
için bir destek veren kesim bulunması beklenir. Gizli davranış değişikliği belirtisi YOK.

Ajanın "eski değerler eşik 250 ile bire bir yeniden üretildi" iddiası VARSAYILDI (okuyarak doğrulanamaz). Digest nedeniyle
bu iddia ancak dosyanın tamamı (not metni dahil) eski haline döndürüldüyse doğru olabilir; bu, iddiayla çelişmez ama
ayrıca kanıt istenmeli.

Kesim başına eşik baz çizgileri KORUMAZDI (doğrulandı, okuyarak):
- Kesim başına eşik için mevcut veri yolu yok: `ActorDecision.evaluate` aktöre özgü theta okumaz; `blocs.json` tek bir
  `react_decision` anahtarı taşır.
- Hangi yoldan yapılırsa yapılsın hash değişir: `decision_tables.json`ye ikinci tablo -> aktör digest'i; `blocs.json`
  -> `PoliticsConfig.digest` (durumda, `politics_state.gd:48`); `roster_m2.json` (özellikler) -> aktör digest'i. Ayrıca
  bloc.2 petition kayıtları A/B'de de yazılıyor; onun eşiği değişince kayıt hash'i yine değişir.
- `blocs.json` hook ile değil, digest'e girdiği için "korumalı": değişirse tüm golden'lar değişir (ADR-0005 satır 180).
- Digest DIŞI tek politika verisi `data/politics/reactions.json`; yalnız kamulaştırma varsa çalışır, eşiği değil
  şikâyet kazancını ayarlar (bloc.2 seçeneği A'yı uygulayamaz). Aşağıda 4'te bloc.1 için anlamlı.

Sonuç: sahip D-026'da "GOLDEN hash'ler bilinçle yenilenir, teknik direktör onayıyla" dedi; kural bilinçli değişti,
yenileme meşrudur. A/B/X ve kural-kapalı referansı ayrı commit'lerde, eski değerler yorumda kayıtlı: iz sürülebilir.
GOLDEN_X ve GOLDEN_X_BEFORE_D021 kayıt farkı çıkarılmadı (ajan da "VARSAYILDI" diyor); X kamulaştırma/geri alma
senaryosudur, eşik orada davranışı A'dakinden daha fazla değiştirebilir (ek tepki olayı, medya haberi, hafıza
kaydırması). `golden_x_council_trust_test.gd` test 2 (kural açık/kapalı farkı yalnız kesinti durumunda) yapısal bir
koruma sağlıyor ama eşik farkını değil.

## 3. Test uyarlamaları

- `tests/sim/actors/actor_evaluate_test.gd` "sessiz": MEŞRU. Eski girdi (şikâyet 100) skoru 0,45x100 + 0,15x500 +
  0,10x500 = 170 (+/- gürültü) veriyordu; yeni eşik 190 ile tohuma bağlı olarak geçebilirdi. Yeni girdi (0, memnuniyet
  500) skor ~0: vaka "sessiz" anlamını korur. Eşiğe yakın olumsuz durum zaten protest/boycott basamaklarında sınanıyor.
  Kırılganlık kaynağı: test sayıları veriye göre elle kalibre (takip önerisi aşağıda).
- `tests/sim/politics/bloc_reaction_test.gd` 25 -> 40: KABUL, hafif gevşeme. Testin amacı "her taramada kayıt yok"
  (80 aday); ölçülen 26, sınır 40 hâlâ yarısı. Artış mekanizması kodla tutarlı: tepkili kesim `recheck_days` (28) ile
  yeniden değerlendirilir (`bloc_engine.gd` `_should_evaluate`, `data/politics/cadence.json`). Sayı sınırı yerine yapısal
  iddia (her değerlendirme ya tetik değişimi ya >= recheck_days) daha sağlam olurdu.
- `tests/ui/m2_result_default_regime_test.gd` `_first_meter`: MEŞRU (seçici daha özgül; ilerleme çubuğunu tepki
  kartının çubuğundan ayırır, iddia gevşemedi). AMA bir kanıt: bu senaryo (küçük M2 test dünyası, yalnız 8 parsel imar,
  250 gün) eşik 190 ile artık bir kesim tepki kartı gösteriyor. Gerçek Ismeral'de imar bloc.2'yi oynatmıyordu (B-130:
  +0 G); test dünyasında 190'ın taban sürüklenmesiyle aşıldığını gösteriyor olabilir (HİPOTEZ, ölçülmedi). "Taban ve tek
  yolda tepki yok" yalnız gerçek Ismeral D2, 2 dünya x 2 sim tohumu, <= 360 gün için ölçüldü; pay 17-19 puan,
  gürültü +/- 80 x oynaklık.

## 4. Barınanlar (actor.bloc.1) hâlâ tepki vermiyor: seçenekler (yaratıcı karar sahibin)

Neden (okuyarak + B-130 ölçümü): bloc.1'in D2 payı %7-7,9 < `blocs.json` `blend.min_share_pm` %10, bölge ölçekli
yerinden edilme sinyali kesime ulaşmıyor; tek karar-bağlı girdi `reactions.json` `local.district_gain` (400) yoluyla
haftalık küçük ilçe şikâyeti (`src/sim/politics/reaction_agenda.gd` `_district_grievance`). Doz testinde puan 31-73,
taban/tek yol 8-42 (örtüşür).

| Seçenek | Ne | Maliyet | Risk | Golden |
|---|---|---|---|---|
| (a) Ölçütü yeniden oku | bloc.2 `group.reacted` + bloc.1 mahalle gündemi PE-01 + haber = "iki grup görünür" | sıfır | M2 ölçütünü sahibin onaylaması gerekir | değişmez |
| (b) `reactions.json` `local.district_gain` artır | yerinden edilen hane sayısıyla ORANTILI ilçe şikâyeti; kamulaştırma yoksa 0 | küçük, veri-yalnız, probe ile ölçüm | D-014 §3 "ilçe geneli çok az ama sıfır değil" sözüyle gerilim; bloc.2 de aynı kazancı alır (seeking kohortunun yerinden edilme konusu var) -> bloc.2 tek-yol payı yeniden ölçülmeli | A/B DEĞİŞMEZ (digest dışı, kamulaştırmasız koşuda çalışmaz); X ve kamulaştırma senaryoları değişir |
| (c) `blocs.json` `blend.min_share_pm` %10 -> <= %7 | bölge sinyalleri bloc.1'e ulaşır | küçük veri, geniş etki | TÜM sinyaller (inşaat yükü, altyapı) iki kesim için değişir, taban sürüklenmesi riski | A/B/X hepsi yeniden |
| (d) Kod: mahalle ölçeğini kesim sinyaline taşı / kesimi mahalle kohortuna böl (B-130 2a) | D-011/D-014 "evi yıkılanın tepkisi yüksek"e en sadık | büyük: yeni durum alanı, kayıt/hash/round-trip testi, ADR | en az gürültü, en çok iş | hepsi yeniden |
| (e) bloc.1 için ayrı (düşük) eşik | kod | orta | REDDEDİLİR: taban ve doz örtüşür (8-42 / 31-73), tepki gürültüden doğar = sahte nedensellik | hepsi yeniden |

Teknik öneri (yaratıcı soru sahibin): önce (b) en küçük deney olarak ölçülsün (probe `tools/godot/group_reaction_probe.gd`,
bloc.1 ve bloc.2 için taban / tek yol / doz, 360 gün); D-014 §3 ile çelişip çelişmediği sahibe sorulmadan uygulanmasın.
Sahip "ilçe geneli az kalsın" derse (a); mahalle ölçekli kesim isterse (d), M2 sonrası ayrı görev + ADR.
Soru `production/QUESTIONS.md`'ye (Q-040 devamı) eklenmeli: "Çok sayıda ev yıkan yol programında evi olan halk da
ilçe genelinde dilekçe versin mi (D-014 §3 'ilçe geneli çok az' ile)?"

## Gerekli değişiklikler (birleştirmeden önce)

1. Golden yorumlarını düzelt (`tests/sim/m2_query_test.gd:13-17`, `golden_expropriation_undo_test.gd:19-22`,
   `golden_x_council_trust_test.gd:12-14`, `production/bugs/B-130.md` GOLDEN bölümü): hash değişiminin ikinci nedeni
   `systems.actors.config_digest` (dosyanın tamamı, `_notes` dahil). "B'de yalnız eşik alanı değişti" ifadesi kaldırılsın.
   Yalnız yorum; hash değişmez.
2. GOLDEN_X için durum farkı çıkarılsın (eski eşik/eski dosya vs yeni: `systems` ve ReasonLog anahtar farkı;
   `group.reacted` / medya / hafıza farkı var mı) ve B-130'a yazılsın. Fark yalnız bloc.react kararlarının doğal
   sonuçlarıysa onay geçerlidir; başka sistemde (ekonomi, yol işleri) fark çıkarsa yeniden inceleme.
3. `golden_x_council_trust_test.gd`'deki koşulsuz `print("GOLDEN_X_RULE_OFF_CANDIDATE=...")` kaldırılsın (aday değer
   zaten hata mesajında); her koşuda gürültü.

## Takip önerileri (engel değil)

- `actor_evaluate_test` vakaları eşiği tablodan okuyup göreli kursun (`cfg.table("bloc.react")["tiers"]`); bir sonraki
  ayar bu testi yine kırmasın.
- `bloc_reaction_test` uzun koşu: sayı sınırı yerine yapısal iddia (tetik değişimi ya da >= recheck_days).
- Taban sürüklenmesi: bloc.2 tabanı 360 günde 167 (eşiğe 23). 720 günlük bilgi amaçlı ölçüm; gerekirse şikâyetin
  karara atfedilen kısmı (tasarım işi, systems-designer).
- `verify full` bu dal üzerinde koşulmalı (benim tarafımdan koşulmadı).

## Doğrulanmış / varsayılan / test edilmemiş

- Doğrulandı (okuyarak): src/sim farkının kapsamı; eşiğin veriden okunması; digest'in durumda ve hash'te olması;
  kesim başına eşik yolunun olmaması; reactions.json'un digest dışı ve kamulaştırmaya bağlı olması; test uyarlamalarının
  içeriği ve sessiz vaka aritmetiği; ana dalda eski golden değerlerinin eski değerlere eşit olması.
- Varsayıldı: eski hash'lerin eşik 250 ile bire bir yeniden üretildiği; A'daki +1 kaydın protest basamağı olduğu
  (mekanizma kodla tutarlı); X farkının aynı nedenden geldiği; ajanın ölçüm sayıları (B-130).
- Test edilmedi: hiçbir test ya da Godot koşusu (kilit başka ajanlarda).
