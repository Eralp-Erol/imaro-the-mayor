# Tick maliyeti: yol onay tick'i ve ay sınırı (gerçek Ismeral, 40 493 parsel) · 2026-10-31

Kaynak bulgu: `production/log/2026-10-31-T-043B-gercek-dunya-olcumu.md`. Commit yok. `src/view/**` ve `src/game/playable.gd` değişmedi.
Ölçüm: aynı probe (`tests/sim/perf/t043b_real_world_probe.gd`, `--queue=1 --order=road_first --profile`), aynı makine (i7-8850H, başsız), duvar saati;
makineye bağlıdır, kabul kararı değildir.

## Sonuç (öncesi -> sonrası, ms)

| Metrik | Önce | Sonra | Hedef |
|---|---|---|---|
| Yol onay tick'i, rank 0 (108 m) | 68,5 (`commands` 66,1) | **23,6** (`commands` 21,4) | <= 25 ULAŞILDI |
| Yol onay tick'i, rank 1 (248 m) | 84,8 (`commands` 82,7) | **12,5** (`commands` 10,4) | <= 25 ULAŞILDI |
| `submit_command` (yol), rank 0 / rank 1 | 9,8 / 29,5 | 4,9 / 14,7 | (hedef yok) |
| `economy.monthly` (en kötü) | 24,2 - 24,7 | **3,8** | |
| Ay sınırı tick'i (tümü) | 24 - 28 | **<= 8,2** (en yavaş 8 listesindeki ay tick'leri: 180 -> 7,4; 210 -> 8,2) | <= 16 ULAŞILDI |
| `graph_hash()` (tek çağrı, gerçek ağ) | 30,7 - 33,6 | 3,5 - 3,8 | |
| 16,6 ms'yi aşan tick (rank 0, 292 tick) | 11 (steady 10) | 2 (ilk tick + yol tick'i) | |
| Ortalama tick (rank 0) | 4,04 | 3,24 | |
| İlk tick (tek seferlik) | 106 - 121 | 109 - 119 | DEĞİŞMEDİ (bkz. kalanlar) |

Sim sonucu AYNI: rank 0 son durum hash'i `04fc00b292e2664ff24bd7604a15e23686174bf9d390311d796d5c7b89907c94` öncesinde de sonrasında da;
rank 1 `d0c04ba022deff218747b3d6ac19d4b930524cab52c5a2fa3e5533a30d4a9605` öncesinde (HEAD dosyalarıyla ayrı koşu) de sonrasında da.

## Kök neden (profille doğrulandı)

Yol tick'i (rank 0, parçalar ayrı ölçüldü; `tmp` betikleriyle, aynı gerçek ağ):
- `WorldNetwork.graph_hash()` ~31 ms: `NetworkColumns.edges` 18,5 + `nodes` 8,6 + SHA 2,8. Her yolda baştan, 4 267 düğüm / 7 366 kenarın tamamı.
- `RoadDraftCheck.check` 4,6 ms (rank 1: 14 ms) ve tick'te ÜÇ KEZ koşuyordu: `validate` -> `_problem` -> `draft`, `apply_with_id` -> `draft`, `RoadDraftCheck.apply` -> `check`.
- `net.add_road` ~18 ms; bunun 16,6 ms'si `NetworkLocalRefresh` -> `NetworkBlocks.extract_local` (dış yüz yürüyüşü: 1 030 yarım kenar, 949 düğümün dönüş sırası `_rotation_of` ile hesaplanıyor, ~13 ms). Rank 1'de 3 ms.
- Toplam ≈ 31 + 3 x 4,6 + 18+ = 68. T-043B'deki varsayım ("graph_hash ~33 ms") doğrulandı; ek olarak üçlü denetim bulundu.
- `component` önbelleği (`_component_info`) her ağ değişiminden sonra bir sonraki denetimde 33 ms ile yeniden kuruluyor (4 267 düğüm); yol tick'inde DEĞİL, ardışık ikinci yolun gönderiminde (aşağıda kalanlar).

Ay sınırı (probe araçlandırması, geçici): `economy.monthly` = `_update_land_values` 19 - 20,6 ms + `_collect_rents` 3,6 - 5,7 ms + diğerleri < 0,2. Arsa değeri döngüsü 40 k parselin tamamını geziyor,
oysa plansız modda (`unplanned_land_enabled` = 1, oynanabilir veri) görülen imarı olmayan parselin imarı "" ve "" imarın izinli kullanımı yok (talep -1 = yapılanmaya kapalı) ⇒ hepsi `continue`.

