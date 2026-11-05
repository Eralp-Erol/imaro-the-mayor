# 2026-11-05 · Teknik direktör incelemesi · Yıkım -> meclis güveni (D-021), commit 9af52eb

**Karar: DÜZELTMELERLE ONAY.** GOLDEN_X yenilemesi: **EVET, koşullu** (aşağıda).
Kapsam: salt okuma. `git show 9af52eb`, `src/sim/politics/council_trust.gd`, `reaction_config.gd`, `politics_state.gd`, `council_engine.gd:231-240`, `politics_query.gd:47-53`, `event_sources.gd:143-160`, `reaction_rehousing.gd`, `game_state.gd` (hash), `state_hash.gd`, `sim_save.gd`, iki yeni test dosyası, GOLDEN_X testi, ADR-0009 §P3, D-021, B-080/B-081. **Godot çalıştırılmadı; hiçbir test sonucu doğrulanmadı.** Hash değerleri ve ölçüm tablosu uygulayıcının raporundan (varsayılan).

## 1. TEK-01/02 ve sim değişmezleri
Doğrulanmış (kod okundu):
- Saf: `RefCounted`, statik; Node/Time/OS/rastgelelik yok. Haftalık tarama `PoliticsSystem.on_daily` içinde sabit noktada (`ReactionAgenda.scan` sonrası), `delta` yok.
- Tam sayı: tüm aritmetik int, tamsayı bölme (`council_trust.gd:182,191,197`); kalıcı durumda float yok. Kayıt `var_to_bytes` (JSON değil), int korunur.
- Sıra: bölge kodları ve komut kimlikleri sıralı dolaşılıyor (`:171-172,185-186`), üyeler sıralı (`:214`). `StateHash` sözlük anahtarlarını kanonik sıralar; ekleme sırası hash'i etkilemez.
- Yeni durum `state.systems.politics.council_trust` altında: `to_dict`/`state_hash`'e otomatik girer; yüklemede `PoliticsState._council_trust_problem` doğrular. Testler: aynı tohum aynı hash, tick parçalama bağımsızlığı, ortada kayıt/yükleme, bozuk kayıt reddi (`council_trust_test.gd:261-309`).
- Veri odaklı: sayılar `reactions.json` `council_trust`; kodda yalnız `SCALE`, `REASON_THRESHOLD` (yapısal).
- SIM-12: her değişiklikte üye adına neden kaydı, özne = yol komutu. CAN-03: yalnız güven girdisi değişir; test var (`:312`).
- "İlk etkide yaratılır": eşik altı/yıkımsız koşuda durum yazılmıyor, A/B hash'i korunur; testli (`:57-82`).

Bulgular:
- **F1 (orta, düzelt):** donmuş kesinti. `scan` kural kapalıysa erken döner (`council_trust.gd:125`) ve yalnız *şu anki* etkilenen üyeleri dolaşır (`:136`). Kesinti tablosu varken (a) veride `enabled:false` yapılırsa ya da (b) `cohorts` listesi değişip bir üye kapsam dışına çıkarsa, o üyenin kesintisi **sonsuza dek** kalır ve `effective_trust` ile oya binmeye devam eder. `reactions.json` digest dışında olduğu için eski kayıt yeni veriyle sessizce yüklenir; bu senaryo gerçekçi (ayar değişikliği). Düzeltme: tabloda olup etkilenen kümede olmayan üyeler için hedef = 0 ile aynı toparlanma adımını uygula; kapalıyken durum varsa da toparlanma (ya da `penalty()` kapalıyken 0) çalışsın. Kural kapalı + durum yokken hash değişmemeli (A/B/X kapalı referansı korunur). Test: kesintili kaydı `enabled:false` ve `cohorts` değişmiş veriyle yükle, kesintinin pencere içinde 0'a indiğini doğrula.
- **F2 (düşük):** `test_unchanged_weeks_write_no_new_records` (`council_trust_test.gd:249-256`) `<= n + 9` iddia ediyor; değişmeyen haftalarda 9 yeni kayıt olsa da geçer, yani adının koruduğu davranış için düşemez. `is_equal(n)` olmalı (fikstürde hedef 15 hanede sabit kalır; varsayılan, koşulmadı).
- **F3 (düşük):** kod varsayılanı (`reaction_config.gd:351-353`: drop 4, cap 150) gönderilen veriden (5, 200) farklı. Kapalı olduğu için davranış etkisi yok ama iki "çalışma değeri" kafa karıştırır; aynı yapın.
- Gizli determinizm riski: bulunmadı. Neden kaydı kimlikleri global sayaçtan aldığı için sonraki bütçe `reason_id`leri kayar; bu deterministik ve beklenen.

