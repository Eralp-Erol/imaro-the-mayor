# Blok çıkarımı önbelleği, bileşen yaması, ilk tick · 2026-10-31

Kaynak: `production/log/2026-10-31-tick-maliyeti-yol-ay.md` ("Kalanlar" 1-3). Commit yok. `src/view/**`, `src/game/playable.gd` değişmedi.
REQ: WLD-01 (tek dünya verisi; çıktı değişmedi), TEK-01/02 (sim saflığı, determinizm). Kanon/D-kararları değişmedi.
Ölçüm: aynı probe (`tests/sim/perf/t043b_real_world_probe.gd --queue=1 --order=road_first --days=260 --profile`), aynı makine, başsız, duvar saati; makineye bağlıdır, kabul kararı değildir.
"Önce" = HEAD (110aa93) `git archive` kopyasında aynı komutla ölçüldü.

## Sonuç (önce -> sonra, ms)

| Metrik | Önce | Sonra | Hedef |
|---|---|---|---|
| Yol onay tick'i, rank 0 (108 m) | 23,78 (`commands` 21,64) | **9,23** (`commands` 6,83) | <= 16 ULAŞILDI |
| Yol onay tick'i, rank 1 (248 m) | 13,20 (`commands` 11,06) | **11,73** (`commands` 9,04) | <= 16 ULAŞILDI |
| 16,6 ms'yi aşan tick (rank 0 / rank 1, 292 tick) | 2 / 1 | **0 / 0** | |
| En yavaş tick (rank 0 / rank 1) | 111,9 / 111,7 (ilk tick) | **9,5 / 11,7** | |
| Ortalama tick (rank 0 / rank 1) | 3,34 / 3,23 | 2,76 / 2,98 | |
| İlk tick (rank 0) | 111,9 | **3,2** | <= 50 ULAŞILDI |
| `net.add_road` (prof, rank 0 / rank 1) | 19,7 / 7,7 | 2,7 / 4,7 | |
| Bileşen sorgusu, yoldan sonra (`components()`) | 33,5 - 34,6 | **0,4** | |
| Bileşen sorgusu, geri almadan sonra | 32,4 | 30 (hâlâ tam hesap, bkz. kalanlar) | |
| `HashCache.build` (mühürde, bir kez; dönüş sırası ısıtma + ilk bileşen dâhil) | (önceden ısıtma yoktu) | 249 | tek seferlik |

Sim sonucu AYNI: rank 0 son durum hash'i `04fc00b2...7c94` önce de sonra da; rank 1 `686b1a8d...483c` önce de sonra da (rank 1 için HEAD kopyasında ayrı ölçüldü;
önceki logdaki rank 1 hash'i `d0c04ba0...` farklı bayraklarla alınmış, bu işte karşılaştırma HEAD ile aynı komutla yapıldı).

## Kök nedenler ve değişiklikler

### 1) Dönüş sırası ve yüz yürüyüşü önbelleği (`NetworkBlocks.extract_local`)
Profil (rank 0): `extract_local` 7,5 ms = dış yüz yürüyüşü 4,7 ms (1 030 yarım kenar) + `_face_from_cycle` 2,2 ms (1 030 köşelik çokgen, sonra alan <= 0 diye atılıyor)
+ 949 düğümün `_rotation_of` hesabı (yürüyüş içinde, her işlemde baştan).
- Yeni `src/world/network/network_rotation_cache.gd` (`NetworkRotationCache`): düğüm başına dönüş sırası, "düğüme varan yarım kenar -> sıradaki yarım kenar" tablosu ve çapraz çarpım tablosu (işaretli alan x2 toplamı için).
  `warm(net)` ile mühürde bir kez dolar. Önbellekli `walk()`: tablodan yürür; çevrimin işaretli alanı < -2 (= -1 m²) ise boş döner, çağıran çokgen kurmadan atlar (özgün kod da alan <= 0 yüzü atıyor; eşik kayan nokta gürültüsünün çok üstünde, bu yüzden çıktı aynı).
- Geçersiz kılma: `NetworkHashCache.mark` (mühürlü ağda her düğüm/kenar değişimi zaten hash için işaretleniyor) artık `rotations.mark`'a da iletir. İşaretler ertelenir, ilk sorguda çözülür:
  kenar işareti -> kenarın ESKİ uçları (hesap anındaki `_ends` kaydı) ve ŞİMDİKİ uçları; düğüm işareti -> düğüm ve şimdiki komşuları. Geçersiz düğümün sırası ve ona varan yarım kenarların tablo kayıtları silinir.