## Değişiklikler

1. **graph_hash artımlı (bit-bit aynı değer).** Yeni `src/world/network/network_hash_cache.gd` (`NetworkHashCache`): düğüm/kenar sütunları kimliğe göre sıralı paralel diziler
   (kimlik, float64 kayıtlar, metin). Mühürden sonra her düğüm/kenar değişimi kirli işaretlenir; hash isteğinde yalnız kirli kimlikler yerinde güncellenir (sona ekleme, ortaya ekleme/silme dilimle),
   kirli yoksa o sütunun SHA-256'sı önbellekten gelir. Bayt akışı `NetworkColumns.nodes/edges` ile aynı (aynı float64 kayıt sırası, aynı `",".join(metin)`), SHA aynı. Mühürden önce önbellek yok ⇒ tam hesap.
   - `world_network.gd`: `_touch(kind, id)` (yeni isteğe bağlı argümanlar; `graph_version` davranışı aynı), `_hash_cache`, `seal_base` önbelleği kurar, `graph_hash()` artımlı, `graph_hash_full()` önbelleksiz referans.
     Dosya 1000 satır sınırında (gdlint `max-file-lines`); yeni mantık ayrı dosyada.
   - `network_columns.gd`: `graph_hash_full(net)` (eski hesap, referans).
   - `network_restore.gd`: geri alma yardımcıları (`drop_/reinstate_node/edge`) kirli işaretler (`graph_version` artırmaz).
   - Bulgu (fuzz testi yakaladı): `_cleanup_node` kenar birleştirmede `e1.a/b`yi doğrudan yazıyor; o noktaya da işaret eklendi (`NetworkHashCache.mark_on`, `graph_version` artmaz).
   - Kural/uyarı: mühürlü ağda düğüm/kenar alanını `WorldNetwork` API'si ve geri alma dışında doğrudan yazan kod önbelleği bayatlatır. Şu an `src`'de böyle bir yazım yok (taramayla doğrulandı: yalnız üreteç, mühürden önce).
2. **Yol denetimi tick'te bir kez.** `PublicWorksContext.draft` son sonucu (graph_version + noktalar + sınıf) önbelleğe alır, ağ değişince geçersiz (eski cevap verilmez), "meşgul" cevabı önbelleğe girmez, dönüş sığ kopya.
   `RoadDraftCheck.apply_checked(net, checked, road_class, rules)` eklendi (`apply` = `check` + `apply_checked`); `PublicWorkRoadHandler.apply_with_id` ikinci denetimi atlar.
3. **Arsa değeri taraması.** `EconomySystem._update_land_values`: `_unplanned_on` ve "" imarın bölge talepleri hepsi < 0 ise yalnız `zone_seen` parsellerini gezer (parsel başına bağımsız güncelleme ⇒ sıra önemsiz, sonuç tam taramayla aynı).
   Koşul çalışma anında hesaplanır (varsayım değil). Bayrak kapalıyken (varsayılan, GOLDEN) tam tarama aynen sürer. Dosya 1000 satır (sınırda).

