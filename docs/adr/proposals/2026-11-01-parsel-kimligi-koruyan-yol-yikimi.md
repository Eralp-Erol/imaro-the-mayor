# ÖNERİ · Parsel kimliğini koruyan yol yıkımı (kamulaştırmalı yol da yıkılabilsin)

- Durum: **KABUL -> ADR-0005 Ek J** (technical-director, 2026-11-01; seçenek A uygulandı `29a2427`). Bağlayıcı metin ve açık kenar durumları (çok parçalı çıkmaz yol, yüklemede yıkım parsel denetimi, `world_network.gd` bölme) Ek J'dedir; bu belge ölçüm/gerekçe kaydı olarak kalır.
- Tarih: 2026-11-01 · Yazan: world-engineer · Taban: `c44d414`
- Karşıladığı gereksinimler: WLD-01 / TEK-03 (tek dünya), TEK-01 / TEK-02 (determinizm, kayıt), CAN-03 (bina doğmaz), CAN-04 (yol çizen oyuncu), D-014 §1 ("yolu yıkma seçeneği hep olsun, maliyeti olsun"), T-042b seçenek A (sim parsel kümesi SABİT)
- Girdi: `src/world/network/world_network.gd`, `network_expropriation.gd`, `network_block_match.gd`, `network_op_journal.gd`, `src/sim/public_works/demolition_plan.gd`, `public_work_demolish_handler.gd`, `tests/sim/public_works/undo_demolish_real_world_test.gd`, ADR-0005 Ek E/F, ADR-0009 §6.

## Düz dille özet

- **Sorun:** Kullanıcı "yolu yıkma seçeneği hep olsun" dedi (D-014 §1). Bugün evlerden parsel alan (kamulaştırmalı) yol yıkılamıyor; oyun "Bu yol yıkılırsa çevredeki arsaların sınırı değişirdi" diyor (`public_work.reject.demolition_changes_parcels`). Söze tam uymuyor.
- **Neden:** Yol silinince dünya, birleşen bloğu baştan parsellere böldü: eski parseller silindi, aynı şekilli ama YENİ numaralı parseller doğdu. Simülasyon parsel numaralarını sabit tutar (sahiplik, hane, bina bu numaralara bağlı); yeni numaralar simülasyonda yok. Oyun bu yüzden yıkımı reddediyordu.
- **Çözüm (küçük, uygulandı):** Yol silinince dünya YENİ parsel üretmez; yolun kestiği blokların kalan (alınmamış) parselleri aynı numara, aynı şekil ve aynı sahiplikle birleşen yeni bloğa taşınır. Kamulaştırmada zaten böyle çalışıyordu (yol eklerken); yıkımda da aynı yol kullanılıyor. Kod değişikliği iki satır, sim'e dokunulmadı.
- **Yolun yerinde ne kalır:** Yolun kamulaştırdığı parseller geri DÖNMEZ (bina geri gelmez, D-014 §1 ruhu ve bugünkü işleyiş). O arsalar dünyada "parselsiz boş zemin" olarak kalır, simülasyonda "alınmış" durumda durur. Bu bugünkü kamulaştırılmış arsalarla aynı görünüm; ama "orası ne olsun" ürün sorusudur: `production/QUESTIONS.md` Q-031 (UYDURULMADI).

## 1. Ölçüm: parsel yeniden üretimi ne yapıyor? (çalıştırıldı, gerçek ağ kodu)

Sentetik test dünyası (`PublicWorksSupport.network()`): 15 parselli blok, 228 parsel. Blok 1'i köşegen kesen kamulaştırmalı yol:

| Adım | Eski kod | Yeni kod |
|---|---|---|
| Yol eklenir | 13 parsel alınır (1-5, 9-13, 22, 62, 78); yeni parsel YOK; blok 1 -> 16 ve 17 olur; kalan 5 parsel (6, 7, 8, 14, 15) kimliğiyle taşınır | aynı |
| Tek kenar silinir (yıkım) | 15 YENİ parsel (229-243) doğar, 5 eski parsel (6, 7, 8, 14, 15) silinir -> `demolition_changes_parcels` reddi | 0 yeni, 0 silinen; 6, 7, 8, 14, 15 aynı nesne, aynı kimlik |
| Alınan parseller | yok (zaten emekli) | yok (geri gelmez) |
| Parsel kimlik sayacı | 229'a ilerler | ilerlemez |

Kök neden (kod): `WorldNetwork.refresh_blocks` / `NetworkLocalRefresh.refresh` yalnız kamulaştırmalı EKLEMEDE "havuzlu yeniden kurma" (`NetworkExpropriation.rebuild`) kullanıyordu: eşleşmeyen eski blokların parselleri havuza girer, yeni yüzler parselleri merkez noktasına göre kimlikleriyle alır. Diğer her işlemde (yıkım dahil) eşleşmeyen eski blok parselleriyle birlikte silinir (`_remove_block`) ve yeni yüz `_build_block` içinde `_parcelize_block` ile baştan bölünür. Bölme tohumu bloğun imzasından türediği için şekiller aynı çıkar; yalnız numaralar yenidir.