## 2. GOLDEN_X yenilemesi: EVET, koşullu
Gerekçe: `golden_x_council_trust_test.gd` kural kapalıyken aynı senaryonun eski `c987fb3d…4094`ü bit-bit verdiğini iddia ediyor. Bu, değişikliğin tek nedeninin kural olduğunun doğru kanıtı (kapalı yol = eski kod yolu). Açık haldeki davranışın doğruluğu ayrıca `council_trust_test.gd` ile kilitli. ADR-0009 §P3 kuralına uyuyor (çalışma değeri/kural bilinçli değişti, gerekçeli, ayrı commit).
Koşullar:
1. Aday hash elle kopyalanmaz: Godot kilidi boşken testi koşan kişi `GOLDEN_X_CANDIDATE=` çıktısını alır; `1914f0e1…bb0d` ile aynı olmalı. Aynı dosyadaki "iki koşu aynı hash" ve "tick 30 kayıt/yükleme" testleri yeni sabitle yeşil olmalı.
2. **Ayrı commit**, yalnız sabit satırı (+ başlık yorumuna bir satır "D-021 ile yenilendi"): `tests/sim/public_works/golden_expropriation_undo_test.gd:13`
   `const GOLDEN_X := "1914f0e131fb087426f0e733162ec7f3b1dfc73a1c2aeb555c268cd37c3abb0d"`
3. F1 düzeltmesi GOLDEN_X'i değiştirmemeli (senaryoda kural hep açık, üye kümesi sabit). Değiştirirse yenileme F1'den sonra tekrar alınır; sırayı F1 -> yenileme yapın ki tek yenileme olsun.
4. Önerilen (engel değil): açık/kapalı karşılaştırmasını `economy`, `public_works` ve bütçe defteriyle sınırlı bırakmayın; `actors`, `policy` ve `politics` (`council_trust` ve `counters.reason_records` çıkarılmış) da eşit olsun. Şu anki test adı "yalnız kesinti durumundan" diyor ama bunu tam kanıtlamıyor.
Komut (kilit boşken, yalnız kendi PID'iniz):
`tools/godot.sh --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/sim/public_works -a res://tests/sim/politics/council_trust_test.gd -c --ignoreHeadlessMode`
Ardından `tools/verify.sh quick`; dal teslim edilmeden önce `full` (bu dal şu an bilerek kırmızı, kırmızıyla `git-wt done` yapılmaz).

## 3. Mimari (durum yeri, digest dışı veri)
- `politics.council_trust` altında, ilişki kaydından ayrı bir tablo: doğru seçim. Tavan/toparlanma tek yerde, A/B korunuyor, kural kaldırılabilir. Tek okuma noktası `effective_trust`: iyi.
- Digest dışı veri: T-042b emsaliyle tutarlı ve A/B'yi korumak için gerekli. Bedeli: eski kayıt yeni ayarla sessizce yüklenir. Kesinti kalıcı durumda saklandığı için bir sonraki taramada yeni hedefe yakınsar (yükselme hemen, düşme tarama başına `recover_per_scan_pm`): kabul edilebilir. İstisna F1'deki donma durumu; düzeltilince yan etki kalmaz.
- Okuyucu tutarlılığı (B-080): "üyenin oyuncuya güveni" artık iki değer taşıyor. Oy ve görünüm kesintili okuyor, `event_sources.gd:156` (`council.trust_gap`) ham ilişkiyi okuyor. Tek doğru kaynak ilkesi açısından teknik tercihim (B): orada da `effective_trust` okunsun. Ama bu PE-03 olay sıklığını değiştiren bir oynanış sonucu, sahibe sorulmalı. Şimdilik engel değil.
- Kapsam notu (bilgi): kesinti `member_factors` üzerinden **tüm** meclis oylarına biniyor, bütçe oyları dahil (`council_engine.gd:141,344`). Kart yalnız imardan söz ediyordu. Güven genel bir kavram olduğu için savunulabilir, ama sahibe bir satırla söylenmeli.

## 4. Eksik/aşırı, ayar düzeyi
- "Reddedilmeye yaklaşır" kartın kelimesi kelimesine karşılığı: marj düşüyor, sonuç değişmiyor (96x2 koşuda KABUL sayısı aynı; varsayılan, ölçülmedi). Teknik olarak sadık. **Ürün riski:** STATE'e göre gerçek oyunda meclis RED'i hiç üretilemedi (81 oylama hep kabul). 200 pm ile sahip demoda yıkımın meclise etkisini hiç **görmeyecek**. Koltuk farkı (40 koltukta 29->24) ancak panel bağlanırsa (B-081) görünür. Kart önerisi: "Hafif (şimdiki): marj düşer, ret yok" / "Sert: cap 400, drop 10; en sert yıkımda yeşil imar 8 denemenin 4-5'inde reddedilir". Sayı veride, kod değişmez.
- B-081 (neden paneli) sim birleşmesini engellemez, ama "özellik tamamlandı" ya da sahibe demo için gerekli: CLAUDE.md nedenselliğin görünmesini istiyor. Eklenen 5 Türkçe metin yer tutucu; ui-engineer gözden geçirmeli.
- B-080: yukarıda; sahibe soru.
- Aşırı iş yok; probe değişikliği yalnız okuma yapıyor.

## Takip
1. simulation-engineer: F1 (+test), F2, F3. Sonra ayrı commit'te GOLDEN_X yenilemesi (koşul 1-3), sonra `verify quick`/`full`.
2. Studio Director: `production/QUESTIONS.md` kartları: ayar düzeyi (hafif/sert), B-080 (PE-03 kesintiyi okusun mu), bütçe oylarının da etkilenmesi (bilgi).
3. ui-engineer: B-081 panel bağı (üyenin son `decision.council.displacement_trust` kaydı).