- `NetworkBlocks.extract_local`: mühürlüyse `cache.walk(...)`, değilse eski `_walk`. Tam `extract` ve `refresh_blocks` DEĞİŞMEDİ (önbelleğe dokunmuyor).

### 2) Bağlı bileşen önbelleğini artımlı yama (`components()` / `component_of()`)
- Yeni `src/world/network/network_components.gd` (`NetworkComponents`): `WorldNetwork._component_info` içindeki hesap buraya taşındı (world_network.gd 1000 -> 973 satır).
  Kip başına `{of, list, memo, pe, pn}`; `memo` = kenarın önbellek anındaki (a, b, açık) hâli, `pe/pn` = işaretlenmiş kenar/düğümler.
- Yama yalnız şu koşulda: silinen düğüm yok, kipte kenarını yitiren düğüm yok, kaybolan her AÇIK bağlantı (a, b) değişen kenarların şimdiki hâliyle köprülenmiş (kenar bölme a-n-b, ekleme, sınıf yükseltme). Yeni üyeler/birleşmeler anahtar-DSU ile birleşir, listede yeri en küçük üye kimliğine göre bulunur, yalnız kayan/yeni bileşenlerin `of` indeksleri yazılır. Aksi halde (kapatma, silme, kopma, geri alma ile düğüm silinmesi) TAM hesaba düşer (`rebuilt` sayacı).
- Tam hesap (`build`) kenar-DSU ile yeniden yazıldı (aynı çıktı; eski DFS'ye eşdeğerlik testle doğrulandı); süresi ~33 -> ~30 ms (hâlâ ağır, nadir yollarda).
- `WorldNetwork._touch`: mühürlü + işaretli ise sözlük TEMİZLENMEZ (işaret iletilir, yama sorguda); mühürsüz ya da işaretsiz (`_touch()`, geri alma) ise eskisi gibi temizlenir.
- Mühürde ilk yol denetimi soğuk hesap ödemesin diye `NetworkHashCache.build` içinde yol bileşenleri bir kez hesaplanır.

### 3) İlk tick 109-119 ms nedeni: `EconomySystem._ensure_state` -> `_apply_stock` (107 ms)
Probe `_note` `tick > 1` ile ilk tick'i sistem profilinden BİLEREK dışlıyordu (bu yüzden "görünmüyordu"). Geçici araçlandırma (geri alındı): `economy.daily` = 106 ms, hepsi `_apply_stock`:
~24 300 stoklu parsel için parsel başına `index_of` (bsearch) + 3 sanal stok çağrısı. Diziler 0,7 ms.
- Yeni `src/sim/economy/economy_stock_columns.gd` (`EconomyStockColumns.build`): aynı döngü, stok STATİK (ExistingStockSource sözleşmesi) olduğundan sistem kurulurken (`EconomySystem.create`, tick dışı) bir kez çalışır;
  `_apply_stock` ilk tick'te yalnız kopyalar (+ başlangıç hane talebi döngüsü, bölge sayısı kadar). Çıktı sütunları eski döngüyle birebir (test).
- Maliyet kurulum zamanına kaydı (~0,1 s, probe `setup_ms` gürültü içinde: 28,3 -> 27,7 s ölçüldü, ayrı ölçülmedi).
- `economy_system.gd` 1000 -> 993 satır.

## Değişen dosyalar
Yeni: `src/world/network/network_rotation_cache.gd`, `src/world/network/network_components.gd`, `src/sim/economy/economy_stock_columns.gd` (+ `.gd.uid`'ler).
Değişen: `src/world/network/{world_network,network_hash_cache,network_blocks}.gd`, `src/sim/economy/economy_system.gd`.
Yeni testler: `tests/world/network/network_derived_cache_test.gd` (5), `tests/sim/economy/economy_stock_columns_test.gd` (2).
`tools/verify-areas.tsv`: yeni dizin yok, değişmedi (`tools/verify-scope.sh check`: area-map tamam).

## Doğrulanmış (koşturuldu)
- Eşdeğerlik (`network_derived_cache_test`, 5/5): her adımda (taban; çıkmaz sokak, halka, kenar bölme, ayrık parçayı bağlama, ray; kapat/aç; kenar sil; LIFO geri alma; 4 tohum x 30 rastgele ekle/geri al/aç-kapa/sil karışık, yol + ray sınıfı, ayrık bileşenler, feribot kenarı; KEEP_PARCELS kuralı açık/kapalı; hafif Ismeral ağı 8 yol + geri alma):
  `components()` + `component_of()` (yol ve ray) == eski DFS algoritması (testte kopyası); her düğümün önbellekteki dönüş sırası == taze `_rotation_of`; ardıl yarım kenar ve çapraz çarpım tabloları == taze türetme ve BAYAT KAYIT YOK (tablo boyutu == ferry dışı yarım kenar sayısı);
  önbellekli `extract_local` (tüm kenarlar tohum) == önbelleksiz (imza, noktalar, kenar kimlikleri, sivri uçlar, alan, ilk düğüm). Yama yolu gerçekten koşuyor (`NetworkComponents.patched` artıyor); köprü kenar kapanınca tam hesaba düşüyor ve bileşen ikiye bölünüyor (olumsuz test).
- Kırmızı-yeşil (mutasyon): rotasyon önbelleğinde kenar ESKİ uçlarının geçersiz kılınması silinince test KIRMIZI (script hatası/başarısızlık); bileşen yamasında köprü denetimi kaldırılınca KIRMIZI (84 başarısızlık, köprü testi dahil); `EconomyStockColumns`'ta `units + 1` mutasyonu KIRMIZI. Hepsi geri alınıp yeşil doğrulandı.
- `EconomyStockColumns` == eski döngü (rastgele 500 parsel, 4 bölge; boş stokta hiçbir parsel `built` değil), 2/2.
- Suite'ler (GdUnit, hepsi 0 hata/0 başarısızlık): `tests/world` 402 (blok/parsel/GOLDEN-uyumlu ağ testleri, hash önbellek testi, undo/yerel yenileme dahil), `tests/view/roads` + `tests/contracts` 126, `tests/sim` (recursive, GOLDEN_A/B `m2_query_test` dahil) 759, `tests/game` + `tests/unit` + `tests/app` 165.
- Probe: rank 0 ve rank 1 durum hash'i HEAD ile birebir aynı; yukarıdaki tablo.
- gdlint (`uvx --from gdtoolkit==4.5.0 gdlint src tests`): temiz.

## Varsayılan / test edilmemiş
- `verify quick/full` KOŞTURULMADI (siz koşturacaksınız); GdUnit kümeleri verify'ın yerini tutmaz. Kayıt/yükleme yolu `tests/sim` içinde geçti; kayıt biçimi değişmedi (yeni durum yok; önbellekler türetilmiş).
- Önbellek bayatlama güvencesi hash önbelleğiyle ortak: yalnız `WorldNetwork` API'si ve geri alma yardımcıları `mark` çağırır. Mühürlü ağda düğüm/kenar alanını bunların dışında yazan yeni kod hem hash'i hem dönüş/bileşen önbelleğini bayatlatır. Yeni op türü eklenirse test dizisine eklenmeli.
- Ölçümler yalnız D2, tohum 1467, başsız (dummy renderer), iki aday yol (rank 0/1). Render, `RoadEditSync`, gerçek pencere kare süresi ölçülmedi. Dış sınıra yakın başka yollar (daha uzun dış yüz) denenmedi; dış yüz artık çokgen kurmadan atlandığı için maliyet yarım kenar sayısıyla doğrusal ve çok küçük (~1 µs/adım), ama ölçülmedi.
- Rank 1'de `road_submit_ms` hâlâ ~16 ms (`RoadDraftCheck.check`, UI iş parçacığında gönderimde, tick DEĞİL; rank 0'da 4,9). Dokunulmadı. Gerçek pencerede 60 fps'te tek kare taşması olabilir.
- Geri alma sonrası bileşen önbelleği tam yeniden kuruluyor (~30 ms; yama düğüm silinmesini bilerek reddeder, `_touch()` zaten temizler). Geri alma oyuncu yolunda nadir; ayrıca ölçülmedi.
- Mühür/yükleme süresi ~0,25 s'ye (ısıtma dâhil) çıktı; yükleme ekranı bütçesi için kabul sizde.
- `economy_system.gd` hâlâ 993 satır (sınır 1000): yeni mantık için yer yok, ayrı dosyaya alın.

## Kalanlar / öneriler
1. `RoadDraftCheck.check` (rank 1: ~14 ms, gönderim anında): bileşen yaması artık sıcak; kalan maliyet geometri/kesişim taraması, ayrı profil gerekir.
2. Geri alma için bileşen yaması (silinen düğüm tek-kenarlı uç ise üyelikten çıkarma) ~30 ms'yi sıfırlar; nadir yol olduğu için ertelendi.
3. Mühürdeki 249 ms'nin dağılımı (dönüş ısıtma ~ yarısı) gerekirse lazy ısıtmaya çevrilebilir (ilk yol tick'i 13 ms ödemeyi göze alırsa).

Geçici betikler `tmp/t050/` (git'e girmez), geçici araçlandırma geri alındı (`PROF_` yok, doğrulandı).