Neyin değiştiği (eski kod, yıkımda): kimlikler (yeni), sınırlar (aynı şekil, çünkü tohum imzadan), sahiplik (`owner_id` boş yuva; sim zaten kendi sütunlarında tutar, kaybolacak şey yok ama numara kaymasıyla eşleşme kopar), binalar (T0 bina sütunları parsel numarasına bağlı; yeni numaralarda bina yok), alınmış parseller (zaten emekli; yeni üretim onları "boş yer" olarak yeniden parsellerdi: alınan arazi satılabilir arsa gibi geri doğardı, bu sim'de karşılığı olmayan parsel olurdu).

## 2. Seçenekler

| | Ne yapar | Artı | Eksi |
|---|---|---|---|
| **A (ÖNERİLEN, uygulandı)** | Yıkım işlemi de havuzlu yeniden kurmayı kullanır; mühürden sonra hiçbir yüz baştan parsellenmez (`keep_parcels` açıkken) | İki satır; sim, kayıt biçimi, GOLDEN değişmez; determinizm aynı mekanizma (yeniden oynatma bit-eşit); geri al/yık zinciri mevcut günlükle çalışır | Alınmış parseller dünyaya dönmez (bilinçli); bağlantı koparan yıkımda (aşağıda §5) güvenli ret kalır |
| B | Alınan parselleri de kimlikleriyle dünyaya geri koy | Yolun yeri "eski parseller" olur | Görünüm "parsel dünyada yok = alınmış, bina gizli" kuralıyla çalışıyor (`playable_expropriation.gd`); geri koyunca binalar GERİ gelir (D-014 §1'e ters) -> görünümün `development == taken` ile gizlemeye geçmesi gerekir (godot-engineer işi, daha büyük) |
| C | Yeni parsel üret, sim'e yeni numara ekle | Boş arsa yeniden satılabilir | Sim parsel kümesi SABİT kuralı kırılır (T-042b A); ekonomi sütunları büyür; kayıt biçimi ve GOLDEN etkilenir; büyük iş, ürün kararı ister |
| D | Reddi sürdür (bugün) | Hiç iş yok | Kullanıcının "hep olsun" sözüne aykırı |

## 3. Teknik tasarım (A)

Değişiklik (iki yer):

1. `src/world/network/network_expropriation.gd` · `active(net)`: `keep_parcels_on_delta` açıkken `remove_edge` işlemi de "havuzlu" sayılır. Böylece tam (`refresh_blocks`) ve yerel (`NetworkLocalRefresh`) yenileme yıkımda da `NetworkExpropriation.rebuild` kullanır: eşleşmeyen eski blokların parselleri havuza girer; yeni yüz, merkezi içinde kalan parselleri kimlikleriyle alır; cephe kenarı yeniden atanır; geri alma günlüğü (`parcels_moved`) mevcut kodla yazılır.
2. `src/world/network/world_network.gd` · `_build_block`: koşul `keep_parcels_on_delta ve yüzde delta kenarı var` iken `keep_parcels_on_delta ve mühürlü` oldu (satır sayısı aynı: 995). Gerekçe: mühür sonrası "delta kenarı olmayan yeni yüz" yalnız yıkımın birleştirdiği yüzdür; onu baştan parsellemek yeni numara üretirdi. `NetworkBlockMatch.has_delta_edge` artık kullanılmadığı için silindi.

Sim tarafı değişmez: `DemolitionPlan.run` zaten "yeni/silinen parsel varsa başarısız" der; artık bu güvenlik ağı yalnız gerçekten parsel değişirse devreye girer.

Kimlik/determinizm/kayıt:
- Parsel kümesi (kimlik olarak) sim kümesinin her zaman ALT kümesidir; yeni kimlik asla doğmaz (`added_parcels` boş, sayaç ilerlemez). Sim kümesi sabit kuralı (T-042b A) bozulmaz.
- Yeniden oynatma: kayıt = tohum + delta (add_road + remove_edge sırası). Sonuç yalnız geometri, işlem ve eski kümeden türer; kimlik sırası havuz sırasındandır (artan blok kimliği, blok içi sıra). `PublicWorksContext._move_to` her işlemden sonra yalnız graf özetini karşılaştırır; parsel özeti kayıtta yok ve eklenmedi.
- **`SimSave.VERSION` 2 KALIR**, taşıma kodu yok: kayıt biçimi aynı. Yeni davranış yalnız eskiden reddedilen bir komutu kabul eder; eski kayıtlarda böyle bir yıkım olamaz.
- **GOLDEN_A/B** yol/kamulaştırma çalıştırmaz (etkilenmez). **GOLDEN_X** (`golden_expropriation_undo_test.gd`) yıkım dalı yalnız düz yoldur; değişiklik sonrası test geçti, sabit değişmedi.
- Satır sınırı: `world_network.gd` 995 (değişmedi), `economy_system.gd` dokunulmadı.

## 4. Risk

- **Orta-düşük:** `_build_block` koşulu mühür sonrası tüm yeni yüzleri etkiler. `keep_parcels` kapalı dünyada (aşama 2) hiçbir şey değişmez. `keep_parcels` açıkken mühür sonrası yeni yüz yalnız yol çevirme ya da yıkım birleştirmesinden doğar; ilki zaten delta kenarı taşıdığı için eskiden de parsellenmiyordu. Prototip koşusunda dünya ağı testleri (171) geçti; sim yol testlerinde yalnız eski reddi doğrulayan 3 test kırıldı (beklenen).
- **Görünüm:** `playable_expropriation.gd` blok değişiminde yer zeminini yeniler (`blocks_moved`); yıkımda blok değişimi var. Sahne içinde gerçek görüntüyle DOĞRULANMADI.
- **Bağlantı koparan yıkım:** kenar silme ağı iki bileşene bölerse birleşen yüz "deliklidir" ve havuz o yüze parsel vermez (`_claim` deliklileri atlar). O durumda parseller silinir -> `DemolitionPlan` yine `demolition_changes_parcels` der ve ağı geri alır (güvenli ret, durum değişmez). Denenen iki yol bu duruma düşmedi; kasıtlı bir test yok (UNVERIFIED sınırı). Gerekirse deliklileri destekleyen ayrı bir iş.
- **Süre:** gerçek Ismeral ağında yıkım süresi ÖLÇÜLMEDİ. Yeniden kurma, kamulaştırmalı eklemeyle aynı kodu kullanır ve yıkımın kuru koşusu (`_dry_run`) bellekte tutulur; yine de ölçülmeli.

## 5. Test planı ve sonuç (koşuldu)

Kırmızıdan yeşile: yeni dünya testi düzeltme geri alınınca 5 testin 4'ü kırmızı (özellik testleri; 5.'si eski davranış güvenlik ağı testi, iki durumda da yeşil), düzeltmeyle 5/5 yeşil.

- `tests/world/network/network_demolition_parcels_test.gd` (yeni): (1) köşegen/kesen kamulaştırmalı yol yıkılır: kalan parseller AYNI nesne, yeni kimlik yok, kayıp yok, kimlik sayacı ilerlemez, graf özeti taban, alınanlar geri dönmez, `NetworkInvariants` boş; (2) yıkım + geri alma zinciri yol sonrasına ve tabana bit-eşit (`state_hash`), kayıttan yeniden oynatma bit-eşit; (3) yerel yenileme == tam yenileme (iki yol, yıkım); (4) `keep_parcels` kapalı dünyada yıkım hâlâ yeniden parseller ve `DemolitionPlan` güvenlik ağı reddeder; (5) 300 tohumlu rastgele yol özelliği: 209 uygulanabilir yol (195'i blok bölen) yıkıldı, parsel kümesi değişmedi, tamamı geri alınınca tabana bit-eşit.
- `tests/sim/public_works/undo_demolish_real_world_test.gd`: eski "reddedilir" testi yerine gerçek köprüyle yıkım kabul + kimlik koruması + bütçe + geri al penceresi kapanır; kayıt/yükleme + 40 tick sonrası hash eşit.
- `demolish_test.gd` ve `resettlement_undo_test.gd`: eski ret testleri yeni doğruya göre yenilendi (sahte dünya ikizinde yıkım kabul; yıkım tahsisi geri ALMAZ, ADR-0009 §6 artık tetiklenebilir ve doğrulanıyor).
- Dokunulmayanlar geçti: `tests/world/network` (171), `tests/sim/public_works` (188, GOLDEN_X dahil).

Yapılmadı: gerçek Ismeral ağında yıkım süresi ölçümü; `playable.tscn --demo` ile görünür doğrulama (yıkım sonrası zemin yenilemesi, ağaçların alınmış arsada gizli kalması); bağlantı koparan yıkım için kasıtlı test; `verify full`.

## 6. Tahmini iş ve sahip

- A: yarım gün, **world-engineer** (yapıldı; testler dahil). Director incelemesi: `technical-director` (ADR eki olup olmayacağı).
- Boş arsanın ne olacağı kararı gelince (Q-031): A seçilirse iş yok; B (yeşil/park) -> `godot-engineer` + `technical-artist` (zemin boyası), CAN-04'e göre park oyuncu işidir, otomatik değil; C (yeniden imar) -> `simulation-engineer` + `world-engineer`, büyük iş.