Değişen dosyalar: `src/world/network/{world_network,network_columns,network_restore,road_draft_check}.gd`, yeni `src/world/network/network_hash_cache.gd`,
`src/sim/public_works/{public_works_context,public_work_road_handler}.gd`, `src/sim/economy/economy_system.gd`.
Yeni testler: `tests/world/network/network_hash_cache_test.gd`, `tests/sim/public_works/public_works_draft_memo_test.gd`, `tests/sim/economy/economy_land_values_unplanned_test.gd`.
(`tools/verify-areas.tsv` değişmedi: yeni dizin yok. Yeni `.gd.uid` dosyaları Godot'un ilk içe aktarmasında oluşur; ikisi oluştu: `network_hash_cache.gd.uid`, `network_hash_cache_test.gd.uid`.)

## Doğrulanmış (koşturuldu)

- Eşdeğerlik: `network_hash_cache_test.gd` 7/7 PASS: artımlı == `graph_hash_full()` her adımda (taban, 3 yol, `set_open`, tam LIFO geri alma, sınıf yükseltme dalı, kenar silme + geri alma, 3 tohum x 40 rastgele işlem dizisi
  (yol/geri al/aç-kapa/sil karışık), mühürsüz ağ, KEEP_PARCELS kuralı açık/kapalı) + ESKİ koddan alınmış sabit hash'ler (3x3 ızgara G0..G4, Ismeral taban özeti `f09011ab...3013`).
- Mutasyon: `network_restore.gd` içindeki kenar ya da düğüm işaretleri silinince test KIRMIZI (yakaladı); `_cleanup_node` işareti eksikken fuzz testi KIRMIZI (50 hata) idi ve düzeltildi; önbellekte `graph_version` anahtarı silinince memo testi KIRMIZI.
- `public_works_draft_memo_test.gd` 5/5, `economy_land_values_unplanned_test.gd` 3/3 (hash eski kodla alındı, yeni kodla aynı).
- `tests/sim` (recursive, GOLDEN_A/B `m2_query_test` dahil): 757 test, 0 hata, 0 başarısızlık (3 dk 02 sn).
- `tests/world/network` + `tests/view/roads` + `tests/contracts`: 269 test, 0 hata/başarısızlık.
- `tests/game` + `tests/world/settlement` + `tests/world/topology_map` + `tests/unit` + `tests/app`: 305 test, 0 hata/başarısızlık.
- gdlint (`uvx --from gdtoolkit==4.5.0 gdlint src tests`): temiz. `tools/verify-scope.sh check`: area-map tamam.
- Probe (gerçek Ismeral): tablodaki sayılar; durum hash'leri öncesiyle birebir aynı (rank 0 ve rank 1).

## Varsayılan / test edilmemiş

- Ölçümler yalnız D2, tohum 1467, başsız (dummy renderer): render, `RoadEditSync`, yol görünümü kurulumu, gerçek pencere kare süresi ölçülmedi.
- Rank 0 yol tick'i hâlâ 23,6 ms: kalanı `NetworkLocalRefresh` dış yüz yürüyüşü (~16 ms). Başka yol/bölge (dış sınıra yakın) benzer olabilir; yalnız rank 0/1 ölçüldü. Bütçe (16,6 ms) hâlâ aşılıyor, 60 fps'te ~1,5 karelik tek seferlik takılma.
- Önbelleğin bayatlama güvenceleri: yalnız WorldNetwork API'si ve geri alma yolu işaret eder. Dışarıdan mühürlü ağa doğrudan alan yazan yeni kod olursa hash yanlış çıkar; test (fuzz + eski değer) bunu mevcut işlemler için kapsıyor, gelecek işlemler için DEĞİL (yeni op türü eklenirse işaret şart).
- `verify quick/full` KOŞTURULMADI (kullanıcı koşturacak); yukarıdaki GdUnit kümeleri verify'ın yerini tutmaz. Kayıt/yükleme yolu (`sync_to`, `public_works_save_test`) `tests/sim` içinde geçti; yeni kayıt sürümü yok, kayıt biçimi değişmedi.
- Aylık hızlanma yalnız oynanabilir yapılandırmada (plansız mod) geçerli; sim varsayılanında (bayrak kapalı) tam tarama sürer, orada kazanç YOK (golden korunur).
- `_collect_rents` (3,6 ms, 40 k parsel taraması) dokunulmadı.

## Kalanlar / öneriler

1. **Yol tick'i 16,6 ms altı için:** `NetworkBlocks._rotation_of` sonuçlarını işlemler arası önbelleğe almak (düğüm başına dönüş sırası; komşuluk/konum değişince geçersiz). Dış yüz yürüyüşü ~13 ms'yi neredeyse sıfırlar. world-engineer işi; `world_network.gd` 1000 satır sınırında, mantık ayrı dosyada olmalı. Bu işte yapılmadı: ağ geometri koduna dokunmak "davranış değişimi yok" kanıtı için daha geniş test ister.
2. **Ardışık yol gönderimi:** her ağ değişiminden sonra `_component_info` ~33 ms yeniden kuruluyor (ilk `check` çağrısında, tick dışı ama UI iş parçacığında; ikinci yolun `submit_command`'ı bunu öder). `_component_info`nin PackedArray ile yeniden yazılması ya da yalnız-ekleme için artımlı bileşen (union-find) ölçülmeye değer.
3. **İlk tick (106 - 121 ms):** `--profile` sistem sürelerinde görünmüyor (sistem başına <= 22 ms) ⇒ sim dışı: büyük olasılıkla `SimBuildingProjector`/pump ilk dilimi ya da ilk `_ensure_state`/önbellek kurulumu. Ayrıca ölçülmedi; yükleme ekranına taşınabilir.
4. `_collect_rents` yapılı parsel listesiyle (seyrek) gezilebilir (~3 ms); ayrı küçük iş.

Geçici ölçüm betikleri `tmp/t049/` (git'e girmez), geçici araçlandırma geri alındı (`PROF_` satırı kalmadı, doğrulandı).
